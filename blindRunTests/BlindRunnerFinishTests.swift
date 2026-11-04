import XCTest
@testable import blindRun

/// 跑步中跑者自己的出路（#660 B-4 / F-10、F-20，#682）。
///
/// 结束动作的判据在后端（陪跑员掉线 5 分钟才放行），客户端要守的是：按下去真的调 `finish`、
/// 409 时念的是后端那句带时刻的原话、成功后完成句不说成「陪跑员结束了」。
@MainActor
final class BlindRunnerFinishTests: XCTestCase {

    private static let finalStats = TrackStats(distanceMeters: 5_204, durationSeconds: 2_021, avgPaceSecPerKm: 388)

    override func tearDown() {
        for orderID in [Self.orderId, Self.otherOrderId] { BlindRunnerFinishRecord.unmark(orderID) }
        super.tearDown()
    }

    // MARK: - 结束动作

    func testRunnerFinishCallsTheEndpointAndSaysTheRunnerEndedIt() async {
        let fixture = makeFixture(current: .inProgress)
        fixture.orders.orderDetailResult = .success(Self.order(status: .completed))

        let refusal = await fixture.viewModel.finishBecauseVolunteerUnreachable()
        await Self.waitUntil { fixture.speech.spokenHistoryForTesting.count >= 2 }

        XCTAssertNil(refusal, "成功时返回 nil，求助中心据此关弹层")

        XCTAssertEqual(fixture.orders.callCount("finish(orderId:)"), 1)
        XCTAssertEqual(fixture.orders.lastOrderId, Self.orderId)
        XCTAssertEqual(fixture.viewModel.order?.status, .completed)
        XCTAssertEqual(
            fixture.speech.spokenHistoryForTesting,
            [BlindRunnerFinishCopy.finishingAnnouncement, "你已结束本次陪跑，共跑 5.20 公里。"],
            "跑者自己结束的单，完成句不能说成「张结束了本次陪跑」"
        )
    }

    /// 409 `VOLUNTEER_STILL_ONLINE`：后端 message 带最早可结束的时刻，原样念、原样显示，订单不动。
    func testVolunteerStillOnlineReadsTheServerMessageVerbatim() async {
        let fixture = makeFixture(current: .inProgress)
        let serverMessage = "陪跑员的手机还在线，请先打电话联系对方；若一直联系不上，9月19日 10:20 之后可以由您结束"
        fixture.orders.finishResult = .failure(APIError.serverError(
            ErrorResponse(code: "VOLUNTEER_STILL_ONLINE", message: serverMessage)
        ))

        let refusal = await fixture.viewModel.finishBecauseVolunteerUnreachable()

        XCTAssertEqual(refusal, serverMessage, "求助中心靠这个返回值把原话留在按钮下面")
        XCTAssertEqual(fixture.viewModel.errorMessage, serverMessage)
        XCTAssertEqual(fixture.speech.spokenHistoryForTesting.last, serverMessage)
        XCTAssertEqual(fixture.viewModel.order?.status, .inProgress)
        XCTAssertFalse(fixture.viewModel.isPerformingAction)
        XCTAssertFalse(
            BlindRunnerFinishRecord.finishedByRunner.contains(Self.orderId),
            "失败要撤销记录，否则之后陪跑员结束时会被说成跑者结束"
        )
    }

    /// 网络断在半路：请求可能已经生效，记录不撤销，免得之后说成「陪跑员结束了本次陪跑」。
    func testNetworkFailureKeepsTheRunnerEndedRecord() async {
        let fixture = makeFixture(current: .inProgress)
        fixture.orders.finishResult = .failure(APIError.networkError(URLError(.timedOut)))

        let refusal = await fixture.viewModel.finishBecauseVolunteerUnreachable()

        XCTAssertNotNil(refusal)
        XCTAssertTrue(BlindRunnerFinishRecord.finishedByRunner.contains(Self.orderId))
    }

    func testVolunteerStillOnlineWithBlankMessageFallsBackToLocalSentence() {
        let error = APIError.serverError(ErrorResponse(code: "VOLUNTEER_STILL_ONLINE", message: "  "))
        XCTAssertEqual(
            BlindOrderStatusViewModel.runnerFinishFailureMessage(for: error),
            BlindRunnerFinishCopy.stillOnlineFallback
        )
    }

