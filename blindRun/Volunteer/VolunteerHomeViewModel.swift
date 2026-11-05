import Combine
import CoreLocation
import SwiftUI

// MARK: - Volunteer Home ViewModel

@MainActor
final class VolunteerHomeViewModel: ObservableObject {
    /// 接单开关。变化同步进 `AppState.volunteerWantsDispatch` —— 根视图的定时上报也读它（#368）。
    @Published var isAvailable = false {
        didSet { appState?.volunteerWantsDispatch = isAvailable }
    }

    /// 为什么要问位置轨迹的单独同意（#368）。非 nil 时 `VolunteerTabView` 盖同意页。
    enum TrackConsentRequest: Equatable {
        /// 滑开接单开关时本机没有同意记录。同意后再去开开关并进接单主页。
        case turnOn
        /// 服务端「可服务」已开着（冷启动 / 别的设备打开）而本机没有同意记录。
        /// 拒绝时替他把服务端开关关掉，否则后端一直当他在线、却收不到位置。
        case resumeStandby
    }

    @Published var trackConsentRequest: TrackConsentRequest?
    /// 拒绝之后滑块上方那句后果说明。下次同意时清掉。
    @Published var trackConsentDeclinedNotice: String?
    /// 从开关发起的同意按下之后置位，由首页把接单主页推出来，然后复位。
    @Published var entersDispatchHubAfterTrackConsent = false
    /// 本次登录里在「自动恢复待命」那一问上拒绝过。拒绝是完整的答案：替他关服务端开关若失败，
    /// 之后的摘要仍会说「开着」，不能因此每次刷新都再问一遍。
    var declinedResumeTrackConsent = false
    @Published var nickname = ""
    @Published var dispatchSummary: VolunteerDispatchSummaryResponse?
    @Published var errorMessage: String?
    @Published var dispatchSummaryErrorMessage: String?
    @Published var dispatchLoadState: AsyncLoadState<VolunteerDispatchSummaryResponse> = .idle
    @Published var refreshPhase: HomeRefreshPhase = .idle
    @Published var isUpdatingAvailability = false
    @Published var activeOrder: OrderDetailResponse?

    /// 已确认但还没到点的跨天预约单，按开跑时间升序（最近的排最前）。
    ///
    /// 🚩 **不能靠 `activeOrder` 承载它**，两条独立的理由：
    /// ① 数据源根本给不到 —— 后端 `VolunteerService.loadActiveOrders` 的白名单只有
    ///    `IN_PROGRESS`/`DRIVER_EN_ROUTE`/`DRIVER_ARRIVED`，`dispatch-summary.activeOrders`
    ///    里从来不会出现 `SCHEDULED_CONFIRMED`（已投 handoff 请后端单开 `scheduledOrders`）。
    /// ② 就算给得到也不该共用一个位 —— `activeVolunteerOrder(from:)` 按 `createdAt` 降序取第一个，
    ///    而新接的即时单 `createdAt` 必然更晚 ⇒ 志愿者在预约日之前又接了一单即时的，
    ///    那张跨天单就从首页消失，直到即时单跑完。而闸门不会因为他在忙就暂停。
    ///
    /// 对标产品同样是两个位：Uber Opportunities Center / Lyft Scheduled pickups /
    /// Rover Upcoming inbox 都独立于「当前行程」
    /// （`docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二.2）。
    @Published var scheduledOrders: [OrderDetailResponse] = []
    /// 正在提交确认/释放的那一单。用 id 而不是 Bool：同屏可能有多张预约单，
    /// 一个全局 Bool 会把所有卡片一起转圈。
    @Published var submittingScheduledOrderID: Int64?
    /// 预约区块自己的错误文案。**不复用 `errorMessage`** —— 那条挂在派单摘要的错误区上，
    /// 预约单拉失败时弹「重试加载」会让人以为整页坏了，而其余内容完全正常。
    @Published var scheduledOrdersMessage: String?

    @Published var locationDispatchWarning: String?

    // WebSocket dispatch state

    /// 待回复 / 刚出结果的邀请，按回复期限升序（由 `AppRealtimeCoordinator` 排好）。
    ///
    /// 🔴 **一队而不是一条**：后端对同一个志愿者的派单跨订单零互斥
    /// （`DispatchService.java:403-406` 的注释自认），并发推两条是真会发生的。
    @Published var invites: [VolunteerInviteState] = []
    /// 邀请卡当前翻到第几张。**用 orderId 而不是下标**：下标会在队列增删时指到另一个人身上，
    /// 而这一屏的动作是「接下 / 拒绝」——指错了就是替别人回复。
    @Published var currentInviteID: Int64?
    /// 刚点了「这次去不了」、还在 5 秒撤销窗口里的那条（§4.4.3）。
    @Published var pendingDecline: VolunteerInviteState?

