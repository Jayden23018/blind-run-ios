import XCTest
@testable import blindRun

/// 首次使用引导。
///
/// 这一页的价值全在**文案**，所以断言几乎全打在文案上 —— 一个盲人 App 的引导把求助说错，
/// 比布局错严重得多：他会以为按下去求助已经发出去了。
@MainActor
final class BlindFirstRunHelpTests: XCTestCase {

    // MARK: - 文案红线

    /// `AGENTS.md` §6：非 `IN_PROGRESS` 的求助一律降级为本地拨号，
    /// **降级分支的文案必须说清「App 不会代你发送求助」**。
    ///
    /// 引导页是用户听到求助说明的第一处，也可能是唯一一处（首页那句提示要按下去才听得到）。
    /// 这里只讲云端那一半，等于亲口教会用户一个错误的预期。
    func testEmergencyTopicSaysTheAppDoesNotSendHelpOnTheFallbackPath() {
        let sos = topic(id: "sos")

        XCTAssertTrue(
            sos.body.contains("App 不会代你发送求助"),
            """
            求助说明里没有「App 不会代你发送求助」。\
            非进行中状态下两指双击只会拨电话，不说清等于让盲人以为求助已经发出（AGENTS.md §6 红线）。
            实际文案：\(sos.body)
            """
        )
    }

    /// 两种模式都要讲到。只讲降级那一半同样是错的 —— 用户会不知道进行中时它真的会上报。
    func testEmergencyTopicCoversBothCloudAndFallbackModes() {
        let body = topic(id: "sos").body

        XCTAssertTrue(body.contains("进行中"), "没讲清云端求助只在陪跑进行中可用")
        XCTAssertTrue(body.contains("其他时候"), "没讲清其余状态会降级，用户会以为任何时候按下都一样")
        XCTAssertTrue(
            body.contains("两根手指双击"),
            "没教 Magic Tap。这是我们自己绑的手势，不教没有任何人猜得到 —— 引导存在的理由就是它"
        )
        XCTAssertTrue(body.contains("确认"), "没说需要二次确认，用户会以为一按就发出")
    }

    /// 提前量必须跟着 `AppConstants` 走。
    ///
    /// 写死 30 的那一版在产品松绑提前量的当天就会变成一句骗人的话，而它错得很安静：
    /// 没有任何东西会失败，只有用户按引导说的做然后被拒。
    func testBookingTopicTakesLeadMinutesFromConstantsInsteadOfHardcoding() {
        let withDefault = BlindFirstRunHelp.topics().first { $0.id == "booking" }?.body ?? ""
        XCTAssertTrue(
            withDefault.contains("\(AppConstants.Timing.minimumBookingLeadMinutes) 分钟"),
            "默认文案里的提前量与 AppConstants 对不上：\(withDefault)"
        )

        // 换一个值，文案必须跟着变 —— 上面那条在「写死 30 且常量恰好是 30」时也会绿。
        let withCustom = BlindFirstRunHelp.topics(leadMinutes: 45).first { $0.id == "booking" }?.body ?? ""
        XCTAssertTrue(withCustom.contains("45 分钟"), "提前量是写死的，没跟着参数走：\(withCustom)")
        XCTAssertFalse(withCustom.contains("30 分钟"), "文案里还留着写死的 30：\(withCustom)")
    }

    /// 播报脚本必须把三条都念出来。漏一条的表现是「引导听起来很完整，但少了一件事」，
    /// 人工过一遍很难发现少的是哪条。
    func testSpokenScriptContainsEveryTopic() {
        let script = BlindFirstRunHelp.spokenScript()

        XCTAssertTrue(script.contains(BlindFirstRunHelp.intro), "播报脚本漏了开场白")
        for topic in BlindFirstRunHelp.topics() {
            XCTAssertTrue(script.contains(topic.title), "播报脚本漏了标题：\(topic.title)")
            XCTAssertTrue(script.contains(topic.body), "播报脚本漏了正文：\(topic.title)")
        }
    }

    func testTopicsAreExactlyTheThreeAppSpecificOnes() {
        XCTAssertEqual(
            BlindFirstRunHelp.topics().map(\.id),
            ["booking", "sos", "repeat"],
            "引导条目变了。加条目前先想清楚：听完要多久？盲人在路上听不完就退出，等于没有引导"
        )
    }

    // MARK: - 「看过」标志

    func testHelpIsNotMarkedSeenUntilTheUserConfirms() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)

        XCTAssertFalse(appState.didSeeBlindFirstRunHelp, "全新安装必须走一次引导")

        appState.markBlindFirstRunHelpSeen()

        XCTAssertTrue(appState.didSeeBlindFirstRunHelp)
        XCTAssertEqual(
            persistence.object(forKey: AppConstants.UserDefaultsKeys.blindFirstRunHelpSeen) as? Bool,
            true,
            "标志没落盘，下次启动会再弹一次引导"
        )
    }

    func testSeenFlagSurvivesRelaunch() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        AppState(persistence: persistence).markBlindFirstRunHelpSeen()

        // 同一个持久化域上重建 AppState = 重启 App。
        XCTAssertTrue(
            AppState(persistence: persistence).didSeeBlindFirstRunHelp,
            "重启后又回到未看过，用户每次开 App 都要被引导页拦一次"
        )
    }

    /// 登出**不清**这个标志，与按账号记的实名提示刻意不同。
    /// 换手机号重登的盲人被强制再听一分钟引导是实打实的打扰，而漏掉引导有兜底：设置里一直在。
    func testSeenFlagIsNotClearedByLogout() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)
        appState.markBlindFirstRunHelpSeen()

        await appState.logout()

        XCTAssertTrue(
            appState.didSeeBlindFirstRunHelp,
            "登出把引导标志清掉了 —— 重新登录的老用户会被再引导一遍"
        )
    }

    // MARK: - Helpers

    private func topic(id: String, file: StaticString = #filePath, line: UInt = #line) -> BlindHelpTopic {
        guard let match = BlindFirstRunHelp.topics().first(where: { $0.id == id }) else {
            XCTFail("引导里没有 id 为 \(id) 的条目", file: file, line: line)
            return BlindHelpTopic(id: id, title: "", body: "")
        }
        return match
    }
}
