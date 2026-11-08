import Combine
import XCTest
@testable import blindRun

/// #872：会话失效（续期后仍 401）由 `AppState.apiClient` 外面那层统一处理，与发请求的页面无关
/// （OpenSpec `centralize-session-expiry-handling`）。
///
/// 全部从 `AppState(apiClient:)` 注入、经 `appState.apiClient` / 领域 service 发请求 —— 走的就是生产路径。
/// 被测的「调用方」一个都不调 `handleAuthenticatedAPIError`：这正是此前 29 个文件的写法。
@MainActor
final class SessionAwareAPIClientTests: XCTestCase, EmergencySOSTestSupport {

    override func setUp() {
        super.setUp()
        EmergencyAlarm.observerForTesting = { _ in }
        EmergencyHaptics.observerForTesting = { _ in }
    }

    override func tearDown() {
        Self.teardownAlarmObservers()
        super.tearDown()
    }

    // MARK: - 统一处理

    /// 此前不处理 401 的页面（例如积分页）：不在跑步中 → 登出一次、登录页提示一次，调用方仍收到 `.unauthorized`。
    func testUnauthorizedOutsideTheRunLogsOutOnceAndStillReachesTheCaller() async {
        let (appState, transport) = Self.loggedInAppState(role: .volunteer)
        transport.nextError = APIError.unauthorized
        let recorder = SessionEventRecorder(appState)

        let caught = await Self.capture { let _: EmptyResponse = try await appState.apiClient.get("/api/volunteer/points") }

        XCTAssertTrue(Self.isUnauthorized(caught), "调用方要收到同一个错误才能停下：\(String(describing: caught))")
        XCTAssertNil(appState.accessToken, "调用方没调任何东西，会话也要结束")
        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated, "退回登录页")
        XCTAssertEqual(recorder.logouts, 1)
        XCTAssertEqual(recorder.expiryMessages, ["登录已过期，请重新登录。"])
    }

    /// 领域 service 架在 `apiClient` 上，同样经过这一层（后台注册推送 token 走的就是 `auth`）。
    func testDomainServicesGoThroughTheSameHandling() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        transport.nextError = APIError.unauthorized

        _ = await Self.capture { try await appState.auth.registerDeviceToken("device-token") }

        XCTAssertNil(appState.accessToken)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    /// 跑步中任一请求收到 401（例如陪跑员端「让对方手机响」）：进暂缓，会话保留，云端求助同时被拦。
    func testUnauthorizedDuringTheRunDefersInsteadOfLoggingOut() async {
        let (appState, transport) = Self.loggedInAppState(role: .volunteer)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        transport.nextError = APIError.unauthorized

        let caught = await Self.capture { let _: EmptyResponse = try await appState.apiClient.post("/api/orders/42/ring") }

        XCTAssertTrue(Self.isUnauthorized(caught))
        XCTAssertEqual(appState.accessToken, "token-7", "跑步中不清会话")
        XCTAssertTrue(appState.isSessionExpiryDeferred)
        XCTAssertTrue(appState.emergencyCoordinator.blocksCloudSOSForExpiredSession)
        XCTAssertNil(appState.consumeSessionExpirationMessage(), "没有退回登录页")
    }

    /// 首页同时发出的三个请求都 401：只登出一次、只写一次过期提示。
    /// 没有幂等的实现会登出三次、写三次提示（第 2、3 次时订单记录已清空，判据又落到「不在跑步中」）。
    func testConcurrentUnauthorizedLogsOutExactlyOnce() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        transport.nextError = APIError.unauthorized
        let recorder = SessionEventRecorder(appState)
        let client = appState.apiClient

        await withTaskGroup(of: Void.self) { group in
            for path in ["/api/orders/mine", "/api/blind/profile", "/api/emergency-contacts"] {
                group.addTask {
                    let _: EmptyResponse? = try? await client.get(path)
                }
            }
        }

        XCTAssertEqual(transport.requests.count, 3, "前提：三个请求都发出去了")
        XCTAssertNil(appState.accessToken)
        XCTAssertEqual(recorder.logouts, 1, "只登出一次")
        XCTAssertEqual(recorder.expiryMessages, ["登录已过期，请重新登录。"], "只提示一次")
    }

    /// 不需要登录的请求（登录、发验证码）的 401 不是会话失效。
    func testUnauthorizedOnARequestThatNeedsNoLoginLeavesTheSessionAlone() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        transport.nextError = APIError.unauthorized

        let caught = await Self.capture {
            let _: EmptyResponse = try await appState.apiClient.post("/api/auth/verify-code", requiresAuth: false)
        }

        XCTAssertTrue(Self.isUnauthorized(caught), "错误照样交给调用方")
        XCTAssertEqual(appState.accessToken, "token-7")
        XCTAssertFalse(appState.isSessionExpiryDeferred)
        XCTAssertNil(appState.consumeSessionExpirationMessage())
    }

    /// 别的错误不碰会话：只有 `.unauthorized` 才是「续期也救不回来」。
    func testOtherErrorsLeaveTheSessionAlone() async {
        for error in [APIError.missingCredentials, .unknown(statusCode: 500), .networkError(CancellationError())] {
            let (appState, transport) = Self.loggedInAppState(role: .blind)
            transport.nextError = error

            _ = await Self.capture { let _: EmptyResponse = try await appState.apiClient.get("/api/orders/mine") }

            XCTAssertEqual(appState.accessToken, "token-7", "\(error)")
        }
    }

    /// 登出那串请求（解绑推送、登出）的 401 按登出规则收尾，不额外提示登录已过期。
    /// 只断最终状态不够：走了统一处理的实现也是「已登出、提示为空」（`performLocalSessionCleanup` 最后会清提示），
    /// 中途写过一次提示才是区别。
    func testLogoutUnauthorizedNeverWritesAnExpiryMessage() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        transport.nextError = APIError.unauthorized
        let recorder = SessionEventRecorder(appState)

        await appState.logout()

        XCTAssertFalse(appState.isLoggedIn)
        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
        XCTAssertEqual(recorder.expiryMessages, [], "登出不提示「登录已过期」")
        XCTAssertEqual(transport.requests.map(\.path), ["/api/auth/logout"], "前提：登出请求确实发了")
    }

    /// 退出登录进行中，后台另一个请求 401：不抢先清会话、不写提示，由登出流程收尾（security-reviewer M1）。
    func testUnauthorizedWhileLoggingOutLeavesTheCleanupToTheLogout() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        transport.nextError = APIError.unauthorized
        let recorder = SessionEventRecorder(appState)
        appState.logoutState = .inProgress

        _ = await Self.capture { let _: EmptyResponse = try await appState.apiClient.get("/api/orders/mine") }

        XCTAssertEqual(appState.accessToken, "token-7", "凭据留给登出流程记补撤")
        XCTAssertEqual(recorder.expiryMessages, [])
    }

    // MARK: - 出口形状

    func testEveryExitIsWrappedExactlyOnceAndLogoutGetsTheRawClient() {
        let (appState, transport) = Self.loggedInAppState(role: .blind)

        let wrapped = appState.apiClient
        XCTAssertTrue(wrapped is SessionAwareAPIClient, "单测注入的客户端同样包上")
        let inner = (wrapped as? SessionAwareAPIClient).map { $0.base as AnyObject }
        XCTAssertTrue(inner === transport, "只包一层")
        let rewrapped = SessionAwareAPIClient.wrapping(wrapped, onSessionEnded: {})
        XCTAssertTrue((rewrapped as AnyObject) === (wrapped as AnyObject), "已包过的不再包")
        XCTAssertTrue((appState.sessionUnawareAPIClient as AnyObject) === transport, "登出用未包的那个")

        let mockState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest(), tokenStore: InMemoryTokenStore())
        mockState.currentEnvironment = .mock
        XCTAssertTrue(mockState.apiClient is SessionAwareAPIClient, "Mock 同样包上")
        XCTAssertTrue(mockState.sessionUnawareAPIClient is MockAPIClient, "UI 测试钩子要认得出 Mock")
        XCTAssertTrue(EmergencyCoordinator.isMockBacked(mockState.safety), "包了一层之后求助仍认得出 Mock（坐标闸）")
        XCTAssertFalse(EmergencyCoordinator.isMockBacked(appState.safety))
    }

    /// 直接给 `accessToken` 赋值（单测、UI 测试种会话）时 Mock 要跟上，否则它对需要登录的端点回 401，
    /// 包上这一层之后就成了一次凭空的登出。规则参数是陪跑员首页加载时顺手拉的那条。
    func testMockFollowsTheLocalSessionSoItNeverFakesAnExpiry() async {
        let appState = AppState(
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore(),
            refreshTokenStore: InMemoryTokenStore()
        )
        appState.currentEnvironment = .mock
        appState.accessToken = "token-7"
        appState.userId = 7
        appState.activeRole = .volunteer

        let caught = await Self.capture { _ = try await appState.auth.ruleParams() }

        XCTAssertNil(caught, "Mock 认这次会话：\(String(describing: caught))")
        XCTAssertEqual(appState.accessToken, "token-7")
    }

    // MARK: - 求助

    /// 跑步中求助请求 401：进暂缓；落到与漏网云端触发同一个失败态；不对账；再按直接走本地拨号。
    func testSOSTriggerUnauthorizedDuringTheRunDefersAndFallsBackToLocalCall() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        transport.nextError = APIError.unauthorized
        let order = Self.makeOrder(status: .inProgress)

        let outcome = await appState.emergencyCoordinator.trigger(
            order: order, role: .blind, userID: 7, safety: appState.safety,
            locate: { Self.coordinate() }
        )

        XCTAssertTrue(appState.isSessionExpiryDeferred, "跑步中 → 暂缓")
        XCTAssertEqual(appState.accessToken, "token-7")
        XCTAssertEqual(outcome.state, .unsentSessionExpired, "不是「网络异常，请重试」那条：\(outcome.message)")
        XCTAssertEqual(appState.emergencyCoordinator.state, .unsentSessionExpired)
        XCTAssertTrue(outcome.isFailure, "失败态才会带出本地拨号兜底按钮")
        for phrase in ["求助未发出", "App 不会代你发送求助", "120", "110"] {
            XCTAssertTrue(outcome.message.contains(phrase), "缺「\(phrase)」：\(outcome.message)")
        }
        XCTAssertEqual(transport.requests.map(\.path), ["/api/emergency/trigger"], "不拿过期凭证再去对账")

        XCTAssertEqual(
            BlindHomeSOSMode.resolve(order: order, role: .blind, isSessionExpired: appState.isSessionExpiryDeferred),
            .localCallSessionExpired,
            "再按求助：本地拨号"
        )
        let again = await appState.emergencyCoordinator.trigger(
            order: order, role: .blind, userID: 7, safety: appState.safety,
            locate: { Self.coordinate() }
        )
        XCTAssertEqual(again.state, .unsentSessionExpired)
        XCTAssertEqual(transport.requests.count, 1, "暂缓中不再调用求助接口")
    }

    /// 求助已发出后按「误触，撤销」401：进暂缓；不许说已撤销。
    func testSOSCancelUnauthorizedDuringTheRunNeverClaimsTheSOSWasWithdrawn() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        transport.nextResponse = EmergencyTriggerResponse(success: true, eventId: 5, status: "PENDING")
        _ = await appState.emergencyCoordinator.trigger(
            order: Self.makeOrder(status: .inProgress), role: .blind, userID: 7, safety: appState.safety,
            locate: { Self.coordinate() }
        )
        XCTAssertEqual(appState.emergencyCoordinator.activeEvent?.eventID, 5, "前提：求助已发出")
        transport.nextError = APIError.unauthorized

        let outcome = await appState.emergencyCoordinator.cancelByOwner(safety: appState.safety)

        XCTAssertTrue(appState.isSessionExpiryDeferred, "跑步中 → 暂缓")
        XCTAssertTrue(outcome.isFailure)
        XCTAssertFalse(outcome.message.contains("已撤销"), outcome.message)
        XCTAssertTrue(outcome.message.contains("求助仍然有效"), outcome.message)
        XCTAssertEqual(appState.emergencyCoordinator.activeEvent?.eventID, 5, "事件还在，不当作已撤")
    }

    /// 倒计时里撤回 401：服务端倒计时照走，求助可能已经发出 —— 进暂缓，文案不许说已撤回、也不许说「未发出」。
    func testSOSCountdownWithdrawUnauthorizedDefersAndSaysItMayAlreadyBeSent() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        transport.nextResponse = Self.countdownResponse(eventId: 6, secondsFromNow: 30)
        _ = await appState.emergencyCoordinator.trigger(
            order: Self.makeOrder(status: .inProgress), role: .blind, userID: 7, safety: appState.safety,
            locate: { Self.coordinate() }, useCountdown: true
        )
        XCTAssertTrue(appState.emergencyCoordinator.state.isCountingDown, "前提：服务端倒计时已登记")
        transport.nextError = APIError.unauthorized

        let outcome = await appState.emergencyCoordinator.cancelCountdown(safety: appState.safety)

        XCTAssertTrue(appState.isSessionExpiryDeferred, "跑步中 → 暂缓")
        XCTAssertEqual(outcome?.state.isFailure, true)
        let message = outcome?.message ?? ""
        XCTAssertTrue(message.contains("求助可能已经发出"), message)
        XCTAssertFalse(message.contains("已撤回"), message)
        XCTAssertFalse(message.contains("未发出"), "服务端还会到点发出，不能说没发：\(message)")
    }

    // MARK: - 删除账户预检

    /// 跑步中预检 401：进暂缓、不弹删除确认。此前直接 `expireSession()`，绕过了暂缓。
    func testAccountDeletionPreflightUnauthorizedDuringTheRunDefers() async {
        let (appState, transport) = Self.loggedInAppState(role: .blind)
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        transport.nextError = APIError.unauthorized
        let viewModel = AccountDeletionViewModel()

        await viewModel.preflight(appState: appState, speechService: SpeechService())

        XCTAssertFalse(viewModel.showFinalConfirmation, "不弹删除确认")
        XCTAssertTrue(appState.isSessionExpiryDeferred)
        XCTAssertEqual(appState.accessToken, "token-7", "跑步中不清会话")
    }

    func testAccountDeletionPreflightUnauthorizedOutsideTheRunLogsOut() async {
        let (appState, transport) = Self.loggedInAppState(role: .volunteer)
        transport.nextError = APIError.unauthorized
        let recorder = SessionEventRecorder(appState)
        let viewModel = AccountDeletionViewModel()

        await viewModel.preflight(appState: appState, speechService: SpeechService())

        XCTAssertFalse(viewModel.showFinalConfirmation, "不弹删除确认")
        XCTAssertNil(appState.accessToken, "退回登录页")
        XCTAssertEqual(recorder.expiryMessages, ["登录已过期，请重新登录。"])
    }

    // MARK: - Helpers

    private static func loggedInAppState(role: UserRole) -> (AppState, RecordingTransport) {
        let transport = RecordingTransport()
        let appState = AppState(
            apiClient: transport,
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore(),
            refreshTokenStore: InMemoryTokenStore()
        )
        appState.accessToken = "token-7"
        appState.userId = 7
        appState.activeRole = role
        return (appState, transport)
    }

    private static func capture(_ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    private static func isUnauthorized(_ error: Error?) -> Bool {
        if case .unauthorized? = error as? APIError { return true }
        return false
    }
}

/// 记下会话结束了几次、登录页提示写了哪几句。只看最终状态分不出「登出一次」与「登出三次」。
@MainActor
private final class SessionEventRecorder {
    private(set) var logouts = 0
    private(set) var expiryMessages: [String] = []
    private var cancellables = Set<AnyCancellable>()

    init(_ appState: AppState) {
        appState.$accessToken.dropFirst().sink { [weak self] token in
            if token == nil { self?.logouts += 1 }
        }.store(in: &cancellables)
        appState.$sessionExpirationMessage.dropFirst().compactMap { $0 }.sink { [weak self] message in
            self?.expiryMessages.append(message)
        }.store(in: &cancellables)
    }
}
