import Foundation

// MARK: - 约跑「先匹配后商量」的日期与时段（#806，模拟图 v4 B1）
//
// 盲人只选「哪天 + 上午 / 下午 / 傍晚」，具体几点可选可不选。订单把选中的时段整段发给后端
// （`timeFlexible = true`），准点由陪跑员通话后填进见面安排单。
// 本文件只放纯判定，`now` / `calendar` 走参数，跨午夜、提前量裁剪都能被单测钉住。

/// 三个时段。取值是产品决定（负责人 2026-11-06 同意 v4）：中午 11–13 点不给，傍晚止于 21 点
/// （22:00–05:00 不能跑，见 `AppConstants.Timing.nightWindowStartHour`）。每段 ≤ 300 分钟（后端时长上限）。
nonisolated enum BookingDaySlot: String, CaseIterable, Sendable, Identifiable {
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "上午"
        case .afternoon: return "下午"
        case .evening: return "傍晚"
        }
    }

    /// 北京时间的起止钟点。
    var hours: (start: Int, end: Int) {
        switch self {
        case .morning: return (6, 11)
        case .afternoon: return (13, 17)
        case .evening: return (17, 21)
        }
    }
}

/// 盲人选中的那一段：发给后端的 `plannedStartTime`–`plannedEndTime` 与可选的 `preferredStartTime`。
nonisolated struct BookingFlexibleSlot: Equatable, Sendable {
    let day: Date
    let slot: BookingDaySlot
    let start: Date
    let end: Date
    var preferredStart: Date?
}

/// 约跑页用到的两条后端规则（#821）：最远可约几天、值守时段。都从 `GET /api/config/rules` 来。
/// 这里只决定界面上给不给选；能不能下单仍以 `POST /api/orders` 的返回为准。
nonisolated struct BookingRules: Equatable, Sendable {
    /// 开跑时间最晚是「现在 + 这么多天」（后端 `app.order.max-lead-days`，超出回 422 `APPOINTMENT_TOO_FAR`）。
    let maxLeadDays: Int
    /// `nil` = 不按值守时段裁：没有限制，或下发了但读不出来（见 `LaunchScopeResponse.dutyMinuteRanges`）。
    let dutyRanges: [LaunchScopeResponse.DutyMinuteRange]?

    init(maxLeadDays: Int, dutyRanges: [LaunchScopeResponse.DutyMinuteRange]? = nil) {
        self.maxLeadDays = maxLeadDays
        self.dutyRanges = dutyRanges
    }

    @MainActor
    init(appState: AppState) {
        self.init(
            maxLeadDays: appState.ruleParams.maxLeadDays,
            dutyRanges: appState.ruleParamsResponse?.launchScope?.dutyMinuteRanges()
        )
    }
}

/// 某段为什么不能选。界面上写在时段名下面。
nonisolated enum BookingSlotUnavailableReason: Equatable, Sendable {
    /// 这一天这一段整段不在值守时段里。
    case offDuty
    /// 时间已过或不够提前量。
    case passed
    /// 超出最远可约天数。
    case tooFar

    var text: String {
        switch self {
        case .offDuty: return "不在值守时间"
        case .passed: return "已过"
        case .tooFar: return "超出可约范围"
        }
    }
}

enum BookingSlotPlanner {
    /// 今天的时段被提前量裁过后，至少还要剩这么多分钟才给选（OpenSpec `blind-booking-match-first`）。
    static let minimumUsableMinutes = 60
    /// 具体时刻的间隔。
    static let startTimeStepMinutes = 30
    /// 具体时刻之后至少还要留这么多分钟跑步，否则那个时刻不给选。
    static let minimumRunMinutes = 30

    /// 开跑时间最晚到这一刻（后端判 `plannedStartTime` 不晚于「现在 + maxLeadDays 天」）。
    static func latestStart(now: Date, rules: BookingRules) -> Date {
        now.addingTimeInterval(TimeInterval(rules.maxLeadDays * 24 * 3600))
    }

    /// 可约范围内的日期：今天起，到「最晚开跑时刻」所在那天为止，每个元素是北京时间的日初。
    /// 最后一天可能只有一部分能约，由 `window` 再判。
    static func days(now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.startOfDay(for: latestStart(now: now, rules: rules))
        let count = calendar.dateComponents([.day], from: today, to: lastDay).day ?? 0
        return (0...max(count, 0)).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// 某天某段只看值守时段时的范围（不管现在几点）。没有值守限制时就是整段。
    /// 一段里碰到几块值守时段时，取最早一块够 `minimumUsableMinutes` 的（订单只能是连续的一段）。
    static func dutyWindow(
        day: Date, slot: BookingDaySlot, rules: BookingRules, calendar: Calendar = .aidRunBackend
    ) -> (start: Date, end: Date)? {
        guard let slotStart = calendar.date(bySettingHour: slot.hours.start, minute: 0, second: 0, of: day),
              let slotEnd = calendar.date(bySettingHour: slot.hours.end, minute: 0, second: 0, of: day) else { return nil }
        guard let ranges = rules.dutyRanges else { return (slotStart, slotEnd) }
        let weekday = calendar.component(.weekday, from: day)
        let dayStart = calendar.startOfDay(for: day)
        let candidates: [(start: Date, end: Date)] = ranges
            .filter { $0.weekdays.contains(weekday) }
            .map { range in
                (max(slotStart, dayStart.addingTimeInterval(TimeInterval(range.startMinute * 60))),
                 min(slotEnd, dayStart.addingTimeInterval(TimeInterval(range.endMinute * 60))))
            }
            .filter { $0.end.timeIntervalSince($0.start) >= TimeInterval(minimumUsableMinutes * 60) }
            .sorted { $0.start < $1.start }
        return candidates.first
    }

    /// 某天某段实际能约的时间范围：先按值守时段裁，再把起点裁到「现在 + 最小提前量」并取整到 5 分钟，
    /// 起点不晚于最晚开跑时刻。剩不到 `minimumUsableMinutes` 返回 `nil`（该段不可选）。
    static func window(
        day: Date, slot: BookingDaySlot, now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend
    ) -> (start: Date, end: Date)? {
        guard let duty = dutyWindow(day: day, slot: slot, rules: rules, calendar: calendar) else { return nil }
        let earliest = roundedUp(
            now.addingTimeInterval(TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60)),
            stepMinutes: 5, calendar: calendar
        )
        let start = max(duty.start, earliest)
        guard start <= latestStart(now: now, rules: rules),
              duty.end.timeIntervalSince(start) >= TimeInterval(minimumUsableMinutes * 60) else { return nil }
        return (start, duty.end)
    }

