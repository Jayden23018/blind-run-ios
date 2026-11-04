import SwiftUI

// 陪跑员订单页上「约好 → 汇合」这一段的几句提醒（#660 V-8 / V-14 / V-35）。
// 单放一个文件：`VolunteerOrderFlowViews.swift`、`VolunteerOrderV2.swift`、`VolunteerOrderFlowStep.swift` 都已超长，
// SwiftLint 棘轮只许它们变短。

/// 汇合时怎么开口（V-14 / F-4）。陪跑员与跑者互不认识，跑者看不见，**认人只能靠陪跑员先开口**。
///
/// ⚠️ 这只是第一步。姓氏谁都能说，一次性暗号要后端生成并下发，已开后端 issue（见 #660 评论），这次不做。
enum VolunteerMeetupIdentityCopy {
    /// 汇合页头卡固定一行。
    static let line = "见面时先报姓氏，说明是助盲跑的陪跑员"
    /// 进入 `DRIVER_ARRIVED` 时那句播报。原来是「见到跑者、握好引导绳后再开始跑步」——
    /// 跑者选搀扶或仅语言引导时那半句不成立（V-8），绳子的事改由「开始跑步」上方那行按引导方式说。
    static let arrivedAnnouncement = "你已到达约定地点。见到跑者，先报姓氏，说明是助盲跑的陪跑员，准备好后再开始跑步。"
}

/// 第一次陪跑（V-35）。派单规则（新人能不能接全盲单）要负责人定，这里只做提示。
///
/// 要点并进「使用帮助」（`VolunteerFirstRunHelp` 的 `firstRun` 一条）：那一页本来就在第一次打开订单页时自动弹，
/// 同一刻再弹一个提示框会和它抢。订单页上另有一条「这是你的第一次陪跑」标签，首单的每一步都在。
enum VolunteerFirstRunCopy {
    static let label = "这是你的第一次陪跑"
    static let tips = [
        "见面先报姓氏，说明是助盲跑的陪跑员。",
        "问跑者习惯怎么引导：引导绳、扶手臂，还是只用语言。",
        "转弯、台阶、路面变化，提前说出来。",
        "跑者说停就停。",
        "跑者用引导绳时出门带上一根，现场谁带了就用谁的。",
    ]

    /// 判据是派单摘要的 `totalCompleted == 0`。`nil` = 没拉到，**不显示**（不猜）。
    /// 只在跑步前那几步给：完成页与取消页上「第一次陪跑」已经不是提醒。
    static func isFirstRun(totalCompleted: Int?, phase: VolunteerOrderPhase) -> Bool {
        guard totalCompleted == 0 else { return false }
        return isBeforeRun(phase)
    }

    static func isBeforeRun(_ phase: VolunteerOrderPhase) -> Bool {
        switch phase {
        case .confirmStillGoing, .agreedEarly, .agreedSoon, .departed, .arrived: return true
        case .completed, .runnerCancelled: return false
        }
    }
}

extension VolunteerOrderHero {
    /// 在 `make` 算好的头卡上补这一段的提醒：约好时的带绳一行、汇合时的开口一行、首单标签。
    func withPrepNotices(order: OrderDetailResponse, phase: VolunteerOrderPhase, totalCompleted: Int?) -> Self {
        var hero = self
        if let rope = GuideRopeReminder.line(for: order, isVolunteer: true) { hero.lines.append(rope) }
        if case .arrived = phase { hero.lines.append(VolunteerMeetupIdentityCopy.line) }
        // 快迟到的提醒条优先：那一句要他立刻知道，首单标签晚一步出现没有代价。
        if hero.notice == nil, VolunteerFirstRunCopy.isFirstRun(totalCompleted: totalCompleted, phase: phase) {
            hero.notice = VolunteerFirstRunCopy.label
        }
        return hero
    }
}

/// 只说一次的提示，按账号记（同 `VolunteerDeclineStreak`：键里带 userId、走 `AppState` 的持久化域，测试自动隔离）。
/// 登出不清：说过就是说过，换一台手机再说一次没有坏处。
struct VolunteerOnceNotice {
    enum Kind: String {
        /// 第一次接单时说明手机号去向（V-17）。
        case phoneShare = "aidrun.volunteer.phoneShareDisclosed"
    }

    let kind: Kind
    let persistence: (any AppStatePersistence)?
    let userID: Int64?

    private var key: String? { userID.map { "\(kind.rawValue).\($0)" } }

    /// 没登录（拿不到 userId）时按「还没说过」处理：宁可多说一次，不漏。
    var isDone: Bool {
        #if DEBUG || DEMO
        if persistence?.object(forKey: Self.uiTestSkipKey) as? Bool == true { return true }
        #endif
        return key.flatMap { persistence?.object(forKey: $0) as? Bool } ?? false
    }

    #if DEBUG || DEMO
    /// UI 用例默认跳过这些只说一次的提示（理由同 `AppState.applyUITestFirstRunHelpDefaults`：
    /// 每条用例都 `RESET_STATE`，不跳过就会在第一次按接单时被挡住）。UI 用例里多半还没有 userId，所以按设备记。
    static let uiTestSkipKey = "aidrun.volunteer.onceNotices.uiTestSkip"
    #endif

    func markDone() {
        guard let key else { return }
        persistence?.set(true, forKey: key)
    }
}

extension VolunteerOnceNotice {
    @MainActor
    init(_ kind: Kind, appState: AppState) {
        self.init(kind: kind, persistence: appState.persistence, userID: appState.userId)
    }
}

/// 首单标签的数据来源。挂在订单页页脚里，自己不画任何东西。
///
/// 订单页的 view model 平时只在完成时拉派单摘要；这里在跑步前补拉一次，拿 `totalCompleted` 判首单。
/// 拉失败就不显示标签（`isFirstRun` 对 `nil` 返回 false），记一条诊断，不重试 —— 少一个标签没有代价。
struct VolunteerFirstRunLoader: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: VolunteerInServiceViewModel
    let phase: VolunteerOrderPhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                guard viewModel.dispatchSummary == nil, VolunteerFirstRunCopy.isBeforeRun(phase) else { return }
                do {
                    viewModel.dispatchSummary = try await appState.orders.dispatchSummary()
                } catch {
                    ClientFlowDiagnostics.record(event: "failed", operation: "volunteer-first-run-summary")
                }
            }
    }
}
