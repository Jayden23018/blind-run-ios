import CoreLocation
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

    // MARK: - 「精确位置」关闭（#406）

    /// 🔴 本机有新鲜样本、逆地理也查得到、服务端也有地址 —— 三条路都通，一个地名都不许念。
    ///
    /// 服务端那份故意打桩成功：只跳过本机、退到服务端的实现会念出「北山街」，这条就红。
    func testPreciseLocationOffNeitherGeocodesNorAsksTheServer() async {
        let fixture = makeAnnouncementFixture(preciseLocationOff: true)

        await fixture.viewModel.announceCurrentLocation()

        XCTAssertEqual(fixture.places.reverseGeocodeCount, 0, "区域代表点不许拿去逆地理")
        XCTAssertTrue(fixture.safety.calls.isEmpty, "服务端那份同样是模糊点上报，不许问")
        XCTAssertEqual(
            fixture.speechService.lastSpokenText,
            "「精确位置」已关闭，只能拿到大致位置，可能偏差几公里，所以念不出你的准确位置。"
                + "请直接拨打120或110，说明你周围的情况；跑完后可在系统设置里为助盲跑打开「精确位置」。"
        )
    }

    /// 对照：同一套桩、精确位置开着时照常念本机地名。没有它，一个「一律不念」的实现也能让上一条绿。
    func testPreciseLocationOnStillReadsTheDevicePlace() async {
        let fixture = makeAnnouncementFixture(preciseLocationOff: false)

        await fixture.viewModel.announceCurrentLocation()

        XCTAssertEqual(fixture.places.reverseGeocodeCount, 1)
        XCTAssertTrue(fixture.safety.calls.isEmpty, "本机查到了就不该再问服务端")
        XCTAssertEqual(fixture.speechService.lastSpokenText, "你现在在人民公园附近。")
    }

    /// `appState` / `location` 必须由夹具持有：ViewModel 对它们是 weak 引用，夹具函数一返回就被释放，
    /// 等于传了 nil（记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private struct AnnouncementFixture {
        let viewModel: BlindOrderStatusViewModel
        let appState: AppState
        let location: LocationService
        let speechService: SpeechService
        let safety: FakeSafetyService
        let places: CountingPlaceSearchProvider
    }

    private func makeAnnouncementFixture(preciseLocationOff: Bool) -> AnnouncementFixture {
        let safety = FakeSafetyService()
        safety.orderLocationAddressResult = .success(
            OrderLocationAddressResponse(formattedAddress: "北山街", latitude: 30.2, longitude: 120.1, ageSeconds: 3, degraded: false)
        )
        let appState = AppState(safety: safety)
        appState.currentEnvironment = .mock
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 30.2593, longitude: 120.1480),
            capturedAt: Date(),
            horizontalAccuracy: preciseLocationOff ? 5000 : 10
        )
        location.simulatePreciseLocationOffForTesting(preciseLocationOff)
        let places = CountingPlaceSearchProvider(
            place: ResolvedPlace(
                id: "poi", title: "人民公园", addressText: "北山街1号",
                latitude: 30.2593, longitude: 120.1480, source: .deviceLocation
            )
        )
        let speechService = makeSpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(
            appState: appState,
            speechService: speechService,
            locationService: location,
            placeSearchProvider: places
        )
        viewModel.startPolling(orderId: 614)
        viewModel.stopPolling()
        return AnnouncementFixture(
            viewModel: viewModel, appState: appState, location: location,
            speechService: speechService, safety: safety, places: places
        )
    }
}

/// 只数逆地理被调了几次。`blindRunTests.swift` 里那个 `FakePlaceSearchProvider` 是 private 的，且不计数。
@MainActor
private final class CountingPlaceSearchProvider: PlaceSearchProviding {
    var lastErrorMessage: String?
    private(set) var reverseGeocodeCount = 0
    private let place: ResolvedPlace

    init(place: ResolvedPlace) {
        self.place = place
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> ResolvedPlace? {
        reverseGeocodeCount += 1
        return place
    }

    func searchPlaces(keyword: String, near coordinate: CLLocationCoordinate2D?) async -> [ResolvedPlace] {
        []
    }
}
