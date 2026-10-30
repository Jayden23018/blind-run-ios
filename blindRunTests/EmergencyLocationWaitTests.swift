import CoreLocation
import XCTest
@testable import blindRun

/// #597：求助等新定位的 5 秒里，精确位置可能被收回（临时授权到期、用户去设置里关掉）。
/// 入口那道闸已经过了，这时送来的新鲜样本是约 5 公里偏差的区域代表点，不能当求助坐标发出去。
@MainActor
final class EmergencyLocationWaitTests: XCTestCase {

    /// 🔴 等到一半精确位置被收回：不返回那份区域代表点，也不再等完剩下的时间。
    /// 2 秒的上限分得开「立刻放弃」和「滤掉样本但等满 5 秒」。
    func testRevokingPreciseLocationDuringTheWaitDropsTheRegionalSampleAndStopsWaiting() async {
        let location = Self.locationServiceWithoutASample()
        let startedAt = Date()

        async let coordinate = EmergencyCoordinator.freshEmergencyCoordinate(using: location, environment: [:])
        await Self.waitUntilThePollIsAsleep()
        location.simulatePreciseLocationOffForTesting()
        Self.deliverSample(to: location, horizontalAccuracy: 5000)
        let result = await coordinate

        XCTAssertNil(result, "收回之后送来的区域代表点不许当求助坐标")
        XCTAssertEqual(
            EmergencyCoordinator.locationFailureReason(using: location),
            .preciseLocationOff,
            "文案要说开关的问题，不是叫人到室外"
        )
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2, "开关问题不该白等完 5 秒")
    }

    /// 对照：精确位置一直开着，等到的新样本照常返回。
    /// 只断上一条的话，一个把等待期间的样本全丢掉的实现也会绿。
    func testASampleArrivingDuringTheWaitIsReturnedWhilePreciseLocationStaysOn() async {
        let location = Self.locationServiceWithoutASample()

        async let coordinate = EmergencyCoordinator.freshEmergencyCoordinate(using: location, environment: [:])
        await Self.waitUntilThePollIsAsleep()
        Self.deliverSample(to: location, horizontalAccuracy: 10)
        let result = await coordinate

        XCTAssertNotNil(result)
    }

    // MARK: - 夹具

    private static func locationServiceWithoutASample() -> LocationService {
        let location = LocationService()
        location.simulateMissingDeviceLocationForTesting()
        location.simulatePreciseLocationOffForTesting(false)
        return location
    }

    /// 比轮询的第一次 0.5 秒睡眠短：醒来时它正睡着，下一次取样才看得见这里做的改动。
    private static func waitUntilThePollIsAsleep() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    private static func deliverSample(to location: LocationService, horizontalAccuracy: Double) {
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            horizontalAccuracy: horizontalAccuracy
        )
    }
}