    /// 队列里当前这一张。
    var currentInvite: VolunteerInviteState? {
        guard let currentInviteID else { return invites.first }
        return invites.first { $0.id == currentInviteID } ?? invites.first
    }

    /// 还等着回复的那几条（结果态的不算）—— 接单主页那个入口的计数用它。
    var invitesAwaitingReply: [VolunteerInviteState] { invites.filter(\.isAwaitingReply) }

    /// 当前这一张的派单载荷。
    ///
    /// ⚠️ **setter 只服务于测试**（两个测试文件里共 38 处 `viewModel.incomingOrder = …`）。
    /// 生产代码一律走 `syncInvites(with:)` 入队 —— 那条路才会建立倒计时与到期归宿。
    var incomingOrder: WSNewOrder? {
        get { currentInvite?.order }
        set {
            guard let newValue else {
                invites.removeAll()
                currentInviteID = nil
                return
            }
            enqueue(order: newValue, receivedAt: Date(), expiresAt: Date().addingTimeInterval(30))
        }
    }

    /// 当前这一张剩几秒。setter 同上，只给测试用。
    var dispatchCountdown: Int {
        get { currentInvite?.remainingSeconds ?? 0 }
        set {
            guard let id = currentInvite?.id,
                  let index = invites.firstIndex(where: { $0.id == id }) else { return }
            invites[index].remainingSeconds = newValue
        }
    }

    @Published var isRespondingToDispatch = false
    @Published var acceptedDispatchOrderId: Int64?
    @Published var acceptedDispatchInitialOrder: OrderDetailResponse?
    /// 要进的那一单通话磨合。**两种到达方式共用这一个导航源。**
    ///
    /// 🚨 带着**派单载荷**而不只是订单 id，因为通话磨合期志愿者根本取不到订单详情：
    /// 后端 `OrderQueryService.getOrder` 只认 `order.volunteer`，而 `markInterested`
    /// 只写 `dispatchCurrentVolunteerId`、`order.volunteer` 恒为 null ⇒ `GET /api/orders/{id}` 403。
    /// 那条推送是那一刻**唯一**的订单事实来源（出发地、时间、导盲犬），丢了就没别的地方能取回来。
    ///
    /// 而冷启动恢复那条路上它**确实丢了**（App 被杀，推送不会重放），所以
    /// `VolunteerIntroCallRoute.dispatchOrder` 是可选的 —— 见那个类型的注释。
    @Published var pendingIntroCallOrder: VolunteerIntroCallRoute?
    /// 已经因为 `introCallOrderId` 自动跳过一次的那一单。
    ///
    /// 🚨 **没有它就是一个导航死循环**：用户手动返回 → `pendingIntroCallOrder` 被清 →
    /// 下一次 `dispatch-summary` 刷新（首页每几秒就会刷）看到 `introCallOrderId` 还在 →
    /// 又把他推回通话页。在 20 分钟窗口结束前他出不来。
    ///
    /// 只记 id 不记「跳过几次」：换了一单就该再跳一次，那是另一个人在等他。
    var autoOpenedIntroCallOrderId: Int64?

    /// 冷启动三岔路已经判过了（设计交付 v3 §4.1）。
    ///
    /// 🚨 **这道闸不是优化，没有它就是一个出不来的导航循环。** 判据读的是
    /// `activeOrder` / `scheduledOrders`，而这两样每 10 秒刷新一次都还在 ——
    /// 志愿者从订单页返回首页，下一次刷新立刻把他推回去。和
    /// `autoOpenedIntroCallOrderId` 防的是同一件事，只是这一条的窗口更严：
    /// **只判首次加载那一轮**（「打开 App 时」，§4.1 的原话），之后一律不再自动导航。
    ///
    /// 窗口在辅助加载收尾时关上（预约单那一岔要等它）。首次加载**失败或被取消**时窗口
    /// 留着，由下一次真正跑完的加载来判 —— 那一次仍然是「他打开 App 之后第一次看到的结果」。
    var didResolveLaunchRoute = false

