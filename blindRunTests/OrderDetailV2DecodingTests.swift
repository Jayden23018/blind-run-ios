import Combine
import XCTest
@testable import blindRun

/// 陪跑员订单页 v2 的数据层：订单详情新字段、两条新 WS 消息、通知触发重拉。
///
/// JSON 是**照契约示例手写**的（后端 `docs/api_spec.yaml` 的 `OrderDetailResponse` / `EtaView` / `MeetView`
/// 与 `docs/websocket-protocol.md` 的 `ORDER_ETA_UPDATED` / `MEET_DISTANCE_BUCKET`，2026-09-26 origin/main），
/// 不是真机采集 —— 真实响应采到后应放进 `Fixtures/` 走 `ContractFixtureTests`。
///
/// 这一层坏掉的形态全是静默的：解码失败 = 陪跑员订单页整页空白；字段名拼错 = 永远是 `nil`，
/// 页面显示「还没有数据」看起来完全正常。
@MainActor
final class OrderDetailV2DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decodeOrder(_ json: String) throws -> OrderDetailResponse {
        try decoder.decode(OrderDetailResponse.self, from: Data(json.utf8))
    }

    private static let baseFields = """
    "orderId": 123, "status": "DRIVER_EN_ROUTE", "startAddress": "深圳湾公园 3 号入口",
    "startLatitude": 22.5, "startLongitude": 113.95,
    "plannedStart": "2026-09-19T07:00:00", "plannedEnd": "2026-09-19T08:00:00", "createdAt": "2026-09-18T09:00:00"
    """

    // MARK: - 订单详情

    func testV2FieldsDecodeWithFractionalLocalTimesAndNestedObjects() throws {
        let order = try decodeOrder("""
        { \(Self.baseFields),
          "travelMinutes": 20,
          "suggestedDepartAt": "2026-09-19T06:35:00",
          "departReminderAt": "2026-09-19T06:30:00.123",
          "primaryActionUnlockAt": "2026-09-19T06:05:00",
          "eta": { "remainingMinutes": 8, "arriveAt": "2026-09-19T06:57:12.5", "deltaVsStartMinutes": -3, "late": false, "progress": 0.68 },
          "meet": null,
          "runnerAtMeetingPoint": true,
          "earliestEndWaitAt": null,
          "completedTogetherCount": 3,
          "guidePreferenceText": "我习惯你在我左边。",
          "messageToVolunteer": "明天见"
        }
        """)
        XCTAssertEqual(order.travelMinutes, 20)
        XCTAssertEqual(order.eta?.remainingMinutes, 8)
        XCTAssertEqual(order.eta?.deltaVsStartMinutes, -3)
        XCTAssertEqual(order.eta?.late, false)
        XCTAssertEqual(try XCTUnwrap(order.eta?.progress), 0.68, accuracy: 0.0001)
        XCTAssertNil(order.meet)
        XCTAssertEqual(order.runnerAtMeetingPoint, true)
        XCTAssertEqual(order.completedTogetherCount, 3)
        XCTAssertEqual(order.messageToVolunteer, "明天见")
        XCTAssertEqual(order.guidePreferenceText, "我习惯你在我左边。")
        // 无时区串，带不带小数秒都要解得出 —— 解不出来页面会显示「没有出发时间」，看着像后端没给。
        XCTAssertNotNil(order.departReminderAt?.backendTimestamp)
        XCTAssertNotNil(order.eta?.arriveAt?.backendTimestamp)
        XCTAssertEqual(order.primaryActionUnlockAt?.backendTimestamp, "2026-09-19T06:05:00".backendTimestamp)
    }

    /// 旧形状（后端还没下发 v2 字段 / 盲人视角）照常解，全部为 `nil`。
    func testOrderWithoutAnyV2FieldStillDecodes() throws {
        let order = try decodeOrder("{ \(Self.baseFields) }")
        XCTAssertNil(order.eta)
        XCTAssertNil(order.meet)
        XCTAssertNil(order.runnerAtMeetingPoint)
        XCTAssertNil(order.completedTogetherCount)
        XCTAssertNil(order.primaryActionUnlockAt)
    }

    /// 开放枚举：不认识的档位按 `UNKNOWN`，整张订单照常解。
    func testUnknownDistanceBucketDegradesToUnknownInsteadOfFailingTheOrder() throws {
        let order = try decodeOrder("""
        { \(Self.baseFields), "meet": { "distanceBucket": "WITHIN_5", "farDistanceKm": null } }
        """)
        XCTAssertEqual(order.meet?.distanceBucket, .unknown)

        let far = try decodeOrder("""
        { \(Self.baseFields), "meet": { "distanceBucket": "FAR", "farDistanceKm": 1.8 } }
        """)
        XCTAssertEqual(far.meet?.distanceBucket, .far)
        XCTAssertEqual(far.meet?.farDistanceKm, 1.8)

        let missing = try decodeOrder("{ \(Self.baseFields), \"meet\": {} }")
        XCTAssertEqual(missing.meet?.distanceBucket, .unknown)
    }

    /// 契约说 `EtaView` 五项必填；少一项也不能让整张订单解码失败（页面空白就是事故）。
    func testEtaMissingARequiredFieldStillDecodesTheOrder() throws {
        let order = try decodeOrder("""
        { \(Self.baseFields), "eta": { "remainingMinutes": 5, "late": true } }
        """)
        XCTAssertEqual(order.eta?.remainingMinutes, 5)
        XCTAssertEqual(order.eta?.late, true)
        XCTAssertNil(order.eta?.progress)
    }

    /// `replacingStatus` 漏带新字段不会报错，只会让头卡在每次状态推送后闪回「没有数据」。
    func testReplacingStatusKeepsTheV2Fields() {
        var order = OrderDetailResponse.preview(status: .driverEnRoute)
        order.eta = EtaView(remainingMinutes: 8, arriveAt: nil, deltaVsStartMinutes: -3, late: false, progress: 0.5)
        order.meet = MeetView(distanceBucket: .within50, farDistanceKm: nil)
        order.travelMinutes = 20
        order.suggestedDepartAt = "2026-09-19T06:35:00"
        order.departReminderAt = "2026-09-19T06:30:00"
        order.primaryActionUnlockAt = "2026-09-19T06:05:00"
        order.runnerAtMeetingPoint = true
        order.earliestEndWaitAt = "2026-09-19T07:15:00"
        order.completedTogetherCount = 4
        order.guidePreferenceText = "左边"
        order.messageToVolunteer = "谢谢"

        let replaced = order.replacingStatus(with: .driverArrived)

        XCTAssertEqual(replaced.status, .driverArrived)
        XCTAssertEqual(replaced.eta, order.eta)
        XCTAssertEqual(replaced.meet, order.meet)
        XCTAssertEqual(replaced.travelMinutes, 20)
        XCTAssertEqual(replaced.suggestedDepartAt, order.suggestedDepartAt)
        XCTAssertEqual(replaced.departReminderAt, order.departReminderAt)
        XCTAssertEqual(replaced.primaryActionUnlockAt, order.primaryActionUnlockAt)
        XCTAssertEqual(replaced.runnerAtMeetingPoint, true)
        XCTAssertEqual(replaced.earliestEndWaitAt, order.earliestEndWaitAt)
        XCTAssertEqual(replaced.completedTogetherCount, 4)
        XCTAssertEqual(replaced.guidePreferenceText, "左边")
        XCTAssertEqual(replaced.messageToVolunteer, "谢谢")
    }

    func testLiveUpdateMergesOnlyIntoTheSameOrder() {
        let order = OrderDetailResponse.preview(orderId: 7, status: .driverEnRoute)
        let eta = EtaView(remainingMinutes: 3, arriveAt: nil, deltaVsStartMinutes: 0, late: false, progress: 0.8)
        XCTAssertEqual(order.merging(.eta(orderId: 7, eta)).eta, eta)
        XCTAssertNil(order.merging(.eta(orderId: 8, eta)).eta, "别的订单的推送不能合进来")
        let meet = MeetView(distanceBucket: .within10, farDistanceKm: nil)
        XCTAssertEqual(order.merging(.meet(orderId: 7, meet)).meet, meet)
    }

    // MARK: - WebSocket（走生产解码路径）

    func testEtaAndDistanceBucketMessagesReachTheLiveUpdatePublisher() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        var updates: [RealtimeOrderLiveUpdate] = []
        let cancellable = coordinator.orderLiveUpdatePublisher.sink { updates.append($0) }
        defer { cancellable.cancel() }
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(
            #"{"type":"ORDER_ETA_UPDATED","messageId":"m1","timestamp":"2026-09-19T06:49:12","orderId":123,"eta":{"remainingMinutes":8,"arriveAt":"2026-09-19T06:57:12","deltaVsStartMinutes":-3,"late":false,"progress":0.68}}"#,
            generation: generation
        )
        service.simulateTextMessageForTesting(
            #"{"type":"MEET_DISTANCE_BUCKET","messageId":"m2","timestamp":"2026-09-19T06:58:03","orderId":123,"distanceBucket":"WITHIN_50","farDistanceKm":null}"#,
            generation: generation
        )
        service.simulateTextMessageForTesting(
            #"{"type":"MEET_DISTANCE_BUCKET","orderId":123,"distanceBucket":"SOMETHING_NEW"}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertEqual(updates.count, 3)
        guard updates.count == 3 else { return }
        if case .eta(let orderId, let eta) = updates[0] {
            XCTAssertEqual(orderId, 123)
            XCTAssertEqual(eta.remainingMinutes, 8)
        } else { XCTFail("第一条应是 ETA") }
        if case .meet(_, let meet) = updates[1] { XCTAssertEqual(meet.distanceBucket, .within50) } else { XCTFail() }
        if case .meet(_, let meet) = updates[2] { XCTAssertEqual(meet.distanceBucket, .unknown) } else { XCTFail() }
    }

    /// `accuracyM` 缺省时整个键不出现（对接说明 §3.3），有没有都要解得出。
    func testBlindLocationAccuracyIsOptionalAndForwarded() throws {
        let without = try decoder.decode(
            WSBlindLocationUpdate.self,
            from: Data(#"{"type":"BLIND_LOCATION_UPDATE","orderId":1,"lat":22.5,"lng":113.9,"timestamp":1716480000000}"#.utf8)
        )
        XCTAssertNil(without.accuracyM)
        let with = try decoder.decode(
            WSBlindLocationUpdate.self,
            from: Data(#"{"type":"BLIND_LOCATION_UPDATE","orderId":1,"lat":22.5,"lng":113.9,"accuracyM":8.0,"timestamp":1716480000000}"#.utf8)
        )
        XCTAssertEqual(with.accuracyM, 8.0)
    }

    /// 留言变了的推送正文**不含留言**（隐私），只能靠重拉详情拿到 —— 所以这条必须触发重拉。
    func testRunnerMessageUpdatedNotificationRequestsAnOrderRefresh() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(
            #"{"type":"APP_NOTIFICATION","messageId":"n1","eventType":"RUNNER_MESSAGE_UPDATED","title":"跑者留言","body":"跑者给你留了一句话","ttsText":"跑者给你留了一句话","priority":"HIGH","timestamp":"2026-09-19T06:10:00","orderId":77,"messageToVolunteer":"明天见"}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertNotNil(coordinator.pendingOrderRefreshRequests[77])
    }

    /// 反方向：普通通知不带来重拉，否则每条播报都会多打一次详情接口。
    func testOrdinaryNotificationDoesNotRequestARefresh() async {
        let coordinator = AppRealtimeCoordinator()
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        let generation = service.simulateNewTransportForTesting()

        service.simulateTextMessageForTesting(
            #"{"type":"APP_NOTIFICATION","messageId":"n2","eventType":"SOME_INFO","title":"提示","body":"一条提示","priority":"NORMAL","timestamp":"2026-09-19T06:10:00","orderId":78}"#,
            generation: generation
        )
        await Task.yield()

        XCTAssertNil(coordinator.pendingOrderRefreshRequests[78])
    }
}
