import XCTest
@testable import blindRun

/// 陪跑员二级页（固定搭档、服务成就、评分、徽章，#697）里会悄悄出错的取舍。
///
/// 这些错了屏幕上仍是一张排版正常的卡片 —— 平均值多算了一个月、徽章墙少了一枚、
/// 好评徽章写了别的徽章的进度 —— 所以写成纯函数，在这里钉住。
/// 每条用例的输入都挑在「对的实现」与「最可能写错的实现」会得出不同结果的地方。
@MainActor
final class VolunteerSecondaryPagesTests: XCTestCase {

    // MARK: - 近 6 个月

    func testRecentMonthsAreSixMonthsEndingWithTheCurrentOneOldestFirst() throws {
        let now = try date(2026, 11, 15)
        let months = VolunteerServiceTrend.recentMonths(endingAt: now, calendar: Self.calendar)
        XCTAssertEqual(months.map(\.month), [6, 7, 8, 9, 10, 11])
        XCTAssertEqual(Set(months.map(\.year)), [2026])
    }

    func testRecentMonthsCrossTheYearBoundary() throws {
        let months = VolunteerServiceTrend.recentMonths(endingAt: try date(2026, 2, 3), calendar: Self.calendar)
        XCTAssertEqual(months.map(\.month), [9, 10, 11, 12, 1, 2])
        XCTAssertEqual(months.map(\.year), [2025, 2025, 2025, 2025, 2026, 2026])
    }

    /// 前 5 个月 = [60, 没读到, 120, 没读到, 0]，本月 200。
    /// 对的平均是 (60 + 120 + 0) / 3 = 60；把没读到当 0 会得 36，把本月算进去会得 95。
    func testPreviousAverageSkipsUnreadMonthsAndExcludesTheCurrentMonth() {
        let months = Self.months([60, nil, 120, nil, 0, 200])
        XCTAssertEqual(VolunteerServiceTrend.previousAverage(months), 60)
    }

    func testSummarySentenceComparesTheCurrentMonthWithThePreviousAverage() {
        XCTAssertEqual(
            VolunteerServiceTrend.summarySentence(Self.months([60, nil, 120, nil, 0, 200])),
            "这个月的陪伴时长比前 5 个月平均多。"
        )
        XCTAssertEqual(
            VolunteerServiceTrend.summarySentence(Self.months([60, nil, 120, nil, 0, 30])),
            "这个月的陪伴时长比前 5 个月平均少。"
        )
    }

    /// 本月没读到时不下结论 —— 当 0 比较会说「比平均少」，那是编的。
    func testNoSummaryWhenTheCurrentMonthWasNotRead() {
        XCTAssertNil(VolunteerServiceTrend.summarySentence(Self.months([60, 60, 60, 60, 60, nil])))
    }

    func testChartIsHiddenOnlyWhenNoMonthWasRead() {
        XCTAssertFalse(VolunteerServiceTrend.hasAnyData(Self.months([nil, nil, nil, nil, nil, nil])))
        XCTAssertTrue(VolunteerServiceTrend.hasAnyData(Self.months([nil, nil, nil, nil, nil, 0])))
    }

    func testDurationPartsSplitNumberAndUnit() {
        XCTAssertEqual(VolunteerServiceTrend.durationParts(760).map(\.value), ["12", "40"])
        XCTAssertEqual(VolunteerServiceTrend.durationParts(760).map(\.unit), ["小时", "分钟"])
        XCTAssertEqual(VolunteerServiceTrend.durationParts(45).map(\.unit), ["分钟"])
    }

    /// 6 个请求里第 3 个失败：那个月记缺失，其余照常 —— 一个月失败不许连坐整张图。
    func testLoaderKeepsOtherMonthsWhenOneRequestFails() async throws {
        let service = MonthlyStub(failingMonth: 8, minutesByMonth: [6: 10, 7: 20, 9: 40, 10: 50, 11: 60])
        let loader = VolunteerServiceTrendLoader()
        await loader.load(service: service, now: try date(2026, 11, 15), calendar: Self.calendar)
        XCTAssertEqual(loader.months?.map(\.minutes), [10, 20, nil, 40, 50, 60])
    }

    // MARK: - 徽章墙

