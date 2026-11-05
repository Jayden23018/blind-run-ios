import Foundation

// 跑步数据页（#710）的输入：ISO 日历、周号、首页带进来的火花、解析后的一单。
// 汇总本身在 `VolunteerRunDataSummary.swift`。

// MARK: - 日历

extension Calendar {
    /// 跑步数据页用的日历：ISO 8601，本地时区。
    ///
    /// 🚩 不用 `Calendar.current`：中国大陆的公历 `firstWeekday` 是周日，按它分周的话，
    /// 周日那一单会被算进下一周，「本周七天」也会从周日开始。
    static var volunteerRunData: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}

/// ISO 周号（`2026-W45`）。
///
/// 🚨 后端 `lastCreditedWeek` 是 ISO 周字符串，**不是日期**：`2025-12-29` 属于 `2026-W01`。
/// 这里只把它拆成「年 + 周序号」两个整数来比，不拼成日期（`PartnerStreakResponse` 注释同一条）。
struct ISOWeekKey: Equatable {
    let year: Int
    let week: Int

    init(year: Int, week: Int) {
        self.year = year
        self.week = week
    }

    /// `date` 所在的那一周。`calendar` 必须是 ISO 8601 日历。
    init(containing date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        self.init(year: parts.yearForWeekOfYear ?? 0, week: parts.weekOfYear ?? 0)
    }

    /// 认 `2026-W45` 与 `2026-W5` 两种写法；别的形状一律 nil（不猜）。
    init?(_ raw: String) {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, let year = Int(parts[0]),
              parts[1].first == "W", let week = Int(parts[1].dropFirst()), (1...53).contains(week) else { return nil }
        self.init(year: year, week: week)
    }
}

// MARK: - 结论卡的火花

/// 首页「连续陪跑」卡上的那一条火花，原样带进数据页。
///
/// 🔴 **不在数据页重拉 `partners/streaks`**：重拉的结果在两次请求之间变了时，
/// 结论卡会和刚点的那张首页卡说两个不同的人（OpenSpec 设计第 2 条）。
struct VolunteerRunDataStreak: Equatable {
    let display: PartnerStreakDisplay
    /// 后端已掩码（`李*`）；对方注销为 nil。
    let partnerName: String?
    let lastCreditedWeek: String?

    /// 这一周记上没有。`lastCreditedWeek` 缺失或形状不认识时为 nil —— 那时结论卡不说这一句，
    /// 而不是默认「还没记上」（那是在替后端断言）。
    func isCreditedThisWeek(now: Date, calendar: Calendar) -> Bool? {
        guard let raw = lastCreditedWeek, let credited = ISOWeekKey(raw) else { return nil }
        return credited == ISOWeekKey(containing: now, calendar: calendar)
    }
}

// MARK: - 一单

/// 月度列表里的一条，解析成数据页要用的形状。`finishedAt` 解析不出的条目丢掉（没法归天）。
struct VolunteerRunDataRun: Equatable {
    let orderId: Int64
    let finishedAt: Date
    let metres: Int?
    let partnerName: String?
    let place: String?
    let thumbnail: [RunLatLng]?

    init?(item: RunHistoryItem) {
        guard let date = item.finishedAt.backendTimestamp else { return nil }
        orderId = item.orderId
        finishedAt = date
        metres = item.distanceM.map { max(0, $0) }
        partnerName = item.partnerName?.nilIfBlank
        place = item.place?.nilIfBlank
        thumbnail = item.thumbnail
    }

    init(orderId: Int64, finishedAt: Date, metres: Int?, partnerName: String?, place: String? = nil, thumbnail: [RunLatLng]? = nil) {
        self.orderId = orderId
        self.finishedAt = finishedAt
        self.metres = metres
        self.partnerName = partnerName
        self.place = place
        self.thumbnail = thumbnail
    }
}
