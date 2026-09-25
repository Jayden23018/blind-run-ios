import Combine
import CoreLocation
import SwiftUI

// MARK: - Blind Order Status ViewModel

@MainActor
final class BlindOrderStatusViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var isSubmittingReview = false
    @Published var reviewRating = 5
    @Published var reviewComment = ""
    @Published var didSubmitReview = false
    /// 本单已有的评价。**离开页面再回来时唯一的真相来源** —— `didSubmitReview` 是进程内的一次性标记，
    /// 重进这一单它就回到 false，评价表单会再摆一次，提交后只能收到 409 `REVIEW_ALREADY_SUBMITTED`。
    @Published private(set) var existingReview: OrderReview?
    @Published private(set) var statusLogs: [OrderStatusLog] = []
    @Published private(set) var isLoadingStatusLogs = false
    /// 状态记录单独一条错误，不复用 `errorMessage`：那条会被 `speakError` 念出来，
    /// 而这是用户主动展开的一块辅助信息，加载失败不该打断正在进行的服务播报。
    @Published private(set) var statusLogsErrorMessage: String?
    @Published var volunteerDistanceToStartText: String?
    @Published private(set) var latestVolunteerSample: LocatedCoordinate?
    @Published var errorMessage: String?
    /// 通话磨合页数据。`nil` = 这一单不在 `PENDING_INTRO_CALL`，或者这一轮已经结束，
    /// **或者这一轮的数据拉失败了** —— 后者由 `introCallUnavailable` 区分。
    ///
    /// 🚨 它里面**没有对方的表态、也没有轮次进度**，而且不许在客户端补算出来
    /// （见 `IntroCallView` 的类型注释）。
    @Published private(set) var introCall: IntroCallView?
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
    @Published private(set) var introCallUnavailable = false
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
    @Published private(set) var submittedIntroCallDecision: IntroCallDecision?

    /// 我已经说过「合适」，正在等对方。
    ///
    /// 表过态之后**不依赖再拉一次 view** 才知道这件事 —— 那正是上面那个记号存在的理由。
    var isWaitingForIntroCallCounterpart: Bool {
        submittedIntroCallDecision == .accept || introCall?.isWaitingForCounterpart == true
    }

    /// 本单是否已经用完延长次数。**按单记**，换单时清空（见 `startPolling`）。
    @Published private(set) var keepWaitingLimitReached = false

    /// 陪跑中那屏与已完成那屏的三个数字（距离 / 时长 / 配速），取 `/track` 的 `blindStats`。
    /// `nil` = 既不在 `IN_PROGRESS` 也不在 `COMPLETED`，或这一单还没拉到过。
    ///
    /// 🚩 取 `blindStats` 不是 `volunteerStats`：屏幕上那个数字是**跑者自己跑了多远**。
    /// 两条轨迹是各自独立采集的（后端 10 秒采样窗口、起点与点数都不同），拿错就是显示别人的成绩。
    @Published private(set) var trackStats: TrackStats?

    /// 汇合 → 跑步中那三秒倒计时还剩第几拍。`nil` = 不在倒计时。
    ///
    /// **纯本地状态，后端没有对应字段。** 它只是把「状态已经变成 `IN_PROGRESS` 了」
    /// 这件事在屏幕上演三秒再上数据 —— 相位的派生在
    /// `BlindOrderFlowPresentation.phase(order:countdown:)`。
    @Published private(set) var runCountdown: Int?

    private var runCountdownTask: Task<Void, Never>?

    /// `/track` 上一次拉的时刻。`nil` = 下一轮立刻拉。
    private var lastTrackFetchAt: Date?
    /// 本单进 `COMPLETED` 之后那**一次**终值拉取做过没有。
    ///
    /// 🚩 它存在只为一件事：**绕过 10 秒节流拉最后一次**。完成那一刻上一次跑动中的拉取
    /// 往往还在节流窗内，照节流跳过的话屏幕上会停在最后一个中途值（5.18 而不是 5.20），
    /// 而这一屏的全部内容就是那三个终值。拉过一次就不再拉 —— 已完成的轨迹不会再变。
    private var didFetchFinalTrack = false

    /// 完成那一刻的收尾任务：拉终值 → 上屏 → 播**唯一**那一句。
    ///
    /// 设计稿要求「一次只播一条、变形为总结状态时不再播第二遍」（状态清单 §4）。
    /// 改版前这一刻有两句：`apply` 的状态句 + `.task` 里那句轨迹总结，
    /// 而后者**同档打断**前者 —— 用户听到的是半句加一句。
    ///
    /// 🔴 **它必须是一个独立的、不继承取消的任务，这一点是实测出来的。**
    /// `apply` 紧接着就会走 `!shouldPoll` 那条分支调 `stopPolling()`，而 `pollingTask`
    /// **就是当前正在跑的这个任务** —— 自我取消。第一版把这件事留在 `loadOrder` 尾巴上，
    /// 真机结果是：那一句照样出声（它是同步的），但 `/track` 在一个已取消的任务里
    /// 立刻抛 cancelled ⇒ **那一句里永远没有里程、屏幕上那三个数字永远是 `--`**。
    /// 两条用例钉住（`BlindRunFinishAnnouncementTests`），它们在修好之前红、修好之后绿。
    ///
    /// 独立任务还顺带盖住第二个入口：`apply` 有两个调用者，另一个是 WebSocket 状态推送
    /// 那条 Combine sink（`subscribeToRealtimeCoordinator`）—— 它根本不在 `loadOrder` 里，
    /// 挂在 `loadOrder` 尾巴上的写法在那条路径上一个字都不会播。
    private var completionTask: Task<Void, Never>?

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
    private var kilometerMilestones = KilometerMilestoneTracker()

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private weak var locationService: LocationService?
    /// 「播报我的位置」用。`weak` 与上面两个同理 —— ⚠️ 传进来的必须是被别处持有的实例
    /// （`AMapGeocodingService` 由 `blindRunApp` 的 `@StateObject` 持有），
    /// 临时构造一个传进来等于传 nil（守卫规则 `weak-temporary` 拦的就是这个）。
    private weak var placeSearchProvider: (any PlaceSearchProviding)?
    private var pollingTask: Task<Void, Never>?
    private var currentOrderId: Int64?
    private var latestVolunteerCoordinate: CLLocationCoordinate2D?
    private var latestVolunteerWebSocketDate: Date?
    private var peerExpiryTask: Task<Void, Never>?
    private var acceptsPeerLocations = true
    private var cancellables = Set<AnyCancellable>()
    private let voiceQuerySession = VoiceStatusQuerySession()
    private let peerFreshness: TimeInterval

    init(peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness) {
        self.peerFreshness = max(0.01, peerFreshness)
    }

    /// Active blind-runner orders keep the 5-second REST fallback even when WebSocket is connected.
    var effectivePollingInterval: TimeInterval {
        return AppConstants.Timing.orderPollingInterval
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

    /// - Parameter speechInputService: 「问一句」用。可选是为了让既有的一批单测不必凭空造一个
    ///   麦克风服务；传 nil 时按下按钮不会起听（`VoiceStatusQuerySession.ask` 自己 guard 掉）。
    func configure(
        appState: AppState,
        speechService: SpeechService,
        locationService: LocationService? = nil,
        speechInputService: SpeechInputService? = nil,
        placeSearchProvider: (any PlaceSearchProviding)? = nil
    ) {
        self.appState = appState
        self.speechService = speechService
        self.locationService = locationService
        self.placeSearchProvider = placeSearchProvider
        acceptsPeerLocations = true
        // 坐标取 `latestVolunteerCoordinate` 而不是重算一遍：它已经过了新鲜度闸
        // （WebSocket 那条判 `age <= peerFreshness`，过期由 `schedulePeerExpiry` 清空）。
        voiceQuerySession.configure(
            speechService: speechService,
            speechInputService: speechInputService,
            context: { [weak self] in (self?.order, self?.latestVolunteerCoordinate) }
        )
        subscribeToRealtimeCoordinator(appState: appState)
    }

    /// 按下「问一句」。判定与答句在 `VoiceStatusQuery`，录音与拨号在 `VoiceStatusQuerySession`。
    func askVoiceQuestion() {
        voiceQuerySession.ask()
    }

    /// 陪跑中那屏的「定位正常 / 定位信号弱」。
    ///
    /// 判**本机定位新不新鲜**，复用既有的新鲜度闸（`LocationService.latestBackendSample`），
    /// 不自己再写一套时限。
    ///
    /// 🚩 不绑后端的 `ESCORT_SIGNAL_LOST`：那是一次性告警事件
    /// （`AppRealtimeCoordinator.routeNotification` 把它路由成瞬时提示），没有可持续读的状态；
    /// 而用户看到这一行能做的事只跟本机定位有关。
    ///
    /// 演示坐标一律判成「信号弱」：这一行是安全信息，把 mock 坐标报成「定位正常」，
    /// 用户就会据此认为「播报我的位置」给出的地名是真的。
    /// 🚩 新鲜度取 `escortSampleMaxAge`（60 秒）**而不是** `latestBackendSample` 默认的 15 秒。
    /// 15 秒是求助路径那道闸的值 —— 那一刻宁可说「拿不到位置」也不能用旧坐标。
    /// 这一行是个**常驻指示灯**：等红灯站 20 秒就翻成「信号弱」，它就成了噪音，
    /// 而噪音化的安全指示灯在真的失效时不会有人注意。60 秒的取法与理由见该常量自己的注释。
    var isDeviceLocationFresh: Bool {
        guard let locationService, !locationService.isUsingDemoFallback else { return false }
        return locationService.latestBackendSample(freshness: LocationService.escortSampleMaxAge) != nil
    }

    /// 求助中心里的「播报我的位置」。电话那头的人问「你在哪」时，这是盲人唯一能自己回答的通道。
    ///
    /// 🔴 **拿不到就说拿不到，不编。** 这一句会被用户逐字转述给 110 / 120 ——
    /// 一个猜出来的地名比没有地名危险得多。演示坐标同样一个字都不播（`isUsingDemoFallback`）。
    ///
    /// 两条来源，本机优先：本机定位是此刻的，服务端那份最旧 30 秒，而且只在出发 / 汇合 /
    /// 陪跑中三态才有（匹配中、约好时求助中心同样开着）。本机拿不到或逆地理失败时才问
    /// `GET /api/orders/{id}/location/address`（后端 #387 ①），并照它的 `ageSeconds` 说清新鲜度。
    func announceCurrentLocation() async {
        // 逆地理要走一趟网络。先说一句进行时，否则按下去到出结果之间是一段静默 ——
        // 对看不见屏幕的人，静默就是「点了没反应」。答句回来时会盖掉它，那正是想要的
        // （`.onDemand` 同档相互打断，见 `AnnouncementPriority`）。
        speechService?.speak(EmergencySafetyCopy.locating, priority: .onDemand)
        if let locationService,
           !locationService.isUsingDemoFallback,
           let coordinate = locationService.currentLocation {
            let place = await placeSearchProvider?.reverseGeocode(coordinate: coordinate)
            // `title` 是 POI 名（「人民公园」），`addressText` 是街道级描述。优先念前者：
            // 电话里说得清的是地标，不是一串门牌号。
            if let description = place.flatMap({ $0.title.nilIfBlank ?? $0.addressText.nilIfBlank }) {
                speechService?.speak(EmergencySafetyCopy.locationAnnouncement(description), priority: .onDemand)
                return
            }
        }
        guard let orderId = currentOrderId,
              let response = try? await appState?.safety.orderLocationAddress(orderId: orderId) else {
            speechService?.speak(EmergencySafetyCopy.locationAnnouncement(nil), priority: .onDemand)
            return
        }
        speechService?.speak(EmergencySafetyCopy.locationAnnouncement(server: response), priority: .onDemand)
    }

    func startPolling(orderId: Int64) {
        if currentOrderId != orderId {
            clearPeerLocation()
            // 上限是**这一单**的属性，不是这个 view model 的。换单不清会让新订单
            // 一进来就少一个本来该有的动作。
            keepWaitingLimitReached = false
            // 同理：评价与状态记录都是按单的，留着就会把上一单的内容展示在这一单下面。
            existingReview = nil
            statusLogs = []
            statusLogsErrorMessage = nil
            // 轨迹统计同理，而且更要紧：它是屏幕上最大的那个数字，串单等于显示上一次的里程。
            // 里程碑基线一起清 —— 不清的话新单一开跑就会从上一单的公里数接着算。
            trackStats = nil
            lastTrackFetchAt = nil
            didFetchFinalTrack = false
            kilometerMilestones.reset()
            // 上一单没来得及播的那句完成播报不许跟到新一单上 —— 那会在一张刚下的单上
            // 念「结束了本次陪跑」。
            completionTask?.cancel()
            completionTask = nil
            // 换单时倒计时同样按单清。上一单遗留的任务会往新一单的屏幕上写数字。
            cancelRunCountdown()
        }
        currentOrderId = orderId
        acceptsPeerLocations = true
        appState?.realtimeCoordinator.registerActiveOrder(orderId)
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.loadOrder(orderId: orderId, speakChanges: true)

            while !Task.isCancelled {
                guard let self else { return }
                if !self.shouldContinuePolling {
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(self.effectivePollingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.loadOrder(orderId: orderId, speakChanges: true)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        acceptsPeerLocations = false
        clearPeerLocation()
        cancelRunCountdown()
    }

    func repeatStatus() {
        if let order {
            var announcement = order.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
            // 「继续等待」只有在这里被念到才会被发现：它是等待期唯一的主动作，
            // 而看不见屏幕的人不会知道页面上多了一个按钮。
            if canShowKeepWaiting {
                announcement += " " + KeepWaitingCopy.repeatStatusSuffix
            }
            // 陪跑中与已完成屏幕上那三个数字**只有这一条通道能听全**：它们是 `Text`，
            // 读屏要逐个滑过去才念，而「重复当前状态」/「播报当前数据」是盲人按一下就听全的入口。
            // 用播报口径（`distanceText` 等）而不是屏幕口径 —— `9'06"` 会被念成「九撇零六引号」。
            if let stats = trackStats,
               let clause = Self.spokenStatsClause(stats, isFinished: order.status == .completed) {
                announcement += " " + clause
            }
            // Canonical order status first, emergency state appended after it — never instead of it.
            if let sos = appState?.emergencyCoordinator.repeatStatusSuffix {
                announcement += " " + sos
            }
            // 按需档：用户刚按了「重复当前状态」/「播报当前数据」。它低于「对方操作」——
            // 状态刚推进时那一句比复述更要紧，复述会排在它后面而不是把它切断。
            // 前置音（单声 0.3 秒）由 `AnnouncementCue.leadIn(for:)` 按档自动加。
            speechService?.speak(announcement, priority: .onDemand)
        } else {
            speechService?.speak("正在获取订单状态。", priority: .onDemand)
        }
    }

    /// 刷新后端的等待超时窗口，让订单不被自动取消。
    ///
    /// **按状态分派，且只打这一个端点。** 两个端点的前置状态互斥，409
    /// `ORDER_STATUS_NOT_ALLOWED` 的含义是「你手上的状态已经过期了」——
    /// 此时正确的动作是刷新订单，不是换一个 URL 再打一次。盲人听不见网络请求，
    /// 连打两次的唯一可见结果是等待时间翻倍。
    ///
    /// 刻意**不做二次确认**：这个动作幂等、可重复，且方向是保住订单。误触的代价是多等一会儿，
    /// 而多一轮确认对读屏用户的代价是实打实的十几秒。（取消订单那条的二次确认不受影响。）
    func keepWaiting() async {
        guard let order, let appState else { return }
        guard let endpoint = order.status.keepWaitingEndpoint else {
            let message = "当前订单状态不能继续等待。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        isPerformingAction = true
        errorMessage = nil
        do {
            try await appState.orders.keepWaiting(endpoint, orderId: order.orderId)
            isPerformingAction = false
            // 成功不改状态（后端只回 `{"success": true}`），所以反馈只能由本地这句话给出。
            speechService?.speak(KeepWaitingCopy.success)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            switch error.errorCode {
            case .keepWaitingLimitReached:
                keepWaitingLimitReached = true
                errorMessage = KeepWaitingCopy.limitReached
                speechService?.speakError(KeepWaitingCopy.limitReached)
            case .invalidOrderStatus:
                // 本地状态过期。刷订单让页面回到真实状态，**不重试另一个端点**。
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
                await loadOrder(orderId: order.orderId, speakChanges: true)
            default:
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            }
        } catch {
            isPerformingAction = false
            let message = "继续等待没有成功，请再试一次。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }

    // MARK: - 接单前通话磨合

    /// 拉通话页数据。跟着订单轮询走，不另起一条定时器 —— 这一页本来就每 5 秒刷一次订单。
    ///
    /// **拿不到仍然清空 `introCall`，但必须同时立起 `introCallUnavailable`。**
    ///
    /// 清空是对的，别改成「保留上一轮的号码」：同一个 `PENDING_INTRO_CALL` 里候选人是会换的
    /// （后端 `INTRO_CALL_NOT_ACTIVE` 的说明逐字写着「本轮候选人已换人」），
    /// 留着旧号码就会把电话打给上一位候选人 —— 而屏幕上看不出任何异常。
    ///
    /// 🚨 缺的从来不是「保留数据」，是**说出来**。原来这里是 `try?`，失败与
    /// 「不在通话态」塌缩成同一个 `nil`，于是整块操作区静默消失。
    private func refreshIntroCallIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status == .pendingIntroCall else {
            clearIntroCallState()
            return
        }
        do {
            let view = try await appState.orders.introCallView(orderId: order.orderId)
            introCall = view
            introCallUnavailable = false
            // 服务端说了话就以它为准。换了候选人时它是 nil，本地记号跟着作废 ——
            // 见 `submittedIntroCallDecision` 的注释。
            submittedIntroCallDecision = view.myDecisionValue
        } catch {
            introCall = nil
            // 🚩 **已经表过态就不算失败。** 表态服务端已经记下了，拉不到 view 不改变这件事，
            // 而此刻用户没有任何该做而做不了的事 —— 报错只会盖掉他刚听到的确认，
            // 并在屏幕上摆出一个他不该在这一刻碰到的「换一位」。
            guard submittedIntroCallDecision == nil else { return }
            // **只在 false → true 那一跳播一次。** `loadOrder` 每 5 秒重跑一遍，
            // 每轮都播会把读屏用户淹掉 —— 而他要听的是「这次没拿到，可以重试」，
            // 不是同一句话每 5 秒一遍。
            if !introCallUnavailable {
                introCallUnavailable = true
                speechService?.speakError(IntroCallCopy.loadFailed)
            }
        }
    }

    /// 离开通话态、或换单时把这一族状态整组清掉。**三个字段必须一起动** ——
    /// 少清一个就会让下一单一进通话态就顶着上一单的错误块或表态。
    private func clearIntroCallState() {
        introCall = nil
        introCallUnavailable = false
        submittedIntroCallDecision = nil
    }

    /// 「重新加载」按下时走这里。也是单测的入口：正常路径下通话数据跟着订单轮询一起拉，
    /// 而用例要的是「只拉这一次」—— 起轮询会顺带打订单详情、动状态机，
    /// 把断言埋进一堆无关请求里。
    ///
    /// 2026-08-26 从 `#if DEBUG` 的 `loadIntroCallForTesting` 提成正式方法：
    /// 失败态那个「重新加载」按钮要的正是同一件事，没有理由再留一个只给测试的孪生入口。
    func reloadIntroCall() async {
        guard let order, let appState else { return }
        await refreshIntroCallIfNeeded(for: order, appState: appState)
    }

    /// 先通知对方，然后**立刻**回拨号 URL 给调用方。
    ///
    /// 🚨 **不等响应**：对盲人来说「点了没反应」是最糟的反馈。APNs 到达与对方手机响铃之间
    /// 本就有几秒差，时序天然对得上；推送晚到还有派单文案兜底
    /// （后端 `notify-incoming` 的端点说明逐字写着这一条）。
    ///
    /// 🚨 返回的号码**只能**来自 `dialableCounterpartPhone`。掩码串拼进 `tel:` 会被
    /// `EmergencyDialer.telURL` 取成 `1381234` 拨出去 —— 空号，而界面上看不出任何异常。
    func introCallDialURL() -> URL? {
        guard let order, let appState, let phone = introCall?.dialableCounterpartPhone else { return nil }
        let orders = appState.orders
        let orderId = order.orderId
        Task {
            // 唯一一处刻意吞掉的错误，理由在上面：这是给对方的一条**预告推送**，
            // 不是拨号的前置条件。它失败时用户该做的事（打这通电话）没有任何变化，
            // 屏幕上也不该多出任何东西 —— 拨号 URL 已经返回，电话照打。
            try? await orders.notifyIntroCallIncoming(orderId: orderId)
        }
        return EmergencyDialer.telURL(for: phone)
    }

    /// 通话后的表态。`.accept` = 合适；`.decline` = 换一位。
    ///
    /// ⚠️ 请求体**没有 reason 字段**，这是后端刻意的：要求填理由等于要求当面说「不」。
    /// 成功后不改本地状态 —— 订单是不是转 `PENDING_ACCEPT` 取决于对方，而我们拿不到对方的表态。
    /// 让 5 秒轮询把真实状态带回来。
    func submitIntroCallDecision(_ decision: IntroCallDecision) async {
        guard let order, let appState else { return }
        isPerformingAction = true
        errorMessage = nil
        do {
            try await appState.orders.submitIntroCallDecision(decision, orderId: order.orderId)
            isPerformingAction = false
            // 先落本地记号，再刷订单 —— `loadOrder` 紧接着就会去拉通话数据，
            // 而那一步拉失败时要靠这个记号判「已经表过态，不算失败」。
            // 顺带把失败态收掉：用户是从失败块里按的「换一位」时，那个块该消失了。
            submittedIntroCallDecision = decision
            introCallUnavailable = false
            switch decision {
            case .accept:
                speechService?.speak(IntroCallCopy.waitingForCounterpart)
            case .decline:
                // 🚨 中性、进行时，与常规等待读起来完全一样：不许出现「重新」「换了一位」
                // 这类暗示前面失败过的措辞（无声拒绝）。
                speechService?.speak(IntroCallCopy.continuedSearch)
            }
            await loadOrder(orderId: order.orderId, speakChanges: false)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            // 409 `INTRO_CALL_NOT_ACTIVE` 的常见成因是窗口已经超时。刷订单让页面回到真实状态，
            // 不重试 —— 重试只会得到同一个 409。
            await loadOrder(orderId: order.orderId, speakChanges: true)
        } catch {
            isPerformingAction = false
            let message = "没有提交成功，请再试一次。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }

    func cancelOrder() async {
        guard let order, let appState else { return }
        guard order.status.canBlindRunnerCancel else {
            let message = "当前订单状态不能由盲人取消。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        isPerformingAction = true
        errorMessage = nil
        do {
            try await appState.orders.cancel(orderId: order.orderId)
            isPerformingAction = false
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            let message = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        } catch {
            isPerformingAction = false
            let message = "取消失败。"
            speechService?.speakError(message)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        }
    }

    /// Sends one SOS for the current `IN_PROGRESS` order.
    ///
    /// Every outcome — including "not sent" — is both shown and spoken. A blind runner decides
    /// whether to look for help another way based on this announcement, so silence on failure
    /// would be the worst possible bug here.
    func enterEmergency() async {
        guard let order, let appState else { return }
        let coordinator = appState.emergencyCoordinator
        let outcome = await coordinator.trigger(
            order: order,
            role: appState.activeRole,
            userID: appState.userId,
            safety: appState.safety,
            locate: { await self.freshEmergencyCoordinate() },
            locationFailureReason: { self.locationService?.locationError }
        )
        // The visible surface is `EmergencyStatusNotice`, driven by the coordinator's state.
        // Deliberately not also setting `errorMessage`: that would render the same sentence twice
        // and make VoiceOver read the failure twice over.
        if outcome.isFailure {
            speechService?.speakError(outcome.message, priority: .emergency)
        } else {
            speechService?.speak(outcome.message, priority: .emergency)
        }
    }

    /// 进发出前的 3 秒反悔窗口（屏 3）。
    ///
    /// **两条路径都落到这里**：长按 3 秒 / 自定义无障碍动作直接进来，轻点则先过
    /// `AGENTS.md` §6 那句逐字锁定的二次确认再进来。合成一条不是为了省代码 ——
    /// 发出求助只有一个出口，「两条路的行为哪里不一样」这个问题就不存在，
    /// 而屏 3b 也只需要从一个地方到达。
    ///
    /// 播报交给 `announce` 回调而不是在 coordinator 里播：coordinator 不该知道
    /// 有没有 TTS 这回事（它在志愿者端也跑）。
    func beginEmergencyCountdown() {
        guard let order, let appState else { return }
        appState.emergencyCoordinator.beginCountdown(
            order: order,
            role: appState.activeRole,
            userID: appState.userId,
            safety: appState.safety,
            locate: { await self.freshEmergencyCoordinate() },
            locationFailureReason: { self.locationService?.locationError },
            announce: { [weak self] message in
                // 倒计时每一秒都要盖掉上一秒那句 —— 合成器全进程只有一个、
                // `speak` 自带 `stopSpeaking`，所以「谁后说谁赢」正是这里想要的行为
                // （记忆 `later-speak-silently-cuts-the-earlier-one`）。
                // 🔴 播报队列**刻意保留了同档打断**，这条链路就是它必须保留的理由之一：
                // 同档改成排队的话，三秒倒计时会念成「3」「3」「2」这样的一串旧数字。
                self?.speechService?.speak(message, priority: .emergency)
            }
        )
    }

    /// Withdraws one's own false alarm. The only user-side exit that exists: the escorting volunteer
    /// is refused this action server-side on purpose.
    func cancelEmergency() async {
        guard let appState else { return }
        let outcome = await appState.emergencyCoordinator.cancelByOwner(safety: appState.safety)
        if outcome.isFailure {
            speechService?.speakError(outcome.message, priority: .emergency)
        } else {
            speechService?.speak(outcome.message, priority: .emergency)
        }
    }

    /// 新鲜真实坐标，实现在 `EmergencyCoordinator.freshEmergencyCoordinate(using:)`。
    ///
    /// 2026-08-07 从这里提走：首页 SOS 条是第二个求助入口，而这段逻辑的每一条都是安全约束
    /// （只接受真实设备采样、演示坐标进不来、拿不到就返回 nil 让上层如实播报「未发出」）。
    /// 两份实现意味着这条保证要守两遍，迟早漂移。
    ///
    /// `IN_PROGRESS` 期间实时陪跑会话每 5 秒采样一次，所以那次有界重试只在刚起跑
    /// 或位置更新短暂暂停时才用得上。
    private func freshEmergencyCoordinate() async -> LocatedCoordinate? {
        await EmergencyCoordinator.freshEmergencyCoordinate(using: locationService)
    }

    func submitReview() async {
        guard let order, let appState, order.status == .completed else { return }
        guard (1...5).contains(reviewRating) else {
            errorMessage = "请选择 1 到 5 星评分。"
            speechService?.speakError("请选择 1 到 5 星评分。")
            return
        }

        isSubmittingReview = true
        errorMessage = nil
        do {
            let request = CreateReviewRequest(
                rating: reviewRating,
                comment: reviewComment.nilIfBlank
            )
            try await appState.orders.submitReview(request, orderId: order.orderId)
            isSubmittingReview = false
            didSubmitReview = true
            speechService?.speak("评价已提交，感谢反馈。")
        } catch let error as APIError {
            isSubmittingReview = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            // 已评价过不是失败：用户就站在这一单的评价页上，能做的正确动作只有把页面切到已评价态。
            // 后端 2026-07-31 起用专用码 REVIEW_ALREADY_SUBMITTED，不再与 DUPLICATE_ORDER 混用。
            if error.errorCode == .reviewAlreadySubmitted {
                didSubmitReview = true
                speechService?.speak(ErrorCode.reviewAlreadySubmitted.localizedMessage)
                // 把那条已存在的评价取回来念给用户听。否则「已评价过此订单」之后是一片空白，
                // 用户既不知道自己当初打了几分，也无从判断要不要联系客服。
                await loadExistingReview()
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isSubmittingReview = false
            errorMessage = "评价提交失败，请稍后重试。"
            speechService?.speakError("评价提交失败，请稍后重试。")
        }
    }

    func skipReview() {
        didSubmitReview = true
        speechService?.speak("已跳过评价，返回首页。")
    }

    /// 取回本单已有的评价（`GET /api/orders/{id}/reviews`，订单双方均可查）。
    ///
    /// 尚未评价时后端回 200 + `data: null`，那是正常业务状态：`existingReview` 保持 nil，
    /// 评价表单照常展示。**只在 `COMPLETED` 调** —— 其余状态下这一单不可能有评价。
    func loadExistingReview() async {
        guard let order, let appState, order.status == .completed else { return }
        do {
            let envelope = try await appState.orders.reviews(orderId: order.orderId)
            existingReview = envelope.data
            if envelope.data != nil {
                didSubmitReview = true
            }
        } catch {
            // 刻意不报错、不播报：拿不到已有评价的唯一后果是评价表单多摆一次，
            // 而重复提交那一路已经由 `REVIEW_ALREADY_SUBMITTED` 兜住（见 `submitReview`）。
            // 为一块只读的辅助信息打断服务播报，代价比它自己大。
        }
    }

    // MARK: - 把这一单的志愿者设为固定搭档

    /// 这位志愿者是不是已经在固定搭档列表里。`nil` = 还没查到（含查失败）。
    ///
    /// 🚩 **三态而不是 Bool。** 查失败时若落成 `false`，页面会摆出「设为固定搭档」按钮，
    /// 而他可能早就收藏过了 —— 点下去后端幂等返 204，于是用户听到「已把陈*设为固定搭档」，
    /// 以为自己刚做成了一件其实几周前就做过的事。整块不渲染是唯一诚实的降级。
    @Published private(set) var isVolunteerFavorited: Bool?
    /// 收藏成功后的那句话。与 `errorMessage` 分开：那条每轮轮询都会被 `loadOrder` 清空，
    /// 而这一句要留到用户划到它（理由同 `statusLogsErrorMessage`）。
    @Published private(set) var favoriteNotice: String?
    @Published private(set) var favoriteErrorMessage: String?
    @Published private(set) var isUpdatingFavorite = false

    /// 查一次「这位志愿者收藏过没有」。**只在 `COMPLETED` 且后端给了 `volunteerId` 时调**。
    ///
    /// 为什么要多打一次 `/api/blind/favorite-volunteers`：`OrderDetailResponse` 只说这一单是谁陪的，
    /// 说不出「他是不是我的固定搭档」。没有这一次查询，按钮只能恒显示「设为固定搭档」，
    /// 对已经收藏过的搭档就是一句假话。
    ///
    /// 失败一律静默（同 `loadExistingReview`）：这是主路径之外的一块附属动作，
    /// 拿不到的唯一后果是整块不出现，不值得打断服务播报。
    func loadFavoriteStateIfNeeded() async {
        guard let order, let appState,
              order.status == .completed,
              let volunteerId = order.volunteerId else { return }
        do {
            let favorites = try await appState.incentive.blindFavoriteVolunteers()
            isVolunteerFavorited = favorites.contains { $0.volunteerId == volunteerId }
        } catch {
            isVolunteerFavorited = nil
        }
    }

    /// `PUT /api/blind/favorite-volunteers/{volunteerId}` —— 幂等，恒 204。
    ///
    /// **只做添加，不做取消。** 取消收藏在设置页的固定搭档列表里，那里看得到全部搭档；
    /// 在一张订单详情上给「取消收藏」，用户取消的是一段跨越很多次跑步的关系，
    /// 而他眼前只有其中一次的上下文。
    func addVolunteerToFavorites() async {
        guard let order, let appState, let volunteerId = order.volunteerId else { return }
        let name = order.volunteerName?.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
        isUpdatingFavorite = true
        favoriteErrorMessage = nil
        defer { isUpdatingFavorite = false }
        do {
            try await appState.incentive.addBlindFavoriteVolunteer(volunteerId: volunteerId)
            isVolunteerFavorited = true
            let notice = PartnerStreakCopy.favoriteAdded(name)
            favoriteNotice = notice
            // 盲人端：结果必须念出来。屏幕上那行字是看得见的一半，播报是听得见的那一半。
            speechService?.speak(notice)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            // 两个收藏专属错误码（`FAVORITE_VOLUNTEER_NOT_ELIGIBLE` / `..._LIMIT_EXCEEDED`）
            // 的文案已经挂在 `ErrorCode.localizedMessage:289-292` 上，这里不再映射一遍 ——
            // 映射第二份的代价是两处文案迟早分叉，而分叉的那一半没有任何东西会报警。
            let message = error.localizedMessage
            favoriteErrorMessage = message
            speechService?.speakError(message)
        } catch {
            favoriteErrorMessage = PartnerStreakCopy.favoriteFailed
            speechService?.speakError(PartnerStreakCopy.favoriteFailed)
        }
    }

    /// 取回本单的状态变更记录（`GET /api/orders/{id}/status-logs`，订单双方均可查）。
    ///
    /// 响应是裸数组，后端已按时间**倒序**返回（`OrderStatusLogRepository:16`），这里不重排。
    func loadStatusLogs() async {
        guard let order, let appState else { return }
        isLoadingStatusLogs = true
        statusLogsErrorMessage = nil
        do {
            let logs = try await appState.orders.statusLogs(orderId: order.orderId)
            isLoadingStatusLogs = false
            statusLogs = logs
        } catch let error as APIError {
            isLoadingStatusLogs = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            statusLogsErrorMessage = error.localizedMessage
        } catch {
            isLoadingStatusLogs = false
            statusLogsErrorMessage = "获取状态变更记录失败。"
        }
    }

    private var shouldContinuePolling: Bool {
        guard let order else { return true }
        return order.status.shouldPoll
    }

    private func loadOrder(orderId: Int64, speakChanges: Bool) async {
        guard let appState else { return }
        var refreshedAuthoritativeOrder = false
        defer {
            if refreshedAuthoritativeOrder {
                appState.realtimeCoordinator.completeOrderRefresh(orderId)
            } else {
                appState.realtimeCoordinator.failOrderRefresh(orderId)
            }
        }
        if order == nil {
            isLoading = true
        }
        errorMessage = nil

        do {
            let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderId)
            let orders = appState.orders
            let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                timeout: HomeLoadPolicy.defaultTimeout,
                operationName: "blind-order-poll"
            ) {
                try await orders.orderDetail(orderId: orderId)
            }
            guard let updated = appState.realtimeCoordinator.reconcileOrderDetail(
                candidate,
                requestToken: requestToken
            ) else {
                isLoading = false
                return
            }
            refreshedAuthoritativeOrder = true
            isLoading = false
            apply(updated, speakChanges: speakChanges)
            await refreshIntroCallIfNeeded(for: updated, appState: appState)
            await refreshVolunteerLocationFallbackIfNeeded(for: updated, appState: appState)
            // 完成那一轮这里大概率**拉不到**（`apply` 刚刚自我取消了这个任务），
            // 所以终值那一次由 `startCompletionAnnouncement` 的独立任务负责 ——
            // 而 `didFetchFinalTrack` 只在**成功**时置位，这一次失败不会把那条路堵掉。
            await refreshTrackStatsIfNeeded(for: updated, appState: appState)
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "获取订单状态失败。"
            speechService?.speakError("获取订单状态失败。")
        }
    }

    private func performAction(
        failureMessage: String,
        operation: () async throws -> Void
    ) async {
        isPerformingAction = true
        errorMessage = nil

        do {
            try await operation()
            isPerformingAction = false
        } catch let error as APIError {
            isPerformingAction = false
            if appState?.handleAuthenticatedAPIError(error) == true {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isPerformingAction = false
            errorMessage = failureMessage
            speechService?.speakError(failureMessage)
        }
    }

    private func apply(_ updated: OrderDetailResponse, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: updated.orderId, status: updated.status)
        // 锁屏卡顶行那句「陪跑中 · 张伟」。名字只有这一端拿得到，所以**排在
        // `updateOwnedOrder` 之后** —— 换单时它内部会 `clearRuntimeSession()`，
        // 那里要清掉上一单的名字，排在前面会被当场擦掉。
        // 名字住在 `ContentState` 里（不是 `attributes`），所以后到也补得上，见那里的注释。
        appState?.liveEscortCoordinator.updateLiveActivityPartnerName(updated.volunteerName?.nilIfBlank)
        refreshVolunteerDistance()
        updateRunCountdown(from: previousStatus, to: updated.status)
        if speakChanges, previousStatus != updated.status {
            if let completion = Self.completionAnnouncement(from: previousStatus, to: updated.status) {
                // 不在这里播 —— 里程要等 `/track` 的终值回来，而这一刻紧接着就要自我取消。
                startCompletionAnnouncement(completion, order: updated)
            } else {
                speechService?.speakStatusChange(
                    updated.status,
                    text: statusChangeAnnouncement(from: previousStatus, to: updated)
                )
            }
        }
        if updated.status != .pendingIntroCall {
            clearIntroCallState()
        }
        if !updated.status.shouldPoll {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            if updated.status != .completed {
                appState?.liveEscortCoordinator.clearOwnedOrder()
            }
            stopPolling()
        }
    }

    /// 汇合 → 跑步中那三秒倒计时。
    ///
    /// 🔴 **触发点是「志愿者把状态推到了 `IN_PROGRESS`」，不是盲人按了什么。**
    /// 设计稿写的是「任一端按下开始跑步（双方都能按，先按的生效）」，而后端
    /// `OrderLifecycleService.startService` 走的是 `loadForVolunteer(...)`，盲人 token
    /// 一律被判 `NOT_ORDER_PARTICIPANT`（403）—— 盲人端根本调不动 `/start-service`。
    /// 所以这一端没有「开始跑步」按钮（① 汇合的主按钮仍是「打电话给张伟」），
    /// 倒计时改挂在状态推进上。**已投 handoff 请后端放开盲人 token**；放开之后
    /// 只需在 ① 加一枚按钮调 `orders.startService`，这里一行都不用改。
    ///
    /// 两条边界都要守住，而且方向相反：
    /// - `previousStatus == nil` ⇒ **冷启动进来时已经在跑了**，不倒数。中途进页面的人
    ///   听一遍「准备开始」是在说一件三公里以前发生过的事。
    /// - `previousStatus == .inProgress` ⇒ 同一态的重复刷新（每 5 秒一轮），不重放。
    ///
    /// 播报走 `announce`（VoiceOver announcement 通道）而**不是** `speak`：
    /// `SpeechService.speak` 会先 `stopSpeaking(.immediate)`，紧接着三拍数字会把
    /// 同一刻正在播的「陪跑服务已开始」整句切断，表现是「只念了开头」
    /// （记忆 `later-speak-silently-cuts-the-earlier-one`）。announcement 不抢合成器、
    /// 也不移动读屏焦点 —— 焦点在这三秒里必须待在原处，那正是原地变形要保住的东西。
    /// `状态清单.md` §2 也是逐字这么要求的：「数字走 announcement 通道播报，
    /// 不插入遍历顺序、不移动焦点」。
    /// 判据抽成**纯静态函数**，理由同 `FlowStepper.accessibilityLabel`：三秒倒计时本身
    /// 只有真机能看，但「什么时候该倒数」是两个布尔判断，不该也要开一次真机才知道对不对。
    /// 上面那两条边界（冷启动不倒数 / 同态刷新不重放）各有一条用例钉着。
    nonisolated static func shouldStartRunCountdown(
        from previousStatus: RunOrderStatus?,
        to status: RunOrderStatus
    ) -> Bool {
        guard status == .inProgress, let previousStatus else { return false }
        return previousStatus != .inProgress
    }

    /// 🔴 **不是「不该倒数就 return」，是「不该倒数就取消」。**
    ///
    /// 志愿者在开跑后三秒内取消（`IN_PROGRESS → REMATCHING`，走 WebSocket 的
    /// `statusUpdatePublisher`）时，只 return 的写法会让旧 Task 照常跑完剩下两拍：
    /// 屏幕是对的（相位已经落回 `.beforeRun`），而耳朵和手指是错的 —— 刚听完
    /// 「陪跑员取消了，正在重新为你匹配」，紧接着念「2」「1」并震两下。
    /// 同一形状也适用于 `IN_PROGRESS → COMPLETED`。
    private func updateRunCountdown(from previousStatus: RunOrderStatus?, to status: RunOrderStatus) {
        if Self.shouldStartRunCountdown(from: previousStatus, to: status) {
            startRunCountdown()
        } else if Self.shouldCancelRunCountdown(on: status) {
            cancelRunCountdown()
        }
    }

    /// 与 `shouldStartRunCountdown` 一样抽成纯函数：这两条**不是互补的**
    /// （「不该启动」≠「该取消」—— 同一态的每 5 秒轮询既不该启动也不该取消），
    /// 所以各需要一条自己的用例，写成一个函数的取反会把那个区别抹掉。
    nonisolated static func shouldCancelRunCountdown(on status: RunOrderStatus) -> Bool {
        status != .inProgress
    }

    private func startRunCountdown() {
        runCountdownTask?.cancel()
        runCountdownTask = Task { @MainActor [weak self] in
            for beat in BlindRunCountdown.beats {
                guard let self, !Task.isCancelled else { return }
                self.runCountdown = beat
                // 每拍**轻震**（设计稿逐字）。用 `.tick` 而不是 `.success`：
                // 后者是通知波形，紧接着 `speakStatusChange(.inProgress)` 也会震一次，
                // 三秒里四次同样的波形等于把触觉这条通道的语义洗掉。见 `HapticFeedback.Kind.tick`。
                HapticFeedback.play(.tick)
                // 阶段 1 留下的账①已结：这三拍**不再绕开播报 funnel**。
                // 通告仍然是通告（合成器一个字都不抢），但现在要过一道优先级闸 ——
                // 此刻若正在播求助或警示，这三个数字不会盖掉它
                // （`AnnouncementQueue.allowsAnnouncement`）。档位按 `状态清单.md` §2 取「对方操作」。
                self.speechService?.announce("\(beat)", priority: .counterpartAction)
                try? await Task.sleep(
                    nanoseconds: UInt64(BlindRunCountdown.beatInterval * 1_000_000_000)
                )
            }
            guard let self, !Task.isCancelled else { return }
            self.runCountdown = nil
            // 🔴 **「现在可以跑了」这一刻必须有信号。**
            //
            // 唯一那句「陪跑服务已开始」是三秒**之前**播的（状态刚推过来时），
            // 而变形完成这一刻此前什么都不发生 —— 对看不见屏幕的人，
            // 起跑这个动作没有任何起点。设计稿 §3 逐字：「开始时『开始跑步』+ 强震一次」。
            //
            // 走 `speak` 而**不是** `announce`：VoiceOver 关着时 announcement 是 no-op，
            // 而低视力用户同样需要听到这一句。
            //
            // 阶段 1 留下的账②已结：排进「对方操作」档之后，此刻若正在播求助或警示，
            // 这一句会**排队等它说完**而不是把它切断（`AnnouncementQueue.submit`）；
            // 正在播的若是每公里或按需那两档，它照旧抢过来 —— 起跑这一刻比复述里程要紧。
            self.speechService?.speak(
                BlindRunCopy.runStartedAnnouncement, priority: .counterpartAction
            )
            HapticFeedback.play(.success)
        }
    }

    /// 换单 / 离开页面时收掉倒计时。
    ///
    /// 不收的后果不是「多演三秒」而是**状态错乱**：任务还在往 `runCountdown` 写值，
    /// 而订单可能已经换成另一单了 —— 那一单的屏幕上会凭空倒数一次。
    private func cancelRunCountdown() {
        runCountdownTask?.cancel()
        runCountdownTask = nil
        runCountdown = nil
    }

    /// 状态推进时该播哪一句。除了一处例外，都是 `blindRunnerAnnouncement`。
    ///
    /// 例外是**通话没聊成、退回派单队列**。两个落点各自的常规播报在这一刻都是错的：
    /// - `PENDING_MATCH` 念「订单提交成功，系统正在为你派单」—— 订单是二十分钟前提交的。
    /// - `REMATCHING` 念「正在确认志愿者状态，请稍候」—— 这一刻**没有志愿者可确认**，
    ///   刚才那位候选人从来就没接过单。
    ///
    /// 后端为这条转移专门发了 `INTRO_CALL_CONTINUE`（正文「正在为你寻找合适的陪跑伙伴」），
    /// 两个落点逐字复用它 —— 后端也**刻意**对两种状态发同一条中性文案，不为 `REMATCHING` 另开一条。
    ///
    /// ⚠️ `REMATCHING` 这个落点是 2026-08-26 后端修 P0（N105）之后才有的：通话退出改成回
    /// 「进通话之前那个状态」，而进通话之前它可能就是 `REMATCHING`。
    ///
    /// 🚨 措辞里不许出现「重新」「换一位」「再找一位」这类暗示前面失败过的词：
    /// 无声拒绝的全部要求就是盲人无从得知自己被谁拒过。
    private func statusChangeAnnouncement(
        from previousStatus: RunOrderStatus?,
        to updated: OrderDetailResponse
    ) -> String {
        if previousStatus == .pendingIntroCall,
           updated.status == .pendingMatch || updated.status == .rematching {
            return IntroCallCopy.continuedSearch
        }
        return updated.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
    }

    func handleVolunteerLocationUpdate(_ sample: RealtimePeerLocationSample) {
        guard acceptsPeerLocations,
              sample.ownerRole == .volunteer,
              sample.orderId == activeOrderId else { return }
        let capturedAt = Date(timeIntervalSince1970: TimeInterval(sample.timestampMilliseconds) / 1_000)
        let age = max(0, Date().timeIntervalSince(capturedAt))
        guard age <= peerFreshness,
              let located = BackendCoordinateNormalizer.backend(
            latitude: sample.latitude,
            longitude: sample.longitude,
            capturedAt: capturedAt
        ) else { return }

        latestVolunteerWebSocketDate = capturedAt
        latestVolunteerSample = located
        latestVolunteerCoordinate = located.coordinate
        refreshVolunteerDistance()
        schedulePeerExpiry(for: located, orderID: sample.orderId, remaining: peerFreshness - age)
    }

    func handleVolunteerLocationUpdate(_ message: WSVolunteerLocationUpdate) {
        handleVolunteerLocationUpdate(
            RealtimePeerLocationSample(
                orderId: message.orderId,
                ownerRole: .volunteer,
                latitude: message.lat,
                longitude: message.lng,
                timestampMilliseconds: message.timestamp
            )
        )
    }

    // `shouldSuppressDirectNotificationSpeech(_:)` 已于 2026-08-09 删除（连同 31 条中文片段表）。
    //
    // 它按通知正文的中文片段决定要不要抑制播报，而**生产代码里一个调用点都没有** ——
    // 唯一的调用者是它自己的那条测试。抑制实际发生在 `AppRealtimeCoordinator`，
    // 那边已经改成按 `eventType` 判定（`lifecycleStatus(forEventType:)`）。
    //
    // 删掉而不是留着的理由不是「没人用」，是**它会被照抄**：按正文匹配意味着后端改任何一条
    // 通知模板的正文都会静默改变 iOS 的播报行为，后端新增的 `REMATCH_ACCEPTED` 就是这么被吞掉的。
    // 片段表里还混着 `"测试志愿者"` / `"志愿者测试"` 两条——测试数据渗进产品代码，
    // 本身就是这段代码只为测试而活的证据。

    private var activeOrderId: Int64? {
        order?.orderId ?? currentOrderId
    }

    private func schedulePeerExpiry(
        for sample: LocatedCoordinate,
        orderID: Int64,
        remaining: TimeInterval
    ) {
        peerExpiryTask?.cancel()
        peerExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(0.01, remaining) * 1_000_000_000)
                )
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.activeOrderId == orderID,
                  self.latestVolunteerSample == sample else { return }
            self.clearPeerLocation()
        }
    }

    private func clearPeerLocation() {
        peerExpiryTask?.cancel()
        peerExpiryTask = nil
        latestVolunteerSample = nil
        latestVolunteerCoordinate = nil
        latestVolunteerWebSocketDate = nil
        refreshVolunteerDistance()
    }

    private func refreshVolunteerDistance() {
        guard let order, order.status.offersVolunteerDistanceToStart else {
            volunteerDistanceToStartText = nil
            return
        }
        volunteerDistanceToStartText = order.volunteerDistanceToStartText(from: latestVolunteerCoordinate)
    }

    /// 🚩 判据是 `fetchesVolunteerLocation`（后端 `sharesLiveLocation()` 那三态），
    /// **不是** `offersVolunteerDistanceToStart`（念不念距离那两态）。两者 2026-08-31 拆开，
    /// 拆之前这里用后者，于是 `PENDING_ACCEPT` 每 5 秒白调一次、`IN_PROGRESS` 一次都不调 ——
    /// 而 `IN_PROGRESS` 正是走散检测唯一需要兜底的那一段。
    private func refreshVolunteerLocationFallbackIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status.fetchesVolunteerLocation else { return }
        let websocketSampleIsFresh = latestVolunteerWebSocketDate.map { Date().timeIntervalSince($0) <= 15 } ?? false
        guard !appState.isWebSocketConnected || !websocketSampleIsFresh else { return }

        do {
            let response = try await appState.orders.volunteerLocation()
            guard let coordinate = Self.volunteerFallbackCoordinate(from: response.data, matching: order) else { return }
            latestVolunteerCoordinate = coordinate
            refreshVolunteerDistance()
            feedEscortPeerLocation(from: response.data, coordinate: coordinate, order: order, appState: appState)
        } catch {
            // 订单轮询才是权威源，兜底拿不到位置不致命 —— 所以这里既不清空已知位置，也不播报。
            //
            // **404 尤其不是错误**：位置 key 不存在（志愿者超过 TTL 没上报）后端就返 404，
            // 契约明写「这是正常情况，客户端应静默保持上一个已知位置，别念报错」
            // （`api_spec.yaml:2365-2366`）。对盲人来说，陪跑途中每隔几秒念一次
            // 「获取位置失败」既没有可执行的动作，又会占住他用来听环境和陪跑员说话的通道。
        }
    }

    /// 拉陪跑中与已完成那两屏的三个数字。跟着订单轮询走，节流到 `trackPollingInterval`。
    ///
    /// 三种走法，别合并：
    /// - `IN_PROGRESS` —— 按 10 秒节流反复拉，顺带判每公里里程碑。
    /// - `COMPLETED` —— **绕过节流拉最后一次终值**，之后不再拉；里程碑基线清掉
    ///   （再进同一单不该补播一次「已跑 5 公里」）。数字**不清空**：它就是 ④ 那一屏的内容。
    /// - 其余状态 —— 三样一起清掉（统计 / 节流时刻 / 里程碑基线）。少清一个，
    ///   下次进同一单就会顶着上一段的数字，或者一进来就补播一次里程碑。
    private func refreshTrackStatsIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        // 里程碑基线：只要不在跑动中就清。完成态也清 —— 否则再进同一单会补播一次
        // 「已跑 5 公里」。放在决策之外是因为它对 `.skip` 与 `.fetch` 两条路都要做。
        if order.status != .inProgress { kilometerMilestones.reset() }

        var isFinalTrackFetch = false
        switch Self.trackFetchDecision(
            status: order.status,
            didFetchFinalTrack: didFetchFinalTrack,
            lastFetchAt: lastTrackFetchAt,
            now: Date()
        ) {
        case .clear:
            trackStats = nil
            lastTrackFetchAt = nil
            didFetchFinalTrack = false
            return
        case .skip:
            return
        case .fetch(let isFinal):
            lastTrackFetchAt = Date()
            isFinalTrackFetch = isFinal
        }

        do {
            let safety = appState.safety
            let orderID = order.orderId
            // 🔴 **终值那一次必须限时。** 完成播报排在它后面，而 `URLSession` 的请求超时是
            // 15 秒、资源超时 20 秒（`APIClient.swift:282-283`）—— 网络一抖，
            // 「张伟结束了本次陪跑」就可能十几秒之后才出声。对刚刚跑完、看不见屏幕的人，
            // 那十几秒里发生的事是「陪跑员松开了引导绳，而 App 一个字没说」。
            // 跑动中那条不限时：它每 10 秒还有下一次，早一秒晚一秒没人听得出来。
            let track: OrderTrackResponse
            if isFinalTrackFetch {
                track = try await HomeLoadCoordinator.run(
                    timeout: Self.finalTrackDeadline,
                    operationName: "blind-order-final-track"
                ) {
                    try await safety.orderTrack(orderId: orderID)
                }
            } else {
                track = try await safety.orderTrack(orderId: orderID)
            }
            trackStats = track.blindStats
            // 🔴 **只在成功之后才算「终值拉过了」。** 置位放在请求之前的写法会让任何一次
            // 失败（网络抖动、或者上面那次自我取消）把这一单永久锁在 `.skip` 上 ——
            // 屏幕上三个 `--`、而读屏还会一直念「正在获取」，也就是一直撒谎。
            if isFinalTrackFetch { didFetchFinalTrack = true }
            // 下面两件事**只在跑动中做**，已完成那一次终值拉取不做：
            // ① 锁屏卡在 `COMPLETED` 已经该结束了（`liveActivityPlan` 判 nil），
            //    往一张正在收起的卡上推数字只会多一次同步；
            // ② 里程碑基线刚在上面被 reset，这一次调用必然只定基线、不播 ——
            //    靠那个隐式事实等于把「跑完之后不补播已跑 N 公里」寄托在另一个函数的内部行为上。
            if order.status == .inProgress {
                // 推给锁屏卡，顺带复位它自己的节流器 —— 不推的话协调器会为同一单再拉一次
                // 同一个 `/track`，跑动中每 10 秒多发一个请求。
                appState.liveEscortCoordinator.submitTrackStats(track.blindStats, orderID: order.orderId)
                announceKilometerMilestoneIfNeeded(track.blindStats)
            }
        } catch {
            // **不清空已有的数字、不播报。** 与 `refreshVolunteerLocationFallbackIfNeeded` 同一条理由：
            // 跑动中一次网络抖动把屏幕上的距离归零，比暂时不更新糟得多；而每 10 秒往耳朵里塞一句
            // 「获取失败」会占住盲人用来听车流和同伴说话的那条通道，且没有任何可执行的动作。
        }
    }

    /// 页面那次不限时的轨迹加载（`CompletedTrackSummaryViewModel.load`，喂 footer 的
    /// 轨迹总结）回来之后，把数字补给卡片与「重复当前状态」。
    ///
    /// 🚩 它只在**终值那一次限时到点或失败**时才有活干：正常路径上 `trackStats` 已经有值，
    /// 这里 guard 掉。不补的后果是 ④ 那张卡顶着三个 `--`，而同一页下面的轨迹总结里
    /// 明明有数字 —— 同一屏上两个矛盾的事实，对读屏用户尤其难解释。
    func adoptCompletedTrackStats(_ stats: TrackStats?) {
        guard order?.status == .completed, trackStats == nil, let stats else { return }
        trackStats = stats
    }

    /// 这一轮要不要拉 `/track`。
    enum TrackFetchDecision: Equatable {
        /// 拉。`isFinal` = 这是完成态那唯一一次终值拉取。
        case fetch(isFinal: Bool)
        /// 不拉，但屏幕上已有的数字**留着**。
        case skip
        /// 不拉，并且把数字清掉（这一态不该有数字）。
        case clear
    }

    /// 判据抽成纯函数，理由同 `shouldStartRunCountdown`：这里三条分支的错误形态全是静默的
    /// —— 完成态误落 `.clear` ⇒ ④ 那一屏三个数字变 `--`（而它的全部内容就是那三个数）；
    /// 完成态照节流走 ⇒ 屏幕停在最后一个中途值；跑动中漏了节流 ⇒ 每 5 秒多发一个请求。
    nonisolated static func trackFetchDecision(
        status: RunOrderStatus,
        didFetchFinalTrack: Bool,
        lastFetchAt: Date?,
        now: Date
    ) -> TrackFetchDecision {
        switch status {
        case .inProgress:
            if let lastFetchAt, now.timeIntervalSince(lastFetchAt) < trackPollingInterval {
                return .skip
            }
            return .fetch(isFinal: false)
        case .completed:
            // 🔴 **刻意不看节流。** 完成那一刻上一次跑动中的拉取往往还在 10 秒窗内，
            // 照节流跳过就把中途值（5.18）留在了 ④ 那一屏上。拉过一次就不再拉 ——
            // 已完成的轨迹不会再变。
            return didFetchFinalTrack ? .skip : .fetch(isFinal: true)
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
             .driverEnRoute, .driverArrived, .rematching, .cancelled, .noVolunteer, .unknown:
            return .clear
        }
    }

    /// 完成那一刻**唯一**那一句。`/track` 的终值拉过之后才调（`loadOrder` 末尾）。
    ///
    /// 走 `speakStatusChange` 这个 funnel 而不是直接 `speak`，是为了拿它那两件东西：
    /// 「同一状态只播一次」的 guard（跨轮询、跨重进页面）与 `RunOrderStatus.haptic`
    /// —— 强震一次就挂在那张表上（`.completed` → `.strong`），
    /// 在这里另外补一次 `HapticFeedback.play` 会变成两下。
    ///
    /// 🔴 **不在这里判「里程为空就不播」**：这件事（陪跑结束了）比那个数字要紧得多，
    /// `runFinishedAnnouncement` 自己会在拿不到里程时把那半句去掉。
    private func startCompletionAnnouncement(
        _ kind: CompletionAnnouncement,
        order: OrderDetailResponse
    ) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            guard let self else { return }
            // 拉终值。限时 3 秒（`finalTrackDeadline`）—— 拉不到就带着没有里程的那一句出声。
            if let appState = self.appState {
                await self.refreshTrackStatsIfNeeded(for: order, appState: appState)
            }
            // 🔴 **刻意不走 `speakStatusChange` 那个 funnel。** 它的 guard 是
            // `status != lastSpokenStatus`，而 `lastSpokenStatus` 是**全 App 一份**的
            // （`SpeechService` 是 `blindRunApp` 上的 `@StateObject`）——
            // 连着从历史记录点开两张已完成的单，第二张会被静默吞掉：两张单的状态
            // 都是 `COMPLETED`，而「状态变了没有」是**每张单各自**的事实。
            // 这一条恰好打在 `.coldStart` 存在的理由上（它就是为「点开一张旧单」写的），
            // 且改版前由 `.task` 里那句轨迹总结兜着 —— 那句已经删了。
            // 用例 `testTwoFinishedOrdersInARowBothSpeak` 钉住（打回 funnel 写法即红）。
            //
            // 去重责任因此留在 view model 这一层，那里本来就是按单记的：
            // `completionAnnouncement(from:to:)` 要求 `previousStatus != .completed`，
            // 而 `apply` 的三个调用者都在主 actor 上、`order` 是同步写的 ⇒ 不存在交错窗口。
            //
            // 触觉跟着这一句就地播，而不是靠 `RunOrderStatus.haptic` 那张表 ——
            // 「触觉必须伴随一句话」那条不变量要的是**同生同灭**，这里两行紧挨着；
            // 而走 funnel 的版本在上面那种情况下是**话没播、震也不震**（整条返回 false）。
            self.speechService?.speak(
                Self.completionAnnouncementText(kind, order: order, stats: self.trackStats),
                priority: .counterpartAction
            )
            HapticFeedback.play(.strong)
        }
    }

    /// 完成那一句的正文。纯函数，两种语境各一句。
    nonisolated static func completionAnnouncementText(
        _ kind: CompletionAnnouncement,
        order: OrderDetailResponse,
        stats: TrackStats?
    ) -> String {
        switch kind {
        case .justFinished:
            return BlindRunCopy.runFinishedAnnouncement(
                name: order.volunteerNameForSpeech,
                distanceText: stats?.distanceText
            )
        case .coldStart:
            // 既有的状态句 + 三个数字。数字这一半原先由 `.task` 里那句轨迹总结承担，
            // 而它**同档打断**了状态句（记忆 `later-speak-silently-cuts-the-earlier-one`）——
            // 合成一句之后两半都能听全。
            var parts = [order.blindRunnerAnnouncement(distanceText: nil)]
            if let stats, let clause = spokenStatsClause(stats, isFinished: true) {
                parts.append(clause)
            }
            return parts.joined(separator: " ")
        }
    }

    /// 三个数字的**播报**口径（`9'06"` 会被念成「九撇零六引号」，所以不能用屏幕口径）。
    ///
    /// 抽出来是因为它有两个调用点 —— 「重复当前状态」与完成播报。两处各拼一份的下场是
    /// 同一组数字在两个入口念得不一样，而屏幕上不会有任何症状。
    nonisolated static func spokenStatsClause(_ stats: TrackStats, isFinished: Bool) -> String? {
        let spoken = [
            stats.distanceText.map { "已跑 \($0)" },
            stats.durationText.map { "用时 \($0)" },
            // 标签与那一屏上写的那格一致（③「配速」/ ④「平均配速」，判据在 `BlindRunCopy`）。
            stats.averagePaceText.map { "\(BlindRunCopy.metricPaceLabel(isFinished: isFinished)) \($0)" }
        ].compactMap { $0 }
        guard !spoken.isEmpty else { return nil }
        return spoken.joined(separator: "，") + "。"
    }

    /// 每跑满一公里播一句「已跑 N 公里」。**只播距离** —— 不播配速、心率、卡路里
    /// （`docs/research/blind-runner-ui-reference-study-20260915.md` §7.4）。
    /// 播不播的判定在 `KilometerMilestoneTracker`，这里只负责发声与震动。
    private func announceKilometerMilestoneIfNeeded(_ stats: TrackStats) {
        guard let kilometers = kilometerMilestones.milestone(forDistanceMeters: stats.distanceMeters) else {
            return
        }
        // 最低档：正在播的任何别的东西都比它要紧，而它排队超过 10 秒就自己丢掉
        // （`AnnouncementQueue.perKilometerMaxQueueAge`）—— 一句迟到的「已跑 2 公里」
        // 会让跑者按一个过期的数字去判断还能跑多久。前置音（单声 0.3 秒）按档自动加。
        speechService?.speak("已跑 \(kilometers) 公里", priority: .perKilometer)
        // ponytail: 复用既有的三种系统语义之一，不为里程碑自造波形（见 `HapticFeedback`）。
        HapticFeedback.play(.success)
    }

    /// 把兜底坐标喂给走散检测（`LiveEscortSessionCoordinator` 只读
    /// `AppRealtimeCoordinator` 的对方样本存量，没有自己的 REST 兜底）。
    ///
    /// 🚩 **与上面那句 `latestVolunteerCoordinate = coordinate` 是两件事，故意分开写：**
    ///
    /// | | 念距离（上面那条） | 走散检测（这一条） |
    /// |---|---|---|
    /// | 问的是 | 屏幕上/播报里那个数字 | 两个人还在不在一起 |
    /// | `updatedAt` 缺失 | **放行**（`volunteerFallbackCoordinate` 的既有口径，失败开放） | **不喂** |
    /// | 新鲜度 | 30 秒（后端 Redis TTL） | 15 秒（`peerFreshness`，由 coordinator 判） |
    ///
    /// 缺 `updatedAt` 时不喂，是因为这一条唯一能凑的替代值是「现在」——
    /// 那会让一个 29 秒前的坐标伪装成刚采的，把「已经走散了」演成「一切正常」。
    /// 念距离那条允许缺失是相反方向的选择：那里拦一次的后果只是数字不出现，
    /// 而这条链路已经因为两道失败闭合的闸各坏过一次（见 `volunteerFallbackCoordinate`）。
    private func feedEscortPeerLocation(
        from data: VolunteerLocationData?,
        coordinate: CLLocationCoordinate2D,
        order: OrderDetailResponse,
        appState: AppState
    ) {
        guard let capturedAtMilliseconds = data?.updatedAt else { return }
        appState.realtimeCoordinator.ingestFallbackPeerLocation(
            RealtimePeerLocationSample(
                orderId: order.orderId,
                ownerRole: .volunteer,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestampMilliseconds: capturedAtMilliseconds
            )
        )
    }

    /// 志愿者位置 REST 兜底的新鲜度阈值。与后端 Redis `vol:loc:{id}` 的 TTL
    /// （`app.volunteer.location-ttl-seconds`）取同一个数：key 还在 ⇒ 志愿者这么久内上报过。
    static let volunteerFallbackFreshness: TimeInterval = 30

    /// REST 兜底拿到的坐标能不能采信。抽成静态方法只为**可测** —— 唯一调用点埋在 async 网络分支里。
    ///
    /// **这个方法只做一件事：判坐标能不能用。它的每一道闸都必须失败开放**，因为它拦掉一次
    /// 的后果不是「显示旧值」而是「『志愿者距出发地点约 X』整个不出现，且没有任何日志」——
    /// 这条链路已经因为两道失败闭合的闸各坏过一次：
    ///
    /// - `updatedAt` 曾是 `String?` + `ISO8601DateFormatter`，而后端当时**压根不发这个字段**
    ///   ⇒ `flatMap` 恒 nil ⇒ 恒 return。对真实后端 100% 静默失效，而 Mock 自己造了一个
    ///   `updatedAt`，于是开发期永远看不到。
    /// - `status` 曾因后端键名是 `orderStatus` 而恒为 nil，那条比较从未真正执行过。
    ///
    /// 两个字段都在 2026-08-20（后端 `119c810`）对齐了，所以两道闸会**第一次真的开始工作** ——
    /// 这正是最危险的时刻：把它们原样留着，等于在这一刻新增两条能否掉坐标的分支，
    /// 而失败表现与它们各自修的那个 bug 一模一样。因此：
    ///
    /// 1. **`status` 不再参与判定。** 契约原话：「拿它做交叉校验时应『不一致以本条为准并刷新订单』，
    ///    **不要用它否掉坐标** —— 坐标是这个端点存在的唯一理由」（`api_spec.yaml:2355-2357`）。
    ///    不一致时也不额外发一次刷新请求：本方法由 `loadOrder` 调用，递归回去会死循环；
    ///    而订单本来就 5 秒轮询一次（`AppConstants.Timing.orderPollingInterval`），
    ///    最多晚一轮就拿到权威状态。多一条立即刷新路径的风险大于那 5 秒。
    /// 2. **`updatedAt` 缺失一律放行**，只在它真的有值时判新鲜度。后端 2026-08-20 才补上这个字段，
    ///    生产未必已部署 —— 失败闭合就会原地重演上面第一条。
    /// 3. 时间戳落在**未来**（设备时钟偏差）按「刚采样」处理，不因此丢坐标。与 WebSocket 那条
    ///    `handleVolunteerLocationUpdate` 的 `max(0, ...)` 口径一致。
    static func volunteerFallbackCoordinate(
        from data: VolunteerLocationData?,
        matching order: OrderDetailResponse,
        now: Date = Date()
    ) -> CLLocationCoordinate2D? {
        guard let data,
              data.coordinateIsValid,
              data.orderId == nil || data.orderId == order.orderId,
              let lat = data.lat,
              let lng = data.lng else { return nil }
        if let updatedAt = data.updatedAt {
            let capturedAt = Date(timeIntervalSince1970: TimeInterval(updatedAt) / 1_000)
            let age = max(0, now.timeIntervalSince(capturedAt))
            guard age <= volunteerFallbackFreshness else { return nil }
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: - Mock 环境的对家代打

#if DEBUG
    /// Mock 状态测试面板上那几个按钮代表的一步。志愿者那半边在单设备上凑不齐，
    /// 由这一组按钮代打。
    enum MockCounterpartStep {
        case respond(OrderRespondAction)
        /// 跨天预约单的临期确认。志愿者那半边在单设备上凑不齐，由这个按钮代打 ——
        /// 不做的话 `SCHEDULED_CONFIRMED` 之后的整条链路在 Mock 里根本走不下去。
        case confirmDeparture
        case enRoute
        case arrived
        case startService
        case finish
    }

    /// 代对方角色推进一次状态机（`.mock` 环境专用，调用点自己判环境）。
    ///
    /// 🚨 **失败必须说出来。** 这段原来是 6 个 `try?`，散在 view body 里：
    /// 从 `PENDING_ACCEPT` 直接打 `/arrived` 会被 Mock 按真实状态机拒掉，
    /// 而 `try?` 把拒绝吞成静默，现象是「点了没反应」，后续依赖 `DRIVER_ARRIVED`
    /// 的「模拟服务开始」永不出现 —— 排查时看不出是被拒了还是按钮没接上。
    func runMockCounterpartSteps(_ steps: [MockCounterpartStep], orderId: Int64) async {
        guard let appState else { return }
        let orders = appState.orders
        do {
            for step in steps {
                switch step {
                case .respond(let action):
                    try await orders.respond(orderId: orderId, action: action)
                case .confirmDeparture:
                    try await orders.confirmDeparture(orderId: orderId)
                case .enRoute:
                    try await orders.enRoute(orderId: orderId)
                case .arrived:
                    try await orders.arrived(orderId: orderId)
                case .startService:
                    try await orders.startService(orderId: orderId)
                case .finish:
                    try await orders.finish(orderId: orderId)
                }
            }
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = "Mock 状态测试失败：\(error.localizedMessage)"
        } catch {
            errorMessage = "Mock 状态测试失败。"
        }
        startPolling(orderId: orderId)
    }
#endif

    // MARK: - App-lifetime realtime routing

    private func subscribeToRealtimeCoordinator(appState: AppState) {
        cancellables.removeAll()
        let coordinator = appState.realtimeCoordinator
        coordinator.$pendingOrderRefreshIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] orderIDs in
                guard let self, let orderID = self.activeOrderId, orderIDs.contains(orderID) else { return }
                Task { await self.loadOrder(orderId: orderID, speakChanges: true) }
            }
            .store(in: &cancellables)

        coordinator.statusUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      let current = self.order,
                      current.orderId == update.orderId else { return }
                self.apply(
                    current.replacingStatus(with: update.toStatus),
                    speakChanges: true
                )
                self.isLoading = false
                self.errorMessage = nil
            }
            .store(in: &cancellables)

        coordinator.peerLocationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in self?.handleVolunteerLocationUpdate(sample) }
            .store(in: &cancellables)

        if let orderID = activeOrderId,
           let sample = coordinator.latestPeerLocation(orderID: orderID, ownerRole: .volunteer) {
            handleVolunteerLocationUpdate(sample)
        }
    }
}

