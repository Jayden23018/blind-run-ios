import CoreLocation
import XCTest
@testable import blindRun

/// #407 第 1 项：陪跑员代发求助与跑者端过同一道精确位置闸。
///
/// 此前陪跑员这边直接拿 `latestBackendSample()`：精确位置关着时那是约 5 公里外的区域代表点，
/// 照样当求助坐标发出去（`AGENTS.md` §6「必须带新鲜的真实 GCJ-02 坐标，拿不到就不发」）。
/// 现在关着时先问一次临时精确位置；仍关着就不发，页面据 `isDefinitelyUnsent` 弹本地拨号兜底。
@MainActor
final class VolunteerEmergencyPreciseLocationTests: XCTestCase {
    /// 精确位置关着、弹窗没人回答：问一次（用途键 `escortRun`），等到超时，一个字节都不发，原因说的是精确位置。
    func testPreciseLocationOffAsksOnceThenSendsNothing() async {
        let location = Self.locationService()
        location.simulatePreciseLocationOffForTesting()
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 1, status: "PENDING"))

        let outcome = await trigger(coordinator, safety: safety, location: location, answerTimeout: 0.3)

        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting, [.escortRun], "关着时要先问一次，且只问一次")
        XCTAssertTrue(safety.calls.isEmpty, "区域代表点发出去了：\(safety.calls)")
        XCTAssertEqual(outcome.state, .unsentNoLocation(.preciseLocationOff))
        XCTAssertTrue(outcome.state.isDefinitelyUnsent, "页面靠它弹本地拨号兜底")
        for word in ["未发出", "精确位置", "120", "110"] {
            XCTAssertTrue(outcome.message.contains(word), "缺「\(word)」：\(outcome.message)")
        }
    }

    /// 弹窗里点了允许：等待中开关打开，就带着真实坐标发出去。
    func testAllowingTemporaryPrecisionDuringTheWaitSendsTheCoordinate() async {
        let location = Self.locationService()
        location.simulatePreciseLocationOffForTesting()
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "CONTACT_NOTIFIED"))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            location.simulatePreciseLocationOffForTesting(false)
        }

        let outcome = await trigger(coordinator, safety: safety, location: location, answerTimeout: 5)

        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)"])
        XCTAssertNotNil(safety.lastTriggerRequest?.gpsLat, "允许之后要带坐标发出")
        XCTAssertEqual(outcome.state, .acknowledged(.contactNotified))
    }

    /// 反向哨兵：精确位置开着时不弹窗、直接用样本 —— 没有它，「一律不发」的实现也能让上面第一条变绿。
    func testPreciseLocationOnSendsWithoutAsking() async {
        let location = Self.locationService()
        location.simulatePreciseLocationOffForTesting(false)
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "PENDING"))

        _ = await trigger(coordinator, safety: safety, location: location, answerTimeout: 5)

        XCTAssertTrue(location.temporaryPreciseLocationRequestsForTesting.isEmpty)
        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)"])
    }

    /// 没同意共享位置（#368）：问了也不会用这个坐标，所以不弹窗；原因说同意，不说精确位置。
    func testWithoutSharingConsentItNeitherAsksNorSends() async {
        let location = Self.locationService()
        location.simulatePreciseLocationOffForTesting()
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }

        let outcome = await trigger(coordinator, safety: safety, location: location, answerTimeout: 5, sharingBlocked: true)

        XCTAssertTrue(location.temporaryPreciseLocationRequestsForTesting.isEmpty)
        XCTAssertTrue(safety.calls.isEmpty)
        XCTAssertEqual(outcome.state, .unsentNoLocation(.locationSharingNotConsented))
    }

    /// 只有「确定一个字节都没发」的两态能如实说「求助没有发出去」；失败 / 冷却都可能是请求到了、回程丢了。
    func testOnlyTheTwoUnsentStatesCountAsDefinitelyUnsent() {
        XCTAssertTrue(EmergencySOSState.unsentNoLocation(.preciseLocationOff).isDefinitelyUnsent)
        XCTAssertTrue(EmergencySOSState.unsentSessionExpired.isDefinitelyUnsent)
        XCTAssertFalse(EmergencySOSState.failed("网络异常").isDefinitelyUnsent)
        XCTAssertFalse(EmergencySOSState.cooldown(retryAfterSeconds: 30).isDefinitelyUnsent)
        XCTAssertFalse(EmergencySOSState.acknowledged(.pending).isDefinitelyUnsent)
        XCTAssertFalse(EmergencySOSState.idle.isDefinitelyUnsent)
    }

    /// 兜底弹窗的话按陪跑员说：只列 120 / 110，不提紧急联系人，不追加「尚未设置联系人」。
    func testVolunteerUnsentCallDialogSpeaksToTheVolunteer() {
        let context = EmergencyCallContext.volunteerCloudUnsent
        XCTAssertTrue(context.dialogMessage.contains("没有发出去"))
        XCTAssertTrue(context.dialogMessage.contains("不会代你发送"), "AGENTS §6：说清 App 不会代你发送求助")
        XCTAssertFalse(context.accessibilityHint.contains("紧急联系人"))
        XCTAssertTrue(context.accessibilityHint.contains("120") && context.accessibilityHint.contains("110"))
        XCTAssertFalse(context.appendsNoContactHint)
    }

    // MARK: - Fixture

    private func trigger(
        _ coordinator: EmergencyCoordinator,
        safety: FakeSafetyService,
        location: LocationService,
        answerTimeout: TimeInterval,
        sharingBlocked: Bool = false
    ) async -> EmergencyCoordinator.TriggerOutcome {
        await coordinator.trigger(
            order: EmergencySOSTests.makeOrder(status: .inProgress),
            role: .volunteer,
            userID: 8,
            safety: safety,
            locate: {
                await EmergencyCoordinator.freshEmergencyCoordinateAskingForPrecision(
                    using: location, sharingBlocked: sharingBlocked, answerTimeout: answerTimeout
                )
            },
            locationFailureReason: {
                EmergencyCoordinator.locationFailureReason(using: location, sharingBlocked: sharingBlocked)
            }
        )
    }

    private static func locationService() -> LocationService {
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            horizontalAccuracy: 10
        )
        return location
    }
}
