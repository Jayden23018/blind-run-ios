import XCTest
@testable import blindRun

/// 联系客服入口、我的工单、不承诺时限的文案、陪跑员使用帮助（#656，OpenSpec `add-support-entry-and-volunteer-help`）。
///
/// 这一片的风险几乎全在**文案**：一句「客服会尽快联系你」没人兑现，一句「求助已发出」把本地拨号说成云端求助，
/// 屏幕上都没有症状。所以断言大多打在文案上，并且挑的是能区分「对的文案」与「被写回去的旧文案」的取值。
@MainActor
final class SupportEntryAndVolunteerHelpTests: XCTestCase {

    // MARK: - 解码

    private func decodePage(_ json: String) throws -> SupportTicketPage {
        try JSONDecoder().decode(SupportTicketPage.self, from: Data(json.utf8))
    }

    func testRepliedTicketCarriesTheReplyText() throws {
        let page = try decodePage("""
        {"content":[{"id":7,"category":"ACCOUNT","content":"收不到验证码","status":"REPLIED",
        "csReply":"已处理，请再试一次","createdAt":"2026-11-01T09:30:00","repliedAt":"2026-11-01T14:05:00"}]}
        """)
        let ticket = try XCTUnwrap(page.content.first)
        XCTAssertEqual(ticket.id, 7)
        XCTAssertEqual(ticket.status, .replied)
        XCTAssertEqual(ticket.csReply, "已处理，请再试一次")
        XCTAssertTrue(ticket.hasReply)
    }

    /// 后端往状态里加新值：这一条要降级成「状态未知」，而不是把整页读空。
    func testUnknownStatusDegradesInsteadOfDroppingTheTicket() throws {
        let page = try decodePage(#"{"content":[{"id":1,"content":"x","status":"ESCALATED"}]}"#)
        XCTAssertEqual(page.content.map(\.status), [.unknown])
        XCTAssertEqual(SupportTicketCopy.statusLabel(.unknown), "状态未知")
    }

    /// 一项形状不对只丢这一项；其余照样显示。
    func testOneUndecodableTicketDoesNotHideTheOthers() throws {
        let page = try decodePage("""
        {"content":[{"content":"没有 id 的坏项","status":"OPEN"},
                    {"id":2,"content":"好的","status":"OPEN"}]}
        """)
        XCTAssertEqual(page.content.map(\.id), [2])
    }

    func testBlankReplyCountsAsNoReply() throws {
        let page = try decodePage(#"{"content":[{"id":3,"content":"x","status":"REPLIED","csReply":"  \n"}]}"#)
        let ticket = try XCTUnwrap(page.content.first)
        XCTAssertNil(ticket.csReply)
        XCTAssertFalse(ticket.hasReply)
    }

    func testMissingContentArrayIsAnEmptyList() throws {
        XCTAssertEqual(try decodePage("{}").content, [])
    }

    // MARK: - 端点

    func testMyTicketsUsesTheContractPathAndFirstPage() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = SupportTicketPage(content: [SupportTicketSummary(id: 9, content: "x", status: .open)])
        let tickets = try await SafetyService(transport: transport).myTickets()

        XCTAssertEqual(tickets.map(\.id), [9])
        let recorded = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(recorded.method, .get)
        XCTAssertEqual(recorded.path, "/api/support/tickets")
        XCTAssertEqual(recorded.query?["page"], "0")
        XCTAssertEqual(recorded.query?["size"], "50", "契约 size 上限 100，取 50")
        XCTAssertTrue(recorded.requiresAuth)
        XCTAssertFalse(recorded.hasBody)
    }

    /// 提交仍是同一路径上的 POST，加读取不能把它改掉。
    func testSubmitStillPostsToTheSamePath() {
        XCTAssertEqual(SafetyEndpoint.supportTicket.request.method, .post)
        XCTAssertEqual(SafetyEndpoint.supportTicket.request.path, SafetyEndpoint.myTickets.request.path)
    }

    // MARK: - 视图模型

    func testLoadFailureIsNotShownAsAnEmptyList() async {
        let safety = FakeSafetyService()
        safety.myTicketsResult = .failure(APIError.unknown(statusCode: 500))
        let appState = AppState(safety: safety)
        let viewModel = MySupportTicketsViewModel()

        await viewModel.load(appState: appState)

        XCTAssertEqual(viewModel.phase, .failed, "读取失败显示成「还没有工单」，刚提交过投诉的人会以为提交丢了")
    }

    func testLoadSuccessShowsTicketsInServerOrder() async {
        let safety = FakeSafetyService()
        let newer = SupportTicketSummary(id: 2, content: "新", status: .open)
        let older = SupportTicketSummary(id: 1, content: "旧", status: .replied, csReply: "回复")
        safety.myTicketsResult = .success([newer, older])
        let appState = AppState(safety: safety)
        let viewModel = MySupportTicketsViewModel()

        await viewModel.load(appState: appState)

        XCTAssertEqual(viewModel.phase, .loaded([newer, older]))
    }

    // MARK: - 文案红线

    private static let promiseWords = ["尽快", "马上", "立即联系", "回拨", "分钟内", "小时内", "天内", "24小时", "24 小时"]

    private func assertNoPromise(_ text: String, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        for word in Self.promiseWords {
            XCTAssertFalse(text.contains(word), "\(name) 又出现了「\(word)」：不承诺回复时限（负责人 2026-11-04）。\n\(text)", file: file, line: line)
        }
    }

    func testTicketPageSaysItIsNotAnInstantChannelBeforeTheUserWrites() {
        let notice = SupportTicketCopy.notice
        XCTAssertTrue(notice.contains("不是即时通道"))
        XCTAssertTrue(notice.contains("会有工作人员查看"))
        XCTAssertTrue(notice.contains("120") && notice.contains("110"))
        assertNoPromise(notice, "工单页提示")
    }

    /// 跑步中面板的联系客服行：旧文案「提交后客服会尽快联系你」是没人兑现的承诺。
    func testRunningPanelDoesNotPromiseCustomerServiceWillContactYou() {
        for (name, text) in [
            ("副标题", VolunteerRunCopy.supportRowSubtitle),
            ("提交回显", VolunteerRunCopy.supportSubmitted),
            ("面板内提交后副标题", VolunteerRunHelpPanel.supportRowSubtitle(state: .submitted, isSessionExpired: false))
        ] {
            assertNoPromise(text, name)
            XCTAssertFalse(text.contains("联系你"), "\(name) 写了「联系你」：\(text)")
            XCTAssertTrue(text.contains("不是即时通道"), "\(name) 没说不是即时通道：\(text)")
        }
    }

    /// 派单规则说明里的「联系客服」要指向「我的」页上真实存在、名字一致的入口。
    func testDispatchNoticePointsAtTheRealEntry() {
        let text = DispatchAlgorithmNoticeCopy.sections
            .flatMap { [$0.heading] + $0.bullets }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("「\(SupportTicketCopy.title)」"), "要写入口的真名：\(SupportTicketCopy.title)")
        XCTAssertTrue(text.contains("「我的」页"))
        assertNoPromise(DispatchAlgorithmNoticeCopy.sections.flatMap(\.bullets).joined(), "派单规则说明")
    }

