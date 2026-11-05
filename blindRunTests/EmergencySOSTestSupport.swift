import Combine
import CoreLocation
import XCTest
@testable import blindRun

/// SOS trigger, gating, failure branches, and the truthfulness rules around emergency-contact copy.
@MainActor
protocol EmergencySOSTestSupport {}

extension EmergencySOSTestSupport {
    /// 倒计时的替身接缝：跑测时不该真的在办公室里拉响警报，也不该真的震。
    @MainActor
    static func makeCountdownFixture() -> (EmergencyCoordinator, FakeSafetyService) {
        EmergencyAlarm.observerForTesting = { _ in }
        EmergencyHaptics.observerForTesting = { _ in }
        return (EmergencyCoordinator(), FakeSafetyService())
    }

    @MainActor
    static func teardownAlarmObservers() {
        EmergencyAlarm.observerForTesting = nil
        EmergencyHaptics.observerForTesting = nil
    }

    // MARK: - Fixtures

    /// `nonisolated` so it can be called from the detached `locate` closure in the concurrency test.
    nonisolated static func coordinate(
        latitude: Double = 39.9,
        longitude: Double = 116.4
    ) -> LocatedCoordinate {
        LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            system: .gcj02Backend,
            capturedAt: Date(), source: .device
        )
    }

    static func makeOrder(status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 4242,
            status: status,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: "13800000000",
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }

    /// 服务端倒计时的响应形状：`COUNTDOWN` + 截止时刻（无时区 LocalDateTime，整秒）。
    static func countdownResponse(eventId: Int64, secondsFromNow: TimeInterval = 3) -> EmergencyTriggerResponse {
        EmergencyTriggerResponse(
            success: true,
            eventId: eventId,
            status: "COUNTDOWN",
            countdownEndsAt: backendTime(secondsFromNow: secondsFromNow)
        )
    }

    @MainActor
    static func makeRecoverableCoordinator(safety: FakeSafetyService) -> EmergencyCoordinator {
        let coordinator = EmergencyCoordinator()
        // `refreshActiveEvent` 只在装了 provider 时才会去问 —— 志愿者那一侧刻意装不上
        // （`GET /api/emergency/active` 角色限 BLIND），所以对账在那一侧天然是空操作。
        coordinator.observe(AppRealtimeCoordinator(notificationDuration: 60)) { safety }
        return coordinator
    }

    static func backendTime(secondsFromNow: TimeInterval) -> String {
        DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(secondsFromNow))
    }
}

enum EmergencySOSFixtures: EmergencySOSTestSupport {}
