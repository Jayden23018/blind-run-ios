import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerArrivedAndInServiceTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerArrivedUnknownPostResultReleasesSpinnerAndAwaitsConfirmation() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel(
            actionDeadlineNanoseconds: 20_000_000,
            confirmationTimeout: 0.2
        )
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 104, status: .driverEnRoute)
        )

        await viewModel.arrive()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverArrived))
        XCTAssertEqual(client.requestCount(for: "/api/orders/104/arrived"), 1)
        XCTAssertEqual(viewModel.order?.status, .driverEnRoute)
    }

    func testVolunteerArrivedSuccessDoesNotWaitForSuspendedConfirmationOrRepost() async {
        let initialOrder = makeOrder(orderId: 105, status: .driverEnRoute)
        let client = TransitionConfirmationFixture(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(orders: client.service)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)

        await viewModel.arrive()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverArrived))
        XCTAssertEqual(client.postRequestCount, 1)
        await viewModel.arrive()
        XCTAssertEqual(client.postRequestCount, 1)
        client.releaseSuspendedRequests()
    }

    func testVolunteerArrivedWebSocketConfirmationWinsOverLateOldREST() async {
        let initialOrder = makeOrder(orderId: 106, status: .driverEnRoute)
        let client = TransitionConfirmationFixture(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(orders: client.service)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.3)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)
        // 生产上 `configure` 与 `startPolling` 在同一个 `.task` 里先后调；状态推送只送给在跟这一单的 track。
        viewModel.startPolling(orderId: 106)

        await viewModel.arrive()
        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: 106,
                fromStatus: RunOrderStatus.driverEnRoute.rawValue,
                toStatus: RunOrderStatus.driverArrived.rawValue,
                message: nil,
                ttsText: nil,
                priority: "NORMAL",
                timestamp: "2026-07-28T11:00:00Z"
            ))
        )
        let didConfirmRealtimeArrival = await waitUntil {
            viewModel.order?.status == .driverArrived && viewModel.transitionState == .idle
        }
        XCTAssertTrue(didConfirmRealtimeArrival)

        client.releaseSuspendedRequests()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(viewModel.order?.status, .driverArrived)
        XCTAssertFalse(viewModel.isPerformingAction)
    }

    func testVolunteerArrivedRESTConfirmationAppliesAuthoritativeStatus() async {
        let client = TransitionConfirmationFixture(
            confirmation: .response,
            order: makeOrder(orderId: 107, status: .driverArrived)
        )
        let appState = AppState(orders: client.service)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 107, status: .driverEnRoute)
        )

        await viewModel.arrive()

        let didConfirmRESTArrival = await waitUntil {
            viewModel.order?.status == .driverArrived && viewModel.transitionState == .idle
        }
        XCTAssertTrue(didConfirmRESTArrival)
        XCTAssertEqual(client.postRequestCount, 1)
        XCTAssertEqual(client.getRequestCount, 1)
    }

    func testVolunteerArrivedExplicitServerErrorRestoresRetryableAction() async {
        let client = TransitionConfirmationFixture(
            postError: .serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED",
                message: "订单状态不允许该操作"
            )),
            confirmation: .response,
            order: makeOrder(orderId: 108, status: .driverEnRoute)
        )
        let appState = AppState(orders: client.service)
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 108, status: .driverEnRoute)
        )

        await viewModel.arrive()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertFalse(viewModel.isTransitionPending)
        XCTAssertEqual(viewModel.errorMessage, "当前订单状态不允许此操作。")
        await viewModel.arrive()
        XCTAssertEqual(client.postRequestCount, 2)
    }

    /// 第 3 批（unify-order-live-tracking）起走真实链路：协调器 → 订单跟踪 → 页面。阈值从 `init(peerFreshness:)`
    /// 经 `open(peerFreshness:)` 进 track；别的单的样本不进流，也清不掉本单的标记。
    func testVolunteerBlindPeerSampleExpiresAndWrongOrderCannotClearIt() async throws {
        let service = FakeOrderService()
        service.orderDetailResult = .success(makeOrder(orderId: 109, status: .driverEnRoute))
        let appState = AppState(orders: service)
        appState.currentEnvironment = .mock
        let viewModel = VolunteerInServiceViewModel(peerFreshness: 0.3)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: makeOrder(orderId: 109, status: .driverEnRoute))
        viewModel.startPolling(orderId: 109)
        appState.realtimeCoordinator.registerActiveOrder(999)
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let coordinator = appState.realtimeCoordinator
        coordinator.simulateIncomingEventForTesting(.blindLocation(WSBlindLocationUpdate(
            type: WSMessageType.blindLocationUpdate.rawValue, orderId: 109, lat: 39.9342, lng: 116.4740, timestamp: now
        )))
        coordinator.simulateIncomingEventForTesting(.blindLocation(WSBlindLocationUpdate(
            type: WSMessageType.blindLocationUpdate.rawValue, orderId: 999, lat: 31.2, lng: 121.5, timestamp: now
        )))
        let arrived = await waitUntil(timeout: 0.25) { viewModel.latestBlindSample != nil }

        XCTAssertTrue(arrived, "本单的样本没送到页面")
        // 等 999 单那条也走完协调器的发布（同一主线程周期合并后各自一个 Task），再断言它没清掉、也没替换本单标记。
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(try XCTUnwrap(viewModel.latestBlindSample).coordinate.latitude, 39.9342, accuracy: 0.000_001)
        // 阈值 0.3 秒：到期后由 track 发 `.peerLocationExpired`，页面清掉。
        let expired = await waitUntil(timeout: 1) { viewModel.latestBlindSample == nil }
        XCTAssertTrue(expired, "样本过期后没清")
        XCTAssertNil(viewModel.latestBlindAccuracyMeters)
    }

    func testVolunteerInServiceBlocksStartServiceOutsideDriverArrived() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 1, status: .inProgress)
        )

        await viewModel.startService()

        XCTAssertEqual(viewModel.order?.status, .inProgress)
        XCTAssertEqual(viewModel.errorMessage, RunOrderStatus.inProgress.startServiceBlockedMessage)
        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.inProgress.startServiceBlockedMessage)
    }

    func testVolunteerInServiceAllowsFinishFromInProgressAndRefreshesSummary() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.complete()

        let didConfirmCompletion = await waitUntil {
            viewModel.order?.status == .completed
                && viewModel.dispatchSummary?.completedCount == 2
        }
        XCTAssertTrue(didConfirmCompletion)
    }

    func testVolunteerInServiceCancelClearsLocalOrderWithoutDetailFetch() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.cancel()

        let didConfirmCancellation = await waitUntil {
            viewModel.didCancelOrder && viewModel.order == nil
        }
        XCTAssertTrue(didConfirmCancellation)
        XCTAssertNil(viewModel.order)
        XCTAssertNil(viewModel.errorMessage)
        // 开跑之后才取消，Mock 按后端口径记一次临时取消，所以那一句后面可能还接着「已记一次」。
        let spoken = speechService.lastSpokenText ?? ""
        XCTAssertTrue(spoken.hasPrefix(VolunteerCancelAnnouncement.cancelledByVolunteer), "实际：\(spoken)")
        XCTAssertFalse(spoken.contains("重新匹配"), "重匹到上限时这半句不成立")
    }

    func testVolunteerTravelStageUsesDepartureCopyBeforeArrival() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.serviceStageTitle, "前往出发地点")
        XCTAssertEqual(RunOrderStatus.driverEnRoute.serviceStageTitle, "前往出发地点")
        XCTAssertEqual(RunOrderStatus.driverArrived.serviceStageTitle, "已到达集合地点")
        XCTAssertEqual(RunOrderStatus.inProgress.serviceStageTitle, "服务进行中")
        XCTAssertEqual(
            RunOrderStatus.pendingAccept.serviceStageSubtitle,
            "请确认当前位置和出发地点，可使用外部地图步行导航"
        )
    }

    func testVolunteerServicePendingAcceptUsesDepartureCopy() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.volunteerServiceDisplayName, "待出发")
        XCTAssertEqual(RunOrderStatus.driverEnRoute.volunteerServiceDisplayName, "陪跑员出发中")
    }
}
