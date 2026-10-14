import CoreLocation
import XCTest
@testable import blindRun

/// #413：授权回调只替「已经有人要过定位」的调用方开定位。
///
/// `CLLocationManager` 一创建就回调一次授权状态。此前回调里无条件 `startUpdating()`，
/// 已授权的设备一启动 App 就在本机持续定位，早于位置轨迹同意（#368）。
///
/// 第一条是复现；其余三条守着「按需启动」不能顺手把授权弹窗之后的启动也删掉 ——
/// 预约页、接单开关、同意页都是先 `requestPermission()` 再 `startUpdating()`，
/// 后者在弹窗还没答时被挡住，全靠授权回调替它补上。
@MainActor
final class LocationServiceAuthorizationTests: XCTestCase {

    private func makeService() -> LocationService {
        let service = LocationService()
        service.interceptLocationManagerForTesting()
        return service
    }

    /// 🔴 复现 #413：没有任何调用方要过定位时，「已授权」的回调不许开定位。
    func testAuthorizationCallbackDoesNotStartUpdatesWhenNobodyAskedForThem() {
        let service = makeService()

        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)

        XCTAssertTrue(service.isAuthorized, "授权状态本身照常记下")
        XCTAssertFalse(service.isUpdatingLocation)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 0)
    }

    /// 先要定位、后答授权弹窗（预约页 / 接单开关 / 同意页的真实顺序）：答「允许」之后要自己开起来。
    func testUpdatesRequestedBeforeAuthorizationStartOnceGranted() {
        let service = makeService()
        service.handleAuthorizationChange(.notDetermined, accuracy: .fullAccuracy)

        service.startUpdating()
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 0, "没授权时被挡住")

        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)

        XCTAssertTrue(service.isUpdatingLocation)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 1)
    }

    /// 要过、又撤回了：之后的授权不能替一个已经不要定位的调用方开。
    func testWithdrawnRequestDoesNotStartOnLaterAuthorization() {
        let service = makeService()
        service.handleAuthorizationChange(.notDetermined, accuracy: .fullAccuracy)
        service.startUpdating()
        service.stopUpdating()

        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)

        XCTAssertFalse(service.isUpdatingLocation)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 0)
    }

    /// 定位开着时去系统设置关掉权限、再打开：恢复原来在跑的定位。
    /// 「拒绝」分支会停掉硬件，但不能把调用方要定位的意图一起抹掉。
    func testUpdatesRunningBeforeRevocationResumeWhenRegranted() {
        let service = makeService()
        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)
        service.startUpdating()
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 1)

        service.handleAuthorizationChange(.denied, accuracy: .fullAccuracy)
        XCTAssertFalse(service.isUpdatingLocation)

        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)

        XCTAssertTrue(service.isUpdatingLocation)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 2)
    }
}
