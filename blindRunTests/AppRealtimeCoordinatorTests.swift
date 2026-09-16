import Combine
import XCTest
@testable import blindRun

@MainActor
final class AppRealtimeCoordinatorTests: XCTestCase {
    func testProductionOrderStatusPayloadDecodesAndPublishesMessageIdentity() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(123, status: .pendingAccept)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { updates.append($0) }
        defer { cancellable.cancel() }
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(
            #"{"type":"ORDER_STATUS_CHANGED","messageId":"c4a2d3b1-2345-4bcd-8ef0-123456789abc","timestamp":"2026-07-23T15:02:35","orderId":123,"fromStatus":"PENDING_ACCEPT","toStatus":"DRIVER_EN_ROUTE","message":"志愿者已出发","ttsText":"志愿者已出发，正在赶往您的位置","priority":"NORMAL"}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.messageId, "c4a2d3b1-2345-4bcd-8ef0-123456789abc")
        XCTAssertEqual(updates.first?.toStatus, .driverEnRoute)
    }

    func testLegacyOrderStatusPayloadWithoutMessageIDStillDecodes() throws {
        let data = try XCTUnwrap(
            #"{"type":"ORDER_STATUS_CHANGED","orderId":42,"fromStatus":"PENDING_ACCEPT","toStatus":"DRIVER_EN_ROUTE"}"#
                .data(using: .utf8)
        )

        let message = try JSONDecoder().decode(WSOrderStatusChanged.self, from: data)

        XCTAssertNil(message.messageId)
        XCTAssertEqual(message.orderId, 42)
        XCTAssertEqual(message.toStatus, "DRIVER_EN_ROUTE")
    }

