import ActivityKit
import AppIntents
import SwiftUI

// MARK: - 陪跑员实时活动（V1–V6）：两个 target 共用的那一份
//
// 🔴 与 `RunLiveActivityShared.swift` 同一条硬约束：本文件**同时属于 `blindRun` 与 `blindRunWidget`**，
// 所以不能 `import` 任何只在 app target 里的东西（`AppColors` / `OrderDetailResponse` /
// `QuickMessageCode` 都不行）。
//
// 设计源：`docs/ui/mockups/live-activity-v7-20261111/`「四、陪跑员端」V1–V6 与「五」起卡表（#920）。
// 这张卡分两段（DECISION 第 3 条）：
// - 第一段：响应派单成功本地起 → V1 商量见面 → V2 已交安排单 → V3 已约好（推这一屏后收卡）；
// - 第二段：开跑前 30 分钟起 → V4 待出发 → V5 出发 → V6 已到达；开跑时收卡，跑步卡（V7）由
//   `RunLiveActivity*` 接上。
// 出发 / 到达两态还由后端经 APNs 推 `update` / `end`（`pushType: .token`，后端 `docs/live-activity.md`）。

@available(iOS 16.2, *)
struct GuideRunAttributes: ActivityAttributes, Hashable {

    /// 后端推送的 `content-state` 与这里**逐字段对应**（后端 `docs/live-activity.md`）。
    ///
    /// 🚨 **不能给它配自定义解码策略**：系统解推送载荷用的是默认 `JSONDecoder`，
    /// 所以 `arriveAt` 是 `Date` 默认编码 = **2001 纪元秒**（后端 issue #434）。
    /// 可选字段可能是 `null` 也可能整键缺省（后端 Gson 默认不写 null）——
    /// 合成的 `Decodable` 对可选属性走 `decodeIfPresent`，两种都能解，
    /// 用例 `GuideRunActivityTests` 用后端文档里的样例钉住。
    struct ContentState: Codable, Hashable {
        var phase: Phase
        var etaMinutes: Int?
        var arriveAt: Date?
        /// 引导进度，后端夹在 [0.1, 0.85]。v4 卡上不再画引导绳，字段留着是因为后端推送里有它。
        var progress: Double
        var runnerNearMeetingPoint: Bool
        /// 只在汇合时有值，开放枚举（`WITHIN_10` / `WITHIN_50` / `WITHIN_100` / `FAR` / `UNKNOWN`）。
        var distanceBucket: String?

        // ⚠️ 以下三项**只由 App 本地填**（后端推送里没有），一律可选 + 默认 `nil`：
        // 后端推送不带它们照样能解，既有构造点也不必改。

        /// V1 商量见面的截止时刻（`IntroCallView.windowEndsAt`）。卡上系统自走倒计时，也是 staleDate。
        var deadline: Date? = nil
        /// V4 建议出发时刻（`OrderDetailResponse.suggestedDepartAt`）。到点卡片转「该出发了」。
        var leaveBy: Date? = nil
        /// V4 路上要多久（`OrderDetailResponse.travelMinutes`）。
        var travelMinutes: Int? = nil
    }

    /// **响应向开放枚举**：后端加了新值时不许整条更新解码失败（那等于锁屏卡冻住），
    /// 不认识的一律按 `departed` 画 —— 「正在赶去」对任何未知的在途状态都不说错话。
    enum Phase: String, Codable, Hashable {
        // 第一段（App 本地，后端从不推这四个值）。
        /// V1 商量见面安排（`PENDING_INTRO_CALL`，还没交安排单）。
        case introCall
        /// V2 已交安排单，等跑者确认。
        case planSubmitted
        /// V3 已约好（`SCHEDULED_CONFIRMED`）。第一段最后一屏。
        case scheduled
        // 第二段。
        /// V4 开跑前 30 分钟，还没出发（App 本地）。
        case preStart
        /// 后端 `end` 推送的 `content-state` 带 `"ended"` ⇒ 画「已结束」样式。
        /// **不能按 `activityState == .ended` 判**：`ActivityViewContext` 只有 `attributes` /
        /// `state` / `isStale` / `activityID`（iOS 26.2 SDK 的 WidgetKit swiftinterface 核过），
        /// `activityState` 只在 app 侧的 `Activity<_>` 上，widget 读不到。
        case ended
        /// V5 出发（准时）。
        case departed
        /// V5 出发（快迟到）。
        case late
        /// V6 已到达。
        case arrived

        init(from decoder: Decoder) throws {
            let rawValue = try? decoder.singleValueContainer().decode(String.self)
            self = rawValue.flatMap(Phase.init(rawValue:)) ?? .departed
        }

        /// 第一段的三屏。第二段的卡与它们互不覆盖（见 `GuideRunActivityController`）。
        var isFirstSegment: Bool {
            self == .introCall || self == .planSubmitted || self == .scheduled
        }

