import XCTest
@testable import blindRun

/// 半路退出从通知、轮询到播报的接线（#653）。判定与文案在 `BlindMidRunDepartureTests`。
@MainActor
final class BlindMidRunDepartureWiringTests: XCTestCase {

    private static let suiteName = "BlindMidRunDepartureWiringTests"
    private var defaults: UserDefaults!
    private var record: BlindMidRunDepartureRecord!
    private var originalRecord: BlindMidRunDepartureRecord!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
        record = BlindMidRunDepartureRecord(defaults: defaults)
        originalRecord = BlindMidRunDepartureRecord.shared
        BlindMidRunDepartureRecord.shared = record
        // 接管提示音与震动：`.alert` 档每句都会响一次。
        AnnouncementCue.observerForTesting = { _ in }
    }

    override func tearDown() {
        AnnouncementCue.observerForTesting = nil
        BlindMidRunDepartureRecord.shared = originalRecord
        defaults.removePersistentDomain(forName: Self.suiteName)
        super.tearDown()
    }

    // MARK: - 播报接线

    /// WebSocket 断着时轮询是唯一通道：这一句要走警示档，通话中也不能丢。
    func testPollingAloneStillSpeaksDuringACall() {
        record.observe(orderID: 7, status: .inProgress)
        let service = VoiceService()
        service.isCallActive = { true }
        service.resetSpokenHistoryForTesting()
        let order = OrderDetailResponse.preview(orderId: 7, status: .rematching)

        service.speakBlindRunnerStatusChange(order, text: order.blindRunnerAnnouncement())

        XCTAssertEqual(service.spokenHistoryForTesting, [BlindMidRunDepartureCopy.announcement])
        service.stop()
    }

    /// 通用状态走默认档，通话中照旧被丢。用来分辨「所有状态都提档」这种过宽的实现。
    func testOrdinaryStatusChangeStaysOnTheDefaultPriority() {
        let service = VoiceService()
        service.isCallActive = { true }
        service.resetSpokenHistoryForTesting()
        let order = OrderDetailResponse.preview(orderId: 7, status: .pendingAccept)

        service.speakBlindRunnerStatusChange(order, text: "状态句")

        XCTAssertTrue(service.spokenHistoryForTesting.isEmpty)
        service.stop()
    }

    /// 后端先发通知、再发状态：横幅那条已经在念，订单页不再重复一遍。
    func testStatusChangeStaysSilentOnceTheAlertArrived() async {
        record.observe(orderID: 7, status: .inProgress)
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let socket = WebSocketService()
        coordinator.attach(to: socket, role: .blind)
        coordinator.registerActiveOrder(7)
        socket.simulateIncomingEventForTesting(.notification(Self.midRunNotification))
        await Task.yield()

        let service = VoiceService()
        service.isCallActive = { false }
        service.resetSpokenHistoryForTesting()
        let order = OrderDetailResponse.preview(orderId: 7, status: .rematching)

        XCTAssertFalse(
            service.speakBlindRunnerStatusChange(order, text: order.blindRunnerAnnouncement())
        )
        XCTAssertTrue(service.spokenHistoryForTesting.isEmpty)
        XCTAssertEqual(service.lastSpokenStatus, .rematching, "要记下去重键，否则首页随后会把这件事再念一遍")
    }

    /// 只抵一次：换人后再次退出而通知没送达时，订单页必须自己念。
    func testAlertOnlySilencesOneStatusChange() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let socket = WebSocketService()
        coordinator.attach(to: socket, role: .blind)
        coordinator.registerActiveOrder(7)
        socket.simulateIncomingEventForTesting(.notification(Self.midRunNotification))
        await Task.yield()

        let service = VoiceService()
        service.isCallActive = { false }
        service.resetSpokenHistoryForTesting()
        let order = OrderDetailResponse.preview(orderId: 7, status: .rematching)

        XCTAssertFalse(service.speakBlindRunnerStatusChange(order, text: "第一次"))
        service.resetLastStatus()
        XCTAssertTrue(service.speakBlindRunnerStatusChange(order, text: "第二次"))
        XCTAssertEqual(service.spokenHistoryForTesting, ["第二次"])
        service.stop()
    }

    /// 手机错过了同行三态时，通知本身也要能让页面换成半路退出的文案。
    func testAlertAloneMarksTheOrderAsLeftMidRun() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let socket = WebSocketService()
        coordinator.attach(to: socket, role: .blind)
        coordinator.registerActiveOrder(7)

        socket.simulateIncomingEventForTesting(.notification(Self.midRunNotification))
        await Task.yield()

        XCTAssertTrue(OrderDetailResponse.preview(orderId: 7, status: .rematching).blindRunnerLeftAloneMidRun)
    }

    /// 两张活跃订单时认不出是哪一单：宁可退回通用句，也不能把别的单说成没人陪。
    func testAlertWithoutOrderIDIsIgnoredWhenTwoOrdersAreActive() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let socket = WebSocketService()
        coordinator.attach(to: socket, role: .blind)
        coordinator.registerActiveOrder(7)
        coordinator.registerActiveOrder(8)

        socket.simulateIncomingEventForTesting(.notification(Self.midRunNotification))
        await Task.yield()

        XCTAssertFalse(OrderDetailResponse.preview(orderId: 7, status: .rematching).blindRunnerLeftAloneMidRun)
        XCTAssertFalse(OrderDetailResponse.preview(orderId: 8, status: .rematching).blindRunnerLeftAloneMidRun)
    }

    /// 补读的通知带 `orderId`，与实时那条走同一个判定。
    func testCatchUpMarksTheOrderFromItsOwnOrderID() {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        coordinator.ingestCatchUp([
            MissedNotificationResponse(
                id: 9001,
                eventType: "REMATCHING_MID_RUN",
                body: "现在只有您一个人。",
                ttsText: nil,
                priority: "HIGH",
                sentAt: "2026-11-02T12:00:00Z",
                orderId: 7
            )
        ])
        XCTAssertTrue(OrderDetailResponse.preview(orderId: 7, status: .rematching).blindRunnerLeftAloneMidRun)
    }

    /// 补读窗口有 24 小时，不带订单号的旧通知可能属于上一单，不能记到当前这一单头上。
    func testCatchUpWithoutOrderIDDoesNotGuessTheActiveOrder() {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        coordinator.registerActiveOrder(7)
        coordinator.ingestCatchUp([
            MissedNotificationResponse(
                id: 9002,
                eventType: "REMATCHING_MID_RUN",
                body: "现在只有您一个人。",
                ttsText: nil,
                priority: "HIGH",
                sentAt: "2026-11-02T12:00:00Z",
                orderId: nil
            )
        ])
        XCTAssertFalse(OrderDetailResponse.preview(orderId: 7, status: .rematching).blindRunnerLeftAloneMidRun)
    }

    // MARK: - 真实调用点

    /// 从 `updateOwnedOrder` 这个漏斗走，不直接调 `observe`：删掉那一行时这条要红。
    func testSharedOrderFunnelFeedsTheRecord() {
        let coordinator = LiveEscortSessionCoordinator(realtimeCoordinator: AppRealtimeCoordinator())
        coordinator.updateOwnedOrder(orderID: 7, status: .inProgress)
        XCTAssertTrue(OrderDetailResponse.preview(orderId: 7, status: .rematching).blindRunnerLeftAloneMidRun)
    }

    /// 订单页真实轮询：通话中转入 `REMATCHING` 也要念出来。默认档的实现在这里一个字都不会念。
    func testOrderPagePollingSpeaksTheDepartureDuringACall() async {
        let orders = FakeOrderService()
        orders.orderDetailResult = .success(.preview(orderId: 71, status: .inProgress, volunteerName: "张*"))
        let appState = AppState(safety: FakeSafetyService(), orders: orders)
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        speech.isCallActive = { true }
        speech.resetSpokenHistoryForTesting()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)

        viewModel.startPolling(orderId: 71)
        await Self.waitUntil(timeout: 3) { viewModel.order != nil }
        orders.orderDetailResult = .success(.preview(orderId: 71, status: .rematching))
        await Self.waitUntil(timeout: AppConstants.Timing.orderPollingInterval * 2 + 3) {
            viewModel.order?.status == .rematching
        }
        viewModel.stopPolling()

        XCTAssertTrue(
            speech.spokenHistoryForTesting.contains(BlindMidRunDepartureCopy.announcement),
            "实际：\(speech.spokenHistoryForTesting)"
        )
        speech.stop()
    }

    /// 首页也活着，且与订单页共用去重键：它若用默认档先念，订单页就再也念不出来。
    func testHomePageSpeaksTheDepartureDuringACall() {
        record.observe(orderID: 72, status: .inProgress)
        let speech = SpeechService()
        speech.isCallActive = { true }
        speech.resetSpokenHistoryForTesting()
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: AppState(), speechService: speech)
        viewModel.activeOrder = .preview(orderId: 72, status: .rematching)

        viewModel.speakCurrentStatus()

        XCTAssertEqual(speech.spokenHistoryForTesting.count, 1)
        XCTAssertTrue(speech.spokenHistoryForTesting.first?.hasPrefix(BlindMidRunDepartureCopy.announcement) == true)
        speech.stop()
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await MainActor.run(body: condition) { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - 通知的播报档位

    func testSafetyNotificationsUseTheAlertPriority() {
        XCTAssertEqual(notification(isSafetyEvent: true).announcementPriority, .alert)
        XCTAssertEqual(notification(isSafetyEvent: false).announcementPriority, .counterpartAction)
    }

    /// 从推送一路到档位：`isSafetyEvent` 没接上时，上面那条照样绿。
    func testMidRunNotificationReachesTheAlertPriority() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let socket = WebSocketService()
        coordinator.attach(to: socket, role: .blind)
        coordinator.registerActiveOrder(7)

        socket.simulateIncomingEventForTesting(.notification(Self.midRunNotification))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.announcementPriority, .alert)
    }

    // MARK: - 辅助

    private func notification(isSafetyEvent: Bool) -> RealtimeForegroundNotification {
        RealtimeForegroundNotification(
            stableEventID: "1",
            title: nil,
            displayText: "文本",
            speechText: "文本",
            priority: .high,
            timestamp: nil,
            isSafetyEvent: isSafetyEvent
        )
    }

    private static let midRunNotification = WSAppNotification(
        type: WSMessageType.appNotification.rawValue,
        eventId: nil,
        messageId: "mid-run-653",
        eventType: "REMATCHING_MID_RUN",
        title: "重新匹配中",
        body: "您的陪跑志愿者已取消服务，现在只有您一个人。",
        ttsText: nil,
        priority: "HIGH",
        timestamp: "2026-11-02T12:00:00Z"
    )
}
