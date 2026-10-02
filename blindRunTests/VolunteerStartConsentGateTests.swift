import XCTest
@testable import blindRun

/// 陪跑员「开始跑步」的同意闸（后端 #307 ①，迁移 0046）。
///
/// 后端对 `start-service` 有两道 409，页面要**分开处理**：
/// - `SERVICE_START_TOO_EARLY`：纯时间问题，只念文案；
/// - `BLIND_CONFIRMATION_PENDING`：盲人还没点头，按钮上方小字换成「等待对方确认」，**按钮仍可按**。
/// 盲人点头时陪跑员收 `BLIND_START_CONFIRMED`（信封不带 `orderId`），页面把小字收回去。
@MainActor
final class VolunteerStartConsentGateTests: XCTestCase {

    func testNewErrorCodesDecodeFromTheBackendStrings() {
        XCTAssertEqual(ErrorCode(rawValue: "SERVICE_START_TOO_EARLY"), .serviceStartTooEarly)
        XCTAssertEqual(ErrorCode(rawValue: "BLIND_CONFIRMATION_PENDING"), .blindConfirmationPending)
        XCTAssertNotEqual(
            ErrorCode.serviceStartTooEarly.localizedMessage,
            ErrorCode.blindConfirmationPending.localizedMessage,
            "两道闸要说的话不同：一个是等时间，一个是等对方"
        )
    }

    func testCaptionSwitchesOnlyForStartRunWhileAwaitingConfirmation() {
        typealias Action = VolunteerOrderFlowPresentation.PrimaryAction
        XCTAssertEqual(
            Action.startRun.caption(awaitingBlindConfirmation: true),
            VolunteerOrderFlowCopy.startRunAwaitingConfirmation
        )
        XCTAssertEqual(Action.startRun.caption(awaitingBlindConfirmation: false), Action.startRun.caption)
        // 别的按钮不受影响（等待对方确认只和「开始跑步」有关）。
        XCTAssertEqual(Action.endWaiting.caption(awaitingBlindConfirmation: true), Action.endWaiting.caption)
        XCTAssertNil(Action.arrived.caption(awaitingBlindConfirmation: true))
    }

    func testPendingConfirmationAnswerShowsWaitingCaptionButKeepsTheButtonPressable() async {
        let (viewModel, service, _) = makeViewModel(startError: "BLIND_CONFIRMATION_PENDING")

        await viewModel.startService()

        XCTAssertTrue(viewModel.awaitingBlindConfirmation)
        XCTAssertFalse(viewModel.isTransitionPending, "不置灰：对方随时可能点，陪跑员要能再按")
        await viewModel.startService()
        XCTAssertEqual(service.callCount("startService(orderId:)"), 2, "第二次按下必须真的发出请求")
    }

    func testTooEarlyAnswerDoesNotClaimTheOtherPersonIsBeingAwaited() async {
        let (viewModel, _, _) = makeViewModel(startError: "SERVICE_START_TOO_EARLY")

        await viewModel.startService()

        XCTAssertFalse(viewModel.awaitingBlindConfirmation)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testConsentNotificationClearsTheWaitingCaptionAndRefetchesTheOrder() async throws {
        let (viewModel, service, socket) = makeViewModel(startError: "BLIND_CONFIRMATION_PENDING")
        await viewModel.startService()
        XCTAssertTrue(viewModel.awaitingBlindConfirmation)

        socket.simulateIncomingEventForTesting(.notification(Self.consentNotification()))
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(viewModel.awaitingBlindConfirmation)
        XCTAssertGreaterThanOrEqual(service.callCount("orderDetail(orderId:)"), 1, "收到点头后要立刻重拉订单")
    }

    func testWaitingCaptionIsDroppedWhenTheOrderLeavesTheArrivedState() async {
        let (viewModel, _, _) = makeViewModel(startError: "BLIND_CONFIRMATION_PENDING")
        await viewModel.startService()
        XCTAssertTrue(viewModel.awaitingBlindConfirmation)

        viewModel.order = Self.makeOrder(status: .inProgress)

        XCTAssertFalse(viewModel.awaitingBlindConfirmation)
    }

    // MARK: - Fixture

    private func makeViewModel(
        startError code: String
    ) -> (VolunteerInServiceViewModel, FakeOrderService, WebSocketService) {
        let order = Self.makeOrder(status: .driverArrived)
        let service = FakeOrderService()
        service.startServiceResult = .failure(APIError.serverError(ErrorResponse(code: code, message: "后端原文")))
        service.orderDetailResult = .success(order)
        let appState = AppState(orders: service)
        let socket = WebSocketService()
        appState.realtimeCoordinator.attach(to: socket, role: .volunteer)
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: order)
        return (viewModel, service, socket)
    }

    /// 信封**不带** `orderId`（`websocket-protocol.md`：这条是 2026-09-18 的事件，早于 orderId 约定）。
    private static func consentNotification() -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: 9_001,
            eventType: "BLIND_START_CONFIRMED",
            title: nil,
            body: "对方已确认，可以开始陪跑了",
            ttsText: nil,
            priority: "NORMAL",
            timestamp: "2026-10-02T12:00:00Z"
        )
    }

    private static func makeOrder(status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 4_307,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}