        /// 后端 `/api/devices/live-activity-token` 只在 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` 收 token
        /// （其余状态 409 `ORDER_STATUS_NOT_ALLOWED`）。V4 就起的卡先存 token，到这三个值再传。
        var acceptsPushToken: Bool {
            self == .departed || self == .late || self == .arrived
        }
    }

    var orderID: Int64
    /// 跑者姓氏。v4 起**卡上不写名字**（DECISION 第 7 条），字段留着只为旧卡认回时 attributes 能解。
    var runnerSurname: String?
    var meetingPointName: String
    /// 计划开跑时刻。V3 / V4 的标题与「晚到约 N 分钟」（`arriveAt − plannedStart`，
    /// 后端 `EtaView.deltaVsStartMinutes` 同一个口径）都靠它。
    var plannedStart: Date?
}

// MARK: - 状态色（跑步卡仍在用）

/// 跑步卡的状态色（交付包 `01-design-tokens.md`）。
///
/// widget target 编译不到 `AppColors`，所以这里是第二份取值，**必须与 `AppColors.Flow` 同名色同值**。
/// 取**暗色档**（实时活动在锁屏上永远是深色呈现，不跟随系统亮暗，同 `RunLiveActivityPalette`）。
/// 两份之间的连接是 `GuideRunActivityTests.testStatePaletteMatchesTheFlowPaletteDarkTones`。
/// v4 起陪跑员出发 / 汇合卡改用 `GuideRunCardPalette`，这里的出发 / 汇合色只剩对撞用例在读。
enum LiveActivityStatePalette {
    /// 出发、快迟到：主蓝。
    static let stateDeparted: UInt32 = 0x2A5BD7
    /// 汇合：琥珀（暗色档 `#AD5210`，亮色档 `#A04B0C` 压暗色卡面对比度不够）。
    static let stateArrived: UInt32 = 0xAD5210
    /// 跑步中：青绿。
    static let stateRunning: UInt32 = 0x0A6B72
    /// 跑步中 · 已暂停：灰。
    static let statePaused: UInt32 = 0x4B5263
    /// 快迟到的 ETA 文字、并肩后的绳子。
    static let gold: UInt32 = 0xFFD978

    /// 彩色底上的白字四档（`onHeroStrong / Body / Eyebrow / Track`）。
    /// Body / Eyebrow 与 `AppColors.Flow.onHeroBodyOpacity / onHeroEyebrowOpacity` 同值（用例钉住）。
    static let onHeroBodyOpacity = 0.94
    static let onHeroEyebrowOpacity = 0.90
    static let onHeroTrackOpacity = 0.22
}

/// 陪跑员卡 v4 的颜色（稿 `draft.html` 的 `:root`）。单独起名，不往 `LiveActivityStatePalette` 里加：
/// 那个类型跑步卡也在用，#919 同期在改，同名常量两边各加一份会编不过。
enum GuideRunCardPalette {
    /// 卡底：深蓝（稿 `--navy`）。
    static let navy: UInt32 = 0x1F2433
    /// 已结束：灰（稿 `.la.stale`）。
    static let ended: UInt32 = 0x3A3F4B
    /// 快迟到 / 该出发了（稿 `--gold`）。
    static let gold: UInt32 = 0xF6C343
    /// 灵动岛「到了」（稿 `--greenDot`）。
    static let positive: UInt32 = 0x5BD38E
    /// 右侧通用人像（稿 `--avBg` / `--avInk`）。
    static let avatarFill: UInt32 = 0xDDE6FF
    static let avatarInk: UInt32 = 0x1F3A66
    /// 副标题：白 64%（稿 `--sub`）。用例 `GuideRunActivityContrastTests` 钉住在两种卡底上 ≥4.5:1。
    static let subtitleOpacity = 0.64
    /// 右侧按钮底：白 16%（稿 `.btn`）。
    static let buttonFillOpacity = 0.16

