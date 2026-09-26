import XCTest
@testable import blindRun

/// 跑者端接收陪跑员动作（issue #214，OpenSpec `runner-receives-volunteer-actions`）。
///
/// 播报的最后一跳（`speechService.speak`）在视图层；这里钉的是它之前的每一步：
/// 解析 → 能不能响 → 响多久 → 去重 → 起止，以及四类朗读事件不被吞掉。
/// 声音本身响不响、够不够大，只能真机人耳验。
@MainActor
final class RunnerVolunteerActionsTests: XCTestCase {

    private let formatter = DateFormatter.aidRunBackendLocalDateTime
    private let sentAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func ring(
        messageId: String? = "ring-1",
        ttsText: String? = "你的陪跑员到了，正在找你",
        until: String?
    ) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: messageId,
            eventType: "RUNNER_RING",
            title: nil,
            body: "你的陪跑员到了，正在找你",
            ttsText: ttsText,
            priority: "HIGH",
            timestamp: formatter.string(from: sentAt),
            orderId: 7,
            until: until
        )
    }

    private func until(after seconds: TimeInterval) -> String {
        formatter.string(from: sentAt.addingTimeInterval(seconds))
    }

    private func notification(_ eventType: String, text: String) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: UUID().uuidString,
            eventType: eventType,
            title: nil,
            body: text,
            ttsText: text,
            priority: "HIGH",
            timestamp: formatter.string(from: sentAt),
            orderId: 7
        )
    }

    // MARK: - 解析

    func testEnvelopeDecodesUntilAndToleratesAWrongType() throws {
        let good = #"{"type":"APP_NOTIFICATION","eventType":"RUNNER_RING","body":"b","orderId":7,"until":"2026-09-26T16:30:12.123"}"#
        XCTAssertEqual(
            try JSONDecoder().decode(WSAppNotification.self, from: Data(good.utf8)).until,
            "2026-09-26T16:30:12.123"
        )
        // `until` 类型不对不许连累整条。
        let bad = #"{"type":"APP_NOTIFICATION","eventType":"RUNNER_RING","body":"b","until":42}"#
        let decoded = try JSONDecoder().decode(WSAppNotification.self, from: Data(bad.utf8))
        XCTAssertNil(decoded.until)
        XCTAssertEqual(decoded.eventType, "RUNNER_RING")
    }

    // MARK: - 能不能响、响多久

    /// 本机时钟快了 100 秒：按服务端时钟算仍是 10 秒。拿「until − 本机 now」算的实现会得到 −90 ⇒ 不响。
    func testDurationUsesServerClockSoDeviceSkewDoesNotEatTheRing() throws {
        let receivedAt = sentAt.addingTimeInterval(100)
        let request = try XCTUnwrap(RunnerRingRequest.make(from: ring(until: until(after: 10)), receivedAt: receivedAt))
        XCTAssertEqual(request.endsAt.timeIntervalSince(receivedAt), 10, accuracy: 0.01)
        XCTAssertEqual(request.id, "ring-1")
    }

    func testUntilWithFractionalSecondsParses() {
        XCTAssertNotNil(RunnerRingRequest.make(from: ring(until: until(after: 10) + ".644571"), receivedAt: sentAt))
    }

    func testMissingOrPastUntilDoesNotRing() {
        XCTAssertNil(RunnerRingRequest.make(from: ring(until: nil), receivedAt: sentAt))
        XCTAssertNil(RunnerRingRequest.make(from: ring(until: "不是时间"), receivedAt: sentAt))
        XCTAssertNil(RunnerRingRequest.make(from: ring(until: until(after: -1)), receivedAt: sentAt))
    }

    func testAbsurdDurationIsCappedAtThirtySeconds() throws {
        // 服务端差值超出 (0, 60] ⇒ 退回本机时钟，再夹到 30 秒。
        let request = try XCTUnwrap(RunnerRingRequest.make(from: ring(until: until(after: 600)), receivedAt: sentAt))
        XCTAssertEqual(request.endsAt.timeIntervalSince(sentAt), RunnerRingRequest.maximumDuration, accuracy: 0.01)
    }

    func testSpeechFallsBackAndNeverSpeaksTheMaskAsterisk() throws {
        let masked = try XCTUnwrap(RunnerRingRequest.make(
            from: ring(ttsText: "陪跑员李*到了", until: until(after: 10)), receivedAt: sentAt
        ))
        XCTAssertEqual(masked.speechText, "陪跑员李到了")
        let noTts = try XCTUnwrap(RunnerRingRequest.make(from: ring(ttsText: nil, until: until(after: 10)), receivedAt: sentAt))
        XCTAssertEqual(noTts.speechText, "你的陪跑员到了，正在找你")
    }

    // MARK: - 协调器路由

    func testRunnerRingGoesToTheRingerNotTheBanner() async {
        let coordinator = AppRealtimeCoordinator(now: { [sentAt] in sentAt }, notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(ring(until: until(after: 10))))
        await Task.yield()

        XCTAssertEqual(coordinator.runnerRing?.id, "ring-1")
        XCTAssertNil(coordinator.currentNotification, "进横幅会让那句话被念两遍")
    }

    func testDuplicateRingIsDroppedButANewOneReplaces() async {
        let coordinator = AppRealtimeCoordinator(now: { [sentAt] in sentAt }, notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(ring(until: until(after: 10))))
        await Task.yield()
        coordinator.dismissRunnerRing()

        service.simulateIncomingEventForTesting(.notification(ring(until: until(after: 10))))
        await Task.yield()
        XCTAssertNil(coordinator.runnerRing, "同一 messageId 重投不许再响")

        service.simulateIncomingEventForTesting(.notification(ring(messageId: "ring-2", until: until(after: 10))))
        await Task.yield()
        XCTAssertEqual(coordinator.runnerRing?.id, "ring-2")
    }

    func testUnringableRingFallsBackToASpokenNotification() async {
        let coordinator = AppRealtimeCoordinator(now: { [sentAt] in sentAt }, notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(ring(until: nil)))
        await Task.yield()

        XCTAssertNil(coordinator.runnerRing)
        XCTAssertEqual(coordinator.currentNotification?.speechText, "你的陪跑员到了，正在找你")
    }

    func testVolunteerSessionNeverRings() async {
        let coordinator = AppRealtimeCoordinator(now: { [sentAt] in sentAt }, notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)

        service.simulateIncomingEventForTesting(.notification(ring(until: until(after: 10))))
        await Task.yield()
        XCTAssertNil(coordinator.runnerRing)
    }

    // MARK: - 迟到与快捷消息

    /// 走通用朗读通道，包括客户端没见过的新 `QUICK_MESSAGE_*`（契约：「直接朗读 ttsText 即可」）。
    func testLateAndQuickMessagesAreSpokenIncludingUnknownPresets() async {
        let cases = [
            ("VOLUNTEER_LATE", "陪跑员会晚到约8分钟"),
            ("VOLUNTEER_BACK_ON_TIME", "陪跑员能按时到了"),
            ("QUICK_MESSAGE_ALMOST_THERE", "陪跑员：我快到了"),
            ("QUICK_MESSAGE_WAIT_5_MIN", "陪跑员：再等我 5 分钟"),
            ("QUICK_MESSAGE_ARRIVED_AT_ENTRANCE", "陪跑员：我到入口了"),
            ("QUICK_MESSAGE_AT_GATE_B", "陪跑员：我在B门"),
        ]
        for (eventType, text) in cases {
            let coordinator = AppRealtimeCoordinator(now: { [sentAt] in sentAt }, notificationDuration: 60)
            let service = WebSocketService()
            coordinator.attach(to: service, role: .blind)

            service.simulateIncomingEventForTesting(.notification(notification(eventType, text: text)))
            await Task.yield()

            XCTAssertEqual(coordinator.currentNotification?.speechText, text, eventType)
            XCTAssertEqual(coordinator.currentNotification?.priority, .high, eventType)
            // 进了生命周期表就会在有活跃订单时被 100% 吞掉。
            XCTAssertNil(AppRealtimeCoordinator.lifecycleStatus(forEventType: eventType), eventType)
        }
    }

    // MARK: - 响铃起止

    private final class Recorder {
        var events: [String] = []
        var speaking = false
    }

    private func controller(_ recorder: Recorder) -> RunnerRingController {
        let controller = RunnerRingController()
        controller.speak = { recorder.events.append("speak:\($0)") }
        controller.isSpeaking = { recorder.speaking }
        controller.startTone = { recorder.events.append("start") }
        controller.stopTone = { recorder.events.append("stop") }
        controller.onFinish = { recorder.events.append("finish") }
        return controller
    }

    private func request(id: String = "r1", lasting seconds: TimeInterval) -> RunnerRingRequest {
        RunnerRingRequest(id: id, orderId: 7, speechText: "到了", endsAt: Date().addingTimeInterval(seconds))
    }

    func testRingSpeaksThenLoopsUntilEndsAtThenStops() async throws {
        let recorder = Recorder()
        let controller = controller(recorder)
        controller.handle(request(lasting: 0.4))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recorder.events, ["stop", "speak:到了", "start"])
        XCTAssertNotNil(controller.active)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(recorder.events, ["stop", "speak:到了", "start", "stop", "finish"])
        XCTAssertNil(controller.active)
    }

    /// 同时起的话铃声会盖住那句话：念完才响。
    func testToneWaitsForTheSpeechToFinish() async throws {
        let recorder = Recorder()
        recorder.speaking = true
        let controller = controller(recorder)
        controller.handle(request(lasting: 2))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(recorder.events.contains("start"), "还在念就不许响")

        recorder.speaking = false
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(recorder.events.contains("start"))
        controller.stop()
    }

    func testStopEndsImmediatelyAndTheLateTimerDoesNothing() async throws {
        let recorder = Recorder()
        let controller = controller(recorder)
        controller.handle(request(lasting: 0.3))
        try await Task.sleep(nanoseconds: 100_000_000)
        controller.stop()
        XCTAssertEqual(Array(recorder.events.suffix(2)), ["stop", "finish"])
        XCTAssertNil(controller.active)

        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(recorder.events.filter { $0 == "finish" }.count, 1, "被按停之后到点不许再收尾一次")
    }

    /// `@Published` 重新订阅会回放当前值 —— 同一 id 与已过点的都不许再响。
    func testReplayedOrExpiredRingIsIgnored() async throws {
        let recorder = Recorder()
        let controller = controller(recorder)
        let ring = request(lasting: 1)
        controller.handle(ring)
        try await Task.sleep(nanoseconds: 50_000_000)
        controller.stop()
        controller.handle(ring)
        controller.handle(request(id: "old", lasting: -1))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(recorder.events.filter { $0.hasPrefix("speak") }.count, 1)
        XCTAssertNil(controller.active)
    }

    func testNewRingWhileRingingRestartsWithTheNewDeadline() async throws {
        let recorder = Recorder()
        let controller = controller(recorder)
        controller.handle(request(id: "a", lasting: 0.3))
        try await Task.sleep(nanoseconds: 100_000_000)
        controller.handle(request(id: "b", lasting: 0.6))
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(controller.active?.id, "b", "旧的那条到点不许把新的一起收掉")
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(controller.active)
        XCTAssertEqual(recorder.events.filter { $0 == "finish" }.count, 1)
    }

    // MARK: - 引导偏好

    func testGuidePreferenceIsAlwaysSentTrimmedSoClearingWorks() throws {
        let viewModel = BlindRunnerProfileViewModel()
        viewModel.name = "跑者"
        viewModel.guidePreferenceText = "  我习惯你在我左边  "
        XCTAssertEqual(viewModel.makeProfileUpdateRequest().guidePreferenceText, "我习惯你在我左边")

        viewModel.guidePreferenceText = "   "
        let cleared = viewModel.makeProfileUpdateRequest()
        XCTAssertEqual(cleared.guidePreferenceText, "", "带 nil 等于保留原值，用户删光了却删不掉")
        let json = String(decoding: try JSONEncoder().encode(cleared), as: UTF8.self)
        XCTAssertTrue(json.contains(#""guidePreferenceText":"""#), json)
    }

    /// 边界取在 80 / 81，再用 emoji 区分「按 UTF-16 数」与「按字素数」：41 个 emoji 的 count 是 41、UTF-16 是 82。
    func testGuidePreferenceLimitCountsUTF16AtTheBoundary() {
        let viewModel = BlindRunnerProfileViewModel()
        viewModel.guidePreferenceText = String(repeating: "左", count: 80)
        XCTAssertNil(viewModel.guidePreferenceLengthError)
        viewModel.guidePreferenceText = String(repeating: "左", count: 81)
        XCTAssertNotNil(viewModel.guidePreferenceLengthError)
        viewModel.guidePreferenceText = String(repeating: "🏃", count: 41)
        XCTAssertNotNil(viewModel.guidePreferenceLengthError, "按 count 数会放行，后端会 400")
    }

    // MARK: - 出发前留言

    func testRunnerMessageIsWritableExactlyInTheFourContractStates() {
        let writable = Set(RunOrderStatus.allCases.filter(\.acceptsRunnerMessage))
        XCTAssertEqual(writable, [.scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived])
    }

    func testRunnerMessageEndpointIsAPut() {
        let request = OrderEndpoint.runnerMessage(orderId: 42).request
        XCTAssertEqual(request.method, .put)
        XCTAssertEqual(request.path, "/api/orders/42/runner-message")
    }

    private func enRouteOrder() throws -> OrderDetailResponse {
        try JSONDecoder().decode(
            OrderDetailResponse.self,
            from: Data(#"{"orderId":88,"status":"DRIVER_EN_ROUTE"}"#.utf8)
        )
    }

    func testSavingARunnerMessageSendsTrimmedTextAndUpdatesTheRowAtOnce() async throws {
        let service = FakeOrderService()
        service.runnerMessageResult = .success(RunnerMessageResponse(messageToVolunteer: "我穿红色外套"))
        let appState = AppState(orders: service)
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = try enRouteOrder()

        let error = await viewModel.saveRunnerMessage("  我穿红色外套 ")

        XCTAssertNil(error)
        XCTAssertEqual(service.lastRunnerMessageText, "我穿红色外套")
        XCTAssertEqual(service.lastOrderId, 88)
        XCTAssertEqual(viewModel.order?.messageToVolunteer, "我穿红色外套")
    }

    func testOverlongRunnerMessageIsStoppedBeforeTheNetwork() async throws {
        let service = FakeOrderService()
        let fine = String(repeating: "红", count: 40)
        service.runnerMessageResult = .success(RunnerMessageResponse(messageToVolunteer: fine))
        let appState = AppState(orders: service)
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = try enRouteOrder()

        let okError = await viewModel.saveRunnerMessage(fine)
        XCTAssertNil(okError)
        let error = await viewModel.saveRunnerMessage(String(repeating: "红", count: 41))
        XCTAssertNotNil(error)
        XCTAssertEqual(service.callCount("updateRunnerMessage(_:orderId:)"), 1, "超长的那次不许发出去")
    }

    func testRunnerMessageFailureIsReturnedForTheSheetToShow() async throws {
        let service = FakeOrderService()
        service.runnerMessageResult = .failure(APIError.serverError(
            ErrorResponse(code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作")
        ))
        let appState = AppState(orders: service)
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = try enRouteOrder()

        let error = await viewModel.saveRunnerMessage("我到了")
        XCTAssertNotNil(error)
        XCTAssertNil(viewModel.order?.messageToVolunteer)
    }
}