    weak var appState: AppState?
    var speechService: SpeechService?
    var realtimeDispatchCancellable: AnyCancellable?
    var realtimeRecoveryCancellable: AnyCancellable?
    var realtimeStatusCancellable: AnyCancellable?
    var realtimeVolunteerLostCancellable: AnyCancellable?
    var inviteWithdrawalCancellable: AnyCancellable?
    var inviteSnapshotCancellable: AnyCancellable?
    var lockScreenAcceptCancellable: AnyCancellable?
    /// 一条 ticker 刷**整队**邀请的剩余秒数。**不是每条一个** —— 每条一个的话
    /// 队列增删时要各自建/撤，而它们刷新的是同一个时钟。
    var countdownTask: Task<Void, Never>?
    /// 「这次去不了」的 5 秒延时发送（§4.4.3 的撤销窗口）。
    var pendingDeclineTask: Task<Void, Never>?
    /// 撤销窗口里的那张邀请被撤回 / 判失效了：撤销时以这个结果恢复（`nil` = 没有）。
    var pendingDeclineInvalidation: VolunteerInviteState.Outcome?
    var delayedSummaryRefreshTask: Task<Void, Never>?
    /// 本地刚改过预约列表（确认 / 释放成功后移走那一单）的时刻。发出早于它的摘要不再覆盖预约列表 ——
    /// 否则在途的那次刷新会把刚移走的单放回来，最长 10 秒（#471 代码复核）。
    var scheduledOrdersChangedLocallyAt: Date?
    /// 撤销窗口的长度（设计交付 v3 §10「撤销『去不了』时长 = 5 秒」）。
    let declineUndoWindow: TimeInterval
    var isSceneActive = false
    /// 定位单次采样为 nil 是真机上的常见瞬态，报警必须等「连续失败」才算数。
    /// 取 3：刷新循环每 10 秒上报一次，连续 3 次约等于持续 20 秒都拿不到定位，
    /// 足以滤掉单次采样抖动，又不至于让真的定位失效拖到半分钟后才提示志愿者。
    static let locationReportFailureThreshold = 3
    var consecutiveLocationReportFailures = 0
    var currentLocationProvider: () -> CLLocationCoordinate2D? = { nil }
    var locationAuthorizedProvider: () -> Bool = { false }
    let reportVolunteerLocation: @MainActor (AppState, CLLocationCoordinate2D?, Bool) -> Bool
    let dispatchPropagationDelay: TimeInterval
    let loadTimeout: TimeInterval
    var activeLoadTask: Task<Void, Never>?
    var activeRequestID: UUID?
    var auxiliaryLoadTask: Task<Void, Never>?
    var auxiliaryRequestID: UUID?
    var summaryRefreshTask: Task<Void, Never>?
    var summaryRefreshID: UUID?
    var refreshLoopTask: Task<Void, Never>?
    /// 去 `GET /api/orders/available` 给邀请补三项的那条任务。
    /// **只留一条**：每条新邀请都会触发一次，而它们要的是同一份列表。
    var inviteSupplementTask: Task<Void, Never>?

    init(
        dispatchPropagationDelay: TimeInterval = 1,
        loadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        declineUndoWindow: TimeInterval = 5,
        reportVolunteerLocation: @escaping @MainActor (AppState, CLLocationCoordinate2D?, Bool) -> Bool = {
            VolunteerLocationReporter.reportIfNeeded(
                appState: $0,
                currentLocation: $1,
                locationAuthorized: $2
            )
        }
    ) {
        self.dispatchPropagationDelay = max(0, dispatchPropagationDelay)
        self.loadTimeout = max(0.05, loadTimeout)
        self.declineUndoWindow = max(0, declineUndoWindow)
        self.reportVolunteerLocation = reportVolunteerLocation
    }

    var isLoading: Bool { refreshPhase.isRefreshing }

    var statusText: String {
        dispatchSummary?.dispatchStatusText ?? (isAvailable ? "等待系统派单" : "已关闭接单")
    }

    /// 滑块与接单主页胶囊共用的判定。「接单中」只从这里出。
    var availabilityStatus: VolunteerAvailabilityStatus {
        .resolve(
            isAvailable: isAvailable,
            hasSummary: dispatchSummary != nil,
            canDispatch: dispatchSummary?.canDispatch,
            reasons: dispatchSummary?.notAvailableReasons ?? [],
            explanation: dispatchSummary?.reasonText ?? ""
        )
    }

    var displayedErrorMessage: String? {
        errorMessage ?? dispatchSummaryErrorMessage
    }

