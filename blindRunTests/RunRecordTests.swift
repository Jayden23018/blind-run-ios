//
//  RunRecordTests.swift
//  blindRunTests
//
//  跑后运动记录阶段 2（OpenSpec `add-post-run-record`）：解码规则、端点映射、Mock、
//  上报扩充字段、运动采集的起停。真实响应的回归在 `ContractFixtureTests`。
//

import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class RunRecordTests: XCTestCase {

    // MARK: - 解码：开放枚举与跳过

    func testUnknownStatusAndRoleFallBackWithoutFailingTheRecord() throws {
        let record = try decodeRecord(status: "RECOMPUTING", viewerRole: "ADMIN")
        XCTAssertEqual(record.status, .unknown)
        XCTAssertEqual(record.viewerRole, .unknown)
        XCTAssertEqual(record.orderId, 7)
    }

    /// 中间那条是新类型、最后一条缺 `at`：两条都跳过，两头的已知事件原样保留。
    /// 用合成解码的数组时，这里整条记录会抛错 —— 用例能区分两种实现。
    func testUnknownOrMalformedEventsAreSkippedAndTheRestKept() throws {
        let events = """
        [{"type":"RUN_STARTED","at":"2026-09-24T08:00:00","inferred":false},
         {"type":"WATER_BREAK","at":"2026-09-24T08:10:00","inferred":true},
         {"type":"REST","at":"2026-09-24T08:20:00","inferred":true,"durationSec":45,"lat":null,"lng":null},
         {"type":"ORDER_COMPLETED","inferred":false}]
        """
        let record = try decodeRecord(events: events)
        XCTAssertEqual(record.events.map(\.type), [.runStarted, .rest])
        XCTAssertEqual(record.events.last?.durationSec, 45)
    }

    func testMessagesOfUnknownTypeAreSkippedButUnknownSenderRoleIsKept() throws {
        let messages = """
        [{"id":1,"fromRole":"BLIND","type":"TEXT","text":"谢谢你","createdAt":"2026-09-24T09:00:00.123456"},
         {"id":2,"fromRole":"VOLUNTEER","type":"VOICE","text":null,"createdAt":"2026-09-24T09:01:00"},
         {"id":3,"fromRole":"ORGANIZER","type":"TEXT","text":"辛苦了","createdAt":"2026-09-24T09:02:00"}]
        """
        let record = try decodeRecord(messages: messages)
        XCTAssertEqual(record.messages.map(\.id), [1, 3])
        XCTAssertEqual(record.messages.map(\.fromRole), [.blind, .unknown])
    }

    /// HANDOFF 6.4：没有数据是 null，界面据此隐藏，**不能解成 0**。
    func testNullQuantitiesStayNil() throws {
        let record = try decodeRecord(
            status: "INSUFFICIENT_TRACK",
            summary: """
            {"distanceM":null,"movingSec":null,"elapsedSec":null,"restSec":null,"avgPaceSecPerKm":null,
             "steps":null,"avgCadence":null,"elevationGainM":null}
            """
        )
        XCTAssertEqual(record.status, .insufficientTrack)
        XCTAssertNil(record.summary?.steps)
        XCTAssertNil(record.summary?.distanceM)
        XCTAssertNil(record.track)
        XCTAssertNil(record.comparison)
        XCTAssertNil(record.service.durationMin)
    }

    func testHistoryDecodesUnknownRoleAndNullThumbnail() throws {
        let json = """
        {"success":true,"code":200,"message":"success","data":{"role":"COACH","month":"2026-09",
         "monthSummary":{"runs":1,"distanceM":null,"serviceMin":null,"topPartner":null},
         "items":[{"orderId":5,"finishedAt":"2026-09-01T08:00:00.5","place":null,"partnerName":null,"distanceM":null,"thumbnail":null}]}}
        """
        let history = try APIPayloadDecoder.decodePayload(RunRecordHistoryResponse.self, from: Data(json.utf8), decoder: JSONDecoder())
        XCTAssertEqual(history.role, .unknown)
        XCTAssertNil(history.items.first?.thumbnail)
        XCTAssertNil(history.monthSummary.topPartner)
    }

    // MARK: - 端点映射

    func testServiceHitsTheContractPathsWithMonthQueryAndTextBody() async throws {
        let transport = RecordingTransport()
        let service = RunRecordService(transport: transport)

        transport.nextResponse = try decodeRecord()
        _ = try await service.record(orderId: 42)
        transport.nextResponse = RunRecordHistoryResponse(
            role: .blind, month: "2026-03",
            monthSummary: RunMonthSummary(runs: 0, distanceM: nil, serviceMin: nil, topPartner: nil),
            items: []
        )
        _ = try await service.monthlyRecords(year: 2026, month: 3)
        transport.nextResponse = RunRecordMessageResponse(id: 1, fromRole: .blind, type: .text, text: "好", createdAt: "x")
        _ = try await service.postMessage(orderId: 42, text: "好")

        XCTAssertEqual(transport.requests.map(\.path), [
            "/api/orders/42/run-record",
            "/api/orders/mine/run-records",
            "/api/orders/42/run-record/messages"
        ])
        XCTAssertEqual(transport.requests.map(\.method), [.get, .get, .post])
        XCTAssertEqual(transport.requests[1].query, ["month": "2026-03"])
        XCTAssertTrue(transport.requests.allSatisfy(\.requiresAuth))
        let body = try XCTUnwrap(transport.requests[2].body as? RunRecordMessageRequest)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: String]
        XCTAssertEqual(encoded, ["type": "TEXT", "text": "好"])
    }

    // MARK: - Mock

    func testMockGatesOnCompletionAndTrimsMessages() async throws {
        let client = MockAPIClient()
        client.mockRole = .volunteer
        client.orders = [Self.makeOrder(orderId: 1, status: .inProgress), Self.makeOrder(orderId: 2, status: .completed)]
        let service = RunRecordService(transport: client)

        do {
            _ = try await service.record(orderId: 1)
            XCTFail("未完成的订单应当 409")
        } catch APIError.serverError(let error) {
            XCTAssertEqual(error.code, "ORDER_STATUS_NOT_ALLOWED")
        }

        let message = try await service.postMessage(orderId: 2, text: "  跑得很稳  ")
        XCTAssertEqual(message.text, "跑得很稳")
        XCTAssertEqual(message.fromRole, .volunteer)

        let record = try await service.record(orderId: 2)
        XCTAssertEqual(record.viewerRole, .volunteer)
        XCTAssertNil(record.comparison, "D6：陪跑员拿不到 comparison")
        XCTAssertEqual(record.messages.map(\.text), ["跑得很稳"])

        do {
            _ = try await service.postMessage(orderId: 2, text: "   ")
            XCTFail("空白留言应当被拒")
        } catch APIError.serverError(let error) {
            XCTAssertEqual(error.code, "VALIDATION_ERROR")
        }
    }

    // MARK: - 上报报文

    func testLocationMessageOmitsEveryMissingFieldInsteadOfSendingZero() throws {
        let sample = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 22.5, longitude: 113.9),
            system: .gcj02Backend,
            horizontalAccuracy: -1,
            speed: -1
        )
        let bare = LiveEscortSessionCoordinator.locationMessage(sample: sample, motion: RunMotionSnapshot())
        XCTAssertEqual(try Set(Self.keys(of: bare)), ["type", "lat", "lng"])

        let full = LiveEscortSessionCoordinator.locationMessage(
            sample: LocatedCoordinate(
                coordinate: sample.coordinate, system: .gcj02Backend, horizontalAccuracy: 5, speed: 0
            ),
            motion: RunMotionSnapshot(steps: 0, cadence: 168, altitude: -2.5)
        )
        let object = try Self.jsonObject(full)
        XCTAssertEqual(object["hAcc"] as? Double, 5)
        // 真实的 0（站着不动、刚开跑）要照传；「不传 0」说的是**拿不到**的时候。
        XCTAssertEqual(object["speed"] as? Double, 0)
        XCTAssertEqual(object["steps"] as? Int, 0)
        XCTAssertEqual(object["cadence"] as? Int, 168)
        XCTAssertEqual(object["alt"] as? Double, -2.5)
    }

    /// 2.8 步/秒 = 168 步/分。忘了 ×60 会报 3，后端 [0, 400] 的范围闸拦不住。
    func testCadenceIsConvertedFromStepsPerSecondToStepsPerMinute() {
        XCTAssertEqual(RunMotionSnapshot.cadencePerMinute(fromStepsPerSecond: 2.8), 168)
        XCTAssertNil(RunMotionSnapshot.cadencePerMinute(fromStepsPerSecond: nil))
        XCTAssertNil(RunMotionSnapshot.cadencePerMinute(fromStepsPerSecond: -1))
    }

    /// normalize 把 WGS-84 转 GCJ-02 时不能把精度和速度弄丢。
    func testNormalizationCarriesAccuracyAndSpeed() throws {
        let device = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 22.5, longitude: 113.9),
            system: .wgs84Device, horizontalAccuracy: 8, speed: 2.4
        )
        let backend = try XCTUnwrap(BackendCoordinateNormalizer.normalize(device))
        XCTAssertEqual(backend.system, .gcj02Backend)
        XCTAssertEqual(backend.horizontalAccuracy, 8)
        XCTAssertEqual(backend.speed, 2.4)
    }

    // MARK: - 起点锚

    func testRunAnchorSurvivesRelaunchForTheSameOrderAndResetsForANewOne() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RunRecordTests.anchor"))
        defaults.removePersistentDomain(forName: "RunRecordTests.anchor")
        let start = Date(timeIntervalSince1970: 1_000)

        let first = RunMotionAnchorStore.anchor(for: 9, now: start, defaults: defaults)
        RunMotionAnchorStore.recordAltitude(-8, orderID: 9, defaults: defaults)
        RunMotionAnchorStore.recordAltitude(99, orderID: 10, defaults: defaults) // 别的单，不许写进来

        let relaunched = RunMotionAnchorStore.anchor(for: 9, now: start.addingTimeInterval(600), defaults: defaults)
        XCTAssertEqual(relaunched.startedAt, first.startedAt, "同一单重启后必须沿用原起点，否则累计步数归零")
        XCTAssertEqual(relaunched.lastAltitude, -8, "海拔要从上次报过的值续上")

        let next = RunMotionAnchorStore.anchor(for: 11, now: start.addingTimeInterval(900), defaults: defaults)
        XCTAssertEqual(next.startedAt, start.addingTimeInterval(900))
        XCTAssertNil(next.lastAltitude)
    }

    // MARK: - 协调器起停

    func testMotionIsRequestedOnEscortStartAttachedOnlyInProgressAndStoppedAfter() async {
        let recorder = FakeMotionRecorder()
        recorder.latestSnapshot = RunMotionSnapshot(steps: 1_320, cadence: 168, altitude: 1.5)
        var sent: [RunMotionSnapshot?] = []
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: AppRealtimeCoordinator(),
            reportInterval: 60,
            motionRecorder: recorder,
            sendLocation: { _, _, motion in sent.append(motion) }
        )
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(.connected)
        let location = LocationService()
        location.simulateDeviceLocationForTesting(CLLocationCoordinate2D(latitude: 22.5, longitude: 113.9), capturedAt: Date())
        coordinator.configure(identityKey: "account:volunteer:token", role: .volunteer, webSocketService: service, locationService: location)

        coordinator.updateOwnedOrder(orderID: 31, status: .driverEnRoute)
        let didSendEnRoute = await waitUntil { sent.count >= 1 }
        XCTAssertTrue(didSendEnRoute)
        XCTAssertGreaterThanOrEqual(recorder.authorizationRequests, 1, "出发去会合时就申请运动与健身权限")
        XCTAssertEqual(recorder.started, [])
        XCTAssertNil(sent.last ?? nil, "去会合的路上不带步数")

        coordinator.updateOwnedOrder(orderID: 31, status: .inProgress)
        let didStart = await waitUntil { recorder.started == [31] && sent.count >= 2 }
        XCTAssertTrue(didStart)
        XCTAssertEqual(sent.last ?? nil, recorder.latestSnapshot)

        coordinator.updateOwnedOrder(orderID: 31, status: .completed)
        XCTAssertGreaterThanOrEqual(recorder.stopCount, 1)
        XCTAssertFalse(recorder.isRunning)
    }

    /// Mock 环境没有 WS：不申请权限、不开采集 —— UI 测试里因此不会冒出系统权限框。
    func testMotionNeverStartsWithoutACloudWebSocket() async {
        let recorder = FakeMotionRecorder()
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: AppRealtimeCoordinator(),
            reportInterval: 60,
            motionRecorder: recorder
        )
        coordinator.configure(identityKey: "account:blind:token", role: .blind, webSocketService: nil)
        coordinator.updateOwnedOrder(orderID: 32, status: .inProgress)
        _ = await waitUntil(timeout: 0.3) { false }
        XCTAssertEqual(recorder.authorizationRequests, 0)
        XCTAssertEqual(recorder.started, [])
    }

    /// 真实 recorder 在单测宿主里必须是空操作。`LiveEscortTrackTests` 用默认参数构造协调器、
    /// 大量推进到 `IN_PROGRESS` —— 这道闸被删掉，跑一次单测就会在测试机上真的开计步、弹权限框。
    func testRealRecorderIsANoOpUnderXCTest() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "RunRecordTests.real"))
        defaults.removePersistentDomain(forName: "RunRecordTests.real")
        let recorder = CoreMotionRunRecorder(defaults: defaults)
        recorder.requestAuthorizationIfNeeded()
        recorder.start(orderID: 1)
        XCTAssertNil(recorder.latestSnapshot)
        XCTAssertNil(defaults.data(forKey: RunMotionAnchorStore.key), "不许写起点锚")
    }

    // MARK: - Helpers

    private func decodeRecord(
        status: String = "READY",
        viewerRole: String = "BLIND",
        summary: String = "null",
        events: String = "[]",
        messages: String = "[]"
    ) throws -> RunRecordResponse {
        let json = """
        {"success":true,"code":200,"errorCode":null,"message":"success","data":{
         "orderId":7,"status":"\(status)","viewerRole":"\(viewerRole)","place":null,"blindName":"张*","volunteerName":null,
         "runStartedAt":null,"runEndedAt":null,"summary":\(summary),"splits":[],"fastestSplitIndex":null,
         "paceSamples":[],"stops":[],"events":\(events),"sosTriggered":false,
         "service":{"startedAt":null,"completedAt":null,"durationMin":null,"volunteerTotalServiceMinutes":null},
         "comparison":null,"messages":\(messages),"track":null}}
        """
        return try APIPayloadDecoder.decodePayload(RunRecordResponse.self, from: Data(json.utf8), decoder: JSONDecoder())
    }

    private static func jsonObject(_ message: WSLocationUpdateMessage) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any])
    }

    private static func keys(of message: WSLocationUpdateMessage) throws -> [String] {
        Array(try jsonObject(message).keys)
    }

    private func waitUntil(timeout: TimeInterval = 2, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private static func makeOrder(orderId: Int64, status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId, status: status, startAddress: "测试出发点",
            startLatitude: 22.5, startLongitude: 113.9,
            endAddress: nil, endLatitude: nil, endLongitude: nil,
            plannedStart: nil, plannedEnd: nil, blindName: "张*", blindPhone: nil, volunteerPhone: nil,
            acceptedAt: "2026-09-24T08:00:00", createdAt: "2026-09-24T07:00:00",
            expectedDurationMinutes: nil, pacePreference: nil, routePreference: nil, routeNotes: nil,
            hasGuideDogThisRun: nil, specialNotes: nil, visionLevel: nil, tetherPreference: nil, chatPreference: nil
        )
    }
}

@MainActor
private final class FakeMotionRecorder: RunMotionRecording {
    var latestSnapshot: RunMotionSnapshot?
    private(set) var authorizationRequests = 0
    private(set) var started: [Int64] = []
    private(set) var stopCount = 0
    private(set) var isRunning = false

    func requestAuthorizationIfNeeded() { authorizationRequests += 1 }

    func start(orderID: Int64) {
        guard started.last != orderID || !isRunning else { return }
        started.append(orderID)
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }
}