    static func color(_ rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

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

// MARK: - 底部进度线（五步）

/// 底部进度线的五步（订单页 v7 竖线五步）。V1–V2 停在「商量」，V3–V4 停在「出发」；V5–V6 不画线（稿四）。
///
/// TODO(#919): 共用组件 `LiveActivityProgressLine`（`blindRunWidget/Shared/LiveActivityProgressLine.swift`）
/// 合进 main 后，`GuideRunStepsPlaceholder` 换成 `LiveActivityProgressLine(mode: .steps(current:))`，
/// 读屏改用 `LiveActivityProgressMode.accessibilityLabel`，这里的 `stepTitles` 删掉。
enum GuideRunProgressSteps {
    static let count = 5
    static let stepTitles = ["匹配", "商量", "出发", "汇合", "开跑"]

    static func spoken(current: Int) -> String {
        let index = min(max(current, 1), count)
        return "第 \(index) 步，共 \(count) 步，\(stepTitles[index - 1])"
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

    let title: String
    /// V6「已到南门」照 Uber「Arriving Now」放大到 26pt。
    let titleIsLarge: Bool
    /// 快迟到 / 该出发了：标题转金色。
    let titleIsWarning: Bool
    let subtitle: String?
    /// V1：副标题后面接一个系统自走的倒计时（`subtitle` 是前缀）。
    let subtitleCountdownTo: Date?
    let trailing: Trailing
    /// 底部进度线停在第几步；`nil` = 不画线。
    let step: Int?
    let background: UInt32
    /// 灵动岛紧凑态右侧的那一个数。`compactCountdownTo` 有值时改画系统倒计时。
    let compactTrailing: String
    let compactCountdownTo: Date?
    let compactIsPositive: Bool
    /// 锁屏卡与展开态：除按钮外整块一站念完。
    let accessibilityLabel: String
    /// 紧凑态与最小态。
    let compactAccessibilityLabel: String

    var actions: [GuideRunActivityAction] {
        if case .action(let action) = trailing { return [action] }
        return []
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    init(
        attributes: GuideRunAttributes,
        state: GuideRunAttributes.ContentState,
        isStale: Bool = false,
        now: Date = Date()
    ) {
        var spokenSubtitle: String?
        var titleIsLarge = false
        var titleIsWarning = false
        var subtitleCountdownTo: Date?
        var compactCountdownTo: Date?
        var compactIsPositive = false
        var step: Int?
        var trailing = Trailing.person
        let title: String
        let subtitle: String?
        let compactTrailing: String

        switch state.phase {
        case .introCall:
            title = GuideRunActivityCopy.introCallTitle
            step = 2
            if let deadline = state.deadline, !isStale, deadline > now {
                subtitle = GuideRunActivityCopy.introCallCountdownPrefix
                subtitleCountdownTo = deadline
                compactCountdownTo = deadline
                spokenSubtitle = "\(GuideRunActivityCopy.introCallSubtitle)，\(GuideRunActivityCopy.spokenRemaining(until: deadline, now: now))"
            } else if state.deadline != nil {
                subtitle = GuideRunActivityCopy.introCallExpired
            } else {
                subtitle = GuideRunActivityCopy.introCallSubtitle
            }
            compactTrailing = GuideRunActivityCopy.introCallSubtitle

        case .planSubmitted:
            title = GuideRunActivityCopy.planSubmittedTitle
            subtitle = GuideRunActivityCopy.planSubmittedSubtitle
            step = 2
            compactTrailing = GuideRunActivityCopy.compactPlanSubmitted

        case .scheduled:
            title = GuideRunActivityCopy.scheduledTitle(plannedStart: attributes.plannedStart, now: now)
            subtitle = GuideRunActivityCopy.scheduledSubtitle(meetingPoint: attributes.meetingPointName)
            step = 3
            compactTrailing = attributes.plannedStart.map { GuideRunActivityCopy.clock($0) }
                ?? GuideRunActivityCopy.scheduledSubtitlePrefix

        case .preStart:
            step = 3
            let pastLeaveBy = state.leaveBy.map { isStale || $0 <= now } ?? false
            if pastLeaveBy {
                title = GuideRunActivityCopy.timeToLeave
                titleIsWarning = true
                subtitle = GuideRunActivityCopy.travelLine(minutes: state.travelMinutes)
            } else if let leaveBy = state.leaveBy {
                title = GuideRunActivityCopy.leaveByTitle(leaveBy)
                subtitle = GuideRunActivityCopy.travelLine(minutes: state.travelMinutes)
            } else {
                title = attributes.plannedStart.map { "\(GuideRunActivityCopy.clock($0)) 开跑" }
                    ?? GuideRunActivityCopy.leaveOnTime
                subtitle = attributes.plannedStart == nil ? nil : GuideRunActivityCopy.leaveOnTime
            }
            if let plannedStart = attributes.plannedStart, plannedStart > now {
                compactCountdownTo = plannedStart
            }
            compactTrailing = pastLeaveBy
                ? GuideRunActivityCopy.timeToLeave
                : attributes.plannedStart.map { GuideRunActivityCopy.clock($0) } ?? GuideRunActivityCopy.leaveOnTime

        case .departed, .late:
            let isLate = state.phase == .late
            title = GuideRunActivityCopy.etaHeadline(minutes: state.etaMinutes, late: isLate)
            titleIsWarning = isLate
            let lateMinutes: Int? = isLate
                ? zip2(state.arriveAt, attributes.plannedStart).map { Int(($0.timeIntervalSince($1) / 60).rounded()) }
                : nil
            if let late = GuideRunActivityCopy.lateSuffix(lateMinutes: lateMinutes) {
                subtitle = late
            } else if state.runnerNearMeetingPoint {
                subtitle = GuideRunActivityCopy.runnerNear(meetingPoint: attributes.meetingPointName)
            } else if let arriveAt = state.arriveAt {
                subtitle = "预计 \(GuideRunActivityCopy.clock(arriveAt)) 到"
                spokenSubtitle = "预计 \(GuideRunActivityCopy.spokenClock(arriveAt))到"
            } else {
                subtitle = nil
            }
            trailing = .action(.almostThere)
            compactTrailing = GuideRunActivityCopy.compactEta(minutes: state.etaMinutes)

        case .arrived:
            title = GuideRunActivityCopy.arrivedTitle(meetingPoint: attributes.meetingPointName)
            titleIsLarge = true
            subtitle = GuideRunActivityCopy.meetLine(distanceBucket: state.distanceBucket)
            trailing = .action(.ringRunner)
            compactTrailing = GuideRunActivityCopy.compactArrived
            compactIsPositive = true

        case .ended:
            title = GuideRunActivityCopy.endedTitle
            subtitle = nil
            trailing = .none
            compactTrailing = GuideRunActivityCopy.compactEnded
        }

        self.title = title
        self.titleIsLarge = titleIsLarge
        self.titleIsWarning = titleIsWarning
        self.subtitle = subtitle
        self.subtitleCountdownTo = subtitleCountdownTo
        self.trailing = trailing
        self.step = step
        self.background = state.phase == .ended ? GuideRunCardPalette.ended : GuideRunCardPalette.navy
        self.compactTrailing = compactTrailing
        self.compactCountdownTo = compactCountdownTo
        self.compactIsPositive = compactIsPositive

        let spokenTitle = state.phase == .scheduled
            ? GuideRunActivityCopy.spokenScheduledTitle(plannedStart: attributes.plannedStart, now: now)
            : title
        self.accessibilityLabel = [
            GuideRunActivityCopy.spokenBrand,
            spokenTitle,
            spokenSubtitle ?? subtitle,
            step.map(GuideRunProgressSteps.spoken(current:)),
        ]
        .compactMap { $0 }
        .joined(separator: "，")
        self.compactAccessibilityLabel = [GuideRunActivityCopy.spokenBrand, spokenTitle, spokenSubtitle ?? subtitle]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

// MARK: - 锁屏按钮背后的意图

/// 锁屏卡上的按钮。原始值是 intent 的参数（`@Parameter` 只收基础类型）。
///
/// v4 起出发卡只放 `.almostThere`、到达卡只放 `.ringRunner`（DECISION 第 9 条）；
/// `.waitFiveMinutes` 不再上卡（「再等我 5 分钟」进 App），case 留着是因为升级前起的旧卡上
/// 还有这枚按钮，按下去仍要能执行。
enum GuideRunActivityAction: String, CaseIterable, Sendable {
    case almostThere
    case waitFiveMinutes
    case ringRunner

    var title: String {
        switch self {
        case .almostThere: return GuideRunActivityCopy.almostThere
        case .waitFiveMinutes: return GuideRunActivityCopy.waitFiveMinutes
        case .ringRunner: return GuideRunActivityCopy.ringRunner
        }
    }
}

/// intent 真正要做的事住在 app target（要拿登录 token、要调 `OrderService`），
/// 本文件够不着，所以由 App 启动时挂进来（`blindRunApp.init`）。
///
/// ponytail: 静态闭包而不是 `AppDependencyManager` —— 后者 iOS 17.2+ 才有，而按钮从 17.0 起就在。
/// 天花板：App 被系统冷启动来跑 intent 时，`App.init` 一定先于 `perform()`（`@main` 的入口就是它），
/// 所以这里不会是 nil；真遇到 nil 就抛错，按钮按下去系统不做任何事，不会假装成功。
enum GuideRunActivityActions {
    typealias Handler = @Sendable (GuideRunActivityAction, Int64) async throws -> Void
    nonisolated(unsafe) static var handler: Handler?

    struct NotConfigured: Error {}
}

/// 「我快到了」「让他手机响」（以及旧卡上的「再等我 5 分钟」）。
///
/// `LiveActivityIntent` ⇒ 系统在 **app 进程**里执行 `perform()`，不打开 App。
@available(iOS 17.0, *)
struct GuideRunActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "陪跑员锁屏快捷操作"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "订单")
    var orderID: Int

    @Parameter(title: "操作")
    var action: String

    init() {}

    init(orderID: Int64, action: GuideRunActivityAction) {
        self.orderID = Int(orderID)
        self.action = action.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let action = GuideRunActivityAction(rawValue: action),
              let handler = GuideRunActivityActions.handler else {
            throw GuideRunActivityActions.NotConfigured()
        }
        try await handler(action, Int64(orderID))
        return .result()
    }
}
