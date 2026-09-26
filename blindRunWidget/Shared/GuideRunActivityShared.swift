import ActivityKit
import AppIntents
import SwiftUI

// MARK: - 陪跑员「出发 / 汇合」锁屏卡：两个 target 共用的那一份
//
// 🔴 与 `RunLiveActivityShared.swift` 同一条硬约束：本文件**同时属于 `blindRun` 与 `blindRunWidget`**，
// 所以不能 `import` 任何只在 app target 里的东西（`AppColors` / `OrderDetailResponse` /
// `QuickMessageCode` 都不行）。
//
// 这张卡与跑步卡**并存、不合并**（决定源 V3，后端对接说明 §5）：
// 跑步卡本地更新，这张卡由后端经 APNs 推 `update` / `end`（`pushType: .token`）。
// 开跑时后端给这张卡发 `end`，App 照旧本地起跑步卡。

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
        /// 引导绳位置，后端夹在 [0.1, 0.85]。画之前再夹一次。
        var progress: Double
        var runnerNearMeetingPoint: Bool
        /// 只在汇合时有值，开放枚举（`WITHIN_10` / `WITHIN_50` / `WITHIN_100` / `FAR` / `UNKNOWN`）。
        var distanceBucket: String?
    }

    /// **响应向开放枚举**：后端加了新值时不许整条更新解码失败（那等于锁屏卡冻住），
    /// 不认识的一律按 `departed` 画 —— 「正在赶去」对任何未知的在途状态都不说错话。
    enum Phase: String, Codable, Hashable {
        case departed
        case late
        case arrived

        init(from decoder: Decoder) throws {
            let rawValue = try? decoder.singleValueContainer().decode(String.self)
            self = rawValue.flatMap(Phase.init(rawValue:)) ?? .departed
        }
    }

    var orderID: Int64
    /// 跑者姓氏（决定源 V11：锁屏只用姓氏，不加「先生 / 女士」）。
    /// 后端 BE-2 的姓氏字段还没到 ⇒ 现在恒为 `nil`，卡上就不出现名字 —— **不拿掩码名顶替**。
    var runnerSurname: String?
    var meetingPointName: String
    /// 计划开跑时刻。推送载荷里没有「晚到几分钟」，由 `arriveAt − plannedStart` 在卡上算
    /// （后端 `EtaView.deltaVsStartMinutes` 同一个口径）。
    var plannedStart: Date?
}

// MARK: - 状态色

/// 锁屏卡的状态色（交付包 `01-design-tokens.md`，决定源 V13：状态色只用于头卡与锁屏卡）。
///
/// ⚠️ **FE-1 会在 app 的设计系统里加同名色**。widget target 编译不到 `AppColors`，
/// 所以这里是第二份取值 —— FE-1 落地时在 `GuideRunActivityTests` 里补一条对撞，
/// 做法同 `RunLiveActivityTests.testPaletteMatchesTheFlowPaletteDarkTones`。
enum LiveActivityStatePalette {
    /// 出发、快迟到：主蓝。
    static let stateDeparted: UInt32 = 0x2A5BD7
    /// 汇合：琥珀。
    static let stateArrived: UInt32 = 0xA04B0C
    /// 跑步中：青绿。
    static let stateRunning: UInt32 = 0x0A6B72
    /// 跑步中 · 已暂停：灰。
    static let statePaused: UInt32 = 0x4B5263
    /// 快迟到的 ETA 文字、并肩后的绳子。
    static let gold: UInt32 = 0xFFD978
    /// 出发卡左上角小图标的底。
    static let yellow: UInt32 = 0xF6C343
    static let onYellow: UInt32 = 0x1E1A0B
    /// 「跑者已到集合点附近」前面那个绿点。
    static let nearDot: UInt32 = 0x6BE79C

    /// 彩色底上的白字四档（`onHeroStrong / Body / Eyebrow / Track`）。
    static let onHeroBodyOpacity = 0.86
    static let onHeroEyebrowOpacity = 0.80
    static let onHeroTrackOpacity = 0.22
    /// 出发 / 汇合卡上的 14–15pt 小字用 86% 而不是交付包的 80%：
    /// 80% 白在出发蓝上只有 4.36:1、在汇合琥珀上 4.45:1，够不到正文 4.5:1
    /// （交付包 01 声称 `onHero*` 全部 ≥4.5:1，这两处不成立）。用例 `GuideRunActivityTests` 钉住。
    static let smallTextOpacityOnGuideCard = onHeroBodyOpacity
    /// 锁屏按钮的底：白色 12%。
    static let buttonFillOpacity = 0.12
}

// MARK: - 文案

enum GuideRunActivityCopy {
    static let eyebrowDeparted = "助盲跑 · 正在赶去"
    static let eyebrowArrived = "助盲跑 · 汇合中"
    static let arrivedHeadline = "已到集合点"
    static let departedWithoutEta = "已出发"
    static let arrivingNow = "马上到"
    static let compactArrived = "已到"
    static let almostThere = "我快到了"
    static let waitFiveMinutes = "再等我 5 分钟"
    static let ringRunner = "让跑者的手机响起来"

