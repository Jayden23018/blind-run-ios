import XCTest
@testable import blindRun

/// 语音抽出的「额外需求」三个可选槽位：导盲犬、配速、本次备注。
///
/// 这三项此前**解出来就被丢掉了**（模型层 2026-08-04 就接了，向导一直没消费），
/// 而丢掉是完全静默的：`hasGuideDogThisRun` 进派单硬过滤，候选池被无声缩放，
/// 盲人从头到尾听不出来。所以断言集中在两件事上 ——
/// **抽到的必须能被听见**（进读回），**没抽到的必须仍然是「没提」**（不塌缩成 false）。
///
/// 对应 `openspec/changes/capture-and-gate-runner-extra-needs/tasks.md` 5.2–5.4。
@MainActor
final class RunnerExtraNeedsVoiceTests: XCTestCase {

    // MARK: 5.2 三态不许在下单请求里被压平

    func testGuideDogNotMentionedIsAbsentFromTheRequest() {
        let viewModel = makeBookingViewModel()
        viewModel.hasGuideDogThisRun = nil

        let request = viewModel.makeCreateOrderRequest()

        XCTAssertNotNil(request, "起点已给，请求应该能拼出来")
        XCTAssertNil(
            request?.hasGuideDogThisRun,
            "「没提导盲犬」必须原样不传：塌缩成 false 等于替用户声明「本次不带」，而这一项进派单硬过滤"
        )
    }

    func testGuideDogExplicitlyDeclinedIsSentAsFalseNotDropped() {
        let viewModel = makeBookingViewModel()
        viewModel.hasGuideDogThisRun = false

        let request = viewModel.makeCreateOrderRequest()

        XCTAssertEqual(
            request?.hasGuideDogThisRun,
            false,
            "「今天不带导盲犬」是用户明确说过的话，转成 nil 等于把它当没说过"
        )
    }

    func testGuideDogBroughtAlongIsSentAsTrue() {
        let viewModel = makeBookingViewModel()
        viewModel.hasGuideDogThisRun = true

        XCTAssertEqual(makeBookingViewModel().makeCreateOrderRequest()?.hasGuideDogThisRun, nil)
        XCTAssertEqual(viewModel.makeCreateOrderRequest()?.hasGuideDogThisRun, true)
    }

    // MARK: 5.4 读回必须念出抽到的项，且不念空态

    func testReadbackSpeaksEveryCapturedOptionalNeed() {
        let viewModel = makeBookingViewModel()
        viewModel.hasGuideDogThisRun = true
        viewModel.pacePreference = .easy
        viewModel.specialNotes = "我有低血糖，如果我说头晕请扶我坐下"

        let summary = viewModel.optionalNeedsSpeechSummary

        XCTAssertTrue(summary.contains("本次携带"), "抽到导盲犬却不念，用户无从发现抽错了：\(summary)")
        XCTAssertTrue(summary.contains(PacePreference.easy.displayName), "配速要念：\(summary)")
        XCTAssertTrue(
            summary.contains("我有低血糖，如果我说头晕请扶我坐下"),
            "备注必须**原文**念出来，不许摘要——摘要产生的是用户无法核对的错误（design.md D1）：\(summary)"
        )
    }

    func testReadbackSpeaksAnExplicitNoGuideDog() {
        let viewModel = makeBookingViewModel()
        viewModel.hasGuideDogThisRun = false

        XCTAssertTrue(
            viewModel.optionalNeedsSpeechSummary.contains("本次不带"),
            "`false` 也要念：用户说了「今天不带」却一个字听不到，与「我们没听懂」无从区分"
        )
    }

    func testReadbackDoesNotEnumerateEmptyOptionalNeeds() {
        let viewModel = makeBookingViewModel()

        let summary = viewModel.optionalNeedsSpeechSummary

        XCTAssertFalse(summary.contains("导盲犬"), "没抽到的项不念——读回本来就要 15~25 秒（design.md D5）：\(summary)")
        XCTAssertFalse(summary.contains("配速"), summary)
        XCTAssertFalse(summary.contains("特殊说明"), summary)
    }

    // MARK: 5.3 备注只能是原话的子串

    func testMockNotesAreAlwaysASubstringOfWhatTheUserSaid() {
        let transcripts = [
            "明天早上八点从人民广场出发跑四十分钟，我有低血糖，如果我说头晕请马上扶我坐到路边",
            "明天七点从五角场跑一小时，麻烦慢一点，我左腿去年做过手术",
            "后天九点从静安寺出发跑半小时，另外我不太能爬坡"
        ]

        for transcript in transcripts {
            guard let notes = MockAPIClient.mockVoiceSpecialNotes(in: transcript) else {
                XCTFail("这三句都带明确的额外需求，Mock 抽不到就等于这条分支在开发期不可达：\(transcript)")
                continue
            }
            XCTAssertTrue(
                transcript.contains(notes),
                "备注必须是原话的子串。Mock 自己编一句，「原文照录」这条规格在 Mock 下就是假的，"
                    + "而假的 Mock 比没有 Mock 更糟——它让人以为验过了。抽到的是：\(notes)"
            )
        }
    }