    /// 通用文案是写给陪跑员的（「需要跑者本人撤销」），跑者听到会不知道说的是谁。
    func testActiveEmergencyUsesTheRunnerWording() {
        let error = APIError.serverError(ErrorResponse(code: "ORDER_HAS_ACTIVE_EMERGENCY", message: "x"))
        let message = BlindOrderStatusViewModel.runnerFinishFailureMessage(for: error)
        XCTAssertEqual(message, BlindRunnerFinishCopy.activeEmergency)
        XCTAssertFalse(message.contains("跑者本人"), message)
    }

    func testFinishIsNotSentOutsideTheRun() async {
        let fixture = makeFixture(current: .driverArrived)
        let refusal = await fixture.viewModel.finishBecauseVolunteerUnreachable()
        XCTAssertEqual(fixture.orders.callCount("finish(orderId:)"), 0)
        XCTAssertEqual(refusal, BlindRunnerFinishCopy.notRunning)
    }

    // MARK: - 完成句

    func testCompletionSentenceDependsOnWhoEndedTheRun() {
        let order = Self.order(status: .completed)
        let byVolunteer = BlindOrderStatusViewModel.completionText(.justFinished, order: order, stats: Self.finalStats)
        XCTAssertEqual(byVolunteer, "张结束了本次陪跑，共跑 5.20 公里。")

        BlindRunnerFinishRecord.mark(Self.orderId)
        XCTAssertEqual(
            BlindOrderStatusViewModel.completionText(.justFinished, order: order, stats: nil),
            "你已结束本次陪跑。"
        )
        let other = OrderDetailResponse.preview(orderId: Self.otherOrderId, status: .completed, volunteerName: "张*")
        XCTAssertEqual(
            BlindOrderStatusViewModel.completionText(.justFinished, order: other, stats: nil),
            "张结束了本次陪跑。",
            "记录按订单号算，别的单不受影响"
        )
    }

    // MARK: - 求助中心里的那一段

    func testEndRunAppearsOnlyDuringTheRunWithAValidSession() {
        XCTAssertTrue(SafetyHubRunSection.showsEndRun(mode: .cloudTrigger, hasAction: true))
        XCTAssertFalse(SafetyHubRunSection.showsEndRun(mode: .cloudTrigger, hasAction: false))
        XCTAssertFalse(SafetyHubRunSection.showsEndRun(mode: .localCall, hasAction: true), "跑步前后后端不收")
        XCTAssertFalse(
            SafetyHubRunSection.showsEndRun(mode: .localCallSessionExpired, hasAction: true),
            "登录过期时 finish 必然 401"
        )
    }

    /// 走「视图里存的闭包」这条路：未标隔离的 async 闭包属性只在经闭包调用时真机崩
    /// （记忆 `unannotated-async-closure-property-crashes-on-device`），直调 view model 抓不到。
    func testEndRunThroughTheSectionClosureDeliversTheServerRefusal() async throws {
        let fixture = makeFixture(current: .inProgress)
        fixture.orders.finishResult = .failure(APIError.serverError(
            ErrorResponse(code: "VOLUNTEER_STILL_ONLINE", message: "10:20 之后可以由您结束")
        ))
        let section = SafetyHubRunSection(mode: .cloudTrigger) { await fixture.viewModel.finishBecauseVolunteerUnreachable() }

        let refusal = try await XCTUnwrap(section.onEndRun)()

        XCTAssertEqual(refusal, "10:20 之后可以由您结束")
        XCTAssertEqual(fixture.orders.callCount("finish(orderId:)"), 1)
    }

    func testVolunteerUnwellGuideAppearsWheneverTheRunIsOn() {
        XCTAssertTrue(SafetyHubRunSection.showsGuide(mode: .cloudTrigger))
        XCTAssertTrue(SafetyHubRunSection.showsGuide(mode: .localCallSessionExpired))
        XCTAssertFalse(SafetyHubRunSection.showsGuide(mode: .localCall))
    }

    /// 三步的先后是审计 F-20 定的，指引里提到的「播报我的位置」必须是求助中心里真有的那一格。
    func testVolunteerUnwellStepsComeInOrderAndNameARealTile() throws {
        let steps = BlindRunnerFinishCopy.volunteerUnwellSteps
        let call = try XCTUnwrap(steps.range(of: "120"))
        let locate = try XCTUnwrap(steps.range(of: EmergencySafetyCopy.hubAnnounceLocationTitle))
        let contact = try XCTUnwrap(steps.range(of: "紧急联系人"))
        XCTAssertLessThan(call.lowerBound, locate.lowerBound)
        XCTAssertLessThan(locate.lowerBound, contact.lowerBound)
    }

