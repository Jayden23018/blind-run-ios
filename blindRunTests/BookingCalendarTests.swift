import XCTest
@testable import blindRun

/// 约跑页 v5（#821）的日历与时段判定：可约天数读后端、跨月、值守时段取交集。
/// 「现在」固定在北京时间 2026-11-07（周六）10:00，所有日子按北京时间的日初。
@MainActor
final class BookingCalendarTests: XCTestCase {
    private let calendar = Calendar.aidRunBackend
    private let thirtyDays = BookingRules(maxLeadDays: 30)
    private let sevenDays = BookingRules(maxLeadDays: 7)

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { date(11, 7, 10) }

    // MARK: 可约天数

    func test_dayThreeWeeksOut_isBookableWith30Days_butNotWith7() {
        // 12 月 1 日在两种上限下结果不同：能区分「读了后端的 30」和「还写死 7」。
        XCTAssertTrue(BookingSlotPlanner.isDayAvailable(date(12, 1), now: now, rules: thirtyDays))
        XCTAssertFalse(BookingSlotPlanner.isDayAvailable(date(12, 1), now: now, rules: sevenDays))
        XCTAssertEqual(BookingCalendar.state(of: date(12, 1), now: now, rules: sevenDays), .beyondRange)
    }

    func test_lastDay_onlyAllowsSlotsStartingBeforeTheLatestStart() {
        // 最晚开跑 = 12 月 7 日 10:00：上午段 6:00 起能约，下午段 13:00 起就超出了。
        XCTAssertNotNil(BookingSlotPlanner.window(day: date(12, 7), slot: .morning, now: now, rules: thirtyDays))
        XCTAssertNil(BookingSlotPlanner.window(day: date(12, 7), slot: .afternoon, now: now, rules: thirtyDays))
        XCTAssertEqual(
            BookingSlotPlanner.unavailableReason(day: date(12, 7), slot: .afternoon, now: now, rules: thirtyDays),
            .tooFar
        )
        XCTAssertEqual(BookingCalendar.state(of: date(12, 8), now: now, rules: thirtyDays), .beyondRange)
    }

    func test_preferredStartTimes_stopAtTheLatestStart() {
        let times = BookingSlotPlanner.startTimes(day: date(12, 7), slot: .morning, now: now, rules: thirtyDays)
        XCTAssertEqual(times.first, date(12, 7, 6))
        XCTAssertEqual(times.last, date(12, 7, 10))
    }

    // MARK: 周与月

    func test_weeks_startOnMondayOfThisWeek_andCoverTheWholeRange() {
        let weeks7 = BookingCalendar.weeks(now: now, rules: sevenDays)
        XCTAssertEqual(weeks7.map(\.id), [date(11, 2), date(11, 9)])
        let weeks30 = BookingCalendar.weeks(now: now, rules: thirtyDays)
        XCTAssertEqual(weeks30.count, 6)
        XCTAssertEqual(weeks30.last?.id, date(12, 7))
        XCTAssertTrue(weeks30.allSatisfy { $0.days.count == 7 })
    }

    func test_months_listOnlyMonthsWithBookableDays_andPointAtTheirFirstBookableDay() {
        let lateNovember = date(11, 20, 10)
        // 11-20 10:00：上午段被提前量裁到 10:30 只剩 30 分钟，不能选；下午还能约，所以 11 月从 20 日起。
        XCTAssertEqual(BookingCalendar.months(now: lateNovember, rules: thirtyDays), [date(11, 20), date(12, 1)])
        XCTAssertEqual(BookingCalendar.months(now: lateNovember, rules: sevenDays), [date(11, 20)])
    }

    func test_title_namesBothMonthsWhenAWeekCrossesThem() {
        let week = BookingWeek(days: (0..<7).map { calendar.date(byAdding: .day, value: $0, to: date(11, 30))! })
        XCTAssertEqual(BookingCalendar.title(for: week), "2026年11月–12月")
        XCTAssertEqual(BookingCalendar.spokenRange(of: week), "11 月 30 日到12 月 6 日")
    }

    func test_pastDays_areMarkedPast() {
        XCTAssertEqual(BookingCalendar.state(of: date(11, 6), now: now, rules: thirtyDays), .past)
        XCTAssertEqual(BookingCalendar.state(of: date(11, 7), now: now, rules: thirtyDays), .available)
    }

    // MARK: 值守时段

