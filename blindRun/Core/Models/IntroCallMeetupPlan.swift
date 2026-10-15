import CoreLocation
import Foundation
import SwiftUI

// MARK: - 通话后的见面安排单（OpenSpec `add-intro-call-meetup-plan`）

/// 接单前通话聊完之后，陪跑员把电话里说好的写下来的那张单。盲人听完朗读、确认后才生效。
///
/// 行为依据 `docs/design/2026-10-15-intro-call-meetup-plan-design.md` §1.2；
/// 文案与读屏原话以视觉稿 v2 `docs/ui/mockups/intro-call-meetup-plan-20261015/index.html` 为准。
///
/// 🚩 **这里只是本地类型，刻意不实现 `Decodable`。** 后端端点（blind-run-backend#755）未合并，
/// 字段名与颜色取值都没定。#432 接契约时只加一层「响应 → 本类型」的映射，下面的纯函数不用动。
///
/// 每个可改字段 `nil` = **按原约**，不是「清空」。陪跑员一个字段都不改也要提交 ——
/// 提交本身就是他的「合适」。
nonisolated struct IntroCallMeetupPlan: Sendable, Equatable {
    /// 服务端生成，每次提交 +1，并清掉盲人之前的确认。
    let version: Int
    let plannedStartTime: Date?
    let plannedEndTime: Date?
    let startAddress: String?
    /// GCJ-02，后端下发的坐标，与 `IntroCallOriginalArrangement` 同一坐标系，直接算距离不转换。
    let startLatitude: Double?
    let startLongitude: Double?
    /// 具体在哪儿见，≤ `meetSpotNoteMaxLength` 字。由**陪跑员**写，不是盲人的自由文本。
    let meetSpotNote: String?
    let volunteerTopColor: MeetupTopColor?
    /// 陪跑员在电话里问来的跑者上衣颜色。跑者不确定就是 `nil`（「未确认」不是一种颜色）。
    let runnerTopColor: MeetupTopColor?

    static let meetSpotNoteMaxLength = 30

    /// 与原约相比改了哪几项。只有时间和地点算「变更」—— 见面位置与颜色原约里没有，谈不上改。
    func changes(from original: IntroCallOriginalArrangement) -> IntroCallMeetupChanges {
        let start = plannedStartTime ?? original.plannedStartTime
        let end = plannedEndTime ?? original.plannedEndTime

        let newAddress = meetupNilIfBlank(startAddress)
        let addressChanged = newAddress != nil && newAddress != meetupNilIfBlank(original.startAddress)
        // 同名不同点也算改：集合点由可能是威胁来源的一方改动，坐标挪了就要让盲人听到距离。
        let meters = distanceFromOriginal(original)
        let coordinateMoved = (meters ?? 0) >= Self.samePlaceToleranceMeters
        return IntroCallMeetupChanges(
            startChanged: start != original.plannedStartTime,
            endChanged: end != original.plannedEndTime,
            placeChanged: addressChanged || coordinateMoved,
            distanceFromOriginalMeters: meters
        )
    }

    /// 两点都齐才有值。任何一边缺坐标就不念距离，不猜。
    func distanceFromOriginal(_ original: IntroCallOriginalArrangement) -> CLLocationDistance? {
        guard let lat = startLatitude, let lng = startLongitude,
              let originalLat = original.startLatitude, let originalLng = original.startLongitude else { return nil }
        return CLLocation(latitude: lat, longitude: lng)
            .distance(from: CLLocation(latitude: originalLat, longitude: originalLng))
    }

    /// 重选同一个 POI 时坐标不会完全一致的那点浮点误差。
    private static let samePlaceToleranceMeters: CLLocationDistance = 1
}

