import CoreLocation
import XCTest
@testable import blindRun

/// 志愿者端求助强提醒的两条补强（后端 issue #387 ② ④）：
/// App 被杀掉再打开时把强提醒找回来；本机 GPS 还冷着时用服务端算的距离兜底。
@MainActor
final class VolunteerEmergencyRecoveryTests: XCTestCase {

    // MARK: - ② 冷启动恢复

    /// 修之前 `catchUpMissedNotifications` 只在盲人角色调 `/api/emergency/active`，
    /// 志愿者这一侧一次都不问 —— 这条断言在旧代码上 `calls` 为空。
    func testVolunteerSessionAsksForTheRunnersActiveEmergency() async {
        let safety = FakeSafetyService()
        safety.activeEmergencyResult = .success(Self.envelope(id: 901))
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let appState = AppState(safety: safety, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"
        appState.activeRole = .volunteer

        await appState.recoverActiveEmergency()

        XCTAssertEqual(safety.calls, ["activeEmergency()"])
        XCTAssertEqual(appState.emergencyCoordinator.volunteerAlert?.eventID, 901)
        // 那是别人的求助，不能落进「我自己的求助」那一格（屏 3b）。
        XCTAssertNil(appState.emergencyCoordinator.activeEvent)
        XCTAssertEqual(appState.emergencyCoordinator.state, .idle)
        persistence.reset()
    }

    func testRecoveredAlertCountsElapsedTimeFromTheTriggerNotFromAppLaunch() async {
        let safety = FakeSafetyService()
        safety.activeEmergencyResult = .success(Self.envelope(id: 902, triggeredAt: "2026-09-25T10:00:00"))
        let coordinator = EmergencyCoordinator()
        let now = try! XCTUnwrap("2026-09-25T10:02:00".backendTimestamp)

        await coordinator.refreshVolunteerAlert(safety: safety, now: now)

        let alert = try! XCTUnwrap(coordinator.volunteerAlert)
        XCTAssertEqual(now.timeIntervalSince(alert.receivedAt), 120, accuracy: 0.5)
        XCTAssertFalse(alert.isAcknowledged, "没确认过的告警必须重新盖满整屏")
        XCTAssertEqual(alert.message, EmergencySafetyCopy.volunteerAlertNotice)
    }

    /// 服务端时钟比本机快时，「X 秒前」不能变成负数。
    func testTriggerTimeAheadOfTheLocalClockIsClampedToNow() async {
        let safety = FakeSafetyService()
        safety.activeEmergencyResult = .success(Self.envelope(id: 903, triggeredAt: "2026-09-25T10:00:30"))
        let coordinator = EmergencyCoordinator()
        let now = try! XCTUnwrap("2026-09-25T10:00:00".backendTimestamp)

        await coordinator.refreshVolunteerAlert(safety: safety, now: now)

        XCTAssertEqual(coordinator.volunteerAlert?.receivedAt, now)
    }

    /// 倒计时里求助还没发出，在线的志愿者此刻也收不到告警 —— 恢复不能替它弹。
    func testCountdownEventDoesNotRaiseTheAlert() async {
        let safety = FakeSafetyService()
        safety.activeEmergencyResult = .success(Self.envelope(id: 904, status: "COUNTDOWN"))
        let coordinator = EmergencyCoordinator()

        await coordinator.refreshVolunteerAlert(safety: safety)

        XCTAssertNil(coordinator.volunteerAlert)
    }

    func testAlreadyConfirmedEventIsRestoredWithoutTheFullScreen() async {
        let safety = FakeSafetyService()
        safety.activeEmergencyResult = .success(
            Self.envelope(id: 905, volunteerConfirmedAt: "2026-09-25T10:00:20")
        )
        let coordinator = EmergencyCoordinator()

        await coordinator.refreshVolunteerAlert(safety: safety)

        XCTAssertEqual(coordinator.volunteerAlert?.isAcknowledged, true)
    }

    /// 断线期间被本人或客服结束了：本地那条要收起，否则全屏关不掉（它没有关闭按钮）。
    func testNoOpenEventClearsAStaleAlert() async {
        let safety = FakeSafetyService()
        safety.activeEmergencyResult = .success(Self.envelope(id: 906))
        let coordinator = EmergencyCoordinator()
        await coordinator.refreshVolunteerAlert(safety: safety)
        XCTAssertNotNil(coordinator.volunteerAlert)

        safety.activeEmergencyResult = .success(EmergencyActiveEnvelope(success: true, data: nil))
        await coordinator.refreshVolunteerAlert(safety: safety)

        XCTAssertNil(coordinator.volunteerAlert)
    }

    /// 请求失败不许动现状：一次没问到不等于求助结束了。
    func testFailedRecoveryKeepsTheCurrentAlert() async {
        let safety = FakeSafetyService()
        safety.activeEmergencyResult = .success(Self.envelope(id: 907))
        let coordinator = EmergencyCoordinator()
        await coordinator.refreshVolunteerAlert(safety: safety)

        safety.activeEmergencyResult = .failure(URLError(.notConnectedToInternet))
        await coordinator.refreshVolunteerAlert(safety: safety)

        XCTAssertEqual(coordinator.volunteerAlert?.eventID, 907)
    }

    // MARK: - ④ 服务端距离兜底

    func testServerDistanceIsUsedWhenTheDeviceHasNoFix() {
        let alert = VolunteerEmergencyAlert(eventID: 1, orderID: 1, message: "", serverDistanceMeters: 120)
        XCTAssertEqual(alert.distanceText(from: nil), "距你约几十米")
    }

    /// 本机实时定位更准（服务端那份最旧 30 秒），两份都有时用本机的。
    func testDeviceFixWinsOverTheServerDistance() throws {
        let peer = try XCTUnwrap(BackendCoordinateNormalizer.backend(latitude: 30.0, longitude: 120.0))
        let alert = VolunteerEmergencyAlert(
            eventID: 1, orderID: 1, message: "", coordinate: peer, serverDistanceMeters: 5_000
        )
        let device = peer.coordinate
        let local = "距你\(DistanceCalculator.proximityBand(DistanceCalculator.distanceFromDeviceToBackend(deviceCoordinate: device, backendCoordinate: peer.coordinate)))"
        // 用例要能分辨两条路：服务端那份 5 公里 = 「较远」，本机那份不能也是它。
        XCTAssertNotEqual(local, "距你较远")
        XCTAssertEqual(alert.distanceText(from: device), local)
    }

    func testUnknownOrUnrecognisedBandHidesTheDistanceLine() {
        XCTAssertNil(Self.alertMessage(meters: 0, band: "UNKNOWN").fallbackDistanceMeters)
        XCTAssertNil(Self.alertMessage(meters: 10, band: "SOMEWHERE_NEW").fallbackDistanceMeters)
        XCTAssertNil(Self.alertMessage(meters: 10, band: nil).fallbackDistanceMeters)
        XCTAssertEqual(Self.alertMessage(meters: 37, band: "NEARBY").fallbackDistanceMeters, 37)
        XCTAssertNil(VolunteerEmergencyAlert(eventID: 1, orderID: 1, message: "").distanceText(from: nil))
    }

    /// 两个新字段从真实形状的推送里解得出来，旧推送缺它们也照常解。
    func testAlertPayloadDecodesTheDistanceFieldsAndToleratesTheirAbsence() throws {
        let withDistance = """
        {"type":"EMERGENCY_VOLUNTEER_ALERT","eventId":456,"orderId":123,"userId":1,
         "distanceMeters":37,"distanceBand":"NEARBY","message":"m","ttsText":"t","priority":"HIGH",
         "gpsLat":null,"gpsLng":null,"timestamp":"2026-05-23T14:30:00"}
        """
        let decoded = try JSONDecoder().decode(WSEmergencyVolunteerAlert.self, from: Data(withDistance.utf8))
        XCTAssertEqual(decoded.fallbackDistanceMeters, 37)

        let legacy = """
        {"type":"EMERGENCY_VOLUNTEER_ALERT","eventId":456,"orderId":123}
        """
        let old = try JSONDecoder().decode(WSEmergencyVolunteerAlert.self, from: Data(legacy.utf8))
        XCTAssertNil(old.fallbackDistanceMeters)
    }

    // MARK: - Fixtures

    private static func alertMessage(meters: Double?, band: String?) -> WSEmergencyVolunteerAlert {
        WSEmergencyVolunteerAlert(
            type: "EMERGENCY_VOLUNTEER_ALERT", eventId: 1, orderId: 1, userId: nil, message: nil,
            ttsText: nil, priority: nil, gpsLat: nil, gpsLng: nil, timestamp: nil,
            distanceMeters: meters, distanceBand: band
        )
    }

    /// 解码造 fixture，理由见 `EmergencySOSTests.openEventEnvelope`。形状取自
    /// `EmergencyEventResponse.forVolunteer`：坐标恒 null，csNotes 恒 null。
    private static func envelope(
        id: Int64,
        status: String = "CONTACT_NOTIFIED",
        triggeredAt: String = "2026-09-25T10:00:00",
        volunteerConfirmedAt: String? = nil
    ) -> EmergencyActiveEnvelope {
        let confirmed = volunteerConfirmedAt.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"success":true,"code":200,"data":{
          "id":\(id),"orderId":4242,"userId":7,
          "triggeredAt":"\(triggeredAt)","triggerType":"BUTTON",
          "status":"\(status)","hasGpsLocation":true,"gpsLat":null,"gpsLng":null,
          "csNotes":null,"volunteerConfirmedAt":\(confirmed)}}
        """
        // swiftlint:disable:next force_try 桩数据解不出说明这条用例本身写坏了，该当场炸。
        return try! APIPayloadDecoder.decodePayload(
            EmergencyActiveEnvelope.self,
            from: Data(json.utf8),
            decoder: JSONDecoder()
        )
    }
}
