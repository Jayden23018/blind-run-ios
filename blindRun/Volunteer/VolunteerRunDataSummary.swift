import Foundation

// 陪跑员「连续陪跑」跑步数据页的全部数字（负责人 2026-11-05 批准 v1，#710；
// 定稿 `docs/ui/mockups/volunteer-run-data-20261105/run-data-final.png`）。
//
// 只依赖 Foundation：页面上每个数字都从这里出来，视图不做计算。
// 这些数字算错时屏幕上仍是一张排版正常的图，所以写成纯函数，留给单测钉住。
//
// 三条口径（OpenSpec `add-volunteer-run-data-page`）：
// 1. 按 ISO 周（周一开头、跨年周归下一年）、本地时区归天归周。
// 2. `distanceM` 为 null 的那一单**算陪跑过的一天**，但不当 0 公里进任何公里数或平均。
// 3. 「最长连续」与任何搭档都算，客户端按周数。
//
// 各块的算法在 `VolunteerRunDataSummary+Sections.swift`，这里只有结果的形状和入口。

// MARK: - 汇总

struct VolunteerRunDataSummary: Equatable {
    let calendarWeeks: [CalendarWeek]
    /// 新的月在前。
    let calendarMonths: [MonthDays]
    let daysRunInWindow: Int
    let longestWeeksInWindow: Int
    let thisWeek: [WeekDot]
    let mileage: [MileageRange: MileageSeries]
    let serviceMonths: [ServiceMonth]
    let averageServiceMinutes: Int64?
    let mileageComparison: MonthComparison?
    /// 近半年每个星期几陪跑了几次，0 = 周一。
    let weekdayCounts: [Int]
    /// 次数最多的星期几（并列时都在里面）；近半年一次都没有时为空。
    let favoriteWeekdays: [Int]
    let longestRun: VolunteerRunDataRun?
    let partners: [PartnerCount]
    let records: Records
    let hasAnyRun: Bool

    /// - Parameter months: 已加载的月份。没加载出来的月份不在字典里，按「没有记录」处理（页面另有失败提示）。
    init(months: [RunRecordMonth: RunRecordHistoryResponse], now: Date, calendar: Calendar = .volunteerRunData) {
        // 同一单出现在两个月里（不该发生）时只算一次。
        var seen = Set<Int64>()
        let runs = months.values
            .flatMap(\.items)
            .compactMap(VolunteerRunDataRun.init(item:))
            .filter { seen.insert($0.orderId).inserted }
        self.init(runs: runs, serviceMinutes: months.mapValues { $0.monthSummary.serviceMin ?? 0 }, now: now, calendar: calendar)
    }

    /// 单测入口：直接给解析好的单子。`serviceMinutes` 只含已加载的月份。
    init(runs: [VolunteerRunDataRun], serviceMinutes: [RunRecordMonth: Int64], now: Date, calendar: Calendar = .volunteerRunData) {
        let context = Context(
            runs: runs.filter { $0.finishedAt <= now }.sorted { $0.finishedAt < $1.finishedAt },
            serviceMinutes: serviceMinutes,
            now: now,
            calendar: calendar
        )
        calendarWeeks = Self.makeCalendarWeeks(context)
        calendarMonths = Self.makeCalendarMonths(context)
        daysRunInWindow = Set(context.windowRuns.map { calendar.startOfDay(for: $0.finishedAt) }).count
        longestWeeksInWindow = Self.longestConsecutiveWeeks(
            context.mondaysWithRuns.filter { $0 >= context.windowStart }, calendar: calendar
        )
        thisWeek = Self.makeThisWeek(context)
        mileage = Self.makeMileage(context, weeks: calendarWeeks)
        serviceMonths = Self.makeServiceMonths(context)
        let loadedService = serviceMonths.filter { $0.minutes != nil }
        averageServiceMinutes = loadedService.isEmpty
            ? nil
            : Int64(Self.average(
                loadedService.map { Double($0.minutes ?? 0) },
                lastIsUnfinished: loadedService.last?.month == context.currentMonth
            ).rounded())
        mileageComparison = Self.makeComparison(context)
        let counts = Self.makeWeekdayCounts(context)
        let topCount = counts.max() ?? 0
        weekdayCounts = counts
        favoriteWeekdays = topCount > 0 ? counts.indices.filter { counts[$0] == topCount } : []
        // 最远一次：公里未知的不参评；并列取最近的一次。
        longestRun = context.runs.filter { $0.metres != nil }.max { lhs, rhs in
            (lhs.metres ?? 0, lhs.finishedAt) < (rhs.metres ?? 0, rhs.finishedAt)
        }
        partners = Self.makePartners(context)
        records = Self.makeRecords(context, longestRun: longestRun)
        hasAnyRun = !context.runs.isEmpty
    }
}

