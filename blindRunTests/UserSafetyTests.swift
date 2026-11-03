import XCTest
@testable import blindRun

/// 举报与拉黑（OpenSpec `add-user-report-and-block`，#524）。
///
/// 入口显示判定、请求构造、解码宽容、错误文案都是纯逻辑，这里逐条钉住。
@MainActor
final class UserSafetyTests: XCTestCase {
    private static let target = CounterpartSafetyTarget(userId: 7, orderId: 42, messageId: nil, quotedText: nil)

    private func order(_ json: String) throws -> OrderDetailResponse {
        try JSONDecoder().decode(OrderDetailResponse.self, from: Data(json.utf8))
    }

    private func serverError(_ code: String, _ message: String = "") -> APIError {
        .serverError(ErrorResponse(code: code, message: message))
    }

    // MARK: 入口判定

    func testEntryIsHiddenWhenTheBackendGaveNoUsableId() {
        XCTAssertNil(CounterpartSafetyGate.target(userId: nil, orderId: 42))
        XCTAssertNil(CounterpartSafetyGate.target(userId: 0, orderId: 42), "0 不是合法 users.id，点了只会 404")
        XCTAssertNil(CounterpartSafetyGate.target(userId: -3, orderId: 42))
        XCTAssertEqual(CounterpartSafetyGate.target(userId: 7, orderId: 42), Self.target)
    }

