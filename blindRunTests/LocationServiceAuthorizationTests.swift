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

    /// 迟到的「系统暂停了定位」回调不能把已经撤回的意图重新立起来。
    func testPausedCallbackAfterStopDoesNotRestartUpdates() {
        let service = makeService()
        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)
        service.startUpdating()
        service.stopUpdating()

        service.handlePausedLocationUpdates()

        XCTAssertFalse(service.isUpdatingLocation)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 1)
    }

    /// 上面几条直接调 `handleAuthorizationChange`；这一条守 delegate 回调真的转到它。
    /// 用「先要定位、后授权」的场景：转发断了的话，授权之后定位开不起来。
    func testDelegateAuthorizationCallbackReachesTheSameRule() async throws {
        let service = makeService()
        service.handleAuthorizationChange(.notDetermined, accuracy: .fullAccuracy)
        service.startUpdating()

        service.locationManagerDidChangeAuthorization(StubLocationManager(status: .authorizedWhenInUse))

        // 回调里切回主线程的 Task 要让一拍才执行。
        for _ in 0..<50 where service.hardwareUpdateStartsForTesting == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(service.isAuthorized)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 1)
    }
}

/// #417：持续定位不跨会话、不跨角色。账号 A 同意并开了定位，退出后没同意的账号 B 在同一进程里登录，
/// 本机不许还在定位；「要定位」的意图也要一起撤回，否则 B 在系统设置里改一次权限，授权回调就把它恢复起来。
///
/// `LocationService` 由用例攥着：`AppState` 对它是 `weak`，传临时对象等于传 nil。
@MainActor
final class LocationSessionBoundaryTests: XCTestCase {

    private func makeAuthorizedService() -> LocationService {
        let service = LocationService()
        service.interceptLocationManagerForTesting()
        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)
        return service
    }

    private func makeLoggedInAppState(role: UserRole?, userId: Int64, service: LocationService) -> AppState {
        let appState = AppState(
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore()
        )
        appState.currentEnvironment = .mock
        appState.accessToken = "token-\(userId)"
        appState.userId = userId
        appState.activeRole = role
        appState.locationService = service
        return appState
    }

    /// 授权先撤回、再恢复：#413 之后拒绝分支只停硬件不清意图，意图还在的话这一下就会把定位开回来。
    private func toggleAuthorization(_ service: LocationService) {
        service.handleAuthorizationChange(.denied, accuracy: .fullAccuracy)
        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)
    }

    /// 🔴 复现 #417：退出登录后不再定位，之后的授权回调也不恢复。
    func testLogoutStopsUpdatesAndLaterAuthorizationDoesNotResumeThem() {
        let service = makeAuthorizedService()
        let appState = makeLoggedInAppState(role: .volunteer, userId: 41, service: service)
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        service.startUpdating()
        XCTAssertTrue(service.isUpdatingLocation)

        appState.clearSession()

        XCTAssertFalse(service.isUpdatingLocation, "退出登录后本机不许还在定位")
        toggleAuthorization(service)
        XCTAssertFalse(service.isUpdatingLocation, "意图要一起撤回，授权回调不许替上一个账号重新开")
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 1)
    }

    /// 退出时已经没有角色（停在角色选择页）也要停：角色从 nil 到 nil 不经过角色变化那一道。
    func testLogoutFromRoleSelectionStillStopsUpdates() {
        let service = makeAuthorizedService()
        let appState = makeLoggedInAppState(role: nil, userId: 42, service: service)
        service.startUpdating()
        XCTAssertTrue(service.isUpdatingLocation)

        appState.clearSession()

        XCTAssertFalse(service.isUpdatingLocation)
        toggleAuthorization(service)
        XCTAssertFalse(service.isUpdatingLocation)
    }

    /// 换账号但角色不变：不经过角色那一道，换成的账号没同意也要停。
    func testSwitchingToAnAccountWithoutTrackConsentStopsUpdatesEvenWhenTheRoleStaysTheSame() {
        let service = makeAuthorizedService()
        let appState = makeLoggedInAppState(role: .volunteer, userId: 45, service: service)
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        service.startUpdating()

        appState.userId = 46

        XCTAssertFalse(service.isUpdatingLocation, "账号 46 没同意过位置轨迹")
        toggleAuthorization(service)
        XCTAssertFalse(service.isUpdatingLocation)
    }

    /// 切到一个没有位置轨迹同意的角色：停掉，之后的授权回调也不恢复。
    func testSwitchingToARoleWithoutTrackConsentStopsUpdates() {
        let service = makeAuthorizedService()
        let appState = makeLoggedInAppState(role: .volunteer, userId: 43, service: service)
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        service.startUpdating()

        appState.switchRole(to: .blind)

        XCTAssertFalse(service.isUpdatingLocation, "盲人角色没同意过位置轨迹")
        toggleAuthorization(service)
        XCTAssertFalse(service.isUpdatingLocation)
    }

    /// 对照：新角色也同意过，就别停 —— 只断「停了」的话，一个换角色就无条件停的实现也会绿。
    func testSwitchingToARoleWithTrackConsentKeepsUpdatesRunning() {
        let service = makeAuthorizedService()
        let appState = makeLoggedInAppState(role: .volunteer, userId: 44, service: service)
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        appState.recordLocationTrackConsent(.blindLocationTrack)
        service.startUpdating()

        appState.switchRole(to: .blind)

        XCTAssertTrue(service.isUpdatingLocation)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 1, "没有停了又开")
    }
}

/// 授权状态由用例给定的 `CLLocationManager` 替身。不设 delegate，自己不会触发任何回调。
private final class StubLocationManager: CLLocationManager {
    private let stubStatus: CLAuthorizationStatus

    init(status: CLAuthorizationStatus) {
        stubStatus = status
        super.init()
    }

    override var authorizationStatus: CLAuthorizationStatus { stubStatus }
    override var accuracyAuthorization: CLAccuracyAuthorization { .fullAccuracy }
}
