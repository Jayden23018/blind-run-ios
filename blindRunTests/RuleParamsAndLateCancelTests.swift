import XCTest
@testable import blindRun

/// 后端 #361（取消响应带 `countedAsLateCancel`）与 #356（`GET /api/config/rules`）。
@MainActor
final class RuleParamsAndLateCancelTests: XCTestCase {

    // MARK: - 规则参数

    func testRuleParamsUseServerValuesWhenPositive() {
        let params = RuleParams(response: RuleParamsResponse(lateCancelWindowHours: 6, volunteerOrderAutoOpenLeadMinutes: 45))
        XCTAssertEqual(params.lateCancelWindowHours, 6)
        XCTAssertEqual(params.volunteerOrderAutoOpenLeadMinutes, 45)
    }

    /// 缺字段、0、负数都退回默认值 —— 0 小时的窗口会让取消提醒永远不出现。
    func testRuleParamsFallBackOnMissingOrNonPositiveValues() {
        XCTAssertEqual(RuleParams(response: nil), .fallback)
        XCTAssertEqual(
            RuleParams(response: RuleParamsResponse(lateCancelWindowHours: nil, volunteerOrderAutoOpenLeadMinutes: 0)),
            .fallback
        )
        XCTAssertEqual(
            RuleParams(response: RuleParamsResponse(lateCancelWindowHours: -1, volunteerOrderAutoOpenLeadMinutes: 90))
                .lateCancelWindowHours,
            12
        )
        XCTAssertEqual(RuleParams.fallback.lateCancelWindowHours, 12)
        XCTAssertEqual(RuleParams.fallback.volunteerOrderAutoOpenLeadMinutes, 120)
    }

    func testAppStateLoadsRuleParamsOnceAndRetriesAfterFailure() async {
        let auth = FakeAuthService()
        auth.ruleParamsResult = .failure(APIError.networkError(URLError(.timedOut)))
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        // 内存 token 库：`accessToken` 的 didSet 会落库，用真 Keychain 会污染设备。
        let appState = AppState(auth: auth, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.accessToken = "token"

        await appState.loadRuleParamsIfNeeded()
        XCTAssertEqual(appState.ruleParams, .fallback, "拉失败时用默认值")

        auth.ruleParamsResult = .success(RuleParamsResponse(lateCancelWindowHours: 6, volunteerOrderAutoOpenLeadMinutes: 45))
        await appState.loadRuleParamsIfNeeded()
        XCTAssertEqual(appState.ruleParams.lateCancelWindowHours, 6, "失败之后没有重试")

        await appState.loadRuleParamsIfNeeded()
        XCTAssertEqual(auth.calls.filter { $0.hasPrefix("ruleParams") }.count, 2, "成功之后又拉了一次")
    }

    /// 自动打开订单页的提前量跟着下发值走：90 分钟后开跑的单，提前量 120 打开、提前量 60 不打开。
    func testLaunchRouteUsesTheGivenLeadMinutes() {
        let now = Date()
        let order = OrderDetailResponse.preview(
            orderId: 7,
            status: .scheduledConfirmed,
            plannedStart: DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(90 * 60))
        )
        XCTAssertEqual(
            VolunteerHomeViewModel.launchOrderToOpen(activeOrder: nil, scheduledOrders: [order], now: now, leadMinutes: 120)?.orderId,
            7
        )
        XCTAssertNil(
            VolunteerHomeViewModel.launchOrderToOpen(activeOrder: nil, scheduledOrders: [order], now: now, leadMinutes: 60)
        )
    }

    // MARK: - 取消响应

