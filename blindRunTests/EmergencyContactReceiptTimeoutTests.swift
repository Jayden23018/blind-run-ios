import XCTest
@testable import blindRun

/// `EMERGENCY_CONTACT_RECEIPT_TIMEOUT`（后端 #898，本仓库 #663）：联系人短信发出约 3 分钟仍无运营商回执，发给受助者。
///
/// 形状与 `EMERGENCY_UNATTENDED` 相同：催办，不是新事实。所以只进安全提醒的呈现，
/// 不进 `emergencyKind`（那条链路会改求助状态机）。
/// 🚨 它**不是**投递失败 —— 之后仍可能收到 `EMERGENCY_CONTACT_SMS_DELIVERED`。
@MainActor
final class EmergencyContactReceiptTimeoutTests: XCTestCase {
    private static let eventType = "EMERGENCY_CONTACT_RECEIPT_TIMEOUT"
    /// 后端 `docs/websocket-protocol.md` 的模板；`ttsText` 与 `body` 同文。
    private static let backendText = "还没确认李阿姨收到求助短信。情况危急请拨110或120"

    func testIsPresentedAsASafetyEvent() async {
        XCTAssertTrue(AppRealtimeCoordinator.isSafetyEventType(Self.eventType))

        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        service.simulateIncomingEventForTesting(.notification(makeNotification()))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, true)
        XCTAssertEqual(coordinator.currentNotification?.priority, .high)
    }

    /// 前台收到时朗读后端的 `ttsText`，一个字不改、不补「已通知」。
    func testSpeaksTheBackendTextVerbatim() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        service.simulateIncomingEventForTesting(.notification(makeNotification()))
        await Task.yield()

        let spoken = coordinator.currentNotification?.speechText ?? ""
        XCTAssertEqual(spoken, Self.backendText)
        XCTAssertFalse(spoken.contains("已通知"), "App 永远不能宣称家属已被通知")
        XCTAssertFalse(spoken.contains("已送达"), "它不是回执，更不是送达")
    }

    /// 求助状态不动：不进 `emergencyKind`，不落 `latestSafetyEvent`，也不能被当成投递失败。
    func testDoesNotDriveTheEmergencyStateMachine() async {
        XCTAssertNil(AppRealtimeCoordinator.emergencyKind(forEventType: Self.eventType))

        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        service.simulateIncomingEventForTesting(.notification(makeNotification()))
        await Task.yield()

        XCTAssertNil(coordinator.latestSafetyEvent, "它是催办，不得驱动求助状态机")
    }

    /// 🔴 有活跃订单时同样要播（求助必然发生在 `IN_PROGRESS` 里）。这条事件若进了生命周期表，会被「有活跃订单 ⇒ 抑制」整条吞掉。
    func testIsNotSwallowedWhileAnOrderIsActive() async {
        XCTAssertNil(AppRealtimeCoordinator.lifecycleStatus(forEventType: Self.eventType))

        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(42)
        service.simulateIncomingEventForTesting(.notification(makeNotification()))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, Self.backendText)
    }

    /// 之后真的收到回执，照常走结构化事件。这条事件不能把它挡掉。
    func testALaterDeliveryReceiptStillMapsToItsOwnKind() {
        XCTAssertEqual(
            AppRealtimeCoordinator.emergencyKind(forEventType: "EMERGENCY_CONTACT_SMS_DELIVERED"),
            .emergencyContactSmsDelivered
        )
    }

    private func makeNotification() -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "receipt-timeout",
            eventType: Self.eventType,
            title: "安全提醒",
            body: Self.backendText,
            ttsText: Self.backendText,
            priority: "HIGH",
            timestamp: "2026-11-04T12:00:00Z"
        )
    }
}
