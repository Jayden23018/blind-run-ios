import CoreLocation
import XCTest
@testable import blindRun

/// #368：位置轨迹单独同意（OpenSpec `gate-location-track-on-separate-consent`，来自安卓 #55）。
///
/// 每条「没有同意就拦住」的用例都配一个「同意之后放行」的对照：只断拦住的话，
/// 一个把所有定位都拦掉的实现也会绿。
@MainActor
final class LocationTrackConsentTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EmergencyAlarm.observerForTesting = { _ in }
        EmergencyHaptics.observerForTesting = { _ in }
    }

    // MARK: - 文案

    /// 拒绝反馈三句与安卓逐字一致（告知七条由 `PrivacyConsentTests` 的指纹钉住）。
    func testDeclinedFeedbackMatchesTheAndroidCopyVerbatim() {
        XCTAssertEqual(
            PrivacyConsentPurpose.blindLocationTrack.declinedFeedback,
            "没有开始预约。不同意位置共享就不能预约陪跑，其他功能照常可用。想好了可以再点「预约新的陪跑」。"
        )
        XCTAssertEqual(
            PrivacyConsentPurpose.volunteerLocationTrack.declinedFeedback,
            "没有开始接单。不同意位置共享就不能接单，其他功能照常可用。想好了可以再打开接单开关。"
        )
        let escort = "没有共享位置。这一单对方看不到你的位置，走散提醒和求助定位也用不了；需要的话可以在订单页取消这次陪跑。"
        XCTAssertEqual(PrivacyConsentPurpose.blindLocationTrack.escortDeclinedFeedback, escort)
        XCTAssertEqual(PrivacyConsentPurpose.volunteerLocationTrack.escortDeclinedFeedback, escort)
        XCTAssertEqual(LiveEscortHealthState.locationSharingDeclined.userMessage, escort, "横幅与播报念的就是这一句")
        XCTAssertNil(LiveEscortHealthState.trackConsentRequired.userMessage, "同意页自己在念，横幅不重复")
        for purpose in [PrivacyConsentPurpose.blindLocationTrack, .volunteerLocationTrack] {
            XCTAssertEqual(purpose.title, "陪跑前，请先确认位置共享")
            XCTAssertEqual(purpose.agreeButtonTitle, "同意共享位置")
            XCTAssertEqual(purpose.declineButtonTitle, "先不同意")
            XCTAssertEqual(purpose.disclosures.count, 7)
        }
    }

    // MARK: - 存储

    func testLocationTrackConsentIsPerAccountAndAbsentByDefault() {
        let appState = Self.loggedInAppState(role: .blind, userId: 11)
        XCTAssertFalse(appState.hasLocationTrackConsent(.blindLocationTrack), "后端不存这项同意：本机没有记录就是没同意")

        appState.recordLocationTrackConsent(.blindLocationTrack)
        XCTAssertTrue(appState.hasLocationTrackConsent(.blindLocationTrack))
        XCTAssertFalse(appState.hasLocationTrackConsent(.volunteerLocationTrack), "两个角色分开问")

        appState.userId = 12
        XCTAssertFalse(appState.hasLocationTrackConsent(.blindLocationTrack), "同一台手机换账号要重新问")
        appState.userId = 11
        XCTAssertTrue(appState.hasLocationTrackConsent(.blindLocationTrack), "回到原账号，记录还在盘上")
    }

    func testOnlyTheTwoLocationTrackPurposesGoThroughThisEntry() {
        let appState = Self.loggedInAppState(role: .blind, userId: 13)
        appState.recordLocationTrackConsent(.voiceOrderThirdPartyLLM)
        XCTAssertFalse(appState.hasLocationTrackConsent(.voiceOrderThirdPartyLLM))
        XCTAssertFalse(appState.hasVoiceOrderConsent, "不许经这个入口写别的同意")
    }

    func testUITestLaunchSkipsTheLocationTrackConsentUnlessItIsTheOneUnderTest() {
        XCTAssertTrue(AppState.uiTestSkipsLocationTrackConsent(environment: ["AIDRUN_UI_TEST_RESET_STATE": "1"]))
        XCTAssertFalse(AppState.uiTestSkipsLocationTrackConsent(environment: [
            "AIDRUN_UI_TEST_RESET_STATE": "1",
            "AIDRUN_UI_TEST_FORCE_LOCATION_TRACK_CONSENT": "1"
        ]))
        XCTAssertFalse(AppState.uiTestSkipsLocationTrackConsent(environment: [:]), "真实安装一律要同意")
    }

    // MARK: - 同行态（协调器）

    func testEscortWithoutConsentSendsNothingAndAsksForTheRunnersConsent() async {
        let consent = ConsentRecorder(granted: false)
        var sent = 0
        let (coordinator, service) = Self.makeEscortCoordinator(role: .blind, consent: consent) { sent += 1 }

        coordinator.updateOwnedOrder(orderID: 91, status: .driverEnRoute)
        let asked = await Self.waitUntil { coordinator.pendingTrackConsent == .blindLocationTrack }

        XCTAssertTrue(asked, "没有同意记录要盖同意页")
        _ = await Self.waitUntil(timeout: 0.3) { false }
        XCTAssertEqual(sent, 0, "回答之前一个点都不许发")
        XCTAssertEqual(coordinator.healthState, .trackConsentRequired)
        XCTAssertTrue(coordinator.isLocationSharingBlocked, "求助也不能附位置")
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    func testAgreeingStartsTheEscortSessionAtOnce() async {
        let consent = ConsentRecorder(granted: false)
        var sent = 0
        let (coordinator, service) = Self.makeEscortCoordinator(role: .blind, consent: consent) { sent += 1 }
        coordinator.updateOwnedOrder(orderID: 92, status: .driverEnRoute)
        _ = await Self.waitUntil { coordinator.pendingTrackConsent != nil }

        coordinator.agreeTrackConsent()
        let started = await Self.waitUntil { sent > 0 }

        XCTAssertEqual(consent.recorded, [.blindLocationTrack])
        XCTAssertNil(coordinator.pendingTrackConsent)
        XCTAssertTrue(started, "同意之后立刻开始上报")
        XCTAssertFalse(coordinator.isLocationSharingBlocked)
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    /// 「这一单不再问」：拒绝后同一单进 `IN_PROGRESS` 不再弹，也不上报；换一单要重新问。
    func testDecliningStopsAskingForThisOrderOnlyAndShowsTheConsequence() async {
        let consent = ConsentRecorder(granted: false)
        var sent = 0
        let (coordinator, service) = Self.makeEscortCoordinator(role: .volunteer, consent: consent) { sent += 1 }
        coordinator.updateOwnedOrder(orderID: 93, status: .driverEnRoute)
        let asked = await Self.waitUntil { coordinator.pendingTrackConsent == .volunteerLocationTrack }
        XCTAssertTrue(asked, "陪跑员问的是陪跑员那一份")

        coordinator.declineTrackConsent()
        XCTAssertNil(coordinator.pendingTrackConsent)
        XCTAssertEqual(coordinator.healthState, .locationSharingDeclined)

        coordinator.updateOwnedOrder(orderID: 93, status: .inProgress)
        _ = await Self.waitUntil(timeout: 0.3) { false }
        XCTAssertNil(coordinator.pendingTrackConsent, "这一单不再问")
        XCTAssertEqual(coordinator.healthState, .locationSharingDeclined)
        XCTAssertEqual(sent, 0)
        XCTAssertTrue(consent.recorded.isEmpty, "拒绝不许写成同意")

        coordinator.updateOwnedOrder(orderID: 94, status: .driverEnRoute)
        let askedAgain = await Self.waitUntil { coordinator.pendingTrackConsent == .volunteerLocationTrack }
        XCTAssertTrue(askedAgain, "换了一单要重新问")
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    /// 对照：有同意记录时与改动前完全一样，不问、照常上报。
    func testEscortWithConsentNeverAsks() async {
        let consent = ConsentRecorder(granted: true)
        var sent = 0
        let (coordinator, service) = Self.makeEscortCoordinator(role: .blind, consent: consent) { sent += 1 }

        coordinator.updateOwnedOrder(orderID: 95, status: .inProgress)
        let started = await Self.waitUntil { sent > 0 }

        XCTAssertTrue(started)
        XCTAssertNil(coordinator.pendingTrackConsent)
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    /// 协调器自带的同意依赖是「默认放行」，只给直接构造它的单测用。
    /// `AppState` 装配时必须换成真实的 —— 否则同行态这道闸在 App 里根本不存在。
    func testAppStateWiresTheRealConsentIntoTheEscortCoordinator() async {
        let appState = Self.loggedInAppState(role: .blind, userId: 21)
        let service = WebSocketService()
        appState.webSocketService = service
        let coordinator = appState.liveEscortCoordinator

        coordinator.updateOwnedOrder(orderID: 96, status: .driverEnRoute)
        let asked = await Self.waitUntil { coordinator.pendingTrackConsent == .blindLocationTrack }
        XCTAssertTrue(asked, "AppState 里的协调器没有接上真实的同意记录")

        coordinator.agreeTrackConsent()
        XCTAssertTrue(appState.hasLocationTrackConsent(.blindLocationTrack), "同意要经 AppState 落盘")
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    // MARK: - 求助

    func testBlockedSharingSendsNoEmergencyAndSaysWhy() async {
        let location = Self.locationService()
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 1, status: "CONTACT_NOTIFIED")
        )

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { await EmergencyCoordinator.freshEmergencyCoordinate(using: location, sharingBlocked: true) },
            locationFailureReason: { EmergencyCoordinator.locationFailureReason(using: location, sharingBlocked: true) }
        )

        XCTAssertTrue(safety.calls.isEmpty, "用户说过不共享位置，求助不许把位置带出去")
        XCTAssertEqual(coordinator.state, .unsentNoLocation(.locationSharingNotConsented))
        XCTAssertTrue(outcome.isFailure, "失败态才会出现本地拨号兜底按钮")
        for word in ["未发出", "共享位置", "120", "110"] {
            XCTAssertTrue(outcome.message.contains(word), "缺「\(word)」：\(outcome.message)")
        }
    }

    /// 对照：同一个新鲜样本，没被拦时照常拿到坐标。
    func testUnblockedSharingStillReturnsTheFreshSample() async {
        let location = Self.locationService()

        let coordinate = await EmergencyCoordinator.freshEmergencyCoordinate(using: location, sharingBlocked: false)

        XCTAssertNotNil(coordinate)
        XCTAssertNil(EmergencyCoordinator.locationFailureReason(using: location, sharingBlocked: false))
    }

    // MARK: - 志愿者接单开关

    func testTurningOnWithoutConsentAsksFirstAndSendsNothing() {
        let orders = FakeOrderService()
        let (appState, viewModel, _) = Self.makeVolunteerHome(orders: orders)

        viewModel.setAvailability(true)

        XCTAssertEqual(viewModel.trackConsentRequest, .turnOn)
        XCTAssertFalse(viewModel.isAvailable, "开关不翻")
        XCTAssertEqual(orders.callCount("setDispatchStatus(wantsDispatch:)"), 0, "不发请求")
        XCTAssertFalse(appState.volunteerWantsDispatch)
    }

    func testAgreeingTurnsOnRequestsPermissionAndEntersTheHub() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .success(())
        orders.dispatchSummaryResult = .success(Self.summary(wantsDispatch: true))
        let (appState, viewModel, _) = Self.makeVolunteerHome(orders: orders)
        viewModel.setAvailability(true)
        var permissionRequests = 0

        viewModel.agreeTrackConsent { permissionRequests += 1 }
        let turnedOn = await Self.waitUntil(timeout: 2) { orders.lastWantsDispatch == true }

        XCTAssertTrue(turnedOn, "同意之后才打开开关")
        XCTAssertEqual(permissionRequests, 1, "系统授权框在按同意时弹")
        XCTAssertTrue(viewModel.entersDispatchHubAfterTrackConsent)
        XCTAssertTrue(appState.hasLocationTrackConsent(.volunteerLocationTrack))
        XCTAssertNil(viewModel.trackConsentRequest)
    }

    func testDecliningKeepsTheToggleOffAndExplains() {
        let orders = FakeOrderService()
        let (appState, viewModel, speech) = Self.makeVolunteerHome(orders: orders)
        viewModel.setAvailability(true)

        viewModel.declineTrackConsent()

        let feedback = PrivacyConsentPurpose.volunteerLocationTrack.declinedFeedback
        XCTAssertEqual(viewModel.trackConsentDeclinedNotice, feedback, "滑块上方要留下这句")
        XCTAssertEqual(speech.lastSpokenText, feedback, "也要念出来")
        XCTAssertFalse(viewModel.isAvailable)
        XCTAssertEqual(orders.callCount("setDispatchStatus(wantsDispatch:)"), 0)
        XCTAssertFalse(appState.hasLocationTrackConsent(.volunteerLocationTrack))
    }

    /// 服务端说还在接单、本机没有记录（重装 / 换手机 / 在安卓上同意过）：先问；拒绝就替他关掉服务端开关。
    func testResumedStandbyWithoutConsentAsksAndDeclineTurnsTheServerSwitchOff() async {
        let orders = FakeOrderService()
        orders.setDispatchStatusResult = .success(())
        orders.dispatchSummaryResult = .success(Self.summary(wantsDispatch: false))
        // view model 对 AppState 是 weak：必须攥着，否则下面的判定拿到的是 nil。
        let (appState, viewModel, _) = Self.makeVolunteerHome(orders: orders)

        viewModel.apply(summary: Self.summary(wantsDispatch: true))
        XCTAssertEqual(viewModel.trackConsentRequest, .resumeStandby)

        viewModel.declineTrackConsent()
        let turnedOff = await Self.waitUntil(timeout: 2) { orders.lastWantsDispatch == false }
        XCTAssertTrue(turnedOff, "后端不能一直当他在线却收不到位置")
        withExtendedLifetime(appState) {}
    }

    /// 对照：有记录时服务端开着就照常恢复，不问。
    func testResumedStandbyWithConsentDoesNotAsk() {
        let (appState, viewModel, _) = Self.makeVolunteerHome(orders: FakeOrderService())
        appState.recordLocationTrackConsent(.volunteerLocationTrack)

        viewModel.apply(summary: Self.summary(wantsDispatch: true))

        XCTAssertNil(viewModel.trackConsentRequest)
        XCTAssertTrue(appState.volunteerWantsDispatch)
        XCTAssertTrue(appState.allowsVolunteerDispatchLocationReporting)
    }

    /// 同意文案写着「暂停接单后不再为派单获取位置」：暂停时刷新循环不上报，也不报「定位暂不可用」。
    func testPausedVolunteerDoesNotReportDispatchLocation() async {
        let orders = FakeOrderService()
        orders.dispatchSummaryResult = .success(Self.summary(wantsDispatch: false))
        var reports = 0
        let (appState, viewModel, _) = Self.makeVolunteerHome(orders: orders) { reports += 1; return false }
        appState.recordLocationTrackConsent(.volunteerLocationTrack)

        for _ in 0..<4 {
            await viewModel.reportLocationThenRefreshSummary(currentLocation: nil, locationAuthorized: false)
        }
        XCTAssertEqual(reports, 0)
        XCTAssertNil(viewModel.locationDispatchWarning, "暂停接单的人不该被一句与他无关的警告打断")
        XCTAssertFalse(appState.allowsVolunteerDispatchLocationReporting)

        // 对照：开着开关就照常报。
        orders.dispatchSummaryResult = .success(Self.summary(wantsDispatch: true))
        viewModel.isAvailable = true
        await viewModel.reportLocationThenRefreshSummary(currentLocation: nil, locationAuthorized: false)
        XCTAssertEqual(reports, 1)
    }

    // MARK: - Helpers

    /// 协调器的同意替身：记下写入，`granted` 决定读到什么（写入后也读到 true，与真实存储一致）。
    private final class ConsentRecorder {
        var granted: Bool
        private(set) var recorded: [PrivacyConsentPurpose] = []

        init(granted: Bool) { self.granted = granted }

        var access: LiveEscortTrackConsent {
            LiveEscortTrackConsent(
                isGranted: { [unowned self] _ in self.granted },
                record: { [unowned self] purpose in
                    self.recorded.append(purpose)
                    self.granted = true
                }
            )
        }
    }

    private static func loggedInAppState(
        role: UserRole,
        userId: Int64,
        orders: (any OrderServing)? = nil
    ) -> AppState {
        let appState = AppState(
            orders: orders,
            persistence: AppStatePersistenceFactory.makeIsolatedTest(),
            tokenStore: InMemoryTokenStore()
        )
        appState.currentEnvironment = .mock
        appState.accessToken = "token-\(userId)"
        appState.userId = userId
        appState.activeRole = role
        return appState
    }

    /// 返回的 `WebSocketService` 与 `LocationService` **必须由调用方攥着**：协调器对两者都是 `weak`，
    /// 传临时对象等于传 nil（记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private static func makeEscortCoordinator(
        role: UserRole,
        consent: ConsentRecorder,
        onSend: @escaping @MainActor () -> Void
    ) -> (LiveEscortSessionCoordinator, EscortDeps) {
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: AppRealtimeCoordinator(),
            reportInterval: 0.05,
            sendLocation: { _, _, _ in await onSend() }
        )
        coordinator.trackConsent = consent.access
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connected)
        coordinator.configure(identityKey: "account:\(role):token", role: role, webSocketService: service)
        let location = locationService()
        coordinator.attachLocationService(location)
        return (coordinator, EscortDeps(service: service, location: location))
    }

    private struct EscortDeps {
        let service: WebSocketService
        let location: LocationService
    }

    private static func makeVolunteerHome(
        orders: FakeOrderService,
        report: @escaping @MainActor () -> Bool = { true }
    ) -> (AppState, VolunteerHomeViewModel, SpeechService) {
        let appState = loggedInAppState(role: .volunteer, userId: Int64.random(in: 1_000...9_999_999), orders: orders)
        let speech = SpeechService()
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, _, _ in report() }
        )
        viewModel.configure(with: appState, speechService: speech)
        return (appState, viewModel, speech)
    }

    private static func summary(wantsDispatch: Bool) -> VolunteerDispatchSummaryResponse {
        let json = #"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":\#(wantsDispatch)}"#
        // swiftlint:disable:next force_try 桩数据解不出说明这条用例本身写坏了，该当场炸。
        return try! JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data(json.utf8))
    }

    private static func locationService() -> LocationService {
        let location = LocationService()
        location.simulatePreciseLocationOffForTesting(false)
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            horizontalAccuracy: 10
        )
        return location
    }

    private static func makeOrder(status: RunOrderStatus) -> OrderDetailResponse {
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
            volunteerPhone: nil,
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

    /// 轮询到条件成立或超时。`{ false }` 当作「等一小段」用。
    private static func waitUntil(timeout: TimeInterval = 1, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
