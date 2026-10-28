import UserNotifications
import XCTest
@testable import blindRun

/// #459：断网退出登录后，推送 token 仍绑在旧账号上、且本机不再有补撤入口。
///
/// 目标：旧账号的推送不能被下一个人听到或看到，服务端绑定最终一定会被撤掉。
/// 每条「记下来 / 撤掉」都配一条「不该记 / 不该再撤」的对照：只断前者的话，
/// 一个什么情况都记、永远重试的实现也会绿。
@MainActor
final class PendingSessionRevocationTests: XCTestCase {

    private let deviceToken = String(repeating: "0a", count: 32)

    // MARK: - 登出时记下没撤成的部分

    /// 🔴 复现 #459：断网登出 → 解绑与登出都没成 → 本地会话照清，但要留下补撤的凭据。
    func testOfflineLogoutRecordsTheUnrevokedSessionBeforeClearingIt() async {
        let client = ScriptedAuthClient(fail: [.unbind: .networkError(URLError(.notConnectedToInternet)),
                                               .logout: .networkError(URLError(.notConnectedToInternet))])
        let (appState, push) = makeSignedInAppState(client: client)

        await appState.logout()

        XCTAssertFalse(appState.isLoggedIn, "用户的意图是退出，本地照清")
        let pending = appState.pendingSessionRevoker.pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.accessToken, "old-access", "补撤要用旧会话的 access")
        XCTAssertEqual(pending.first?.refreshToken, "old-refresh", "access 过期时只为撤销换一个")
        XCTAssertEqual(pending.first?.deviceToken, deviceToken)
        XCTAssertEqual(pending.first?.needsLogout, true)
        withExtendedLifetime(push) {}
    }

    /// 对照：服务端都撤成了就什么都不记。
    func testSuccessfulLogoutLeavesNothingToRevoke() async {
        let (appState, push) = makeSignedInAppState(client: ScriptedAuthClient())

        await appState.logout()

        XCTAssertTrue(appState.pendingSessionRevoker.pending.isEmpty)
        withExtendedLifetime(push) {}
    }

    /// 对照：401 = 这次登录在服务端已经结束（续期也救不回），旧凭据再试也是 401，不记。
    func testLogoutOfAnAlreadyEndedSessionLeavesNothingToRevoke() async {
        let client = ScriptedAuthClient(fail: [.unbind: .unauthorized, .logout: .unauthorized])
        let (appState, push) = makeSignedInAppState(client: client)

        await appState.logout()

        XCTAssertTrue(appState.pendingSessionRevoker.pending.isEmpty)
        withExtendedLifetime(push) {}
    }

    /// 只差登出（解绑成了）：记录里不带推送 token，补撤时不会再去解绑。
    func testOnlyTheUnfinishedStepIsRecorded() async {
        let client = ScriptedAuthClient(fail: [.logout: .networkError(URLError(.timedOut))])
        let (appState, push) = makeSignedInAppState(client: client)

        await appState.logout()

        XCTAssertNil(appState.pendingSessionRevoker.pending.first?.deviceToken)
        XCTAssertEqual(appState.pendingSessionRevoker.pending.first?.needsLogout, true)
        withExtendedLifetime(push) {}
    }

    // MARK: - 补撤

    /// 补撤按契约顺序：先解绑再登出（登出会把 JWT 拉黑），两个都带记录里的旧 access；撤完删记录。
    func testRetryUnbindsBeforeLoggingOutWithTheRecordedAccessToken() async {
        let log = RequestLog()
        let revoker = makeRevoker(log: log, script: [:])
        revoker.record(pendingItem())

        await revoker.retryIfPending()

        XCTAssertEqual(log.calls, [
            .init(step: .unbind, accessToken: "old-access"),
            .init(step: .logout, accessToken: "old-access")
        ])
        XCTAssertTrue(revoker.pending.isEmpty)
    }

    /// 还没联网：记录留着，下次联网再撤；联网后撤完。
    func testNetworkFailureKeepsTheRecordUntilALaterRetrySucceeds() async {
        let log = RequestLog()
        var offline = true
        let revoker = PendingSessionRevoker(
            store: PendingSessionRevocationStore(storage: InMemoryTokenStore()),
            transport: { access in
                ScriptedAuthClient(
                    accessToken: access,
                    log: log,
                    fail: offline ? [.unbind: .networkError(URLError(.notConnectedToInternet))] : [:]
                )
            },
            monitorsNetwork: false
        )
        revoker.record(pendingItem())

        await revoker.retryIfPending()
        XCTAssertEqual(revoker.pending.count, 1, "断网时不许丢")

        offline = false
        await revoker.retryIfPending()
        XCTAssertTrue(revoker.pending.isEmpty)
    }

    /// 旧 access 已过期：用记录里的 refresh 换一个，**只为撤销**，换到的写回记录、不碰当前会话。
    func testExpiredAccessIsRenewedWithTheRecordedRefreshTokenAndThenRevoked() async {
        let log = RequestLog()
        let revoker = makeRevoker(log: log, script: [.unbind: .unauthorizedFor("old-access")])
        revoker.record(pendingItem())

        await revoker.retryIfPending()

        XCTAssertEqual(log.calls.last, .init(step: .logout, accessToken: "renewed-access"))
        XCTAssertTrue(log.calls.contains(.init(step: .refresh, accessToken: nil)), "换 access 的请求不带 Bearer")
        XCTAssertTrue(revoker.pending.isEmpty)
    }

    /// 对照：refresh 也 401 = 这次登录在服务端已经结束，没有能撤的了 —— 丢掉，不无限重试。
    func testEndedSessionIsDroppedInsteadOfRetriedForever() async {
        let log = RequestLog()
        let revoker = makeRevoker(log: log, script: [.unbind: .unauthorizedFor(nil), .refresh: .unauthorizedFor(nil)])
        revoker.record(pendingItem())

        await revoker.retryIfPending()

        XCTAssertTrue(revoker.pending.isEmpty)
    }

    /// 超过 refresh 有效期（30 天）的记录直接丢：服务端那次登录已自然结束。
    func testRecordsOlderThanTheRefreshLifetimeAreDroppedWithoutRequests() async {
        let log = RequestLog()
        let revoker = makeRevoker(log: log, script: [:])
        revoker.record(pendingItem(recordedAt: Date().addingTimeInterval(-PendingSessionRevoker.retention - 60)))

        await revoker.retryIfPending()

        XCTAssertTrue(log.calls.isEmpty)
        XCTAssertTrue(revoker.pending.isEmpty)
    }

    // MARK: - 没人登录时收不到、听不到

    /// 有人登录才向 APNs 注册；会话一结束就注销 —— 不在前台时横幅由系统直接弹，前台闸拦不住。
    func testRemoteNotificationRegistrationFollowsTheSession() {
        let appState = AppState(apiClient: ScriptedAuthClient(), persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let push = PushNotificationsManager()
        var events: [String] = []
        push.registrar = .init(register: { events.append("register") }, unregister: { events.append("unregister") })
        push.configure(appState: appState, speechService: SpeechService())

        appState.handleLoginSuccess(response: LoginResponse(token: "t", userId: 3, role: "BLIND"))
        appState.clearSession()

        XCTAssertEqual(events.suffix(2), ["register", "unregister"])
        XCTAssertNil(PushNotificationsManager.wantsRemoteNotifications(.restoring), "恢复中还不知道会话在不在，不动")
    }

    /// 前台闸：没人登录时不上屏（朗读走同一个判据）。
    func testForegroundPushIsHiddenWhenNobodyIsSignedIn() {
        XCTAssertEqual(PushNotificationsManager.foregroundPresentation(isSignedIn: false), [])
        XCTAssertEqual(PushNotificationsManager.foregroundPresentation(isSignedIn: true), [.banner, .sound])
    }

    // MARK: - Helpers

    /// `PushNotificationsManager` 由用例攥着：`AppState` 对它是 `weak`。
    private func makeSignedInAppState(client: ScriptedAuthClient) -> (AppState, PushNotificationsManager) {
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let push = PushNotificationsManager()
        push.registrar = .inert
        push.configure(appState: appState, speechService: SpeechService())
        appState.pushNotificationsManager = push
        appState.handleLoginSuccess(response: LoginResponse(
            token: "old-access", userId: 7, role: "BLIND", refreshToken: "old-refresh", expiresIn: 3600
        ))
        push.seedReportedScopeForTesting(.init(token: deviceToken, environment: appState.currentEnvironment, userId: 7))
        return (appState, push)
    }

    private func makeRevoker(log: RequestLog, script: [ScriptedAuthClient.Step: ScriptedAuthClient.Failure]) -> PendingSessionRevoker {
        PendingSessionRevoker(
            store: PendingSessionRevocationStore(storage: InMemoryTokenStore()),
            transport: { access in ScriptedAuthClient(accessToken: access, log: log, fail: script) },
            monitorsNetwork: false
        )
    }

    private func pendingItem(recordedAt: Date = Date()) -> PendingSessionRevocation {
        PendingSessionRevocation(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            deviceToken: deviceToken,
            needsLogout: true,
            recordedAt: recordedAt
        )
    }
}

