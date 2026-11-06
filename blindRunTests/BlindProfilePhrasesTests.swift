import XCTest
@testable import blindRun

/// 个人资料核对清单（#812）：常用说法的拼接与回读（`BlindProfilePhraseSet`），
/// 以及「一张卡一次保存」（`BlindRunnerProfileViewModel.saveCard`）的回退。
@MainActor
final class BlindProfilePhrasesTests: XCTestCase {

    private let guide = BlindProfilePhraseSet.guideNote
    private let needs = BlindProfilePhraseSet.specialNeeds

    // MARK: - 拼接

    /// 单选在前、多选按列表顺序（不按勾选顺序）、补充说明最后，用「；」连接。
    func testComposePutsSingleFirstThenMultiInListOrderThenSupplement() {
        let answer = BlindProfilePhraseAnswer(
            single: "详略均可",
            multi: ["递物或肢体接触前先征询", "转弯前提前提示"],
            supplement: "  我习惯陪跑员在我左侧  "
        )
        XCTAssertEqual(
            guide.compose(answer),
            "详略均可；转弯前提前提示；递物或肢体接触前先征询；我习惯陪跑员在我左侧"
        )
    }

    func testComposeOfAnEmptyAnswerIsEmpty() {
        XCTAssertEqual(guide.compose(.empty), "")
    }

    // MARK: - 回读

    func testParseRoundTripsAComposedAnswer() {
        let answer = BlindProfilePhraseAnswer(
            single: "仅播报必要路况",
            multi: ["台阶、路沿提前提示", "说明陪跑员所在的一侧"],
            supplement: "跑前先热身"
        )
        XCTAssertEqual(guide.parse(guide.compose(answer)), answer)
    }

    /// 认不出的段按原顺序拼回补充说明 —— 老用户手写的字不能丢。
    /// **验红方式**：把 `leftovers.append(segment)` 删掉，这条必须失败。
    func testParseKeepsUnknownSegmentsInTheSupplementInTheirOriginalOrder() {
        let parsed = guide.parse("我习惯你在我左边；转弯前提前提示；跑慢一点")
        XCTAssertEqual(parsed.multi, ["转弯前提前提示"])
        XCTAssertNil(parsed.single)
        XCTAssertEqual(parsed.supplement, "我习惯你在我左边；跑慢一点")
    }

    /// #812 之前的自由文本没有「；」：整句原样进补充说明，一个说法都不勾（「转弯前提前说」不是现在的说法）。
    func testLegacyFreeTextWithoutSeparatorsStaysWholeInTheSupplement() {
        let legacy = "我习惯你在我左边，转弯前提前说一声"
        let parsed = guide.parse(legacy)
        XCTAssertEqual(parsed, BlindProfilePhraseAnswer(single: nil, multi: [], supplement: legacy))
        XCTAssertEqual(guide.compose(parsed), legacy, "回读后原样存回，文字不变")
    }

    func testEmptyTextParsesToAnEmptyAnswer() {
        XCTAssertEqual(guide.parse(""), .empty)
        XCTAssertEqual(needs.parse("  ；  "), .empty)
    }

    /// 同一句单选说法出现两次：只认第一次，第二次进补充说明（不丢字）。
    func testRepeatedSingleOptionOnlyCountsOnce() {
        let parsed = guide.parse("详略均可；仅播报必要路况")
        XCTAssertEqual(parsed.single, "详略均可")
        XCTAssertEqual(parsed.supplement, "仅播报必要路况")
    }

    // MARK: - 互斥项「无其他需求」

    func testNoOtherNeedsClearsTheOtherChoicesAndIsClearedByThem() {
        let picked = needs.toggling("途中需要休息", in: ["定时提醒补水"])
        XCTAssertEqual(picked, ["途中需要休息", "定时提醒补水"])

        let none = needs.toggling(BlindProfilePhraseSet.noOtherNeeds, in: picked)
        XCTAssertEqual(none, [BlindProfilePhraseSet.noOtherNeeds], "选「无其他需求」要清掉别的")

        let again = needs.toggling("定时提醒补水", in: none)
        XCTAssertEqual(again, ["定时提醒补水"], "选别的要清掉「无其他需求」")

        XCTAssertEqual(needs.toggling("定时提醒补水", in: again), [], "再点一次取消勾选")
    }

