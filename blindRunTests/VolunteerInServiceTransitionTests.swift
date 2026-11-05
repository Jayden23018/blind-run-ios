import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerInServiceTransitionTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerEnRouteUnknownPostResultReleasesSpinnerAndAwaitsConfirmation() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel(
            actionDeadlineNanoseconds: 20_000_000,
            confirmationTimeout: 0.2
        )
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 94, status: .pendingAccept)
        )

        await viewModel.enRoute()

        XCTAssertFalse(viewModel.isPerformingAction)
        await client.awaitCancellation()
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverEnRoute))
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(
            speechService.lastSpokenText,
            "操作结果尚未确认，正在后台同步状态。请勿重复提交同一操作。"
        )
        XCTAssertEqual(viewModel.order?.status, .pendingAccept)
    }

    func testVolunteerEnRouteSuccessDoesNotWaitForSuspendedConfirmationAndBlocksDuplicatePost() async {
        let initialOrder = makeOrder(orderId: 95, status: .pendingAccept)
        let client = TransitionConfirmationFixture(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(orders: client.service)
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: initialOrder
        )
        let startedAt = Date()

        await viewModel.enRoute()

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverEnRoute))
        XCTAssertEqual(client.postRequestCount, 1)
        XCTAssertEqual(viewModel.order?.status, .pendingAccept)

        await viewModel.enRoute()
        XCTAssertEqual(client.postRequestCount, 1, "Pending conversion must not submit a duplicate POST")
        let didStartConfirmation = await waitUntil { client.getRequestCount == 1 }
        XCTAssertTrue(didStartConfirmation)
        client.releaseSuspendedRequests()
    }

    func testVolunteerEnRouteWebSocketConfirmationWinsOverSuspendedDetailQuery() async {
        let initialOrder = makeOrder(orderId: 96, status: .pendingAccept)
        let client = TransitionConfirmationFixture(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(orders: client.service)
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(with: appState, speechService: speechService, initialOrder: initialOrder)

        await viewModel.enRoute()
        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: 96,
                fromStatus: RunOrderStatus.pendingAccept.rawValue,
                toStatus: RunOrderStatus.driverEnRoute.rawValue,
                message: nil,
                ttsText: nil,
                priority: "NORMAL",
                timestamp: "2026-07-23T12:00:00Z"
            ))
        )
        let didConfirm = await waitUntil {
            viewModel.order?.status == .driverEnRoute && viewModel.transitionState == .idle
        }

        XCTAssertTrue(didConfirm)
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(
            speechService.lastSpokenText,
            RunOrderStatus.driverEnRoute.volunteerAnnouncement
        )
        client.releaseSuspendedRequests()
    }

    func testVolunteerEnRoutePollingConfirmationAppliesAuthoritativeStatus() async {
        let initialOrder = makeOrder(orderId: 97, status: .pendingAccept)
        let confirmedOrder = makeOrder(orderId: 97, status: .driverEnRoute)
        let client = TransitionConfirmationFixture(
            confirmation: .response,
            order: confirmedOrder
        )
        let appState = AppState(orders: client.service)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)

        await viewModel.enRoute()
        let didConfirm = await waitUntil {
            viewModel.order?.status == .driverEnRoute && viewModel.transitionState == .idle
        }

        XCTAssertTrue(didConfirm)
        XCTAssertEqual(client.postRequestCount, 1)
        XCTAssertEqual(client.getRequestCount, 1)
    }

    func testVolunteerEnRouteConfirmationDelayOffersReadOnlyRetryWithoutReposting() async {
        let initialOrder = makeOrder(orderId: 98, status: .pendingAccept)
        let client = TransitionConfirmationFixture(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(orders: client.service)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)

        await viewModel.enRoute()
        let didDelay = await waitUntil {
            viewModel.transitionState == .confirmationDelayed(target: .driverEnRoute)
        }

        XCTAssertTrue(didDelay)
        XCTAssertTrue(viewModel.canRetryTransitionConfirmation)
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(client.postRequestCount, 1)

        viewModel.retryTransitionConfirmation()
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverEnRoute))
        let didRetryConfirmation = await waitUntil { client.getRequestCount == 2 }
        XCTAssertTrue(didRetryConfirmation)
        XCTAssertEqual(client.postRequestCount, 1, "Read-only retry must never repeat the state-changing POST")
        client.releaseSuspendedRequests()
    }

    func testVolunteerEnRouteExplicitServerErrorRestoresRetryableAction() async {
        let client = TransitionConfirmationFixture(
            postError: .serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED",
                message: "订单状态不允许该操作"
            )),
            confirmation: .response,
            order: makeOrder(orderId: 99, status: .pendingAccept)
        )
        let appState = AppState(orders: client.service)
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 99, status: .pendingAccept)
        )

        await viewModel.enRoute()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertFalse(viewModel.isTransitionPending)
        if case .failed = viewModel.transitionState {
            // Expected: an explicit backend rejection permits a deliberate retry.
        } else {
            XCTFail("Expected an explicit server error to enter failed state")
        }
        XCTAssertEqual(viewModel.errorMessage, "当前订单状态不允许此操作。")
        XCTAssertEqual(client.postRequestCount, 1)

        await viewModel.enRoute()
        XCTAssertEqual(client.postRequestCount, 2)
    }

    func testVolunteerEnRouteUnauthorizedUsesSessionExpirationFlow() async {
        let client = TransitionConfirmationFixture(
            postError: .unauthorized,
            confirmation: .response,
            order: makeOrder(orderId: 100, status: .pendingAccept)
        )
        let appState = AppState(orders: client.service)
        appState.accessToken = "expired-token"
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 100, status: .pendingAccept)
        )

        await viewModel.enRoute()

        XCTAssertNil(appState.accessToken)
        XCTAssertEqual(appState.sessionExpirationMessage, "登录已过期，请重新登录。")
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertFalse(viewModel.isTransitionPending)
    }

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

    func testVolunteerBlindPeerSampleExpiresAndWrongOrderCannotClearIt() async throws {
        let viewModel = VolunteerInServiceViewModel(peerFreshness: 0.06)
        viewModel.order = makeOrder(orderId: 109, status: .driverEnRoute)
        let sample = RealtimePeerLocationSample(
            orderId: 109,
            ownerRole: .blind,
            latitude: 39.9342,
            longitude: 116.4740,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        viewModel.handleBlindLocationUpdate(sample)
        viewModel.handleBlindLocationUpdate(RealtimePeerLocationSample(
            orderId: 999,
            ownerRole: .blind,
            latitude: 31.2,
            longitude: 121.5,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        ))

        XCTAssertEqual(
            try XCTUnwrap(viewModel.latestBlindSample).coordinate.latitude,
            sample.latitude,
            accuracy: 0.000_001
        )
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(viewModel.latestBlindSample)
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
