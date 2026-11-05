import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerEnRouteTransitionTests: XCTestCase, BlindRunTestSupport {
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
}
