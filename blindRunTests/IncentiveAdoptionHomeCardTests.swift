import XCTest
@testable import blindRun

/// SPEC-E 志愿者首页「我的贡献」卡：主数字的取舍、文案红线、一次性加载与跑完一单后的补拉。
///
/// 从 `IncentiveAdoptionTests` 按主题拆出（#508），用例与断言原样搬过来。
final class IncentiveAdoptionHomeCardTests: XCTestCase {

    // MARK: - 首页「我的贡献」卡

    /// 有人收藏我时，主数字是**人数**而不是勋章进度。
    ///
    /// 顺序本身就是产品决策（被别人选中 > 平台进度条），断言挑的是
    /// 「两样都有」这个取值 —— 只有把优先级排反才会红。
    func testHomeIncentiveLeadsWithRelationshipWhenSomebodyFavoritedMe() {
        let summary = VolunteerHomeIncentiveSummary(
            favoritedByCount: 3,
            nextBadge: makeNextBadge(code: "RUNS_10", current: 7, target: 10),
            streak: nil,
            streakPartnerName: nil
        )
        XCTAssertEqual(summary.hero, .partners(count: 3))
        // 主角已经不是勋章了，勋章仍要单独画一行 —— 否则「下一步差多少」整个丢掉。
        XCTAssertTrue(summary.showsBadgeRow)
    }

    /// 🔴 **0 位搭档时绝不能显示「0 位跑者把你设为固定搭档」。**
    ///
    /// 新人第一天打开 App，第一个看到的数字是 0，那是负激励。这一档让位给勋章进度
    /// （他的第一枚是「首次陪跑」，天然就是「下一步差多少」）。
    ///
    /// 断言挑的取值能区分三种破法：
    /// - 「恒取人数」的实现 → 第一条红（会拿到 `.partners(count: 0)`）
    /// - 「勋章当主角后又重复画一行」的实现 → 最后一条红
    /// - 单位换算写错（`HOURS_*` 的 `current`/`target` 是**分钟**，要除 60）→ 第二条红
    func testHomeIncentiveNeverShowsZeroPartnersAndConvertsBadgeMinutesToHours() throws {
        let newcomer = VolunteerHomeIncentiveSummary(
            favoritedByCount: 0,
            nextBadge: makeNextBadge(code: "HOURS_10", current: 420, target: 600),
            streak: nil,
            streakPartnerName: nil
        )
        XCTAssertNotEqual(newcomer.hero, .partners(count: 0))
        XCTAssertEqual(
            newcomer.hero,
            .badgeProgress(current: 7, target: 10, suffix: "小时", badgeName: "服务 10 小时")
        )
        // 已经当了主角就不再重复画 —— 同一个数出现两次，读屏用户会听两遍。
        XCTAssertFalse(newcomer.showsBadgeRow)
    }

    /// 两样都没有（七枚全解锁 + 还没人收藏）时**整张卡不渲染**，不留一个写着 0 的空壳。
    ///
    /// 同时钉住：未知 `code` 的勋章拿不到量词，契约要求整块进度隐藏 ——
    /// 那就更不能拿它当主角（拼一个猜的量词是这里最容易犯的错）。
    func testHomeIncentiveCardDisappearsInsteadOfRenderingAnEmptyShell() {
        let veteran = VolunteerHomeIncentiveSummary(
            favoritedByCount: 0, nextBadge: nil, streak: nil, streakPartnerName: nil
        )
        XCTAssertNil(veteran.hero)
        XCTAssertFalse(veteran.isRenderable)

        let unknownBadge = VolunteerHomeIncentiveSummary(
            favoritedByCount: 0,
            nextBadge: makeNextBadge(code: "MARATHON_2030", current: 1, target: 5),
            streak: nil,
            streakPartnerName: nil
        )
        XCTAssertNil(unknownBadge.hero)
        XCTAssertFalse(unknownBadge.isRenderable)
    }