    /// 取消后的单是这个字段存在的理由：`volunteerId` 为空而 `counterpartUserId` 有值。
    /// 用 `volunteerId` 顶替的实现在这里拿到 nil。
    func testOrderPageUsesCounterpartIdEvenAfterTheVolunteerCancelled() throws {
        let cancelled = try order(#"{"orderId":42,"status":"PENDING_MATCH","counterpartUserId":7}"#)
        XCTAssertNil(cancelled.volunteerId)
        XCTAssertEqual(CounterpartSafetyGate.orderPageTarget(cancelled), Self.target)
    }

    /// 反过来：只有 `volunteerId` 没有 `counterpartUserId` 时不放入口，不拿别的字段猜。
    func testOrderPageDoesNotFallBackToVolunteerId() throws {
        let detail = try order(#"{"orderId":42,"status":"COMPLETED","volunteerId":9}"#)
        XCTAssertNil(CounterpartSafetyGate.orderPageTarget(detail))
    }

    func testRunningPageKeepsOnlyTheSafetyAction() throws {
        let running = try order(#"{"orderId":42,"status":"IN_PROGRESS","counterpartUserId":7}"#)
        XCTAssertNil(CounterpartSafetyGate.orderPageTarget(running))
        let finished = try order(#"{"orderId":42,"status":"COMPLETED","counterpartUserId":7}"#)
        XCTAssertNotNil(CounterpartSafetyGate.orderPageTarget(finished))
    }

    func testOnlyTheOtherSidesMessageCanBeReported() {
        func target(
            from: RunRecordRole,
            viewer: RunRecordRole,
            counterpart: CounterpartSafetyTarget? = UserSafetyTests.target
        ) -> CounterpartSafetyTarget? {
            CounterpartSafetyGate.messageTarget(
                messageId: 5, fromRole: from, text: "一句话", viewerRole: viewer, counterpart: counterpart
            )
        }
        XCTAssertNil(target(from: .volunteer, viewer: .volunteer), "自己写的留言")
        XCTAssertNil(target(from: .unknown, viewer: .blind), "认不出的角色：messageId 可能不是对方写的")
        XCTAssertNil(target(from: .blind, viewer: .unknown))
        XCTAssertNil(target(from: .volunteer, viewer: .blind, counterpart: nil), "没有对方 id")

        let reported = target(from: .volunteer, viewer: .blind)
        XCTAssertEqual(reported?.userId, 7)
        XCTAssertEqual(reported?.orderId, 42)
        XCTAssertEqual(reported?.messageId, 5)
        XCTAssertEqual(reported?.quotedText, "一句话")
    }

    // MARK: 解码

    func testOrderKeepsCounterpartIdThroughStatusChanges() throws {
        let detail = try order(#"{"orderId":42,"status":"PENDING_ACCEPT","counterpartUserId":7}"#)
        XCTAssertEqual(detail.counterpartUserId, 7)
        XCTAssertEqual(detail.replacingStatus(with: .driverEnRoute).counterpartUserId, 7, "漏掉会让入口在轮询后静默消失")
    }

    /// 字段类型不对时合成解码会让整张订单失败，页面全空。
    func testMalformedCounterpartIdDoesNotBreakTheOrder() throws {
        let detail = try order(#"{"orderId":42,"status":"COMPLETED","counterpartUserId":"seven"}"#)
        XCTAssertEqual(detail.orderId, 42)
        XCTAssertNil(detail.counterpartUserId)
        XCTAssertNil(try order(#"{"orderId":42,"status":"COMPLETED","counterpartUserId":null}"#).counterpartUserId)
        XCTAssertNil(try order(#"{"orderId":42,"status":"COMPLETED"}"#).counterpartUserId)
    }

    func testIntroCallCarriesCounterpartId() throws {
        func decode(_ json: String) throws -> IntroCallView {
            try JSONDecoder().decode(IntroCallView.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode(#"{"counterpartName":"李*","counterpartUserId":7}"#).counterpartUserId, 7)
        XCTAssertNil(try decode(#"{"counterpartName":"李*","counterpartUserId":{}}"#).counterpartUserId)
    }

    func testBlockedListSkipsAMalformedRowAndKeepsTheRest() throws {
        let json = """
        [{"userId":1,"maskedName":"张*","blockedAt":"2026-11-02T09:30:00"},
         {"maskedName":"缺 id"},
         {"userId":3,"maskedName":null,"blockedAt":12345}]
        """
        let list = try JSONDecoder().decode(SkippingUndecodable<BlockedUserResponse>.self, from: Data(json.utf8))
        XCTAssertEqual(list.wrappedValue.map(\.userId), [1, 3])
        XCTAssertEqual(list.wrappedValue[0].spokenName, "张", "读屏不念星号")
        XCTAssertEqual(list.wrappedValue[1].displayName, UserSafetyCopy.unknownPerson)
        XCTAssertNil(list.wrappedValue[1].blockedAt)
    }

    func testDispatchSummarySurvivesAnUnknownReasonNextToSuspension() throws {
        let json = #"{"canDispatch":false,"notAvailableReasons":["ACCOUNT_SUSPENDED","SOME_NEW_REASON"]}"#
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data(json.utf8))
        XCTAssertEqual(summary.notAvailableReasons, [.accountSuspended, .unknown])
        XCTAssertEqual(summary.reasonText, VolunteerDispatchNotAvailableReason.accountSuspended.displayText)
    }

    // MARK: 请求

    func testReportReasonsAreExactlyTheContractEnum() {
        XCTAssertEqual(
            UserReportReason.allCases.map(\.rawValue),
            ["HARASSMENT", "UNSAFE_BEHAVIOR", "FALSE_INFO", "OTHER"]
        )
    }

    func testBlankDetailIsOmittedFromTheRequest() throws {
        let request = try XCTUnwrap(UserReportRequest(target: Self.target, reason: .harassment, detail: " \n "))
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(body?["targetUserId"] as? Int, 7)
        XCTAssertEqual(body?["reason"] as? String, "HARASSMENT")
        XCTAssertEqual(body?["orderId"] as? Int, 42)
        XCTAssertNil(body?["detail"])
        XCTAssertNil(body?["messageId"])
    }

    /// 输入落在两种计数口径之间：500 个 emoji 按字素簇是 500、按 UTF-16 正好 1000，
    /// 再加一个按字素簇是 501（放行）、按 UTF-16 是 1002（要拦）。
    func testDetailLimitIsCountedInUTF16() {
        let emoji = "🏃"
        let exactly = String(repeating: emoji, count: 500)
        XCTAssertNotNil(UserReportRequest(target: Self.target, reason: .other, detail: exactly))
        XCTAssertNil(UserReportRequest(target: Self.target, reason: .other, detail: exactly + emoji))
    }

    func testEndpointsMatchTheContract() {
        let cases: [(SafetyEndpoint, HTTPMethod, String)] = [
            (.report, .post, "/api/reports"),
            (.blockUser(userId: 7), .post, "/api/users/7/block"),
            (.unblockUser(userId: 7), .delete, "/api/users/7/block"),
            (.blockedUsers, .get, "/api/users/blocked")
        ]
        for (endpoint, method, path) in cases {
            XCTAssertEqual(endpoint.request.method, method)
            XCTAssertEqual(endpoint.request.path, path)
        }
    }

    /// Mock 的 `/api/users/` 删除兜底会拒绝一切 DELETE，解除要排在它前面才走得到。
    func testMockBlockRoundTripIsNotCaughtByTheAccountDeletionGuard() async throws {
        let service = SafetyService(transport: MockAPIClient())
        try await service.blockUser(userId: 7)
        try await service.blockUser(userId: 7)
        let afterBlock = try await service.blockedUsers()
        XCTAssertEqual(afterBlock.map(\.userId), [7], "幂等，不出现两行")
        try await service.unblockUser(userId: 7)
        let afterUnblock = try await service.blockedUsers()
        XCTAssertTrue(afterUnblock.isEmpty)
    }

    // MARK: 错误文案

    func testSuspensionReadsTheServerMessageThenAddsWhoCanHelp() {
        // 故意与本地兜底文案不同：用后端真实那句时，不念后端 message 的实现也能过这条断言（验红时实测）。
        let server = "账号受限（来自后端的句子）"
        let message = serverError("ACCOUNT_SUSPENDED", server).localizedMessage
        XCTAssertTrue(message.hasPrefix(server), "后端原文一个字不动")
        XCTAssertTrue(message.contains("上报问题"), "要说清去哪里找客服")
        XCTAssertTrue(message.contains("不是这次操作出了错"), "要说清为什么")
    }

    /// 后端 message 为空时本地文案要自己说全：发生了什么、为什么、能做什么、谁能帮。
    func testSuspensionFallbackCoversAllFourQuestions() {
        let message = serverError("ACCOUNT_SUSPENDED").localizedMessage
        for phrase in ["不能下单或接单", "平台对账号的限制", "紧急求助", "客服"] {
            XCTAssertTrue(message.contains(phrase), "缺「\(phrase)」")
        }
    }

    func testSuspensionNeverEndsTheSession() {
        let appState = AppState()
        XCTAssertFalse(appState.handleAuthenticatedAPIError(serverError("ACCOUNT_SUSPENDED", "受限")))
    }

    func testMessagesTheContractAsksToReadAloud() {
        XCTAssertEqual(
            serverError("FAVORITE_VOLUNTEER_NOT_ELIGIBLE", "你已拉黑对方，请先解除").localizedMessage,
            "你已拉黑对方，请先解除"
        )
        XCTAssertEqual(
            serverError("SUPPORT_TICKET_LIMIT_EXCEEDED", "你还有 5 条工单在处理中").localizedMessage,
            "你还有 5 条工单在处理中"
        )
    }

    func testTargetErrorsAllShareOneSentence() {
        let notFound = serverError("RESOURCE_NOT_FOUND", "对方不存在")
        XCTAssertEqual(
            UserSafetyCopy.failureMessage(for: notFound, fallback: "兜底"),
            UserSafetyCopy.targetUnavailable,
            "后端 message 不上屏：区分原因等于确认这个 id 是谁"
        )
        XCTAssertEqual(UserSafetyCopy.failureMessage(for: .networkError(URLError(.timedOut)), fallback: "兜底"), "兜底")
    }

    func testSuspensionBlocksTheAvailabilitySlider() {
        func status(_ reasons: [VolunteerDispatchNotAvailableReason]) -> VolunteerAvailabilityStatus {
            .resolve(isAvailable: false, hasSummary: true, canDispatch: false, reasons: reasons, explanation: "")
        }
        XCTAssertEqual(status([.accountSuspended]), .blockedBySuspension)
        XCTAssertEqual(status([.notVerified, .accountSuspended]), .blockedBySuspension, "资质办完也接不了单，先说这件")
        XCTAssertTrue(VolunteerAvailabilityStatus.blockedBySuspension.blocksOpening)
    }
}