    func testBoardDrawsAllSevenWithEarnedNextAndLockedStates() {
        let board = VolunteerBadgeBoard.items(Self.achievements(
            badges: [VolunteerBadgeDto(code: "FIRST_RUN", name: "首次陪跑")],
            next: VolunteerNextBadgeDto(code: "RUNS_10", name: "陪跑达人 · 10 次", current: 7, target: 10)
        ))
        XCTAssertEqual(board.map(\.id), ["FIRST_RUN", "RUNS_10", "RUNS_50", "RUNS_100", "HOURS_10", "HOURS_50", "HIGH_RATED"])
        XCTAssertEqual(board[0].state, .earned)
        XCTAssertEqual(board[1].state.shortText, "7 / 10")
        XCTAssertEqual(board[1].spoken, "陪跑 10 次，未获得，已完成 7 次，共需 10 次")
        XCTAssertEqual(board[2].state, .locked)
        XCTAssertEqual(VolunteerBadgeBoard.countText(board), "已获得 1 枚 / 共 7 枚")
    }

    /// 后端加了新徽章、App 还没跟上：服务端说你拿到了，这一页就要有它（放「其他」），不许丢。
    func testUnknownEarnedBadgeIsKeptUnderOther() {
        let board = VolunteerBadgeBoard.items(Self.achievements(
            badges: [VolunteerBadgeDto(code: "STREAK_4", name: "连续陪跑 4 周")],
            next: nil
        ))
        XCTAssertEqual(board.count, 8)
        XCTAssertEqual(board.last?.name, "连续陪跑 4 周")
        XCTAssertEqual(board.last?.category, .other)
        XCTAssertEqual(board.last?.state, .earned)
        XCTAssertEqual(VolunteerBadgeBoard.sections(board).map(\.category), [.runs, .hours, .rating, .other])
    }

    /// 时长徽章的进度后端给的是**分钟**：420 / 600 分钟要写成 7 / 10 小时。
    func testHourBadgeProgressIsShownInHours() {
        let next = VolunteerNextBadgeDto(code: "HOURS_10", name: "累计服务 10 小时", current: 420, target: 600)
        XCTAssertEqual(VolunteerBadgeBoard.encouragementText(next), "7 / 10 小时 · 再陪伴 3 小时")
    }

    /// 好评是双条件：条数满了也可能拿不到，所以**不说「再 …」**，卡在评分时补一句。
    func testHighRatedEncouragementNeverPromisesTheBadge() {
        let next = VolunteerNextBadgeDto(code: "HIGH_RATED", name: "口碑之星", current: 10, target: 10, blockedBy: "RATING")
        let text = VolunteerBadgeBoard.encouragementText(next)
        XCTAssertEqual(text, "10 / 10 条评价 · 评分未达标")
        XCTAssertFalse(text?.contains("再") ?? true)
    }

    // MARK: - 评分页

    /// 好评徽章那一行只在 `nextBadge` 正好是 `HIGH_RATED` 时写进度。
    /// 下一枚是「陪跑 10 次」时写它的 7 / 10 就是把别的徽章的进度安在好评上。
    func testHighRatedStatusOnlyShowsProgressWhenTheNextBadgeIsHighRated() {
        let runsNext = Self.achievements(badges: [], next: VolunteerNextBadgeDto(code: "RUNS_10", name: nil, current: 7, target: 10))
        XCTAssertEqual(VolunteerSecondaryPagesCopy.highRatedStatus(runsNext), "未获得 · 评价条数和评分都达到要求后获得。")

        let ratedNext = Self.achievements(badges: [], next: VolunteerNextBadgeDto(code: "HIGH_RATED", name: nil, current: 7, target: 10))
        XCTAssertEqual(VolunteerSecondaryPagesCopy.highRatedStatus(ratedNext), "未获得 · 已有 7 / 10 条评价")
    }

    func testRatingLevelsFollowTheContract() {
        XCTAssertEqual(VolunteerRatingLevel(rating: 5).label, "很好")
        XCTAssertEqual(VolunteerRatingLevel(rating: 4).label, "一般")
        XCTAssertEqual(VolunteerRatingLevel(rating: nil).label, "无评分")
        // 旧五星评价对被评人可见：照实说分数，不硬归到「一般」。
        XCTAssertEqual(VolunteerRatingLevel(rating: 3).label, "3 分")
    }

