import Foundation

// 跑步数据页（#710）各块的算法。入口与结果形状在 `VolunteerRunDataSummary.swift`。
// 每个函数只算一块，共用的按天 / 按周索引在 `Context` 里只算一次。

extension VolunteerRunDataSummary {
    /// 一次计算共用的东西：时间锚点和按天、按周的索引。
    struct Context {
        let runs: [VolunteerRunDataRun]
        let serviceMinutes: [RunRecordMonth: Int64]
        let calendar: Calendar
        let today: Date
        let thisMonday: Date
        /// 陪跑日历第一列的周一（本周一往前 25 周）。
        let windowStart: Date
        let currentMonth: RunRecordMonth
        /// 近 12 个月，旧的在前，最后一个是本月。
        let yearMonths: [RunRecordMonth]
        let windowRuns: [VolunteerRunDataRun]
        let runsByDay: [Date: Int]
        /// 只加已知公里；公里未知的单不进这里（口径 2）。
        let metresByDay: [Date: Int]
        let metresByMonth: [RunRecordMonth: Int]
        let mondaysWithRuns: Set<Date>

        init(runs: [VolunteerRunDataRun], serviceMinutes: [RunRecordMonth: Int64], now: Date, calendar: Calendar) {
            self.runs = runs
            self.serviceMinutes = serviceMinutes
            self.calendar = calendar
            today = calendar.startOfDay(for: now)
            let monday = VolunteerRunDataSummary.monday(of: now, calendar: calendar)
            let start = calendar.date(
                byAdding: .weekOfYear, value: -(VolunteerRunDataSummary.windowWeeks - 1), to: monday
            ) ?? monday
            thisMonday = monday
            windowStart = start
            currentMonth = RunRecordMonth(containing: now, calendar: calendar)
            var months = [currentMonth]
            while months.count < VolunteerRunDataSummary.yearMonths { months.insert(months[0].previous, at: 0) }
            yearMonths = months
            windowRuns = runs.filter { $0.finishedAt >= start }

            var runsByDay: [Date: Int] = [:]
            var metresByDay: [Date: Int] = [:]
            var metresByMonth: [RunRecordMonth: Int] = [:]
            for run in runs {
                let day = calendar.startOfDay(for: run.finishedAt)
                runsByDay[day, default: 0] += 1
                guard let metres = run.metres else { continue }
                metresByDay[day, default: 0] += metres
                metresByMonth[RunRecordMonth(containing: run.finishedAt, calendar: calendar), default: 0] += metres
            }
            self.runsByDay = runsByDay
            self.metresByDay = metresByDay
            self.metresByMonth = metresByMonth
            mondaysWithRuns = Set(runs.map { VolunteerRunDataSummary.monday(of: $0.finishedAt, calendar: calendar) })
        }

        func day(_ offset: Int, from start: Date) -> Date? {
            calendar.date(byAdding: .day, value: offset, to: start)
        }

        func km(on day: Date) -> Double {
            Double(metresByDay[day] ?? 0) / 1000
        }