// MARK: - 结果的形状

extension VolunteerRunDataSummary {
    /// 陪跑日历与「近半年」的范围：本周一往前 25 周，共 26 周。
    static let windowWeeks = 26
    static let yearMonths = 12
    static let serviceMonthCount = 6

    /// 日历里的一格。
    enum DayMark: Equatable {
        /// 今天之后：不画。
        case future
        case none
        /// 1...4，按当天公里分档（`level(metres:)`）。
        case ran(level: Int)
    }

    struct CalendarWeek: Equatable {
        let monday: Date
        /// 周一到周日，恒 7 格。
        let days: [DayMark]
    }

    /// 一个月里哪几天陪跑了（日期号升序）。读屏摘要与 AX3 以上的按月列表用它。
    struct MonthDays: Equatable {
        let month: RunRecordMonth
        let days: [Int]
    }

    struct WeekDot: Equatable {
        /// 0 = 周一 … 6 = 周日。
        let weekday: Int
        let ran: Bool
        let isToday: Bool
        let isFuture: Bool
    }

    enum MileageRange: String, CaseIterable, Identifiable {
        case week, month, halfYear, year
        var id: String { rawValue }
    }

    struct Bar: Equatable {
        let start: Date
        /// 公里（里程图）或分钟（陪伴时长图）。
        let value: Double
    }

    struct MileageSeries: Equatable {
        let range: MileageRange
        let bars: [Bar]
        /// 周档 / 月档是总计，半年档 / 年档是平均。
        let headlineKm: Double
        var isAverage: Bool { range == .halfYear || range == .year }
        /// 起止日期（含）。年档是起止月的 1 号。
        let start: Date
        let end: Date
    }

    struct ServiceMonth: Equatable {
        let month: RunRecordMonth
        /// 这个月没加载出来时为 nil（不画柱、不进平均），与「加载了但是 0」分开。
        let minutes: Int64?
    }

    struct MonthComparison: Equatable {
        let lastMonth: RunRecordMonth
        let lastKm: Double
        let previousMonth: RunRecordMonth
        let previousKm: Double
    }

    struct PartnerCount: Equatable {
        /// nil = 对方已注销。
        let name: String?
        let count: Int
    }

    struct Records: Equatable {
        let longestRunMetres: Int?
        let mostRunsInWeek: Int
        let mostMetresInWeek: Int
        let longestWeeks: Int
    }

    // MARK: 小工具

    /// 当天公里分档，照定稿：0–3 / 3–5 / 5–7 / 7 以上。跑了但公里全部未知时算最浅一档。
    static func level(metres: Int?) -> Int {
        guard let metres else { return 1 }
        switch metres {
        case ..<3_000: return 1
        case ..<5_000: return 2
        case ..<7_000: return 3
        default: return 4
        }
    }

    static func monday(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// 一组周一里最长的连续段。相邻按日历加一周判，跨年（W52 → W01、W53 → W01）照样连上。
    static func longestConsecutiveWeeks(_ mondays: Set<Date>, calendar: Calendar) -> Int {
        var best = 0
        var current = 0
        var previous: Date?
        for monday in mondays.sorted() {
            if let previous, calendar.date(byAdding: .weekOfYear, value: 1, to: previous) == monday {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = monday
        }
        return best
    }

    /// 平均。最后一段（本周 / 本月）还没结束，**还没有数时不进分母** —— 否则每周一、每月初平均都被拉低一截。
    /// 已经有数时照算：它是真跑出来的。`lastIsUnfinished` 为 false 时（最后一个不是本周 / 本月，
    /// 例如本月没加载出来），最后一个是 0 也照算。
    static func average(_ values: [Double], lastIsUnfinished: Bool = true) -> Double {
        guard let last = values.last else { return 0 }
        let denominator = values.count - (lastIsUnfinished && last == 0 ? 1 : 0)
        guard denominator > 0 else { return 0 }
        return values.reduce(0, +) / Double(denominator)
    }
}
