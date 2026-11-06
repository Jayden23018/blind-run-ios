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

enum BookingSlotPlanner {
    /// 今天的时段被提前量裁过后，至少还要剩这么多分钟才给选（OpenSpec `blind-booking-match-first`）。
    static let minimumUsableMinutes = 60
    /// 具体时刻的间隔。
    static let startTimeStepMinutes = 30
    /// 具体时刻之后至少还要留这么多分钟跑步，否则那个时刻不给选。
    static let minimumRunMinutes = 30

    /// 可约的日期：今天起连续 `maximumBookingLeadDays` 天，每个元素是北京时间的日初。
    static func days(now: Date, calendar: Calendar = .aidRunBackend) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<AppConstants.Timing.maximumBookingLeadDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    /// 某天某段实际能约的时间范围：起点被「现在 + 最小提前量」裁过并取整到 5 分钟，终点不动，
    /// 也不超过最远可约时刻。剩不到 `minimumUsableMinutes` 返回 `nil`（该段不可选）。
    static func window(
        day: Date, slot: BookingDaySlot, now: Date, calendar: Calendar = .aidRunBackend
    ) -> (start: Date, end: Date)? {
        guard let slotStart = calendar.date(bySettingHour: slot.hours.start, minute: 0, second: 0, of: day),
              let slotEnd = calendar.date(bySettingHour: slot.hours.end, minute: 0, second: 0, of: day) else { return nil }
        let earliest = roundedUp(
            now.addingTimeInterval(TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60)),
            stepMinutes: 5, calendar: calendar
        )
        let latest = now.addingTimeInterval(TimeInterval(AppConstants.Timing.maximumBookingLeadDays * 24 * 3600))
        let start = max(slotStart, earliest)
        guard start <= latest, slotEnd.timeIntervalSince(start) >= TimeInterval(minimumUsableMinutes * 60) else { return nil }
        return (start, slotEnd)
    }

    /// 该段里可选的具体时刻：每 30 分钟一个，从段内第一个整半点起，到「结束前 30 分钟」为止。
    static func startTimes(
        day: Date, slot: BookingDaySlot, now: Date, calendar: Calendar = .aidRunBackend
    ) -> [Date] {
        guard let range = window(day: day, slot: slot, now: now, calendar: calendar) else { return [] }
        var times: [Date] = []
        var time = roundedUp(range.start, stepMinutes: startTimeStepMinutes, calendar: calendar)
        let last = range.end.addingTimeInterval(-TimeInterval(minimumRunMinutes * 60))
        while time <= last {
            times.append(time)
            time = time.addingTimeInterval(TimeInterval(startTimeStepMinutes * 60))
        }
        return times
    }

    /// 某天有没有任何一段能约。
    static func isDayAvailable(_ day: Date, now: Date, calendar: Calendar = .aidRunBackend) -> Bool {
        BookingDaySlot.allCases.contains { window(day: day, slot: $0, now: now, calendar: calendar) != nil }
    }

    /// 打开页面时默认选中的：最早一个还能约的日期里最早一段。
    static func defaultSelection(now: Date, calendar: Calendar = .aidRunBackend) -> (day: Date, slot: BookingDaySlot)? {
        for day in days(now: now, calendar: calendar) {
            if let slot = BookingDaySlot.allCases.first(where: { window(day: day, slot: $0, now: now, calendar: calendar) != nil }) {
                return (day, slot)
            }
        }
        return nil
    }

    /// 组出要提交的那一段。选中的时刻不在这一段里（换了日期或时段后残留）时丢掉它。
    static func makeSlot(
        day: Date, slot: BookingDaySlot, preferredStart: Date?, now: Date, calendar: Calendar = .aidRunBackend
    ) -> BookingFlexibleSlot? {
        guard let range = window(day: day, slot: slot, now: now, calendar: calendar) else { return nil }
        let valid = preferredStart.flatMap { time in
            startTimes(day: day, slot: slot, now: now, calendar: calendar).contains(time) ? time : nil
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