    // MARK: - ORDER_OVERDUE

    func testOverdueAlertForTheRunnerNamesTheRunnerSideExit() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(Self.overdueNotification(
            body: "本次陪跑已超过约定结束时间。如果一切正常，请让志愿者点击结束服务；如果联系不上志愿者，可以按下求助。"
        )))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, BlindRunnerFinishCopy.overdueForRunner)
        XCTAssertEqual(coordinator.currentNotification?.speechText, BlindRunnerFinishCopy.overdueForRunner)
        XCTAssertFalse(BlindRunnerFinishCopy.overdueForRunner.contains("点击结束服务"))
    }

    func testOverdueAlertForTheVolunteerKeepsTheServerText() async {
        let body = "您有一个订单已超过约定结束时间。如果服务已经结束，请点击结束服务；如果联系不上跑者，请按下求助。"
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)

        service.simulateIncomingEventForTesting(.notification(Self.overdueNotification(body: body)))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.speechText, body)
    }

    // MARK: - #682 开跑时的系统 SOS 提醒

    /// 不暗示 App 会代为求助（`AGENTS.md` §6），按法只写苹果文档写明的那一种。
    func testSystemSOSReminderSaysTheAppDoesNotSendHelp() {
        let reminder = BlindRunnerFinishCopy.systemSOSReminder
        XCTAssertTrue(reminder.contains("侧边按钮"))
        XCTAssertTrue(reminder.contains("App 不会代你发送求助"))
        for forbidden in ["已通知", "会通知", "已发出", "按五次"] {
            XCTAssertFalse(reminder.contains(forbidden), "不该出现「\(forbidden)」")
        }
    }

    /// 倒计时走完：先「开始跑步」，再提醒，提醒不能把「开始跑步」切断。
    func testRunStartCountdownQueuesTheReminderAfterTheStartCue() async {
        let fixture = makeFixture(current: .driverArrived)
        fixture.orders.orderDetailResult = .success(Self.order(status: .inProgress))

        fixture.viewModel.startPolling(orderId: Self.orderId)
        await Self.waitUntil(timeout: 20) {
            fixture.speech.spokenHistoryForTesting.contains(BlindRunnerFinishCopy.systemSOSReminder)
        }
        fixture.viewModel.stopPolling()

        let spoken = fixture.speech.spokenHistoryForTesting
        let start = spoken.firstIndex(of: BlindRunCopy.runStartedAnnouncement)
        let reminder = spoken.firstIndex(of: BlindRunnerFinishCopy.systemSOSReminder)
        XCTAssertNotNil(start, "倒计时没走完：\(spoken)")
        XCTAssertNotNil(reminder, "没有提醒：\(spoken)")
        if let start, let reminder { XCTAssertLessThan(start, reminder, "\(spoken)") }
        XCTAssertEqual(spoken.filter { $0 == BlindRunnerFinishCopy.systemSOSReminder }.count, 1)
    }

    // MARK: - 辅助

    private static let orderId: Int64 = 9_660
    private static let otherOrderId: Int64 = 9_661

    private struct Fixture {
        /// view model 对它是 `weak`，fixture 不持有就会被释放（guard `weak-helper`）。
        let appState: AppState
        let orders: FakeOrderService
        let speech: SpeechService
        let viewModel: BlindOrderStatusViewModel
    }

    private func makeFixture(current status: RunOrderStatus) -> Fixture {
        let orders = FakeOrderService()
        let safety = FakeSafetyService()
        safety.orderTrackResult = .success(OrderTrackResponse(
            status: .completed,
            volunteerTrack: [],
            volunteerStats: TrackStats(distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil),
            blindTrack: [],
            blindStats: Self.finalStats
        ))
        let appState = AppState(safety: safety, orders: orders)
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = Self.order(status: status)
        return Fixture(appState: appState, orders: orders, speech: speech, viewModel: viewModel)
    }

    private static func order(status: RunOrderStatus) -> OrderDetailResponse {
        .preview(orderId: orderId, status: status, volunteerName: "张*", volunteerPhone: "13800000001")
    }

    private static func overdueNotification(body: String) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: 66_001,
            eventType: "ORDER_OVERDUE",
            title: "本次陪跑已超过约定结束时间",
            body: body,
            ttsText: body,
            priority: "HIGH",
            timestamp: "2026-11-04T12:00:00Z"
        )
    }

    private static func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: condition) { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
