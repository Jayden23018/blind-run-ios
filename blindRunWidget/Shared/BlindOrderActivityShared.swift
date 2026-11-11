import ActivityKit
import Foundation

// MARK: - 盲人端「约跑进度」锁屏卡：两个 target 共用的那一份（#919）
//
// 🔴 本文件**同时属于 `blindRun` 与 `blindRunWidget`**：widget 画卡、app 起卡与单测都用它。
// 所以不能 `import` 任何只在 app target 里的东西（`RunOrderStatus` / `OrderDetailResponse` 都不行）——
// 订单状态到「卡上哪一屏」的映射在 app 侧 `BlindOrderActivityController.phase(...)`。
//
// 设计源：`docs/ui/mockups/live-activity-v7-20261111/`（负责人 2026-11-11 定稿）B1–B7、B10、B11。
// 卡分两段：
// - 第一段 匹配中 → 商量见面安排 → 已约好（推完 B4 就结束，锁屏留 15 分钟）。超 8 小时变灰（B10）。
// - 第二段 开跑前 30 分钟起 → 出发 → 已到达；开跑后交给跑步卡（`RunLiveActivityAttributes`）。
// 卡上不写名字（负责人原话「不需要说是谁来了」）。

@available(iOS 16.2, *)
struct BlindOrderActivityAttributes: ActivityAttributes, Hashable {

    struct ContentState: Codable, Hashable {
        var phase: BlindOrderActivityPhase
        /// 计划开跑时刻。B1「周三 7:00 开跑」、B4「明天 7:00 开跑」、B5 倒计时用。
        var plannedStart: Date?
        /// B3 确认见面安排的截止时刻（磨合窗口结束）。
        var confirmDeadline: Date?
        /// 见面地点的短名（负责人 11-11 定：照稿写地点）。取「具体在哪儿见」，没有就取出发地址。
        var placeName: String?
        /// 陪跑员上衣颜色（「蓝色」）。B7「穿蓝色上衣」。
        var volunteerTopColor: String?
        /// 陪跑员离见面点的直线距离（米）。只有订单页开着、拿到陪跑员实时位置时才有。
        var distanceMeters: Int?
        /// 陪跑员刚出发时的那个距离。小人位置 = 1 − 现在 / 出发时。
        var departureDistanceMeters: Int?
    }

    var orderID: Int64
    /// 这张卡是哪一段起的。**第一段到 8 小时变灰**，按这个时刻算 `staleDate`。
    var startedAt: Date
}

/// 卡上哪一屏。**开放枚举**：旧版本 App 起的卡被新版本认回、或反过来，未知值降级成「匹配中」
/// 而不是整条解码失败（那等于锁屏卡冻住）。同 `GuideRunAttributes.Phase` 的写法。
enum BlindOrderActivityPhase: String, Codable, Hashable, Sendable, CaseIterable {
    /// B1 正在找陪跑员。
    case matching
    /// B2 陪跑员已响应，先通电话商量。
    case talking
    /// B3 请确认见面安排。
    case confirmPlan
    /// B4 已约好 → 第一段收卡。
    case scheduled
    /// B5 开跑前 30 分钟（第二段起卡）。
    case preRun
    /// B6 陪跑员正在赶来。
    case enRoute
    /// B7 陪跑员到了。
    case arrived
    /// B11 取消。
    case cancelled
    /// B11 没找到陪跑员。
    case noVolunteer

    init(from decoder: Decoder) throws {
        let rawValue = try? decoder.singleValueContainer().decode(String.self)
        self = rawValue.flatMap(BlindOrderActivityPhase.init(rawValue:)) ?? .matching
    }

    /// 第二段（开跑前 30 分钟起）的卡排在第一段前面（`relevanceScore`）。
    var isSecondStage: Bool {
        switch self {
        case .preRun, .enRoute, .arrived: return true
        case .matching, .talking, .confirmPlan, .scheduled, .cancelled, .noVolunteer: return false
        }
    }

    /// 第一段里还在「找人 / 商量」的三屏：这三屏才有 8 小时变灰的问题。
    var isFindingStage: Bool {
        self == .matching || self == .talking || self == .confirmPlan
    }

    /// 推完这一屏就收卡。
    var endsCard: Bool {
        self == .scheduled || self == .cancelled || self == .noVolunteer
    }