    /// 某段不能选的原因。能选时返回 `nil`。
    static func unavailableReason(
        day: Date, slot: BookingDaySlot, now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend
    ) -> BookingSlotUnavailableReason? {
        guard window(day: day, slot: slot, now: now, rules: rules, calendar: calendar) == nil else { return nil }
        guard let duty = dutyWindow(day: day, slot: slot, rules: rules, calendar: calendar) else { return .offDuty }
        return duty.start > latestStart(now: now, rules: rules) ? .tooFar : .passed
    }

    /// 该段里可选的具体时刻：每 30 分钟一个，从段内第一个整半点起，到「结束前 30 分钟」为止，
    /// 且不晚于最晚开跑时刻（后端对 `preferredStartTime` 同样判最远天数）。
    static func startTimes(
        day: Date, slot: BookingDaySlot, now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend
    ) -> [Date] {
        guard let range = window(day: day, slot: slot, now: now, rules: rules, calendar: calendar) else { return [] }
        var times: [Date] = []
        var time = roundedUp(range.start, stepMinutes: startTimeStepMinutes, calendar: calendar)
        let last = min(
            range.end.addingTimeInterval(-TimeInterval(minimumRunMinutes * 60)),
            latestStart(now: now, rules: rules)
        )
        while time <= last {
            times.append(time)
            time = time.addingTimeInterval(TimeInterval(startTimeStepMinutes * 60))
        }
        return times
    }

    /// 某天有没有任何一段能约。
    static func isDayAvailable(_ day: Date, now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend) -> Bool {
        BookingDaySlot.allCases.contains { window(day: day, slot: $0, now: now, rules: rules, calendar: calendar) != nil }
    }

    /// 某天的第一个能约的时段。
    static func firstAvailableSlot(
        day: Date, now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend
    ) -> BookingDaySlot? {
        BookingDaySlot.allCases.first { window(day: day, slot: $0, now: now, rules: rules, calendar: calendar) != nil }
    }

    /// 打开页面时默认选中的：最早一个还能约的日期里最早一段。
    static func defaultSelection(
        now: Date, rules: BookingRules, calendar: Calendar = .aidRunBackend
    ) -> (day: Date, slot: BookingDaySlot)? {
        for day in days(now: now, rules: rules, calendar: calendar) {
            if let slot = firstAvailableSlot(day: day, now: now, rules: rules, calendar: calendar) {
                return (day, slot)
            }
        }
        return nil
    }

    /// 组出要提交的那一段。选中的时刻不在这一段里（换了日期或时段后残留）时丢掉它。
    static func makeSlot(
        day: Date, slot: BookingDaySlot, preferredStart: Date?, now: Date, rules: BookingRules,
        calendar: Calendar = .aidRunBackend
    ) -> BookingFlexibleSlot? {
        guard let range = window(day: day, slot: slot, now: now, rules: rules, calendar: calendar) else { return nil }
        let valid = preferredStart.flatMap { time in
            startTimes(day: day, slot: slot, now: now, rules: rules, calendar: calendar).contains(time) ? time : nil
        }
        return BookingFlexibleSlot(day: day, slot: slot, start: range.start, end: range.end, preferredStart: valid)
    }

    static func roundedUp(_ date: Date, stepMinutes: Int, calendar: Calendar = .aidRunBackend) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        guard let minute = components.minute else { return date }
        let hasRemainder = minute % stepMinutes != 0 || (components.second ?? 0) > 0 || (components.nanosecond ?? 0) > 0
        var floored = components
        floored.minute = minute - minute % stepMinutes
        floored.second = 0
        floored.nanosecond = 0
        guard let base = calendar.date(from: floored) else { return date }
        return hasRemainder ? base.addingTimeInterval(TimeInterval(stepMinutes * 60)) : base
    }
}

/// 约跑页（#806）的钟点与日期说法。屏幕上「8:30」「周五」，读屏「明天，11 月 7 日，周五」。
enum BookingSlotText {

    static func clock(_ date: Date) -> String {
        DateFormatter.aidRunDisplayClock.string(from: date)
    }

    static func weekdayName(_ day: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[Calendar.aidRunBackend.component(.weekday, from: day) - 1]
    }

    /// 读屏念的日期：「明天，11 月 7 日，周五」。相对说法只到后天，理由同 `RunPlanFormat.shortStart`。
    static func spokenDay(_ day: Date, now: Date) -> String {
        let calendar = Calendar.aidRunBackend
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 99
        let relatives = ["今天", "明天", "后天"]
        let relative = relatives.indices.contains(offset) ? relatives[offset] + "，" : ""
        return "\(relative)\(calendar.component(.month, from: day)) 月 \(calendar.component(.day, from: day)) 日，\(weekdayName(day))"
    }
}
