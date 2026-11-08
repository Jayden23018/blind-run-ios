import XCTest
@testable import blindRun

/// 举报与拉黑的 view model 层：失败留在原页、状态不丢。纯判定在 `UserSafetyTests`。
@MainActor
final class UserSafetyViewModelTests: XCTestCase {
    private static let target = CounterpartSafetyTarget(userId: 7, orderId: 42, messageId: nil, quotedText: nil)

    private func order(_ json: String) throws -> OrderDetailResponse {
        try JSONDecoder().decode(OrderDetailResponse.self, from: Data(json.utf8))
    }

    private func serverError(_ code: String, _ message: String = "") -> APIError {
        .serverError(ErrorResponse(code: code, message: message))
    }

    // MARK: 举报 view model

    func testReportNeedsAReasonBeforeAnyRequest() async {
        let fake = FakeSafetyService()
        let appState = AppState(safety: fake)
        let viewModel = UserReportViewModel()
        let sent = await viewModel.submit(target: Self.target, appState: appState)
        XCTAssertFalse(sent)
        XCTAssertEqual(viewModel.errorMessage, UserSafetyCopy.reasonRequired)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testOverlongDetailStaysOnScreenAndSendsNothing() async {
        let fake = FakeSafetyService()
        let appState = AppState(safety: fake)
        let viewModel = UserReportViewModel()
        viewModel.reason = .other
        viewModel.detail = String(repeating: "问", count: 1001)
        let sent = await viewModel.submit(target: Self.target, appState: appState)
        XCTAssertFalse(sent)
        XCTAssertEqual(viewModel.detail.count, 1001, "字不能丢")
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testSuccessfulReportCarriesTheMessageAndShowsTheTicketNumber() async {
        let fake = FakeSafetyService()
        fake.reportResult = .success(UserReportTicket(id: 88))
        let appState = AppState(safety: fake)
        let viewModel = UserReportViewModel()
        viewModel.reason = .unsafeBehavior
        viewModel.detail = "  一直催我快跑  "
        let message = CounterpartSafetyTarget(userId: 7, orderId: 42, messageId: 5, quotedText: "你跑太慢")

        let sent = await viewModel.submit(target: message, appState: appState)

        XCTAssertTrue(sent)
        XCTAssertEqual(fake.lastReport?.targetUserId, 7)
        XCTAssertEqual(fake.lastReport?.messageId, 5)
        XCTAssertEqual(fake.lastReport?.reason, .unsafeBehavior)
        XCTAssertEqual(fake.lastReport?.detail, "一直催我快跑")
        XCTAssertEqual(viewModel.submittedMessage, UserSafetyCopy.reportSubmitted(ticketId: 88))
        XCTAssertTrue(viewModel.submittedMessage?.contains("88") == true)
    }

    func testRejectedReportKeepsTheFormAndUsesTheGenericSentence() async {
        let fake = FakeSafetyService()
        fake.reportResult = .failure(serverError("RESOURCE_NOT_FOUND", "没有交集"))
        let appState = AppState(safety: fake)
        let viewModel = UserReportViewModel()
        viewModel.reason = .harassment
        viewModel.detail = "说明"

        let sent = await viewModel.submit(target: Self.target, appState: appState)

        XCTAssertFalse(sent)
        XCTAssertEqual(viewModel.errorMessage, UserSafetyCopy.targetUnavailable)
        XCTAssertEqual(viewModel.reason, .harassment)
        XCTAssertEqual(viewModel.detail, "说明")
        XCTAssertNil(viewModel.submittedMessage)
    }

    // MARK: 拉黑 view model

    func testBlockSucceedsOnce() async {
        let fake = FakeSafetyService()
        fake.blockUserResult = .success(())
        let appState = AppState(safety: fake)
        let viewModel = CounterpartBlockViewModel()
        let done = await viewModel.block(userId: 7, appState: appState)
        XCTAssertTrue(done)
        XCTAssertTrue(viewModel.didBlock)
        XCTAssertEqual(fake.lastBlockedUserId, 7)
    }

    func testBlockFailureLeavesTheEntryAvailable() async {
        let fake = FakeSafetyService()
        fake.blockUserResult = .failure(serverError("RESOURCE_NOT_FOUND", "没有交集"))
        let appState = AppState(safety: fake)
        let viewModel = CounterpartBlockViewModel()
        let done = await viewModel.block(userId: 7, appState: appState)
        XCTAssertFalse(done)
        XCTAssertFalse(viewModel.didBlock)
        XCTAssertEqual(viewModel.errorMessage, UserSafetyCopy.targetUnavailable)
    }

    // MARK: 已拉黑列表 view model

    private static let blocked = BlockedUserResponse(userId: 7, maskedName: "张*", blockedAt: "2026-11-02T09:30:00")

    func testListLoadsThenFailsVisibly() async {
        let fake = FakeSafetyService()
        fake.blockedUsersResult = .success([Self.blocked])
        let appState = AppState(safety: fake)
        let viewModel = BlockedUsersViewModel()
        await viewModel.load(appState: appState)
        XCTAssertEqual(viewModel.phase, .loaded([Self.blocked]))

        fake.blockedUsersResult = .failure(URLError(.timedOut))
        await viewModel.retry(appState: appState)
        XCTAssertEqual(viewModel.phase, .failed(message: UserSafetyCopy.blockedListFailed), "失败要看得见，不能落成空列表（那等于说没拉黑过任何人）")
    }

    func testUnblockReloadsFromTheServer() async {
        let fake = FakeSafetyService()
        fake.unblockUserResult = .success(())
        fake.blockedUsersResult = .success([])
        let appState = AppState(safety: fake)
        let viewModel = BlockedUsersViewModel()

        let spoken = await viewModel.unblock(Self.blocked, appState: appState)

        XCTAssertEqual(fake.lastUnblockedUserId, 7)
        XCTAssertEqual(viewModel.phase, .loaded([]))
        XCTAssertEqual(viewModel.notice, UserSafetyCopy.unblockSucceeded)
        XCTAssertEqual(spoken, UserSafetyCopy.unblockSucceeded)
    }

    func testFailedUnblockKeepsTheRow() async {
        let fake = FakeSafetyService()
        fake.blockedUsersResult = .success([Self.blocked])
        fake.unblockUserResult = .failure(URLError(.timedOut))
        let appState = AppState(safety: fake)
        let viewModel = BlockedUsersViewModel()
        await viewModel.load(appState: appState)

        _ = await viewModel.unblock(Self.blocked, appState: appState)

        XCTAssertEqual(viewModel.phase, .loaded([Self.blocked]))
        XCTAssertEqual(viewModel.actionError, UserSafetyCopy.unblockFailed)
        XCTAssertNil(viewModel.notice)
    }

    // MARK: 通话页

    private func introCall(counterpartUserId: Int64?) -> IntroCallView {
        IntroCallView(
            counterpartName: "王*", counterpartPhone: nil, counterpartPhoneMasked: nil, myDecision: nil,
            windowEndsAt: nil, startAddress: nil, plannedStartTime: nil, plannedEndTime: nil,
            counterpartUserId: counterpartUserId
        )
    }

    /// 通话端点拉取失败时 `introCall` 会清空，入口不能跟着消失：填到一半的举报单在这个入口下面。
    func testBlindIntroCallKeepsTheCounterpartThroughAFailedRefresh() async throws {
        let orders = FakeOrderService()
        orders.introCallViewResult = .success(introCall(counterpartUserId: 7))
        let appState = AppState(safety: FakeSafetyService(), orders: orders)
        let speech = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speech)
        viewModel.order = try order(#"{"orderId":42,"status":"PENDING_INTRO_CALL"}"#)

        await viewModel.reloadIntroCall()
        XCTAssertEqual(viewModel.introCallCounterpartUserId, 7)

        orders.introCallViewResult = .failure(URLError(.timedOut))
        await viewModel.reloadIntroCall()
        XCTAssertNil(viewModel.introCall, "前提：这次拉取确实失败了")
        XCTAssertEqual(viewModel.introCallCounterpartUserId, 7)
    }

    /// 陪跑员这一轮结束后读不到通话端点，也读不到订单详情，入口全靠这份留着。
    func testVolunteerIntroCallKeepsTheCounterpartAfterTheRoundEnds() async {
        let safety = FakeSafetyService()
        safety.introCallResult = .success(introCall(counterpartUserId: 7))
        let appState = AppState(safety: safety)
        let speech = SpeechService()
        let viewModel = VolunteerIntroCallViewModel()
        viewModel.configure(orderId: 42, appState: appState, speechService: speech)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.counterpartUserId, 7)

        safety.introCallResult = .failure(serverError("INTRO_CALL_NOT_ACTIVE"))
        safety.matchedOrderResult = .failure(serverError("NOT_ORDER_PARTICIPANT"))
        await viewModel.refresh()
        XCTAssertEqual(viewModel.outcome, .closed, "前提：这一轮确实结束了")
        XCTAssertNil(viewModel.introCall)
        XCTAssertEqual(viewModel.counterpartUserId, 7)
    }

    func testRemainingCountMatchesWhatIsActuallySent() {
        let viewModel = UserReportViewModel()
        viewModel.detail = String(repeating: "问", count: 1000) + "\n\n"
        XCTAssertEqual(viewModel.remainingCharacters, 0, "首尾空白发送前会去掉，不算字数")
    }

    func testRateLimitIsNotCalledANetworkProblem() {
        let limited = APIError.rateLimited(RateLimitInfo(message: "操作过于频繁。", retryAfterSeconds: nil))
        XCTAssertEqual(UserSafetyCopy.failureMessage(for: limited, fallback: "检查网络"), "操作过于频繁。")
    }

    // MARK: 记录详情取对方 id

    private struct StubRunRecord: RunRecordServing {
        let response: RunRecordResponse
        func record(orderId: Int64) async throws -> RunRecordResponse { response }
        func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse { throw URLError(.badURL) }
        func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw URLError(.badURL) }
    }