    /// 稿「五、什么时候起卡」：找到陪跑员（B2）、请确认（B3）、出发（B6）、已到达（B7）带一次提醒（亮屏 + 声音）。
    var alertsOnEntry: Bool {
        switch self {
        case .talking, .confirmPlan, .enRoute, .arrived: return true
        case .matching, .scheduled, .preRun, .cancelled, .noVolunteer: return false
        }
    }
}

// MARK: - 时长与颜色

enum BlindOrderActivityTiming {
    /// 第二段起卡点：开跑前 30 分钟（负责人 2026-11-11 定）。
    static let preRunLead: TimeInterval = 30 * 60
    /// 第一段到点变灰（B10）。系统上限也是 8 小时，到点它会自己结束这张卡。
    static let findingStaleAfter: TimeInterval = 8 * 60 * 60
    /// B4 已约好、B11 取消 / 没找到：推完最后一屏后锁屏留 15 分钟。
    static let lingerAfterEnd: TimeInterval = 15 * 60
    /// 相关度：第二段的卡排在前。
    static let secondStageRelevance: Double = 100
    static let firstStageRelevance: Double = 50
}

/// 稿 `draft.html` `:root` 的几块颜色。实时活动在锁屏上永远是深色呈现。
enum BlindOrderActivityPalette {
    /// `--navy`：卡底。
    static let card: UInt32 = 0x1F2433
    /// `.la.stale`：B10 变灰、B11 取消。
    static let stale: UInt32 = 0x3A3F4B
    /// `--avBg` / `--avInk`：右侧通用人像。
    static let avatarBackground: UInt32 = 0xDDE6FF
    static let avatarInk: UInt32 = 0x1F3A66
    /// `--sub`：副标题白 64%。
    static let subtitleOpacity = 0.64
}

// MARK: - 文案

enum BlindOrderActivityCopy {
    static let appName = "助盲跑"
    static let matching = "正在找陪跑员"
    static let matchingWithoutTime = "找到后马上通知你"
    static let talking = "陪跑员已响应"
    static let talkingSubtitle = "先通电话，商量见面"
    static let confirmPlan = "请确认见面安排"
    static let scheduledFallback = "已约好"
    static let preRunSubtitle = "陪跑员还没出发"
    static let enRoute = "陪跑员正在赶来"
    static let enRouteWithoutDistance = "陪跑员已出发"
    static let arrived = "陪跑员到了"
    static let staleMatching = "还在找陪跑员"
    static let staleSubtitle = "打开 App 看最新进度"
    static let cancelled = "这次约跑已取消"
    static let noVolunteer = "这次没找到陪跑员"
    static let reorderSubtitle = "打开 App 可以重新约"
    static let you = "你"
    static let compactMatching = "找陪跑员"
    static let compactTalking = "商量中"
    static let compactScheduled = "已约好"
    static let compactArrived = "到了"
    static let compactCancelled = "已取消"

    /// 「7:00」。
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 读屏念的时刻：「7 点」「7 点 30 分」。
    static func spokenClock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(parts.hour ?? 0) 点" : "\(parts.hour ?? 0) 点 \(minute) 分"
    }

    /// 「今天 7:00」「明天 7:00」「周三 7:00」「11月20日 7:00」。
    ///
    /// 稿 B4 写「明早」，这里统一写「明天」：「明早 19:00」说不通，而开跑时刻什么点都有。
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        case 3...6:
            let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return weekdays[(calendar.component(.weekday, from: date) - 1) % 7]
        default:
            let parts = calendar.dateComponents([.month, .day], from: date)
            return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
        }
    }

    static func startsAt(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        "\(day(date, now: now, calendar: calendar)) \(clock(date, calendar: calendar)) 开跑"
    }

    static func spokenStartsAt(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        "\(day(date, now: now, calendar: calendar)) \(spokenClock(date, calendar: calendar))开跑"
    }

    /// 「300 米」「1.2 公里」「2 公里」。米档取整到 10 米；公里档一位小数，整数去掉 .0（负责人 11-08 定）。
    static func distance(_ meters: Int) -> String {
        let meters = max(meters, 0)
        guard meters >= 1_000 else {
            return "\(max((meters + 5) / 10 * 10, 10)) 米"
        }
        let km = (Double(meters) / 100).rounded() / 10
        return km == km.rounded() ? "\(Int(km)) 公里" : String(format: "%.1f 公里", km)
    }

    static func awayFromYou(_ meters: Int) -> String {
        "离你约 \(distance(meters))"
    }

    /// 「已约好，在朝阳公园南门」。
    static func scheduledSubtitle(place: String?) -> String {
        guard let place else { return scheduledFallback }
        return "\(scheduledFallback)，在\(place)"
    }

    /// 「在南门等你，穿蓝色上衣」；两样都没有时返回 `nil`（不出副标题）。
    static func arrivedSubtitle(place: String?, topColor: String?) -> String? {
        let parts = [place.map { "在\($0)等你" }, topColor.map { "穿\($0)上衣" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "，")
    }

    /// 看距离右端：「你 · 南门」。
    static func distanceEndLabel(place: String?) -> String {
        guard let place else { return you }
        return "\(you) · \(place)"
    }
}