    /// 🔴 首页激励文案**只陈述、不催促**。
    ///
    /// 依据是 Motivation Crowding Theory（外在激励被感知为 controlling 时挤出内在动机），
    /// 而我们的志愿者是无偿的、纯内在动机人群。详见
    /// `docs/research/volunteer-home-incentive-layer-20260914.md` §3。
    ///
    /// 一并钉住 `HIGH_RATED` 那条：它是「均分 ≥ 4.8 **且** ≥ 10 条评价」的双条件，
    /// 进度条满格也可能没解锁 ⇒ 一律不许写「还差 N 就解锁」。
    func testHomeIncentiveCopyStatesProgressWithoutNaggingOrPromisingUnlock() throws {
        let summary = VolunteerHomeIncentiveSummary(
            favoritedByCount: 2,
            nextBadge: makeNextBadge(code: "HIGH_RATED", current: 9, target: 10),
            streak: try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 7, bestWeeks: 9)),
            streakPartnerName: "张*"
        )
        let spoken = VolunteerHomeIncentiveCopy.accessibilityLabel(summary)

        XCTAssertTrue(spoken.contains("有 2 位跑者把你设为固定搭档"))
        XCTAssertTrue(spoken.contains("张*，已经连续 7 周一起跑步"))
        XCTAssertTrue(spoken.contains("已完成 9 / 10 条评价"))

        // ⚠️ **不能拿「还差」当禁词**：火花那句「距离你们最好的 9 周还差 2 周」比的是
        // 他们**自己的**历史最好成绩，是 supportive 那一侧（SDT 的胜任感），既有实现是对的。
        // 要拦的是「平台设的门槛 + 催你去够」这种 controlling 句式。
        XCTAssertTrue(spoken.contains("还差 2 周"), "前提：自比历史最好成绩的说法保留着")

        for nagging in ["就解锁", "就能解锁", "再跑", "赶快", "立即", "马上", "快去"] {
            XCTAssertFalse(spoken.contains(nagging), "首页激励文案不许催促：命中「\(nagging)」")
        }
    }

    /// 🔴 这张卡**不许出现积分**。
    ///
    /// `HOURS_10` / `HOURS_50` 两个勋章展示的是**服务时长**，所以这张卡有时会显示时长；
    /// 积分与志愿服务时长「刻意分两屏」（中央网信办 2026-06-19 通知第 2 条）。
    /// 把积分加进来就会**随数据**与时长同屏相邻 —— 时有时无，手测很可能撞不上，
    /// 所以这条必须由用例守着。
    func testHomeIncentiveNeverPutsPointsNextToServiceHours() {
        let hoursBadge = VolunteerHomeIncentiveSummary(
            favoritedByCount: 1,
            nextBadge: makeNextBadge(code: "HOURS_50", current: 1_200, target: 3_000),
            streak: nil,
            streakPartnerName: nil
        )
        let spoken = VolunteerHomeIncentiveCopy.accessibilityLabel(hoursBadge)
        XCTAssertTrue(spoken.contains("小时"), "前提：这张卡确实会念出服务时长")
        XCTAssertFalse(spoken.contains("积分"))
        XCTAssertFalse(spoken.contains(" 分"))

        let allCopy = [
            VolunteerHomeIncentiveCopy.sectionTitle,
            VolunteerHomeIncentiveCopy.partnersCaption,
            VolunteerHomeIncentiveCopy.achievementsLinkTitle,
            VolunteerHomeIncentiveCopy.achievementsLinkHint,
            VolunteerHomeIncentiveCopy.nextBadgePrefix
        ].joined(separator: "\n")
        XCTAssertFalse(allCopy.contains("积分"))
    }

    /// 🔴 **只有火花回来了也要渲染。**
    ///
    /// 「有火花但没被收藏」是契约里明确存在的一档（火花由订单结算、与收藏无关，
    /// 见 `PartnerRowMerge` 顶部），叠上「勋章全解锁 / 成就那条请求失败」中任意一种，
    /// 就是 `hero == nil` 而 `streak != nil`。`isRenderable` 只看 `hero` 的话，
    /// 一条**已经成功取回**的关系数据会被整张卡一起静默丢掉 —— 没有任何运行时信号。
    func testHomeIncentiveStillRendersWhenOnlyTheStreakCameBack() throws {
        let onlyStreak = VolunteerHomeIncentiveSummary(
            favoritedByCount: 0,
            nextBadge: nil,
            streak: try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 7, bestWeeks: 9)),
            streakPartnerName: "张*"
        )
        XCTAssertNil(onlyStreak.hero, "前提：这一档确实没有主数字")
        XCTAssertTrue(onlyStreak.isRenderable, "火花已经拿到手了，不能因为没有主数字就整张卡丢掉")
        XCTAssertTrue(
            VolunteerHomeIncentiveCopy.accessibilityLabel(onlyStreak).contains("连续 7 周"),
            "渲染了却不念出来等于没渲染"
        )
    }

    /// 后端没发 `name` 时整行不画。
    ///
    /// `displayName` 会退到 `code`（一串英文枚举，本仓库在积分流水上已定过「不显示原始枚举值」
    /// 的口径）或「下一枚勋章」（与栏目标题撞车，念出来是「下一枚勋章，下一枚勋章」）。
    func testBadgeRowIsHiddenWhenTheBackendSentNoHumanReadableName() {
        for nameless in [
            VolunteerNextBadgeDto(code: nil, name: nil, current: 1, target: 5),
            VolunteerNextBadgeDto(code: "MARATHON_2030", name: nil, current: 1, target: 5),
            VolunteerNextBadgeDto(code: "RUNS_10", name: "   ", current: 1, target: 5)
        ] {
            let summary = VolunteerHomeIncentiveSummary(
                favoritedByCount: 2, nextBadge: nameless, streak: nil, streakPartnerName: nil
            )
            XCTAssertFalse(summary.showsBadgeRow, "code=\(nameless.code ?? "nil")")
            let spoken = VolunteerHomeIncentiveCopy.accessibilityLabel(summary)
            XCTAssertFalse(spoken.contains("下一枚勋章，下一枚勋章"))
            XCTAssertFalse(spoken.contains("MARATHON_2030"), "原始英文枚举值不许上屏，也不许念")
        }
    }

    // MARK: - 首页「我的贡献」卡的一次性加载

    /// 🔴 **「这一轮算加载过了」的判据必须是「该跑的全成了」。**
    ///
    /// 写成「成了任意一条」会造出一条**这张卡整个会话消失且永不重试**的路径，
    /// 而且它很常见：新人的收藏列表成功返回空数组，紧接着成就那条失败 ——
    /// 「成功过一条」成立 ⇒ 置位 ⇒ `loadIfNeeded` 此后一直拦住重试，
    /// 而此刻三样都空、`isRenderable` 为 false。用户看到的是「这功能没有」。
    ///
    /// 断言打在「第二次调用有没有再发请求」上，不打在私有的 `hasLoaded` 上。
    @MainActor
    func testHomeIncentiveRetriesNextTimeWhenAnythingFailed() async {
        let service = FakeIncentiveService()
        // 新人常态：收藏列表成功，但是空的。
        service.volunteerFavoritedByResult = .success([])
        service.volunteerAchievementsResult = .failure(APIError.serverError(
            ErrorResponse(code: "INTERNAL_ERROR", message: "服务暂时不可用")
        ))
        service.volunteerPartnerStreaksResult = .success([])
        let appState = AppState(incentive: service)
        let viewModel = VolunteerHomeIncentiveViewModel()
        viewModel.configure(appState: appState)

        await viewModel.loadIfNeeded()
        let afterFirstRound = service.calls.count
        XCTAssertGreaterThan(afterFirstRound, 0, "第一轮就没发请求的话后面两条断言都不成立")

        await viewModel.loadIfNeeded()
        XCTAssertGreaterThan(
            service.calls.count, afterFirstRound,
            "有请求失败过，下次进首页必须重试 —— 否则这张卡整个会话都不会出现，且用户没有任何补救途径"
        )
    }

    /// 反过来：全成了就别再打。
    ///
    /// 与上一条成对，两条一起才能区分「恒重试」「恒不重试」「按成败决定」三种实现。
    /// 恒重试不是小事：`GET /api/volunteer/achievements` 要扫该志愿者的全部已完成订单，
    /// 后端刻意把它与 `dispatch-summary` 分开，就是为了不让它跟着首页那条 5 秒轮询跑。
    @MainActor
    func testHomeIncentiveDoesNotRefetchOnceEverythingSucceeded() async throws {
        let service = FakeIncentiveService()
        service.volunteerFavoritedByResult = .success([])
        service.volunteerAchievementsResult = .success(
            try JSONDecoder().decode(
                VolunteerAchievementsResponse.self,
                from: Data(#"{"totalCompleted":3,"badges":[]}"#.utf8)
            )
        )
        service.volunteerPartnerStreaksResult = .success([])
        let appState = AppState(incentive: service)
        let viewModel = VolunteerHomeIncentiveViewModel()
        viewModel.configure(appState: appState)

        await viewModel.loadIfNeeded()
        let afterFirstRound = service.calls.count
        XCTAssertGreaterThan(afterFirstRound, 0)

        await viewModel.loadIfNeeded()
        XCTAssertEqual(service.calls.count, afterFirstRound, "全都成功了就不该再打一轮")
    }

    // MARK: - 跑完一单后补拉（#335，安卓 #170 同源）

    @MainActor
    private func refreshKey(completed: Int, ratings: Int) throws -> VolunteerHomeIncentiveViewModel.RefreshKey? {
        VolunteerHomeIncentiveViewModel.RefreshKey(try JSONDecoder().decode(
            VolunteerDispatchSummaryResponse.self,
            from: Data(#"{"totalCompleted":\#(completed),"totalRatings":\#(ratings)}"#.utf8)
        ))
    }

    /// 摘要版本不变（5 秒轮询的常态）不打；跑完一单（`totalCompleted` 变了）补拉一轮。
    /// 旧实现每会话只加载一次，最后一条断言红：跑完一单影响力区还是「还没有完成的陪跑」。
    @MainActor
    func testHomeIncentiveRefetchesOnceWhenACompletedRunBumpsTheSummary() async throws {
        let service = FakeIncentiveService()
        service.volunteerFavoritedByResult = .success([])
        service.volunteerAchievementsResult = .success(
            try JSONDecoder().decode(VolunteerAchievementsResponse.self, from: Data(#"{"totalCompleted":0,"badges":[]}"#.utf8))
        )
        service.volunteerPartnerStreaksResult = .success([])
        let appState = AppState(incentive: service)
        let viewModel = VolunteerHomeIncentiveViewModel()
        viewModel.configure(appState: appState)

        // 摘要还没到：不记版本。否则它第一次到达会被当成「变了」，冷启动白拉一遍。
        await viewModel.summaryVersionChanged(nil)
        await viewModel.loadIfNeeded()
        let afterFirstRound = service.calls.count
        XCTAssertGreaterThan(afterFirstRound, 0)

        await viewModel.summaryVersionChanged(try refreshKey(completed: 0, ratings: 0))
        XCTAssertEqual(service.calls.count, afterFirstRound, "第一个版本只记下，首次加载已经做过了")
        await viewModel.summaryVersionChanged(try refreshKey(completed: 0, ratings: 0))
        XCTAssertEqual(service.calls.count, afterFirstRound, "版本没变（轮询常态）不许打 achievements")

        await viewModel.summaryVersionChanged(try refreshKey(completed: 1, ratings: 0))
        XCTAssertEqual(service.calls.count, afterFirstRound * 2, "跑完一单后没有补拉，影响力区停在旧数")

        await viewModel.summaryVersionChanged(try refreshKey(completed: 1, ratings: 1))
        XCTAssertEqual(service.calls.count, afterFirstRound * 3, "收到一条评价后没有补拉")
    }

    /// 火花开关拿不到（`nil`）时**照常发请求**。
    ///
    /// 落到 false 就是替后端断言「功能没开」—— `FeatureFlagsResponse` 顶部点名不许做。
    /// 这里 `AppState` 没有 token，`loadFeatureFlagsIfNeeded()` 直接返回，`featureFlags` 保持 nil。
    @MainActor
    func testStreakRequestStillGoesOutWhenTheFeatureFlagIsUnknown() async {
        let service = FakeIncentiveService()
        service.volunteerFavoritedByResult = .success([])
        service.volunteerAchievementsResult = .failure(APIError.serverError(
            ErrorResponse(code: "INTERNAL_ERROR", message: "服务暂时不可用")
        ))
        service.volunteerPartnerStreaksResult = .success([])
        let appState = AppState(incentive: service)
        XCTAssertNil(appState.featureFlags, "前提：开关确实是「不知道」而不是 false")
        let viewModel = VolunteerHomeIncentiveViewModel()
        viewModel.configure(appState: appState)

        await viewModel.loadIfNeeded()

        XCTAssertTrue(
            service.calls.contains { $0.contains("volunteerPartnerStreaks") },
            "开关是 nil 不是 false，不许替后端断言「功能没开」"
        )
    }

    // MARK: - Helpers

    private func makeNextBadge(
        code: String,
        current: Int64,
        target: Int64
    ) -> VolunteerNextBadgeDto {
        VolunteerNextBadgeDto(
            code: code,
            name: Self.badgeNames[code],
            current: current,
            target: target
        )
    }

    /// 后端下发的 `name`。未知 `code` 刻意给 `nil`，好让用例覆盖「拿不到量词」那一档。
    private static let badgeNames: [String: String] = [
        "RUNS_10": "陪跑 10 次",
        "HOURS_10": "服务 10 小时",
        "HOURS_50": "服务 50 小时",
        "HIGH_RATED": "好评如潮"
    ]
}
