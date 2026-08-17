import XCTest
@testable import blindRun

/// 盲人端两条只读信息的解码与展示：`GET /api/orders/{id}/reviews` 与 `/status-logs`。
///
/// 两条端点都**不走 `ApiResponse` 信封**，而 `APIPayloadDecoder` 的策略是「信封优先、裸解兜底」——
/// 也就是说它们都会先被当成信封解一遍。这个文件钉住的就是那一遍不能把数据吃掉：
/// 评价那条尤其危险，`{"data": {...}}` 与信封长得一模一样，合成的 `Decodable`
/// 会把内层的 `ReviewResponse` 当成 `OrderReviewEnvelope` 解成「无评价」，
/// **解得出来、值是 nil**，一条真实评价静默消失（记忆 `silent-decode-degradation-bug-class`）。
///
/// 用例一律走 `APIPayloadDecoder.decodePayload`，与线上同一条路径。
final class OrderReviewAndStatusLogDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIPayloadDecoder.decodePayload(type, from: Data(json.utf8), decoder: decoder)
    }

    // MARK: - GET /api/orders/{id}/reviews

    /// 真实响应体（`ReviewController.java:41-48` 的裸 `Map`）必须解出评价本体。
    /// 这条一旦红，现象是「明明评过分，重进订单还是让你再评一次」。
    func testReviewEnvelopeSurvivesTheEnvelopeFirstDecodingPass() throws {
        let envelope = try decode(OrderReviewEnvelope.self, """
        {
          "data": {
            "orderId": 4201,
            "rating": 5,
            "comment": "全程沟通很清楚",
            "createdAt": "2026-08-11T20:14:07"
          }
        }
        """)

        XCTAssertEqual(envelope.data?.rating, 5)
        XCTAssertEqual(envelope.data?.orderId, 4201)
        XCTAssertEqual(envelope.data?.comment, "全程沟通很清楚")
        XCTAssertEqual(envelope.data?.createdAt, "2026-08-11T20:14:07")
    }

    /// 尚未评价是 **200 + `data: null`**，不是 404，也不是错误 —— 必须解得出来、且为 nil。
    func testReviewEnvelopeDecodesTheNotYetReviewedCaseAsNil() throws {
        let envelope = try decode(OrderReviewEnvelope.self, #"{"data": null}"#)
        XCTAssertNil(envelope.data)
    }

    /// 可空字段真的可空：只有 `rating` 是写入侧保证非空的。
    func testReviewDecodesWithoutCommentOrTimestamp() throws {
        let envelope = try decode(OrderReviewEnvelope.self, """
        {"data": {"orderId": 7, "rating": 3, "comment": null, "createdAt": null}}
        """)

        XCTAssertEqual(envelope.data?.rating, 3)
        XCTAssertNil(envelope.data?.comment)
        XCTAssertNil(envelope.data?.createdAt)
    }

    /// 宽容的边界：`data` 键**必须在**。缺了就抛，而不是当成「无评价」。
    ///
    /// 这条是上面那个静默吞数据的反向锁 —— 正是因为「缺 data 键要抛」，
    /// 信封优先那一遍才会失败并退回裸解，真实评价才落到正确分支。
    /// 放宽这里，第一个用例就会开始返回 nil 而不报错。
    func testReviewEnvelopeRejectsAPayloadWithoutTheDataKey() {
        XCTAssertThrowsError(
            try decode(OrderReviewEnvelope.self, #"{"orderId": 7, "rating": 3}"#)
        )
    }

    // MARK: - GET /api/orders/{id}/status-logs

    /// 裸数组，且首条 `fromStatus` 为 null（后端 `OrderCreationService:125` 建单那一条）。
    func testStatusLogsDecodeFromABareArray() throws {
        let logs = try decode([OrderStatusLog].self, """
        [
          {"id": 92, "orderId": 4201, "fromStatus": "PENDING_ACCEPT", "toStatus": "DRIVER_EN_ROUTE",
           "changedBy": 7, "changedAt": "2026-08-11T19:31:02", "remark": "志愿者已出发"},
          {"id": 90, "orderId": 4201, "fromStatus": null, "toStatus": "PENDING_MATCH",
           "changedBy": 3, "changedAt": "2026-08-11T19:02:11", "remark": "创建订单"}
        ]
        """)

        XCTAssertEqual(logs.count, 2)
        // 后端按 changedAt 倒序返回，客户端不重排 —— 顺序本身就是断言的一部分。
        XCTAssertEqual(logs.first?.toStatus, .driverEnRoute)
        XCTAssertEqual(logs.first?.fromStatus, .pendingAccept)
        XCTAssertNil(logs.last?.fromStatus)
        XCTAssertEqual(logs.last?.toStatus, .pendingMatch)
    }

    /// AGENTS.md 红线：后端往状态机加值，客户端要降级到「未知」而不是整条崩。
    /// 这里整条崩的代价是**整个状态变更记录一条都读不出来**。
    func testStatusLogsSurviveAnUnknownBackendStatus() throws {
        let logs = try decode([OrderStatusLog].self, """
        [{"id": 1, "fromStatus": "IN_PROGRESS", "toStatus": "PAUSED_BY_BACKEND",
          "changedAt": "2026-08-11T19:31:02", "remark": "后端新增的状态"}]
        """)

        XCTAssertEqual(logs.first?.toStatus, .unknown)
        // 兄弟字段完好才算真的兜住了。
        XCTAssertEqual(logs.first?.changedAt, "2026-08-11T19:31:02")
        XCTAssertEqual(logs.first?.remark, "后端新增的状态")
    }

    // MARK: - OrderStatusLog.displayText

    /// 后端 12 处 `logStatusChange` 里 11 处的 remark 就是可朗读的中文，原样用。
    func testDisplayTextUsesTheBackendRemarkVerbatimWhenItIsReadable() {
        XCTAssertEqual(makeLog(to: .driverArrived, remark: "志愿者已到达").displayText, "志愿者已到达")
        XCTAssertEqual(makeLog(to: .completed, remark: "超时自动完成").displayText, "超时自动完成")
    }

    /// 唯一的例外：取消那条拼的是原始枚举（`OrderLifecycleService.java:260`）。
    /// 不翻译就会对着盲人念出「取消方=BLIND」。
    func testDisplayTextTranslatesTheRawCancelledByRemark() {
        XCTAssertEqual(makeLog(to: .cancelled, remark: "取消方=BLIND").displayText, "你取消了订单")
        XCTAssertEqual(makeLog(to: .cancelled, remark: "取消方=VOLUNTEER").displayText, "志愿者取消了订单")
        XCTAssertEqual(makeLog(to: .cancelled, remark: "取消方=SYSTEM").displayText, "系统自动取消了订单")
    }

    /// 后端再加一个 `CancelledBy` 取值时，落到状态名而不是把新枚举念出来。
    func testDisplayTextFallsBackToTheStatusNameForAnUnknownCanceller() {
        XCTAssertEqual(makeLog(to: .cancelled, remark: "取消方=CUSTOMER_SERVICE").displayText, "已取消")
    }

    /// remark 可空（实体列没有 `nullable = false`），空的时候用状态名兜底。
    func testDisplayTextFallsBackToTheStatusNameWhenRemarkIsMissing() {
        XCTAssertEqual(makeLog(to: .inProgress, remark: nil).displayText, "进行中")
        XCTAssertEqual(makeLog(to: .inProgress, remark: "   ").displayText, "进行中")
    }

    private func makeLog(to status: RunOrderStatus, remark: String?) -> OrderStatusLog {
        OrderStatusLog(
            id: 1,
            fromStatus: nil,
            toStatus: status,
            changedAt: "2026-08-11T19:31:02",
            remark: remark
        )
    }

    // MARK: - Mock 端到端（路由 + 状态积累）

    /// 走一遍完整流程，钉住两条新端点在 Mock 里真的接上了。
    ///
    /// 解码用例只证明「后端这么回，前端解得出」；这条证明的是另一半：路径拼对了、方法对了、
    /// 读写不对称的 `/review` 与 `/reviews` 没串到一起。少了它，把路径写错一个字母
    /// 也照样全绿。
    func testMockRecordsStatusLogsAndServesTheSubmittedReview() async throws {
        let client = MockAPIClient()
        let plannedStart = Date().addingTimeInterval(45 * 60)
        let createResponse: OrderResponse = try await client.post(
            "/api/orders",
            body: CreateOrderRequest(
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                startAddress: "朝阳公园南门",
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
                plannedStartTime: DateFormatter.aidRunBackendLocalDateTime.string(from: plannedStart),
                plannedEndTime: DateFormatter.aidRunBackendLocalDateTime
                    .string(from: plannedStart.addingTimeInterval(3600)),
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil
            )
        )
        let orderId = try XCTUnwrap(createResponse.id)

        // 尚未评价 → 200 + data: null，不是 404。
        let beforeReview: OrderReviewEnvelope = try await client.get("/api/orders/\(orderId)/reviews")
        XCTAssertNil(beforeReview.data)

        let _: EmptyResponse = try await client.put(
            "/api/volunteer/dispatch-status",
            body: DispatchStatusRequest(wantsDispatch: true)
        )
        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/arrived")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/start-service")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/finish")

        let logs: [OrderStatusLog] = try await client.get("/api/orders/\(orderId)/status-logs")
        // 建单 + 5 次流转。
        XCTAssertEqual(logs.count, 6)
        // 最新在前，与后端 `findByOrderIdOrderByChangedAtDesc` 同序。
        XCTAssertEqual(logs.first?.toStatus, .completed)
        XCTAssertEqual(logs.first?.fromStatus, .inProgress)
        // 建单那条没有前序状态。
        XCTAssertEqual(logs.last?.toStatus, .pendingMatch)
        XCTAssertNil(logs.last?.fromStatus)
        XCTAssertEqual(logs.last?.displayText, "创建订单")

        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/review",
            body: CreateReviewRequest(rating: 4, comment: "路线讲得很清楚")
        )

        let afterReview: OrderReviewEnvelope = try await client.get("/api/orders/\(orderId)/reviews")
        XCTAssertEqual(afterReview.data?.rating, 4)
        XCTAssertEqual(afterReview.data?.comment, "路线讲得很清楚")

        // 重复提交必须撞上 409 —— 「重进已完成订单再点提交」走的就是这条。
        do {
            let _: EmptyResponse = try await client.post(
                "/api/orders/\(orderId)/review",
                body: CreateReviewRequest(rating: 1, comment: nil)
            )
            XCTFail("重复评价没有被拒")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .reviewAlreadySubmitted)
        }
    }
}
