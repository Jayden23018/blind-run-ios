import XCTest
@testable import blindRun

/// #530：陪跑员端「隐私与授权」撤回位置轨迹同意。断言打在服务端开关与定位意图上，不打在文案上。
@MainActor
final class VolunteerPrivacyAuthorizationTests: XCTestCase {

    /// 🔴 开着接单开关时撤回：开关要同步关掉（服务端也关），否则服务端一直当他在线、却收不到他的位置。
    func testRevokingWhileDispatchingTurnsDispatchOffOnTheServer() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .success(())
        let (appState, home) = makeVolunteerHome(orders: orders)
        home.isAvailable = true

        let notice = await VolunteerLocationConsentRevocation.revoke(appState: appState, homeViewModel: home)

        XCTAssertEqual(notice, VolunteerPrivacyCopy.revokedAndPausedDispatch)
        XCTAssertEqual(orders.lastWantsDispatch, false, "服务端的接单开关没关")
        XCTAssertFalse(home.isAvailable)
        XCTAssertFalse(appState.hasLocationTrackConsent(.volunteerLocationTrack))
    }

    /// 🔴 审查 A：服务端没关成就不撤 —— 否则页面说「已关闭」，开关却还开着、服务端还当他在线，而本机同意已删。
    func testFailingToTurnDispatchOffKeepsTheConsentAndSaysSo() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .failure(URLError(.notConnectedToInternet))
        let (appState, home) = makeVolunteerHome(orders: orders)
        home.isAvailable = true

        let notice = await VolunteerLocationConsentRevocation.revoke(appState: appState, homeViewModel: home)

        XCTAssertEqual(notice, VolunteerPrivacyCopy.dispatchOffFailed)
        XCTAssertTrue(appState.hasLocationTrackConsent(.volunteerLocationTrack), "开关没关成，同意不许先删")
        XCTAssertTrue(home.isAvailable)
    }

    /// 对照：开关本来关着就只撤回，不发多余的请求。
    func testRevokingWhileNotDispatchingOnlyRevokes() async {
        let orders = FakeOrderService()
        let (appState, home) = makeVolunteerHome(orders: orders)

        let notice = await VolunteerLocationConsentRevocation.revoke(appState: appState, homeViewModel: home)

        XCTAssertEqual(notice, VolunteerPrivacyCopy.revoked)
        XCTAssertFalse(appState.hasLocationTrackConsent(.volunteerLocationTrack))
        _ = await waitUntil(timeout: 0.3) { false }
        XCTAssertNil(orders.lastWantsDispatch, "开关本来关着，不该再发请求")
    }

    /// 陪跑进行中拒绝撤回，同意与开关都不动（同盲人端）。
    func testRevokingIsRefusedDuringAnEscortSession() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .success(())
        let (appState, home) = makeVolunteerHome(orders: orders)
        home.isAvailable = true
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 88, status: .driverEnRoute)

        let notice = await VolunteerLocationConsentRevocation.revoke(appState: appState, homeViewModel: home)

        XCTAssertEqual(notice, PrivacyAuthorizationCopy.locationBlockedDuringEscort)
        XCTAssertTrue(appState.hasLocationTrackConsent(.volunteerLocationTrack))
        XCTAssertTrue(home.isAvailable, "陪跑中开关也不许动")
        XCTAssertNil(orders.lastWantsDispatch, "陪跑中不许发关开关的请求")
        appState.liveEscortCoordinator.reset()
    }

    // MARK: - Helpers

    private func makeVolunteerHome(orders: FakeOrderService) -> (AppState, VolunteerHomeViewModel) {
        let appState = AppState(
            orders: orders,
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore()
        )
        appState.currentEnvironment = .mock
        appState.accessToken = "token-71"
        appState.userId = 71
        appState.activeRole = .volunteer
        appState.recordLocationTrackConsent(.volunteerLocationTrack)
        let home = VolunteerHomeViewModel(dispatchPropagationDelay: 0, reportVolunteerLocation: { _, _, _ in true })
        home.configure(with: appState, speechService: SpeechService())
        return (appState, home)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
