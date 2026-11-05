import XCTest
@testable import blindRun

/// 陪跑员「连续陪跑」跑步数据页的数字（#710）。这些数算错时屏幕上仍是一张排版正常的图，
/// 所以每条都挑「对的实现与错的实现会得出不同结果」的输入（写在每条的注释里）。
final class VolunteerRunDataSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func run(_ id: Int64, _ at: Date, metres: Int?, partner: String? = "李*") -> VolunteerRunDataRun {
        VolunteerRunDataRun(orderId: id, finishedAt: at, metres: metres, partnerName: partner)
    }

    private func summary(_ runs: [VolunteerRunDataRun], now: Date, loaded: [RunRecordMonth: Int64] = [:]) -> VolunteerRunDataSummary {
        VolunteerRunDataSummary(runs: runs, serviceMinutes: loaded, now: now, calendar: calendar)
    }

    // MARK: - ISO 周

    /// 2025-12-29（周一）属于 **2026-W01**。错的实现（拿日历年拼周号）会得出 2025-W01。
    func testWeekKeyPutsLateDecemberIntoNextYearsFirstWeek() {
        XCTAssertEqual(ISOWeekKey(containing: date(2025, 12, 29), calendar: calendar), ISOWeekKey(year: 2026, week: 1))
        XCTAssertEqual(ISOWeekKey(containing: date(2021, 1, 3), calendar: calendar), ISOWeekKey(year: 2020, week: 53))
    }

    func testWeekKeyParsesOnlyTheIsoWeekShape() {
        XCTAssertEqual(ISOWeekKey("2026-W45"), ISOWeekKey(year: 2026, week: 45))
        XCTAssertEqual(ISOWeekKey("2026-W5"), ISOWeekKey(year: 2026, week: 5))
        XCTAssertNil(ISOWeekKey("2026-11-05"), "日期串不是周号，不许猜")
        XCTAssertNil(ISOWeekKey("2026-W54"))
        XCTAssertNil(ISOWeekKey(""))
    }

    /// 「本周记上没有」跨年那一周：今天 2025-12-30，后端记的是 `2026-W01` ⇒ 记上了；`2025-W52` ⇒ 没记上。
    /// 把 `lastCreditedWeek` 当日期解析、或拿日历年比的实现，在这一周会说反。
    func testThisWeekCreditComparesIsoWeeksAcrossTheYearBoundary() {
        let display = PartnerStreakDisplay(currentWeeks: 3, bestWeeks: 7)!
        let now = date(2025, 12, 30)
        let credited = VolunteerRunDataStreak(display: display, partnerName: "李*", lastCreditedWeek: "2026-W01")
        let lastWeek = VolunteerRunDataStreak(display: display, partnerName: "李*", lastCreditedWeek: "2025-W52")
        let missing = VolunteerRunDataStreak(display: display, partnerName: "李*", lastCreditedWeek: nil)
        XCTAssertEqual(credited.isCreditedThisWeek(now: now, calendar: calendar), true)
        XCTAssertEqual(lastWeek.isCreditedThisWeek(now: now, calendar: calendar), false)
        XCTAssertNil(missing.isCreditedThisWeek(now: now, calendar: calendar), "没有周号时不说这一句，不默认「没记上」")
    }

    // MARK: - 连续周

    /// 2020 年有 W53：12-28（W53）→ 2021-01-04（W01）是相邻两周。按「周序号 + 1」判相邻的实现会在这里断开。
    func testLongestStreakCountsAcrossAYearWithWeek53() {
        let runs = [
            run(1, date(2020, 12, 21), metres: 3_000),
            run(2, date(2020, 12, 28), metres: 3_000),
            run(3, date(2021, 1, 4), metres: 3_000),
            run(4, date(2021, 1, 11), metres: 3_000)
        ]
        XCTAssertEqual(summary(runs, now: date(2021, 1, 12)).records.longestWeeks, 4)
    }

    /// 空一周就断。第 3 周空着：1–2 周、4–6 周 ⇒ 最长 3。把「有记录的周数」当连续的实现会得 5。
    func testAnEmptyWeekBreaksTheStreak() {
        let mondays = [date(2026, 9, 7), date(2026, 9, 14), date(2026, 9, 28), date(2026, 10, 5), date(2026, 10, 12)]
        let runs = mondays.enumerated().map { run(Int64($0.offset), $0.element, metres: 4_000) }
        let result = summary(runs, now: date(2026, 10, 14))
        XCTAssertEqual(result.records.longestWeeks, 3)
        XCTAssertEqual(result.longestWeeksInWindow, 3)
    }

    /// 「最长连续」与任何搭档都算：同一周换了人照样连上。只按某一位搭档算的实现会得 1。
    func testLongestStreakCountsAnyPartner() {
        let runs = [
            run(1, date(2026, 10, 19), metres: 3_000, partner: "李*"),
            run(2, date(2026, 10, 26), metres: 3_000, partner: "王*"),
            run(3, date(2026, 11, 2), metres: 3_000, partner: nil)
        ]
        XCTAssertEqual(summary(runs, now: date(2026, 11, 3)).records.longestWeeks, 3)
    }

    // MARK: - distanceM 为 null

    /// 公里未知的那一单：那天算陪跑过（日历上有色、陪跑天数 +1），但不参评「最远一次」、不当 0 公里进图。
    func testUnknownDistanceCountsAsARunDayButNotAsZeroKilometres() {
        let now = date(2026, 11, 5)
        let runs = [
            run(1, date(2026, 11, 3), metres: nil),
            run(2, date(2026, 11, 4), metres: 2_500)
        ]
        let result = summary(runs, now: now)
        XCTAssertEqual(result.daysRunInWindow, 2)
        let thisWeek = result.calendarWeeks.last!.days
        XCTAssertEqual(thisWeek[1], .ran(level: 1), "11-03（周二）跑了，公里未知 ⇒ 最浅一档，不是空格")
        XCTAssertEqual(thisWeek[2], .ran(level: 1))
        XCTAssertEqual(result.longestRun?.orderId, 2, "公里未知的那单不能被选成最远一次")
        XCTAssertEqual(result.mileage[.week]?.headlineKm ?? -1, 2.5, accuracy: 0.001)
        XCTAssertEqual(result.thisWeek.filter(\.ran).count, 2)
    }

    // MARK: - 当前周未结束

    /// 周一一早还没跑：本周不进分母。前 25 周每周 2 公里 ⇒ 平均 2.0；除以 26 的实现得 1.92。
    func testAnUnfinishedEmptyCurrentWeekDoesNotDragTheAverageDown() {
        let now = date(2026, 11, 2, hour: 7) // 周一
        let runs = (1...25).map { offset in
            run(Int64(offset), calendar.date(byAdding: .weekOfYear, value: -offset, to: date(2026, 11, 3))!, metres: 2_000)
        }
        let average = summary(runs, now: now).mileage[.halfYear]!.headlineKm
        XCTAssertEqual(average, 2.0, accuracy: 0.001)

        // 本周已经跑了，就照算进分母。
        let withToday = runs + [run(99, date(2026, 11, 2, hour: 6), metres: 2_000)]
        XCTAssertEqual(summary(withToday, now: now).mileage[.halfYear]!.headlineKm, 2.0, accuracy: 0.001)
        XCTAssertEqual(summary(withToday, now: now).mileage[.halfYear]!.bars.count, 26)
    }

    /// 今天之后的格子不画，本周七个圆标出今天与未来。
    func testFutureDaysAreNotDrawnAndTodayIsMarked() {
        let now = date(2026, 11, 5) // 周四
        let result = summary([run(1, date(2026, 11, 3), metres: 4_000)], now: now)
        let days = result.calendarWeeks.last!.days
        XCTAssertEqual(days[3], .none)
        XCTAssertEqual(Array(days[4...]), [.future, .future, .future])
        XCTAssertEqual(result.calendarWeeks.count, 26)
        XCTAssertEqual(result.thisWeek.map(\.isToday), [false, false, false, true, false, false, false])
        XCTAssertEqual(result.thisWeek.map(\.isFuture), [false, false, false, false, true, true, true])
        XCTAssertEqual(result.thisWeek.map(\.ran), [false, true, false, false, false, false, false])
    }

    /// 周日那一单算本周（ISO 周一开头）。按中国公历（周日开头）分周的实现会把它算进下一周。
    func testSundayBelongsToTheWeekThatStartedOnMonday() {
        let now = date(2026, 11, 8, hour: 20) // 周日晚上
        let result = summary([run(1, date(2026, 11, 8, hour: 7), metres: 5_000)], now: now)
        XCTAssertEqual(result.thisWeek[6].ran, true)
        XCTAssertEqual(result.mileage[.week]!.headlineKm, 5.0, accuracy: 0.001)
    }

    // MARK: - 分档与其他

    func testDailyLevelsFollowTheMockupThresholds() {
        XCTAssertEqual(VolunteerRunDataSummary.level(metres: 2_999), 1)
        XCTAssertEqual(VolunteerRunDataSummary.level(metres: 3_000), 2)
        XCTAssertEqual(VolunteerRunDataSummary.level(metres: 5_000), 3)
        XCTAssertEqual(VolunteerRunDataSummary.level(metres: 7_000), 4)
        XCTAssertEqual(VolunteerRunDataSummary.level(metres: nil), 1)
    }

    /// 对方注销（名字为空）的合成一行，按次数排。
    func testDeletedPartnersMergeIntoOneRow() {
        let now = date(2026, 11, 5)
        let runs = [
            run(1, date(2026, 10, 1), metres: 3_000, partner: "王*"),
            run(2, date(2026, 10, 8), metres: 3_000, partner: nil),
            run(3, date(2026, 10, 15), metres: 3_000, partner: nil),
            run(4, date(2026, 10, 22), metres: 3_000, partner: nil),
            run(5, date(2026, 10, 29), metres: 3_000, partner: "王*")
        ]
        let partners = summary(runs, now: now).partners
        XCTAssertEqual(partners, [.init(name: nil, count: 3), .init(name: "王*", count: 2)])
        XCTAssertEqual(VolunteerRunDataCopy.partner(partners[0].name, spoken: false), "已注销的跑者")
    }

    /// 上月比前月：两个月都加载过才给；只加载了一个月时不给（否则会说成「比 9 月多 50 公里」）。
    func testMonthComparisonNeedsBothMonthsLoaded() {
        let now = date(2026, 11, 5)
        let runs = [run(1, date(2026, 10, 10), metres: 50_100), run(2, date(2026, 9, 10), metres: 40_400)]
        let both = summary(runs, now: now, loaded: [RunRecordMonth(year: 2026, month: 10): 400, RunRecordMonth(year: 2026, month: 9): 300])
        XCTAssertEqual(both.mileageComparison?.lastKm ?? 0, 50.1, accuracy: 0.001)
        XCTAssertEqual(both.mileageComparison?.previousKm ?? 0, 40.4, accuracy: 0.001)
        XCTAssertEqual(VolunteerRunDataCopy.comparison(both.mileageComparison!), "10 月你陪跑了 50.1 公里，比 9 月多 9.7 公里。")
        let one = summary(runs, now: now, loaded: [RunRecordMonth(year: 2026, month: 10): 400])
        XCTAssertNil(one.mileageComparison)
    }

    /// 年档：12 根月柱，本月还没跑不进分母。
    func testYearSeriesHasTwelveMonthsAndSkipsAnEmptyCurrentMonth() {
        let now = date(2026, 11, 1, hour: 6)
        let runs = (1...11).map { offset -> VolunteerRunDataRun in
            let day = calendar.date(byAdding: .month, value: -offset, to: date(2026, 11, 10))!
            return run(Int64(offset), day, metres: 10_000)
        }
        let year = summary(runs, now: now).mileage[.year]!
        XCTAssertEqual(year.bars.count, 12)
        XCTAssertEqual(year.headlineKm, 10.0, accuracy: 0.001)
        XCTAssertEqual(calendar.component(.month, from: year.bars.first!.start), 12)
    }

    /// 最常陪跑的星期几：并列时两个都说。
    func testFavoriteWeekdayListsTies() {
        let now = date(2026, 11, 5)
        let runs = [
            run(1, date(2026, 10, 24), metres: 3_000), // 周六
            run(2, date(2026, 10, 25), metres: 3_000), // 周日
            run(3, date(2026, 10, 31), metres: 3_000), // 周六
            run(4, date(2026, 11, 1), metres: 3_000)   // 周日
        ]
        let result = summary(runs, now: now)
        XCTAssertEqual(result.favoriteWeekdays, [5, 6])
        XCTAssertEqual(VolunteerRunDataCopy.favoriteWeekday(result.favoriteWeekdays), "近半年你最常在周六和周日陪跑。")
    }

    /// 单周最多次数与单周最远。
    func testWeeklyRecords() {
        let runs = [
            run(1, date(2026, 10, 19), metres: 4_000),
            run(2, date(2026, 10, 21), metres: 6_600),
            run(3, date(2026, 10, 24), metres: nil),
            run(4, date(2026, 10, 27), metres: 5_000)
        ]
        let records = summary(runs, now: date(2026, 11, 5)).records
        XCTAssertEqual(records.mostRunsInWeek, 3)
        XCTAssertEqual(records.mostMetresInWeek, 10_600)
        XCTAssertEqual(records.longestRunMetres, 6_600)
    }

    // MARK: - 从月度响应解析

    /// 走 `init(months:)`：后端无时区串（含小数秒）能解析、同一单出现两次只算一次、`serviceMin` 进陪伴时长。
    func testBuildsFromMonthlyResponses() {
        let october = RunRecordMonth(year: 2026, month: 10)
        let november = RunRecordMonth(year: 2026, month: 11)
        let item = { (id: Int64, at: String, metres: Int?) in
            RunHistoryItem(orderId: id, finishedAt: at, place: "西湖", partnerName: "李*", distanceM: metres, thumbnail: nil)
        }
        let response = { (month: RunRecordMonth, minutes: Int64, items: [RunHistoryItem]) in
            RunRecordHistoryResponse(
                role: .volunteer, month: RunRecordService.monthQuery(year: month.year, month: month.month),
                monthSummary: RunMonthSummary(runs: items.count, distanceM: nil, serviceMin: minutes, topPartner: nil),
                items: items
            )
        }
        let months = [
            october: response(october, 120, [item(1, "2026-10-17T07:30:00.123456", 6_600), item(2, "2026-10-03T07:30:00", nil)]),
            november: response(november, 30, [item(1, "2026-10-17T07:30:00", 6_600), item(3, "2026-11-03T08:00:00", 4_200)])
        ]
        let result = VolunteerRunDataSummary(months: months, now: date(2026, 11, 5), calendar: calendar)
        XCTAssertEqual(result.daysRunInWindow, 3, "orderId 1 两个月都出现，只算一天")
        XCTAssertEqual(result.longestRun?.orderId, 1)
        XCTAssertEqual(result.serviceMonths.map(\.minutes), [nil, nil, nil, nil, 120, 30])
        XCTAssertEqual(result.calendarMonths.first?.days, [3])
        XCTAssertEqual(result.calendarMonths.dropFirst().first?.days, [3, 17])
    }

    // MARK: - 读屏

    /// 定稿原句：「近半年陪跑 N 天，最长连续 M 周。11 月 1 天：3 日。10 月 …」，没跑的月说「没有陪跑」。
    func testCalendarSentenceListsEachMonthNewestFirst() {
        let now = date(2026, 11, 5)
        let result = summary([run(1, date(2026, 11, 3), metres: 3_000), run(2, date(2026, 10, 17), metres: 6_600)], now: now)
        let sentence = VolunteerRunDataCopy.calendarSpoken(result, current: RunRecordMonth(year: 2026, month: 11))
        XCTAssertTrue(sentence.hasPrefix("近半年陪跑 2 天，最长连续 1 周。11月 1 天：3 日。10月 1 天：17 日。9月没有陪跑"), sentence)
    }

    func testThisWeekLineSaysWhetherTheWeekWasCredited() {
        XCTAssertEqual(VolunteerRunDataCopy.thisWeekLine(partner: "李*", credited: true), "本周已经和 李* 跑过，这一周记上了")
        XCTAssertEqual(
            VolunteerRunDataCopy.thisWeekLine(partner: "李*", credited: false, spoken: true),
            "本周还没和 李 一起跑，跑完一次就记上这一周"
        )
    }

    // MARK: - 先到先画

    @MainActor
    func testModelDrawsAsSoonAsTheFirstMonthArrivesAndCountsFailures() {
        let model = VolunteerRunDataModel(now: date(2026, 11, 5), calendar: calendar)
        XCTAssertEqual(model.phase, .loading)
        let months = model.targetMonths
        XCTAssertEqual(months.count, 12)
        model.record(month: months[0], response: nil)
        XCTAssertEqual(model.phase, .loading, "失败一个月还不算全失败")
        let november = RunRecordHistoryResponse(
            role: .volunteer, month: "2026-11",
            monthSummary: RunMonthSummary(runs: 1, distanceM: 3_000, serviceMin: 30, topPartner: nil),
            items: [RunHistoryItem(orderId: 1, finishedAt: "2026-11-03T08:00:00", place: nil, partnerName: "李*", distanceM: 3_000, thumbnail: nil)]
        )
        model.record(month: months[11], response: november)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.summary.daysRunInWindow, 1)
        XCTAssertEqual(model.failedMonths, [months[0]])

        let failing = VolunteerRunDataModel(now: date(2026, 11, 5), calendar: calendar)
        failing.targetMonths.forEach { failing.record(month: $0, response: nil) }
        XCTAssertEqual(failing.phase, .failed)
    }
}