// MARK: - 卡上要画什么（纯函数，app 与 widget 都用）

/// 把 `ContentState` 解成卡上每一处的文字。**widget 只照着画**，所以每一屏的字都能在 app target 的单测里逐字钉住。
@available(iOS 16.2, *)
struct BlindOrderActivityPresentation: Equatable {
    /// 标题里接一个系统自走倒计时（`Text(timerInterval:)`）的位置。
    enum Countdown: Equatable {
        /// B5：「29:58 后开跑」。
        case titlePrefix(until: Date, suffix: String)
        /// B3：副标题「还剩 8:59」。
        case subtitlePrefix(until: Date, prefix: String)
    }

    let title: String
    /// B7 照 Uber「Arriving Now」标题放大到 26pt。
    let titleIsLarge: Bool
    let subtitle: String?
    let countdown: Countdown?
    /// 右侧通用人像。B1 还没有人，不放；取消 / 变灰也不放。
    let showsAvatar: Bool
    let line: LiveActivityProgressMode?
    let background: UInt32
    /// 灵动岛紧凑态右侧那一个数 / 两三个字。有倒计时时 widget 画倒计时，这里是读屏用的静态值。
    let compactTrailing: String
    /// 找人那三屏左边是呼吸点，其余是人像。
    let compactShowsSearchingDot: Bool
    /// 锁屏卡、展开态整张念一站的那一句。
    let accessibilityLabel: String

