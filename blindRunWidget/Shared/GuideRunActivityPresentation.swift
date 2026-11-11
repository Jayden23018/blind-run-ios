import SwiftUI

// MARK: - 陪跑员实时活动：文案与「卡上要画什么」（#920）
//
// 🔴 同 `GuideRunActivityShared.swift`：本文件**同时属于 `blindRun` 与 `blindRunWidget`**，
// 不能 `import` 只在 app target 里的东西。

// MARK: - 文案

enum GuideRunActivityCopy {
    static let brand = "助盲跑 · 陪跑"
    static let spokenBrand = "助盲跑，陪跑"

    // V1 / V2
    static let introCallTitle = "给跑者打电话"
    static let introCallSubtitle = "商量见面"
    static let introCallCountdownPrefix = "商量见面，还剩 "
    static let introCallExpired = "打开 App 看最新进度"
    static let planSubmittedTitle = "等跑者确认"
    static let planSubmittedSubtitle = "见面安排已发出"
    static let compactPlanSubmitted = "等确认"

    // V3 / V4
    static let scheduledWithoutTime = "见面安排已约好"
    static let scheduledSubtitlePrefix = "已约好"
    static let timeToLeave = "该出发了"
    static let leaveOnTime = "记得按时出发"

    // V5 / V6
    static let departedWithoutEta = "已出发"
    static let arrivingNow = "马上到"
    static let arrivedFallback = "已到集合点"
    static let compactArrived = "到了"

    // 已结束
    static let endedTitle = "引导已结束"
    static let compactEnded = "已结束"

    // 按钮
    static let almostThere = "我快到了"
    static let waitFiveMinutes = "再等我 5 分钟"
    /// 稿 V6 原文：「让他的手机响起来」缩成「让他手机响」才放得下（DECISION 第 9 条）。
    static let ringRunner = "让他手机响"

    /// 「8 分钟后到」。四舍五入到 0 时说「马上到」，不说「0 分钟后到」。
    static func etaHeadline(minutes: Int?, late: Bool) -> String {
        guard let minutes else { return departedWithoutEta }
        guard minutes > 0 else { return arrivingNow }
        return late ? "约 \(minutes) 分钟后到" : "\(minutes) 分钟后到"
    }

    /// 快迟到时的副标题。晚到不足 1 分钟（或算不出来）时不写。
    static func lateSuffix(lateMinutes: Int?) -> String? {
        guard let lateMinutes, lateMinutes > 0 else { return nil }
        return "晚到约 \(lateMinutes) 分钟"
    }

    static func compactEta(minutes: Int?) -> String {
        guard let minutes else { return departedWithoutEta }
        return minutes > 0 ? "\(minutes) 分钟" : arrivingNow
    }

    /// 整句一律用「跑者」（DECISION 第 7 条：卡上不写名字）。
    static func runnerNear(meetingPoint: String) -> String {
        let place = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? "跑者已到集合点附近" : "跑者已到\(place)附近"
    }

    /// V6 标题「已到南门」。集合点名字空时说「已到集合点」。
    static func arrivedTitle(meetingPoint: String) -> String {
        let place = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? arrivedFallback : "已到\(place)"
    }

    /// V6 副标题（稿：「跑者就在 10 米内」）。档位取值同 App 内汇合页的距离档。
    /// `UNKNOWN` 与缺省不写 —— 锁屏上没地方解释「看不到位置」是什么意思。
    static func meetLine(distanceBucket: String?) -> String? {
        switch distanceBucket {
        case "WITHIN_10": return "跑者就在 10 米内"
        case "WITHIN_50": return "跑者就在 50 米内"
        case "WITHIN_100": return "跑者就在 100 米内"
        case "FAR": return "跑者还没到集合点"
        default: return nil
        }
    }

    /// V3 标题「明早 7:00 开跑」。今天 / 明早（中午前）/ 明天 / M月d日。
    static func scheduledTitle(plannedStart: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let plannedStart else { return scheduledWithoutTime }
        return "\(dayWord(plannedStart, now: now, calendar: calendar)) \(clock(plannedStart, calendar: calendar)) 开跑"
    }

    static func spokenScheduledTitle(plannedStart: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let plannedStart else { return scheduledWithoutTime }
        return "\(dayWord(plannedStart, now: now, calendar: calendar)) \(spokenClock(plannedStart, calendar: calendar))开跑"
    }

    private static func dayWord(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return calendar.component(.hour, from: date) < 12 ? "明早" : "明天"
        }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    /// V3 副标题「已约好，在朝阳公园南门」。
    static func scheduledSubtitle(meetingPoint: String) -> String {
        let place = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? scheduledSubtitlePrefix : "\(scheduledSubtitlePrefix)，在\(place)"
    }

    /// V4 标题「6:40 前出发」。
    static func leaveByTitle(_ leaveBy: Date, calendar: Calendar = .current) -> String {
        "\(clock(leaveBy, calendar: calendar)) 前出发"
    }