/// 记下补撤发了哪些请求、各带哪个 access。
private final class RequestLog: @unchecked Sendable {
    struct Call: Equatable {
        let step: ScriptedAuthClient.Step
        let accessToken: String?
    }

    var calls: [Call] = []
}

/// 只认三个撤销相关的端点。`fail` 按端点给失败；`.unauthorizedFor(token)` 只对那个 access 回 401（nil = 一律 401）。
private struct ScriptedAuthClient: APIClientProtocol, @unchecked Sendable {
    enum Step: Equatable { case unbind, logout, refresh }

    enum Failure {
        case networkError(URLError)
        case unauthorized
        case unauthorizedFor(String?)
    }

    var accessToken: String?
    var log: RequestLog?
    var fail: [Step: Failure] = [:]

    init(accessToken: String? = nil, log: RequestLog? = nil, fail: [Step: Failure] = [:]) {
        self.accessToken = accessToken
        self.log = log
        self.fail = fail
    }

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        let step: Step
        let success: Any
        switch (method, path) {
        case (.delete, "/api/devices/apns"):
            step = .unbind
            success = EmptyResponse()
        case (.post, "/api/auth/logout"):
            step = .logout
            success = LogoutResponse(success: true, message: nil)
        case (.post, "/api/auth/refresh"):
            step = .refresh
            success = LoginResponse(token: "renewed-access", userId: 7, role: "BLIND", refreshToken: "renewed-refresh")
        default:
            throw APIError.invalidURL
        }
        log?.calls.append(.init(step: step, accessToken: step == .refresh ? nil : accessToken))
        switch fail[step] {
        case .networkError(let error)?:
            throw APIError.networkError(error)
        case .unauthorized?:
            throw APIError.unauthorized
        case .unauthorizedFor(let token)? where token == nil || token == accessToken:
            throw APIError.unauthorized
        default:
            guard let typed = success as? T else { throw APIError.invalidURL }
            return typed
        }
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}