    /// 跑者名客户端再掩码一次：全名进来也只上屏姓氏。
    func testRecentRowMasksTheRunnerNameAgain() {
        XCTAssertEqual(VolunteerSecondaryPagesCopy.recentRowDetail(blindName: "李明", address: "奥林匹克森林公园"), "和李* · 奥林匹克森林公园")
        XCTAssertEqual(VolunteerSecondaryPagesCopy.recentRowDetail(blindName: "李*", address: nil), "和李*")
    }

    // MARK: - 固定搭档

    func testStreakCellsDrawBestWeeksAndLightCurrentWeeks() throws {
        let streak = try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 3, bestWeeks: 7))
        let cells = PartnerStreakCells(streak)
        XCTAssertEqual(cells.total, 7)
        XCTAssertEqual(cells.lit, 3)
        XCTAssertEqual(PartnerStreakCopy.detailStreakProgress(streak), "最好 7 周 · 还差 4 周追平")
    }

    /// 退出了就只说退出：连续周数已经不再累积，再写「连续 3 周」是误导。
    func testOptedOutRowSaysOnlyThatYouLeft() throws {
        let row = PartnerRow(
            userId: 1, name: "陈*", completedRunsTogether: nil, favoritedAt: nil,
            hasOptedOut: true, streak: PartnerStreakDisplay(currentWeeks: 3, bestWeeks: 7), isFavorite: true
        )
        XCTAssertEqual(PartnerStreakCopy.volunteerRowDetail(row), "你已退出")
        XCTAssertEqual(PartnerStreakCopy.volunteerRowSpoken(row), "陈，你已退出")
    }

    // MARK: - 卡名色

    /// 卡名是字：每个色在白卡（亮）和 `#1C1C1E` 卡（暗）上都要 4.5:1。
    func testCardTitleColorsClearBodyContrastOnBothCardSurfaces() {
        for (name, tone) in VolunteerSecondaryTint.all {
            XCTAssertGreaterThanOrEqual(Self.contrast(tone.light, 0xFFFFFF), 4.5, "\(name) 亮色")
            XCTAssertGreaterThanOrEqual(Self.contrast(tone.dark, 0x1C1C1E), 4.5, "\(name) 暗色")
        }
        let bar = VolunteerSecondaryTint.durationTone
        let ink = VolunteerSecondaryTint.onDurationTone
        XCTAssertGreaterThanOrEqual(Self.contrast(bar.light, ink.light), 4.5, "横条里的字 亮色")
        XCTAssertGreaterThanOrEqual(Self.contrast(bar.dark, ink.dark), 4.5, "横条里的字 暗色")
    }

    /// 验红：天青暗色档如果直接用 `Flow.stateRunning`（两档同值）就不达标 —— 上面那条不是恒真。
    func testRunningTealIsNotReadableAsTextOnTheDarkCard() {
        XCTAssertLessThan(Self.contrast(AppColors.Flow.stateRunningTone.dark, 0x1C1C1E), 4.5)
    }

    // MARK: - 辅助

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private static func months(_ minutes: [Int64?]) -> [VolunteerServiceMonth] {
        minutes.enumerated().map { VolunteerServiceMonth(year: 2026, month: 6 + $0.offset, minutes: $0.element) }
    }

    private static func achievements(badges: [VolunteerBadgeDto], next: VolunteerNextBadgeDto?) -> VolunteerAchievementsResponse {
        VolunteerAchievementsResponse(
            totalCompleted: 7,
            totalServiceMinutes: 420,
            totalDistanceMeters: 36_400,
            avgRating: 4.9,
            totalRatings: 7,
            badges: badges,
            nextBadge: next,
            starLevel: nil
        )
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ rgb: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let raw = Double((rgb >> UInt32(shift)) & 0xFF) / 255
                return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// 只有月度列表的桩：指定的那个月抛错，其余按表返回 `serviceMin`。
private struct MonthlyStub: RunRecordServing {
    let failingMonth: Int
    let minutesByMonth: [Int: Int64]

    func record(orderId: Int64) async throws -> RunRecordResponse { throw URLError(.badURL) }

    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse {
        if month == failingMonth { throw URLError(.timedOut) }
        return RunRecordHistoryResponse(
            role: .volunteer,
            month: RunRecordService.monthQuery(year: year, month: month),
            monthSummary: RunMonthSummary(runs: 1, distanceM: nil, serviceMin: minutesByMonth[month], topPartner: nil),
            items: []
        )
    }

    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw URLError(.badURL) }
}
