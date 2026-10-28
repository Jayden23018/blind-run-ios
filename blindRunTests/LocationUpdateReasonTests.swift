import CoreLocation
import SwiftUI
import XCTest
@testable import blindRun

/// #425：持续定位按调用方记意图。`LocationService` 全 App 只有一份，此前 `startUpdating()` /
/// `stopUpdating()` 不分是谁，于是两条路径一直开着：关接单开关只关上报闸、不停硬件；
/// 同行会话结束只关后台模式、不停定位。
///
/// 每条「停了」都配一条「别人还要时不停」的对照：只断「停了」的话，一个关开关就无条件全停的实现也会绿，
/// 而那种实现会停掉同行会话要的定位。
@MainActor
final class LocationUpdateReasonTests: XCTestCase {

    // MARK: - LocationService

    /// 两个调用方都要定位，其中一个撤回：硬件不停。最后一个撤回才停。
    func testHardwareStopsOnlyWhenTheLastReasonIsWithdrawn() {
        let service = Self.makeAuthorizedService()

        service.startUpdating(for: .escortSession)
        service.startUpdating(for: .volunteerDispatch)
        XCTAssertEqual(service.hardwareUpdateStartsForTesting, 1, "第二份意图不重开硬件")

        service.stopUpdating(for: .volunteerDispatch)
        XCTAssertTrue(service.isUpdatingLocation, "同行会话还要，关接单开关不许停掉它")
        XCTAssertEqual(service.updateReasons, [.escortSession])

        service.stopUpdating(for: .escortSession)
        XCTAssertFalse(service.isUpdatingLocation, "最后一份撤回就停")
        XCTAssertTrue(service.updateReasons.isEmpty)
    }

    /// 撤回一份不存在的意图不影响别人：页面重复走 `onDisappear` 是常态。
    func testWithdrawingAReasonThatWasNeverRequestedLeavesOthersRunning() {
        let service = Self.makeAuthorizedService()
        service.startUpdating(for: .blindBooking)

        service.stopUpdating(for: .volunteerOrderDetail)

        XCTAssertTrue(service.isUpdatingLocation)
    }

    /// 全部撤回之后，系统设置里关了又开权限，授权回调不许把定位开回来；还剩一份时要开回来。
    func testAuthorizationRegrantResumesOnlyWhileSomeReasonRemains() {
        let service = Self.makeAuthorizedService()
        service.startUpdating(for: .escortSession)
        service.startUpdating(for: .blindBooking)
        service.stopUpdating(for: .blindBooking)

        Self.toggleAuthorization(service)
        XCTAssertTrue(service.isUpdatingLocation, "同行会话那一份还在，重新授权要恢复")

        service.stopUpdating(for: .escortSession)
        Self.toggleAuthorization(service)
        XCTAssertFalse(service.isUpdatingLocation, "没人要了，授权回调不许替谁开")
    }

    /// `stopAllUpdates` 是账号边界用的：谁的意图都不留。
    func testStopAllWithdrawsEveryReason() {
        let service = Self.makeAuthorizedService()
        service.startUpdating(for: .escortSession)
        service.startUpdating(for: .volunteerActiveOrder)

        service.stopAllUpdates()

        XCTAssertFalse(service.isUpdatingLocation)
        Self.toggleAuthorization(service)
        XCTAssertFalse(service.isUpdatingLocation)
    }

    // MARK: - 接单开关（AppState）

    /// 🔴 复现 #425 第一条：关接单开关之后本机不再定位（此前只关上报闸，硬件一直开着）。
    func testTurningDispatchOffStopsLocationUpdates() {
        let service = Self.makeAuthorizedService()
        let appState = Self.makeVolunteer(userId: 51, service: service)

        appState.volunteerWantsDispatch = true
        XCTAssertTrue(service.isUpdatingLocation, "开着接单开关要为派单定位")
        XCTAssertEqual(service.updateReasons, [.volunteerDispatch])

        appState.volunteerWantsDispatch = false

        XCTAssertFalse(service.isUpdatingLocation, "同意文案：暂停接单后不再为派单获取位置")
        Self.toggleAuthorization(service)
        XCTAssertFalse(service.isUpdatingLocation, "意图要一起撤回，授权回调不许开回来")
    }

