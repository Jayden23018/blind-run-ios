import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerHomeDispatchTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerHomeCoalescesLifecycleReconnectAndManualRefreshWhileKeepingContent() async throws {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let existingSummary = try JSONDecoder().decode(
            VolunteerDispatchSummaryResponse.self,
            from: Data(#"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true}"#.utf8)
        )
        let existingOrder = makeOrder(orderId: 702, status: .driverEnRoute)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 0.08)
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.dispatchSummary = existingSummary
        viewModel.activeOrder = existingOrder
        let startedAt = Date()

        let lifecycleLoad = Task {
            await viewModel.load(currentLocation: nil, locationAuthorized: false)
        }
        let didStart = await waitUntil {
            client.requestCount(for: "/api/volunteer/dispatch-summary") == 1
        }
        let reconnectLoad = Task {
            await viewModel.load(currentLocation: nil, locationAuthorized: false)
        }
        let manualRefresh = Task { await viewModel.refreshDispatchSummary() }
        await lifecycleLoad.value
        await reconnectLoad.value
        await manualRefresh.value

        XCTAssertTrue(didStart)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertEqual(client.requestCount(for: "/api/volunteer/dispatch-summary"), 1)
        XCTAssertEqual(viewModel.dispatchSummary?.canDispatch, true)
        XCTAssertEqual(viewModel.activeOrder?.orderId, existingOrder.orderId)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.dispatchSummaryErrorMessage, "加载超过 20 秒，请重试。")
    }

    func testVolunteerDispatchSummaryDoesNotWaitForSlowProfileHydration() async {
        // 两个替身各管一片：慢的那半是资料水合（认证片，走 apiClient），
        // 快的那半是派单摘要（订单片，走 orders）。
        let client = Self.makeDispatchSummaryService(
            first: .success(Self.dispatchSummaryAvailable),
            rest: Self.dispatchSummaryAvailable
        )
        let appState = AppState(apiClient: SlowProfileHydrationAPIClient(), orders: client)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 2)
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.load(currentLocation: nil, locationAuthorized: false) }
        let didLoadSummary = await waitUntil(timeout: 0.5) {
            viewModel.dispatchSummary?.canDispatch == true && !viewModel.isLoading
        }

        XCTAssertTrue(didLoadSummary)
        XCTAssertEqual(client.callCount("dispatchSummary()"), 1)
        loadTask.cancel()
        await loadTask.value
    }

    /// 接下之后**卡片原地变「已约好」，不自动跳订单页**（设计交付 v3 §4.4.3）。
    ///
    /// 🔴 **这条用例 2026-09-17 改过方向。** 它原先断言 `acceptedDispatchOrderId == 1`
    /// 会在接单成功那一刻出现 —— 那正是「自动 push」的实现。改成邀请卡之后自动跳会把
    /// 那张确认卡一闪而过，而它是唯一一处告诉陪跑员「跑者的全名和电话已经放进订单」的地方。
    ///
    /// 所以断言拆成两段：**成功那一刻不导航**，**点了「查看订单」才导航**。
    /// 只留后半段的话，一个仍然自动跳的实现照样能过。
    func testAcceptingDispatchShowsTheBookedCardAndOnlyNavigatesOnTap() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        // 等到**整条链路跑完**（`isRespondingToDispatch` 在最后一次刷新之后才落回 false）。
        // 只等 `outcome == .accepted` 是不够的：结果先落在卡上、刷新在后面，
        // 那一刻 `acceptedDispatchInitialOrder` 还没回来。
        let didBook = await waitUntil {
            viewModel.currentInvite?.outcome == .accepted && !viewModel.isRespondingToDispatch
        }
        XCTAssertTrue(didBook)
        XCTAssertNil(
            viewModel.acceptedDispatchOrderId,
            "接下成功那一刻不该导航 —— 结果卡还没被看到"
        )
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.orderId, 1)
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.status, .pendingAccept)
        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)
        XCTAssertEqual(viewModel.activeOrder?.status, .pendingAccept)
        XCTAssertNotNil(viewModel.incomingOrder, "结果卡还在，邀请不该从队列里消失")
        XCTAssertEqual(speechService.lastSpokenText, "已接受订单")

        viewModel.openAcceptedOrder(orderID: 1)

        XCTAssertEqual(viewModel.acceptedDispatchOrderId, 1)
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertFalse(viewModel.isInviteSheetPresented)
    }

    func testAcceptingDispatchFailureDoesNotPublishNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 999)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didFail = await waitUntil { viewModel.errorMessage != nil }
        XCTAssertTrue(didFail)
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(viewModel.incomingOrder)
        XCTAssertEqual(viewModel.dispatchCountdown, 30)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
    }

    func testAcceptingDispatchRequiresReadinessAndLocation() async throws {
        let unavailableState = AppState()
        unavailableState.currentEnvironment = .mock
        unavailableState.updateVolunteerProfile(makeApprovedVolunteerProfile(isAvailable: false))
        let unavailableViewModel = VolunteerHomeViewModel()
        unavailableViewModel.configure(with: unavailableState, speechService: SpeechService())
        unavailableViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        unavailableViewModel.respondToDispatch(
            action: .accept,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        XCTAssertEqual(unavailableViewModel.errorMessage, "请先开启可服务状态")
        XCTAssertNil(unavailableViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(unavailableViewModel.incomingOrder)

        let noLocationState = AppState()
        noLocationState.currentEnvironment = .mock
        noLocationState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let noLocationViewModel = VolunteerHomeViewModel()
        noLocationViewModel.configure(with: noLocationState, speechService: SpeechService())
        noLocationViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        noLocationViewModel.respondToDispatch(
            action: .accept,
            currentLocation: nil,
            locationAuthorized: false
        )

        XCTAssertEqual(noLocationViewModel.errorMessage, "需要开启定位权限才能接单")
        XCTAssertNil(noLocationViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(noLocationViewModel.incomingOrder)
    }

    /// 推送说「这一单可以直接接」，后端却回 409 `INTRO_CALL_REQUIRED`。
    ///
    /// 成因是竞态：推送是后端判断的一个**快照**，发出之后这一对的磨合记录或
    /// `app.intro-call.enabled` 都可能变。志愿者已经点过这个动作了，30 秒倒计时里不该让他
    /// 再点一遍 —— 客户端自己改发 `INTERESTED`，并照常进通话页。
    ///
    /// 断言打在**发出去的动作序列**上，不是打在「最后成功了」上：只看结果的话，
    /// 一个从头到尾只发 `INTERESTED` 的实现也能过。
    func testAcceptRejectedByTheIntroCallGuardSilentlyFallsBackToInterested() async throws {
        let client = IntroCallRequiredOnAcceptAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        let order = makeDispatchOrder(orderId: 77, requiresIntroCall: false)
        XCTAssertEqual(order.dispatchRespondAction, .accept)
        viewModel.incomingOrder = order
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            action: order.dispatchRespondAction,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didFallBack = await waitUntil { viewModel.pendingIntroCallOrder != nil }
        XCTAssertTrue(didFallBack)
        XCTAssertEqual(client.respondActions, [.accept, .interested])
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertEqual(speechService.lastSpokenText, "已告诉跑者你有意向，请留意他的来电")
    }

    /// 志愿者资料水合**慢**，而派单摘要要照常先出来。
    ///
    /// 它仍然是传输桩，因为它演的是**认证·会话片**那两条端点
    /// （`AuthServing.volunteerProfile` / `.volunteerRegistrationStatus`）——
    /// 订单片这次不动它们。派单摘要那一半已经交给 `FakeOrderService`，
    /// 所以这里只剩「挂住 5 秒」这一件事。
    private final class SlowProfileHydrationAPIClient: APIClientProtocol, @unchecked Sendable {
        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw APIError.invalidURL
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

    /// `/respond` 收到 `ACCEPT` 就回 409 `INTRO_CALL_REQUIRED`，`INTERESTED` 照单全收 ——
    /// 后端 `DispatchService.handleAccept` 那道守卫的最小复刻。记录动作序列，
    /// 因为「有没有先试过 ACCEPT」只有序列看得出来。
    private final class IntroCallRequiredOnAcceptAPIClient: APIClientProtocol, @unchecked Sendable {
        private(set) var respondActions: [OrderRespondAction] = []

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .post, path.hasSuffix("/respond"),
                  let request = body as? OrderRespondRequest else {
                throw APIError.invalidURL
            }
            respondActions.append(request.action)
            if request.action == .accept {
                throw APIError.serverError(ErrorResponse(
                    code: "INTRO_CALL_REQUIRED",
                    message: "需要先与跑者通话"
                ))
            }
            guard let value = EmptyResponse() as? T else { throw APIError.invalidURL }
            return value
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
}
