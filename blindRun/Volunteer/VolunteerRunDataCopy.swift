import Foundation

// 跑步数据页（#710）上的全部文字与读屏摘要。只依赖 Foundation，单测直接断言整句。
//
// 读屏口径：每张图对读屏是**一个**元素，配一句摘要（定稿注的示例句）。
// 掩码姓名在屏幕上照原样显示（`李*`），只在念的句子里去掉星号（同首页「连续陪跑」卡）。

enum VolunteerRunDataCopy {
    static let navigationTitle = "连续陪跑"
    static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]
    static let deletedPartner = "已注销的跑者"
    /// 首页「连续陪跑」卡的读屏提示（卡点进来就是这一页）。
    static let homeCardHint = "打开连续陪跑，查看陪跑日历、里程和陪伴时长"

    // MARK: 数字

    /// 公里一位小数（「8.2」）。念的时候去掉「.0」：「8.0」念成「8点0」没有意义。
    static func km(_ value: Double, spoken: Bool = false) -> String {
        let text = String(format: "%.1f", value)
        guard spoken, text.hasSuffix(".0") else { return text }
        return String(text.dropLast(2))
    }

    static func km(metres: Int, spoken: Bool = false) -> String {
        km(Double(metres) / 1000, spoken: spoken)
    }

    /// 「6 小时 45 分钟」。
    static func duration(_ minutes: Int64) -> String {
        RunRecordHistoryViewModel.serviceDuration(max(0, minutes))
    }

    static func partner(_ name: String?, spoken: Bool) -> String {
        guard let name else { return deletedPartner }
        return spoken ? name.unmaskedForSpeech : name
    }

    private static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    // MARK: 结论卡

    static func streakTitle(partner name: String?) -> String {
        "和 \(partner(name, spoken: false)) 连续陪跑"
    }

    static let streakWeeksUnit = "周"

    static func streakProgress(_ display: PartnerStreakDisplay) -> String {
        display.isPersonalBest
            ? "这是你们最好的成绩"
            : "最好 \(display.bestWeeks) 周 · 还差 \(display.bestWeeks - display.currentWeeks) 周追平"
    }

    static func thisWeekLine(partner name: String?, credited: Bool, spoken: Bool = false) -> String {
        let who = partner(name, spoken: spoken)
        return credited
            ? "本周已经和 \(who) 跑过，这一周记上了"
            : "本周还没和 \(who) 一起跑，跑完一次就记上这一周"
    }

    static func streakSpoken(_ streak: VolunteerRunDataStreak, credited: Bool?) -> String {
        let who = partner(streak.partnerName, spoken: true)
        var parts = [
            "和 \(who) 连续陪跑 \(streak.display.currentWeeks) 周",
            streak.display.progressText
        ]
        if let credited { parts.append(thisWeekLine(partner: streak.partnerName, credited: credited, spoken: true)) }
        return parts.joined(separator: "。")
    }

    /// 本周七个圆一句话：「本周一、周三陪跑了」。
    static func weekDotsSpoken(_ dots: [VolunteerRunDataSummary.WeekDot]) -> String {
        let ran = dots.filter(\.ran).map { "周\(weekdayNames[$0.weekday])" }
        return ran.isEmpty ? "本周还没有陪跑" : "本周\(ran.joined(separator: "、"))陪跑了"
    }

    // MARK: 陪跑日历

    static let calendarTitle = "陪跑日历"
    static let calendarMeta = "近半年"
    static let daysRunLabel = "陪跑天数"
    static let longestLabel = "最长连续"
    static let longestCaption = "每周都有陪跑"
    static let dayUnit = "天"
    static let weekUnit = "周"
    static let legendLess = "少"
    static let legendMore = "多（按当天公里）"

    static func monthTitle(_ month: RunRecordMonth, current: RunRecordMonth) -> String {
        month.title(relativeTo: current)
    }

    /// 定稿原句：「近半年陪跑 47 天，最长连续 15 周。11 月 1 天：3 日。10 月 6 天：…」。
    static func calendarSpoken(_ summary: VolunteerRunDataSummary, current: RunRecordMonth) -> String {
        let head = "近半年陪跑 \(summary.daysRunInWindow) 天，最长连续 \(summary.longestWeeksInWindow) 周。"
        let months = summary.calendarMonths.map { entry -> String in
            let title = monthTitle(entry.month, current: current)
            guard !entry.days.isEmpty else { return "\(title)没有陪跑" }
            return "\(title) \(entry.days.count) 天：\(entry.days.map(String.init).joined(separator: "、")) 日"
        }
        return head + months.joined(separator: "。")
    }

    static func monthRowValue(_ days: Int) -> String {
        days == 0 ? "没有陪跑" : "跑了 \(days) 天"
    }

    // MARK: 里程

    static let mileageSection = "里程"
    static let totalLabel = "总计"
    static let weeklyAverageLabel = "平均每周"
    static let monthlyAverageLabel = "平均每月"
    static let kmUnit = "公里"
    static let cumulativeMileage = "累计里程"

    static func rangeTitle(_ range: VolunteerRunDataSummary.MileageRange) -> String {
        switch range {
        case .week: return "周"
        case .month: return "月"
        case .halfYear: return "半年"
        case .year: return "年"
        }
    }

    static func headlineLabel(_ range: VolunteerRunDataSummary.MileageRange) -> String {
        switch range {
        case .week, .month: return totalLabel
        case .halfYear: return weeklyAverageLabel
        case .year: return monthlyAverageLabel
        }
    }

    /// 图头那行日期：周「11月2日 – 8日」，月「2026年11月」，半年「2026年5月11日 – 11月8日」，年「2025年12月 – 2026年11月」。
    static func rangeText(_ series: VolunteerRunDataSummary.MileageSeries, calendar: Calendar) -> String {
        let start = calendar.dateComponents([.year, .month, .day], from: series.start)
        let end = calendar.dateComponents([.year, .month, .day], from: series.end)
        let (sy, sm, sd) = (start.year ?? 0, start.month ?? 0, start.day ?? 0)
        let (ey, em, ed) = (end.year ?? 0, end.month ?? 0, end.day ?? 0)
        switch series.range {
        case .week:
            if sy != ey { return "\(sy)年\(sm)月\(sd)日 – \(ey)年\(em)月\(ed)日" }
            return sm == em ? "\(sm)月\(sd)日 – \(ed)日" : "\(sm)月\(sd)日 – \(em)月\(ed)日"
        case .month:
            return "\(sy)年\(sm)月"
        case .halfYear:
            return sy == ey ? "\(sy)年\(sm)月\(sd)日 – \(em)月\(ed)日" : "\(sy)年\(sm)月\(sd)日 – \(ey)年\(em)月\(ed)日"
        case .year:
            return "\(sy)年\(sm)月 – \(ey)年\(em)月"
        }
    }

    static func mileageSpoken(_ series: VolunteerRunDataSummary.MileageSeries, calendar: Calendar) -> String {
        let range = rangeText(series, calendar: calendar).replacingOccurrences(of: " – ", with: "到")
        var parts = [
            "里程，\(rangeTitle(series.range))，\(range)",
            "\(headlineLabel(series.range)) \(km(series.headlineKm, spoken: true)) 公里"
        ]
        if let top = series.bars.max(by: { $0.value < $1.value }), top.value > 0 {
            switch series.range {
            case .week, .month:
                parts.append("最多的一天是 \(monthDay(top.start, calendar: calendar))，\(km(top.value, spoken: true)) 公里")
            case .halfYear:
                parts.append("最多的一周从 \(monthDay(top.start, calendar: calendar)) 开始，\(km(top.value, spoken: true)) 公里")
            case .year:
                let month = calendar.component(.month, from: top.start)
                parts.append("最多的是 \(month) 月，\(km(top.value, spoken: true)) 公里")
            }
        } else {
            parts.append("这段时间没有陪跑")
        }
        return parts.joined(separator: "。")
    }

    // MARK: 陪伴时长

    static let durationTitle = "陪伴时长"
    static let durationMeta = "近 6 个月"
    static let cumulativeDuration = "累计陪伴"

    static func durationSpoken(_ summary: VolunteerRunDataSummary, current: RunRecordMonth) -> String {
        var parts = ["陪伴时长，近 6 个月"]
        if let average = summary.averageServiceMinutes {
            parts.append("平均每月 \(duration(average))")
        }
        let months = summary.serviceMonths.map { entry -> String in
            let title = monthTitle(entry.month, current: current)
            guard let minutes = entry.minutes else { return "\(title)没加载出来" }
            return minutes == 0 ? "\(title)没有陪伴" : "\(title) \(duration(minutes))"
        }
        parts.append(months.joined(separator: "，"))
        return parts.joined(separator: "。")
    }

    // MARK: 提要

    static let highlightsSection = "提要"
    static let comparisonTitle = "里程"
    static let weekdayTitle = "常跑的日子"
    static let longestTitle = "最远的一次"

    static func comparison(_ value: VolunteerRunDataSummary.MonthComparison, spoken: Bool = false) -> String {
        let last = "\(value.lastMonth.month) 月"
        let previous = "\(value.previousMonth.month) 月"
        let difference = value.lastKm - value.previousKm
        let lastText = "\(last)你陪跑了 \(km(value.lastKm, spoken: spoken)) 公里"
        if abs(difference) < 0.05 { return "\(lastText)，和 \(previous)一样。" }
        return "\(lastText)，比 \(previous)\(difference > 0 ? "多" : "少") \(km(abs(difference), spoken: spoken)) 公里。"
    }

    static func favoriteWeekday(_ weekdays: [Int]) -> String {
        "近半年你最常在\(weekdays.map { "周\(weekdayNames[$0])" }.joined(separator: "和"))陪跑。"
    }

    static func weekdaySpoken(_ counts: [Int], favorite: [Int]) -> String {
        let list = counts.enumerated().map { "周\(weekdayNames[$0.offset]) \($0.element) 次" }.joined(separator: "，")
        return "\(weekdayTitle)。\(favoriteWeekday(favorite))\(list)"
    }

    static func longestDetail(_ run: VolunteerRunDataRun, calendar: Calendar) -> String {
        [monthDay(run.finishedAt, calendar: calendar), run.place].compactMap { $0 }.joined(separator: " · ")
    }

    static func longestSpoken(_ run: VolunteerRunDataRun, calendar: Calendar) -> String {
        [
            longestTitle,
            run.metres.map { "\(km(metres: $0, spoken: true)) 公里" },
            monthDay(run.finishedAt, calendar: calendar),
            run.place,
            "和 \(partner(run.partnerName, spoken: true))"
        ].compactMap { $0 }.joined(separator: "，")
    }

    // MARK: 一起跑的人

    static let partnersTitle = "一起跑的人"

    static func partnersHeadline(_ partners: [VolunteerRunDataSummary.PartnerCount], spoken: Bool = false) -> String {
        guard let top = partners.first else { return "近半年还没有和跑者一起跑过。" }
        return "近半年你和 \(partners.count) 位跑者一起跑过，和 \(partner(top.name, spoken: spoken)) 最多。"
    }

    static func partnersSpoken(_ partners: [VolunteerRunDataSummary.PartnerCount]) -> String {
        let list = partners.map { "\(partner($0.name, spoken: true)) \($0.count) 次" }.joined(separator: "，")
        return "\(partnersTitle)。\(partnersHeadline(partners, spoken: true))\(list)"
    }

    static func timesValue(_ count: Int) -> String { "\(count) 次" }

    // MARK: 个人纪录

    static let recordsSection = "个人纪录"
    static let recordsFootnote = "个人纪录按近 12 个月的陪跑算。"
    static let recordLongest = "最远一次"
    static let recordMostRuns = "单周最多"
    static let recordMostKm = "单周最远"
    static let recordLongestWeeks = "最长连续"

    // MARK: 页底

    static let partnersLinkTitle = "固定搭档"
    static let partnersLinkHint = "打开固定搭档列表"

    static func partnersLinkValue(_ count: Int) -> String { "\(max(0, count)) 位" }

    static let ruleFootnote = "你们每周至少一起跑完一次，就多记一周。断了从第 1 周重新算，最好成绩会保留。"

    // MARK: 加载

    static let loading = "正在加载跑步数据"

    static func partialFailure(_ count: Int) -> String {
        "有 \(count) 个月的记录没加载出来，图上这几个月是空的。"
    }

    static let allFailed = "跑步数据没加载出来，请检查网络后重试。"
    static let retry = "重试"
    static let empty = "近 12 个月还没有完成的陪跑。完成第一次陪跑后，这里会画出你的陪跑日历和里程。"
}
