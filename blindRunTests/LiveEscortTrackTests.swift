import Combine
import CoreLocation
import XCTest
@testable import blindRun

final class LiveEscortTrackTests: XCTestCase {
    func testWGS84BeijingConvertsToKnownGCJ02Coordinate() throws {
        let sample = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470),
            system: .wgs84Device,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let normalized = try XCTUnwrap(BackendCoordinateNormalizer.normalize(sample))
        XCTAssertEqual(normalized.coordinate.latitude, 39.910226, accuracy: 0.00001)
        XCTAssertEqual(normalized.coordinate.longitude, 116.403714, accuracy: 0.00001)
        XCTAssertEqual(normalized.system, .gcj02Backend)
        XCTAssertEqual(normalized.capturedAt, sample.capturedAt)
    }

    func testOverseasDeviceCoordinateIsNotShifted() throws {
        let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        let normalized = try XCTUnwrap(BackendCoordinateNormalizer.normalize(
            LocatedCoordinate(coordinate: paris, system: .wgs84Device)
        ))
        XCTAssertEqual(normalized.coordinate.latitude, paris.latitude, accuracy: 0.0000001)
        XCTAssertEqual(normalized.coordinate.longitude, paris.longitude, accuracy: 0.0000001)
    }

    func testBackendGCJ02IsNeverConvertedTwice() throws {
        let gcj = CLLocationCoordinate2D(latitude: 39.910226, longitude: 116.403714)
        let normalized = try XCTUnwrap(BackendCoordinateNormalizer.normalize(
            LocatedCoordinate(coordinate: gcj, system: .gcj02Backend)
        ))
        XCTAssertEqual(normalized.coordinate.latitude, gcj.latitude)
        XCTAssertEqual(normalized.coordinate.longitude, gcj.longitude)
    }

    func testFlatProductionAppNotificationDecodesOuterIdentityAndBody() throws {
        let data = try XCTUnwrap(#"{"type":"APP_NOTIFICATION","messageId":"7D42C6B2-54C8-4609-8B46-C465C2B443C0","eventType":"ESCORT_DISTANCE_ALERT","timestamp":"2026-07-21T08:00:00Z","body":"与志愿者的距离似乎有点远","ttsText":"你和志愿者的距离似乎有点远，请留在原地，志愿者正在确认位置","priority":"HIGH"}"#.data(using: .utf8))
        let message = try JSONDecoder().decode(WSAppNotification.self, from: data)
        XCTAssertEqual(message.type, "APP_NOTIFICATION")
        XCTAssertEqual(message.messageId, "7D42C6B2-54C8-4609-8B46-C465C2B443C0")
        XCTAssertEqual(message.eventType, "ESCORT_DISTANCE_ALERT")
        XCTAssertEqual(message.body, "与志愿者的距离似乎有点远")
        XCTAssertEqual(message.timestamp, "2026-07-21T08:00:00Z")
    }

    @MainActor
    func testAlertWithoutOrderIDRequiresOneInProgressOrderAndDeduplicatesMessageID() {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(42, status: .inProgress)
        let message = WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "7D42C6B2-54C8-4609-8B46-C465C2B443C0",
            eventType: "ESCORT_SIGNAL_LOST",
            title: nil,
            body: "暂时无法获取对方位置，正在为你确认安全",
            ttsText: "暂时无法获取志愿者位置，请留在原地，我们正在为你确认安全",
            priority: "HIGH",
            timestamp: "2026-07-21T08:00:00Z"
        )
        coordinator.simulateIncomingEventForTesting(.notification(message))
        coordinator.simulateIncomingEventForTesting(.notification(message))
        XCTAssertEqual(coordinator.latestSeparationAlert?.orderID, 42)
        XCTAssertEqual(coordinator.latestSeparationAlert?.eventType, "ESCORT_SIGNAL_LOST")
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "escort:7D42C6B2-54C8-4609-8B46-C465C2B443C0")
    }

    @MainActor
    func testSafetyLookingNotificationIsNotShownWithoutExactlyOneInProgressOrder() {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)
        coordinator.registerActiveOrder(42, status: .completed)
        coordinator.simulateIncomingEventForTesting(.notification(WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "1F7C8719-0AB3-4F19-949C-5E966307350B",
            eventType: "ESCORT_DISTANCE_ALERT",
            title: nil,
            body: "与志愿者的距离似乎有点远",
            ttsText: "你和志愿者的距离似乎有点远，请留在原地，志愿者正在确认位置",
            priority: "HIGH",
            timestamp: "2026-07-21T08:00:00Z"
        )))
        XCTAssertNil(coordinator.currentNotification)
        XCTAssertNil(coordinator.latestSeparationAlert)
    }

    @MainActor
    func testEventTypeRoutesSafetyWithoutDependingOnDisplayCopy() {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        coordinator.registerActiveOrder(84, status: .inProgress)

        coordinator.simulateIncomingEventForTesting(.notification(WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "B244E7BD-AECB-46B7-8330-615EF1988D17",
            eventType: "ESCORT_DISTANCE_ALERT",
            title: nil,
            body: "后端未来调整后的安全展示文案",
            ttsText: "后端未来调整后的安全朗读文案",
            priority: "HIGH",
            timestamp: "2026-07-21T08:00:01Z"
        )))
        XCTAssertEqual(coordinator.latestSeparationAlert?.eventType, "ESCORT_DISTANCE_ALERT")
        XCTAssertEqual(coordinator.currentNotification?.stableEventID, "escort:B244E7BD-AECB-46B7-8330-615EF1988D17")
    }

    @MainActor
    func testAllFourFrozenRoleSpecificEscortTemplatesRoute() {
        let cases: [(WSRole, String, String, String)] = [
            (
                .blind,
                "与志愿者的距离似乎有点远",
                "你和志愿者的距离似乎有点远，请留在原地，志愿者正在确认位置",
                "ESCORT_DISTANCE_ALERT"
            ),
            (
                .volunteer,
                "与盲人用户的距离似乎有点远",
                "你和盲人用户的距离似乎有点远，请尽快确认对方位置",
                "ESCORT_DISTANCE_ALERT"
            ),
            (
                .blind,
                "暂时无法获取对方位置，正在为你确认安全",
                "暂时无法获取志愿者位置，请留在原地，我们正在为你确认安全",
                "ESCORT_SIGNAL_LOST"
            ),
            (
                .volunteer,
                "暂时无法获取对方位置，正在为你确认安全",
                "暂时无法获取盲人用户位置，请尽快确认对方安全",
                "ESCORT_SIGNAL_LOST"
            )
        ]

        let messageIDs = [
            "00A66495-F821-4FF2-B08F-6BB3F49C6364",
            "4BB9E3C1-C78F-42D7-9EA8-1CEDCAEB32F0",
            "51498EE6-CF31-49D2-A341-A5D8583B8AD2",
            "F571EEA9-933B-4A6F-9DB0-F9A25024D347"
        ]
        for (index, item) in cases.enumerated() {
            let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
            coordinator.attach(to: WebSocketService(), role: item.0)
            coordinator.registerActiveOrder(100 + Int64(index), status: .inProgress)
            coordinator.simulateIncomingEventForTesting(.notification(WSAppNotification(
                type: WSMessageType.appNotification.rawValue,
                eventId: nil,
                messageId: messageIDs[index],
                eventType: item.3,
                title: nil,
                body: item.1,
                ttsText: item.2,
                priority: "HIGH",
                timestamp: "2026-07-21T08:00:00Z"
            )))
            XCTAssertEqual(coordinator.latestSeparationAlert?.eventType, item.3)
            XCTAssertEqual(coordinator.currentNotification?.displayText, item.1)
            XCTAssertEqual(coordinator.currentNotification?.speechText, item.2)
        }
    }

    @MainActor
    func testWrongOrderPeerLocationIsRejected() async {
        let realtime = AppRealtimeCoordinator()
        let service = WebSocketService()
        realtime.attach(to: service, role: .volunteer)
        service.simulateIncomingEventForTesting(.blindLocation(WSBlindLocationUpdate(
            type: "BLIND_LOCATION_UPDATE", orderId: 5, lat: 39.9, lng: 116.4,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000)
        )))
        await Task.yield()
        XCTAssertNil(realtime.latestPeerLocation(orderID: 5, ownerRole: .blind))

        realtime.registerActiveOrder(5, status: .inProgress)
        service.simulateIncomingEventForTesting(.blindLocation(WSBlindLocationUpdate(
            type: "BLIND_LOCATION_UPDATE", orderId: 6, lat: 39.9, lng: 116.4,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000)
        )))
        await Task.yield()
        XCTAssertNil(realtime.latestPeerLocation(orderID: 5, ownerRole: .blind))

        service.simulateIncomingEventForTesting(.blindLocation(WSBlindLocationUpdate(
            type: "BLIND_LOCATION_UPDATE", orderId: 5, lat: 39.9, lng: 116.4,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000)
        )))
        await Task.yield()
        XCTAssertNotNil(realtime.latestPeerLocation(orderID: 5, ownerRole: .blind))
    }

    func testTrackDecodesPartialStatsAndUsesBlindTrackAsPrimaryRoute() throws {
        let json = #"{"status":"COMPLETED","volunteerTrack":[{"lat":39.91,"lng":116.41,"recordedAt":"2026-07-21T08:00:00Z"},{"lat":39.92,"lng":116.42,"recordedAt":"2026-07-21T08:01:00Z"}],"volunteerStats":{"distanceMeters":null,"durationSeconds":null,"avgPaceSecPerKm":null},"blindTrack":[{"lat":39.90,"lng":116.40,"recordedAt":"2026-07-21T08:00:00Z"},{"lat":39.905,"lng":116.405,"recordedAt":"2026-07-21T08:05:00Z"}],"blindStats":{"distanceMeters":820,"durationSeconds":1440,"avgPaceSecPerKm":1756}}"#
        let response = try JSONDecoder().decode(OrderTrackResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.primaryRouteCoordinates.count, 2)
        XCTAssertEqual(response.primaryRouteCoordinates.first?.latitude, 39.90)
        XCTAssertEqual(response.blindStats.distanceText, "820 米")
        XCTAssertTrue(response.spokenSummary.contains("平均配速"))
        XCTAssertNil(response.volunteerStats.distanceText)
    }

    func testEmptyTrackMessageUsesStatusWithoutInventingAnomaly() {
        let response = OrderTrackResponse(
            status: .inProgress,
            volunteerTrack: [],
            volunteerStats: TrackStats(distanceMeters: 0, durationSeconds: 0, avgPaceSecPerKm: nil),
            blindTrack: [],
            blindStats: TrackStats(distanceMeters: 0, durationSeconds: 0, avgPaceSecPerKm: nil)
        )
        XCTAssertEqual(response.emptyStateText, "本次路线仍在采集，暂时没有足够的轨迹点。")
        XCTAssertFalse(response.spokenSummary.contains("异常"))
    }

    func testSingleRawTrackPointIsRetainedButNotDrawable() throws {
        let json = #"{"status":"COMPLETED","volunteerTrack":[],"volunteerStats":{"distanceMeters":0,"durationSeconds":0,"avgPaceSecPerKm":null},"blindTrack":[{"lat":39.90,"lng":116.40,"recordedAt":"2026-07-21T08:00:00Z"}],"blindStats":{"distanceMeters":0,"durationSeconds":0,"avgPaceSecPerKm":null}}"#
        let response = try JSONDecoder().decode(OrderTrackResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.blindTrack.count, 1)
        XCTAssertEqual(response.primaryRouteCoordinates.count, 1)
        XCTAssertEqual(response.emptyStateText, "本次轨迹点不足，暂时无法绘制路线。")
        XCTAssertEqual(response.blindStats.distanceMeters, 0)
        XCTAssertEqual(response.blindStats.durationSeconds, 0)
        XCTAssertNil(response.blindStats.avgPaceSecPerKm)
    }

    func testPolylineIdentityAndSignatureAreStable() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            CLLocationCoordinate2D(latitude: 39.91, longitude: 116.41)
        ]
        let first = MapPolylineItem(id: "blind-primary-route", coordinates: coordinates, isPrimary: true)
        let second = MapPolylineItem(id: "blind-primary-route", coordinates: coordinates, isPrimary: true)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.signature, second.signature)
        XCTAssertTrue(first.isPrimary)
    }

    @MainActor
    func testBothRolesHeartbeatAndCollisionQueuePreservesMessages() {
        XCTAssertTrue(WebSocketService.shouldStartHeartbeat(for: .blind))
        XCTAssertTrue(WebSocketService.shouldStartHeartbeat(for: .volunteer))
        XCTAssertTrue(WSConnectionState.connecting.canSendOrQueueMessages)
        XCTAssertTrue(WSConnectionState.connected.canSendOrQueueMessages)
        XCTAssertFalse(WSConnectionState.reconnecting(attempt: 1).canSendOrQueueMessages)
        XCTAssertFalse(WSConnectionState.disconnected.canSendOrQueueMessages)
        let base = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(
            WebSocketService.requiredSendDelay(lastSend: base, now: base.addingTimeInterval(0.1)),
            0.4,
            accuracy: 0.0001
        )
        let service = WebSocketService()
        service.simulateQueuedMessagesForTesting(count: 2)
        XCTAssertEqual(service.queuedMessageCountForTesting, 2)
        service.disconnect()
        XCTAssertEqual(service.queuedMessageCountForTesting, 0)
    }

    @MainActor
    func testConnectingLocationQueueRetainsOnlyLatestSampleWithoutDroppingReliableMessages() {
        let service = WebSocketService()
        service.simulateQueuedMessagesForTesting(count: 2)
        service.simulateLocationUpdatesForTesting([
            (39.90, 116.40),
            (39.91, 116.41),
            (39.92, 116.42)
        ])
        XCTAssertEqual(
            service.queuedMessageCountForTesting,
            3,
            "Two reliable messages plus only the latest location must remain queued"
        )
        service.disconnect()
        XCTAssertEqual(service.queuedMessageCountForTesting, 0)
    }

    @MainActor
    func testSessionLifecycleEnablesBackgroundOnlyInProgressAndClearsOnTerminalOrIdentityChange() async {
        let realtime = AppRealtimeCoordinator()
        let coordinator = LiveEscortSessionCoordinator(realtimeCoordinator: realtime)
        let service = WebSocketService()
        let location = LocationService()
        coordinator.configure(identityKey: "account-a:blind:token", role: .blind, webSocketService: service)
        coordinator.attachLocationService(location)
        coordinator.updateOwnedOrder(orderID: 8, status: .driverEnRoute)
        await Task.yield()
        XCTAssertTrue(coordinator.isSessionEligible)
        XCTAssertFalse(location.isEscortBackgroundModeEnabled)

        coordinator.updateOwnedOrder(orderID: 8, status: .inProgress)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(location.isEscortBackgroundModeEnabled)
        XCTAssertTrue(
            coordinator.healthState == .permissionRequired || coordinator.healthState == .networkDisconnected
        )

        coordinator.updateOwnedOrder(orderID: 8, status: .completed)
        await Task.yield()
        XCTAssertNil(coordinator.activeOrderID)
        XCTAssertFalse(location.isEscortBackgroundModeEnabled)

        coordinator.updateOwnedOrder(orderID: 9, status: .driverArrived)
        coordinator.configure(identityKey: "account-b:blind:new-token", role: .blind, webSocketService: service)
        await Task.yield()
        XCTAssertNil(coordinator.activeOrderID)
    }

    @MainActor
    func testDuplicateStatusSchedulesOneEscortReconciliationAndReturnsBeforeHungSend() async {
        let realtime = AppRealtimeCoordinator()
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connected)
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            capturedAt: Date()
        )
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: realtime,
            reportInterval: 60,
            sendLocation: { _, _ in
                await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
            }
        )
        coordinator.configure(
            identityKey: "anonymous-session",
            role: .volunteer,
            webSocketService: service,
            locationService: location
        )

        coordinator.updateOwnedOrder(orderID: 88, status: .driverEnRoute)
        coordinator.updateOwnedOrder(orderID: 88, status: .driverEnRoute)
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(coordinator.activeStatus, .driverEnRoute)
        XCTAssertEqual(coordinator.reconciliationCountForTesting, 1)
    }

    @MainActor
    func testRepeatedHealthRefreshPublishesOnlyRealStateChanges() async {
        let realtime = AppRealtimeCoordinator()
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connected)
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            capturedAt: Date(),
            authorized: false
        )
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: realtime,
            reportInterval: 60
        )
        var publishedStates: [LiveEscortHealthState] = []
        let cancellable = coordinator.$healthState
            .dropFirst()
            .sink { publishedStates.append($0) }
        coordinator.configure(
            identityKey: "anonymous-session",
            role: .volunteer,
            webSocketService: service,
            locationService: location
        )
        coordinator.updateOwnedOrder(orderID: 90, status: .driverEnRoute)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(publishedStates, [.permissionRequired])

        for _ in 0..<50 {
            service.simulateConnectionStateForTesting(.connected)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(publishedStates, [.permissionRequired])
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testRepeatedIdenticalDeviceSamplesDoNotRepublishLocationEnvironment() {
        let service = LocationService()
        var presentationChanges = 0
        let cancellable = service.objectWillChange.sink {
            presentationChanges += 1
        }
        let coordinate = CLLocationCoordinate2D(latitude: 25.0402, longitude: 102.7123)

        service.simulateDeviceLocationForTesting(
            coordinate,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        service.simulateDeviceLocationForTesting(
            coordinate,
            capturedAt: Date(timeIntervalSince1970: 1_005)
        )

        XCTAssertEqual(presentationChanges, 1)
        XCTAssertEqual(
            service.latestDeviceSample?.capturedAt,
            Date(timeIntervalSince1970: 1_005)
        )
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testInFlightLocationSendRetainsOnlyLatestSampleForNextSend() async {
        let realtime = AppRealtimeCoordinator()
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connected)
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            capturedAt: Date()
        )
        var sent: [LocatedCoordinate] = []
        var firstSendContinuation: CheckedContinuation<Void, Never>?
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: realtime,
            reportInterval: 60,
            sendLocation: { _, sample in
                sent.append(sample)
                if sent.count == 1 {
                    await withCheckedContinuation { continuation in
                        firstSendContinuation = continuation
                    }
                }
            }
        )
        coordinator.configure(
            identityKey: "anonymous-session",
            role: .volunteer,
            webSocketService: service,
            locationService: location
        )
        coordinator.updateOwnedOrder(orderID: 89, status: .driverEnRoute)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(sent.count, 1)

        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.91, longitude: 116.41),
            capturedAt: Date()
        )
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.92, longitude: 116.42),
            capturedAt: Date()
        )
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(sent.count, 1)

        firstSendContinuation?.resume()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(sent.count, 2)
        XCTAssertNotEqual(sent.first?.coordinate.latitude, sent.last?.coordinate.latitude)
    }

    @MainActor
    func testPeerFreshnessExpiresAfterFifteenSeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let realtime = AppRealtimeCoordinator()
        let service = WebSocketService()
        realtime.attach(to: service, role: .volunteer)
        let coordinator = LiveEscortSessionCoordinator(realtimeCoordinator: realtime)
        coordinator.configure(identityKey: "account:volunteer:token", role: .volunteer, webSocketService: service)
        coordinator.updateOwnedOrder(orderID: 77, status: .inProgress)
        realtime.simulateIncomingEventForTesting(.blindLocation(WSBlindLocationUpdate(
            type: "BLIND_LOCATION_UPDATE",
            orderId: 77,
            lat: 39.9,
            lng: 116.4,
            timestamp: Int64(now.timeIntervalSince1970 * 1_000)
        )))
        XCTAssertNotNil(coordinator.freshPeerCoordinate(now: now.addingTimeInterval(15)))
        XCTAssertNil(coordinator.freshPeerCoordinate(now: now.addingTimeInterval(15.01)))
    }

    @MainActor
    func testStationaryRealLocationContinuesUntilExplicitFailureAndThenRecovers() async {
        let realtime = AppRealtimeCoordinator()
        var sent: [LocatedCoordinate] = []
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: realtime,
            reportInterval: 0.05,
            sendLocation: { _, sample in sent.append(sample) }
        )
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connecting)
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            capturedAt: Date().addingTimeInterval(-60)
        )
        coordinator.configure(identityKey: "account:blind:token", role: .blind, webSocketService: service)
        coordinator.attachLocationService(location)
        coordinator.updateOwnedOrder(orderID: 78, status: .inProgress)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertGreaterThanOrEqual(sent.count, 1)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertGreaterThanOrEqual(sent.count, 2)

        service.simulateConnectionStateForTesting(.connected)
        await Task.yield()
        let beforeFailure = sent.count
        location.simulateLocationFailureForTesting()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(sent.count, beforeFailure)
        XCTAssertEqual(coordinator.healthState, .waitingForLocation)

        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.9001, longitude: 116.4001),
            capturedAt: Date()
        )
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertGreaterThan(sent.count, beforeFailure)
        XCTAssertEqual(coordinator.healthState, .active(background: true))

        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            capturedAt: Date(),
            authorized: false
        )
        service.simulateConnectionStateForTesting(.disconnected)
        service.simulateConnectionStateForTesting(.connected)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(coordinator.healthState, .permissionRequired)
        XCTAssertNil(location.latestEscortBackendSample())
    }

    @MainActor
    func testImmediatePeriodicReconnectSendAndTerminalStop() async {
        let realtime = AppRealtimeCoordinator()
        var sent: [LocatedCoordinate] = []
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: realtime,
            reportInterval: 0.05,
            sendLocation: { _, sample in sent.append(sample) }
        )
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connected)
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470),
            capturedAt: Date()
        )
        coordinator.configure(identityKey: "account:blind:token", role: .blind, webSocketService: service)
        coordinator.attachLocationService(location)
        coordinator.updateOwnedOrder(orderID: 88, status: .driverEnRoute)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertGreaterThanOrEqual(sent.count, 1)
        XCTAssertEqual(sent.last?.system, .gcj02Backend)
        XCTAssertEqual(LiveEscortSessionCoordinator.reportInterval, 5)

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertGreaterThanOrEqual(sent.count, 2)
        let beforeReconnect = sent.count
        service.simulateConnectionStateForTesting(.reconnecting(attempt: 1))
        service.simulateConnectionStateForTesting(.connecting)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertGreaterThan(sent.count, beforeReconnect)

        coordinator.updateOwnedOrder(orderID: 88, status: .cancelled)
        let stoppedCount = sent.count
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(sent.count, stoppedCount)
    }

    @MainActor
    func testCompletedTrackRetryRecoversWithoutRepeatingFinish() async {
        let client = RecoveringTrackAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = CompletedTrackSummaryViewModel()

        await viewModel.load(orderID: 94, appState: appState)
        XCTAssertNil(viewModel.track)
        XCTAssertEqual(viewModel.errorMessage, "本次路线暂时无法加载。")

        await viewModel.load(orderID: 94, appState: appState)
        XCTAssertEqual(viewModel.track?.status, .completed)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(client.requestedPaths, ["/api/orders/94/track", "/api/orders/94/track"])
        XCTAssertEqual(client.requestedMethods, [.get, .get])
    }
}

private final class RecoveringTrackAPIClient: APIClientProtocol, @unchecked Sendable {
    private(set) var requestedPaths: [String] = []
    private(set) var requestedMethods: [HTTPMethod] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requestedMethods.append(method)
        requestedPaths.append(path)
        guard requestedPaths.count > 1 else {
            throw APIError.serverError(
                ErrorResponse(code: "TRACK_UNAVAILABLE", message: "轨迹暂时不可用")
            )
        }
        let json = #"{"status":"COMPLETED","volunteerTrack":[],"volunteerStats":{"distanceMeters":0,"durationSeconds":0,"avgPaceSecPerKm":null},"blindTrack":[],"blindStats":{"distanceMeters":0,"durationSeconds":0,"avgPaceSecPerKm":null}}"#
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}