    /// 对照：关开关时同行会话还在要定位，硬件照开。
    func testTurningDispatchOffKeepsAnEscortSessionsUpdatesRunning() {
        let service = Self.makeAuthorizedService()
        let appState = Self.makeVolunteer(userId: 52, service: service)
        appState.volunteerWantsDispatch = true
        service.startUpdating(for: .escortSession)

        appState.volunteerWantsDispatch = false

        XCTAssertTrue(service.isUpdatingLocation)
        XCTAssertEqual(service.updateReasons, [.escortSession])
    }

    /// 没有位置轨迹同意时开着开关也不定位；同意之后立刻开（`resumeStandby`：服务端开关本来就开着）。
    func testDispatchLocationWaitsForTheTrackConsent() {
        let service = Self.makeAuthorizedService()
        let appState = Self.makeVolunteer(userId: 53, service: service, consented: false)

        appState.volunteerWantsDispatch = true
        XCTAssertFalse(service.isUpdatingLocation, "没同意不许开（#368）")

        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        XCTAssertTrue(service.isUpdatingLocation, "同意之后开关还开着，就该开始为派单定位")
    }

    /// 开着接单开关切到盲人角色（盲人没同意）：派单那一份要撤回，不能带着陪跑员的意图去盲人端。
    func testDispatchReasonDoesNotFollowTheUserIntoTheBlindRole() {
        let service = Self.makeAuthorizedService()
        let appState = Self.makeVolunteer(userId: 54, service: service)
        appState.volunteerWantsDispatch = true

        appState.switchRole(to: .blind)

        XCTAssertFalse(service.isUpdatingLocation)
        XCTAssertTrue(service.updateReasons.isEmpty)
    }

    /// 盲人角色这一份：同意过就开，换回陪跑员（开关关着）就撤回。
    func testBlindRoleReasonFollowsTheRoleAndItsConsent() {
        let service = Self.makeAuthorizedService()
        let appState = Self.makeVolunteer(userId: 55, service: service)
        appState.recordLocationTrackConsent(.blindLocationTrack)

        appState.switchRole(to: .blind)
        XCTAssertEqual(service.updateReasons, [.blindRole])

        appState.switchRole(to: .volunteer)
        XCTAssertFalse(service.isUpdatingLocation, "陪跑员开关关着，没有理由定位")
    }