/// 与 `String.nilIfBlank` 同义。那个扩展在默认 MainActor 隔离下不能从 `nonisolated` 类型里引用
/// （编译器报 main actor-isolated property），这里不为它改共用扩展。
private nonisolated func meetupNilIfBlank(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

/// 原约：订单本来的时间与地点。客户端据此念「由 X 改为 Y」与离原地点多远。
nonisolated struct IntroCallOriginalArrangement: Sendable, Equatable {
    let plannedStartTime: Date?
    let plannedEndTime: Date?
    let startAddress: String?
    let startLatitude: Double?
    let startLongitude: Double?
}

nonisolated struct IntroCallMeetupChanges: Sendable, Equatable {
    let startChanged: Bool
    /// 只改结束时间也算时间变了 —— 朗读要点名改的是结束时间，不能念成「由 7 点改为 7 点」。
    let endChanged: Bool
    let placeChanged: Bool
    let distanceFromOriginalMeters: CLLocationDistance?

    /// 开始、结束合起来算一项「开跑时间」。
    var timeChanged: Bool { startChanged || endChanged }
    var count: Int { (timeChanged ? 1 : 0) + (placeChanged ? 1 : 0) }
}

/// 上衣颜色。契约里是闭合枚举、按开放枚举解码（blind-run-backend#755）。
///
/// 🚨 **未知值降级为 `.unknown`，不许把整张单带崩** —— 与 `RunOrderStatus.unknown` 同一条红线。
/// 降级之后那一行**不念、不显示颜色名**（`spokenName == nil`）。
///
/// ⚠️ 原始取值是占位：契约未定，#432 对齐时只改这张 `rawValue` 表。
///
/// 刻意不遵循 `CaseIterable`：合成的 `allCases` 会把 `.unknown` 带进陪跑员的颜色单选。
/// #433 要列表时照 `RunOrderStatus.allCases` 手写一份排除 `.unknown` 的。
nonisolated enum MeetupTopColor: String, Sendable {
    case black = "BLACK"
    case white = "WHITE"
    case gray = "GRAY"
    case red = "RED"
    case orange = "ORANGE"
    case yellow = "YELLOW"
    case green = "GREEN"
    case blue = "BLUE"
    case purple = "PURPLE"
    case pink = "PINK"
    /// 后端新增颜色时的兜底。**不是后端会发的值**。
    case unknown = "UNKNOWN"

    /// 解码入口（#432 接）。认不出的一律 `.unknown`。
    init(lenientRawValue rawValue: String) {
        self = MeetupTopColor(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) ?? .unknown
    }

    /// 视觉稿 v2 的颜色名（「红色」）。`.unknown` 返回 `nil` ⇒ 调用方整句不念。
    var spokenName: String? {
        switch self {
        case .black: return "黑色"
        case .white: return "白色"
        case .gray: return "灰色"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .unknown: return nil
        }
    }
}

// MARK: - 子状态

/// 盲人端在通话这一步的子状态。**不是订单状态** —— 全程都在 `PENDING_INTRO_CALL` 之内。
nonisolated enum IntroCallRunnerStep: Sendable, Equatable {
    /// B1 待通话
    case awaitingCall
    /// B2 等安排：打完电话回来了，安排单还没到
    case awaitingPlan
    /// B3 听安排、做确认
    case reviewingPlan
    /// 已确认最新版本，等订单转「约好」
    case confirmed

    /// 🚩 **服务端的安排单优先于本地「回过前台」标记**：关页重进、杀进程重启
    /// （本地标记丢了）也要回到 B3，而不是退回 B1。
    ///
    /// 盲人确认的是旧版本时仍是 B3 —— 陪跑员改过，之前那次确认不算数。
    static func resolve(
        plan: IntroCallMeetupPlan?,
        confirmedPlanVersion: Int?,
        hasReturnedFromBackground: Bool
    ) -> IntroCallRunnerStep {
        guard let plan else {
            return hasReturnedFromBackground ? .awaitingPlan : .awaitingCall
        }
        return confirmedPlanVersion == plan.version ? .confirmed : .reviewingPlan
    }
}

/// 陪跑员端的子状态。V2（填表）是本地界面状态，V4（结局）跟着订单状态走，都不在这里推。
nonisolated enum IntroCallVolunteerStep: Sendable, Equatable {
    /// V1 等来电
    case awaitingCall
    /// V3 等跑者确认。🚨 **不区分跑者听没听、同不同意** —— 那是跑者的无声拒绝权。
    case awaitingRunnerConfirmation

    static func resolve(plan: IntroCallMeetupPlan?) -> IntroCallVolunteerStep {
        plan == nil ? .awaitingCall : .awaitingRunnerConfirmation
    }
}

// MARK: - 回前台判据

/// 「打完电话回来了」的唯一判据：上次 `.active` 之后**进过 `.background`**，现在又回到 `.active`。
///
/// 🚨 **不是比较相邻两个阶段。** 打完电话回来的真实顺序是 `background → inactive → active`
/// （`docs/research/intro-call-post-call-coordination-20261015.md:70`），
/// 只认 `onChange` 里的 `(old, new) == (.background, .active)` 在真机上永远不成立 —— B2 进不去，
/// 而单测照样绿。所以这里记一笔「进过后台」，到 `.active` 时结算并清零。
///
/// `.inactive` 自己不算离开：拨号确认框点取消、权限弹窗、控制中心都会让它走一趟
/// （记忆 `permission-alert-makes-scenephase-inactive`）。
nonisolated struct IntroCallForegroundReturnDetector: Sendable, Equatable {
    private(set) var hasBeenInBackground = false

    /// 每次 `scenePhase` 变化喂一次新值。返回 true = 这一刻是「从后台回来」。
    mutating func observe(_ phase: ScenePhase) -> Bool {
        switch phase {
        case .background:
            hasBeenInBackground = true
            return false
        case .active:
            defer { hasBeenInBackground = false }
            return hasBeenInBackground
        case .inactive:
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: - 倒计时

/// 主动播报的两个节点。平时倒计时静默更新，只在这两处开口。
nonisolated enum IntroCallCountdownNode: Int, Sendable, Hashable {
    case fiveMinutes = 300
    case oneMinute = 60
}

/// 倒计时播报的去重器：同一个窗口里每个节点只响一次，轮询再多也不重复。
///
/// - 第一次观察时已经不到 5 分钟（剩 3 分钟才进页面）也会触发 5 分钟节点，念的是**实际**剩余分钟数
///   （`IntroCallMeetupCopy.countdownAnnouncement`），不是硬念「5 分钟」。
/// - 🚩 `windowEndsAt` 必须传后端给的**固定时刻**。传「now + 剩余秒数」这种每次轮询都在变的值，
///   每次都会被当成新一轮清零，两个节点会反复重播。
/// - 一下跳到 1 分钟以内（App 被挂起过）只触发 1 分钟节点，5 分钟节点同时作废 —— 不连念两句。
/// - 窗口已过不触发：超时由服务端宣布，客户端不抢先说（与 `IntroCallCopy.blindWindowRemainingText` 同一口径）。
/// - 窗口结束时刻变了（新一轮）就清零。
nonisolated struct IntroCallCountdownAnnouncer: Sendable, Equatable {
    private var windowEndsAt: Date?
    private var announced: Set<IntroCallCountdownNode> = []

    /// 返回这一次轮询该播的节点；不该播返回 `nil`。
    mutating func nodeToAnnounce(windowEndsAt: Date, now: Date) -> IntroCallCountdownNode? {
        if self.windowEndsAt != windowEndsAt {
            self.windowEndsAt = windowEndsAt
            announced = []
        }
        let remaining = windowEndsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        let due: IntroCallCountdownNode
        if remaining <= TimeInterval(IntroCallCountdownNode.oneMinute.rawValue) {
            due = .oneMinute
        } else if remaining <= TimeInterval(IntroCallCountdownNode.fiveMinutes.rawValue) {
            due = .fiveMinutes
        } else {
            return nil
        }
        guard !announced.contains(due) else { return nil }
        announced.insert(due)
        if due == .oneMinute { announced.insert(.fiveMinutes) }
        return due
    }
}

// MARK: - 文案

/// 见面安排单的朗读与倒计时文案。逐字取视觉稿 v2 的读屏原话。
enum IntroCallMeetupCopy {

    /// B3 第 ⑥ 项，固定句。
    static let fixedGreetingLine = "见面时由陪跑员主动上前，并告知姓氏。"

    /// 常驻倒计时的那一行（视觉稿「剩余 19 分钟」）。
    ///
    /// 不足 1 分钟显示「不到 1 分钟」而**不消失** —— 现有 `blindWindowRemainingText` 那一行
    /// 到这里就整行没了，读屏用户会以为倒计时坏了。已过期但服务端还没转走的那几秒也落这一档，
    /// 不说「已超时」。
    static func remainingText(windowEndsAt: Date, now: Date) -> String {
        let minutes = Int(windowEndsAt.timeIntervalSince(now) / 60)
        return minutes >= 1 ? "剩余 \(minutes) 分钟" : "剩余不到 1 分钟"
    }

    /// 剩 5 分钟 / 1 分钟那两次主动播报。B3 补一句下一步（视觉稿「剩余 5 分钟，请确认见面安排。」）；
    /// 其余子状态与陪跑员端只报剩余时间（视觉稿时间线第 7 行）。
    ///
    /// 🚩 **分钟数向上取整，与常驻那一行（向下取整）不同。** 节点在越过阈值后的第一次轮询触发，
    /// 那一刻剩的是 295–300 秒、55–60 秒：向下取整会把「5 分钟」那句念成「剩余 4 分钟」、
    /// 「1 分钟」那句念成「不到 1 分钟」。常驻那一行要保守（不多报剩余时间），播报要说中节点。
    static func countdownAnnouncement(windowEndsAt: Date, now: Date, isReviewingPlan: Bool) -> String {
        let seconds = windowEndsAt.timeIntervalSince(now)
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let remaining = "剩余 \(minutes) 分钟"
        return isReviewingPlan ? "\(remaining)，请确认见面安排。" : "\(remaining)。"
    }

    /// B3 整张安排单的朗读：标题一个焦点，下面每项一个焦点，**顺序固定**：
    /// 开跑时间 → 集合地点 → 具体见面位置 → 上衣颜色 → 固定句。
    ///
    /// - 只有变更项带「已变更：由 X 改为 Y」；未变更项不出现「改」字。
    /// - 变更地点**念全名**，不省掉与原地点相同的前缀：按字截前缀会把「朝阳门 → 朝阳公园」
    ///   念成「改为公园」，而集合点是由可能是威胁来源的一方改的（设计文档 §5.6）。
    /// - 不认识的颜色那一句不念；两人都没有颜色时整项省掉。
    /// - `volunteerName` 传后端的掩码称呼（`李*`），这里自己去星号 —— 这是朗读通道。
    static func planSpeech(
        plan: IntroCallMeetupPlan,
        original: IntroCallOriginalArrangement,
        volunteerName: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> IntroCallMeetupPlanSpeech {
        let changes = plan.changes(from: original)
        let name = volunteerName.unmaskedForSpeech
        let title = changes.count > 0
            ? "陪跑员\(name)已提交见面安排，共 \(changes.count) 项变更。"
            : "陪跑员\(name)已提交见面安排，无变更。"

        var items: [String] = []
        if let time = timeItem(plan: plan, original: original, changes: changes, now: now, calendar: calendar) {
            items.append(time)
        }
        if let place = placeItem(plan: plan, original: original, changes: changes) {
            items.append(place)
        }
        if let note = plan.meetSpotNote?.nilIfBlank {
            items.append("具体见面位置：\(note)。")
        }
        if let colors = colorItem(plan: plan) {
            items.append(colors)
        }
        items.append(fixedGreetingLine)
        return IntroCallMeetupPlanSpeech(title: title, items: items)
    }

    // MARK: 各项

    private static func timeItem(
        plan: IntroCallMeetupPlan,
        original: IntroCallOriginalArrangement,
        changes: IntroCallMeetupChanges,
        now: Date,
        calendar: Calendar
    ) -> String? {
        guard let start = plan.plannedStartTime ?? original.plannedStartTime else { return nil }
        let end = plan.plannedEndTime ?? original.plannedEndTime
        let clock = { spokenClock($0, calendar: calendar) }
        let startText = "\(spokenDay(start, now: now, calendar: calendar)) \(clock(start))"
        let endClause = end.map { "，" + spaced(clock($0), "结束") } ?? ""

        guard changes.timeChanged else { return "开跑时间：\(startText)\(endClause)。" }
        // 只改了结束时间：点名结束时间，不念一句「由 7 点改为 7 点」。
        if !changes.startChanged, let end {
            guard let originalEnd = original.plannedEndTime else {
                return "开跑时间，已变更：\(spaced(startText, "开始"))\(endClause)。"
            }
            let endChange = spaced(spaced(spaced("结束时间由", clock(originalEnd)), "改为"), clock(end))
            return "开跑时间，已变更：\(spaced(startText, "开始"))，\(endChange)。"
        }
        guard let originalStart = original.plannedStartTime else {
            return "开跑时间，已变更：\(spaced("改为", startText))\(endClause)。"
        }
        // 「由明天 7 点改为 7 点 30」：新时间与原时间同一天就不重复说「明天」。
        let from = "\(spokenDay(originalStart, now: now, calendar: calendar)) \(clock(originalStart))"
        let to = calendar.isDate(start, inSameDayAs: originalStart) ? clock(start) : startText
        return "开跑时间，已变更：\(spaced(spaced(spaced("由", from), "改为"), to))\(endClause)。"
    }

    /// 视觉稿的排版：阿拉伯数字与汉字相邻处留一个空格（「改为 7 点 30」「8 点 30 结束」）。
    /// **只用于模板拼接处**，不处理地址、见面位置这些用户填的内容（「3号门」不许被改成「3 号门」）。
    static func spaced(_ left: String, _ right: String) -> String {
        guard let last = left.last, let first = right.first else { return left + right }
        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        let isHan: (Character) -> Bool = { !$0.isASCII && $0.isLetter }
        let needsSpace = (isDigit(last) && isHan(first)) || (isHan(last) && isDigit(first))
        return needsSpace ? "\(left) \(right)" : left + right
    }

    private static func placeItem(
        plan: IntroCallMeetupPlan,
        original: IntroCallOriginalArrangement,
        changes: IntroCallMeetupChanges
    ) -> String? {
        let originalAddress = original.startAddress?.nilIfBlank
        guard let address = plan.startAddress?.nilIfBlank ?? originalAddress else { return nil }
        guard changes.placeChanged else { return "集合地点：\(address)。" }

        // `formattedDistance` 最小报 10 米：不到 10 米时不念距离，免得把没挪的点说成「约 10 米」。
        let distance = changes.distanceFromOriginalMeters
            .flatMap { $0 >= minimumSpokenDistanceMeters ? $0 : nil }
            .map { "，距原地点约 \(DistanceCalculator.formattedDistance($0))" } ?? ""
        guard let originalAddress else {
            return "集合地点，已变更：改为\(address)\(distance)。"
        }
        // 同名不同点：念「由南门改为南门」听不出改了什么，改说「仍为南门」再报距离。
        guard address != originalAddress else {
            return "集合地点，已变更：仍为\(address)\(distance)。"
        }
        return "集合地点，已变更：由\(originalAddress)改为\(address)\(distance)。"
    }

    private static let minimumSpokenDistanceMeters: CLLocationDistance = 10

    private static func colorItem(plan: IntroCallMeetupPlan) -> String? {
        var sentences: [String] = []
        if let volunteer = plan.volunteerTopColor?.spokenName {
            sentences.append("陪跑员上衣为\(volunteer)。")
        }
        if let runner = plan.runnerTopColor?.spokenName {
            sentences.append("你的上衣记录为\(runner)，如有误请致电更正。")
        }
        return sentences.isEmpty ? nil : sentences.joined()
    }

    // MARK: 时间的说法

    /// 「7 点」「7 点 30」「7 点 05」。整点不念「00」，非整点不加「分」—— 视觉稿原话「7 点 30」。
    static func spokenClock(_ date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return minute == 0 ? "\(hour) 点" : String(format: "%d 点 %02d", hour, minute)
    }

    /// 「今天」「明天」「后天」，再往后退回「10月18日」。规则与 `RunPlanFormat.shortStart` 一致。
    static func spokenDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let dayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day
        switch dayOffset {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        default:
            let parts = calendar.dateComponents([.month, .day], from: date)
            return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
        }
    }
}

/// B3 的朗读：`title` 是第一个读屏焦点，`items` 每项一个读屏元素，顺序即数组顺序。
nonisolated struct IntroCallMeetupPlanSpeech: Sendable, Equatable {
    let title: String
    let items: [String]

    /// 「重复当前状态」念的整张单。
    var fullText: String { ([title] + items).joined() }
}