    /// 其他文案指向「我的」页入口时，名字必须与入口一致 —— 改了入口名而漏改它们，用户就找不到。
    func testCopyThatPointsAtTheEntryUsesItsRealName() {
        let quoted = "「\(SupportTicketCopy.title)」"
        XCTAssertTrue(AccountSuspensionCopy.supplement.contains(quoted))
        XCTAssertTrue(AccountSuspensionCopy.dispatchNotice.contains(quoted))
        XCTAssertTrue(UserSafetyCopy.targetUnavailable.contains(quoted))
        XCTAssertEqual(SupportTicketCopy.title, "联系客服")
        XCTAssertFalse(SupportTicketCopy.title.contains("求助"), "「求助」在本 App 里专指云端 SOS")
    }

    func testRowReadsStatusTimeWordsAndReplyInOneBreath() {
        let replied = SupportTicketSummary(id: 1, content: "收不到验证码", status: .replied, csReply: "已处理")
        let label = SupportTicketCopy.rowAccessibilityLabel(replied, time: "11月1日 09:30")
        XCTAssertEqual(label, "已回复。11月1日 09:30。你写的：收不到验证码。客服回复：已处理")

        let waiting = SupportTicketSummary(id: 2, content: "问一下", status: .open)
        let waitingLabel = SupportTicketCopy.rowAccessibilityLabel(waiting, time: nil)
        XCTAssertTrue(waitingLabel.hasSuffix(SupportTicketCopy.noReplyYet))
        XCTAssertFalse(waitingLabel.contains("等待回复"), "不暗示一定会有回复")
        assertNoPromise(waitingLabel, "无回复的工单行")
    }

    // MARK: - 陪跑员帮助：文案