    func testRewrittenNotesAreDiscardedAndTheBookingStillProceeds() async {
        // spec `Parser returns rewritten text`：备注是原样展示给志愿者、并被当成盲人本人的话读的。
        // 模型编出来的「我行动不便」会直接误导对方，而盲人看不见屏幕、核对不了。
        let wizard = VoiceOrderWizard()
        let booking = makeBookingViewModel()
        wizard.configureForTesting(bookingViewModel: booking)

        wizard.applyForTesting(
            makeParseResponse(specialNotes: "该用户行动不便，需要全程搀扶"),
            spokenIn: "明天早上八点从人民广场出发跑四十分钟"
        )

        XCTAssertTrue(
            booking.specialNotes.isEmpty,
            "备注不是原话的子串就必须丢掉，落进去的是：\(booking.specialNotes)"
        )
        XCTAssertNotNil(booking.makeCreateOrderRequest(), "丢备注不该连累下单——spec 要求订单照常创建")
    }

    func testNotesInheritedFromAnEarlierRoundSurviveACorrectionRound() {
        // 跨轮修正时后端会把上一轮的备注从 `current` 继承回来，而这一轮的原话是「时间改成九点」。
        // 只比对本轮 transcript 会把一条用户真说过的备注当成伪造删掉。
        let wizard = VoiceOrderWizard()
        let booking = makeBookingViewModel()
        booking.specialNotes = "我有低血糖，如果我说头晕请扶我坐下"
        wizard.configureForTesting(bookingViewModel: booking)

        wizard.applyForTesting(
            makeParseResponse(specialNotes: "我有低血糖，如果我说头晕请扶我坐下"),
            spokenIn: "时间改成九点"
        )

        XCTAssertEqual(
            booking.specialNotes,
            "我有低血糖，如果我说头晕请扶我坐下",
            "上一轮说过的备注在定点修改轮必须留着——擦掉等于替用户撤回他说过的话"
        )
    }

    func testMockNotesAreNilWhenNothingExtraWasSaid() {
        XCTAssertNil(
            MockAPIClient.mockVoiceSpecialNotes(in: "明天早上八点从人民广场出发跑四十分钟"),
            "没说额外需求就该是 nil——编一条出来会直接误导志愿者"
        )
    }

    // MARK: 3.4 超字数线时必须先说一句，不能静默丢

    func testLongUtteranceIsAnnouncedBecauseTheBackendSilentlyDropsSlots() {
        let limit = ParseVoiceOrderRequest.modelFallbackCharacterLimit
        let longTranscript = String(repeating: "跑", count: limit + 1)

        let notice = VoiceOrderWizard.longUtteranceNotice(forCharacterCount: longTranscript.count)

        XCTAssertNotNil(notice, "超过 \(limit) 字后端跳过大模型，终点和备注一定抽不到，不说等于让用户以为自己没说过")
        XCTAssertTrue(notice?.contains("重说") == true, "必须给出路，否则用户只知道出了问题不知道怎么办：\(notice ?? "")")
    }

    func testNormalLengthUtteranceSaysNothingExtra() {
        // 契约注释里我们最长的回归语料是 22 字，正常语音下单远达不到这条线。
        XCTAssertNil(
            VoiceOrderWizard.longUtteranceNotice(forCharacterCount: 22),
            "正常长度多播一句是纯粹的噪音——读回已经 15~25 秒了"
        )
        XCTAssertNil(
            VoiceOrderWizard.longUtteranceNotice(
                forCharacterCount: ParseVoiceOrderRequest.modelFallbackCharacterLimit
            ),
            "边界值本身不触发：契约说的是「超过」这个长度才降级"
        )
    }

    func testMockDropsNotesOnceTheUtteranceCrossesTheModelFallbackLimit() {
        // Mock 必须复现后端的降级，否则开发期看到的是「说多长都有备注」，真机上却没有。
        let limit = ParseVoiceOrderRequest.modelFallbackCharacterLimit
        let padding = String(repeating: "跑", count: limit)
        let transcript = padding + "，我有低血糖"

        XCTAssertNil(
            MockAPIClient.mockVoiceSpecialNotes(in: transcript),
            "超线之后后端走纯正则，而备注只在大模型那次抽——Mock 照样给出备注就是在制造假信心"
        )
    }

    // MARK: Fixtures

    /// 只填备注这条路径要用到的字段，其余走 init 的默认 nil（= 原话没提）。
    private func makeParseResponse(specialNotes: String?) -> ParseVoiceOrderResponse {
        ParseVoiceOrderResponse(
            plannedStartTime: "2026-08-16T08:00:00",
            durationMinutes: 40,
            address: "上海市黄浦区人民广场",
            latitude: 31.2304,
            longitude: 121.4737,
            missing: [],
            needReask: false,
            ttsText: nil,
            specialNotes: specialNotes
        )
    }

    /// `BlindBookingViewModel` 的依赖是 `weak`，传临时对象等于传 nil，
    /// 所以这里只填拼请求真正需要的东西：起点。
    private func makeBookingViewModel() -> BlindBookingViewModel {
        let viewModel = BlindBookingViewModel()
        viewModel.applyVoiceResolvedStartPlace(
            address: "上海市黄浦区人民广场",
            spokenAddress: "人民广场",
            latitude: 31.2304,
            longitude: 121.4737
        )
        return viewModel
    }
}