    /// 存量文字里「无其他需求」和具体需求并存：具体需求打勾，「无其他需求」进补充说明（不丢字、不自相矛盾）。
    func testParseDoesNotTickNoOtherNeedsTogetherWithRealNeeds() {
        let parsed = needs.parse("途中需要休息；无其他需求")
        XCTAssertEqual(parsed.multi, ["途中需要休息"])
        XCTAssertEqual(parsed.supplement, "无其他需求")
    }

    /// 「其他需求」至少选一项，「途中提示」一项不选也能继续，单选没选不能继续。
    func testAdvanceRules() {
        var draft = BlindProfileCardDraft()
        XCTAssertFalse(draft.canAdvance(from: .otherNeeds))
        XCTAssertTrue(draft.canAdvance(from: .guideCues))
        XCTAssertFalse(draft.canAdvance(from: .guideDetail))
        XCTAssertFalse(draft.canAdvance(from: .tether))

        draft = draft.toggling(BlindProfilePhraseSet.noOtherNeeds, for: .otherNeeds)
            .choosing("详略均可", for: .guideDetail)
            .choosing(BlindProfileOption.tetherUndecidedID, for: .tether)
        XCTAssertTrue(draft.canAdvance(from: .otherNeeds))
        XCTAssertTrue(draft.canAdvance(from: .guideDetail))
        XCTAssertTrue(draft.canAdvance(from: .tether), "「暂不确定」也是一个答案")
    }

    // MARK: - 字数

    /// 边界取在 80 / 81：上限写成 79 或 81 时两条断言必有一条失败。
    func testLengthErrorAppearsOnlyAboveTheLimit() {
        // 「详略均可」4 + 「；」1 + 补充 75 = 80。
        let atLimit = BlindProfilePhraseAnswer(single: "详略均可", multi: [], supplement: String(repeating: "字", count: 75))
        XCTAssertEqual(guide.length(of: guide.compose(atLimit)), 80)
        XCTAssertNil(guide.lengthError(for: atLimit))
        XCTAssertEqual(guide.remainingText(for: atLimit), "含已选内容，剩余 0 字。")

        var over = atLimit
        over.supplement += "字"
        XCTAssertEqual(guide.lengthError(for: over), "内容超出 1 字，最多 80 字。请减少选项或缩短补充说明。")
        XCTAssertEqual(guide.remainingText(for: over), "含已选内容，已超出 1 字。")
    }

    func testSpecialNeedsLimitIsTheContractLimit() {
        XCTAssertEqual(needs.limit, 500)
        XCTAssertEqual(guide.limit, BlindProfileUpdateRequest.guidePreferenceMaxLength)
    }

    // MARK: - 一张卡一次保存

