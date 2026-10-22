import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// 屏 3b「求助已发出」页重新设计（#506）：文案、时间记录，以及真机截图。
///
/// 截图走单测而不是 UI 测试：UI 测试里定位闸门恒拦，走不到「已发出」（#500）。
/// 这里用 `FakeSafetyService` 把协调器推进到目标状态，再把真实的 `EmergencyCountdownView`
/// 放进窗口画成图片，作为测试附件导出（`device-test.sh` 会导到 result bundle 旁的 `attachments/`）。
@MainActor
final class EmergencySentScreenTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run { EmergencySOSTests.teardownAlarmObservers() }
        try await super.tearDown()
    }

    // MARK: 文案

    /// 负责人 2026-10-22 定的全 App 共用提醒。
    func testSharedReminderNamesBothNumbers() {
        XCTAssertEqual(EmergencySafetyCopy.emergencyCallReminder, "若情况危急请立即拨打120或110。")
    }

    /// 拨号选择在「已发出」页的第一句：说已经发出，不说任何人已收到，也不能借用「没发出去」那句。
    func testSentCallOptionsSayTheRequestWasSent() {
        let context = EmergencyCallContext.cloudSent
        XCTAssertEqual(context.dialogMessage, "求助已经发出。你也可以自己打电话，请选择要拨打的号码。")
        XCTAssertNotEqual(context.dialogMessage, EmergencyCallContext.cloudFailed.dialogMessage)
        XCTAssertTrue(context.appendsNoContactHint, "跑者没设主联系人时，弹窗要说清只能打 120 / 110")
        for claim in ["已收到", "已通知", "已送达"] {
            XCTAssertFalse(context.dialogMessage.contains(claim), claim)
        }
    }

    /// 「多久以前」的三档边界：59 秒仍是「刚刚」、60 秒是「1 分钟前」；59 分钟与 60 分钟分属两档；
    /// 整点省掉分钟；后端时钟比本机快（负数）夹成「刚刚」。
    func testSentAgoBoundaries() {
        XCTAssertEqual(EmergencySafetyCopy.sentAgo(seconds: 0), "刚刚")
        XCTAssertEqual(EmergencySafetyCopy.sentAgo(seconds: 59), "刚刚")
        XCTAssertEqual(EmergencySafetyCopy.sentAgo(seconds: 60), "1 分钟前")
        XCTAssertEqual(EmergencySafetyCopy.sentAgo(seconds: 59 * 60 + 59), "59 分钟前")
        XCTAssertEqual(EmergencySafetyCopy.sentAgo(seconds: 60 * 60), "1 小时前")
        XCTAssertEqual(EmergencySafetyCopy.sentAgo(seconds: 61 * 60), "1 小时 1 分钟前")
        XCTAssertEqual(EmergencySafetyCopy.sentAgo(seconds: -120), "刚刚")
    }

    func testSentSinceShowsClockAndSpeaksIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let sentAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9, minute: 5)))
        let since = EmergencySafetyCopy.sentSince(sentAt, now: sentAt.addingTimeInterval(3 * 60), calendar: calendar)
        XCTAssertEqual(since.text, "09:05 发出 · 3 分钟前")
        XCTAssertEqual(since.spoken, "9点05分发出，3 分钟前")
    }

    // MARK: 发出时刻与并入时刻

    func testNewEventRecordsWhenItWasSentAndIsNotAMerge() {
        let now = Date(timeIntervalSince1970: 1_000)
        let event = ActiveEmergencyEvent.afterTrigger(
            eventID: 1, orderID: 9, userID: 7, status: .csHandling, previous: nil, now: now
        )
        XCTAssertEqual(event.sentAt, now)
        XCTAssertNil(event.lastMergedAt)
    }

    /// 并入时发出时刻沿用原来那条 —— 用新时刻就会把「10:02 发出」改写成「10:05 发出」。
    func testMergeKeepsTheOriginalSendTimeAndRecordsTheMerge() {
        let first = ActiveEmergencyEvent.afterTrigger(
            eventID: 1, orderID: 9, userID: 7, status: .csHandling, previous: nil, now: Date(timeIntervalSince1970: 1_000)
        )
        let merged = ActiveEmergencyEvent.afterTrigger(
            eventID: 1, orderID: 9, userID: 7, status: .csHandling, previous: first, now: Date(timeIntervalSince1970: 1_180)
        )
        XCTAssertEqual(merged.sentAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(merged.lastMergedAt, Date(timeIntervalSince1970: 1_180))

        let other = ActiveEmergencyEvent.afterTrigger(
            eventID: 2, orderID: 9, userID: 7, status: .pending, previous: merged, now: Date(timeIntervalSince1970: 1_300)
        )
        XCTAssertEqual(other.sentAt, Date(timeIntervalSince1970: 1_300), "换了事件就是新求助")
        XCTAssertNil(other.lastMergedAt)
    }

    /// 倒计时到点后的那次对账也走恢复路径：同一条事件的本机时刻不能被后端的 `triggeredAt` 冲掉。
    func testRecoveryKeepsLocalTimesForTheSameEventAndUsesTriggeredAtOtherwise() {
        var local = ActiveEmergencyEvent.afterTrigger(
            eventID: 1, orderID: 9, userID: 7, status: .csHandling, previous: nil, now: Date(timeIntervalSince1970: 1_000)
        )
        local.lastMergedAt = Date(timeIntervalSince1970: 1_100)
        let triggeredAt = Date(timeIntervalSince1970: 990)

        let same = ActiveEmergencyEvent.recovered(
            eventID: 1, orderID: 9, userID: 7, status: .contactNotified, triggeredAt: triggeredAt, previous: local
        )
        XCTAssertEqual(same.sentAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(same.lastMergedAt, Date(timeIntervalSince1970: 1_100))

        let coldStart = ActiveEmergencyEvent.recovered(
            eventID: 5, orderID: 9, userID: 7, status: .csHandling, triggeredAt: triggeredAt, previous: local
        )
        XCTAssertEqual(coldStart.sentAt, triggeredAt)
        XCTAssertNil(coldStart.lastMergedAt)
    }

    func testCountdownFiringMarksTheEventSent() {
        var event = ActiveEmergencyEvent(eventID: 3, orderID: 9, userID: 7, status: .countdown)
        XCTAssertNil(event.sentAt, "倒计时中还没发出")
        let endsAt = Date(timeIntervalSince1970: 2_000)
        event.markCountdownFired(at: endsAt)
        XCTAssertEqual(event.status, .pending)
        XCTAssertEqual(event.sentAt, endsAt)
    }

    // MARK: 真机截图（三态 × 亮暗 + 最大字号）

    func testCaptureSentScreenStates() async throws {
        let sent = await Self.coordinator(mergedTwice: false)
        add(render(sent, name: "sos-sent-light"))
        add(render(sent, name: "sos-sent-dark", style: .dark))

        let merged = await Self.coordinator(mergedTwice: true)
        XCTAssertNotNil(merged.activeEvent?.lastMergedAt, "前置条件：要截的是并入后的那一屏")
        add(render(merged, name: "sos-merged-light"))
        add(render(merged, name: "sos-merged-dark", style: .dark))
        add(render(merged, name: "sos-merged-ax5", typeSize: .accessibility5, height: 2_200))

        let unsent = await Self.coordinator(unsent: true)
        XCTAssertTrue(unsent.state.isFailure, "前置条件：要截的是没发出的那一屏")
        add(render(unsent, name: "sos-unsent-light"))
    }

    private static func coordinator(mergedTwice: Bool = false, unsent: Bool = false) async -> EmergencyCoordinator {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        let order = EmergencySOSTests.makeOrder(status: .inProgress)
        if unsent {
            _ = await coordinator.trigger(order: order, role: .blind, userID: 7, safety: safety, locate: { nil })
            return coordinator
        }
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 830, status: "CONTACT_NOTIFIED")
        )
        _ = await coordinator.trigger(
            order: order, role: .blind, userID: 7, safety: safety,
            locate: { EmergencySOSTests.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        if mergedTwice {
            _ = await coordinator.trigger(
                order: order, role: .blind, userID: 7, safety: safety,
                locate: { EmergencySOSTests.coordinate(latitude: 39.916, longitude: 116.405) }
            )
        }
        return coordinator
    }

    private func render(
        _ coordinator: EmergencyCoordinator,
        name: String,
        style: UIUserInterfaceStyle = .light,
        typeSize: DynamicTypeSize = .large,
        height: CGFloat = 852
    ) -> XCTAttachment {
        let contact = EmergencyContactResponse(id: 1, name: "妈妈", phone: "13900139001", relationship: "家人", isPrimary: true)
        let view = EmergencyCountdownView(
            coordinator: coordinator,
            primaryContact: contact,
            onCancelCountdown: {},
            onCancelOwnEmergency: {},
            onRetry: {},
            onClose: {}
        )
        .environment(\.dynamicTypeSize, typeSize)
        let size = CGSize(width: 393, height: height)
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            _ = host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
