import Combine
import XCTest
@testable import blindRun

@MainActor
final class AppRealtimeCoordinatorTests: XCTestCase {
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

    private func makeNotification(eventID: Int64, body: String, priority: String) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: eventID,
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