    private func makeViewModel(client: ProfileSaveSpy, profile: BlindProfileResponse) -> (AppState, BlindRunnerProfileViewModel) {
        let appState = AppState(apiClient: client, persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(profile)
        let viewModel = BlindRunnerProfileViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        return (appState, viewModel)
    }

    /// 「途中提示」存上：请求里是拼好的文字；`specialNeeds` 原样带回（契约：不带键 = 清空）。
    func testSavingTheGuideNoteCardSendsTheComposedTextAndKeepsSpecialNeeds() async {
        let client = ProfileSaveSpy()
        client.result = .success(BlindProfileResponse(name: "测试", specialNeeds: "途中需要休息", guidePreferenceText: "详略均可"))
        let (appState, viewModel) = makeViewModel(
            client: client,
            profile: BlindProfileResponse(name: "测试", specialNeeds: "途中需要休息")
        )
        let draft = BlindProfileCardDraft().choosing("详略均可", for: .guideDetail)

        let saved = await viewModel.saveCard(savedLabel: draft.savedLabel(for: .guideNote)) {
            draft.apply(to: .guideNote, viewModel: $0)
        }

        XCTAssertTrue(saved)
        XCTAssertEqual(client.lastUpdate?.guidePreferenceText, "详略均可")
        XCTAssertEqual(client.lastUpdate?.specialNeeds, "途中需要休息", "另一张卡的文字被清掉了")
        XCTAssertEqual(viewModel.savedNotice, "已保存：途中提示")
        withExtendedLifetime(appState) {}
    }

    /// 没存上：这张卡改到的字段全部回到打开前，错误说清「已选内容已保留」。
    /// **验红方式**：把 `saveCard` 里的 `snapshot.restore(to: self)` 换成空闭包，这条必须失败。
    func testSaveCardRestoresEveryFieldWhenTheSaveFails() async {
        let client = ProfileSaveSpy()
        client.result = .failure(APIError.networkError(URLError(.notConnectedToInternet)))
        let (appState, viewModel) = makeViewModel(
            client: client,
            profile: BlindProfileResponse(name: "测试", tetherPreference: "TETHER_ROPE", defaultPace: .easy)
        )
        var draft = BlindProfileCardDraft()
        draft = draft.choosing(TetherPreference.armHold.rawValue, for: .tether)
            .choosing(PacePreference.fast.rawValue, for: .pace)

        let saved = await viewModel.saveCard(savedLabel: draft.savedLabel(for: .escort)) {
            draft.apply(to: .escort, viewModel: $0)
        }

        XCTAssertFalse(saved)
        XCTAssertEqual(client.lastUpdate?.tetherPreference, "ARM_HOLD", "前提：请求带的是新值，是服务端没存上")
        XCTAssertEqual(viewModel.tetherPreference, .tetherRope)
        XCTAssertEqual(viewModel.defaultPace, .easy)
        XCTAssertNil(viewModel.savedNotice)
        let error = viewModel.errorMessage ?? ""
        XCTAssertTrue(error.hasPrefix("保存失败："), error)
        XCTAssertTrue(error.hasSuffix("已选内容已保留，请再次点按「完成」。"), error)
        XCTAssertFalse(error.contains("。。"), error)
        withExtendedLifetime(appState) {}
    }

    /// 「暂不确定」写回成没有引导方式（`nil`），档案原来有值时请求发 `NOT_SPECIFIED` 才撤得回。
    func testUndecidedTetherIsAppliedAsNoPreferenceAndSentAsNotSpecified() {
        let client = ProfileSaveSpy()
        let (appState, viewModel) = makeViewModel(
            client: client,
            profile: BlindProfileResponse(name: "测试", tetherPreference: "TETHER_ROPE")
        )
        let draft = BlindProfileCardDraft()
            .choosing(BlindProfileOption.tetherUndecidedID, for: .tether)
            .choosing(PacePreference.noPreference.rawValue, for: .pace)

        draft.apply(to: .escort, viewModel: viewModel)

        XCTAssertNil(viewModel.tetherPreference)
        XCTAssertEqual(viewModel.makeProfileUpdateRequest().tetherPreference, TetherPreference.notSpecifiedRawValue)
        XCTAssertEqual(draft.savedLabel(for: .escort), "暂不确定 · 无偏好")
        withExtendedLifetime(appState) {}
    }

    /// 打开「途中提示」时从已存文字回读：认得的说法预选，其余进补充说明。
    func testGuideNoteCardOpensWithTheStoredAnswer() {
        let client = ProfileSaveSpy()
        let (appState, viewModel) = makeViewModel(
            client: client,
            profile: BlindProfileResponse(name: "测试", guidePreferenceText: "详略均可；转弯前提前提示；我习惯你在我左边")
        )

        let draft = BlindProfileCardDraft.initial(for: .guideNote, viewModel: viewModel, isSet: true)

        XCTAssertEqual(draft.selection(for: .guideDetail), "详略均可")
        XCTAssertEqual(draft.selectedSet(for: .guideCues), ["转弯前提前提示"])
        XCTAssertEqual(draft.phraseAnswer(for: .guideSupplement)?.supplement, "我习惯你在我左边")
        withExtendedLifetime(appState) {}
    }
}