    var statusColor: Color {
        if dispatchSummary?.canDispatch == true {
            return AppColors.success
        }
        return isAvailable ? AppColors.warning : AppColors.textSecondary
    }

    static func activeVolunteerOrder(from orders: [OrderDetailResponse]) -> OrderDetailResponse? {
        orders
            .filter { $0.status.isActiveForVolunteer }
            .sorted { $0.sortKey > $1.sortKey }
            .first
    }

    /// 打开 App 时该不该跳过主页、直接进订单页 —— 设计交付 v3 §4.1 三岔路的第二岔。
    ///
    /// 「有进行中订单（已出发 / 汇合 / 跑步中）**或 2 小时内开始的陪跑**」。两个来源各管一半，
    /// 不能合并成一个列表：`activeOrder` 来自 `dispatch-summary.activeOrders`，后端
    /// `VolunteerService.loadActiveOrders` 的白名单**只有**那三态；跨天预约单只在
    /// `scheduledOrders`（单独打 `GET /api/orders/mine`）里。
    ///
    /// 🚩 **已经过点还没走的算在内**（差值为负）—— 那种情况比「还有 1 小时」更该打开，
    /// 而写成 `0..<lead` 会把它漏掉。判据因此是「距开跑不足 lead」，不是「在 [0, lead] 区间内」。
    ///
    /// 纯函数是为了有可以验红的测试面：这条判据整个长在网络回调里，
    /// 挂在视图上就只能靠 UI 测试隔着三次请求去断言一个时间阈值。
    nonisolated static func launchOrderToOpen(
        activeOrder: OrderDetailResponse?,
        scheduledOrders: [OrderDetailResponse],
        now: Date = Date(),
        leadMinutes: Int
    ) -> OrderDetailResponse? {
        if let activeOrder { return activeOrder }
        let lead = TimeInterval(leadMinutes * 60)
        // `scheduledOrders` 已按 `plannedStart` 升序（`applyUpcoming`），最近的排最前。
        // 解析不出时间的不猜 —— 宁可让他自己从首页点进去，也不要凭空把人推进一张
        // 可能几天后才开始的单。
        return scheduledOrders.first { order in
            guard let start = order.plannedStart?.backendTimestamp else { return false }
            return start.timeIntervalSince(now) < lead
        }
    }

    func configure(
        with appState: AppState,
        speechService: SpeechService,
        currentLocationProvider: @escaping () -> CLLocationCoordinate2D? = { nil },
        locationAuthorizedProvider: @escaping () -> Bool = { false }
    ) {
        self.appState = appState
        self.speechService = speechService
        self.currentLocationProvider = currentLocationProvider
        self.locationAuthorizedProvider = locationAuthorizedProvider
        appState.liveEscortCoordinator.onTrackConsentQuestion = { [weak self] event in
            self?.escortTrackConsentQuestion(event)
        }
        apply(profile: appState.volunteerProfile)
        subscribeToRealtimeCoordinator(appState)
        seedInvitesForUITestsIfNeeded()
    }

    func setSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
        if !isActive {
            cancelLoading()
            summaryRefreshTask?.cancel()
            summaryRefreshTask = nil
            summaryRefreshID = nil
            delayedSummaryRefreshTask?.cancel()
            delayedSummaryRefreshTask = nil
            refreshLoopTask?.cancel()
            refreshLoopTask = nil
        }
    }

    // MARK: - 邀请队列

    /// 邀请卡开着没有。**收起不等于回复**：这一位只控制那张 sheet 的可见性，
    /// 队列与倒计时都不受它影响（设计交付 v3 §4.4.2「下滑或点背景：收起，不算回复」）。
    @Published var isInviteSheetPresented = false

    /// 接单主页（S3/S4）此刻在不在屏上。**由那一页自己的 `onAppear`/`onDisappear` 写。**
    ///
    /// 它是 §4.4.1 判定的另一半输入：坐在接单主页上等单的人，邀请该直接顶到脸上；
    /// 在别的页面（主页 / 记录 / 我的 / 订单页「约好」）只该收一条横幅。
    /// view model 自己看不到这件事 —— 接单主页是 push 出来的一页，
    /// 而 view model 挂在 `VolunteerTabView` 上。
    @Published var isDispatchHubVisible = false

    /// 正在顶部显示的那条横幅。`nil` = 不显示。4 秒后由视图侧的计时收起（§10「横幅停留 4 秒」）。
    @Published var bannerInvite: VolunteerInviteState?
}