    private func runRecord() throws -> RunRecordResponse {
        let json = """
        {"orderId":42,"status":"READY","viewerRole":"BLIND","splits":[],"paceSamples":[],"stops":[],"events":[],
         "sosTriggered":false,"service":{},"messages":[]}
        """
        return try JSONDecoder().decode(RunRecordResponse.self, from: Data(json.utf8))
    }

    func testRecordDetailReadsTheCounterpartFromTheOrder() async throws {
        let orders = FakeOrderService()
        orders.orderDetailResult = .success(try order(#"{"orderId":42,"status":"COMPLETED","counterpartUserId":7}"#))
        let viewModel = RunRecordViewModel(
            orderId: 42,
            dependencies: .fixed(runRecord: StubRunRecord(response: try runRecord()), orders: orders)
        )

        await viewModel.loadUntilSettled()

        XCTAssertEqual(viewModel.counterpartTarget, Self.target)
    }

    /// 订单详情读不到时记录页照常可看，只是没有入口。
    func testRecordDetailStillLoadsWhenTheOrderCannotBeRead() async throws {
        let orders = FakeOrderService()
        orders.orderDetailResult = .failure(serverError("ORDER_PERMISSION_DENIED"))
        let viewModel = RunRecordViewModel(
            orderId: 42,
            dependencies: .fixed(runRecord: StubRunRecord(response: try runRecord()), orders: orders)
        )

        await viewModel.loadUntilSettled()

        guard case .loaded = viewModel.phase else { return XCTFail("记录应已加载") }
        XCTAssertNil(viewModel.counterpartTarget)
    }

    /// 页面用的 `.live(appState)` 要把订单详情接到 `appState.orders`（#894）。接错（比如接到默认环境的客户端）
    /// 读回来的就不是这张替身订单，对方 id 对不上。已写，未执行。
    func testLiveDependenciesReadTheOrderThroughAppState() async throws {
        let orders = FakeOrderService()
        orders.orderDetailResult = .success(try order(#"{"orderId":42,"status":"COMPLETED","counterpartUserId":7}"#))
        let appState = AppState(orders: orders)

        let detail = try await RunRecordDependencies.live(appState).orderDetail(42)

        XCTAssertEqual(detail.counterpartUserId, 7)
    }
}
