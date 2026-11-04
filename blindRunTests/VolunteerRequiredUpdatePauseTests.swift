import XCTest
@testable import blindRun

/// #668：必须更新的弹窗出现时自动关掉陪跑员的接单开关。断言打在服务端请求、本地开关与弹窗正文上。
@MainActor
final class VolunteerRequiredUpdatePauseTests: XCTestCase {

    // MARK: 关开关

    /// 开着 → 先打服务端，成功后本地开关与档案缓存才一起翻成关。
    func testSwitchOnIsTurnedOffOnTheServerAndLocally() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .success(())
        let (appState, home) = makeVolunteerHome(orders: orders)
        appState.updateVolunteerProfile(VolunteerProfileResponse(name: "王", isAvailable: true, wantsDispatch: true))
        home.isAvailable = true

        let result = await home.pauseDispatchForRequiredUpdate(appState: appState)

        XCTAssertEqual(result, .paused)
        XCTAssertEqual(orders.lastWantsDispatch, false, "服务端的接单开关没关")
        XCTAssertFalse(home.isAvailable)
        XCTAssertFalse(appState.volunteerWantsDispatch, "位置上报读这一份，必须跟着停")
        XCTAssertEqual(appState.volunteerProfile?.isAvailable, false, "档案缓存还是开着，重建首页时开关会弹回开")
        XCTAssertEqual(appState.volunteerProfile?.name, "王", "其他字段不许被冲掉")
        XCTAssertFalse(home.isUpdatingAvailability)
    }

    /// 🔴 服务端没关成：开关保持开着，如实返回 `.failed`，不许假装暂停了。
    func testFailureKeepsTheSwitchOnAndReportsFailure() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .failure(URLError(.notConnectedToInternet))
        let (appState, home) = makeVolunteerHome(orders: orders)
        home.isAvailable = true

        let result = await home.pauseDispatchForRequiredUpdate(appState: appState)

        XCTAssertEqual(result, .failed)
        XCTAssertTrue(home.isAvailable, "服务端还当他在线，本地不能先显示关")
        XCTAssertFalse(home.isUpdatingAvailability, "失败后开关不能卡在『正在改』")
    }

    /// 本来就关着：不发请求，返回 nil，弹窗不会说「已暂停」。
    func testSwitchAlreadyOffSendsNothing() async {
        let orders = FakeOrderService()
        let (appState, home) = makeVolunteerHome(orders: orders)

        let result = await home.pauseDispatchForRequiredUpdate(appState: appState)

        XCTAssertNil(result)
        XCTAssertNil(orders.lastWantsDispatch)
    }

    /// 别的开关请求正在途：让给它，不并发打第二个。
    func testWhileAnotherSwitchRequestIsInFlightItStepsAside() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .success(())
        let (appState, home) = makeVolunteerHome(orders: orders)
        home.isAvailable = true
        home.isUpdatingAvailability = true

        let result = await home.pauseDispatchForRequiredUpdate(appState: appState)

        XCTAssertNil(result)
        XCTAssertNil(orders.lastWantsDispatch)
        XCTAssertTrue(home.isAvailable)
    }

    // MARK: 弹窗状态

    private final class Source: AppUpdateSource {
        var response: AppVersionResponse
        init(min: String?) {
            response = AppVersionResponse(
                iosMinSupportedVersion: min, iosLatestVersion: nil, iosUpdateUrl: "https://apps.apple.com/cn/app/aidrun"
            )
        }
        func appVersionRequirements() async throws -> AppVersionResponse { response }
        func appUpdateOrderPresence() async -> AppUpdateOrderPresence { .none }
    }

    private func makeGate() -> AppUpdateGate {
        AppUpdateGate(currentVersion: "1.0", persistence: AppStatePersistenceFactory.makeIsolatedTest())
    }

    /// 正文只在有结果时才追加：没试过不说话（避免对本来就关着的人说「已暂停」）。
    func testAlertNoteOnlySpeaksForARealOutcome() {
        XCTAssertEqual(AppUpdateCopy.dispatchPauseNote(.idle), "")
        XCTAssertEqual(AppUpdateCopy.dispatchPauseNote(.paused), "已暂停接单，更新后请重新打开。")
        XCTAssertTrue(AppUpdateCopy.dispatchPauseNote(.failed).contains("没能"))
    }

    /// 去 App Store 绕一圈回来弹窗再出现：关成功的那句仍然是真的，保留；关失败的复位，让这次弹窗再试一次。
    func testPausedSurvivesClosingTheAlertButFailedIsRetried() async {
        let source = Source(min: "1.2")
        let gate = makeGate()
        await gate.refresh(from: source)
        gate.recordDispatchPause(.paused)
        gate.promptDidClose()
        XCTAssertEqual(gate.dispatchPause, .paused)

        await gate.refresh(from: source)
        gate.recordDispatchPause(.failed)
        gate.promptDidClose()
        XCTAssertEqual(gate.dispatchPause, .idle)
    }

    /// 要求消失（已更新）就复位：之后再出现新要求，从头判。
    func testRequirementGoingAwayResetsThePause() async {
        let source = Source(min: "1.2")
        let gate = makeGate()
        await gate.refresh(from: source)
        gate.recordDispatchPause(.paused)

        source.response = AppVersionResponse(
            iosMinSupportedVersion: "1.0", iosLatestVersion: nil, iosUpdateUrl: "https://apps.apple.com/cn/app/aidrun"
        )
        await gate.refresh(from: source)

        XCTAssertEqual(gate.presentation, .none)
        XCTAssertEqual(gate.dispatchPause, .idle)
    }

    // MARK: Fixtures

    private func makeVolunteerHome(orders: FakeOrderService) -> (AppState, VolunteerHomeViewModel) {
        let appState = AppState(
            orders: orders,
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore()
        )
        appState.currentEnvironment = .mock
        appState.accessToken = "token-668"
        appState.userId = 668
        appState.activeRole = .volunteer
        let home = VolunteerHomeViewModel(dispatchPropagationDelay: 0, reportVolunteerLocation: { _, _, _ in true })
        home.configure(with: appState, speechService: SpeechService())
        return (appState, home)
    }
}