        func firstDay(of month: RunRecordMonth) -> Date {
            calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) ?? today
        }
    }

    // MARK: 陪跑日历

    static func makeCalendarWeeks(_ context: Context) -> [CalendarWeek] {
        (0..<windowWeeks).compactMap { offset in
            guard let monday = context.calendar.date(byAdding: .weekOfYear, value: offset, to: context.windowStart) else {
                return nil
            }
            let days = (0..<7).map { index -> DayMark in
                guard let day = context.day(index, from: monday), day <= context.today else { return .future }
                guard context.runsByDay[day] != nil else { return .none }
                return .ran(level: level(metres: context.metresByDay[day]))
            }
            return CalendarWeek(monday: monday, days: days)
        }
    }

    /// 按月列出近半年哪几天跑了（新的月在前）。范围内一天没跑的月也列，读屏要听到「8 月没有陪跑」。
    static func makeCalendarMonths(_ context: Context) -> [MonthDays] {
        let days = Set(context.windowRuns.map { context.calendar.startOfDay(for: $0.finishedAt) })
        var list: [MonthDays] = []
        var cursor = RunRecordMonth(containing: context.windowStart, calendar: context.calendar)
        let last = context.currentMonth.year * 12 + context.currentMonth.month
        while cursor.year * 12 + cursor.month <= last {
            let month = cursor
            let numbers = days
                .filter { RunRecordMonth(containing: $0, calendar: context.calendar) == month }
                .map { context.calendar.component(.day, from: $0) }
                .sorted()
            list.append(MonthDays(month: month, days: numbers))
            cursor = cursor.next
        }
        return list.reversed()
    }

    static func makeThisWeek(_ context: Context) -> [WeekDot] {
        (0..<7).map { index in
            let day = context.day(index, from: context.thisMonday) ?? context.thisMonday
            return WeekDot(
                weekday: index,
                ran: context.runsByDay[day] != nil,
                isToday: day == context.today,
                isFuture: day > context.today
            )
        }
    }

    // MARK: 里程

    static func makeMileage(_ context: Context, weeks: [CalendarWeek]) -> [MileageRange: MileageSeries] {
        let calendar = context.calendar
        func dayBars(from start: Date, count: Int) -> [Bar] {
            (0..<count).compactMap { index in context.day(index, from: start).map { Bar(start: $0, value: context.km(on: $0)) } }
        }
        let weekEnd = context.day(6, from: context.thisMonday) ?? context.thisMonday

        let weekBars = dayBars(from: context.thisMonday, count: 7)
        let monthStart = context.firstDay(of: context.currentMonth)
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let monthBars = dayBars(from: monthStart, count: dayCount)
        let halfYearBars = weeks.map { week in
            Bar(start: week.monday, value: (0..<7).compactMap { context.day($0, from: week.monday) }.map(context.km(on:)).reduce(0, +))
        }
        let yearBars = context.yearMonths.map {
            Bar(start: context.firstDay(of: $0), value: Double(context.metresByMonth[$0] ?? 0) / 1000)
        }

        return [
            .week: MileageSeries(
                range: .week, bars: weekBars, headlineKm: weekBars.map(\.value).reduce(0, +),
                start: context.thisMonday, end: weekEnd
            ),
            .month: MileageSeries(
                range: .month, bars: monthBars, headlineKm: monthBars.map(\.value).reduce(0, +),
                start: monthStart, end: context.day(dayCount - 1, from: monthStart) ?? monthStart
            ),
            .halfYear: MileageSeries(
                range: .halfYear, bars: halfYearBars, headlineKm: average(halfYearBars.map(\.value)),
                start: context.windowStart, end: weekEnd
            ),
            .year: MileageSeries(
                range: .year, bars: yearBars, headlineKm: average(yearBars.map(\.value)),
                start: context.firstDay(of: context.yearMonths[0]), end: monthStart
            )
        ]
    }

    // MARK: 陪伴时长与提要

    static func makeServiceMonths(_ context: Context) -> [ServiceMonth] {
        context.yearMonths.suffix(serviceMonthCount).map { ServiceMonth(month: $0, minutes: context.serviceMinutes[$0]) }
    }

    /// 上月 vs 前月。两个月都要加载过；都是 0 时不出这张（「0 比 0」没有话说）。
    static func makeComparison(_ context: Context) -> MonthComparison? {
        let lastMonth = context.currentMonth.previous
        let previousMonth = lastMonth.previous
        guard context.serviceMinutes[lastMonth] != nil, context.serviceMinutes[previousMonth] != nil else { return nil }
        let lastKm = Double(context.metresByMonth[lastMonth] ?? 0) / 1000
        let previousKm = Double(context.metresByMonth[previousMonth] ?? 0) / 1000
        guard lastKm > 0 || previousKm > 0 else { return nil }
        return MonthComparison(lastMonth: lastMonth, lastKm: lastKm, previousMonth: previousMonth, previousKm: previousKm)
    }

    /// 近半年每个星期几陪跑了几次（按次数，不按天）。
    static func makeWeekdayCounts(_ context: Context) -> [Int] {
        var counts = Array(repeating: 0, count: 7)
        for run in context.windowRuns {
            counts[(context.calendar.component(.weekday, from: run.finishedAt) + 5) % 7] += 1
        }
        return counts
    }

    /// 一起跑的人：近半年按次数；注销的人（名字为空）合成一行。并列时最近跑过的在前。
    static func makePartners(_ context: Context) -> [PartnerCount] {
        var counts: [String?: (count: Int, last: Date)] = [:]
        for run in context.windowRuns {
            let current = counts[run.partnerName] ?? (0, run.finishedAt)
            counts[run.partnerName] = (current.count + 1, max(current.last, run.finishedAt))
        }
        return counts
            .sorted { lhs, rhs in
                lhs.value.count != rhs.value.count ? lhs.value.count > rhs.value.count : lhs.value.last > rhs.value.last
            }
            .map { PartnerCount(name: $0.key, count: $0.value.count) }
    }

    // MARK: 个人纪录

    /// 已加载的全部月份（近 12 个月）。
    static func makeRecords(_ context: Context, longestRun: VolunteerRunDataRun?) -> Records {
        var runsByWeek: [Date: Int] = [:]
        var metresByWeek: [Date: Int] = [:]
        for run in context.runs {
            let week = monday(of: run.finishedAt, calendar: context.calendar)
            runsByWeek[week, default: 0] += 1
            metresByWeek[week, default: 0] += run.metres ?? 0
        }
        return Records(
            longestRunMetres: longestRun?.metres,
            mostRunsInWeek: runsByWeek.values.max() ?? 0,
            mostMetresInWeek: metresByWeek.values.max() ?? 0,
            longestWeeks: longestConsecutiveWeeks(context.mondaysWithRuns, calendar: context.calendar)
        )
    }
}