    init(state: BlindOrderActivityAttributes.ContentState, isStale: Bool, now: Date = Date(), calendar: Calendar = .current) {
        let place = Self.trimmed(state.placeName)
        let topColor = Self.trimmed(state.volunteerTopColor)
        var countdown: Countdown?
        // 读屏念的标题 / 副标题。和屏幕上不同的只有两处：时刻念成「7 点」，系统自走的倒计时念成这一刻的「约 N 分钟」。
        var spokenTitle: String?
        var spokenSubtitle: String?
        background = (isStale || state.phase == .cancelled || state.phase == .noVolunteer)
            ? BlindOrderActivityPalette.stale
            : BlindOrderActivityPalette.card
        titleIsLarge = state.phase == .arrived && !isStale
        compactShowsSearchingDot = state.phase == .matching

        // B10：第一段找人的三屏到 8 小时变灰。别的屏不会 stale（第二段不设 staleDate）。
        if isStale && state.phase.isFindingStage {
            title = BlindOrderActivityCopy.staleMatching
            subtitle = BlindOrderActivityCopy.staleSubtitle
            self.countdown = nil
            showsAvatar = false
            line = nil
            compactTrailing = BlindOrderActivityCopy.compactMatching
            accessibilityLabel = "\(BlindOrderActivityCopy.appName)，\(title)，\(BlindOrderActivityCopy.staleSubtitle)"
            return
        }

        switch state.phase {
        case .matching:
            title = BlindOrderActivityCopy.matching
            subtitle = state.plannedStart.map { BlindOrderActivityCopy.startsAt($0, now: now, calendar: calendar) }
                ?? BlindOrderActivityCopy.matchingWithoutTime
            spokenSubtitle = state.plannedStart.map { BlindOrderActivityCopy.spokenStartsAt($0, now: now, calendar: calendar) }
            showsAvatar = false
            line = .steps(current: 1)
            compactTrailing = BlindOrderActivityCopy.compactMatching
        case .talking:
            title = BlindOrderActivityCopy.talking
            subtitle = BlindOrderActivityCopy.talkingSubtitle
            showsAvatar = true
            line = .steps(current: 2)
            compactTrailing = BlindOrderActivityCopy.compactTalking
        case .confirmPlan:
            title = BlindOrderActivityCopy.confirmPlan
            if let deadline = state.confirmDeadline, deadline > now {
                subtitle = nil
                countdown = .subtitlePrefix(until: deadline, prefix: "还剩 ")
                let minutes = max(Int((deadline.timeIntervalSince(now) / 60).rounded(.up)), 1)
                spokenSubtitle = "还剩约 \(minutes) 分钟"
            } else {
                subtitle = nil
            }
            showsAvatar = true
            line = .steps(current: 2)
            compactTrailing = BlindOrderActivityCopy.compactTalking
        case .scheduled:
            title = state.plannedStart.map { BlindOrderActivityCopy.startsAt($0, now: now, calendar: calendar) }
                ?? BlindOrderActivityCopy.scheduledFallback
            spokenTitle = state.plannedStart.map { BlindOrderActivityCopy.spokenStartsAt($0, now: now, calendar: calendar) }
            subtitle = BlindOrderActivityCopy.scheduledSubtitle(place: place)
            showsAvatar = true
            line = .steps(current: 3)
            compactTrailing = BlindOrderActivityCopy.compactScheduled
        case .preRun:
            if let start = state.plannedStart, start > now {
                title = "\(BlindOrderActivityCopy.clock(start, calendar: calendar)) 开跑"
                countdown = .titlePrefix(until: start, suffix: " 后开跑")
                let minutes = max(Int((start.timeIntervalSince(now) / 60).rounded(.up)), 1)
                spokenTitle = "\(minutes) 分钟后开跑"
                compactTrailing = "\(minutes) 分钟"
            } else {
                title = state.plannedStart.map { "\(BlindOrderActivityCopy.clock($0, calendar: calendar)) 开跑" }
                    ?? BlindOrderActivityCopy.scheduledFallback
                compactTrailing = BlindOrderActivityCopy.compactScheduled
            }
            subtitle = BlindOrderActivityCopy.preRunSubtitle
            showsAvatar = true
            line = .steps(current: 3)
        case .enRoute:
            title = BlindOrderActivityCopy.enRoute
            let progress = Self.walkerProgress(now: state.distanceMeters, departure: state.departureDistanceMeters)
            subtitle = state.distanceMeters.map { BlindOrderActivityCopy.awayFromYou($0) }
                ?? BlindOrderActivityCopy.enRouteWithoutDistance
            showsAvatar = true
            line = .distance(progress: progress, endLabel: BlindOrderActivityCopy.distanceEndLabel(place: place))
            compactTrailing = state.distanceMeters.map { BlindOrderActivityCopy.distance($0) } ?? BlindOrderActivityCopy.enRouteWithoutDistance
        case .arrived:
            title = BlindOrderActivityCopy.arrived
            subtitle = BlindOrderActivityCopy.arrivedSubtitle(place: place, topColor: topColor)
            showsAvatar = true
            line = .distance(progress: 1, endLabel: BlindOrderActivityCopy.distanceEndLabel(place: place))
            compactTrailing = BlindOrderActivityCopy.compactArrived
        case .cancelled, .noVolunteer:
            title = state.phase == .cancelled ? BlindOrderActivityCopy.cancelled : BlindOrderActivityCopy.noVolunteer
            subtitle = BlindOrderActivityCopy.reorderSubtitle
            showsAvatar = false
            line = nil
            compactTrailing = BlindOrderActivityCopy.compactCancelled
        }
        self.countdown = countdown

        // 读屏一站念完：「助盲跑，陪跑员正在赶来，离你约 300 米，陪跑员在路上，前往你 · 南门」。
        accessibilityLabel = [
            BlindOrderActivityCopy.appName,
            spokenTitle ?? title,
            spokenSubtitle ?? subtitle,
            line.map { $0.accessibilityLabel },
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }

    /// 去掉首尾空白，空串当没有。
    static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// 小人走到哪：1 − 现在距离 / 出发时距离。任一缺失 ⇒ 0（停在起点，「陪跑员已出发」）。
    static func walkerProgress(now: Int?, departure: Int?) -> Double {
        guard let now, let departure, departure > 0 else { return 0 }
        return LiveActivityProgressLine.clampedProgress(1 - Double(now) / Double(departure))
    }

    /// 灵动岛紧凑态 / 最小态的读屏标签（稿「三、灵动岛」：B1 读「助盲跑，正在找陪跑员」）。
    var compactAccessibilityLabel: String {
        "\(BlindOrderActivityCopy.appName)，\(title)"
    }
}
