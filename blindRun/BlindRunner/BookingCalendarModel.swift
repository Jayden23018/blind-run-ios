import Foundation

// MARK: - 约跑页的日历（#821，v5）
//
// v4 只有一排 7 个日期圆，月份那一排是装饰，点不了。v5 第三稿甲（负责人 2026-11-07 定）：
// - 一整排日期从今天排到可约的最后一天，一直能横滑；
// - 月份写在当月第一个日子上方，跟日期一起滑；
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

enum BookingCalendar {
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

    /// 读屏上下轻扫换一天：在能约的日子里前后走 `step` 天。还没选（或选的不在里面）时落到第一个能约的日子；
    /// 走到头返回 `nil`（不动）。
    static func step(from selected: Date?, by step: Int, in availableDays: [Date]) -> Date? {
        guard let first = availableDays.first else { return nil }
        guard let selected, let current = availableDays.firstIndex(of: selected) else { return first }
        let next = current + step
        return availableDays.indices.contains(next) ? availableDays[next] : nil
    }

    /// 日期条上方的月份字（第三稿甲）：写在条里第一个日子和每月 1 日上方，其余返回 `nil`。
    /// 跨年那个月写全「2027年1月」。
    static func monthLabel(for day: Date, in days: [Date], calendar: Calendar = .aidRunBackend) -> String? {
        guard let first = days.first else { return nil }
        let isFirstInStrip = calendar.isDate(day, inSameDayAs: first)
        guard isFirstInStrip || calendar.component(.day, from: day) == 1 else { return nil }
        let month = calendar.component(.month, from: day)
        let year = calendar.component(.year, from: day)
        return year == calendar.component(.year, from: first) ? "\(month)月" : "\(year)年\(month)月"
    }

    /// 卡底那句：「最多约 30 天内，最远到 12月7日」。
    static func rangeFootnote(now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> String {
        let latest = BookingSlotPlanner.latestStart(now: now, rules: rules)
        let month = calendar.component(.month, from: latest)
        let day = calendar.component(.day, from: latest)
        return "最多约 \(rules.maxLeadDays) 天内，最远到 \(month)月\(day)日"
    }
}