    /// V4 副标题「路上约 18 分钟」。
    static func travelLine(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return "路上约 \(minutes) 分钟"
    }

    /// 「6:57」。
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 读屏念的时间：「6 点 57 分」；整点念「7 点」。
    static func spokenClock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(parts.hour ?? 0) 点" : "\(parts.hour ?? 0) 点 \(minute) 分"
    }

    /// 读屏念剩余时间：「还剩约 19 分钟」。不足 1 分钟说「不到 1 分钟」。
    static func spokenRemaining(until deadline: Date, now: Date) -> String {
        let minutes = Int((deadline.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 1 ? "还剩不到 1 分钟" : "还剩约 \(minutes) 分钟"
    }
}

// MARK: - 卡上要画什么（纯函数，app 与 widget 都用）

/// 把 `ContentState` + attributes 解成卡上每一块的内容。**widget 只照着画**，
/// 所以 app target 的用例能把每一屏长什么样逐字钉住。
@available(iOS 16.2, *)
struct GuideRunActivityPresentation: Equatable {
    /// 主行右侧：通用人像（V1–V4）、一个按钮（V5 / V6），或什么都没有（已结束）。
    enum Trailing: Equatable {
        case person
        case action(GuideRunActivityAction)
        case none
    }

    var title: String
    /// V6「已到南门」照 Uber「Arriving Now」放大到 26pt。
    var titleIsLarge = false
    /// 快迟到 / 该出发了：标题转金色。
    var titleIsWarning = false
    var subtitle: String?
    /// 读屏念的副标题（与屏上不同时才有值，例如倒计时、时刻）。
    var spokenSubtitle: String?
    /// V1：副标题后面接一个系统自走的倒计时（`subtitle` 是前缀）。
    var subtitleCountdownTo: Date?
    var trailing = Trailing.person
    /// 底部进度线停在第几步；`nil` = 不画线。
    var step: Int?
    var background = GuideRunCardPalette.navy
    /// 灵动岛紧凑态右侧的那一个数。`compactCountdownTo` 有值时改画系统倒计时。
    var compactTrailing: String
    var compactCountdownTo: Date?
    var compactIsPositive = false
    /// 锁屏卡与展开态：除按钮外整块一站念完。
    var accessibilityLabel = ""
    /// 紧凑态与最小态。
    var compactAccessibilityLabel = ""

    var actions: [GuideRunActivityAction] {
        if case .action(let action) = trailing { return [action] }
        return []
    }

    init(
        attributes: GuideRunAttributes,
        state: GuideRunAttributes.ContentState,
        isStale: Bool = false,
        now: Date = Date()
    ) {
        switch state.phase {
        case .introCall: self = Self.introCall(state, isStale: isStale, now: now)
        case .planSubmitted: self = Self.planSubmitted()
        case .scheduled: self = Self.scheduled(attributes, now: now)
        case .preStart: self = Self.preStart(attributes, state, isStale: isStale, now: now)
        case .departed, .late: self = Self.departed(attributes, state)
        case .arrived: self = Self.arrived(attributes, state)
        case .ended: self = Self.ended()
        }
        let spokenTitle = state.phase == .scheduled
            ? GuideRunActivityCopy.spokenScheduledTitle(plannedStart: attributes.plannedStart, now: now)
            : title
        let spokenLines = [GuideRunActivityCopy.spokenBrand, spokenTitle, spokenSubtitle ?? subtitle]
        accessibilityLabel = (spokenLines + [step.map { LiveActivityProgressMode.steps(current: $0).accessibilityLabel }])
            .compactMap { $0 }
            .joined(separator: "，")
        compactAccessibilityLabel = spokenLines.compactMap { $0 }.joined(separator: "，")
    }

    private init(title: String, compactTrailing: String) {
        self.title = title
        self.compactTrailing = compactTrailing
    }

    // MARK: 每一屏

    /// V1 商量见面。
    private static func introCall(_ state: GuideRunAttributes.ContentState, isStale: Bool, now: Date) -> Self {
        var view = Self(title: GuideRunActivityCopy.introCallTitle, compactTrailing: GuideRunActivityCopy.introCallSubtitle)
        view.step = 2
        if let deadline = state.deadline, !isStale, deadline > now {
            view.subtitle = GuideRunActivityCopy.introCallCountdownPrefix
            view.subtitleCountdownTo = deadline
            view.compactCountdownTo = deadline
            view.spokenSubtitle = "\(GuideRunActivityCopy.introCallSubtitle)，\(GuideRunActivityCopy.spokenRemaining(until: deadline, now: now))"
        } else {
            // 过了截止时刻（staleDate）还停在倒计时，会让「还剩 00:00」一直挂在锁屏上。
            view.subtitle = state.deadline == nil ? GuideRunActivityCopy.introCallSubtitle : GuideRunActivityCopy.introCallExpired
        }
        return view
    }

    /// V2 已交安排单。
    private static func planSubmitted() -> Self {
        var view = Self(title: GuideRunActivityCopy.planSubmittedTitle, compactTrailing: GuideRunActivityCopy.compactPlanSubmitted)
        view.subtitle = GuideRunActivityCopy.planSubmittedSubtitle
        view.step = 2
        return view
    }

    /// V3 已约好。
    private static func scheduled(_ attributes: GuideRunAttributes, now: Date) -> Self {
        var view = Self(
            title: GuideRunActivityCopy.scheduledTitle(plannedStart: attributes.plannedStart, now: now),
            compactTrailing: attributes.plannedStart.map { GuideRunActivityCopy.clock($0) } ?? GuideRunActivityCopy.scheduledSubtitlePrefix
        )
        view.subtitle = GuideRunActivityCopy.scheduledSubtitle(meetingPoint: attributes.meetingPointName)
        view.step = 3
        return view
    }

    /// V4 开跑前 30 分钟。过了建议出发时刻（staleDate）标题转金色「该出发了」（稿 V4 注）。
    private static func preStart(
        _ attributes: GuideRunAttributes, _ state: GuideRunAttributes.ContentState, isStale: Bool, now: Date
    ) -> Self {
        let startClock = attributes.plannedStart.map { GuideRunActivityCopy.clock($0) }
        let pastLeaveBy = state.leaveBy.map { isStale || $0 <= now } ?? false
        var view = Self(
            title: startClock.map { "\($0) 开跑" } ?? GuideRunActivityCopy.leaveOnTime,
            compactTrailing: pastLeaveBy ? GuideRunActivityCopy.timeToLeave : startClock ?? GuideRunActivityCopy.leaveOnTime
        )
        view.step = 3
        if pastLeaveBy {
            view.title = GuideRunActivityCopy.timeToLeave
            view.titleIsWarning = true
            view.subtitle = GuideRunActivityCopy.travelLine(minutes: state.travelMinutes)
        } else if let leaveBy = state.leaveBy {
            view.title = GuideRunActivityCopy.leaveByTitle(leaveBy)
            view.subtitle = GuideRunActivityCopy.travelLine(minutes: state.travelMinutes)
        } else if startClock != nil {
            // 陪跑员没有位置记录时后端不发建议出发时刻：退到开跑时刻，不编一个出发时间。
            view.subtitle = GuideRunActivityCopy.leaveOnTime
        }
        // 过了出发时刻紧凑态改写「该出发了」，不再画到开跑的倒计时（画的要和念的一致）。
        if !pastLeaveBy, let plannedStart = attributes.plannedStart, plannedStart > now {
            view.compactCountdownTo = plannedStart
        }
        return view
    }

    /// V5 出发（含快迟到）。右侧只有「我快到了」，不画线（稿四）。
    private static func departed(_ attributes: GuideRunAttributes, _ state: GuideRunAttributes.ContentState) -> Self {
        let isLate = state.phase == .late
        var view = Self(
            title: GuideRunActivityCopy.etaHeadline(minutes: state.etaMinutes, late: isLate),
            compactTrailing: GuideRunActivityCopy.compactEta(minutes: state.etaMinutes)
        )
        view.titleIsWarning = isLate
        view.trailing = .action(.almostThere)
        let lateMinutes: Int? = isLate
            ? zip2(state.arriveAt, attributes.plannedStart).map { Int(($0.timeIntervalSince($1) / 60).rounded()) }
            : nil
        if let late = GuideRunActivityCopy.lateSuffix(lateMinutes: lateMinutes) {
            view.subtitle = late
        } else if state.runnerNearMeetingPoint {
            view.subtitle = GuideRunActivityCopy.runnerNear(meetingPoint: attributes.meetingPointName)
        } else if let arriveAt = state.arriveAt {
            view.subtitle = "预计 \(GuideRunActivityCopy.clock(arriveAt)) 到"
            view.spokenSubtitle = "预计 \(GuideRunActivityCopy.spokenClock(arriveAt))到"
        }
        return view
    }

    /// V6 已到达。右侧只有「让他手机响」。
    private static func arrived(_ attributes: GuideRunAttributes, _ state: GuideRunAttributes.ContentState) -> Self {
        var view = Self(
            title: GuideRunActivityCopy.arrivedTitle(meetingPoint: attributes.meetingPointName),
            compactTrailing: GuideRunActivityCopy.compactArrived
        )
        view.titleIsLarge = true
        view.subtitle = GuideRunActivityCopy.meetLine(distanceBucket: state.distanceBucket)
        view.trailing = .action(.ringRunner)
        view.compactIsPositive = true
        return view
    }

    /// 后端 `end` 推送之后锁屏还留 5 分钟：灰底、不留任何旧数字和按钮。
    private static func ended() -> Self {
        var view = Self(title: GuideRunActivityCopy.endedTitle, compactTrailing: GuideRunActivityCopy.compactEnded)
        view.trailing = .none
        view.background = GuideRunCardPalette.ended
        return view
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
