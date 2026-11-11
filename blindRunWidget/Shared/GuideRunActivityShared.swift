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
