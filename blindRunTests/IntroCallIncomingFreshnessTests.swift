import XCTest
@testable import blindRun

/// 过期的「跑者正在来电」不进横幅、不念（#448）。
///
/// 这条提醒只在 2 分钟内有意义。陪跑员不在通话页时（例如在首页），离线 10 分钟后重连，
/// 补读会把那条早已过期的「跑者正在打给你」照常放进横幅并朗读 —— 让人以为跑者此刻在打电话。
/// 判据与通话页（`VolunteerIntroCallViewModel.noteIncomingCall`）是同一条：后端发出时刻 + 2 分钟。
@MainActor
final class IntroCallIncomingFreshnessTests: XCTestCase {
    private static let body = "跑者正在打给你，请留意来电"

    /// 119 秒前的还算，121 秒前的不算：把窗口写成 3 分钟或忘了判的实现在 121 那条上红。
    func testFreshnessWindowIsTwoMinutesFromTheBackendSendTime() {
        let now = Date()
        XCTAssertNotNil(IntroCallCopy.incomingCallDisplayUntil(sentAt: now.addingTimeInterval(-119), now: now))
        XCTAssertNil(IntroCallCopy.incomingCallDisplayUntil(sentAt: now.addingTimeInterval(-121), now: now))
        XCTAssertEqual(
            IntroCallCopy.incomingCallDisplayUntil(sentAt: now.addingTimeInterval(30), now: now), now.addingTimeInterval(120),
            "发出时刻晚于本机现在（时钟偏差）按现在算，免得挂得比 2 分钟还久"
        )
    }

    /// 实时推送：页面不在时，10 分钟前发出的不进横幅；刚发出的照旧进。
    func testStaleLiveIncomingCallSkipsTheBannerWhenTheCallPageIsClosed() async {
        let (coordinator, service) = makeCoordinator()

        service.simulateIncomingEventForTesting(.notification(Self.live(sentSecondsAgo: 600)))
        await Task.yield()
        XCTAssertNil(coordinator.currentNotification, "10 分钟前的来电提醒不该进横幅")

        service.simulateIncomingEventForTesting(.notification(Self.live(sentSecondsAgo: 5)))
        await Task.yield()
        XCTAssertEqual(coordinator.currentNotification?.displayText, Self.body, "刚发出的照旧走横幅")
    }

    /// 重连补读（issue 描述的那条路）：同一条判据。
    func testStaleCaughtUpIncomingCallSkipsTheBanner() {
        let (coordinator, _) = makeCoordinator()

        coordinator.ingestCatchUp([Self.missed(id: 1, sentSecondsAgo: 600)])
        XCTAssertNil(coordinator.currentNotification, "补读来的 10 分钟前的来电提醒不该进横幅")

        coordinator.ingestCatchUp([Self.missed(id: 2, sentSecondsAgo: 5)])
        XCTAssertEqual(coordinator.currentNotification?.displayText, Self.body)
    }

    /// 补读的 `sentAt` 可能是带时区的 ISO-8601（与 WS 信封的无时区 LocalDateTime 不同）。解不出来会按「刚刚」算，
    /// 修复就静默失效 —— 这里钉住那种格式也能判出过期（复核 B）。
    func testCaughtUpTimestampInIso8601WithZoneIsStillJudgedByItsSendTime() {
        let (coordinator, _) = makeCoordinator()
        let tenMinutesAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600))
        coordinator.ingestCatchUp([MissedNotificationResponse(
            id: 3, eventType: "INTRO_CALL_INCOMING", body: Self.body, ttsText: nil, priority: "HIGH", sentAt: tenMinutesAgo, orderId: nil
        )])
        XCTAssertNil(coordinator.currentNotification, "带时区的 10 分钟前时刻被当成了「刚刚」")
    }

    // MARK: - Fixture

    private func makeCoordinator() -> (AppRealtimeCoordinator, WebSocketService) {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        return (coordinator, service)
    }

    private static func timestamp(secondsAgo: TimeInterval) -> String {
        DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(-secondsAgo))
    }

    private static func live(sentSecondsAgo: TimeInterval) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue, eventId: Int64.random(in: 1...1_000_000),
            eventType: "INTRO_CALL_INCOMING", title: nil, body: body,
            ttsText: nil, priority: "HIGH", timestamp: timestamp(secondsAgo: sentSecondsAgo)
        )
    }

    private static func missed(id: Int64, sentSecondsAgo: TimeInterval) -> MissedNotificationResponse {
        MissedNotificationResponse(
            id: id, eventType: "INTRO_CALL_INCOMING", body: body, ttsText: nil, priority: "HIGH",
            sentAt: timestamp(secondsAgo: sentSecondsAgo), orderId: nil
        )
    }
}
