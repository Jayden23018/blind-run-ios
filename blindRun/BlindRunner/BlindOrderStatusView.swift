// 只为 `ObservableObject` / `@Published`（工程开了 MemberImportVisibility，SwiftUI 不再替它带进来）。
// 订单实时跟踪不用 Combine 订阅（`unify-order-live-tracking`），这里不许再加订阅。
import Combine
import CoreLocation
import SwiftUI

// MARK: - Blind Order Status ViewModel

@MainActor
final class BlindOrderStatusViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var statusLogs: [OrderStatusLog] = []
    @Published var isLoadingStatusLogs = false
    /// 状态记录单独一条错误，不复用 `errorMessage`：那条会被 `speakError` 念出来，
    /// 而这是用户主动展开的一块辅助信息，加载失败不该打断正在进行的服务播报。
    @Published var statusLogsErrorMessage: String?
    @Published var volunteerDistanceToStartText: String?
    @Published var latestVolunteerSample: LocatedCoordinate?
    @Published var errorMessage: String?
    /// 通话磨合页数据。`nil` = 这一单不在 `PENDING_INTRO_CALL`，或者这一轮已经结束，
    /// **或者这一轮的数据拉失败了** —— 后者由 `introCallUnavailable` 区分。
    ///
    /// 🚨 它里面**没有对方的表态、也没有轮次进度**，而且不许在客户端补算出来
    /// （见 `IntroCallView` 的类型注释）。
    @Published var introCall: IntroCallView?
    /// 举报入口用的对方 id。**一次拉取失败不清空**：`introCall` 失败时会清掉，而入口跟着消失的话，
    /// 填到一半的举报单也没了。与号码不同，这里留着旧值不会打错电话，只会举报刚通过话的那个人。
    @Published var introCallCounterpartUserId: Int64?
    /// 处在 `PENDING_INTRO_CALL` 但通话数据**拉不到**。
    ///
    /// 存在的理由是一个真实缺陷：`introCall == nil` 此前同时代表「不在通话态」和
    /// 「拉失败了」，而通话区靠 `let introCall` 拆包 ⇒ 拉失败时
    /// 拨号 / 合适 / 换一位三个按钮**一个都不渲染**，没有错误文字、没有播报，
    /// 而状态播报仍在说「有位志愿者想陪你跑，可以打个电话聊聊」。
    /// 对看不见屏幕的人，那是被告知去做一件屏幕上根本没有入口的事。
    ///
    /// **不复用 `errorMessage`**：`loadOrder` 每一轮开头都会把它清空（见那里），
    /// 而这个状态要跨轮活着。理由与 `statusLogsErrorMessage` 同源。
    @Published var introCallUnavailable = false
    /// 这一轮我**已经提交过**的表态。`nil` = 还没表态。
    ///
    /// 🚨 它的作用只有一个：**表过态之后，「拉不到通话数据」就不再算失败。**
    /// 表态已经被服务端记下了，再拉不到 view 也不改变这个事实。
    /// 没有它，用户刚听完「已经告诉系统你觉得合适」就会被「暂时拿不到通话信息」盖掉，
    /// 而屏幕上还会冒出一个「换一位」—— 他刚说完合适，那个按钮在那一刻是危险的。
    /// （`submitIntroCallDecision` 成功后紧接着就 `loadOrder`，这条路每次都会走到。）
    ///
    /// 🚩 **服务端说了话就以它为准**：每次成功拉到 view 都用 `myDecisionValue` 覆盖它。
    /// 换了候选人时后端回的 `myDecision` 是 nil，本地这个记号必须跟着作废 ——
    /// 否则新一轮一开局就显示成「正在等对方」，而用户其实还没打那通电话。
    /// 本地只是在**拉不到的时候**替服务端记着，不是另一个真相来源。
    @Published var submittedIntroCallDecision: IntroCallDecision?

    /// 我已经说过「合适」，正在等对方。
    ///
    /// 表过态之后**不依赖再拉一次 view** 才知道这件事 —— 那正是上面那个记号存在的理由。
    var isWaitingForIntroCallCounterpart: Bool {
        submittedIntroCallDecision == .accept || introCall?.isWaitingForCounterpart == true
    }

    // MARK: 见面安排单（#434）

    /// 拨过号、并且 App 之后**从后台**回到了前台 ⇒ B2「等待见面安排」。
    ///
    /// 放在 view model 而不是通话页的 `@State`：页面关掉再进来时不该退回 B1（审查 #4）。
    /// 它仍只是**本地推断** —— 服务端有安排单时一律以安排单为准（`IntroCallRunnerStep.resolve`）。
    @Published var hasReturnedFromIntroCallDialer = false
    /// 这一轮按过拨号。`(.background → .active)` 之前**没拨过号**的那次回前台不算「打完电话回来」。
    var didDialThisIntroCallRound = false
    var introCallForegroundDetector = IntroCallForegroundReturnDetector()
    /// 本地确认成功的那一版。只在「确认成功 → 订单转走」之间的那几秒有意义；换版本即失效。
    @Published var confirmedIntroCallPlanVersion: Int?
    /// 确认没送到。屏幕上按钮上方那条红字的开关（视觉稿 ④，修审查 #3：此前只有语音）。
    @Published var introCallConfirmFailed = false
    /// 陪跑员改过一版、盲人还没重新听完：头部换成「见面安排已修改，请重新收听」。
    @Published var introCallPlanChangedNotice = false
    /// 每次 +1 = 通话页要把读屏焦点挪回 B3 标题（安排单刚到、或改了一版）。
    @Published var introCallPlanFocusRequest = 0
    /// 上一次看到的安排单版本。用来认出「陪跑员改了一版」。
    var lastSeenIntroCallPlanVersion: Int?
    /// 409 `INTRO_CALL_PLAN_STALE` 时已经播过「请重新收听」的那一版（旧版本号）。
    /// 紧接着那次刷新会看到版本变了，不许再播第二遍。
    var planChangeAnnouncedFromVersion: Int?
    var introCallCountdownAnnouncer = IntroCallCountdownAnnouncer()
    var introCallPlanReminder = IntroCallPlanReminder()
    var introCallNotifyThrottle = IntroCallIncomingNotifyThrottle()
    /// App 在不在前台。10 分钟提醒在前台播报、不在前台走本地通知。
    var isAppActive = true
    /// 找到陪跑员那一刻的过渡（#926）。`apply` 换订单的**同一刻**置上（同一次发布，首帧不会先闪出新屏），
    /// 订单页演完约 1 秒后 `finishMatchFound()` 清掉。判据是纯函数 `BlindMatchFoundTransition.shouldPlay`。
    @Published var matchFound: BlindMatchFoundTransition?
    /// 上一次 `apply` 之后 App 进过后台。为真时这一次不放过渡：人没一直看着等待那一屏（稿第 5 条）。
    var backgroundedSinceLastApply = false
    /// 这次离开前台时真排出去的那条提醒的到点时刻。`nil` = 没排（回前台时就不撤、也不记「已送达」）。
    var introCallReminderScheduledFor: Date?
    /// 安排单读不懂这件事已经念过了。只在 false → true 那一跳念一次，理由同 `introCallUnavailable`。
    var didAnnounceUnreadableIntroCallPlan = false
    /// 10 分钟提醒的本地通知。单测换成假的（真排一条是系统级副作用）。
    var introCallPlanReminderNotifier: any IntroCallPlanReminderNotifying = IntroCallPlanReminderNotifier.shared
    /// 时钟。单测拨它验 10 分钟提醒与 60 秒节流。
    var introCallNow: () -> Date = { Date() }

    /// 盲人端此刻在 B1 / B2 / B3 / 已确认 哪一屏。**服务端安排单优先**（`IntroCallRunnerStep.resolve`）。
    ///
    /// `myDecision == ACCEPT` 却没有安排单：开关关着时旧版陪跑员客户端直接说了合适、或盲人此前在旧版上说过合适 ——
    /// 这一刻盲人能做的也只有等安排单，所以归 B2，不回 B1 再让他打一遍。
    var introCallRunnerStep: IntroCallRunnerStep {
        // 确认成功之后那一次刷新拉不到通话数据（`introCall` 被清成 nil）：仍是「已确认」，
        // 不许掉回 B2 让人以为还要等安排单。理由同 `submittedIntroCallDecision`。
        if confirmedIntroCallPlanVersion != nil, introCall?.meetupPlan == nil {
            return .confirmed
        }
        return IntroCallRunnerStep.resolve(
            plan: introCall?.meetupPlan,
            confirmedPlanVersion: confirmedIntroCallPlanVersion,
            hasReturnedFromBackground: hasReturnedFromIntroCallDialer || isWaitingForIntroCallCounterpart
        )
    }

    /// 本单是否已经用完延长次数。**按单记**，换单时清空（见 `startPolling`）。
    @Published var keepWaitingLimitReached = false

    /// 陪跑中那屏与已完成那屏的三个数字（距离 / 时长 / 配速），取 `/track` 的 `blindStats`。
    /// `nil` = 既不在 `IN_PROGRESS` 也不在 `COMPLETED`，或这一单还没拉到过。
    ///
    /// 🚩 取 `blindStats` 不是 `volunteerStats`：屏幕上那个数字是**跑者自己跑了多远**。
    /// 两条轨迹是各自独立采集的（后端 10 秒采样窗口、起点与点数都不同），拿错就是显示别人的成绩。
    @Published var trackStats: TrackStats?
    @Published var liveRunRoute: [CLLocationCoordinate2D] = [] // 同一次 `/track` 的跑者轨迹，订单页 v7 地图画已跑路线（#918）

    /// 汇合 → 跑步中那三秒倒计时还剩第几拍。`nil` = 不在倒计时。
    ///
    /// **纯本地状态，后端没有对应字段。** 它只是把「状态已经变成 `IN_PROGRESS` 了」
    /// 这件事在屏幕上演三秒再上数据 —— 相位的派生在
    /// `BlindOrderFlowPresentation.phase(order:countdown:)`。
    @Published var runCountdown: Int?

    /// 「开始跑步」的请求在途（含成功后重拉订单那一段）。
    ///
    /// 存在的理由是一条红线：蜂窝网络慢时这一段可能十几秒，此前按钮外观不变、
    /// 再按被 guard 静默吞掉 —— 「点了没反应」。在途时主按钮原位变成不可点的「准备中」
    /// （`BlindOrderFlowPresentation.primaryAction`），成功后与倒计时那三秒是同一个样子，无缝接上。
    /// 不复用 `isPerformingAction`：那个标记别的动作也在用，混用会让开跑按钮跟着它们变灰。
    @Published var isStartingRun = false

    var runCountdownTask: Task<Void, Never>?
    /// 上一轮 `apply` 时汇合页「取消本单」的样子。只用来判「刚刚从置灰变成可按」。
    var lastArrivalCancelGate: BlindArrivalCancelGate?

    /// `/track` 上一次拉的时刻。`nil` = 下一轮立刻拉。
    var lastTrackFetchAt: Date?
    /// 本单进 `COMPLETED` 之后那**一次**终值拉取做过没有。
    ///
    /// 🚩 它存在只为一件事：**绕过 10 秒节流拉最后一次**。完成那一刻上一次跑动中的拉取
    /// 往往还在节流窗内，照节流跳过的话屏幕上会停在最后一个中途值（5.18 而不是 5.20），
    /// 而这一屏的全部内容就是那三个终值。拉过一次就不再拉 —— 已完成的轨迹不会再变。
    var didFetchFinalTrack = false

    /// 完成那一刻的收尾任务：拉终值 → 上屏 → 播**唯一**那一句。
    ///
    /// 设计稿要求「一次只播一条、变形为总结状态时不再播第二遍」（状态清单 §4）。
    /// 改版前这一刻有两句：`apply` 的状态句 + `.task` 里那句轨迹总结，
    /// 而后者**同档打断**前者 —— 用户听到的是半句加一句。
    ///
    /// 🔴 **它必须是一个独立的、不继承取消的任务，这一点是实测出来的。**
    /// `apply` 紧接着就会走 `!shouldPoll` 那条分支调 `stopPolling()`，而订单跟踪的轮询任务
    /// **就是当前正在跑的这个任务** —— 自我取消。第一版把这件事留在 `loadOrder` 尾巴上，
    /// 真机结果是：那一句照样出声（它是同步的），但 `/track` 在一个已取消的任务里
    /// 立刻抛 cancelled ⇒ **那一句里永远没有里程、屏幕上那三个数字永远是 `--`**。
    /// 两条用例钉住（`BlindRunFinishAnnouncementTests`），它们在修好之前红、修好之后绿。
    ///
    /// 独立任务还顺带盖住第二个入口：`apply` 有两个调用者，另一个是 WebSocket 状态推送
    /// 那条（订单跟踪的 `.status` 事件，`handle(_:)`）—— 它根本不在 `loadOrder` 里，
    /// 挂在 `loadOrder` 尾巴上的写法在那条路径上一个字都不会播。
    var completionTask: Task<Void, Never>?

    /// 完成播报的两种语境。分开是因为两句话说的不是一件事。
    enum CompletionAnnouncement: Equatable {
        /// 陪跑员刚刚长按结束（本次会话见过转移前的状态）。设计稿那句 + 强震。
        case justFinished
        /// 冷启动直接进一张已完成的单（从历史记录点进来）。沿用既有的状态句 + 三个数字，
        /// **不说「刚刚结束」**——那件事可能是三天前发生的。
        case coldStart
    }

    /// 这次状态推进要不要播完成那句、播哪一句。`nil` = 不播。
    ///
    /// 判据抽成**纯静态函数**，理由同 `shouldStartRunCountdown`：这条链路的两个错误形态
    /// 都是静默的 —— 每 5 秒轮询一次却重播一遍（`previousStatus == .completed` 漏判），
    /// 或者从历史记录点进一张三天前的单、被告知「张伟刚刚结束了本次陪跑」。
    /// 两者在屏幕上都没有任何症状。
    nonisolated static func completionAnnouncement(
        from previousStatus: RunOrderStatus?,
        to status: RunOrderStatus
    ) -> CompletionAnnouncement? {
        guard status == .completed, previousStatus != .completed else { return nil }
        return previousStatus == nil ? .coldStart : .justFinished
    }
    /// 每公里播报的判定。逻辑（含「首个样本只定基线」那条）在 `KilometerMilestoneTracker`。
    var kilometerMilestones = KilometerMilestoneTracker()

    weak var appState: AppState? // `private(set)`：跑者结束陪跑在 `BlindRunnerFinish.swift`
    var speechService: SpeechService?
    weak var locationService: LocationService?
    /// 「播报我的位置」用。`weak` 与上面两个同理 —— ⚠️ 传进来的必须是被别处持有的实例
    /// （`AMapGeocodingService` 由 `blindRunApp` 的 `@StateObject` 持有），
    /// 临时构造一个传进来等于传 nil（守卫规则 `weak-temporary` 拦的就是这个）。
    weak var placeSearchProvider: (any PlaceSearchProviding)?
    var pollFailureGate = OrderPollFailureGate() // 轮询失败只播一次（#659）
    var currentOrderId: Int64?
    var latestVolunteerCoordinate: CLLocationCoordinate2D?
    var latestVolunteerWebSocketDate: Date?
    /// 订单实时跟踪（`unify-order-live-tracking`）。第一次 `configure` 时打开，之后复用。
    var orderTrack: OrderLiveTrack?
    var orderTrackTask: Task<Void, Never>?
    let voiceQuerySession = VoiceStatusQuerySession()
    /// 只经 `open(peerFreshness:)` 交给 tracker，REST 兜底的 `isFresh` 也用它。
    let peerFreshness: TimeInterval

    init(peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness) {
        self.peerFreshness = max(0.01, peerFreshness)
    }

    /// `GET /api/orders/{id}/track` 的最小间隔。
    ///
    /// **不另起定时器**：它挂在既有那条 5 秒订单轮询上（`loadOrder` 末尾），靠这个时间戳节流到
    /// 两轮一次。同一条循环、同一种并发模型 —— `AGENTS.md` 的「并发模型只用一种」。
    ///
    /// 🚩 10 秒是**我们自己定的**，不是契约值。后端对这个端点有没有频率约束尚未答复
    /// （`demo/docs/handoff.md` 2026-09-15 那条仍是未答项）。他们给了值就按他们的改。
    static let trackPollingInterval: TimeInterval = 10

    /// 完成态那一次**终值**拉取的限时。
    ///
    /// 3 秒是拿「那句话该多快出声」定的，不是拿网络延迟定的：完成本身已经因为 5 秒轮询
    /// 最多迟到 5 秒，再叠一个十几秒的请求超时（`APIClient.swift:282-283` 是 15 / 20 秒），
    /// 这句话就与它描述的事件脱钩了。到点就带着已有的数字把话播出去
    /// （`runFinishedAnnouncement` 允许没有里程），屏幕上那三个数字由页面那次不限时的
    /// `CompletedTrackSummaryViewModel.load` 兜底（`adoptCompletedTrackStats`）。
    static let finalTrackDeadline: TimeInterval = 3

    var canShowEmergency: Bool {
        order?.status.canBlindRunnerTriggerEmergency == true
    }

    var canShowCancel: Bool {
        order?.status.canBlindRunnerCancel == true
    }

    /// 上限到了就把按钮收起来，不留一个必定失败的控件 —— 对盲人来说
    /// 「按了、听到报错、再按、还是报错」比没有按钮更糟。
    ///
    /// 🔴 读 `offersBlindRunnerKeepWaitingControl` 而**不是** `offersKeepWaiting`：后者含
    /// `PENDING_MATCH`（后端确实受理），而那个按钮已按 2026-09-16 的决策删除。用后者的话
    /// `repeatStatus` 会在 `PENDING_MATCH` 照旧念「可以点继续等待」—— 念一个屏幕上没有的
    /// 按钮，对看不见屏幕的人是最贵的一种错误提示。
    var canShowKeepWaiting: Bool {
        order?.status.offersBlindRunnerKeepWaitingControl == true && !keepWaitingLimitReached
    }

    var shouldPoll: Bool {
        order?.status.shouldPoll ?? true
    }
}