    /// 定位服务后注入（真 App 里根视图那一行晚于恢复会话）也要补算：此前同意过的盲人，注入那一刻就该开始定位。
    func testInjectingTheLocationServiceLaterStillAppliesTheRoleIntent() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest(), tokenStore: InMemoryTokenStore())
        appState.accessToken = "token-56"
        appState.userId = 56
        appState.activeRole = .blind
        appState.recordLocationTrackConsent(.blindLocationTrack)
        let service = Self.makeAuthorizedService()

        appState.locationService = service

        XCTAssertEqual(service.updateReasons, [.blindRole])
    }

    // MARK: - 页面修饰符

    /// `requestsLocationUpdates`：页面出现时以自己的名义要，消失时只撤自己那一份（#425 之前三处页面都只开不撤）。
    func testPageModifierRequestsOnAppearAndWithdrawsOnDisappear() async {
        let service = Self.makeAuthorizedService()
        service.startUpdating(for: .escortSession)
        let host = UIHostingController(
            rootView: Color.clear.requestsLocationUpdates(.blindBooking).environmentObject(service)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = host
        window.makeKeyAndVisible()

        let requested = await Self.waitUntil { service.updateReasons.contains(.blindBooking) }
        XCTAssertTrue(requested, "页面出现时没要定位")

        window.rootViewController = nil
        window.isHidden = true
        let withdrawn = await Self.waitUntil { !service.updateReasons.contains(.blindBooking) }
        XCTAssertTrue(withdrawn, "页面消失后没撤回")
        XCTAssertEqual(service.updateReasons, [.escortSession], "只撤自己那一份")
    }

    // MARK: - 同行会话（协调器）

    /// 🔴 复现 #425 第二条：同行会话结束（订单完成）之后本机不再定位。
    func testEscortSessionEndStopsLocationUpdates() async {
        let (coordinator, deps) = Self.makeEscortCoordinator()
        coordinator.updateOwnedOrder(orderID: 301, status: .driverEnRoute)
        let started = await Self.waitUntil { deps.location.updateReasons.contains(.escortSession) }
        XCTAssertTrue(started, "同行会话要以自己的名义开定位")

        coordinator.updateOwnedOrder(orderID: 301, status: .completed)

        XCTAssertFalse(deps.location.isUpdatingLocation, "会话结束不许还在定位")
        Self.toggleAuthorization(deps.location)
        XCTAssertFalse(deps.location.isUpdatingLocation)
        coordinator.reset()
    }

    /// 对照：会话结束时接单开关还开着，派单那一份照开。
    func testEscortSessionEndKeepsDispatchUpdatesRunning() async {
        let (coordinator, deps) = Self.makeEscortCoordinator()
        deps.location.startUpdating(for: .volunteerDispatch)
        coordinator.updateOwnedOrder(orderID: 302, status: .driverEnRoute)
        _ = await Self.waitUntil { deps.location.updateReasons.contains(.escortSession) }

        coordinator.updateOwnedOrder(orderID: 302, status: .completed)

        XCTAssertTrue(deps.location.isUpdatingLocation)
        XCTAssertEqual(deps.location.updateReasons, [.volunteerDispatch])
        coordinator.reset()
    }

    // MARK: - Helpers

    private static func makeAuthorizedService() -> LocationService {
        let service = LocationService()
        service.interceptLocationManagerForTesting()
        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)
        return service
    }

    private static func toggleAuthorization(_ service: LocationService) {
        service.handleAuthorizationChange(.denied, accuracy: .fullAccuracy)
        service.handleAuthorizationChange(.authorizedWhenInUse, accuracy: .fullAccuracy)
    }

    /// `LocationService` 由用例攥着：`AppState` 对它是 `weak`，传临时对象等于传 nil。
    private static func makeVolunteer(userId: Int64, service: LocationService, consented: Bool = true) -> AppState {
        let appState = AppState(
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore()
        )
        appState.currentEnvironment = .mock
        appState.accessToken = "token-\(userId)"
        appState.userId = userId
        appState.activeRole = .volunteer
        appState.locationService = service
        if consented { appState.recordLocationTrackConsent(.volunteerLocationTrack) }
        return appState
    }

    private struct EscortDeps {
        let socket: WebSocketService
        let location: LocationService
    }

    /// 陪跑员端：`DRIVER_EN_ROUTE` 不开后台模式，也不申请临时精确位置，只看意图本身。
    private static func makeEscortCoordinator() -> (LiveEscortSessionCoordinator, EscortDeps) {
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: AppRealtimeCoordinator(),
            reportInterval: 0.05,
            sendLocation: { _, _, _ in }
        )
        let socket = WebSocketService()
        socket.simulateConnectionStateForTesting(.connected)
        coordinator.configure(identityKey: "account:volunteer:token", role: .volunteer, webSocketService: socket)
        let location = makeAuthorizedService()
        coordinator.attachLocationService(location)
        return (coordinator, EscortDeps(socket: socket, location: location))
    }

    private static func waitUntil(timeout: TimeInterval = 1, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
