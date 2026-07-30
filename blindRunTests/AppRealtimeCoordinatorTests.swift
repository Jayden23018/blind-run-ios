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
        service.simulateIncomingEventForTesting(.separationAlert(makeSeparation(eventID: 11)))
        service.simulateIncomingEventForTesting(.separationAlert(makeSeparation(eventID: 12)))
        service.simulateIncomingEventForTesting(.notification(makeNotification(eventID: 2, body: "可丢弃普通通知", priority: "NORMAL")))
        await Task.yield()

        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "separation:11")
        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "separation:12")
        coordinator.dismissCurrentNotification()
        XCTAssertNil(coordinator.currentNotification)
    }

    func testLifecycleTemplateIsSuppressedForActiveOrder() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(9)

        service.simulateIncomingEventForTesting(.notification(makeNotification(eventID: 3, body: "志愿者已到达", priority: "NORMAL")))
        await Task.yield()
        XCTAssertNil(coordinator.currentNotification)
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
            priority: "NORMAL"
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
            priority: "NORMAL"
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
            priority: "NORMAL"
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
        let cancellable = coordinator.peerLocationPublisher.sink { samples.append($0) }
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
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.timestampMilliseconds, 250)
        XCTAssertEqual(
            coordinator.latestPeerLocation(orderID: 7, ownerRole: .volunteer)?.timestampMilliseconds,
            250
        )
    }

    func testDistinctSeparationEventIDsWithSameCopyArePreserved() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(7)

        service.simulateIncomingEventForTesting(.separationAlert(makeSeparation(eventID: 11)))
        service.simulateIncomingEventForTesting(.separationAlert(makeSeparation(eventID: 12)))
        await Task.yield()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "separation:11")
        XCTAssertEqual(coordinator.latestSeparationAlert?.eventID, "12")

        coordinator.dismissCurrentNotification()
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "separation:12")
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

    private func makeNotification(eventID: Int64, body: String, priority: String) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: eventID,
            eventType: "TEST_NOTIFICATION",
            title: nil,
            body: body,
            ttsText: body,
            priority: priority,
            timestamp: "2026-07-19T12:00:00Z"
        )
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
            specialNotes: nil
        )
    }

    private func makeSeparation(eventID: Int64) -> WSSeparationAlert {
        WSSeparationAlert(
            type: WSMessageType.separationAlert.rawValue,
            eventId: eventID,
            orderId: 7,
            distanceMeters: 120,
            message: "请注意与同行者的距离",
            ttsText: "请注意与同行者的距离",
            priority: "HIGH",
            timestamp: "2026-07-19T12:00:00Z"
        )
    }
}