    func testInvalidStatusMessageIdentityKeepsLegacyCompatibility() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(42, status: .pendingAccept)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { updates.append($0) }
        defer { cancellable.cancel() }

        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            messageID: "not-a-uuid",
            orderID: 42,
            from: "PENDING_ACCEPT",
            to: "DRIVER_EN_ROUTE"
        )))
        await Task.yield()

        XCTAssertEqual(updates.count, 1)
        XCTAssertNil(updates.first?.messageId)
        XCTAssertEqual(updates.first?.toStatus, .driverEnRoute)
    }

    func testAttachIsExactlyOnceAndReplacementDetachesOldService() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let first = WebSocketService()
        let replacement = WebSocketService()

        coordinator.attach(to: first, role: .volunteer)
        coordinator.attach(to: first, role: .volunteer)
        XCTAssertEqual(coordinator.attachmentCount, 1)

        coordinator.attach(to: replacement, role: .volunteer)
        XCTAssertEqual(coordinator.attachmentCount, 2)
        first.simulateIncomingEventForTesting(.newOrder(makeDispatch(orderID: 1)))
        await Task.yield()
        XCTAssertNil(coordinator.pendingDispatch)

        replacement.simulateIncomingEventForTesting(.newOrder(makeDispatch(orderID: 2)))
        await Task.yield()
        XCTAssertEqual(coordinator.pendingDispatch?.order.orderId, 2)
    }

    func testStatusRefreshIsRetainedAndCoalescedUntilCompleted() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        let event = WSOrderStatusChanged(
            type: WSMessageType.orderStatusChanged.rawValue,
            orderId: 42,
            fromStatus: "PENDING_MATCH",
            toStatus: "PENDING_ACCEPT",
            message: nil,
            ttsText: nil,
            priority: "NORMAL",
            timestamp: "2026-07-19T12:00:00Z"
        )
        service.simulateIncomingEventForTesting(.orderStatusChanged(event))
        service.simulateIncomingEventForTesting(.orderStatusChanged(event))
        await Task.yield()

        XCTAssertEqual(coordinator.pendingOrderRefreshIDs, [42])
        coordinator.completeOrderRefresh(42)
        XCTAssertTrue(coordinator.pendingOrderRefreshIDs.isEmpty)
    }

    func testValidatedStatusUpdatePublishesImmediatelyForAssociatedOrder() async {
        let receivedAt = Date(timeIntervalSince1970: 123)
        let coordinator = AppRealtimeCoordinator(now: { receivedAt })
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(42, status: .pendingAccept)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { updates.append($0) }

        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            orderID: 42,
            from: "PENDING_ACCEPT",
            to: "DRIVER_EN_ROUTE"
        )))
        await Task.yield()

        XCTAssertEqual(updates, [
            RealtimeOrderStatusUpdate(
                orderId: 42,
                fromStatus: .pendingAccept,
                toStatus: .driverEnRoute,
                receivedAt: receivedAt
            )
        ])
        XCTAssertTrue(coordinator.pendingOrderRefreshIDs.contains(42))
        withExtendedLifetime(cancellable) {}
    }

    func testStatusMessageIdentitySurvivesReconnectAndDropsReplayWithoutRefresh() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        service.simulateConnectionStateForTesting(.connected)
        coordinator.registerActiveOrder(42, status: .pendingAccept)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { updates.append($0) }
        defer { cancellable.cancel() }
        let messageID = "C4A2D3B1-2345-4BCD-8EF0-123456789ABC"
        let event = makeStatusEvent(
            messageID: messageID,
            orderID: 42,
            from: "PENDING_ACCEPT",
            to: "DRIVER_EN_ROUTE"
        )

        service.simulateIncomingEventForTesting(.orderStatusChanged(event))
        await Task.yield()
        coordinator.completeOrderRefresh(42)
        service.simulateConnectionStateForTesting(.disconnected)
        service.simulateConnectionStateForTesting(.connected)
        // `attach` subscribes to `$connectionState` through `receive(on: DispatchQueue.main)`,
        // so the reconnect resync refresh is delivered asynchronously. It must be drained and
        // completed here, otherwise it is still pending below and would be mistaken for a
        // refresh triggered by the replayed event this test is actually guarding against.
        await Task.yield()
        XCTAssertEqual(coordinator.pendingOrderRefreshIDs, [42])
        XCTAssertEqual(coordinator.pendingOrderRefreshRequests[42]?.reason, .reconnected)
        coordinator.completeOrderRefresh(42)

        service.simulateIncomingEventForTesting(.orderStatusChanged(event))
        await Task.yield()

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.messageId, messageID)
        XCTAssertFalse(coordinator.pendingOrderRefreshIDs.contains(42))
    }

    func testStatusMessageIdentityCollisionRequestsOneSafeRefreshWithoutMutation() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        coordinator.registerActiveOrder(42, status: .pendingAccept)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { updates.append($0) }
        defer { cancellable.cancel() }
        let messageID = "C4A2D3B1-2345-4BCD-8EF0-123456789ABC"

        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            messageID: messageID,
            orderID: 42,
            from: "PENDING_ACCEPT",
            to: "DRIVER_EN_ROUTE"
        )))
        await Task.yield()
        coordinator.completeOrderRefresh(42)

        let collidingEvent = makeStatusEvent(
            messageID: messageID,
            orderID: 42,
            from: "DRIVER_EN_ROUTE",
            to: "DRIVER_ARRIVED"
        )
        service.simulateIncomingEventForTesting(.orderStatusChanged(collidingEvent))
        await Task.yield()

        XCTAssertEqual(updates.map(\.toStatus), [.driverEnRoute])
        XCTAssertTrue(coordinator.pendingOrderRefreshIDs.contains(42))
        coordinator.completeOrderRefresh(42)

        service.simulateIncomingEventForTesting(.orderStatusChanged(collidingEvent))
        await Task.yield()
        XCTAssertFalse(coordinator.pendingOrderRefreshIDs.contains(42))
    }

    func testStatusUpdateRejectsWrongOrderInvalidStatusDuplicateAndLateEvents() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        coordinator.registerActiveOrder(42, status: .pendingAccept)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { updates.append($0) }

        let acceptedUpdate = makeStatusEvent(
            orderID: 42,
            from: "PENDING_ACCEPT",
            to: "DRIVER_EN_ROUTE"
        )
        service.simulateIncomingEventForTesting(.orderStatusChanged(acceptedUpdate))
        service.simulateIncomingEventForTesting(.orderStatusChanged(acceptedUpdate))
        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            orderID: 42,
            from: "PENDING_ACCEPT",
            to: "DRIVER_ARRIVED"
        )))
        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            orderID: 42,
            from: "NOT_A_STATUS",
            to: "DRIVER_ARRIVED"
        )))
        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            orderID: 42,
            from: "DRIVER_EN_ROUTE",
            to: "NOT_A_STATUS"
        )))
        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            orderID: 99,
            from: "PENDING_ACCEPT",
            to: "DRIVER_EN_ROUTE"
        )))
        await Task.yield()

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.toStatus, .driverEnRoute)
        XCTAssertTrue(coordinator.pendingOrderRefreshIDs.contains(42))
        XCTAssertTrue(coordinator.pendingOrderRefreshIDs.contains(99))
        withExtendedLifetime(cancellable) {}
    }

    func testLateRESTStatusCannotRegressAcceptedRealtimeTransition() {
        var reconciler = OrderStatusReconciler()
        reconciler.register(orderID: 42, status: .pendingAccept)
        let request = reconciler.requestToken(orderID: 42)

        XCTAssertEqual(
            reconciler.reconcileRealtime(
                orderID: 42,
                fromStatus: .pendingAccept,
                toStatus: .driverEnRoute
            ),
            .applied(.driverEnRoute)
        )
        XCTAssertEqual(
            reconciler.reconcileREST(
                orderID: 42,
                candidate: .pendingAccept,
                token: request
            ),
            .rejectedStale(current: .driverEnRoute, candidate: .pendingAccept)
        )
    }

    func testReconcilerAcceptsLegalForwardRESTAndRejectsWrongOrderToken() {
        var reconciler = OrderStatusReconciler()
        reconciler.register(orderID: 42, status: .pendingAccept)
        let request = reconciler.requestToken(orderID: 42)

        XCTAssertEqual(
            reconciler.reconcileREST(
                orderID: 42,
                candidate: .driverArrived,
                token: request
            ),
            .applied(.driverArrived)
        )
        XCTAssertEqual(
            reconciler.reconcileREST(
                orderID: 99,
                candidate: .driverEnRoute,
                token: request
            ),
            .rejectedInvalid(current: nil, candidate: .driverEnRoute)
        )
    }

    func testFailedStatusRefreshRetriesAreBounded() async throws {
        let coordinator = AppRealtimeCoordinator(orderRefreshRetryDelays: [0.01, 0.01])
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        let event = WSOrderStatusChanged(
            type: WSMessageType.orderStatusChanged.rawValue,
            orderId: 42,
            fromStatus: "PENDING_MATCH",
            toStatus: "PENDING_ACCEPT",
            message: nil,
            ttsText: nil,
            priority: "NORMAL",
            timestamp: "2026-07-19T12:00:00Z"
        )
        service.simulateIncomingEventForTesting(.orderStatusChanged(event))
        await Task.yield()

        coordinator.failOrderRefresh(42)
        XCTAssertFalse(coordinator.pendingOrderRefreshIDs.contains(42))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(coordinator.pendingOrderRefreshIDs.contains(42))

        coordinator.failOrderRefresh(42)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(coordinator.pendingOrderRefreshIDs.contains(42))

        coordinator.failOrderRefresh(42)
        XCTAssertFalse(coordinator.pendingOrderRefreshIDs.contains(42))
        XCTAssertNil(coordinator.pendingOrderRefreshRequests[42])
    }

    private func makeStatusEvent(
        messageID: String? = nil,
        orderID: Int64,
        from: String?,
        to: String
    ) -> WSOrderStatusChanged {
        WSOrderStatusChanged(
            type: WSMessageType.orderStatusChanged.rawValue,
            messageId: messageID,
            orderId: orderID,
            fromStatus: from,
            toStatus: to,
            message: nil,
            ttsText: nil,
            priority: "NORMAL",
            timestamp: "2026-07-23T12:00:00Z"
        )
    }

    func testHighPriorityPreemptsNormalAndNonSafetyDuplicatesAreBounded() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeNotification(eventID: 1, body: "普通通知", priority: "NORMAL")))
        await Task.yield()
        XCTAssertEqual(coordinator.currentNotification?.displayText, "普通通知")

        service.simulateIncomingEventForTesting(.notification(makeNotification(eventID: 2, body: "重要通知", priority: "HIGH")))
        await Task.yield()
        XCTAssertEqual(coordinator.currentNotification?.displayText, "重要通知")
        XCTAssertEqual(coordinator.currentNotification?.speechText, "重要通知")

        service.simulateIncomingEventForTesting(.notification(makeNotification(eventID: 2, body: "重要通知", priority: "HIGH")))
        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.displayText, "普通通知")
        coordinator.dismissCurrentNotification()
        XCTAssertNil(coordinator.currentNotification)
    }

    func testNotificationBacklogIsBoundedAndRetainsSafetyBeforeNormal() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60, maximumQueuedNotifications: 2)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeNotification(eventID: 1, body: "当前通知", priority: "HIGH")))
        service.simulateIncomingEventForTesting(.notification(makeContactNotified(eventID: 11)))
        service.simulateIncomingEventForTesting(.emergencyResolved(makeEmergencyResolved(eventID: 12)))
        service.simulateIncomingEventForTesting(.notification(makeNotification(eventID: 2, body: "可丢弃普通通知", priority: "NORMAL")))
        await Task.yield()

        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "emergencyContactNotified:11")
        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "emergencyResolved:12")
        coordinator.dismissCurrentNotification()
        XCTAssertNil(coordinator.currentNotification)
    }

    func testLifecycleTemplateIsSuppressedForActiveOrder() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9)

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 3,
            body: "志愿者已到达",
            priority: "NORMAL",
            eventType: "DRIVER_ARRIVED"
        )))
        await Task.yield()
        XCTAssertNil(coordinator.currentNotification)
    }

    /// 抑制的判据是 `eventType`，**不是正文文案**。
    ///
    /// 旧实现匹配一张中文片段表，于是后端改任何一条模板正文都会静默改变 iOS 的播报行为。
    /// 两个方向各钉一条：正文长得像生命周期但 `eventType` 不是 → 照播；
    /// 正文毫无线索但 `eventType` 是 → 抑制。
    ///
    /// ⚠️ 取样用 `REMATCH_TIMEOUT` 而不是 `ORDER_CANCELLATION_WARNING`（2026-09-16 换的）。
    /// 后者现在有一条**按状态**的正文覆盖（`testCancellationWarningDropsTheDeletedButtonHint`），
    /// 于是它的 `displayText` 不再恒等于 `body` —— 拿它当「照播」的样本会让这条用例
    /// 红在一件它根本不关心的事上。换样本不削弱它的保证：它要的只是一个
    /// **不在生命周期表里**的 eventType。
    func testSuppressionFollowsEventTypeNotBodyText() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9)

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 40,
            body: "志愿者已取消，正在重新匹配，订单已完成",
            priority: "NORMAL",
            eventType: "REMATCH_TIMEOUT"
        )))
        await Task.yield()
        XCTAssertEqual(
            coordinator.currentNotification?.displayText,
            "志愿者已取消，正在重新匹配，订单已完成",
            "正文命中旧片段表但 eventType 不是状态重复播报，必须照播"
        )
        coordinator.dismissCurrentNotification()

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 41,
            body: "本次跑步已结束，感谢您的使用",
            priority: "NORMAL",
            eventType: "ORDER_COMPLETED"
        )))
        await Task.yield()
        XCTAssertNil(coordinator.currentNotification, "eventType 命中就抑制，与正文用词无关")
    }

    /// `REMATCH_ACCEPTED` **永远不抑制**，哪怕用户正开着订单页。
    ///
    /// 它与 `ORDER_ACCEPTED` 落到同一个 `PENDING_ACCEPT`，而订单页两次念的都是
    /// 「志愿者已接单」——既没有「重新」也没有新志愿者的名字。吞掉这条，
    /// 刚被告知上一个志愿者取消的用户就分不出这是新人还是原来那个。
    ///
    /// 旧的文案匹配正是这么吞的：模板正文「已为您**重新匹配**志愿者{name}」命中片段「重新匹配」。
    func testRematchAcceptedIsNeverSuppressedSoTheNewVolunteerIsAnnounced() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .rematching)

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 42,
            body: "已为您重新匹配志愿者张三，服务即将开始",
            priority: "NORMAL",
            eventType: "REMATCH_ACCEPTED"
        )))
        await Task.yield()

        XCTAssertEqual(
            coordinator.currentNotification?.speechText,
            "已为您重新匹配志愿者张三，服务即将开始"
        )
    }

    // MARK: - ORDER_CANCELLATION_WARNING 的正文覆盖

    /// 🔴 **`PENDING_MATCH` 时不许照播后端那句「点击继续等待可延长」。**
    ///
    /// 后端模板正文逐字带着那半句（`demo/src/main/resources/data.sql:146`），而
    /// `PENDING_MATCH` 那个按钮已按 2026-09-16 的决策删除。照播的后果是最坏的一种：
    /// 盲人听见一句明确的操作指引，然后在屏幕上找不到那个控件 ——
    /// 而他无从判断是自己没找到，还是它根本不在。
    ///
    /// **两条通道一起断。** `makeNotification` 把 `ttsText` 设成后端原文，所以只换
    /// `displayText` 的实现会让第二个断言红 —— 而读屏用户听到的正是 `speechText`。
    func testCancellationWarningDropsTheDeletedButtonHintWhilePendingMatch() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 60,
            body: "您的订单即将因长时间无人接单被取消，点击继续等待可延长",
            priority: "HIGH",
            eventType: "ORDER_CANCELLATION_WARNING"
        )))
        await Task.yield()

        XCTAssertEqual(
            coordinator.currentNotification?.displayText,
            KeepWaitingCopy.cancellationWarningWithoutControl
        )
        XCTAssertEqual(
            coordinator.currentNotification?.speechText,
            KeepWaitingCopy.cancellationWarningWithoutControl,
            "只换了屏幕上那行、播报照念后端原文 —— 而这条覆盖存在的全部理由就是那句话"
        )
        XCTAssertFalse(
            coordinator.currentNotification?.speechText.contains("继续等待") == true,
            "替代文案里还提到了那个已删的按钮"
        )
    }

    /// 反向：`REMATCHING` 那一侧按钮还在，**一个字都不许改**。
    ///
    /// 同一个 eventType 在后端有三个推送点，覆盖两态（`OrderLifecycleService:526` 就是
    /// 重匹这一侧）。在这一态换文案的代价是具体的：把一条准确且此刻真能延长订单寿命的提示，
    /// 换成「去取消订单重新预约」—— 而重新下单要求 ≥30 分钟提前量。
    ///
    /// 这条同时是覆盖逻辑的**验红面**：把判据从「此刻有没有那个按钮」改成
    /// 「eventType 是不是它」（也就是无条件覆盖），这一条立刻红。
    func testCancellationWarningIsLeftIntactWhileRematchingBecauseTheButtonExists() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .rematching)

        let backendBody = "您的订单即将因长时间无人接单被取消，点击继续等待可延长"
        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 61,
            body: backendBody,
            priority: "HIGH",
            eventType: "ORDER_CANCELLATION_WARNING"
        )))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, backendBody)
        XCTAssertEqual(coordinator.currentNotification?.speechText, backendBody)
    }

    /// 看不到任何订单时（App 刚起来、订单还没加载完就收到推送）按「没有按钮」处理。
    ///
    /// 替代文案在两态下都是真话，而后端原文在其中一态下是假的 ——
    /// 不确定时说那句两边都成立的。
    func testCancellationWarningFallsBackToTheSafeCopyWhenNoOrderIsKnown() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 62,
            body: "您的订单即将因长时间无人接单被取消，点击继续等待可延长",
            priority: "HIGH",
            eventType: "ORDER_CANCELLATION_WARNING"
        )))
        await Task.yield()

        XCTAssertEqual(
            coordinator.currentNotification?.displayText,
            KeepWaitingCopy.cancellationWarningWithoutControl
        )
    }

    /// 🔴 **同时登记两张单、其中一张没有那个按钮时，按「没有」处理。**
    ///
    /// `WSAppNotification` 里**没有 `orderId`**，判不出这条预警说的是哪一张 ——
    /// 而两张单同时在册是可达的：首页登记它那一张、订单详情页登记它那一张，
    /// 且详情页 `onDisappear` 只 `stopPolling()`、**不 unregister**。
    ///
    /// 用 `contains(where:)`（任意一张有按钮就照播原文）会让 `PENDING_MATCH` 那张单的
    /// 预警被 `REMATCHING` 那张单「担保」下来，照播「点击继续等待可延长」——
    /// 而按下的那一屏没有这个控件。两个方向的代价不对称：多覆盖一次只是少一句提示，
    /// 少覆盖一次是把盲人指去按一个不存在的东西。
    func testCancellationWarningTakesTheSaferSideWhenTwoOrdersAreRegistered() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        // 两张候选单同时在册，一张有按钮、一张没有。
        coordinator.registerActiveOrder(9, status: .pendingMatch)
        coordinator.registerActiveOrder(10, status: .rematching)

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 63,
            body: "您的订单即将因长时间无人接单被取消，点击继续等待可延长",
            priority: "HIGH",
            eventType: "ORDER_CANCELLATION_WARNING"
        )))
        await Task.yield()

        XCTAssertEqual(
            coordinator.currentNotification?.displayText,
            KeepWaitingCopy.cancellationWarningWithoutControl,
            "有一张单没有那个按钮，却被另一张担保着照播了原文"
        )
    }

    /// 无关状态的订单**不算候选**，不许把它们算进判据。
    ///
    /// 只有 `PENDING_MATCH` / `REMATCHING` 是这个 eventType 可能指向的态
    /// （后端三个推送点都在这两态）。把 `DRIVER_EN_ROUTE` 这种也算进来的话，
    /// 它永远没有那个按钮 ⇒ 判据恒为「没有」⇒ 连 `REMATCHING` 那条准确的原文也被换掉。
    func testCancellationWarningIgnoresOrdersThisEventCannotBeAbout() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .rematching)
        // 同一账号的另一张远期单，与这条预警无关。
        coordinator.registerActiveOrder(11, status: .driverEnRoute)

        let backendBody = "您的订单即将因长时间无人接单被取消，点击继续等待可延长"
        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 64,
            body: backendBody,
            priority: "HIGH",
            eventType: "ORDER_CANCELLATION_WARNING"
        )))
        await Task.yield()

        XCTAssertEqual(
            coordinator.currentNotification?.displayText,
            backendBody,
            "一张无关状态的订单把 REMATCHING 那条准确的原文顶掉了"
        )
    }

    /// 替代正文**在两态下都得是真话**。
    ///
    /// 判不出这条预警说的是哪张单，所以它也会落到 `REMATCHING` 上 —— 而那一态是
    /// 「有人接过、又取消了，正在重新找」。初稿写「你的订单还没有人接单」在那一态是假的。
    /// 这条钉的是措辞本身，改回去会红。
    func testCancellationWarningReplacementIsTrueInBothWaitingStates() {
        let copy = KeepWaitingCopy.cancellationWarningWithoutControl
        XCTAssertFalse(
            copy.contains("还没有人接单"),
            "REMATCHING 是「接过又取消了」，说「还没有人接单」是假话"
        )
        XCTAssertFalse(copy.contains("继续等待"), "替代文案不许提那个已删的按钮")
        XCTAssertTrue(copy.contains("取消"), "没说清可能的结局")
        XCTAssertTrue(copy.contains(KeepWaitingCopy.stillMatchingAdvice), "没说清还能做什么")
    }

    /// 断线重连的补读走**同一条**覆盖。
    ///
    /// 漏掉 `ingestCatchUp` 的后果只在这条路径上出现，最难在真机上复现：
    /// 横幅上是替代文案、补读念的却是后端原文。
    func testCatchUpAppliesTheSameCancellationWarningOverride() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)

        coordinator.ingestCatchUp([
            MissedNotificationResponse(
                id: 900,
                eventType: "ORDER_CANCELLATION_WARNING",
                body: "您的订单即将因长时间无人接单被取消，点击继续等待可延长",
                ttsText: "您的订单即将因长时间无人接单被取消，点击继续等待可延长",
                priority: "HIGH",
                sentAt: "2026-09-16T08:00:00Z",
                orderId: 9
            ),
        ])
        await Task.yield()

        XCTAssertEqual(
            coordinator.currentNotification?.speechText,
            KeepWaitingCopy.cancellationWarningWithoutControl
        )
    }

    /// 派单期（最长 30 分钟、3 轮扩圈）订单一直停在 `PENDING_MATCH`，没有任何状态变化，
    /// 所以订单页不会播 —— 这几条被抑制就等于整段静音，而看不见屏幕的人没有别的方式知道系统还在跑。
    func testDispatchProgressNotificationsAreNeverSuppressed() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .pendingMatch)

        for (index, eventType) in ["DISPATCH_STARTED", "DISPATCH_EXPANDING", "REMATCH_TIMEOUT"].enumerated() {
            service.simulateIncomingEventForTesting(.notification(makeNotification(
                eventID: Int64(50 + index),
                body: "派单进度 \(eventType)",
                priority: "NORMAL",
                eventType: eventType
            )))
            await Task.yield()
            XCTAssertEqual(
                coordinator.currentNotification?.displayText,
                "派单进度 \(eventType)",
                "\(eventType) 不改订单状态，订单页不会播，抑制它等于静音"
            )
            coordinator.dismissCurrentNotification()
        }
    }

    func testCompletedStatusThenParallelTemplateProducesOnlyStructuredStatusChannel() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .inProgress)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { update in
                updates.append(update)
                coordinator.unregisterActiveOrder(update.orderId)
            }
        defer { cancellable.cancel() }

        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            messageID: "BF598B4F-C8D2-4D7C-9D45-84FAFF46F37D",
            orderID: 9,
            from: "IN_PROGRESS",
            to: "COMPLETED"
        )))
        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 90,
            body: "订单已完成",
            priority: "NORMAL",
            eventType: "ORDER_COMPLETED"
        )))
        await Task.yield()

        XCTAssertEqual(updates.map(\.toStatus), [.completed])
        XCTAssertNil(coordinator.currentNotification)
    }

    func testParallelTemplateBeforeCompletedStatusIsSuppressedByActiveOrder() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .inProgress)
        var updates: [RealtimeOrderStatusUpdate] = []
        let cancellable = coordinator.statusUpdatePublisher
            .sink { updates.append($0) }
        defer { cancellable.cancel() }

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 91,
            body: "订单已完成",
            priority: "NORMAL",
            eventType: "ORDER_COMPLETED"
        )))
        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            messageID: "99B27ECF-4B44-4C19-98AF-BD99F9BE652F",
            orderID: 9,
            from: "IN_PROGRESS",
            to: "COMPLETED"
        )))
        await Task.yield()

        XCTAssertNil(coordinator.currentNotification)
        XCTAssertEqual(updates.map(\.toStatus), [.completed])
    }

    func testLifecycleTemplateSuppressionExpiresAfterThirtySeconds() async {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let coordinator = AppRealtimeCoordinator(
            now: { currentDate },
            notificationDuration: 60
        )
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9, status: .inProgress)
        let cancellable = coordinator.statusUpdatePublisher
            .sink { update in coordinator.unregisterActiveOrder(update.orderId) }
        defer { cancellable.cancel() }

        service.simulateIncomingEventForTesting(.orderStatusChanged(makeStatusEvent(
            messageID: "67F3FE3C-DB29-4DEE-8575-F9881444D7FB",
            orderID: 9,
            from: "IN_PROGRESS",
            to: "COMPLETED"
        )))
        await Task.yield()
        currentDate.addTimeInterval(31)

        service.simulateIncomingEventForTesting(.notification(makeNotification(
            eventID: 92,
            body: "订单已完成",
            priority: "NORMAL",
            eventType: "ORDER_COMPLETED"
        )))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, "订单已完成")
    }

    func testBothPeerDirectionsRouteAndInvalidOrWrongOrderSamplesAreRejected() async {
        let blindCoordinator = AppRealtimeCoordinator()
        let blindService = WebSocketService()
        blindCoordinator.attach(to: blindService, role: .blind)
        blindCoordinator.registerActiveOrder(7)

        blindService.simulateIncomingEventForTesting(.volunteerLocation(WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: 7,
            lat: 39.9,
            lng: 116.4,
            timestamp: 100
        )))
        blindService.simulateIncomingEventForTesting(.volunteerLocation(WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: 8,
            lat: 39.8,
            lng: 116.3,
            timestamp: 101
        )))
        blindService.simulateIncomingEventForTesting(.volunteerLocation(WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: 7,
            lat: 100,
            lng: 116.3,
            timestamp: 102
        )))
        await Task.yield()
        XCTAssertEqual(blindCoordinator.latestPeerLocation(orderID: 7, ownerRole: .volunteer)?.latitude, 39.9)
        XCTAssertNil(blindCoordinator.latestPeerLocation(orderID: 8, ownerRole: .volunteer))
        XCTAssertNil(blindCoordinator.currentNotification, "Coordinates must not become visible notification or accessibility text")

        let volunteerCoordinator = AppRealtimeCoordinator()
        let volunteerService = WebSocketService()
        volunteerCoordinator.attach(to: volunteerService, role: .volunteer)
        volunteerCoordinator.registerActiveOrder(7)
        volunteerService.simulateIncomingEventForTesting(.blindLocation(WSBlindLocationUpdate(
            type: WSMessageType.blindLocationUpdate.rawValue,
            orderId: 7,
            lat: 39.91,
            lng: 116.41,
            timestamp: 103
        )))
        await Task.yield()
        XCTAssertEqual(volunteerCoordinator.latestPeerLocation(orderID: 7, ownerRole: .blind)?.longitude, 116.41)
    }

    func testPeerLocationFloodPublishesOnlyTheLatestSamplePerMainActorTurn() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(7)
        var samples: [RealtimePeerLocationSample] = []
        // 等「第一次发布真的到了」，不是等一个猜出来的时长。
        //
        // 原来这里是 `Task.yield() ×2 + sleep(10ms)`：合并发布调度在后续的 main-actor turn 上，
        // 单独跑够用，全量跑（489 条）时不够 —— 2026-08-06 实测隔离 3/3 通过、全量失败，
        // 且失败的只有 `samples.count`，`latestPeerLocation` 那条是过的，即数据已入库、只是还没推出来。
        // 固定睡眠等的是墙钟，负载一高就翻车；expectation 等的是事件本身。
        let firstPublish = expectation(description: "peer location published")
        firstPublish.assertForOverFulfill = false
        let cancellable = coordinator.peerLocationPublisher.sink {
            samples.append($0)
            firstPublish.fulfill()
        }
        defer { cancellable.cancel() }

        for timestamp in 1...250 {
            service.simulateIncomingEventForTesting(.volunteerLocation(WSVolunteerLocationUpdate(
                type: WSMessageType.volunteerLocationUpdate.rawValue,
                orderId: 7,
                lat: 39.9,
                lng: 116.4,
                timestamp: Int64(timestamp)
            )))
        }
        await fulfillment(of: [firstPublish], timeout: 5)
        // 收到第一条之后再放一轮，确认剩下 249 条真的被合并掉了 —— 这一段仍是「等一小会儿看有没有
        // 第二条」，但此时已经不影响是否漏判：真有第二条会让下面的 count 断言失败，而不是像原来那样
        // 因为第一条都还没到就整条假失败。
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.timestampMilliseconds, 250)
        XCTAssertEqual(
            coordinator.latestPeerLocation(orderID: 7, ownerRole: .volunteer)?.timestampMilliseconds,
            250
        )
    }

    func testDistinctSafetyEventIDsWithSameCopyArePreserved() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(7)

        service.simulateIncomingEventForTesting(.emergencyResolved(makeEmergencyResolved(eventID: 11)))
        service.simulateIncomingEventForTesting(.emergencyResolved(makeEmergencyResolved(eventID: 12)))
        await Task.yield()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "emergencyResolved:11")
        XCTAssertEqual(coordinator.latestSafetyEvent?.eventID, "12")

        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "emergencyResolved:12")
    }

    func testReconnectRequestsRefreshAndEmitsRecoverySignal() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        var signals: [RealtimeRecoverySignal] = []
        let cancellable = coordinator.recoveryPublisher.sink { signals.append($0) }
        defer { cancellable.cancel() }
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(55)

        service.simulateConnectionStateForTesting(.connected)
        service.simulateConnectionStateForTesting(.reconnecting(attempt: 1))
        service.simulateConnectionStateForTesting(.connected)
        await Task.yield()

        XCTAssertEqual(coordinator.pendingOrderRefreshIDs, [55])
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.role, .blind)
    }

    func testStaleTransportFailureCannotDisconnectReplacementAndOneFailureSchedulesOneReconnect() {
        let service = WebSocketService()
        let staleGeneration = service.simulateNewTransportForTesting()
        let activeGeneration = service.simulateNewTransportForTesting()

        service.simulateDisconnectForTesting(generation: staleGeneration)
        XCTAssertEqual(service.connectionState, .connected)

        service.simulateDisconnectForTesting(generation: activeGeneration)
        XCTAssertEqual(service.connectionState, .reconnecting(attempt: 1))
        service.simulateDisconnectForTesting(generation: activeGeneration)
        XCTAssertEqual(service.connectionState, .reconnecting(attempt: 1))
        service.disconnect()
    }

    func testNewOrderDiagnosticMovesFromReceivedToRetainedAndPresented() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(
            #"{"type":"NEW_ORDER","orderId":42,"dispatchTimeoutSeconds":30}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertEqual(coordinator.pendingDispatch?.order.orderId, 42)
        XCTAssertEqual(coordinator.dispatchDiagnostic?.stage, .retained)
        XCTAssertEqual(coordinator.dispatchDiagnostic?.orderID, 42)
        coordinator.markDispatchPresented(orderID: 42)
        XCTAssertEqual(coordinator.dispatchDiagnostic?.stage, .presented)
    }

    func testMalformedNewOrderRecordsOnlyFailedFieldAndKeepsReceiverUsable() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(
            #"{"type":"NEW_ORDER","startAddress":"不应进入诊断"}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertNil(coordinator.pendingDispatch)
        XCTAssertEqual(coordinator.dispatchDiagnostic?.stage, .decodeFailed)
        XCTAssertEqual(coordinator.dispatchDiagnostic?.messageType, "NEW_ORDER")
        XCTAssertEqual(coordinator.dispatchDiagnostic?.failedField, "orderId")
        XCTAssertFalse(coordinator.dispatchDiagnostic?.debugSummary.contains("不应进入诊断") ?? true)

        service.simulateTextMessageForTesting(
            #"{"type":"NEW_ORDER","orderId":43,"dispatchTimeoutSeconds":30}"#,
            generation: generation
        )
        await Task.yield()
        XCTAssertEqual(coordinator.pendingDispatch?.order.orderId, 43)
    }

    // MARK: - 解码失败必须留痕（不是只有 NEW_ORDER）

    /// 从前 `decodeTextMessage` 的八个分支里只有 `NEW_ORDER` 上报失败，其余七个
    /// `try? … else { return nil }` 之后无日志、无计数、无诊断。受影响的正是
    /// `APP_NOTIFICATION`（TTS 播报的输入）与两条求助事件 —— 盲人端的现象是「点了没反应」，
    /// 而这恰好是 `PagedOrderResponse` 那次「静默吞成空页」的同一个 bug class 的 WebSocket 版本。
    ///
    /// 这四条钉的不是「解不出」，是「解不出时必须**吵**」。

    /// `APP_NOTIFICATION` 解不出时要计入失败，且**不得**污染派单面包屑。
    func testMalformedAppNotificationIsRecordedAsFailedWithoutTouchingDispatchDiagnostic() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        let generation = service.simulateNewTransportForTesting()

        // 先让派单面包屑停在 .retained，这样"有没有被别的类型踩脏"才看得出来。
        service.simulateTextMessageForTesting(
            #"{"type":"NEW_ORDER","orderId":42,"dispatchTimeoutSeconds":30}"#,
            generation: generation
        )
        await Task.yield()
        XCTAssertEqual(coordinator.dispatchDiagnostic?.stage, .retained)

        // `body` 是必填，缺了必然解不出。
        service.simulateTextMessageForTesting(
            #"{"type":"APP_NOTIFICATION","eventType":"ESCORT_DISTANCE_ALERT"}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertEqual(ClientFlowDiagnostics.currentPhase, "websocket-decode.failed")
        // 关键：派单诊断仍停在 .retained。若把非派单的失败也写进去，
        // `AppRealtimeCoordinator` 后续的 `.advancing(to:)` 会推进错误的那条。
        XCTAssertEqual(coordinator.dispatchDiagnostic?.stage, .retained)
        XCTAssertEqual(coordinator.dispatchDiagnostic?.orderID, 42)
    }

    /// 求助告警解不出时同样要计入失败 —— 这条单独钉，因为它落在 SOS 红线上。
    func testMalformedEmergencyVolunteerAlertIsRecordedAsFailed() async {
        let service = WebSocketService()
        let generation = service.simulateNewTransportForTesting()

        // `eventId` 是必填。
        service.simulateTextMessageForTesting(
            #"{"type":"EMERGENCY_VOLUNTEER_ALERT","orderId":9}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertEqual(ClientFlowDiagnostics.currentPhase, "websocket-decode.failed")
    }

    /// 整段 JSON 畸形（信封都解不出）时也必须计入失败。
    ///
    /// 这条是设计上最容易漏的一个：`failedField(from:)` 对 codingPath 为空的
    /// `dataCorrupted` 返回 `nil`，所以失败判定**不能**写成 `if let failedField`，
    /// 否则最常见的一种失败反而会漏回静默。
    func testCompletelyMalformedPayloadIsRecordedAsFailedEvenWithoutAFailedField() async {
        let service = WebSocketService()
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(#"{"type":"#, generation: generation)
        await Task.yield()

        XCTAssertEqual(ClientFlowDiagnostics.currentPhase, "websocket-decode.failed")
    }

    /// 反向锁：认不出的**类型**是降级，不是失败。
    ///
    /// 收紧的只是「解码失败要留痕」，绝不能顺手把「后端加了新类型而 spec 没跟上时不许整条崩」
    /// 一起收掉 —— 那两条规则的安全方向相反。与 `OrderEnumLeniencyDecodingTests` 同构。
    func testUnknownMessageTypeStillDegradesAndIsNotCountedAsAFailure() async {
        let service = WebSocketService()
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(
            #"{"type":"SOME_TYPE_ADDED_BY_THE_BACKEND_LATER"}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertEqual(ClientFlowDiagnostics.currentPhase, "websocket-decode.applied")
    }

    /// 接单前的派单载荷不得把盲人的自由文本备注带进 App（`AGENTS.md §8`）。
    ///
    /// 两件事一起验，因为它们会以相反的方向坏掉：
    /// - **带 `specialNotes` 的载荷仍要解得出来** —— 后端还在发这个字段，我们只是不声明它。
    ///   要是哪天解码变严了（多余键改成报错之类），派单会整条静默失效，志愿者收不到单，
    ///   而这条路上没有任何用户可见的报错。
    /// - **那段文本不能出现在解出来的对象里** —— 用 `Mirror` 遍历而不是断言某个属性，
    ///   是因为要拦的正是「有人把字段加回来」，针对具体属性写的断言在那种改动下要么编译不过、
    ///   要么根本不存在。已验红：把字段加回 `WSNewOrder`，本用例立刻失败。
    func testNewOrderCarryingSpecialNotesDecodesButNeverReachesTheClient() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        let generation = service.simulateNewTransportForTesting()

        let sensitive = "我有低血糖，如果我说头晕请马上停下来"
        service.simulateTextMessageForTesting(
            #"{"type":"NEW_ORDER","orderId":91,"dispatchTimeoutSeconds":30,"pacePreference":"MODERATE","hasGuideDog":true,"specialNotes":"\#(sensitive)"}"#,
            generation: generation
        )
        await Task.yield()

        guard let order = coordinator.pendingDispatch?.order else {
            return XCTFail("带 specialNotes 的 NEW_ORDER 必须仍然解得出来，否则志愿者会静默收不到派单")
        }
        XCTAssertEqual(order.orderId, 91)
        // 匹配条件照常可见 —— 藏它们会让志愿者盲接，成本落回盲人身上。
        XCTAssertEqual(order.pacePreference, "MODERATE")
        XCTAssertEqual(order.hasGuideDog, true)

        for child in Mirror(reflecting: order).children {
            XCTAssertFalse(
                String(describing: child.value).contains(sensitive),
                "接单前的派单载荷带上了盲人自由文本（属性 \(child.label ?? "?")）。"
                    + "派单是串行的，一单会依次推给多个志愿者，包括最后拒单的那些。"
                    + "详见 WebSocketModels.swift 里 WSNewOrder 上的说明。"
            )
        }
    }

    func testDuplicateNewOrderDoesNotRepublishRetainedPrompt() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        var deliveredOrderIDs: [Int64] = []
        let cancellable = coordinator.$pendingDispatch
            .compactMap { $0?.order.orderId }
            .sink { deliveredOrderIDs.append($0) }
        defer { cancellable.cancel() }

        let message = makeDispatch(orderID: 44)
        service.simulateIncomingEventForTesting(.newOrder(message))
        service.simulateIncomingEventForTesting(.newOrder(message))
        await Task.yield()

        XCTAssertEqual(deliveredOrderIDs, [44])
    }

    private func makeNotification(
        eventID: Int64,
        body: String,
        priority: String,
        eventType: String = "TEST_NOTIFICATION"
    ) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: eventID,
            eventType: eventType,
            title: nil,
            body: body,
            ttsText: body,
            priority: priority,
            timestamp: "2026-07-19T12:00:00Z"
        )
    }

    // MARK: - Emergency copy substitution

    /// End-to-end proof that the backend's completed-tense emergency body never reaches the user.
    ///
    /// `EMERGENCY_CONTACT_NOTIFIED` arrives as an `APP_NOTIFICATION` envelope
    /// (`NotificationService.sendNotification` → `buildEnvelope("APP_NOTIFICATION")`, :93-99) whose
    /// template body is "已通知紧急联系人张三" (`data.sql:72`) — pushed inside the trigger
    /// transaction, before the SMS is even attempted. Rendering it verbatim would tell a blind
    /// runner their family already knows.
    func testEmergencyNotificationBodyIsReplacedWithProgressiveTenseCopy() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
            eventType: "EMERGENCY_CONTACT_NOTIFIED",
            title: nil,
            body: "已通知紧急联系人张三",
            ttsText: "已通知你的联系人张三，请保持冷静",
            priority: "HIGH",
            timestamp: "2026-07-31T12:00:00"
        )))
        await Task.yield()

        let notification = coordinator.currentNotification
        XCTAssertEqual(notification?.displayText, EmergencySafetyCopy.contactNotified)
        XCTAssertEqual(notification?.speechText, EmergencySafetyCopy.contactNotified)
        XCTAssertFalse(notification?.displayText.contains("已通知你的联系人") ?? true)
        XCTAssertFalse(notification?.speechText.contains("已通知你的联系人") ?? true)
        XCTAssertEqual(notification?.priority, .high)
        XCTAssertEqual(coordinator.latestSafetyEvent?.kind, .emergencyContactNotified)
    }

    /// 身份回退：`APP_NOTIFICATION` 没有 `messageId` 时，去重键取 `eventId`。
    /// （原先这里还有一条针对「顶层 `EMERGENCY_CONTACT_NOTIFIED` 类型」的用例，
    /// 那个类型后端从未实现、前端通道已删除，用例随之下线。）
    func testContactNotifiedFallsBackToEventIDWhenMessageIDIsAbsent() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: 77,
            eventType: "EMERGENCY_CONTACT_NOTIFIED",
            title: nil,
            body: "已通过短信通知您的联系人张三",
            ttsText: "已通知你的联系人张三，请保持冷静",
            priority: "HIGH",
            timestamp: nil
        )))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, EmergencySafetyCopy.contactNotified)
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "emergencyContactNotified:77")
    }

    private func makeDispatch(orderID: Int64) -> WSNewOrder {
        WSNewOrder(
            type: WSMessageType.newOrder.rawValue,
            timestamp: nil,
            orderId: orderID,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            distanceKm: nil,
            plannedStart: nil,
            plannedEnd: nil,
            dispatchTimeoutSeconds: 30,
            priority: "HIGH",
            pacePreference: nil,
            hasGuideDog: nil,
            requiresIntroCall: true
        )
    }

    /// 文案刻意与 `makeContactNotified` 保持一致：验证去重键取的是事件 ID 而不是正文。
    private func makeEmergencyResolved(eventID: Int64) -> WSEmergencyResolved {
        WSEmergencyResolved(
            type: WSMessageType.emergencyResolvedByVolunteer.rawValue,
            eventId: eventID,
            message: "安全事件已处理",
            ttsText: "安全事件已处理",
            priority: "HIGH",
            timestamp: "2026-07-19T12:00:00Z"
        )
    }

    /// `EMERGENCY_CONTACT_NOTIFIED` 只以 `APP_NOTIFICATION` 的 `eventType` 出现，没有顶层类型。
    /// `messageId` 留空是刻意的：这样 `routeEmergencyNotification` 的身份回退到 `eventId`，
    /// `stableEventID` 才是 `emergencyContactNotified:<eventID>`。
    private func makeContactNotified(eventID: Int64) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: eventID,
            eventType: "EMERGENCY_CONTACT_NOTIFIED",
            title: nil,
            body: "安全事件已处理",
            ttsText: "安全事件已处理",
            priority: "HIGH",
            timestamp: "2026-07-19T12:00:00Z"
        )
    }
}