// MARK: - Blind Order Status View

struct BlindOrderStatusView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var speechInputService: SpeechInputService
    /// 求助中心的「播报我的位置」要逆地理。取 `@EnvironmentObject` 而不是就地 new 一个：
    /// view model 那一侧是 `weak` 持有，临时对象传进去等于传 nil（守卫 `weak-temporary`）。
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BlindOrderStatusViewModel()
    @StateObject private var trackViewModel = CompletedTrackSummaryViewModel()
    @StateObject private var shareViewModel = RunPlanLiveShareViewModel()
    @State private var showEmergencyConfirmation = false
    @State private var showEmergencyCancelConfirmation = false
    /// 云端求助失败后的一跳拨号兜底（`EmergencyCallContext.cloudFailed`）。
    /// 常规的「陪跑中主动拨号」现在走求助中心那一层，不再单独开这个弹窗。
    @State private var showEmergencyCallOptions = false
    /// 陪跑中那块红色安全锚点打开的求助中心。
    @State private var showSafetyHub = false
    /// 「匹配规则说明」。骨架态从取消确认弹窗里进（设计稿 §3.5），
    /// 只读退路那条列表仍走自己的 `NavigationLink`。
    @State private var showDispatchAlgorithmNotice = false
    /// 屏 3 / 屏 3b 的全屏呈现。**由显式动作打开，不由 coordinator 状态推导** ——
    /// 推导的话首页 SOS 条触发的求助也会在订单页上弹出这一屏，而那条路径有它自己的界面。
    @State private var showEmergencyCountdown = false
    @State private var showCancelConfirmation = false
    @State private var showStatusLogs = false
    @State private var showRunPlanShare = false
    @State private var showLiveShareConsent = false
    @State private var showLiveShareConfirmation = false
    /// 通话页什么时候弹出来。整个通话流程在 `BlindIntroCallView` 里，这一页只管呈现时机 ——
    /// 转移规则（关过一次不再弹、离开通话态复位）在 `BlindIntroCallPresentation` 上，
    /// 连同它们各自防的那个缺陷一起。
    @State private var introCallPresentation = BlindIntroCallPresentation()
    /// 状态推进后把 VoiceOver 焦点接到状态卡上。
    ///
    /// 这一页每 5 秒轮询一次，重绘时焦点会被系统收走，落点不确定 —— 而状态卡恰恰是
    /// 盲人此刻在等的那一条。已经有 `speakStatusChange` 在播报了，焦点不跟过来的话
    /// 两条通道就分家：听到「志愿者已到达」，抬手一滑却还在旧位置。
    ///
    /// 只在 `status` **真的变了**时移（含首次加载的 nil → 有值），不是每次轮询都移 ——
    /// 后者会把正在读订单信息的用户反复弹回顶部。
    @AccessibilityFocusState private var statusHeaderFocused: Bool
    let orderId: Int64
    let onOrderUpdated: (OrderDetailResponse) -> Void

    /// 主按钮高度。比首页的 280 小：这一页顶上还有状态卡要占位置，
    /// 而状态本身也是盲人此刻需要的信息，不能被按钮挤出首屏。
    ///
    /// 2026-09-05 起**只剩「打电话给志愿者」用它**。「继续等待」原先共用这个高度，
    /// 已降级为 64pt 的次级按钮 —— 见 `keepWaitingSection`。
    @ScaledMetric(relativeTo: .largeTitle) private var primaryActionButtonHeight: CGFloat = 140

    /// 这一刻渲染的是设计稿的骨架吗。
    ///
    /// 派生自 `flowPresentation` 而不是另写一套状态判断 —— 两处各判一次的下场是
    /// 骨架渲染出来了而底栏还挂着旧的两个按钮（或者反过来），而那种错位在真机上
    /// 表现为「底部四个按钮」，不会有任何东西报错。
    private var usesFlowSkeleton: Bool {
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
    private var flowPresentation: BlindOrderFlowPresentation? {
        guard let order = viewModel.order else { return nil }
        return BlindOrderFlowPresentation.make(
            order: order,
            distanceText: viewModel.volunteerDistanceToStartText,
            canKeepWaiting: viewModel.canShowKeepWaiting,
            locationWarning: flowLocationWarning,
            countdown: viewModel.runCountdown
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

    @ViewBuilder
    private var content: some View {
        if let presentation = flowPresentation, let order = viewModel.order {
            // 设计稿的骨架。**六幕共用同一套布局**，只换内容 —— 改版前每态一个
            // 独立页面，而 iOS 切页时 VoiceOver 会把焦点移回第一个元素，读屏用户每次
            // 都要从头找。单页原地更新让焦点保持不动，只播报变化。
            //
            // 🔴 `IN_PROGRESS` 2026-09-16 起也走这里（原先是一整屏独立的深底执行屏）。
            // 那一屏被移出的东西**一件都没删**，只是换了落点：三个数字进
            // `BlindActiveRunView`（现在是这张卡的内容区）、定位新鲜度进顶行、
            // 求助失败与撤销进 `flowFooter`、「重复当前状态」由主按钮「播报当前数据」承担。
            // 🔴 **`debugMockControls` 必须在骨架的 ScrollView 里面（走 footer），
            // 不能当 `BlindOrderFlowView` 的兄弟节点。**
            //
            // 它原先挂在外层 `VStack` 上，于是在**横屏**（可用高度约 390pt）里：
            // 那三个 mock 按钮按自然高度占掉一大片、底部两个版位再占一片，
            // 留给状态卡与信息列表的空间被压到几乎为零 —— 真机横屏截图上状态标题、
            // 副标题、四行信息**一个字都看不到**，而「求助与安全」被拉成一个巨块。
            // 这是 2026-09-16 第一次真机跑 `testBlindOrderStatusInLandscapePassesAccessibilityAudit`
            // 时暴露的：那两条 `Contrast failed` 的元素是**没有任何文字的近白色区域**，
            // 也就是被压扁的卡片本身，不是配色问题。
            //
            // 改版前它就在 `trackingContent` 的 ScrollView 里（跟着内容滚），
            // 阶段 3a 把它提到外面是无意的 —— 放回去即恢复。
            // `#if DEBUG` + `currentEnvironment == .mock` 两道闸没动，Release 里仍是 `EmptyView`。
            BlindOrderFlowView(
                presentation: presentation,
                order: order,
                stats: viewModel.trackStats,
                isLocationFresh: viewModel.isDeviceLocationFresh,
                onOpenStartPlace: nil,
                onLastRowTapped: { handleFlowLastRow(order) },
                onPrimaryAction: { handleFlowPrimaryAction(presentation, order: order) },
                onOpenSafetyHub: { showSafetyHub = true },
                footer: {
                    VStack(spacing: 16) {
                        flowFooter(order)
                        // 🔴 已完成那一幕**把改版前那一页的三块原样接回来**（项目负责人
                        // 2026-09-17 决策）：轨迹总结 + 大图回放 + 评价表单 + 收藏固定搭档
                        // （`lifecycleSection` → `completionRatingSection`）、本单信息、状态流水。
                        //
                        // 设计稿 ④ 的第一屏之下是空白，而那三块是**已经上线的功能**：
                        // 评价还有后端在催、收藏这条路是全 App 唯一不依赖火花开关的收藏入口
                        // （另一个在设置页，只能收藏已点亮火花的一对，而那个开关后端默认关着）。
                        // 照稿删掉等于让两个功能都没有入口 —— ⑤ 首页评价卡还卡在
                        // 「后端 rating 是 1–5 必填、没有三档枚举」上（待拍板项 D 的决定是推迟）。
                        if order.status == .completed {
                            lifecycleSection(order)
                            orderInfoSection(order)
                            statusLogSection
                        }
                        debugMockControls(order)
                    }
                }
            )
        } else {
            // 只读退路：`.unknown` 与终态（完成 / 取消 / 无人接单）。
            // 这一条**不许删** —— 后端加状态时它是未知态唯一的落点。
            trackingContent
        }
    }

    /// 骨架信息列表之后那块「刚才那一下的结果」。**三态正常时整块为空。**
    ///
    /// 这不是补充装饰，是把改版前那条滚动列表末尾的**可见失败面**接回来：骨架换掉
    /// `trackingContent` 的同时也换掉了 `viewModel.errorMessage` 与实时分享结果提示
    /// 唯一的渲染点。少了它，失败只剩一句 TTS，而不开读屏的低视力用户屏幕上零变化。
    ///
    /// 短信降级按钮同样在这里：`showSMSFallback` 只在实时分享失败后为真，
    /// 而那一刻「把行程告诉家人」这件事仍然做得到 —— 收走入口等于把人支上死路。
    @ViewBuilder
    private func flowFooter(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 10) {
            // 求助的结果面。**不额外判相位** —— 云端求助只在 `IN_PROGRESS` 可发
            // （`canBlindRunnerTriggerEmergency`），所以这三块在别的幕里本来就恒为空；
            // 多一道相位闸只会多一个能判错的地方，而判错的方向是「求助失败了却没有兜底按钮」。
            BlindRunSafetyResultSection(
                coordinator: appState.emergencyCoordinator,
                onLocalCall: { showEmergencyCallOptions = true },
                onCancelOwnEmergency: { showEmergencyCancelConfirmation = true }
            )

            if let notice = shareViewModel.notice {
                Text(notice.text)
                    .font(AppFonts.body())
                    .foregroundColor(notice.isProblem ? AppColors.destructive : AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(notice.text)
                    .accessibilityIdentifier("blindOrderStatusShareRunPlanNotice")
            }

            // 只在实时分享走不通时露出来。`canSendText` 一并判掉：这台设备本来就发不了
            // 短信时摆出降级入口，等于把用户支上一条同样走不通的路。
            if shareViewModel.showSMSFallback, MessageComposeSheet.canSendText {
                runPlanShareButton(
                    title: RunPlanLiveShareCopy.smsFallbackButtonTitle,
                    hint: RunPlanLiveShareCopy.smsFallbackHint,
                    identifier: "blindOrderStatusShareRunPlanButton",
                    tint: AppColors.primary,
                    action: { shareRunPlanBySMS(order) }
                )
            }

            // 字号用 `AppFonts.body()`，**不用骨架的 13pt `rowDetail`** ——
            // 这是这一页唯一的可见失败面，而它替代的那处（`trackingContent` 末尾）
            // 就是 body。为了跟骨架的视觉调性一致而把它调小一档，等于专门在
            // 「不开读屏的低视力用户唯一能读到失败原因的地方」减字号。
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(errorMessage)
                    .accessibilityIdentifier("blindOrderFlowErrorMessage")
            }
        }
    }

    /// 信息列表最后一行。能取消的态弹取消确认，不能取消的态开求助中心。
    ///
    /// 「遇到问题」落到求助中心而不是新开一页：联系陪跑员 / 播报位置 / 问一句 /
    /// 拨紧急联系人与 120、110 全都已经在那一层里，是这一刻用户可能要做的事的完整集合。
    private func handleFlowLastRow(_ order: OrderDetailResponse) {
        if order.status.canBlindRunnerCancel {
            showCancelConfirmation = true
        } else {
            showSafetyHub = true
        }
    }

    /// 本地拨号弹窗的第一句该说哪一种。判据与 `BlindRunnerTabView.callContext` 逐字相同：
    /// 云端那条路此刻通不通，就决定了「刚才那一下到底发生了什么」是哪个答案。
    private var emergencyCallContext: EmergencyCallContext {
        BlindHomeSOSMode.resolve(order: viewModel.order, role: appState.activeRole) == .cloudTrigger
            ? .cloudFailed
            : .homeIdle
    }

    /// 求助中心那一格按下去：起分享还是停分享。
    ///
    /// **分流放在这里而不是弹层里**：起分享要先过明示同意那道门
    /// （`RunPlanShareConsentStep.next`，判定见 `requestLiveShare`），
    /// 而「同意过没有」是按用户存的本地状态，弹层拿不到也不该拿到。
    private func toggleLiveShare() {
        if shareViewModel.isLiveSharing {
            Task { await shareViewModel.stopLiveShare() }
        } else {
            requestLiveShare()
        }
    }

    private func handleFlowPrimaryAction(
        _ presentation: BlindOrderFlowPresentation,
        order: OrderDetailResponse
    ) {
        switch presentation.primaryAction {
        case .callVolunteer:
            // 拨号一律经 `EmergencyDialer`：它拦掩码串、并只取数字位；掩码串若不拦会拼成 `tel://1381234`，
            // 而空号在界面上看不出任何异常（守卫 `raw-open-url` 拦绕开它的写法）。
            guard let url = EmergencyDialer.telURL(for: order.volunteerPhone?.nilIfBlank) else { return }
            EmergencyDialer.dial(url)
        case .openIntroCall:
            introCallPresentation.isShowing = true
        case .keepWaiting:
            Task { await viewModel.keepWaiting() }
        case .announceStats:
            // 与导航栏那枚「重复当前状态」是**同一个函数**：`repeatStatus` 播的就是
            // 状态 + 里程 / 时长 / 配速（用播报口径，不是屏幕上那个 `9'06"`）。
            // 两处各写一份的下场是跑步中那屏播的和别处不一样，而没有人会发现。
            viewModel.repeatStatus()
        case .done:
            // 「完成」只是离开这一页（订单早已是 `COMPLETED`，结束权在陪跑员手上）。
            //
            // 🚩 **刻意不调 `viewModel.skipReview()`** —— 那个函数的语义是「我不评了」，
            // 而评价表单还在这一页的滚动区里。把「离开」当成「放弃评价」会让用户
            // 下次从历史点进来时看到一张已经被自己关掉的表。
            dismiss()
        case .preparing:
            // 倒计时那三秒按钮是 `.disabled()` 的，走不到这里。留一个显式分支而不是
            // 并进 `nil`：`PrimaryAction` 加档时编译器会逼一次决策。
            break
        case nil:
            break
        }
    }

    private var trackingContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading && viewModel.order == nil {
                    ProgressView("正在获取订单状态...")
                        .tint(AppColors.primary)
                        .accessibilityLabel("正在获取订单状态")
                }

                if let order = viewModel.order {
                    // 顺序即优先级：状态（一句话 + 一个数字）→ 这一态唯一的主动作 →
                    // 同一态的次级动作 → 附属动作 → 其余全部下沉。此前主动作排在第 4 位，
                    // 读屏要滑过状态卡、地图、生命周期卡才够得着。
                    //
                    // `actionSection` 2026-08-19 从第 8 位提到这里：它装的是**这一态的
                    // 状态机动作**（等待中取消、终态返回首页），与上面的主动作同族；
                    // 而「把行程告诉家人」是附属动作 —— 跑不跑得成与它无关。
                    // 排在附属动作后面的直接后果：延长次数用完的 `REMATCHING`
                    // 主动作版位是空的，于是首屏第一个能按的东西是分享，
                    // 而此刻用户唯一还能做的决定是「要不要取消」。
                    statusHeader(order)
                        .accessibilityFocused($statusHeaderFocused)
                    introCallEntrySection(order)
                    volunteerCallSection(order)
                    keepWaitingSection(order)
                    actionSection(order)
                    runPlanShareSection(order)
                    dispatchAlgorithmNoticeSection(order)
                    peerMapSection(order)
                    lifecycleSection(order)
                    orderInfoSection(order)
                    statusLogSection
                    debugMockControls(order)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            // 这一页在 iPad 上最吃亏：状态卡、生命周期、订单信息全是长文本行，
            // 不限宽时一行横跨 1024pt。见 `BlindLayout.readableContentWidth`。
            .readableContentColumn()
        }
    }

    var body: some View {
        content
        // 骨架自己铺 `AppColors.Flow.page`，这一层只兜住只读退路那条分支。
        .background(AppColors.background)
        .navigationTitle(usesFlowSkeleton ? "陪跑订单" : "订单状态")
        .navigationBarTitleDisplayMode(.inline)
        // 跑步中与已完成隐藏返回箭头（设计稿 ③④ 两屏的导航栏都没有它）。
        //
        // 不藏的后果是具体的：读屏遍历第一站就是「返回」，两次右滑 + 双击就退出了这一屏，
        // 而它是盲人跑动中唯一能听到里程 / 时长 / 配速、也是唯一能按到求助的地方。
        //
        // 🔴 **藏它不会把人关在这一屏里，这一点是核过的**：订单页是在首页 tab 的
        // `NavigationStack` 里 push 的（`BlindRunnerHomeView` 的 `navigationDestination`），
        // 而全仓 `.toolbar(.hidden, for: .tabBar)` 命中 0 ⇒ 标签栏照常在，
        // 切到「记录」或「我的」就离开了。**若将来有人隐藏标签栏，这一行必须同时撤销**，
        // 否则跑步中就没有任何出口（结束权只在陪跑员手上）。
        // 已完成那一幕另有一个显式出口 —— 主按钮就是「完成」（`PrimaryAction.done`）。
        .navigationBarBackButtonHidden(isRunningPhase || isFinishedPhase)
        // 🔴 走四步骨架时**不挂这条底栏** —— 骨架自带设计稿的两个版位
        // （主按钮 + 求助与安全），再挂一条会变成四个按钮，而
        // `docs/05-page-specs.md` 那条「不要往常驻区加第三个版位」的理由是
        // 「三个 64pt 按钮在 6.1" 上吃掉约 26% 屏幕，治了求助够不着换来别的都够不着」。
        .safeAreaInset(edge: .bottom) {
            if !usesFlowSkeleton {
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
            if usesFlowSkeleton && !isRunningPhase {
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
            Text("确认取消本次预约？取消后将结束本次服务。")
        }
        // 不是 `NavigationLink`：`confirmationDialog` 的按钮只能跑闭包，塞不进导航。
        // 用 sheet 而不是 push 还有一个好处 —— 看完说明关掉就回到原地，
        // 而 push 会把用户留在一页深处，返回键在左上角（管状视力用户的盲区）。
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
        // 🔴 `mode` 不能写死 `.cloudTrigger`。这一层 2026-09-16 起也从四步骨架的底部
        // 打开，而那四态（匹配 / 约好 / 出发 / 汇合）一个都不是 `IN_PROGRESS` ——
        // 云端求助在那里根本不可调，照走云端的后果是**屏幕零变化、一个字也不播**
        // （详见 `EmergencySafetyCopy.hubLocalCallNotice`）。
        .blindActiveRunSafetyHubSheet(
            isPresented: $showSafetyHub,
            mode: BlindHomeSOSMode.resolve(order: viewModel.order, role: appState.activeRole),
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
            onTriggerEmergencyImmediately: startEmergencyCountdown
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
            guard let status else { return }
            statusHeaderFocused = true
            introCallPresentation.apply(status: status)
        }
        // 全屏，不是 sheet：这一态盲人只有一件该做的事，而 sheet 会把订单页的内容
        // 留在下缘可见、可被 VoiceOver 滑到 —— 那正是这次要解决的问题。
        // 关闭只走「返回订单」按钮（`fullScreenCover` 本来就不能下滑关掉），
        // 于是「用户主动关过」这个事实能被可靠地记下来，不会与「系统因状态变化收起」混淆。
        .fullScreenCover(isPresented: $introCallPresentation.isShowing) {
            BlindIntroCallView(viewModel: viewModel) {
                introCallPresentation.dismiss()
            }
        }
        .task(id: viewModel.order?.status) {
            guard viewModel.order?.status == .completed else { return }
            await viewModel.loadExistingReview()
            // 挂在这条已有的 COMPLETED 分支上而不是另起一个 `.task`：这一页每 5 秒轮询一次，
            // 独立的 task 很容易变成「每轮都查一次收藏列表」。这里一单只查一次。
            await viewModel.loadFavoriteStateIfNeeded()
            await trackViewModel.load(orderID: orderId, appState: appState)
            // 这一次是不限时的（它只喂屏幕，不挡播报）。终值那次限时到点时，
            // ④ 那张卡的三个数字由它兜底 —— 否则卡片顶着 `--`，而同一页下面的
            // 轨迹总结里明明有数字。
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

    /// 一句话 + 一个数字，合成**一个** VoiceOver 焦点。
    ///
    /// 距离此前埋在下面的「志愿者信息」卡片里当正文读，而它恰恰是这一页唯一会变的数字 ——
    /// 对标 GoodMaps 的 `Start Walking … 96 ft`、WeWALK 的 `116 meters`：状态旁边就该是那个数
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1 规则 4）。
    private func statusHeader(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.system(size: 56))
                .foregroundColor(order.status.statusColor)
                .accessibilityHidden(true)

            Text(order.status.displayName)
                .font(.largeTitle.bold())
                .foregroundColor(AppColors.textPrimary)

            Text(order.status.blindRunnerDescription)
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            // 还在等人时，这一格是「已等待 12 分钟」；有志愿者了换成距离；跑起来了换成
            // 约定结束时间。三者状态集互不相交（`offersWaitedDuration` 的注释里有理由），
            // 所以卡上任何时刻只有一个数字。
            if let waitedText = order.blindRunnerWaitedText() {
                Text(waitedText)
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            if let distanceText = viewModel.volunteerDistanceToStartText {
                Text("志愿者\(distanceText)")
                    .font(.title.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // 服务进行中，把约定的结束时间摆在首屏。低视力用户靠这行字看到，
            // 读屏用户靠 `statusHeaderAnnouncement` 听到 —— 两条通道都要有。
            if let plannedEndText = plannedEndHeaderText(order) {
                Text(plannedEndText)
                    .font(.title2.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusHeaderAnnouncement(order))
    }

    /// 结束时间只在服务进行中出现在首屏。派单期、汇合期摆它没有用（还没开始跑），
    /// 终态更不该摆（已经结束了，一个「预计」是噪音）。
    ///
    /// 拼接抽成独立函数而不是塞进 `Text(...)`：带可选拆包的字符串插值放在 view builder 里
    /// 会把类型检查器拖到超时（`unable to type-check this expression in reasonable time`）。
    private func plannedEndHeaderText(_ order: OrderDetailResponse) -> String? {
        guard order.status == .inProgress, let end = order.plannedEndForAnnouncement else { return nil }
        return "预计 \(end) 结束"
    }

    /// 合并后的朗读文本写死，不交给 `.combine` 自己拼 —— 自动拼接会把状态名、说明和距离
    /// 糊成一长串没有停顿的音。
    private func statusHeaderAnnouncement(_ order: OrderDetailResponse) -> String {
        var parts = [order.status.displayName, order.status.blindRunnerDescription]
        if let waitedText = order.blindRunnerWaitedText() {
            parts.append(waitedText)
        }
        if let distanceText = viewModel.volunteerDistanceToStartText {
            parts.append("志愿者\(distanceText)")
        }
        if let plannedEndText = plannedEndHeaderText(order) {
            parts.append(plannedEndText)
        }
        return parts.joined(separator: "。")
    }

    @ViewBuilder
    private func lifecycleSection(_ order: OrderDetailResponse) -> some View {
        switch order.status.blindRunnerRoute {
        case .tracking, .inService, .terminal:
            // 这三条分支此前各渲染一张「标题 + 正文」卡片，正文都与 `statusHeader` 重复：
            //   · `DRIVER_ARRIVED` 的 `arrivedWaitingCopy` **就是**它的 `blindRunnerDescription`
            //     （`OrderDisplayHelpers.swift:77` 直接 return 了它）—— 逐字重复
            //   · `IN_PROGRESS` 那句「请与志愿者保持沟通，注意安全。系统会持续同步订单状态，
            //     服务完成后进入评价页面。」33 个字里没有一个能让盲人做出动作：
            //     「持续同步订单状态」是实现细节，「完成后进入评价页面」是还没发生的事
            //   · `.terminal` 的 `terminalSection`（2026-08-19 并进来）整张卡就是
            //     `Text(status.displayName)` + `Text(status.blindRunnerDescription)`，
            //     与 `statusHeader` **逐字**是同两句 —— 已取消 / 暂无志愿者的人把
            //     「本次预约已取消」听两遍，中间还隔着一次滑动
            // 读屏用户为此要多滑一次、把同一件事听两遍。状态语义由 `statusHeader` 一处承担。
            EmptyView()
        case .completion:
            completionRatingSection(order)
        }
    }

    private func completionRatingSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务已完成")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if let track = trackViewModel.track {
                // 🚩 这枚「重复当前状态」与导航栏那枚走**同一个函数**（`repeatStatus`）——
                // 同一页上两个入口念出不同的话，对看不见屏幕的人是两个矛盾的事实。
                // 原先它念 `track.spokenSummary`（只有三个数字，没有状态），
                // 而 `repeatStatus` 念的是「状态 + 三个数字 + 求助状态」，是它的严格超集。
                CompletedTrackSummaryView(track: track, recordOrderId: order.orderId, role: .runner) {
                    viewModel.repeatStatus()
                }
            } else if trackViewModel.isLoading {
                ProgressView("正在加载本次路线")
            } else if let error = trackViewModel.errorMessage {
                Text(error).foregroundColor(AppColors.textSecondary)
            }

            if viewModel.didSubmitReview {
                if let review = viewModel.existingReview {
                    submittedReviewSummary(review)
                }
                Text("感谢反馈，可以返回首页。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("感谢反馈，可以返回首页")
            } else {
                Picker("评分", selection: $viewModel.reviewRating) {
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value) 星").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("服务评分")
                .accessibilityHint("选择一到五星评分")

                TextEditor(text: $viewModel.reviewComment)
                    .frame(minHeight: 96)
                    .padding(8)
                    .background(AppColors.background)
                    .cornerRadius(8)
                    .accessibilityLabel("评价内容，选填")

                PrimaryButton("提交评价", isLoading: viewModel.isSubmittingReview) {
                    Task { await viewModel.submitReview() }
                }
                .accessibilityLabel("提交评价")
                .accessibilityHint("提交本次服务评分和评价")

                Button("跳过评价并返回首页") {
                    viewModel.skipReview()
                    dismiss()
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .buttonShapeOutlineIfNeeded(color: AppColors.textSecondary)
                .accessibilityLabel("跳过评价并返回首页")
            }

            favoriteVolunteerSection(order)

            if viewModel.didSubmitReview {
                PrimaryButton("返回首页") {
                    dismiss()
                }
                .accessibilityLabel("返回首页")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    /// 「把这一单的志愿者设为固定搭档」。
    ///
    /// 🚩 **这是全 App 第二个、也是覆盖面最大的收藏入口。** 另一个在设置页的固定搭档列表里，
    /// 但那里只能收藏**已经点亮火花**的一对 —— 而火花开关（`app.incentive.streak.enabled`）
    /// 后端默认关着，所以在它打开之前，那个入口实际上一个人也收藏不了。
    /// 这条路不依赖火花：收藏的门槛是「一起跑完至少一单」，而这一页就站在那一单上。
    ///
    /// 位置在评价之后：评价是这一屏的主动作（有时限压力、后端会催），收藏没有。
    ///
    /// 三个渲染条件缺一不可：
    /// - `COMPLETED` —— 门槛是跑完，跑之前点必然吃 `FAVORITE_VOLUNTEER_NOT_ELIGIBLE`
    /// - `volunteerId != nil` —— 结构判据，不另外判状态（后端接单前本就不下发它）
    /// - `isVolunteerFavorited != nil` —— 查不到收藏状态时整块不出现，理由见那个属性
    @ViewBuilder
    private func favoriteVolunteerSection(_ order: OrderDetailResponse) -> some View {
        if order.status == .completed,
           order.volunteerId != nil,
           let isFavorited = viewModel.isVolunteerFavorited {
            let name = order.volunteerName?.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
            VStack(alignment: .leading, spacing: 8) {
                if isFavorited {
                    // 已经是搭档时只陈述事实，不给「取消收藏」——
                    // 取消的是一段跨越很多次跑步的关系，而这一页只有其中一次的上下文。
                    // 取消入口在设置页的固定搭档列表，那里看得到全部搭档。
                    Text("\(name)已经是你的固定搭档")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blindOrderAlreadyFavoriteText")
                } else {
                    Button(PartnerStreakCopy.addFavoriteTitle(name)) {
                        Task { await viewModel.addVolunteerToFavorites() }
                    }
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                    .disabled(viewModel.isUpdatingFavorite)
                    // 🔴 承诺只能说到「更可能」。收藏加的 15 分在满分 100 的五维加权和之外，
                    // 附近有个不错的陌生人时固定搭档仍然会输 —— 说「优先派给他」是承诺一件系统做不到的事。
                    .accessibilityHint(PartnerStreakCopy.favoriteExplanation)
                    .accessibilityIdentifier("blindOrderAddFavoriteButton")
                }

                // 成功与失败都要**在屏幕上多出一行字**，不能只靠播报：
                // 低视力用户走的是视觉那条通道（AGENTS.md §1.4）。
                if let notice = viewModel.favoriteNotice {
                    Text(notice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blindOrderFavoriteNotice")
                }
                if let failure = viewModel.favoriteErrorMessage {
                    Text(failure)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blindOrderFavoriteError")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 已提交过的评价读回来。
    ///
    /// 这一块的存在理由是**重进这一单**：`didSubmitReview` 只活在这个进程里，
    /// 重开 App 再进已完成的订单，用户看到的是一张空白评价表 —— 填完提交只会撞上
    /// 409「已评价过此订单」。把真实评价念出来，用户才知道这一单已经评过、评的是什么。
    /// 合成一个焦点：星数和评语分两次读会让读屏用户以为是两条不同的记录。
    private func submittedReviewSummary(_ review: OrderReview) -> some View {
        let comment = review.comment?.nilIfBlank
        let reviewedAt = review.createdAt?.nilIfBlank?.displayDateTime
        // 视觉与读屏两条通道给同一份内容，不给读屏偷偷多塞一句 —— 低视力用户走的是视觉那条
        // （AGENTS.md §1.4）。
        return VStack(alignment: .leading, spacing: 4) {
            Text("你给本次服务打了 \(review.rating) 星")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
            if let comment {
                Text(comment)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
            }
            if let reviewedAt {
                Text("评价于\(reviewedAt)")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "你给本次服务打了 \(review.rating) 星"
                + (comment.map { "，评语：\($0)" } ?? "")
                + (reviewedAt.map { "，评价于\($0)" } ?? "")
        )
    }

    /// 「刚才到底发生了什么」。
    ///
    /// 折叠，理由与「预约信息」同一条：这是用户想回溯时才来找的信息，不是主路径上的动作。
    /// 摊开会让读屏用户在到达「重复当前状态」之前多滑十几次。
    private var statusLogSection: some View {
        DisclosureGroup("状态变更记录", isExpanded: $showStatusLogs) {
            statusLogContent
                .padding(.top, 12)
        }
        .font(.title3.bold())
        .tint(AppColors.textPrimary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityHint("展开后可以听到这一单每一次状态变化和发生时间")
        .accessibilityIdentifier("blindOrderStatusLogsDisclosure")
    }

    @ViewBuilder
    private var statusLogContent: some View {
        if viewModel.isLoadingStatusLogs && viewModel.statusLogs.isEmpty {
            ProgressView("正在获取状态变更记录")
                .tint(AppColors.primary)
                .accessibilityLabel("正在获取状态变更记录")
        } else if let errorMessage = viewModel.statusLogsErrorMessage {
            // 「拿不到」和「没有记录」必须分得开：前者可以重试，后者重试也没用。
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(errorMessage)
        } else if viewModel.statusLogs.isEmpty {
            Text("暂无状态变更记录")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("暂无状态变更记录")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // 后端已按时间倒序给，最新的一条在最上面 —— 读屏第一个听到的就是刚发生的事。
                ForEach(viewModel.statusLogs) { log in
                    infoRow(log.changedAt.displayDateTime, log.displayText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func peerMapSection(_ order: OrderDetailResponse) -> some View {
        if [.driverEnRoute, .driverArrived, .inProgress].contains(order.status) {
            let peer = viewModel.latestVolunteerSample?.coordinate
            if let peer {
                // 与首页同一条规则：地图是装饰，列表才是界面。它不可交互、不承载任何必要信息
                // ——「志愿者距你多远」的文字版在 `statusHeader` 里，是那一页最大的那个数字。
                // 「同行位置」这个标题一并去掉：视觉扫读才需要标题，这一页没有扫读。
                // 隐藏走 `isDecorative`，不是在外层加 `.accessibilityHidden(true)` ——
                // 后者在真 key 构建下盖不住 `MapViewWrapper` 自己合成的那个元素
                // （2026-08-22 在盲人首页实测，见 `MapViewWrapper.isDecorative` 的说明）。
                // 这一页同样是「地图是装饰、列表才是界面」，所以同一个洞在这里也开着。
                MapViewWrapper(
                    centerCoordinate: peer,
                    showsUserLocation: false,
                    annotations: [MapAnnotationItem(
                        id: "associated-volunteer",
                        coordinate: peer,
                        title: "同行志愿者",
                        subtitle: "位置刚刚更新",
                        kind: .peer
                    )],
                    tracksUserLocation: false,
                    isDecorative: true
                )
                .decorativeMapHeight(180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            } else {
                // 但「拿不到位置」必须留在读屏里：盲人据此决定要不要打电话，
                // 这是状态信息不是装饰。
                Text("同行位置暂时不可用")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("同行位置暂时不可用")
            }
        }
    }

    /// 接单后这一页唯一的主动作：打电话给志愿者。
    ///
    /// 此前它是「志愿者信息」卡片里的一行只读文字（`Text("志愿者电话：…")`）。
    /// 打车 App 里视障乘客靠车型 / 车牌 / 颜色确认对方，**陪跑场景这三样都没有** ——
    /// 志愿者是个人，视障者手里唯一的汇合手段就是这通电话。把它做成一行文字，
    /// 等于把唯一的出路藏在第四张卡片里。
    ///
    /// 依据：202 名视障者问卷 + 12 人访谈的结论是导航阶段最优先的信息为「怎么找到正确的那一个」；
    /// Guide Dogs for the Blind 给视障乘客的操作建议直接就是「接驾前几分钟主动打电话说明自己在哪」。
    /// 见 `docs/research/blind-ui-visual-benchmark-20260808.md` §3.2。
    ///
    /// 只在需要汇合的状态出现：终态（已完成 / 已取消 / 暂无志愿者）下电话可能还在，
    /// 但那时候摆一个占半屏的拨号按钮是错的。
    /// ponytail: 复用 `EmergencyDialer.telURL` —— 它只是在拼 `tel://`，与求助语义无关，
    /// 不值得为「非紧急拨号」再造一个同样的三行函数。
    @ViewBuilder
    private func volunteerCallSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersVolunteerCall,
           let volunteerPhone = order.volunteerPhone?.nilIfBlank,
           let telURL = EmergencyDialer.telURL(for: volunteerPhone) {
            Button {
                EmergencyDialer.dial(telURL)
            } label: {
                Text("打电话给志愿者")
                    .font(AppFonts.largeTitle())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryActionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel("打电话给志愿者")
            // 这里此前是「拨打 \(volunteerPhone)，系统会先弹出拨号确认」——
            // VoiceOver 每次焦点落到按钮上就把 11 位号码整个念出来，用户还没决定要不要打。
            // 视障跑者在户外常常**不戴耳机**（要听车流），外放等于把志愿者的手机号广播给周围的人。
            // 号码对「要不要打这通电话」这个决策没有任何帮助，唯一有用的信息是「会先弹确认」。
            //
            // 语音拨号那条路**照旧逐位复述号码**（`VoiceStatusQuery.swift:212`），
            // 那不是冗余暴露：用户已经明确说了要打，复述是拨号前确认拨给谁，删掉会变成盲拨。
            .accessibilityHint("系统会先弹出拨号确认，确认后才会拨出")
            .accessibilityIdentifier("blindOrderStatusCallVolunteerButton")
        }
    }

    /// 进通话页的入口。通话本身整个在 `BlindIntroCallView` 里，这里只有一个按钮。
    ///
    /// 🚩 **它不能因为「反正会自动弹」而省掉。** 自动弹出只发生在 `status` **变化**那一跳，
    /// 而用户按过「返回订单」之后本轮就不再自动弹（`BlindIntroCallPresentation`）——
    /// 没有这个按钮，他此刻回不去了：状态卡还在念「有位志愿者想陪你跑，可以打个电话聊聊」，
    /// 而屏幕上没有任何入口。那与 `introCallUnavailable` 当初修的是同一类缺陷。
    ///
    /// 还有一条更细的路会绕过自动弹出：同一次通话磨合里换候选人要经过 `PENDING_MATCH`
    /// （`AGENTS.md` §5），而这一页 5 秒轮一次 —— 后端立刻派给下一位时，那个中间态
    /// 可能整个落在两次轮询之间。客户端看到的是 `PENDING_INTRO_CALL → PENDING_INTRO_CALL`，
    /// `onChange` 不触发。
    ///
    /// 版位与 `volunteerCallSection` / `keepWaitingSection` 相同、状态集互斥
    /// （`.pendingIntroCall` 不在 `offersVolunteerCall` 也不在 `offersKeepWaiting` 里），
    /// 所以读屏遍历时状态卡之后紧跟的永远是此刻唯一该做的那件事。
    ///
    /// 🚨 文案**不许复用 `callButtonTitle`**（「打电话给这位志愿者」）：那个按钮按下去
    /// 立刻弹系统拨号确认，这个按钮只是打开一个页面。对看不见屏幕的人，两件事听起来
    /// 一样就等于随时可能误拨。
    @ViewBuilder
    private func introCallEntrySection(_ order: OrderDetailResponse) -> some View {
        if order.status == .pendingIntroCall {
            Button {
                introCallPresentation.isShowing = true
            } label: {
                Text(IntroCallCopy.blindEntryButtonTitle)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: primaryActionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel(IntroCallCopy.blindEntryButtonTitle)
            .accessibilityHint(IntroCallCopy.blindEntryAccessibilityHint)
            .accessibilityIdentifier("blindOrderStatusIntroCallEntryButton")
        }
    }

    /// 等待期这一页唯一的主动作。
    ///
    /// 后端的 `ORDER_CANCELLATION_WARNING` 正文逐字写着「点击继续等待可延长」，在这个按钮
    /// 存在之前，盲人听到那句话之后**在屏幕上找不到它**，能做的只有等订单被自动取消再重下一单。
    ///
    /// 排在 `volunteerCallSection` 后面同一个版位：两者状态集互斥，等待中给这个、汇合中给电话，
    /// 读屏遍历时状态卡之后紧跟的永远是此刻唯一该做的那件事。
    ///
    /// 没有二次确认（幂等 + 方向是保住订单）。取消订单那条的确认对话框不受影响。
    ///
    /// 🚩 **2026-09-05 从 140pt 的实心主按钮降级为 64pt 的描边次级按钮，功能一字未动。**
    /// 等待态这一页真正的主体是「系统正在派单」这条状态，而这个按钮此刻并不是用户**该做**
    /// 的事 —— 它是一条**保险**（不按，订单会在后端的窗口到点后被自动取消）。
    /// 用主按钮的体量把它摆在那里，会让盲人以为等待期有一件必须完成的操作。
    ///
    /// 🚨 **降级的是体量，不是可达性。** 三条不许动：
    /// 1. 仍在 `statusHeader` 之后的同一个版位，读屏遍历顺序不变；
    /// 2. 仍是整行铺满、64pt 高（`docs/research/blind-ui-visual-benchmark-20260808.md`
    ///    那条「次级操作一律整行铺满竖直堆叠」，与「换一位」「取消订单」同档）；
    /// 3. `repeatStatus` 里那句 `KeepWaitingCopy.repeatStatusSuffix` 照旧念 ——
    ///    看不见屏幕的人靠它知道这个按钮存在，那才是它真正的发现路径。
    ///
    /// `buttonShapeOutlineIfNeeded` 不能省：这一段降级后是纯文字按钮，开启「按钮形状」
    /// 的低视力用户否则看不出它可点（与 `actionSection` 的「取消订单」同一条理由）。
    @ViewBuilder
    private func keepWaitingSection(_ order: OrderDetailResponse) -> some View {
        if viewModel.canShowKeepWaiting {
            Button {
                Task { await viewModel.keepWaiting() }
            } label: {
                Text(KeepWaitingCopy.buttonTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
            }
            .disabled(viewModel.isPerformingAction)
            .buttonShapeOutlineIfNeeded(color: AppColors.primary)
            .accessibilityLabel(KeepWaitingCopy.buttonTitle)
            .accessibilityHint(KeepWaitingCopy.accessibilityHint)
            .accessibilityIdentifier("blindOrderStatusKeepWaitingButton")
        }
    }

    /// 把这次行程告诉家人。主路径是**实时分享**（后端生成免登录链接，家属能看到位置与轨迹），
    /// 短信是它失败时的降级路径。
    ///
    /// 排在主动作与 `actionSection` 之后、地图之前：它是**附属**动作（不该抢 140pt 的主按钮
    /// 版位，也不该排在「取消订单」这种状态机动作前面），但也不能沉到订单信息下面 ——
    /// 看不见屏幕的人靠遍历顺序发现功能存在，沉下去等于没做。样式用整行铺满的次级按钮，与
    /// `docs/research/blind-ui-visual-benchmark-20260808.md` 那条「次级操作一律整行铺满
    /// 竖直堆叠」一致。
    ///
    /// 终态整段消失（`offersRunPlanShare`），不是禁用：后端对终态返 409，
    /// 摆一个按下去必然报错的按钮，对读屏用户是纯噪音。
    @ViewBuilder
    private func runPlanShareSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersRunPlanShare {
            VStack(spacing: 10) {
                if shareViewModel.isLiveSharing {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.stopButtonTitle,
                        hint: RunPlanLiveShareCopy.stopAccessibilityHint,
                        identifier: "blindOrderStatusStopLiveShareButton",
                        tint: AppColors.destructive,
                        action: { Task { await shareViewModel.stopLiveShare() } }
                    )
                } else {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.buttonTitle,
                        hint: RunPlanLiveShareCopy.accessibilityHint,
                        identifier: "blindOrderStatusLiveShareButton",
                        tint: AppColors.primary,
                        action: { requestLiveShare() }
                    )
                }

                // 只在实时分享走不通时露出来。`canSendText` 一并判掉：这台设备本来就发不了短信时
                // 摆出降级入口，等于把用户支上一条同样走不通的路。
                if shareViewModel.showSMSFallback, MessageComposeSheet.canSendText {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.smsFallbackButtonTitle,
                        hint: RunPlanLiveShareCopy.smsFallbackHint,
                        identifier: "blindOrderStatusShareRunPlanButton",
                        tint: AppColors.primary,
                        action: { shareRunPlanBySMS(order) }
                    )
                }

                if let notice = shareViewModel.notice {
                    Text(notice.text)
                        .font(AppFonts.body())
                        .foregroundColor(notice.isProblem ? AppColors.destructive : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(notice.text)
                        .accessibilityIdentifier("blindOrderStatusShareRunPlanNotice")
                }
            }
        }
    }

    private func runPlanShareButton(
        title: String,
        hint: String,
        identifier: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFonts.title())
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .cornerRadius(16)
        }
        .disabled(shareViewModel.isWorking)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Live share

    private var consentStore: RunPlanShareConsentStore {
        RunPlanShareConsentStore(persistence: appState.persistence)
    }

    /// 同意按**用户**存。未登录拿不到 userId 时用一个恒不命中的 key，效果是每次都走全屏告知 ——
    /// 这条路正常走不到（这一页在登录后才可达），宁可多告知一次也不要让一个空 key
    /// 被所有账号共用。
    private var consentUserKey: String {
        appState.currentUser.map { String($0.userId) } ?? "anonymous"
    }

    /// 按下分享：先过明示同意这道门。**不许直接发请求** ——
    /// 调 `POST /api/orders/{id}/share` 本身就等同于盲人对「向持链接者提供实时位置与轨迹」
    /// 作出单独同意（PIPL 第 23/29 条，轨迹属第 28 条敏感个人信息）。后端挡不住这一层，
    /// 只有客户端能，判定在 `RunPlanShareConsentStep.next`。
    private func requestLiveShare() {
        shareViewModel.clearNotice(hidingSMSFallback: true)
        switch RunPlanShareConsentStep.next(hasGivenConsent: consentStore.hasGivenConsent(userKey: consentUserKey)) {
        case .fullDisclosure:
            showLiveShareConsent = true
        case .shortConfirmation:
            showLiveShareConfirmation = true
        }
    }

    // MARK: - SMS fallback

    /// 把行程要素交给系统短信，发给紧急联系人。**不发任何网络请求** ——
    /// 行程来自本页已持有的 `OrderDetailResponse`，收件人来自 `AppState.emergencyContacts`。
    ///
    /// 三道门，顺序不能换：**先问设备能不能发**，再问有没有收件人。
    /// 反过来的话，一台不能发短信的设备会先把用户支去添加紧急联系人，
    /// 加完回来发现还是发不出去 —— 那是一趟白跑的路，而这条路对盲人格外贵。
    private func shareRunPlanBySMS(_ order: OrderDetailResponse) {
        guard MessageComposeSheet.canSendText else {
            shareViewModel.note(RunPlanShareCopy.unavailable, isProblem: true)
            return
        }
        guard appState.primaryEmergencyContact?.phone?.nilIfBlank != nil else {
            shareViewModel.note(RunPlanShareCopy.noContact, isProblem: true)
            return
        }
        // 第三道门与前两道一样要出声。`compose` 只在 `status.offersRunPlanShare == false` 时返回 nil，
        // 也就是 5 秒轮询把订单推到终态、而按钮还留在屏幕上的那一瞬 —— 静默 return 的表现是
        // 「点了没反应」，对盲人端就是事故（`AGENTS.md` §1 那条枚举红线的同类）。
        guard RunPlanShareMessage.compose(order: order) != nil else {
            shareViewModel.note(RunPlanShareCopy.notShareable, isProblem: true)
            return
        }
        shareViewModel.clearNotice()
        showRunPlanShare = true
    }

    /// 「匹配规则说明」——《互联网信息服务算法推荐管理规定》第十六条的「显著方式告知」。
    ///
    /// **版位**：附属动作（分享）之后、地图之前。本文件开头写死的顺序原则是
    /// 「状态 → 主动作 → 同态次级动作 → 附属动作 → 其余下沉」，而这一条是**信息性**的：
    /// 它不该抢在「取消订单」前面（那是此刻唯一真正的决定），也不能沉到订单信息下面 ——
    /// 看不见屏幕的人靠遍历顺序发现功能存在，沉下去等于没做，而「显著」正是这条法规要的东西。
    ///
    /// 🚩 **刻意不进 `repeatStatus` 播报。** 「继续等待」进播报是因为它有时限、不按订单会被自动取消；
    /// 算法告知没有时限，为它把最高频的那条路径（每次复述状态）加长不划算。它的发现路径是遍历顺序。
    ///
    /// `buttonShapeOutlineIfNeeded` 不能省：纯文字行，开启「按钮形状」的低视力用户
    /// 否则看不出它可点（与 `keepWaitingSection` / `actionSection` 同一条理由）。
    @ViewBuilder
    private func dispatchAlgorithmNoticeSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersDispatchAlgorithmNotice {
            NavigationLink {
                DispatchAlgorithmNoticeView()
            } label: {
                Text(DispatchAlgorithmNoticeCopy.entryTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
            }
            .buttonShapeOutlineIfNeeded(color: AppColors.primary)
            .accessibilityLabel(DispatchAlgorithmNoticeCopy.entryTitle)
            .accessibilityHint(DispatchAlgorithmNoticeCopy.entryAccessibilityHint)
            .accessibilityIdentifier("blindOrderStatusDispatchAlgorithmNoticeLink")
        }
    }

    /// 折叠。这 8 行在下单时已经被逐条读回确认过一遍，服务进行中它们既不可改也无需再听 ——
    /// 摊开就是读屏用户在主路径上多滑 8 次。`DisclosureGroup` 保留了「想听时能听」，
    /// 而不是把信息删掉。
    private func orderInfoSection(_ order: OrderDetailResponse) -> some View {
        DisclosureGroup("预约信息") {
            orderInfoRows(order)
                .padding(.top, 12)
        }
        .font(.title3.bold())
        .tint(AppColors.textPrimary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityHint("展开后可以听到预约时间、出发地点等已确认的信息")
    }

    private func orderInfoRows(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("预约时间", (order.plannedStart ?? "").displayDateTime)
            // 约定的结束时间。取 `plannedEnd`，**不是** `预约时间 + 预计时长` 推的 ——
            // 理由见 `plannedEndForAnnouncement`。下面那行「预计时长」是用户下单时选的档位，
            // 两者放在一起时更要分清：时长是意愿，结束时间是后端算出来的约定。
            if let plannedEnd = order.plannedEndForAnnouncement {
                infoRow("预计结束时间", plannedEnd)
            }
            if let address = order.startAddress, !address.trimmed.isEmpty {
                infoRow("出发地点", address)
            }
            if let endAddress = order.endAddressForDisplay {
                infoRow("结束地点", endAddress)
            }
            if let routeNotes = order.routeNotes, !routeNotes.trimmed.isEmpty {
                infoRow("路线备注", routeNotes)
            }
            if let duration = order.expectedDurationMinutes {
                infoRow("预计时长", "\(duration) 分钟")
            }
            if let pace = order.pacePreference {
                infoRow("配速偏好", pace.displayName)
            }
            if let route = order.routePreference {
                infoRow("路线偏好", route.displayName)
            }
            if order.hasGuideDogThisRun == true {
                infoRow("导盲犬", "本次携带")
            }
            if let notes = order.specialNotes, !notes.trimmed.isEmpty {
                infoRow("特殊说明", notes)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }

    /// 求助区块**不在这里** —— `IN_PROGRESS` 时它在骨架底部那两个固定版位里
    /// （`BlindOrderFlowView.bottomActions` 的「求助与安全」）。
    ///
    /// 2026-08-19 搬走：这个 section 排在滚动内容第 7 位，`IN_PROGRESS` 时上面压着状态卡、
    /// 140pt 的「打电话给志愿者」、行程分享、180pt 装饰地图 —— 内容顶到求助按钮约 700pt，
    /// 而底部常驻条吃掉约 164pt 后视口只剩约 550pt，**服务进行中的求助按钮在首屏之外，要下滑**。
    /// 而且它的位置还不稳定：拿不到志愿者位置时地图退化成一行文字，求助又回到首屏。
    /// 这直接违反 `docs/research/blind-voice-booking-ia-20260805.md` §4「求助（`IN_PROGRESS` 时）
    /// 必须在首屏两次滑动内可达」。
    ///
    /// 求助搬走之后这里剩下的两个都是**这一态的状态机动作**：等待中的「取消订单」、
    /// 终态的「返回首页」。所以同日把整段从第 8 位提到主动作紧后面 —— 一个页面上
    /// 「此刻能对这一单做的事」应该连在一起，中间不隔着分享和地图。
    /// `IN_PROGRESS` 时这一段是空的（`canBlindRunnerCancel` 为假，`AGENTS.md` §5
    /// 明确禁止服务中展示取消），所以那一态的布局不受这次移动影响。
    private func actionSection(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 14) {
            if viewModel.canShowCancel {
                Button("取消订单") {
                    showCancelConfirmation = true
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                // 这一页只有这一个按钮是**纯文字**（其余都是实心色块），开启「按钮形状」时
                // 它是唯一一个看不出可点的。而它是破坏性操作，认不出来的代价是两个方向的：
                // 想取消的人找不到，不想取消的人以为那只是一行说明。
                .buttonShapeOutlineIfNeeded(color: AppColors.destructive)
                .accessibilityLabel("取消订单")
                .accessibilityHint("需要确认后取消")
            }

            if order.status.isTerminal && order.status != .completed {
                PrimaryButton("返回首页") {
                    dismiss()
                }
                .accessibilityLabel("返回首页")
                .accessibilityHint("点击后返回盲人首页")
            }
        }
    }

    @ViewBuilder
    private func debugMockControls(_ order: OrderDetailResponse) -> some View {
        #if DEBUG
        if appState.currentEnvironment == .mock {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mock 状态测试")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                if order.status == .pendingMatch {
                    Button("模拟志愿者接单") {
                        Task {
                            await viewModel.runMockCounterpartSteps(
                                [.respond(.accept)],
                                orderId: order.orderId
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者接单")

                    // 真实链路里陌生人**不能**直接接单（后端 409 `INTRO_CALL_REQUIRED`），
                    // 走的是这一条。留着上面那个是因为熟人路径与「后端把开关关掉」都还走它。
                    Button("模拟志愿者想先聊聊") {
                        Task {
                            await viewModel.runMockCounterpartSteps(
                                [.respond(.interested)],
                                orderId: order.orderId
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者想先聊聊")
                }

                // 通话磨合期只有盲人这一侧能在 Mock 里操作，志愿者那半边由这个按钮代打 ——
                // 否则「双方都说合适」在单设备上永远凑不齐。
                if order.status == .pendingIntroCall {
                    Button("模拟志愿者说合适") {
                        (appState.apiClient as? MockAPIClient)?.simulateIntroCallDecisionForTesting(
                            orderId: order.orderId,
                            role: .volunteer,
                            decision: .accept
                        )
                        viewModel.startPolling(orderId: order.orderId)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者说合适")
                }

                // 跨天预约单：先让志愿者「确认出发」把它推到 `PENDING_ACCEPT`，
                // 之后就接回既有的那几个按钮。分开一个按钮而不是并进下面那条链，
                // 是因为这一步本身就是要验的东西 —— 合进去就跳过了它。
                if order.status == .scheduledConfirmed {
                    Button("模拟志愿者确认出发") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.confirmDeparture], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者确认出发")
                }

                if order.status == .driverEnRoute || order.status == .pendingAccept {
                    Button("模拟志愿者到达") {
                        Task {
                            // 真实状态机是 PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED，不能跳级，
                            // 所以 `PENDING_ACCEPT` 要先补一步 en-route。被 Mock 拒掉时
                            // `runMockCounterpartSteps` 会把原因写进 `errorMessage`，不再静默。
                            let steps: [BlindOrderStatusViewModel.MockCounterpartStep] =
                                order.status == .pendingAccept ? [.enRoute, .arrived] : [.arrived]
                            await viewModel.runMockCounterpartSteps(steps, orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者到达")
                }

                if order.status == .driverArrived {
                    Button("模拟服务开始") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.startService], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务开始")
                }

                if order.status == .inProgress {
                    Button("模拟服务完成") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.finish], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务完成")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
        }
        #endif
    }

    /// **只读退路**（`.unknown` 与终态）那条常驻底栏：「问一句」+「重复当前状态」。
    ///
    /// 「问一句」排在前面是因为更省时间 —— 整段状态播报要 15~25 秒，而问一句只念被问的那一项。
    ///
    /// 🚩 这里**没有求助分支**，而且不该有。求助只在 `IN_PROGRESS` 开放
    /// （`canBlindRunnerTriggerEmergency` 恒等于 `status == .inProgress`），
    /// 而那一态 2026-09-16 起走骨架、由骨架自带的「求助与安全」版位承担 ——
    /// 这条底栏根本不会被挂上去（`usesFlowSkeleton` 为真时 `safeAreaInset` 里是空的）。
    /// 留着一条永远走不到的安全分支比删掉危险：它会继续被当成「这条路还在」，
    /// 而没有任何东西会说话。
    private var standardRepeatStatusArea: some View {
        VStack(spacing: 12) {
            askQuestionButton
            PrimaryButton("重复当前状态") {
                viewModel.repeatStatus()
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前订单状态")
        }
        // 与内容列同宽。都是具名按钮，收窄不影响读屏用户找得到。
        .readableContentColumn()
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // 这条常驻底栏压在滚动内容之上，**恒用实色**。
        //
        // 原来只在系统「降低透明度」打开时才实色，默认走 `.regularMaterial` ——
        // 于是滑过去的文字会从这几个按钮底下透上来，2026-09-07 真机报的「穿模」就是它。
        // 材质在短底栏上没问题，问题出在这一页：它压着一条很长的滚动列表，
        // 透上来的是**正文**，成了文字叠文字。
        //
        // 判据不是「好不好看」，是这一页服务谁：`VisionLevel.LOW_VISION` 的用户不开读屏，
        // 只有「看得见的那一屏」这一条通道，而叠影恰好打掉的就是那条通道
        // （对比度审计查不出来 —— 它查的是静态配色，不是两层内容叠在一起）。
        // 恒实色是原来那个条件的超集，「降低透明度」的用户拿到的东西没变。
        .background(AppColors.background)
        // 底栏与滚动内容之间的边界原本靠材质的模糊来暗示，改实色之后要自己画一条 ——
        // 底栏背景与页面背景是同一个颜色（`:1037`），不画就真的看不出哪里是边界。
        //
        // **不透明，不要 `.opacity(0.25)`**：那样在亮色下是 `#D6D6D7` 压白底 ≈ 1.4:1、
        // 暗色 ≈ 1.5:1，而 WCAG 1.4.11 对「用来识别控件边界」的非文本内容要求 3:1。
        // 这条线正是这次改动为低视力用户新增的**唯一**视觉边界，做成看不见的那一档
        // 等于白改；而且它不响应「增强对比度」，没有别的补偿。
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.textSecondary)
                .frame(height: 1)
                // 纯装饰：不参与命中测试，也不该在无障碍树里多出一个没有 label 的元素。
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 只读退路那条底栏上的「问一句」。
    ///
    /// 走骨架的那六幕不经过这里 —— 它们的「问一句」在求助中心弹层的第三格
    /// （`BlindActiveRunSafetyHubOption.askQuestion`）。两处按的是同一个
    /// `viewModel.askVoiceQuestion()`，且**都不是**纯 `accessibilityAction`：
    /// 那样只有开读屏的人够得着（记忆 `low-vision-visual-channel-unaudited`）。
    private var askQuestionButton: some View {
        Button("问一句") {
            viewModel.askVoiceQuestion()
        }
        .font(AppFonts.body().weight(.semibold))
        .foregroundColor(AppColors.primary)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        // 描边不是装饰。底栏改成实色之后这个按钮压的是 `AppColors.background`，
        // 而 `secondaryBackground` 与它是**同一族系统语义色**：亮色 `#F2F2F7` 压 `#FFFFFF`
        // ≈ 1.06:1，暗色 `#1C1C1E` 压 `#000000` ≈ 1.22:1 —— 按钮的形状实际上消失了，
        // 只剩文字能认出这里可以点。这个组合此前只有开了「降低透明度」的人会遇到，
        // 改成恒实色等于把它变成所有人的默认，所以必须补上边界。
        // 用 `primary`（就是文字色）而不是灰线：它同时给出 ≈7:1 的边界对比。
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.primary, lineWidth: 2)
        )
        .accessibilityLabel("问一句")
        .accessibilityHint("点击后开始录音，可以问志愿者还有多远、几点开始，或者打电话给志愿者")
        .accessibilityIdentifier("blindOrderStatusAskQuestionButton")
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
