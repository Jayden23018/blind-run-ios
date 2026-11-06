import Foundation

// MARK: - 约跑页的日历（#821，v5）
//
// v4 只有一排 7 个日期圆，月份那一排是装饰，点不了。v5 改成真实的日历：
// - 按周一到周日分页，能翻到下一周；
// - 月份只列可约范围覆盖的月份，点了跳到那个月第一个能约的日子；
// - 可约范围的长度读后端 `maxLeadDays`（负责人 2026-11-07 定放宽到 30 天，backend#935）。
// 本文件只放纯判定，`now` / `rules` / `calendar` 都走参数，单测能钉住跨月与边界。

/// 日期格子的样子。
nonisolated enum BookingDayState: Equatable, Sendable {
    /// 能约。
    case available
    /// 今天之前。浅灰字，不画圈。
    case past
    /// 在可约范围里，但没有任何一段能约（值守时段外、或今天已经太晚）。虚线圈。
    case unavailable
    /// 超出最远可约天数。虚线圈。
    case beyondRange
}

/// 一周：周一到周日 7 天，每个元素是北京时间的日初。
nonisolated struct BookingWeek: Equatable, Sendable, Identifiable {
    let days: [Date]
    var id: Date { days[0] }
}

enum BookingCalendar {
    /// 覆盖「今天 … 可约的最后一天」的所有周。第一周从今天所在那周的周一起。
    static func weeks(now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> [BookingWeek] {
        let range = BookingSlotPlanner.days(now: now, rules: rules, calendar: calendar)
        guard let first = range.first, let last = range.last else { return [] }
        var monday = startOfWeek(first, calendar: calendar)
        var weeks: [BookingWeek] = []
        while monday <= last {
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
            weeks.append(BookingWeek(days: days))
            guard let next = calendar.date(byAdding: .day, value: 7, to: monday) else { break }
            monday = next
        }
        return weeks
    }

    /// 那天所在周的周一。`Calendar.weekday` 周日 = 1，所以周一偏移是 `(weekday + 5) % 7`。
    static func startOfWeek(_ day: Date, calendar: Calendar = .aidRunBackend) -> Date {
        let start = calendar.startOfDay(for: day)
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    static func state(of day: Date, now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> BookingDayState {
        let today = calendar.startOfDay(for: now)
        if day < today { return .past }
        let lastDay = calendar.startOfDay(for: BookingSlotPlanner.latestStart(now: now, rules: rules))
        if day > lastDay { return .beyondRange }
        return BookingSlotPlanner.isDayAvailable(day, now: now, rules: rules, calendar: calendar) ? .available : .unavailable
    }

    /// 所有能约的日子，按时间排。读屏的「可调整」日期只在这些日子里走。
    static func availableDays(now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> [Date] {
        BookingSlotPlanner.days(now: now, rules: rules, calendar: calendar)
            .filter { BookingSlotPlanner.isDayAvailable($0, now: now, rules: rules, calendar: calendar) }
    }

    /// 月份胶囊：有能约日子的月份，每个元素是该月第一个能约的日子。
    static func months(now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> [Date] {
        var firstDays: [Date] = []
        for day in availableDays(now: now, rules: rules, calendar: calendar) {
            if let last = firstDays.last, calendar.isDate(last, equalTo: day, toGranularity: .month) { continue }
            firstDays.append(day)
        }
        return firstDays
    }

    /// 读屏上下轻扫换一天：在能约的日子里前后走 `step` 天。还没选（或选的不在里面）时落到第一个能约的日子；
    /// 走到头返回 `nil`（不动）。
    static func step(from selected: Date?, by step: Int, in availableDays: [Date]) -> Date? {
        guard let first = availableDays.first else { return nil }
        guard let selected, let current = availableDays.firstIndex(of: selected) else { return first }
        let next = current + step
        return availableDays.indices.contains(next) ? availableDays[next] : nil
    }

    /// 那天在第几周。不在任何一周里返回 `nil`。
    static func weekIndex(of day: Date, in weeks: [BookingWeek]) -> Int? {
        weeks.firstIndex { $0.days.contains(day) }
    }

    /// 标题：「2026年11月」。一周跨两个月时写「2026年11月–12月」，跨年写全两头。
    static func title(for week: BookingWeek, calendar: Calendar = .aidRunBackend) -> String {
        guard let first = week.days.first, let last = week.days.last else { return "" }
        let firstYear = calendar.component(.year, from: first)
        let firstMonth = calendar.component(.month, from: first)
        let lastYear = calendar.component(.year, from: last)
        let lastMonth = calendar.component(.month, from: last)
        if firstYear != lastYear { return "\(firstYear)年\(firstMonth)月–\(lastYear)年\(lastMonth)月" }
        if firstMonth != lastMonth { return "\(firstYear)年\(firstMonth)月–\(lastMonth)月" }
        return "\(firstYear)年\(firstMonth)月"
    }

    /// 卡底那句：「最多约 30 天内，最远到 12月7日」。
    static func rangeFootnote(now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> String {
        let latest = BookingSlotPlanner.latestStart(now: now, rules: rules)
        let month = calendar.component(.month, from: latest)
        let day = calendar.component(.day, from: latest)
        return "最多约 \(rules.maxLeadDays) 天内，最远到 \(month)月\(day)日"
    }

    /// 读屏念的一周范围：「11 月 9 日到 15 日」「11 月 30 日到 12 月 6 日」。翻周按钮的标签用。
    static func spokenRange(of week: BookingWeek, calendar: Calendar = .aidRunBackend) -> String {
        guard let first = week.days.first, let last = week.days.last else { return "" }
        let firstMonth = calendar.component(.month, from: first)
        let lastMonth = calendar.component(.month, from: last)
        let head = "\(firstMonth) 月 \(calendar.component(.day, from: first)) 日"
        let tail = firstMonth == lastMonth
            ? "\(calendar.component(.day, from: last)) 日"
            : "\(lastMonth) 月 \(calendar.component(.day, from: last)) 日"
        return "\(head)到\(tail)"
    }
}
