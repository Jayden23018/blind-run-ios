import XCTest
@testable import blindRun

/// 见面安排单的契约接入（#432，后端 blind-run-backend#755 / #757）。
///
/// 第 1 组纯逻辑（子状态、朗读、倒计时）在 `IntroCallMeetupPlanTests`；这里只管
/// 「线上的字节 ↔ 本地类型」与服务层、错误码、Mock 的两态开关。
@MainActor
final class IntroCallPlanContractTests: XCTestCase {

    // MARK: - 解码

    /// 后端加了一种颜色时，整条通话页响应必须照常解出来 —— 那一页承载着盲人唯一能拨通的号码。
    /// 偷懒实现（颜色直接用合成的 `Decodable` 枚举）在这里会整条抛错。
    func testUnknownTopColorDegradesWithoutBreakingTheIntroCallView() throws {
        let view = try decodeView(plan: #"""
        {"version":2,"volunteerTopColor":"TEAL","runnerTopColor":"BLUE","meetSpotNote":"东门保安亭左侧"}
        """#)

        XCTAssertEqual(view.dialableCounterpartPhone, "13800000002", "颜色认不出不能连号码一起丢")
        XCTAssertEqual(view.plan?.volunteerTopColor, .unknown)
        XCTAssertEqual(view.plan?.runnerTopColor, .blue)
        let plan = try XCTUnwrap(view.meetupPlan, "只是一项颜色不认识，整张单仍然能念")
        XCTAssertEqual(plan.version, 2)
        XCTAssertNil(plan.volunteerTopColor?.spokenName, "认不出的颜色那一句不念")
        XCTAssertEqual(plan.meetSpotNote, "东门保安亭左侧")
    }

    /// 颜色键的**类型**变了（数字）同样只降级这一项。
    func testNonStringTopColorAlsoDegradesInsteadOfThrowing() throws {
        let view = try decodeView(plan: #"{"version":1,"volunteerTopColor":3}"#)
        XCTAssertEqual(view.plan?.volunteerTopColor, .unknown)
        XCTAssertNotNil(view.meetupPlan)
    }

    /// `null` 是「未确认」，不是「不认识的颜色」—— 两者在朗读上一样（都不念），但别混成 `.unknown`。
    func testNullTopColorIsUnconfirmedNotUnknown() throws {
        let view = try decodeView(plan: #"{"version":1,"volunteerTopColor":null}"#)
        XCTAssertNil(view.plan?.volunteerTopColor)
    }

    /// 安排单里任何一项形状坏了，外层照样解得出来；这一版标为「读不懂」，而不是「还没提交」。
    func testMalformedPlanKeepsTheViewAndIsFlaggedUnreadable() throws {
        let view = try decodeView(plan: #"{"version":"2"}"#)

        XCTAssertEqual(view.dialableCounterpartPhone, "13800000002")
        XCTAssertNotNil(view.plan)
        XCTAssertNil(view.meetupPlan)
        XCTAssertTrue(view.hasUnreadablePlan, "陪跑员已经提交了，不许退回成「等安排」")
    }

    /// `plan` 本身不是对象时外层照样解出来（号码还在），这一版标为读不懂。
    func testPlanThatIsNotAnObjectKeepsTheView() throws {
        for shape in [#""x""#, "[]", "3"] {
            let view = try decodeView(plan: shape)
            XCTAssertEqual(view.dialableCounterpartPhone, "13800000002", "plan=\(shape)")
            XCTAssertTrue(view.hasUnreadablePlan, "plan=\(shape)")
        }
    }

    /// 时间或地点**类型**错（不是解析不出的串，而是数字）同样读不懂 —— 落成 `nil` 就是「按原约」。
    func testWrongTypedTimeOrPlaceMakesThePlanUnreadable() throws {
        let numericTime = try decodeView(plan: #"{"version":1,"plannedStartTime":1760570000}"#)
        XCTAssertNil(numericTime.meetupPlan)
        XCTAssertTrue(numericTime.hasUnreadablePlan)

        let numericPlace = try decodeView(plan: #"{"version":1,"startAddress":1,"startLatitude":"x","startLongitude":"y"}"#)
        XCTAssertTrue(numericPlace.hasUnreadablePlan, "三项全坏也会通过「同有同无」，必须另外拦")
    }

    /// 提交时刻只用于展示：它读坏了不许拦住整张单，否则盲人永远到不了确认那一步。
    func testMalformedSubmittedAtDoesNotBlockThePlan() throws {
        let view = try decodeView(plan: #"{"version":1,"submittedAt":1760570000}"#)
        XCTAssertNotNil(view.meetupPlan)
        XCTAssertFalse(view.hasUnreadablePlan)
    }

    func testMissingPlanIsNotUnreadable() throws {
        let view = try JSONDecoder().decode(IntroCallView.self, from: Data(#"{"counterpartPhone":"13800000002"}"#.utf8))
        XCTAssertNil(view.plan)
        XCTAssertFalse(view.hasUnreadablePlan)
    }

    /// null = 按原约；非 null 且解析得出 = 改了。
    func testNullTimeMeansKeepOriginalAndParsedTimeMeansChanged() throws {
        let view = try decodeView(plan: #"{"version":1,"plannedStartTime":"2026-10-16T07:30:00","plannedEndTime":null}"#)
        let plan = try XCTUnwrap(view.meetupPlan)

        XCTAssertEqual(plan.plannedStartTime, "2026-10-16T07:30:00".backendTimestamp)
        XCTAssertNil(plan.plannedEndTime)
        let changes = plan.changes(from: view.originalArrangement)
        XCTAssertTrue(changes.startChanged)
        XCTAssertFalse(changes.endChanged)
    }

    /// 时间是非 null 却解析不出时，**不许**落成「按原约」—— 那会把一次改期念成没改。
    func testUnparseableTimeMakesThePlanUnreadableInsteadOfKeepOriginal() throws {
        let view = try decodeView(plan: #"{"version":1,"plannedStartTime":"明早七点半"}"#)
        XCTAssertNil(view.meetupPlan)
        XCTAssertTrue(view.hasUnreadablePlan)
    }

    /// 地点三项契约保证同有同无。只来了坐标没有地址时，朗读会念「仍为原地址，约 N 米」，比不念更误导。
    func testHalfAPlaceMakesThePlanUnreadable() throws {
        let coordinatesOnly = try decodeView(plan: #"{"version":1,"startLatitude":39.94,"startLongitude":116.48}"#)
        XCTAssertNil(coordinatesOnly.meetupPlan)

        let full = try decodeView(plan: #"""
        {"version":1,"startAddress":"朝阳公园东门","startLatitude":39.94,"startLongitude":116.48}
        """#)
        let plan = try XCTUnwrap(full.meetupPlan)
        XCTAssertEqual(plan.startAddress, "朝阳公园东门")
        XCTAssertTrue(plan.changes(from: full.originalArrangement).placeChanged)
    }

    /// 原约取 `IntroCallView` 顶层（含 #755 新加的两个坐标）。
    func testOriginalArrangementComesFromTheTopLevelFields() throws {
        let view = try decodeView(plan: nil)
        let original = view.originalArrangement

        XCTAssertEqual(original.startAddress, "朝阳公园南门")
        XCTAssertEqual(original.startLatitude, 39.9330)
        XCTAssertEqual(original.startLongitude, 116.4720)
        XCTAssertEqual(original.plannedStartTime, "2026-10-16T07:00:00".backendTimestamp)
        XCTAssertEqual(original.plannedEndTime, "2026-10-16T08:00:00".backendTimestamp)
    }

    // MARK: - 订单详情的三个新字段

    func testOrderDetailDecodesMeetSpotNoteAndTopColorsLeniently() throws {
        let json = #"""
        {"orderId":5,"status":"SCHEDULED_CONFIRMED","startAddress":"朝阳公园东门",
         "meetSpotNote":"东门保安亭左侧","runnerTopColor":"TEAL","volunteerTopColor":"RED"}
        """#
        let order = try JSONDecoder().decode(OrderDetailResponse.self, from: Data(json.utf8))

        XCTAssertEqual(order.status, .scheduledConfirmed, "颜色认不出不许带崩整张订单")
        XCTAssertEqual(order.startAddress, "朝阳公园东门")
        XCTAssertEqual(order.meetSpotNote, "东门保安亭左侧")
        XCTAssertEqual(order.runnerTopColor, .unknown)
        XCTAssertEqual(order.volunteerTopColor, .red)
    }

    /// 5 秒轮询走 `replacingStatus`：漏带会让约好页的见面位置与颜色静默消失。
    func testReplacingStatusKeepsTheMeetupFields() {
        var order = OrderDetailResponse.preview(status: .scheduledConfirmed)
        order.meetSpotNote = "东门保安亭左侧"
        order.runnerTopColor = .blue
        order.volunteerTopColor = .red

        let next = order.replacingStatus(with: .pendingAccept)

        XCTAssertEqual(next.meetSpotNote, "东门保安亭左侧")
        XCTAssertEqual(next.runnerTopColor, .blue)
        XCTAssertEqual(next.volunteerTopColor, .red)
    }

    // MARK: - 请求体

    /// 盲人确认必须把版本号带上去 —— 漏带时后端开关一打开就 409，开关关着时则会**绕过**安排单直接成单。
    func testConfirmSendsAcceptWithThePlanVersion() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmptyResponse()

        let outcome = try await OrderService(transport: transport).confirmIntroCallPlan(orderId: 7, version: 3)

        XCTAssertEqual(outcome, .confirmed)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/orders/7/intro-call/decision")
        let body = try jsonObject(request.body)
        XCTAssertEqual(body["decision"] as? String, "ACCEPT")
        XCTAssertEqual(body["planVersion"] as? Int, 3)
    }

    /// 老入口不带版本时请求体与 #755 之前逐字节相同（不发 `"planVersion": null`）。
    func testDecisionWithoutPlanVersionOmitsTheKey() throws {
        let body = try jsonObject(IntroCallDecisionRequest(decision: .decline))
        XCTAssertEqual(Set(body.keys), ["decision"])
    }

    /// `STALE` 不是错误：服务层换成 `.planChanged`，调用方没法把它和「确认未送达」走同一条红条。
    func testStalePlanBecomesPlanChangedInsteadOfThrowing() async throws {
        let transport = RecordingTransport()
        transport.nextError = APIError.serverError(ErrorResponse(code: "INTRO_CALL_PLAN_STALE", message: "x"))

        let outcome = try await OrderService(transport: transport).confirmIntroCallPlan(orderId: 7, version: 1)

        XCTAssertEqual(outcome, .planChanged)
    }

    /// 只有 `STALE` 被接住。别的码（这里用同族的 `REQUIRED`）照旧抛出 —— 一律吞成 `.planChanged`
    /// 的偷懒实现会让盲人在网络断了时被要求「重新收听」一张根本没变的单。
    func testOtherConfirmErrorsStillThrow() async {
        let transport = RecordingTransport()
        transport.nextError = APIError.serverError(ErrorResponse(code: "INTRO_CALL_PLAN_REQUIRED", message: "x"))

        do {
            _ = try await OrderService(transport: transport).confirmIntroCallPlan(orderId: 7, version: 1)
            XCTFail("REQUIRED 不该被当成「安排改了」")
        } catch {
            XCTAssertEqual((error as? APIError)?.errorCode, .introCallPlanRequired)
        }
    }

    func testSubmitPlanPutsTheFlattenedBodyToThePlanPath() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = IntroCallPlanView(version: 1)
        let start = try XCTUnwrap("2026-10-16T07:30:00".backendTimestamp)
        let request = IntroCallPlanRequest(
            plannedStart: start,
            place: .init(address: "朝阳公园东门", latitude: 39.94, longitude: 116.48),
            meetSpotNote: "  东门保安亭左侧  ",
            volunteerTopColor: .red,
            runnerTopColor: .unknown
        )

        let stored = try await SafetyService(transport: transport).submitIntroCallPlan(orderId: 7, plan: request)

        XCTAssertEqual(stored.version, 1)
        let recorded = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(recorded.method, .put)
        XCTAssertEqual(recorded.path, "/api/orders/7/intro-call/plan")
        let body = try jsonObject(recorded.body)
        XCTAssertEqual(body["plannedStartTime"] as? String, "2026-10-16T07:30:00", "北京时间 LocalDateTime 形状")
        XCTAssertNil(body["plannedEndTime"], "只改开始时不传结束，后端按原时长平移")
        XCTAssertEqual(body["startAddress"] as? String, "朝阳公园东门")
        XCTAssertEqual(body["startLatitude"] as? Double, 39.94)
        XCTAssertEqual(body["startLongitude"] as? Double, 116.48)
        XCTAssertEqual(body["meetSpotNote"] as? String, "东门保安亭左侧")
        XCTAssertEqual(body["volunteerTopColor"] as? String, "RED")
        XCTAssertNil(body["runnerTopColor"], "本地兜底值 UNKNOWN 不许发上去")
    }

    /// 一项都不改也要提交（提交本身就是「合适」）：请求体是空对象，不是一堆 null。
    func testUnchangedPlanEncodesAsAnEmptyObject() throws {
        let body = try jsonObject(IntroCallPlanRequest(meetSpotNote: "   "))
        XCTAssertTrue(body.isEmpty, "\(body)")
    }

    // MARK: - 错误码

    func testPlanErrorCodesMapToTheMockupCopy() {
        XCTAssertEqual(message(for: "INTRO_CALL_PLAN_STALE"), "陪跑员已修改见面安排，请重新收听。")
        XCTAssertEqual(message(for: "INTRO_CALL_PLAN_TIME_UNAVAILABLE"), "该时段不可用，请调整时间。")
        XCTAssertEqual(message(for: "INTRO_CALL_PLAN_REQUIRED"), IntroCallMeetupCopy.planNotSubmittedYet)
        XCTAssertEqual(message(for: "INTRO_CALL_PLAN_TOO_FAR_FROM_ORIGINAL"), IntroCallMeetupCopy.planTooFarFromOriginal)
        XCTAssertEqual(message(for: "INTRO_CALL_PLAN_TOO_MANY_SUBMISSIONS"), IntroCallMeetupCopy.planTooManySubmissions)
    }

    /// 时段不可用**不说原因**：说出「跑者那边有单」等于把跑者的行程告诉陪跑员。
    /// 超距**不写死 3 公里**：那是后端配置。STALE **不念成错误**。
    func testPlanErrorCopyKeepsItsRedLines() {
        let timeUnavailable = message(for: "INTRO_CALL_PLAN_TIME_UNAVAILABLE")
        for leak in ["跑者", "另有", "冲突", "已有"] {
            XCTAssertFalse(timeUnavailable.contains(leak), "「\(leak)」泄露了不可用的原因")
        }
        XCTAssertFalse(message(for: "INTRO_CALL_PLAN_TOO_FAR_FROM_ORIGINAL").contains("3"))
        let stale = message(for: "INTRO_CALL_PLAN_STALE")
        XCTAssertFalse(stale.contains("失败") || stale.contains("错误"))
    }

    /// 安排单的提前量是 30 分钟 + 本轮窗口剩余分钟。照念下单那句「至少30分钟之后」，
    /// 陪跑员会改到 31 分钟后再被拒一次。其余码照常走 `APIError.localizedMessage`。
    func testPlanSubmitErrorReplacesTheBookingLeadTimeCopy() {
        let tooSoon = APIError.serverError(ErrorResponse(code: "APPOINTMENT_TOO_SOON", message: "x"))
        XCTAssertEqual(IntroCallMeetupCopy.planSubmitErrorMessage(for: tooSoon), IntroCallMeetupCopy.planStartTooSoon)
        XCTAssertNotEqual(IntroCallMeetupCopy.planSubmitErrorMessage(for: tooSoon), tooSoon.localizedMessage)

        let engaged = APIError.serverError(ErrorResponse(code: "VOLUNTEER_ALREADY_ENGAGED", message: "x"))
        XCTAssertEqual(IntroCallMeetupCopy.planSubmitErrorMessage(for: engaged), engaged.localizedMessage)
    }

    // MARK: - Mock：两种开关状态都走得通

    /// 新版客户端的完整流程在开关**关着**时：提交 → 改一版 → 盲人确认旧版被告知「改了」→ 确认新版成单，
    /// 安排单写进订单。
    func testMockFullFlowWithSwitchOff() async throws {
        let mock = makeMock()
        XCTAssertFalse(mock.introCallPlanRequired, "缺省与后端一致：关")
        try await runNewClientFlow(on: mock)
    }

    /// 同一条流程在开关**打开**时必须同样走通 —— 新版客户端不判开关。
    func testMockFullFlowWithSwitchOn() async throws {
        let mock = makeMock()
        mock.introCallPlanRequired = true
        try await runNewClientFlow(on: mock)
    }

    /// 开关打开后老路被堵：陪跑员直接 ACCEPT、盲人不带版本 ACCEPT 都是 `REQUIRED`。
    func testMockSwitchOnBlocksTheOldAcceptPath() throws {
        let mock = makeMock()
        mock.introCallPlanRequired = true

        mock.mockRole = .volunteer
        XCTAssertThrowsError(try mock.handleIntroCallDecision(
            orderId: Self.orderId, body: IntroCallDecisionRequest(decision: .accept))) { error in
            XCTAssertEqual((error as? APIError)?.errorCode, .introCallPlanRequired)
        }
        mock.mockRole = .blind
        XCTAssertThrowsError(try mock.handleIntroCallDecision(
            orderId: Self.orderId, body: IntroCallDecisionRequest(decision: .accept))) { error in
            XCTAssertEqual((error as? APIError)?.errorCode, .introCallPlanRequired)
        }
    }

    /// 开关关着、这一轮**已有**安排单时，盲人不带版本照样被拦 —— 否则老入口能跳过安排单成单。
    func testMockSwitchOffStillRequiresTheVersionOnceAPlanExists() throws {
        let mock = makeMock()
        mock.mockRole = .volunteer
        _ = try mock.handleSubmitIntroCallPlan(orderId: Self.orderId, body: IntroCallPlanRequest())

        mock.mockRole = .blind
        XCTAssertThrowsError(try mock.handleIntroCallDecision(
            orderId: Self.orderId, body: IntroCallDecisionRequest(decision: .accept))) { error in
            XCTAssertEqual((error as? APIError)?.errorCode, .introCallPlanStale)
        }
    }

    func testMockRejectsAPlaceTooFarFromTheOriginal() {
        let mock = makeMock()
        mock.mockRole = .volunteer
        // 原约 22.5210, 113.9350（preview 工厂）；纬度挪 0.05 ≈ 5.5 公里。
        let far = IntroCallPlanRequest(place: .init(address: "别处", latitude: 22.5710, longitude: 113.9350))
        XCTAssertThrowsError(try mock.handleSubmitIntroCallPlan(orderId: Self.orderId, body: far)) { error in
            XCTAssertEqual((error as? APIError)?.errorCode, .introCallPlanTooFarFromOriginal)
        }
    }

    /// 被拒的提交也计数；到顶之后连合法提交也被拒。
    func testMockCountsRejectedSubmissionsTowardsTheLimit() throws {
        let mock = makeMock()
        mock.mockRole = .volunteer
        let far = IntroCallPlanRequest(place: .init(address: "别处", latitude: 22.5710, longitude: 113.9350))
        for _ in 0..<MockAPIClient.mockIntroCallPlanMaxSubmissions {
            _ = try? mock.handleSubmitIntroCallPlan(orderId: Self.orderId, body: far)
        }
        XCTAssertThrowsError(try mock.handleSubmitIntroCallPlan(orderId: Self.orderId, body: IntroCallPlanRequest())) { error in
            XCTAssertEqual((error as? APIError)?.errorCode, .introCallPlanTooManySubmissions)
        }
    }

    /// 到顶之后重发上一版（弱网），拿回的是那一版，不是「次数到顶」。
    func testMockIdenticalResendAtTheLimitReturnsTheStoredVersion() throws {
        let mock = makeMock()
        mock.mockRole = .volunteer
        let stored = try mock.handleSubmitIntroCallPlan(orderId: Self.orderId, body: IntroCallPlanRequest())
        let far = IntroCallPlanRequest(place: .init(address: "别处", latitude: 22.5710, longitude: 113.9350))
        for _ in 1..<MockAPIClient.mockIntroCallPlanMaxSubmissions {
            _ = try? mock.handleSubmitIntroCallPlan(orderId: Self.orderId, body: far)
        }

        let resent = try mock.handleSubmitIntroCallPlan(orderId: Self.orderId, body: IntroCallPlanRequest())

        XCTAssertEqual(resent.version, stored.version)
    }

    // MARK: - Helpers

    private static let orderId: Int64 = 900

    private func makeMock() -> MockAPIClient {
        let mock = MockAPIClient()
        mock.orders = [.preview(orderId: Self.orderId, status: .pendingIntroCall)]
        return mock
    }

    /// 陪跑员一律 `PUT /plan`，盲人一律带版本确认 —— 不看开关。
    private func runNewClientFlow(on mock: MockAPIClient) async throws {
        let volunteer = SafetyService(transport: mock)
        let blind = OrderService(transport: mock)

        mock.mockRole = .volunteer
        let first = try await volunteer.submitIntroCallPlan(orderId: Self.orderId, plan: IntroCallPlanRequest())
        XCTAssertEqual(first.version, 1)
        let resent = try await volunteer.submitIntroCallPlan(orderId: Self.orderId, plan: IntroCallPlanRequest())
        XCTAssertEqual(resent.version, 1, "内容相同的重发不加版本")
        let second = try await volunteer.submitIntroCallPlan(
            orderId: Self.orderId,
            plan: IntroCallPlanRequest(meetSpotNote: "南门保安亭左边", volunteerTopColor: .red)
        )
        XCTAssertEqual(second.version, 2)

        mock.mockRole = .blind
        let view = try await blind.introCallView(orderId: Self.orderId)
        XCTAssertEqual(view.meetupPlan?.version, 2, "两端看到的都是最新一版")
        XCTAssertEqual(view.originalArrangement.startLatitude, 22.5210)

        let stale = try await blind.confirmIntroCallPlan(orderId: Self.orderId, version: 1)
        XCTAssertEqual(stale, .planChanged)
        XCTAssertEqual(mock.orders.first?.status, .pendingIntroCall)

        let confirmed = try await blind.confirmIntroCallPlan(orderId: Self.orderId, version: 2)
        XCTAssertEqual(confirmed, .confirmed)
        let order = try XCTUnwrap(mock.orders.first)
        XCTAssertEqual(order.status, .scheduledConfirmed, "preview 订单是明早 7 点，远期单落约好")
        XCTAssertEqual(order.meetSpotNote, "南门保安亭左边")
        XCTAssertEqual(order.volunteerTopColor, .red)
        XCTAssertNil(mock.introCallPlans[Self.orderId], "约成后这一轮的安排单清掉")
    }

    private func decodeView(plan: String?) throws -> IntroCallView {
        let planJSON = plan.map { #","plan":"# + $0 } ?? ""
        let json = #"""
        {"counterpartName":"李*","counterpartPhone":"13800000002","myDecision":null,
         "windowEndsAt":"2026-10-15T20:20:00","startAddress":"朝阳公园南门",
         "plannedStartTime":"2026-10-16T07:00:00","plannedEndTime":"2026-10-16T08:00:00",
         "startLatitude":39.9330,"startLongitude":116.4720
        """# + planJSON + "}"
        return try JSONDecoder().decode(IntroCallView.self, from: Data(json.utf8))
    }

    private func jsonObject(_ body: (any Encodable & Sendable)?) throws -> [String: Any] {
        let encodable = try XCTUnwrap(body)
        let data = try JSONEncoder().encode(encodable)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func message(for code: String) -> String {
        APIError.serverError(ErrorResponse(code: code, message: "后端原文")).localizedMessage
    }
}