    /// 契约：响应是裸对象，不在信封里。
    func testCancelResponseDecodesFromTheBareBackendObject() throws {
        let data = Data(#"{"success":true,"countedAsLateCancel":true}"#.utf8)
        let decoded = try APIPayloadDecoder.decodePayload(CancelOrderResponse.self, from: data, decoder: JSONDecoder())
        XCTAssertEqual(decoded.countedAsLateCancel, true)
    }

    /// 缺键时不该让「取消已经成功」变成解码错误。
    func testCancelResponseToleratesAMissingFlag() throws {
        let data = Data(#"{"success":true}"#.utf8)
        let decoded = try APIPayloadDecoder.decodePayload(CancelOrderResponse.self, from: data, decoder: JSONDecoder())
        XCTAssertNil(decoded.countedAsLateCancel)
        XCTAssertEqual(VolunteerCancelAnnouncement.suffix(for: decoded), "")
    }

    // MARK: - 播报的两种先后

    /// 响应先到：取消那一句里直接带上「已记一次」，之后不再补。
    func testResponseFirstPutsTheNoticeInsideTheCancellationSentence() {
        var announcement = VolunteerCancelAnnouncement()
        announcement.begin()
        XCTAssertNil(announcement.recordResponse(CancelOrderResponse(success: true, countedAsLateCancel: true)))
        XCTAssertEqual(
            announcement.cancellationSentence(),
            VolunteerCancelAnnouncement.cancelledByVolunteer + VolunteerCancelAnnouncement.lateCancelRecorded
        )
    }

    /// 推送先到：取消那一句已经念了，响应到达时补一句，且只补一次。
    func testPushFirstAppendsTheNoticeExactlyOnce() {
        var announcement = VolunteerCancelAnnouncement()
        announcement.begin()
        XCTAssertEqual(announcement.cancellationSentence(), VolunteerCancelAnnouncement.cancelledByVolunteer)
        let response = CancelOrderResponse(success: true, countedAsLateCancel: true)
        XCTAssertEqual(announcement.recordResponse(response), VolunteerCancelAnnouncement.lateCancelRecorded)
        XCTAssertNil(announcement.recordResponse(response), "同一次取消补了两遍")
    }

    func testNotCountedNeverMentionsLateCancel() {
        var announcement = VolunteerCancelAnnouncement()
        announcement.begin()
        XCTAssertEqual(announcement.cancellationSentence(), VolunteerCancelAnnouncement.cancelledByVolunteer)
        XCTAssertNil(announcement.recordResponse(CancelOrderResponse(success: true, countedAsLateCancel: false)))
    }

    /// `CANCELLED` 有两种来源：自己取消撞上重匹上限（要念取消那一句），跑者取消（不念）。
    func testCancelledIsOnlyAnnouncedAsOwnCancellationWhenSelfInitiated() {
        var announcement = VolunteerCancelAnnouncement()
        XCTAssertFalse(announcement.announcesCancellation(entering: .cancelled), "跑者取消被念成了「你取消了」")
        XCTAssertTrue(announcement.announcesCancellation(entering: .rematching))
        announcement.begin()
        XCTAssertTrue(announcement.announcesCancellation(entering: .cancelled))
        XCTAssertFalse(announcement.announcesCancellation(entering: .inProgress))
    }

    /// 文案红线：只说「记一次」，不说后果；取消那一句不说「重新匹配」（重匹到上限时不成立）。
    func testCopyStatesOnlyTheCount() {
        let all = VolunteerCancelAnnouncement.cancelledByVolunteer + VolunteerCancelAnnouncement.lateCancelRecorded
        for forbidden in ["3 次", "14 天", "不会收到邀请", "处罚", "重新匹配"] {
            XCTAssertFalse(all.contains(forbidden), "不许写：\(forbidden)")
        }
    }

    // MARK: - 视图模型

    /// 订单页：取消成功、确认拉取回来是 `REMATCHING` ⇒ 只念一句，且带上「已记一次」。
    /// 原来先念盲人端的「正在确认志愿者状态」，再被同档的取消句切断。
    func testDetailPageSpeaksOneSentenceWithTheNoticeAfterACountedCancel() async {
        let service = FakeOrderService()
        service.cancelResult = .success(CancelOrderResponse(success: true, countedAsLateCancel: true))
        service.orderDetailResult = .success(.preview(orderId: 31, status: .rematching))
        let appState = AppState(orders: service)
        appState.currentEnvironment = .mock
        let speech = SpeechService()
        let viewModel = VolunteerOrderDetailViewModel()
        viewModel.configure(with: appState, speechService: speech)
        viewModel.order = .preview(orderId: 31, status: .pendingAccept)
        speech.resetSpokenHistoryForTesting()

        await viewModel.cancel()
        await waitUntil { viewModel.didCancelOrder }

        XCTAssertEqual(
            speech.spokenHistoryForTesting,
            [VolunteerCancelAnnouncement.cancelledByVolunteer + VolunteerCancelAnnouncement.lateCancelRecorded]
        )
    }

    // MARK: - Mock 与契约对齐

    func testMockCountsAVolunteerCancelInsideTheWindowOnly() throws {
        let mock = MockAPIClient()
        mock.mockRole = .volunteer
        let soon = DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(3 * 3600))
        let later = DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(72 * 3600))
        mock.orders = [
            .preview(orderId: 41, status: .pendingAccept, plannedStart: soon),
            .preview(orderId: 42, status: .pendingAccept, plannedStart: later),
        ]
        XCTAssertEqual(try mock.handleCancel(orderId: 41).countedAsLateCancel, true)
        XCTAssertEqual(try mock.handleCancel(orderId: 42).countedAsLateCancel, false)
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
