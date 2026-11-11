import Combine
import XCTest
@testable import blindRun

/// 派单进度不弹浮层（#949）。
///
/// 附近没人时后端在同一个事务里扩完三轮，`DISPATCH_STARTED` + 两条 `DISPATCH_EXPANDING` 几乎同时到。
/// 以前它们进前台浮层队列：挡住订单页，点「关闭」又冒出下一条，三句连念互相切断。
/// 现在：不进浮层；订单页 ① 那一行写「正在扩大范围找」；读屏只念最后一条。
final class DispatchProgressNotificationTests: XCTestCase, BlindRunTestSupport {

    // MARK: - 浮层与播报

    /// 三条连发：浮层一条都不出，播报只出一次，且是最后那条（不带「第N轮」）。
    ///
    /// 验红：把 `routeNotification` 里那一行去掉，三条回到浮层队列，第一条断言就红。
    func testBurstOfDispatchProgressShowsNoBannerAndSpeaksOnlyTheLastOne() async throws {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, dispatchProgressSettleDelay: 0.05)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)
        var spoken: [String] = []
        let cancellable = coordinator.$dispatchProgressAnnouncement.compactMap { $0 }.sink { spoken.append($0.text) }
        defer { cancellable.cancel() }

        for (id, event) in [(1, "DISPATCH_STARTED"), (2, "DISPATCH_EXPANDING"), (3, "DISPATCH_EXPANDING")] {
            service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: Int64(id), eventType: event)))
        }
        await Task.yield()

        XCTAssertNil(coordinator.currentNotification, "派单进度又进了浮层")
        XCTAssertTrue(spoken.isEmpty, "还在连发就念了：后一句会切断前一句")

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(spoken, [DispatchProgressCopy.wideningSpeech])
        XCTAssertFalse(spoken.joined().contains("轮"))
        XCTAssertEqual(coordinator.widenedDispatchOrderIDs, [9])
    }

    /// 只有一条「已收到订单」时照念后端 `ttsText`，那一行不写「扩大范围」。
    func testStartedAloneSpeaksBackendTextAndDoesNotMarkWidening() async throws {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, dispatchProgressSettleDelay: 0.05)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)

        service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: 1, eventType: "DISPATCH_STARTED")))
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(coordinator.dispatchProgressAnnouncement?.text, "已收到订单，正在为您呼叫附近的志愿者，请稍候")
        XCTAssertTrue(coordinator.widenedDispatchOrderIDs.isEmpty)
        XCTAssertNil(coordinator.currentNotification)
    }

    /// 重新匹配从 `DISPATCH_STARTED` 重来：上一次的「扩大范围」不再成立。
    func testNewDispatchClearsThePreviousWidening() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, dispatchProgressSettleDelay: 0.05)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .rematching)

        service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: 1, eventType: "DISPATCH_EXPANDING")))
        await Task.yield()
        XCTAssertEqual(coordinator.widenedDispatchOrderIDs, [9])

        service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: 2, eventType: "DISPATCH_STARTED")))
        await Task.yield()
        XCTAssertTrue(coordinator.widenedDispatchOrderIDs.isEmpty)
    }

    /// 离开匹配（找到人）或注销后，「扩大范围」不再留着；退回匹配时不会凭旧标记又显示出来。
    ///
    /// 验红：去掉 `activeOrderStatuses` 的 `didSet`，第一条断言红。
    func testWideningIsClearedWhenTheOrderLeavesMatchingOrIsUnregistered() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, dispatchProgressSettleDelay: 0.05)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)
        service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: 1, eventType: "DISPATCH_EXPANDING")))
        await Task.yield()
        XCTAssertEqual(coordinator.widenedDispatchOrderIDs, [9])

        coordinator.registerActiveOrder(9, status: .pendingIntroCall)
        XCTAssertTrue(coordinator.widenedDispatchOrderIDs.isEmpty, "找到人以后还标着扩大范围")

        coordinator.registerActiveOrder(9, status: .pendingMatch)
        XCTAssertTrue(coordinator.widenedDispatchOrderIDs.isEmpty, "退回匹配时凭旧标记又显示了")

        coordinator.widenedDispatchOrderIDs = [9]
        coordinator.unregisterActiveOrder(9)
        XCTAssertTrue(coordinator.widenedDispatchOrderIDs.isEmpty)
    }

    /// 同一条推送重复投递（重连重发）不再念第二遍。
    func testDuplicateDeliveryIsSpokenOnce() async throws {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, dispatchProgressSettleDelay: 0.05)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)
        var spoken = 0
        let cancellable = coordinator.$dispatchProgressAnnouncement.compactMap { $0 }.sink { _ in spoken += 1 }
        defer { cancellable.cancel() }

        service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: 1, eventType: "DISPATCH_EXPANDING")))
        try await Task.sleep(nanoseconds: 200_000_000)
        service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: 1, eventType: "DISPATCH_EXPANDING")))
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(spoken, 1)
    }

    /// 信封不带 `orderId`、又有两张单在等：认不出是哪一单，就哪一单都不写（写错单比不写更糟）。
    /// 信封带了 `orderId` 就只写那一单。
    func testWideningIsAttributedOnlyWhenTheOrderIsKnown() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, dispatchProgressSettleDelay: 0.05)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)
        coordinator.registerActiveOrder(10, status: .pendingMatch)

        service.simulateIncomingEventForTesting(.notification(Self.progress(eventID: 1, eventType: "DISPATCH_EXPANDING")))
        await Task.yield()
        XCTAssertTrue(coordinator.widenedDispatchOrderIDs.isEmpty)

        service.simulateIncomingEventForTesting(.notification(
            Self.progress(eventID: 2, eventType: "DISPATCH_EXPANDING", orderID: 10)
        ))
        await Task.yield()
        XCTAssertEqual(coordinator.widenedDispatchOrderIDs, [10])
    }

    /// 重连补读到的是过去的进度：只更新那一行，不念、不弹。
    func testCatchUpUpdatesTheLineWithoutSpeakingOrBanner() async throws {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, dispatchProgressSettleDelay: 0.05)
        coordinator.registerActiveOrder(9, status: .pendingMatch)

        coordinator.ingestCatchUp([MissedNotificationResponse(
            id: 501, eventType: "DISPATCH_EXPANDING", body: "正在为您扩大搜索范围（第2轮），请稍候",
            ttsText: "正在为您寻找更远的志愿者，请稍候", priority: "NORMAL",
            sentAt: "2026-11-11T10:00:00", orderId: nil
        )])
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(coordinator.currentNotification)
        XCTAssertNil(coordinator.dispatchProgressAnnouncement)
        XCTAssertEqual(coordinator.widenedDispatchOrderIDs, [9])
    }

    // MARK: - 订单页 ① 那一行

    func testMatchingDetailCombinesWideningAndWaitedTime() {
        XCTAssertEqual(BlindOrderStageCopy.matchingDetail(widening: true, waitedMinutes: 3), "正在扩大范围找 · 已等 3 分钟")
        XCTAssertEqual(BlindOrderStageCopy.matchingDetail(widening: true, waitedMinutes: nil), "正在扩大范围找")
        XCTAssertEqual(BlindOrderStageCopy.matchingDetail(widening: false, waitedMinutes: 3), "已等 3 分钟")
        XCTAssertNil(BlindOrderStageCopy.matchingDetail(widening: false, waitedMinutes: nil))
    }

    func testStagePageWritesWideningIntoTheCurrentStepLine() throws {
        let order = makeOrder(orderId: 1, status: .pendingMatch)
        let now = try XCTUnwrap(order.createdAt?.backendTimestamp).addingTimeInterval(3 * 60)

        let widened = try XCTUnwrap(BlindOrderStagePresentation.make(
            order: order, canKeepWaiting: false, dispatchWidened: true, now: now
        ))
        let plain = try XCTUnwrap(BlindOrderStagePresentation.make(order: order, canKeepWaiting: false, now: now))

        XCTAssertEqual(widened.timeline.details[.matchVolunteer], "正在扩大范围找 · 已等 3 分钟")
        XCTAssertEqual(plain.timeline.details[.matchVolunteer], "已等 3 分钟")
    }

    // MARK: - 夹具

    /// 正文与 `ttsText` 照后端 `data.sql` 的模板原文。
    private static func progress(eventID: Int64, eventType: String, orderID: Int64? = nil) -> WSAppNotification {
        let started = eventType == "DISPATCH_STARTED"
        return WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: eventID,
            messageId: "dispatch-progress-\(eventID)",
            eventType: eventType,
            title: nil,
            body: started ? "已收到订单，正在为您呼叫志愿者，请稍候" : "正在为您扩大搜索范围（第2轮），请稍候",
            ttsText: started ? "已收到订单，正在为您呼叫附近的志愿者，请稍候" : "正在为您寻找更远的志愿者，请稍候",
            priority: "NORMAL",
            timestamp: "2026-11-11T10:00:00",
            orderId: orderID
        )
    }
}