// MARK: - Blind Order Status View

struct BlindOrderStatusView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speechService: SpeechService
    @EnvironmentObject var locationService: LocationService
    /// 不是 `private`：评价框的语音输入在 `+StatusSections.swift` 里用它（#795）。
    @EnvironmentObject var speechInputService: SpeechInputService
    /// 求助中心的「播报我的位置」要逆地理。取 `@EnvironmentObject` 而不是就地 new 一个：
    /// view model 那一侧是 `weak` 持有，临时对象传进去等于传 nil（守卫 `weak-temporary`）。
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService
    @Environment(\.dismiss) var dismiss
    /// 喂给 `viewModel.observeScenePhase`：通话页 B2 判据与 10 分钟提醒都靠它。
    /// 挂在订单页而不是通话页上 —— 通话页可以被关掉，订单页在整个通话期都在。
    @Environment(\.scenePhase) private var scenePhase
    /// 找到陪跑员那一刻（#926）：开了「减弱动态效果」就只做 0.25 秒淡入淡出。
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @StateObject var viewModel = BlindOrderStatusViewModel()
    @StateObject var trackViewModel = CompletedTrackSummaryViewModel()
    @StateObject var shareViewModel = RunPlanLiveShareViewModel()
    /// 举报 / 不再匹配此人。入口在「···」，弹层挂在页面根上，结果一行在正文 footer（`CounterpartSafetyMenu`）。
    @StateObject var counterpartSafety = CounterpartBlockViewModel()
    @State private var showEmergencyConfirmation = false
    @State var showEmergencyCancelConfirmation = false
    /// 云端求助失败后的一跳拨号兜底（`EmergencyCallContext.cloudFailed`）。
    /// 常规的「陪跑中主动拨号」现在走求助中心那一层，不再单独开这个弹窗。
    @State var showEmergencyCallOptions = false
    /// 陪跑中那块红色安全锚点打开的求助中心。
    @State var showSafetyHub = false
    /// 「匹配规则说明」。骨架态从取消确认弹窗里进（设计稿 §3.5），
    /// 只读退路那条列表仍走自己的 `NavigationLink`。
    @State private var showDispatchAlgorithmNotice = false
    /// 屏 3 / 屏 3b 的全屏呈现。**由显式动作打开，不由 coordinator 状态推导** ——
    /// 推导的话恢复路径以外的状态变化也会弹出这一屏。
    @State private var showEmergencyCountdown = false
    @State var showCancelConfirmation = false
    @State var showStatusLogs = false
    @State var showRunPlanShare = false
    @State var showRunnerMessage = false
    @State var showLiveShareConsent = false
    @State var showLiveShareConfirmation = false
    /// 状态推进后把 VoiceOver 焦点接到状态卡上。
    ///
    /// 这一页每 5 秒轮询一次，重绘时焦点会被系统收走，落点不确定 —— 而状态卡恰恰是
    /// 盲人此刻在等的那一条。已经有 `speakStatusChange` 在播报了，焦点不跟过来的话
    /// 两条通道就分家：听到「志愿者已到达」，抬手一滑却还在旧位置。
    ///
    /// 只在 `status` **真的变了**时移（含首次加载的 nil → 有值），不是每次轮询都移 ——
    /// 后者会把正在读订单信息的用户反复弹回顶部。
    @AccessibilityFocusState var statusHeaderFocused: Bool
    let orderId: Int64
    /// 「我的」或全屏手势转来的紧急请求（#605）。只有首页那条导航路径传它。
    var safetyRequest: Binding<BlindOrderSafetyRequest?> = .constant(nil)
    let onOrderUpdated: (OrderDetailResponse) -> Void

    /// 主按钮高度。比首页的 280 小：这一页顶上还有状态卡要占位置，
    /// 而状态本身也是盲人此刻需要的信息，不能被按钮挤出首屏。
    ///
    /// 2026-09-05 起**只剩「打电话给志愿者」用它**。「继续等待」原先共用这个高度，
    /// 已降级为 64pt 的次级按钮 —— 见 `keepWaitingSection`。
    @ScaledMetric(relativeTo: .largeTitle) var primaryActionButtonHeight: CGFloat = 140

    /// 这一刻渲染的是设计稿的骨架吗。
    ///
    /// 派生自 `flowPresentation` 而不是另写一套状态判断 —— 两处各判一次的下场是
    /// 骨架渲染出来了而底栏还挂着旧的两个按钮（或者反过来），而那种错位在真机上
    /// 表现为「底部四个按钮」，不会有任何东西报错。
    var usesFlowSkeleton: Bool {
        flowPresentation != nil
    }

    /// 进倒计时并把屏 3 呈上来。**两条触发路径共用这一个函数** —— 长按直接调，
    /// 轻点经二次确认后调。两处各写一遍的话，迟早只有一处记得打开那个全屏。
    private func startEmergencyCountdown() {
        viewModel.beginEmergencyCountdown()
        // 资格判定失败时 coordinator 落到 `.failed` 而不进倒计时。那一刻不该弹全屏：
        // 屏幕上该出现的是安全锚点上那条「当前订单状态不能发起求助」，而不是一个
        // 标题写着「即将发出」的空倒计时。
        guard appState.emergencyCoordinator.state.isCountingDown else { return }
        showEmergencyCountdown = true
    }

    /// 订单落在骨架的哪一格、哪一幕，以及那一幕要显示什么。`nil` = 不走骨架。
    ///
    /// 走不走骨架由 `RunOrderStatus.blindOrderFlowStep` 判：`.unknown` 与终态落 `nil`，
    /// 退回改版前那条只读滚动列表（`trackingContent`）。**刻意保留那条退路** ——
    /// 后端加了状态时，未知态要么有一个只读落点，要么整屏空白，而后者对盲人端是事故。
    var flowPresentation: BlindOrderFlowPresentation? {
        guard let order = viewModel.order else { return nil }
        return BlindOrderFlowPresentation.make(
            order: order,
            distanceText: viewModel.volunteerDistanceToStartText,
            canKeepWaiting: viewModel.canShowKeepWaiting,
            locationWarning: flowLocationWarning,
            countdown: viewModel.runCountdown,
            isStartingRun: viewModel.isStartingRun
        )
    }

    /// 这一刻是不是跑步中那一幕。底栏、导航栏与求助中心的三处分流都读它。
    private var isRunningPhase: Bool {
        flowPresentation?.phase.isRunning == true
    }

    /// 这一刻是不是已完成那一幕（设计稿 ④）。
    ///
    /// **与 `isRunningPhase` 分开而不是合成一个「骨架折叠态」**：两者在导航栏上的结论
    /// 正好相反 —— ④ 要有那枚「重复当前状态」（项目负责人 2026-09-16 决策 2 指明 ①②④），
    /// ③ 收起。合成一个的直接后果是 ④ 丢掉它。
    private var isFinishedPhase: Bool {
        flowPresentation?.phase == .finished
    }

    /// 副标题下方那行警示。**只在异常时非 nil。**
    ///
    /// 目前只有一种：需要对端位置的状态下拿不到它（设计稿 §3.4 的「同行位置暂不可用」，
    /// 改版前是顶部一条浮层提醒）。正常状态恒 `nil` —— 设计稿明确不要「定位正常」
    /// 这类反向提示，那对读屏用户是每次进页面都要滑过去的一条无信息内容。
    private var flowLocationWarning: String? {
        guard let order = viewModel.order,
              order.status.offersVolunteerDistanceToStart,
              viewModel.volunteerDistanceToStartText == nil else { return nil }
        return "同行位置暂不可用，稍后会自动恢复。"
    }

    var body: some View {
        content
        // 骨架自己铺 `AppColors.Flow.page`，这一层只兜住只读退路那条分支。
        .background(AppColors.background)
        .navigationTitle(usesFlowChrome ? "陪跑订单" : "订单状态")
        .navigationBarTitleDisplayMode(.inline)
        // 🔄 2026-10-07（方向 A，OpenSpec `redesign-blind-runner-screens-a`）：订单页**每一态都藏标签栏**，
        // 因此**每一态都给返回箭头**，包括跑步中与已完成。
        //
        // 此前跑步中 / 已完成藏的是返回箭头，出口靠标签栏（这段注释原先写着「若将来有人隐藏标签栏，
        // 这一行必须同时撤销，否则跑步中就没有任何出口 —— 结束权只在陪跑员手上」）。现在兑现了那句话。
        // 代价：读屏第一站是「返回」。误触的后果只是回到首页，订单照常进行，首页订单卡可以再点进来。
        //
        // 只能用 `.toolbar(.hidden, for: .tabBar)`：给内容加底部 padding 挡不住标签栏
        // （记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        // 订单页 v7 ①–④（#917）自带顶栏（返回、重复当前状态、···、右上角求助），藏掉系统导航栏。
        // 出发起（#918 之前）仍用系统导航栏。
        .toolbar(usesStagePage || usesTrackingMapPage ? .hidden : .visible, for: .navigationBar) // ⑤–⑧ 顶栏在地图上（#918）
        // 🔴 走四步骨架时**不挂这条底栏** —— 骨架自带设计稿的两个版位
        // （主按钮 + 求助与安全），再挂一条会变成四个按钮，而
        // `docs/05-page-specs.md` 那条「不要往常驻区加第三个版位」的理由是
        // 「三个 64pt 按钮在 6.1" 上吃掉约 26% 屏幕，治了求助够不着换来别的都够不着」。
        .safeAreaInset(edge: .bottom) {
            if !usesFlowChrome {
                standardRepeatStatusArea
            }
        }
        // 「重复当前状态」在骨架态放**导航栏右侧**。
        //
        // 设计稿的导航栏只规定了返回 + 标题，右侧是空的 —— 所以这枚图标零设计冲突，
        // 且与首页那枚（问候行右侧）是同一个模式，两页位置可类比。
        //
        // 🔴 它不是可选项：skill `aidrun-a11y-voice` 要求每个关键盲人页面都有它，
        // 理由是系统的 Speak Screen 读不到一次性的 `announcement` —— 没有它，
        // 盲人错过一次状态播报就再也拿不回来。**可以降视觉权重，但不能删。**
        //
        // ⚠️ 必须是**可见按钮**，不许做成 accessibility custom action：后者不开读屏的
        // 低视力用户够不到，且 `XCUIElement.tap()` 注入物理触摸、不经过 accessibility
        // action，等于这条硬规则没有任何机器守卫（记忆
        // `xcuitest-cannot-invoke-accessibility-actions`）。
        //
        // 🚩 **跑步中那一幕它收起**（项目负责人 2026-09-16 决策 2）：那一屏的主按钮就是
        // 「播报当前数据」，按下去调的是同一个 `repeatStatus()`。两枚按钮播同一段话，
        // 对看不见屏幕的人只是多一次误触面 —— 而这一条不违反上面那句「不能删」：
        // 功能没有消失，只是换了一个**更大、位置固定**的载体。
        .toolbar {
            if (usesFlowSkeleton && !isRunningPhase && !usesStagePage && !usesTrackingMapPage) || usesTerminalPage {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.repeatStatus()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.Flow.accent)
                            // 工具栏按钮的系统触达区约 44pt，低于盲人端 64pt 下限。
                            // `contentShape` 把命中区撑到 64 而不改变视觉尺寸 ——
                            // 直接 `.frame(width:64)` 会把图标顶出导航栏。
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle().size(width: 64, height: 64))
                    }
                    .accessibilityLabel("重复当前状态")
                    .accessibilityHint("点击后重新播报当前订单状态")
                    .accessibilityIdentifier("blindOrderFlowRepeatStatusButton")
                }
            }
            // 用系统导航栏的那几态（已取消、只读退路）：举报 / 不再匹配收在这里的「···」。
            if !usesStagePage && !usesTrackingMapPage && counterpartSafetyTarget != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    BlindOrderNavBarSafetyMenu(viewModel: counterpartSafety)
                }
            }
        }
        .counterpartSafetyPrompts(
            viewModel: counterpartSafety,
            target: counterpartSafetyTarget,
            blockContext: counterpartSafetyBlockContext
        )
        // 换到下一位对方时清掉上一位的「已不再匹配」（通话期换人 → 退回匹配 → 新的人，页面不重建）。
        // 变成 nil 时不清：刚拉黑、订单还没转走的那几秒，结果一行要留在屏幕上。
        .onChange(of: counterpartSafetyTarget?.userId) { userId in
            if userId != nil { counterpartSafety.reset() }
        }
        .confirmationDialog("取消订单", isPresented: $showCancelConfirmation) {
            Button("确认取消", role: .destructive) {
                Task {
                    await viewModel.cancelOrder()
                    if let order = viewModel.order {
                        onOrderUpdated(order)
                    }
                }
            }
            // 设计稿 §3.5 的迁移：「匹配规则说明 → 「取消匹配」二次确认弹窗中附带说明链接」。
            //
            // 🔴 **为什么必须迁，不能就这么丢掉**：《互联网信息服务算法推荐管理规定》
            // 第十六条要求「以显著方式告知」，而骨架替换掉的那条滚动列表里就挂着它
            // （`dispatchAlgorithmNoticeSection`）。四步骨架的两个固定版位与四行信息列表
            // 都排满了，这个二次确认弹窗是唯一一个**恰好只在被算法排序的那两态弹出**的
            // 落点（`offersDispatchAlgorithmNotice` = `PENDING_MATCH` + `REMATCHING`，
            // 与 `lastRowTitle` 说「取消匹配」的那两态逐字重合）。
            //
            // ⚠️ 排在破坏性按钮**之后**：读屏从上往下念，把一条信息性链接放在
            // 「确认取消」前面会让要看说明的人先滑过那枚红字。
            if viewModel.order?.status.offersDispatchAlgorithmNotice == true {
                Button(DispatchAlgorithmNoticeCopy.entryTitle) {
                    showDispatchAlgorithmNotice = true
                }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            // 汇合态取消的是一次见面，不是一个预约（后端 #682）。
            Text(viewModel.order?.status == .driverArrived
                 ? BlindArrivalCancelCopy.confirmationMessage
                 : "确认取消本次预约？取消后将结束本次服务。")
        }
        // 不是 `NavigationLink`：`confirmationDialog` 的按钮只能跑闭包，塞不进导航。
        // 用 sheet 而不是 push 还有一个好处 —— 看完说明关掉就回到原地，
        // 而 push 会把用户留在一页深处，返回键在左上角（管状视力用户的盲区）。
        .sheet(isPresented: $showRunnerMessage) {
            RunnerMessageSheet(initialText: viewModel.order?.messageToVolunteer ?? "") { text in
                await viewModel.saveRunnerMessage(text)
            }
        }
        .sheet(isPresented: $showDispatchAlgorithmNotice) {
            NavigationStack {
                DispatchAlgorithmNoticeView()
            }
        }
        .confirmationDialog(
            EmergencySafetyCopy.cancelButtonTitleForOwner,
            isPresented: $showEmergencyCancelConfirmation
        ) {
            Button(EmergencySafetyCopy.cancelButtonTitleForOwner, role: .destructive) {
                Task { await viewModel.cancelEmergency() }
            }
            Button("保持求助", role: .cancel) {}
        } message: {
            Text(EmergencySafetyCopy.cancelOwnerConfirmation)
        }
        .sheet(isPresented: $showRunPlanShare) {
            // 正文在呈现时重算而不是提前存进 @State：这一页每 5 秒轮询一次订单，
            // 打开 sheet 那一刻的行程要素才是要发出去的那份。
            MessageComposeSheet(
                recipients: [appState.primaryEmergencyContact?.phone?.nilIfBlank].compactMap { $0 },
                body: viewModel.order.flatMap(RunPlanShareMessage.compose(order:)) ?? ""
            ) { outcome in
                showRunPlanShare = false
                switch outcome {
                case .sent:
                    // 进行时。`.sent` 只代表用户点了发送，不代表送达 —— 见 `RunPlanShareCopy`。
                    shareViewModel.note(RunPlanShareCopy.sent, isProblem: false)
                case .cancelled:
                    shareViewModel.note(RunPlanShareCopy.cancelled, isProblem: false)
                case .failed:
                    shareViewModel.note(RunPlanShareCopy.failed, isProblem: true)
                }
            }
        }
        // 全屏，不是对话框：三条告知要各自可听、可停、可回头再听，理由见 `RunPlanShareConsentView`。
        .fullScreenCover(isPresented: $showLiveShareConsent) {
            RunPlanShareConsentView(
                onAgree: {
                    showLiveShareConsent = false
                    // 同意在**发请求之前**落盘。反过来的话，一次网络失败会让用户下次再看一遍
                    // 全文告知 —— 而他已经同意过了，重复告知是在消耗告知本身的效力。
                    consentStore.recordConsent(userKey: consentUserKey)
                    Task { await shareViewModel.startLiveShare() }
                },
                onDecline: {
                    showLiveShareConsent = false
                    shareViewModel.note(RunPlanShareConsentCopy.declined, isProblem: false)
                }
            )
        }
        .alert(RunPlanShareConsentCopy.repeatConfirmationTitle, isPresented: $showLiveShareConfirmation) {
            Button(RunPlanShareConsentCopy.agreeButtonTitle) {
                Task { await shareViewModel.startLiveShare() }
            }
            Button(RunPlanShareConsentCopy.declineButtonTitle, role: .cancel) {
                shareViewModel.note(RunPlanShareConsentCopy.declined, isProblem: false)
            }
        } message: {
            Text(RunPlanShareConsentCopy.repeatConfirmationMessage)
        }
        .sheet(item: $shareViewModel.payload) { payload in
            ShareLinkSheet(text: payload.text) {
                shareViewModel.payload = nil
                // 面板关掉不改变任何事实：链接在服务端已经生效，选没选目标应用都一样在分享中。
                shareViewModel.note(RunPlanLiveShareCopy.panelDismissed, isProblem: false)
            }
        }
        // 与首页共用同一个构造点，号码集合与顺序两页一致 —— 理由见 `emergencyCallOptionsDialog`。
        //
        // 🔴 **语境不能写死。** 两个入口，第一句必须分开说对：
        // ① 云端求助失败后安全锚点上冒出来的那枚「紧急呼叫」→ `.cloudFailed`
        //    （「求助没有发出去」）；
        // ② 非 `IN_PROGRESS` 时求助中心底部那条降级按钮 → `.homeIdle`
        //    （「当前没有进行中的陪跑」）。
        // 写死 `.cloudFailed` 会在②里对一个从没按过求助的人说「求助没有发出去」——
        // 那句话会让他以为自己刚才按错了什么，而他什么都没按错。
        .emergencyCallOptionsDialog(
            isPresented: $showEmergencyCallOptions,
            context: emergencyCallContext,
            primaryContact: appState.primaryEmergencyContact
        )
        // 求助中心。**它不是二次确认** —— 轻点「一键求助」之后才弹下面那条确认，
        // `AGENTS.md` §6 的逐字锁定文案与那一步都没动。
        //
        // 长按 3 秒 / 自定义无障碍动作走 `onTriggerEmergencyImmediately`：跳过二次确认，
        // 直接进倒计时。轻点那条先过二次确认，确认之后**也进同一个倒计时** ——
        // 发出求助只有一个出口，「两条路的行为哪里不一样」这个问题就不存在。
        //
        // 🔴 `mode` 不能写死 `.cloudTrigger`。这一层 2026-09-16 起也从四步骨架的底部打开，而那四态
        // 一个都不是 `IN_PROGRESS` —— 照走云端的后果是**屏幕零变化、一个字也不播**（见 `hubLocalCallNotice`）。
        .blindActiveRunSafetyHubSheet(
            isPresented: $showSafetyHub,
            mode: sosMode,
            primaryContact: appState.primaryEmergencyContact,
            volunteerPhone: viewModel.order?.volunteerPhone,
            locationError: locationService.locationError,
            // 设计稿 §3.5 的迁移：「分享实时位置给家人 → 求助与安全中心」。
            // 骨架替换掉了 `runPlanShareSection` 那条列表，不迁进来这四态就一个入口都没有。
            //
            // 🔴 **跑步中那一幕刻意仍然没有分享入口**，尽管它现在也有 `flowFooter` 了
            // （结果看得见这条前提已经成立）。理由换了一个：`IN_PROGRESS` 要不要给
            // 「把行程告诉家人」是一次**独立的产品决定** —— 那一屏的设计只有一个黄按钮 +
            // 求助与安全，而求助中心的格子数上限是 7（`BlindActiveRunSafetyHubOption.tiles`），
            // 跑中那一版的五项还在等 §2-C 拍板。顺手打开等于在一个没人拍过板的位置加功能。
            offersLiveShare: usesFlowSkeleton
                && !isRunningPhase
                && viewModel.order?.status.offersRunPlanShare == true,
            isLiveSharing: shareViewModel.isLiveSharing,
            onAnnounceLocation: { Task { await viewModel.announceCurrentLocation() } },
            onAskQuestion: { viewModel.askVoiceQuestion() },
            onToggleLiveShare: toggleLiveShare,
            onLocalCall: { showEmergencyCallOptions = true },
            onTriggerEmergency: { showEmergencyConfirmation = true },
            onTriggerEmergencyImmediately: startEmergencyCountdown,
            // 只在 `.cloudTrigger`（跑步中、登录有效）出现，判据在 `SafetyHubRunSection`。
            onEndRunWithoutVolunteer: { await viewModel.finishBecauseVolunteerUnreachable() }
        )
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirmation, audience: .runner) {
            startEmergencyCountdown()
        }
        // 屏 3 / 屏 3b。**全屏而不是 sheet**：这一刻盲人只有一件该做的事，
        // 而 sheet 会把订单页留在下缘可见、可被 VoiceOver 滑到。
        // 关闭只走屏内的按钮（`fullScreenCover` 本来就不能下滑关掉）。
        .fullScreenCover(isPresented: $showEmergencyCountdown) {
            EmergencyCountdownView(
                coordinator: appState.emergencyCoordinator,
                primaryContact: appState.primaryEmergencyContact,
                onCancelCountdown: {
                    guard let outcome = await appState.emergencyCoordinator.cancelCountdown(
                        safety: appState.safety
                    ) else { return }
                    if outcome.isFailure {
                        speechService.speakError(outcome.message, priority: .emergency)
                    } else {
                        speechService.speak(outcome.message, priority: .emergency)
                    }
                    // 撤回失败时**留在这一屏**：服务端倒计时照走，求助可能已经发出，
                    // 这一屏上有 120 / 110 和「撤销求助」，送回跑步页会让他以为已经取消了。
                    if appState.emergencyCoordinator.activeEvent == nil {
                        showEmergencyCountdown = false
                    }
                },
                onCancelOwnEmergency: {
                    await viewModel.cancelEmergency()
                    // 撤销成功就退出这一屏；失败**留在原地** —— 求助仍然有效，
                    // 而把人送回跑步页会让他以为已经撤掉了（`cancelOwnerFailed` 那句正是这个意思）。
                    if appState.emergencyCoordinator.activeEvent == nil {
                        showEmergencyCountdown = false
                    }
                },
                onRetry: {
                    // 重试走**完整的倒计时**，不是直接重发。理由有二：这一按同样可能是误触
                    // （屏幕上刚刚才说过「未发出」，用户可能只是想确认一下）；
                    // 而且发出求助只有一个出口，重试绕过倒计时就成了第二条路径。
                    viewModel.beginEmergencyCountdown()
                },
                onClose: { showEmergencyCountdown = false }
            )
        }
        // 求助不是只能从「按下按钮」那条路进屏 3b：志愿者代触发、冷启动、断线重连、
        // 点开推送，四条路都会让 App 在不知情的情况下处在一个进行中的求助里。
        // 数据侧早就有了（`AppState.catchUpMissedNotifications` → `refreshActiveEvent`），
        // 缺的一直是界面侧 —— 恢复出来的状态此前只体现为底部一行小字。
        .emergencyRecoveryCover(
            coordinator: appState.emergencyCoordinator,
            isPresented: $showEmergencyCountdown
        )
        .onAppear {
            shareViewModel.configure(
                appState: appState,
                speechService: speechService,
                orderId: orderId
            )
            viewModel.configure(
                appState: appState,
                speechService: speechService,
                locationService: locationService,
                speechInputService: speechInputService,
                placeSearchProvider: amapGeocodingService
            )
            viewModel.startPolling(orderId: orderId)
        }
        .onDisappear {
            viewModel.stopPolling()
            if let order = viewModel.order {
                onOrderUpdated(order)
            }
        }
        .onChange(of: viewModel.order?.status) { status in
            guard status != nil else { return }
            // 过渡中整页会换一棵视图树，这时设焦点会落空：等定格后由下面的 `.task` 设（#926）。
            guard viewModel.matchFound == nil else { return }
            statusHeaderFocused = true
        }
        .task(id: viewModel.matchFound?.id) {
            await playMatchFound()
        }
        .onChange(of: scenePhase) { phase in
            viewModel.observeScenePhase(phase)
        }
        .blindRunnerPreRunCues(order: viewModel.order, announcesMatchingWait: true, isFrontmost: !(showSafetyHub || showEmergencyCountdown || showRunnerMessage || viewModel.order?.status == .pendingIntroCall)) // #660；通话那一步照旧不插播（原先由通话全屏页挡住）
        .modifier(OrderSafetyRequestPresenter(
            request: safetyRequest,
            isOrderLoaded: { viewModel.order != nil },
            isCloudMode: { sosMode == .cloudTrigger },
            showConfirmation: { showEmergencyConfirmation = true },
            showSafetyHub: { showSafetyHub = true }
        ))
        .task(id: viewModel.order?.status) {
            guard viewModel.order?.status == .completed else { return }
            // 评价与「设为固定搭档」11-07 挪进跑者跑步详情（#831），这里不再查。
            await trackViewModel.load(orderID: orderId, appState: appState)
            // 这一次是不限时的（它只喂屏幕，不挡播报）。终值那次限时到点时，
            // ④ 那张卡的三个数字由它兜底 —— 否则卡片顶着 `--`。
            viewModel.adoptCompletedTrackStats(trackViewModel.track?.blindStats)
            // 🔴 **这里刻意不再播轨迹总结。** 它曾经是完成那一刻的**第二句**，而两句同档 ⇒
            // 后到的把先到的从半句切断（记忆 `later-speak-silently-cuts-the-earlier-one`），
            // 用户听到的是「服务已完」+「本次路线 5.20 公里…」。
            // 设计稿要求「一次只播一条、变形为总结状态时不再播第二遍」（状态清单 §4），
            // 那三个数字已经并进 `startCompletionAnnouncement` 那唯一一句里。
            // 想再听一遍走「重复当前状态」—— 导航栏那枚与轨迹卡里那枚都是它。
        }
        // 展开时拉一次，之后每次状态推进再拉一次 —— 服务进行中新增的那条转移会自己出现。
        // 折叠状态下不请求：这是一块用户主动来找的辅助信息，不该给主路径加一次 5 秒一轮的开销。
        .task(id: statusLogReloadKey) {
            guard showStatusLogs else { return }
            await viewModel.loadStatusLogs()
        }
    }

    private var statusLogReloadKey: String {
        "\(showStatusLogs)-\(viewModel.order?.status.rawValue ?? "")"
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindOrderStatusView(orderId: 1) { _ in }
            .environmentObject(AppState())
            .environmentObject(SpeechService())
            .environmentObject(LocationService())
            .environmentObject(SpeechInputService())
    }
}
#endif
