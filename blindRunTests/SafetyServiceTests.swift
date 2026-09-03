import XCTest
@testable import blindRun

/// 求助·通话磨合·轨迹片的 service 层端点映射。
///
/// 分工与 `AuthServiceTests` 相同：路径字面量本身由 `scripts/validate-spec-coverage.mjs`
/// 对着后端契约撞，这里只管「**这个方法**打的是不是**那一条**」—— 那个脚本看不出
/// `cancelEmergencyByOwner` 打成了 `/api/emergency/{id}/volunteer-response`。
///
/// 这一组在本片格外要紧：迁移前这些断言寄生在各测试文件的 `APIClientProtocol` 桩上
/// （桩按 path 分支决定返回什么），桩一换成 service 替身就全没了。
final class SafetyServiceTests: XCTestCase {

    // MARK: - 求助

    func testTriggerEmergencyPostsTheRequestBody() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmergencyTriggerResponse(success: true, eventId: 1, status: "PENDING")

        _ = try await SafetyService(transport: transport)
            .triggerEmergency(EmergencyTriggerRequest(orderId: 4242, gpsLat: 39.915, gpsLng: 116.404))

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.path, "/api/emergency/trigger")
        let body = try XCTUnwrap(sent.body as? EmergencyTriggerRequest)
        XCTAssertEqual(body.orderId, 4242, "orderId 是必填的：求助必须挂在一单进行中的服务上")
        XCTAssertEqual(body.gpsLat ?? 0, 39.915, accuracy: 0.000001)
    }

    func testActiveEmergencyIsAGet() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmergencyActiveEnvelope(success: true, data: nil)

        _ = try await SafetyService(transport: transport).activeEmergency()

        XCTAssertEqual(transport.requests.first?.method, .get)
        XCTAssertEqual(transport.requests.first?.path, "/api/emergency/active")
    }

    func testCancelByOwnerPutsToTheEventsOwnPath() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmergencyCancelResponse(success: true, eventId: 77, status: "FALSE_ALARM")

        _ = try await SafetyService(transport: transport).cancelEmergencyByOwner(eventId: 77)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .put)
        XCTAssertEqual(sent.path, "/api/emergency/77/cancel")
    }

    /// 🚨 `action` 只能是 `NEED_HELP`，而且 service 层写死它、不开成参数。
    ///
    /// `FALSE_ALARM` 后端恒 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`：一对一陪跑里志愿者
    /// 可能就是威胁来源，撤销权只在受助者本人和客服手里（`AGENTS.md` §6）。
    /// 这条用例守的是「这条红线不会因为某个调用点手滑而破」——
    /// 把 `action` 改回参数，它不会红；把默认值改成别的，它立刻红。
    func testVolunteerAcknowledgementCanOnlyEverSendNeedHelp() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = VolunteerEmergencyAcknowledgement(success: true, eventId: 77, action: "NEED_HELP")

        _ = try await SafetyService(transport: transport).acknowledgeEmergencyAsVolunteer(eventId: 77)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .put)
        XCTAssertEqual(sent.path, "/api/emergency/77/volunteer-response")
        XCTAssertEqual(sent.query, ["action": "NEED_HELP"])
    }

    // MARK: - 通话磨合

    func testIntroCallReadsTheCallEndpointNotTheOrder() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = try Self.decode(
            IntroCallView.self,
            #"{"counterpartName":"张*","counterpartPhone":null,"counterpartPhoneMasked":"138****1234","myDecision":null,"windowEndsAt":null,"startAddress":null,"plannedStartTime":null,"plannedEndTime":null}"#
        )

        _ = try await SafetyService(transport: transport).introCall(orderId: 42)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .get)
        XCTAssertEqual(
            sent.path,
            "/api/orders/42/intro-call",
            "通话期 order.volunteer 还是 null，打订单详情会 403"
        )
    }

    func testIntroCallDecisionPostsTheDecisionBody() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmptyResponse()

        try await SafetyService(transport: transport)
            .submitIntroCallDecision(orderId: 42, decision: .decline)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.path, "/api/orders/42/intro-call/decision")
        XCTAssertEqual(try XCTUnwrap(sent.body as? IntroCallDecisionRequest).decision, .decline)
    }

    /// 「一直没接到电话」与「不合适」**必须是两个端点**：后端统计口径相反
    /// （前者只增 timeout、不动 declined，而 `acceptanceRate` 直接进派单评分）。
    func testUnreachableIsItsOwnEndpointWithNoBody() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmptyResponse()

        try await SafetyService(transport: transport).reportIntroCallUnreachable(orderId: 42)

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.path, "/api/orders/42/intro-call/unreachable")
        XCTAssertFalse(sent.hasBody, "这条端点没有请求体，拒绝不需要给理由")
    }

    func testMatchedOrderProbeReadsTheOrderDetail() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = try Self.decode(
            OrderDetailResponse.self,
            #"{"orderId":42,"status":"IN_PROGRESS"}"#
        )

        _ = try await SafetyService(transport: transport).matchedOrder(orderId: 42)

        XCTAssertEqual(transport.requests.first?.method, .get)
        XCTAssertEqual(transport.requests.first?.path, "/api/orders/42")
    }

    // MARK: - 轨迹

    func testOrderTrackIsAGet() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = try Self.decode(OrderTrackResponse.self, Self.emptyTrackJSON)

        _ = try await SafetyService(transport: transport).orderTrack(orderId: 94)

        XCTAssertEqual(transport.requests.first?.method, .get)
        XCTAssertEqual(transport.requests.first?.path, "/api/orders/94/track")
    }

    // MARK: - Helpers

    static let emptyTrackJSON = #"{"status":"COMPLETED","volunteerTrack":[],"volunteerStats":{"distanceMeters":0,"durationSeconds":0,"avgPaceSecPerKm":null},"blindTrack":[],"blindStats":{"distanceMeters":0,"durationSeconds":0,"avgPaceSecPerKm":null}}"#

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