    /// 「8 分钟后到」。四舍五入到 0 时说「马上到」，不说「0 分钟后到」。
    static func etaHeadline(minutes: Int?, late: Bool) -> String {
        guard let minutes else { return departedWithoutEta }
        guard minutes > 0 else { return arrivingNow }
        return late ? "约 \(minutes) 分钟后到" : "\(minutes) 分钟后到"
    }

    /// 快迟到时跟在 ETA 后面的那一段。晚到不足 1 分钟（或算不出来）时不写。
    static func lateSuffix(lateMinutes: Int?) -> String? {
        guard let lateMinutes, lateMinutes > 0 else { return nil }
        return "晚到约 \(lateMinutes) 分钟"
    }

    static func compactEta(minutes: Int?) -> String {
        guard let minutes else { return departedWithoutEta }
        return minutes > 0 ? "\(minutes) 分钟" : arrivingNow
    }

    /// 决定源 V11：**整句用「跑者」**，姓氏只进短标签（引导绳上的圆点）。
    static func runnerNear(meetingPoint: String) -> String {
        let place = meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? "跑者已到集合点附近" : "跑者已到\(place)附近"
    }

    /// 汇合时第 4 行。取值与 App 内汇合页 `MeetCopy` 同口径，只是名字一律换成「跑者」。
    /// `UNKNOWN` 与缺省不写 —— 锁屏上没地方解释「看不到位置」是什么意思。
    static func meetLine(distanceBucket: String?) -> String? {
        switch distanceBucket {
        case "WITHIN_10": return "跑者就在你身边"
        case "WITHIN_50", "WITHIN_100": return "跑者就在附近"
        case "FAR": return "跑者还没到集合点"
        default: return nil
        }
    }

    /// 「6:57」—— 到达时间只在锁屏卡上出现这一次。
    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 读屏念的时间：「6 点 57 分」。
    static func spokenClock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return "\(parts.hour ?? 0) 点 \(parts.minute ?? 0) 分"
    }
}

// MARK: - 卡上要画什么（纯函数，app 与 widget 都用）

/// 把 `ContentState` + attributes 解成卡上每一行的文字。**widget 只照着画**，
/// 所以 app target 的用例能把「快迟到」「汇合」各长什么样逐字钉住。
@available(iOS 16.2, *)
struct GuideRunActivityPresentation: Equatable {
    let eyebrow: String
    let headline: String
    let headlineIsLate: Bool
    /// 「6:57」。汇合时为 `nil`。
    let arriveClock: String?
    let lateSuffix: String?
    let statusLine: String?
    let compactTrailing: String
    let background: UInt32
    let progress: Double
    let actions: [GuideRunActivityAction]
    let accessibilityLabel: String

    init(attributes: GuideRunAttributes, state: GuideRunAttributes.ContentState) {
        let isArrived = state.phase == .arrived
        let isLate = state.phase == .late
        eyebrow = isArrived ? GuideRunActivityCopy.eyebrowArrived : GuideRunActivityCopy.eyebrowDeparted
        headlineIsLate = isLate
        if isArrived {
            headline = GuideRunActivityCopy.arrivedHeadline
            arriveClock = nil
            lateSuffix = nil
            statusLine = GuideRunActivityCopy.meetLine(distanceBucket: state.distanceBucket)
            compactTrailing = GuideRunActivityCopy.compactArrived
            actions = [.ringRunner]
        } else {
            headline = GuideRunActivityCopy.etaHeadline(minutes: state.etaMinutes, late: isLate)
            arriveClock = state.arriveAt.map(GuideRunActivityCopy.clock)
            let lateMinutes: Int? = isLate
                ? zip2(state.arriveAt, attributes.plannedStart).map { Int(($0.timeIntervalSince($1) / 60).rounded()) }
                : nil
            lateSuffix = GuideRunActivityCopy.lateSuffix(lateMinutes: lateMinutes)
            statusLine = state.runnerNearMeetingPoint
                ? GuideRunActivityCopy.runnerNear(meetingPoint: attributes.meetingPointName)
                : nil
            compactTrailing = GuideRunActivityCopy.compactEta(minutes: state.etaMinutes)
            actions = [.almostThere, .waitFiveMinutes]
        }
        background = isArrived ? LiveActivityStatePalette.stateArrived : LiveActivityStatePalette.stateDeparted
        progress = isArrived ? 0.85 : min(max(state.progress, 0.1), 0.85)

        // 读屏一站念完（交付包 04「可访问性」）：「助盲跑，正在赶去，8 分钟后到，6 点 57 分，跑者已到…附近」。
        let spokenEyebrow = eyebrow.replacingOccurrences(of: " · ", with: "，")
        accessibilityLabel = [
            spokenEyebrow,
            headline,
            lateSuffix,
            isArrived ? nil : state.arriveAt.map(GuideRunActivityCopy.spokenClock),
            statusLine,
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

// MARK: - 锁屏按钮背后的意图

/// 锁屏卡上的三个按钮。原始值是 intent 的参数（`@Parameter` 只收基础类型）。
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

/// 「我快到了」「再等我 5 分钟」「让跑者的手机响起来」。
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