    private var weekdayEvenings: BookingRules {
        // 周一到周五 18:00–21:00（Calendar.weekday：周一 = 2 … 周五 = 6）。
        BookingRules(
            maxLeadDays: 30,
            dutyRanges: [.init(weekdays: [2, 3, 4, 5, 6], startMinute: 18 * 60, endMinute: 21 * 60)]
        )
    }

    func test_dutyHours_clipEveningAndBlockMorningAndAfternoon() {
        let monday = date(11, 9)
        XCTAssertNil(BookingSlotPlanner.window(day: monday, slot: .morning, now: now, rules: weekdayEvenings))
        XCTAssertEqual(
            BookingSlotPlanner.unavailableReason(day: monday, slot: .afternoon, now: now, rules: weekdayEvenings),
            .offDuty
        )
        let evening = BookingSlotPlanner.window(day: monday, slot: .evening, now: now, rules: weekdayEvenings)
        XCTAssertEqual(evening?.start, date(11, 9, 18))
        XCTAssertEqual(evening?.end, date(11, 9, 21))
    }

    func test_dutyHours_makeWeekendsUnavailable() {
        let saturday = date(11, 14)
        XCTAssertFalse(BookingSlotPlanner.isDayAvailable(saturday, now: now, rules: weekdayEvenings))
        XCTAssertEqual(BookingCalendar.state(of: saturday, now: now, rules: weekdayEvenings), .unavailable)
        // 没有值守限制时同一天能约：确认是值守时段挡住的，不是别的原因。
        XCTAssertTrue(BookingSlotPlanner.isDayAvailable(saturday, now: now, rules: thirtyDays))
    }

    func test_dutyRanges_crossingMidnight_areNotUsedForClipping() {
        let scope = LaunchScopeResponse(
            acceptingOrders: true, areaRestricted: false, dutyHoursRestricted: true,
            dutyWindows: [.init(days: ["MONDAY"], start: "22:00", end: "02:00")]
        )
        XCTAssertNil(scope.dutyMinuteRanges())
    }

    func test_dutyRanges_parseWeekdayNames() {
        let scope = LaunchScopeResponse(
            acceptingOrders: true, areaRestricted: false, dutyHoursRestricted: true,
            dutyWindows: [.init(days: ["MONDAY", "SUNDAY"], start: "18:00", end: "21:00")]
        )
        XCTAssertEqual(scope.dutyMinuteRanges(), [.init(weekdays: [2, 1], startMinute: 1080, endMinute: 1260)])
    }

    // MARK: 读屏上下轻扫换天

    func test_step_walksOnlyBookableDays_andStopsAtTheEnds() {
        let days = [date(11, 7), date(11, 9), date(11, 10)]
        XCTAssertEqual(BookingCalendar.step(from: date(11, 7), by: 1, in: days), date(11, 9))
        XCTAssertEqual(BookingCalendar.step(from: date(11, 9), by: -1, in: days), date(11, 7))
        XCTAssertNil(BookingCalendar.step(from: date(11, 10), by: 1, in: days))
        XCTAssertEqual(BookingCalendar.step(from: nil, by: 1, in: days), date(11, 7))
        XCTAssertNil(BookingCalendar.step(from: nil, by: 1, in: []))
    }

    // MARK: 陪跑员安排单跟着放宽

    func test_volunteerPlanLatestStart_followsMaxLeadDays() {
        // 24 天后的时段单：按 30 天能填，按旧的 7 天会被判「太远」。
        XCTAssertGreaterThan(VolunteerMeetupPlanDraft.latestStart(now: now, maxLeadDays: 30), date(12, 1, 8))
        XCTAssertLessThan(VolunteerMeetupPlanDraft.latestStart(now: now, maxLeadDays: 7), date(12, 1, 8))
    }

    // MARK: 后端下发的天数

    func test_maxLeadDays_fallsBackTo7WhenMissingOrInvalid() throws {
        XCTAssertEqual(RuleParams(response: nil).maxLeadDays, 7)
        XCTAssertEqual(RuleParams(response: RuleParamsResponse(lateCancelWindowHours: nil, volunteerOrderAutoOpenLeadMinutes: nil)).maxLeadDays, 7)
        XCTAssertEqual(RuleParams(response: RuleParamsResponse(lateCancelWindowHours: nil, volunteerOrderAutoOpenLeadMinutes: nil, maxLeadDays: 0)).maxLeadDays, 7)
        let decoded = try JSONDecoder().decode(RuleParamsResponse.self, from: Data(#"{"maxLeadDays":30}"#.utf8))
        XCTAssertEqual(RuleParams(response: decoded).maxLeadDays, 30)
    }
}