    private var helpText: String {
        VolunteerFirstRunHelp.topics.map { "\($0.title)\n\($0.body)" }.joined(separator: "\n")
    }

    func testHelpWalksThroughEveryStepWithTheRealButtonNames() {
        let flow = VolunteerFirstRunHelp.topics.first { $0.id == "flow" }?.body ?? ""
        for name in [
            VolunteerOrderFlowCopy.confirmDeparture,
            VolunteerOrderFlowCopy.enRoute,
            VolunteerOrderFlowCopy.arrived,
            VolunteerOrderFlowCopy.startRun,
            VolunteerFinishLongPress.title
        ] {
            XCTAssertTrue(flow.contains("「\(name)」"), "帮助页没讲到按钮「\(name)」：\(flow)")
        }
    }

    /// 红线（AGENTS.md §6）：非跑步中只有本地拨号，要说清 App 不会代发；客服不是求助入口。
    func testHelpSaysWhereToGoWhenSomethingGoesWrongWithoutOverpromising() throws {
        let help = try XCTUnwrap(VolunteerFirstRunHelp.topics.first { $0.id == "help" }).body
        XCTAssertTrue(help.contains("120") && help.contains("110"))
        XCTAssertTrue(help.contains("App 不会代你发送求助"), "没说降级时不会代发，陪跑员会以为按下去求助已发出：\(help)")
        XCTAssertTrue(help.contains("只有跑步进行中"))
        XCTAssertTrue(help.contains("不是求助入口"))
        XCTAssertTrue(help.contains("不会立刻有人联系你"))
        XCTAssertTrue(help.contains("「\(SupportTicketCopy.title)」"))
        XCTAssertTrue(help.contains("「\(VolunteerRunCopy.navButtonLabel)」"), "求助入口的名字要和跑步页上的一致")
        for banned in ["已通知", "已发出", "已送达", "回拨", "会有人来", "马上有人"] {
            XCTAssertFalse(helpText.contains(banned), "帮助页出现「\(banned)」：App 不得宣称有人已被通知或会回拨")
        }
        assertNoPromise(helpText, "陪跑员帮助页")
    }

    // MARK: - 陪跑员帮助：首次自动打开

    /// 只在出发之前两态弹；其余每个状态逐个钉，新增状态时这里要有人来决定。
    func testAutoOpenOnlyBeforeDeparture() {
        let allowed: Set<RunOrderStatus> = [.scheduledConfirmed, .pendingAccept]
        for status in RunOrderStatus.allCases + [.unknown] {
            XCTAssertEqual(
                VolunteerFirstRunHelpPolicy.shouldAutoOpen(status: status, alreadySeen: false),
                allowed.contains(status),
                "\(status.rawValue) 的自动弹出判定变了"
            )
        }
        XCTAssertFalse(VolunteerFirstRunHelpPolicy.shouldAutoOpen(status: nil, alreadySeen: false), "订单没加载出来不弹")
    }

    func testNeverAutoOpensOnceSeen() {
        for status in RunOrderStatus.allCases + [.unknown] {
            XCTAssertFalse(VolunteerFirstRunHelpPolicy.shouldAutoOpen(status: status, alreadySeen: true))
        }
    }

    func testSeenFlagIsWrittenOnlyByMarkAndSurvivesRelaunchAndLogout() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)
        XCTAssertFalse(appState.didSeeVolunteerFirstRunHelp, "全新安装必须弹一次")
        XCTAssertNil(persistence.object(forKey: AppConstants.UserDefaultsKeys.volunteerFirstRunHelpSeen))

        appState.markVolunteerFirstRunHelpSeen()

        XCTAssertTrue(appState.didSeeVolunteerFirstRunHelp)
        XCTAssertEqual(persistence.object(forKey: AppConstants.UserDefaultsKeys.volunteerFirstRunHelpSeen) as? Bool, true)
        XCTAssertTrue(AppState(persistence: persistence).didSeeVolunteerFirstRunHelp, "重启后又回到未看过")
        await appState.logout()
        XCTAssertTrue(appState.didSeeVolunteerFirstRunHelp, "登出把标志清了，换号重登的老陪跑员会被再弹一次")
    }

    /// 两端各记各的：盲人看过引导不代表陪跑员看过（同一台手机先后用两个角色是真实场景）。
    func testBlindAndVolunteerFlagsAreIndependent() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)
        appState.markBlindFirstRunHelpSeen()
        XCTAssertFalse(appState.didSeeVolunteerFirstRunHelp)
    }
}
