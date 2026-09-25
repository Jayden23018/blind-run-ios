import XCTest
@testable import blindRun

/// 「播报位置」接 `GET /api/orders/{id}/location/address`（后端 issue #387 ①）。
@MainActor
final class LocationAddressAnnouncementTests: XCTestCase {

    /// 🔴 这两条会**真的开口**（先「正在定位」，随即被答句打断），而每个 `SpeechService` 自带一个
    /// `AVSpeechSynthesizer`。用例结束就释放它 = 合成器在念的时候被释放，回调打在野指针上，
    /// 崩在**下一条**用例里（真机实测：紧随其后的 `SafetyServiceTests` 报 `signal segv`，单跑它全绿）。
    /// App 里它是常驻的，所以这里也让它常驻 —— 记忆 `finishedplaying-crash-means-player-freed-not-delegate`。
    private static var retainedSpeechServices: [SpeechService] = []

    private func makeSpeechService() -> SpeechService {
        let service = SpeechService()
        Self.retainedSpeechServices.append(service)
        return service
    }

    // MARK: - 三种答句 + 新鲜度

    func testAddressIsReadWithoutAgeWhenFresh() {
        let response = OrderLocationAddressResponse(formattedAddress: "北山街", latitude: 30.2, longitude: 120.1, ageSeconds: 15, degraded: false)
        XCTAssertEqual(EmergencySafetyCopy.locationAnnouncement(server: response), "你现在在北山街附近。")
    }

    /// 阈值是「超过 15 秒」：15 不说、16 说。取落在两种实现之间的值，才分辨得出 `>` 与 `>=`。
    func testStaleAddressSaysHowOldItIs() {
        let response = OrderLocationAddressResponse(formattedAddress: "北山街", latitude: 30.2, longitude: 120.1, ageSeconds: 16, degraded: false)
        XCTAssertEqual(EmergencySafetyCopy.locationAnnouncement(server: response), "你现在在北山街附近。这是16秒前的位置。")
    }

    func testCoordinatesAreReadWhenTheAddressIsMissing() {
        let response = OrderLocationAddressResponse(latitude: 30.25931, longitude: 120.14803, ageSeconds: 28, degraded: true)
        XCTAssertEqual(
            EmergencySafetyCopy.locationAnnouncement(server: response),
            "暂时查不到地址。你的坐标是北纬30.2593、东经120.1480。这是28秒前的位置。"
        )
    }

    func testNothingFallsBackToTheCallForHelpSentence() {
        let response = OrderLocationAddressResponse(ageSeconds: nil, degraded: true)
        XCTAssertEqual(
            EmergencySafetyCopy.locationAnnouncement(server: response),
            EmergencySafetyCopy.locationAnnouncement(nil)
        )
    }

    /// `ageSeconds` 为 null 时不提 —— 不知道就不说，也不当成 0 秒。
    func testUnknownAgeIsNotMentioned() {
        let response = OrderLocationAddressResponse(formattedAddress: "北山街", ageSeconds: nil, degraded: false)
        XCTAssertFalse(EmergencySafetyCopy.locationAnnouncement(server: response).contains("秒前"))
    }

    func testVolunteerCardShowsThePeersPlaceWithAge() {
        XCTAssertEqual(
            EmergencySafetyCopy.volunteerAlertPlace(server: OrderLocationAddressResponse(formattedAddress: "北山街", ageSeconds: 20, degraded: false)),
            "北山街。这是20秒前的位置。"
        )
        XCTAssertEqual(
            EmergencySafetyCopy.volunteerAlertPlace(server: OrderLocationAddressResponse(latitude: 30.2, longitude: 120.1, ageSeconds: 3, degraded: true)),
            "北纬30.2000、东经120.1000"
        )
        XCTAssertNil(EmergencySafetyCopy.volunteerAlertPlace(server: OrderLocationAddressResponse(degraded: true)))
    }

    // MARK: - 盲人端：本机拿不到时问服务端

    /// 修之前本机没有定位就直接念「定位不到」，一次都不问后端 —— `calls` 为空。
    func testBlindAnnouncementAsksTheServerWhenTheDeviceHasNoLocation() async {
        let safety = FakeSafetyService()
        safety.orderLocationAddressResult = .success(
            OrderLocationAddressResponse(formattedAddress: "北山街", latitude: 30.2, longitude: 120.1, ageSeconds: 20, degraded: false)
        )
        let appState = AppState(safety: safety)
        appState.currentEnvironment = .mock
        let speechService = makeSpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.startPolling(orderId: 612)
        viewModel.stopPolling()

        await viewModel.announceCurrentLocation()

        XCTAssertEqual(safety.lastOrderId, 612)
        XCTAssertEqual(speechService.lastSpokenText, "你现在在北山街附近。这是20秒前的位置。")
    }

    /// 服务端也失败：照旧说「定位不到」，不能一声不吭。
    func testBlindAnnouncementStillSpeaksWhenTheServerFails() async {
        let safety = FakeSafetyService()
        safety.orderLocationAddressResult = .failure(URLError(.timedOut))
        let appState = AppState(safety: safety)
        appState.currentEnvironment = .mock
        let speechService = makeSpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.startPolling(orderId: 613)
        viewModel.stopPolling()

        await viewModel.announceCurrentLocation()

        XCTAssertEqual(speechService.lastSpokenText, EmergencySafetyCopy.locationAnnouncement(nil))
    }
}
