import Combine
import CoreLocation
import SwiftUI

/// 首页那个「可服务」开关叫什么名字 —— **全 App 单一来源**。
///
/// 🔴 存在的理由是一个真实缺陷：资质审核通过的引导语此前写的是
/// 「请回到首页开启**接单开关**」（`VolunteerCertificateUploadView.swift:105`、`:130`），
/// 而首页那个控件叫「可服务开关」。**首页上根本没有叫「接单开关」的东西** ——
/// 用户照着那句话回首页找，找到的是另一个名字，没有办法确认这是不是同一个控件。
/// 对按控件名导航的读屏用户尤其致命，但看得见的人一样要停顿一下。
///
/// 抽成常量而不是写一条「两处文案要一致」的用例：常量化之后两处**不可能**再各叫各的，
/// 而用例只能在漂移发生之后报警。
enum VolunteerAvailabilityCopy {
    static let toggleTitle = "可服务开关"

    /// 引导用户去开这个开关的那半句。资质审核通过、身份材料通过两条路径共用。
    static let goOpenItHint = "请回到首页开启\(toggleTitle)。"
}

// MARK: - Volunteer Home ViewModel

@MainActor
final class VolunteerHomeViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var nickname = ""
    @Published var dispatchSummary: VolunteerDispatchSummaryResponse?
    @Published var errorMessage: String?
    @Published var dispatchSummaryErrorMessage: String?
    @Published private(set) var dispatchLoadState: AsyncLoadState<VolunteerDispatchSummaryResponse> = .idle
    @Published private(set) var refreshPhase: HomeRefreshPhase = .idle
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
    @Published private(set) var scheduledOrders: [OrderDetailResponse] = []
    /// 正在提交确认/释放的那一单。用 id 而不是 Bool：同屏可能有多张预约单，
    /// 一个全局 Bool 会把所有卡片一起转圈。
    @Published private(set) var submittingScheduledOrderID: Int64?
    /// 预约区块自己的错误文案。**不复用 `errorMessage`** —— 那条挂在派单摘要的错误区上，
    /// 预约单拉失败时弹「重试加载」会让人以为整页坏了，而其余内容完全正常。
    @Published private(set) var scheduledOrdersMessage: String?

    @Published private(set) var locationDispatchWarning: String?

    // WebSocket dispatch state

    /// 待回复 / 刚出结果的邀请，按回复期限升序（由 `AppRealtimeCoordinator` 排好）。
    ///
    /// 🔴 **一队而不是一条**：后端对同一个志愿者的派单跨订单零互斥
    /// （`DispatchService.java:403-406` 的注释自认），并发推两条是真会发生的。
    @Published private(set) var invites: [VolunteerInviteState] = []
    /// 邀请卡当前翻到第几张。**用 orderId 而不是下标**：下标会在队列增删时指到另一个人身上，
    /// 而这一屏的动作是「接下 / 拒绝」——指错了就是替别人回复。
    @Published var currentInviteID: Int64?
    /// 刚点了「这次去不了」、还在 5 秒撤销窗口里的那条（§4.4.3）。
    @Published private(set) var pendingDecline: VolunteerInviteState?

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
    /// 接单被后端 403 `VOLUNTEER_NOT_VERIFIED` 拒绝后，错误区要长出「去上传资质证书」入口。
    @Published var needsCertificateUpload = false
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
    private var autoOpenedIntroCallOrderId: Int64?

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
    private var didResolveLaunchRoute = false

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var realtimeDispatchCancellable: AnyCancellable?
    private var realtimeRecoveryCancellable: AnyCancellable?
    private var realtimeStatusCancellable: AnyCancellable?
    /// 一条 ticker 刷**整队**邀请的剩余秒数。**不是每条一个** —— 每条一个的话
    /// 队列增删时要各自建/撤，而它们刷新的是同一个时钟。
    private var countdownTask: Task<Void, Never>?
    /// 「这次去不了」的 5 秒延时发送（§4.4.3 的撤销窗口）。
    private var pendingDeclineTask: Task<Void, Never>?
    private var delayedSummaryRefreshTask: Task<Void, Never>?
    private let declineStreak: VolunteerDeclineStreak
    /// 撤销窗口的长度（设计交付 v3 §10「撤销『去不了』时长 = 5 秒」）。
    private let declineUndoWindow: TimeInterval
    private var isSceneActive = false
    /// 定位单次采样为 nil 是真机上的常见瞬态，报警必须等「连续失败」才算数。
    /// 取 3：刷新循环每 10 秒上报一次，连续 3 次约等于持续 20 秒都拿不到定位，
    /// 足以滤掉单次采样抖动，又不至于让真的定位失效拖到半分钟后才提示志愿者。
    private static let locationReportFailureThreshold = 3
    private var consecutiveLocationReportFailures = 0
    private var currentLocationProvider: () -> CLLocationCoordinate2D? = { nil }
    private var locationAuthorizedProvider: () -> Bool = { false }
    private let reportVolunteerLocation: @MainActor (AppState, CLLocationCoordinate2D?, Bool) -> Bool
    private let dispatchPropagationDelay: TimeInterval
    private let loadTimeout: TimeInterval
    private var activeLoadTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var auxiliaryLoadTask: Task<Void, Never>?
    private var auxiliaryRequestID: UUID?
    private var summaryRefreshTask: Task<Void, Never>?
    private var summaryRefreshID: UUID?
    private var refreshLoopTask: Task<Void, Never>?
    /// 去 `GET /api/orders/available` 给邀请补三项的那条任务。
    /// **只留一条**：每条新邀请都会触发一次，而它们要的是同一份列表。
    private var inviteSupplementTask: Task<Void, Never>?

    init(
        dispatchPropagationDelay: TimeInterval = 1,
        loadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        declineStreak: VolunteerDeclineStreak = VolunteerDeclineStreak(),
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
        self.declineStreak = declineStreak
        self.declineUndoWindow = max(0, declineUndoWindow)
        self.reportVolunteerLocation = reportVolunteerLocation
    }

    var isLoading: Bool { refreshPhase.isRefreshing }

    var statusText: String {
        dispatchSummary?.dispatchStatusText ?? (isAvailable ? "等待系统派单" : "已关闭接单")
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

    var acceptBlockMessage: String? {
        VolunteerOrderActionGuard.acceptBlockMessage(
            profile: appState?.volunteerProfile,
            registrationStatus: appState?.volunteerRegistrationStatus
        )
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
        leadMinutes: Int = AppConstants.Timing.volunteerOrderAutoOpenLeadMinutes
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
        apply(profile: appState.volunteerProfile)
        subscribeToRealtimeCoordinator(appState)
        seedInvitesForUITestsIfNeeded()
    }

    /// UI 测试用的「预置几条待回复邀请」。与 `AIDRUN_UI_TEST_SEED_ORDER_STATUS` 同一套做法。
    ///
    /// 🚩 **必须有这个种子，否则邀请卡在 UI 测试里根本到不了。** 派单只从 WebSocket 来，
    /// 而 UI 测试默认 `disableWebSocket` —— 没有种子的话这一屏的无障碍形状永远没人验。
    ///
    /// `#if DEBUG` 包住：Release 产物里不存在这条路径，一个环境变量骗不出一张假邀请。
    private func seedInvitesForUITestsIfNeeded() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_RESET_STATE"] == "1",
              let raw = environment["AIDRUN_UI_TEST_SEED_INVITES"],
              let count = Int(raw), count > 0 else { return }
        let now = Date()
        for index in 0..<count {
            enqueue(
                order: Self.uiTestSeedInvite(orderId: Int64(9_000 + index), now: now),
                receivedAt: now,
                // 每条差 30 秒，好让「按回复期限升序」和分页点在 UI 上真的分得开。
                expiresAt: now.addingTimeInterval(TimeInterval(120 + index * 30)),
                // 🚩 真实路径上这三项由 `GET /api/orders/available` 补，而 mock 对那条路径恒返空数组
                // （它没有这些客户端注入的 id）。直接种进来，否则跑者行在 UI 测试里永远不可达 ——
                // 而「整行不渲染」恰恰是它出问题时的样子，没人分得出是渲染坏了还是数据没来。
                // 匹配逻辑本身由 `VolunteerInviteState.merge` 的单测验。
                supplement: VolunteerInviteSupplement(
                    visionLevel: VisionLevel.totalBlind.rawValue,
                    tetherPreference: TetherPreference.tetherRope.rawValue,
                    expectedDurationMinutes: 60
                ),
                // 🚩 **显式钉死 `.inviteCard`，不许现算。** 种子在 `configure` 里跑，
                // 那一刻接单主页还没打开 ⇒ `resolve` 会落到 `.banner`，而这一整组 UI 用例
                // （`blindRunUITests` 的邀请卡无障碍形状）验的就是那张卡自动弹出来。
                presentation: .inviteCard,
                // 种下 N 条就响 N 声，而那台真机正拿在跑测的人手里。
                announces: false
            )
        }
        #endif
    }

    #if DEBUG
    private static func uiTestSeedInvite(orderId: Int64, now: Date) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: nil,
            orderId: orderId,
            startAddress: "深圳湾公园 3 号入口",
            startLatitude: nil,
            startLongitude: nil,
            distanceKm: 3.2,
            // 🔴 **不能是 nil。** `RunPlanFormat.shortStart(nil)` 返回 nil ⇒ 那行大字退回
            // fallback「新的陪跑邀请」，于是调试预置永远看不到真实版式（28pt 的「明天 7:00」），
            // 而那正是这张卡的主角。2026-09-18 项目负责人的截图就是这么来的。
            plannedStart: Self.uiTestSeedPlannedStart(now: now),
            plannedEnd: nil,
            dispatchTimeoutSeconds: 120,
            priority: "HIGH",
            pacePreference: "MODERATE",
            hasGuideDog: false,
            requiresIntroCall: true,
            paceMinSecondsPerKm: 390,
            paceMaxSecondsPerKm: 450,
            plannedDistanceMeters: 5_000
        )
    }

    /// 明天 07:00，写成后端那种**无时区的 `LocalDateTime`** 串（`String.backendLocalDate` 认的形状）。
    ///
    /// 用「明天」而不是写死某一天：`RunPlanFormat.shortStart` 只对今天 / 明天 / 后天给相对日期，
    /// 写死的日期过几天就退化成「9月18日 7:00」，而调试预置要看的恰恰是「明天 7:00」那一版。
    private static func uiTestSeedPlannedStart(now: Date) -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let at7 = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return DateFormatter.aidRunBackendLocalDateTime.string(from: at7)
    }
    #endif

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

    // MARK: - WebSocket Dispatch

    /// 响应派单。
    ///
    /// 🚨 **发 `.accept` 还是 `.interested` 由推送里的 `requiresIntroCall` 决定，不由这里推算。**
    /// 后端 `app.intro-call.enabled` 默认 true，陌生人直接发 `ACCEPT` 会 409
    /// `INTRO_CALL_REQUIRED`（`DispatchService.handleAccept` 的守卫）。后端只在两种情况放行
    /// `ACCEPT`：这一对已经磨合成功过（`IntroCallPair.outcome == MATCHED`），或者距开跑时间
    /// 已经塞不下一轮通话窗口。两个判据客户端都拿不到 —— 前者在后端库里，后者的窗口长度是
    /// 后端配置（`app.intro-call.window-minutes`）。
    ///
    /// 所以判断只有一份，在后端（`DispatchService.introCallWindowFits`），结论随派单推送下发：
    /// `WSNewOrder.requiresIntroCall` → `WSNewOrder.dispatchRespondAction`。
    /// 调用方按那个属性传 `action` 进来，这里不再二次判断。
    ///
    /// **两个方向的 409 都要兜，因为推送是一个快照**：它发出之后，这一对的磨合记录
    /// 或 `app.intro-call.enabled` 都可能变，于是快照给的答案两边都可能过时。
    /// 志愿者已经点过这个动作了，30 秒倒计时里不该让他为后端改主意再点一遍。
    ///
    /// - `.accept` → 409 `INTRO_CALL_REQUIRED`：就地改发 `.interested` 重试一次
    ///   （下面那个内层 `do/catch`）。`.interested` 没有额外前置闸，就地重发是安全的。
    /// - `.interested` → 409 `INTRO_CALL_NOT_REQUIRED`：**递归重走本函数**而不是就地补一个
    ///   API 调用 —— `.accept` 有 `.interested` 没有的前置闸（定位权限判定 +
    ///   `VolunteerLocationReporter.reportIfNeeded`），就地补调用等于绕过它们。
    ///
    /// 两条各自只走一次，所以不会来回打：前者靠内层 `do` 的结构（重试不再被 catch 接住），
    /// 后者靠 `allowsIntroCallUpgrade` —— 递归时传 `false`。**调用方不要传这个参数。**
    ///
    /// ⚠️ 顺带一条历史：`requiresIntroCall` 曾经只挂在 `AvailableOrderResponse` 上，
    /// 而本 App 不调 `GET /api/orders/available`，所以那段时间客户端对陌生人一律发
    /// `.interested`，`AGENTS.md` §5 也据此写着「字段搬到推送上之前不要加 `.accept` 分支」。
    /// 后端已于 2026-08-22（迁移 `0031`）把它搬到 `NEW_ORDER` 上并标为**必填**
    /// （`websocket-protocol.md`「客户端按它决定 `/respond` 发哪个 `action`」），前提已解除。
    func respondToDispatch(
        action: OrderRespondAction,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        orderId: Int64? = nil,
        allowsIntroCallUpgrade: Bool = true
    ) {
        // 队列里可能同时有几条邀请（后端并发派单），所以**必须钉死是哪一条** ——
        // 不传就是「当前翻到的那张」，递归兜底那一支会把它原样传回来。
        let targetID = orderId ?? currentInvite?.id
        guard let order = invites.first(where: { $0.id == targetID })?.order else { return }
        guard let appState else { return }
        let accept = action == .accept
        if accept || action == .interested {
            // 定位权限只对 `.accept` 卡：`INTERESTED` 不上报位置，也还不是接单。
            // 为一件不需要定位的事拦住用户，代价落回正在等的盲人身上。
            // 资质（`verified`）两条路径都要过 —— 后端 `markInterested` 也跑同一套校验。
            let message = accept
                ? VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    registrationStatus: appState.volunteerRegistrationStatus,
                    locationAuthorized: locationAuthorized
                )
                : VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    registrationStatus: appState.volunteerRegistrationStatus
                )
            if let message {
                errorMessage = message
                speechService?.speakError(message)
                return
            }
        }
        isRespondingToDispatch = true
        Task {
            do {
                var effectiveAction = action
                do {
                    try await submitDispatchResponse(
                        action: action,
                        order: order,
                        appState: appState,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized
                    )
                } catch let error as APIError
                    where action == .accept && error.errorCode == .introCallRequired {
                    // 推送说「这一单可以直接接」，后端却说不行 —— 推送发出后这一对的磨合记录
                    // 或 `app.intro-call.enabled` 变了。这是同一个意图的两种发法，
                    // 不是一个需要用户重新决策的场景，所以自己改口，**只重试一次**。
                    // 重试仍失败就落到下面的正常错误分支。
                    effectiveAction = .interested
                    try await submitDispatchResponse(
                        action: .interested,
                        order: order,
                        appState: appState,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized
                    )
                }
                // 请求已经在上面的 `submitDispatchResponse` 里发过了（`.accept` 撞上
                // `INTRO_CALL_REQUIRED` 时会自己改口重发一次），这里只是记结果。
                // 判据用 `effectiveAction` 而不是入参 `action`：改过口之后这一单没接成。
                let acceptedOrderId = effectiveAction == .accept ? order.orderId : nil
                appState.realtimeCoordinator.clearDispatch(orderID: order.orderId)

                // 🔴 **结果先落在卡上，再去刷新 —— 顺序不能反。**
                // `refreshAfterDispatchResponse` 里会走一遍 `apply(summary:)`，而那里面有
                // 冷启动三岔路 `resolveLaunchRouteIfNeeded()`。先刷新的话，那一刻这条邀请
                // 还是「待回复」状态，三岔路的 guard 放行 ⇒ 它直接把人推进订单页，
                // 「已约好」那张卡一闪而过。由
                // `testAcceptingDispatchShowsTheBookedCardAndOnlyNavigatesOnTap` 红出来
                // （第一版修在 guard 上，没用 —— 问题不在判据，在这两步的先后）。
                //
                // 穷举 switch：`OrderRespondAction` 将来加值时编译器会逼一次决策。
                // 此前这里是 `if .interested { … } else { … }`，而那个 `else` 把 `.decline`
                // 也当成了「已接下」。
                switch effectiveAction {
                case .interested:
                    // 通话磨合那一支**照旧直接跳走**，不停在结果卡上。
                    // 设计稿 §4.4.3 的成功态只有「已约好」一种，而 `INTERESTED` 不是接单：
                    // 那边 20 分钟的通话窗口已经在走，多一次「查看订单」的点击是在烧他的窗口。
                    removeInvite(orderID: order.orderId)
                    pendingIntroCallOrder = VolunteerIntroCallRoute(dispatchOrder: order)
                case .accept:
                    // 🚩 **接下之后不再自动 push 订单页。** §4.4.3：卡片**原地**变成「已约好」，
                    // 由用户点「查看订单」才走。自动跳等于把那张确认卡一闪而过 ——
                    // 而它是这一刻唯一一处告诉他「全名和电话已经放进订单」的地方。
                    markInvite(orderID: order.orderId, outcome: .accepted)
                    declineStreak.reset()
                    // 交付包 03 触感总表：接下邀请成功 `.success`。下一行那句播报就是它的语义。
                    HapticFeedback.play(.success)
                case .decline:
                    removeInvite(orderID: order.orderId)
                }
                speechService?.speak(Self.dispatchResponseSpeech(for: effectiveAction))

                let acceptedOrder = await refreshAfterDispatchResponse(
                    acceptedOrderId: acceptedOrderId,
                    appState: appState
                )
                isRespondingToDispatch = false
                acceptedDispatchInitialOrder = acceptedOrder
            } catch let error as APIError {
                isRespondingToDispatch = false
                if appState.handleAuthenticatedAPIError(error) {
                    return
                }
                // 熟人误发 `INTERESTED`：后端 409 `INTRO_CALL_NOT_REQUIRED`（2026-08-26 新增）。
                //
                // 🚩 **必须重新走一遍本函数，不能就地补一个 API 调用**：`.accept` 有 `.interested`
                // 没有的前置闸（定位权限判定 + `VolunteerLocationReporter.reportIfNeeded`），
                // 就地补调用等于绕过它们，志愿者会在没给定位权限的情况下把单接下来。
                // 闸拦住时用户看到的是「需要定位权限」这类可执行的提示，也是对的。
                //
                // 不弹「操作失败」就停：派单弹窗只有「有意向」和「拒绝」两个按钮，
                // 停在这里等于让志愿者卡在一个本该能接的单上（后端在那条 handoff 里点名要求别这样）。
                if allowsIntroCallUpgrade,
                   action == .interested,
                   error.errorCode == .introCallNotRequired {
                    respondToDispatch(
                        action: .accept,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized,
                        // 队列化之后必须显式带上 orderId：递归这一跳发生在 `await` 之后，
                        // 期间用户可能已经翻到了下一张卡，`currentInvite` 会指到另一个人身上。
                        orderId: order.orderId,
                        allowsIntroCallUpgrade: false
                    )
                    return
                }
                needsCertificateUpload = error.errorCode == .volunteerNotApproved
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            } catch {
                isRespondingToDispatch = false
                errorMessage = "响应失败，请重试"
                speechService?.speakError("响应失败，请重试")
            }
        }
    }

    /// 只做「发出去」这一件事，成功后的刷新 / 收弹窗 / 播报都留在调用方 ——
    /// 409 兜底会把它调两次，而那些后处理只该跑一次。
    private func submitDispatchResponse(
        action: OrderRespondAction,
        order: WSNewOrder,
        appState: AppState,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async throws {
        if action == .accept {
            VolunteerLocationReporter.reportIfNeeded(
                appState: appState,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized
            )
        }
        try await appState.orders.respond(orderId: order.orderId, action: action)
    }

    /// 三种动作各自的播报。`.interested` 刻意不说「已接单」——它不是接单，说错了志愿者
    /// 会以为事情已经定了，然后错过那通电话。
    static func dispatchResponseSpeech(for action: OrderRespondAction) -> String {
        switch action {
        case .accept:
            return "已接受订单"
        case .decline:
            return "已拒绝订单"
        case .interested:
            return "已告诉跑者你有意向，请留意他的来电"
        }
    }

    /// 清空整队邀请。**这不是「下滑收起」** —— 收起走 `isInviteSheetPresented = false`，
    /// 邀请留在队列里、倒计时继续走，接单主页上还有回来的入口（§4.4.2「不算回复」）。
    /// 这个函数只在登出 / 换角色 / 测试收尾这类「整个上下文没了」的时候用。
    func dismissDispatch() {
        countdownTask?.cancel()
        countdownTask = nil
        // 走 `removeInvite` 而不是 `invites.removeAll()`：协调器那一份也要清，
        // 不然下一条推送会把这些邀请整队灌回来。
        for id in invites.map(\.id) { removeInvite(orderID: id) }
        currentInviteID = nil
        bannerInvite = nil
        isRespondingToDispatch = false
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
    @Published private(set) var bannerInvite: VolunteerInviteState?

    /// 首页标签上的数字角标（§4.4.1「首页标签加数字角标」）。
    ///
    /// 陪跑进行中恒 0：那一档设计稿要求「不推送、不横幅、不震动」，
    /// 而一枚红点同样是打断。它们会在他跑完回到接单主页时以卡片出现。
    var inviteBadgeCount: Int {
        guard !isEscortUnderway else { return 0 }
        return invitesAwaitingReply.count
    }

    /// 他此刻正走在某一单里（§4.4.1 那行「已出发 / 汇合 / 跑步中 / 等待中」）。
    ///
    /// 取 `activeOrder` 的状态而不是 `activeOrder != nil`：后端
    /// `VolunteerService.loadActiveOrders` 的白名单今天恰好就是这三态，
    /// 而「恰好相等」不是契约 —— 白名单一旦放宽，`!= nil` 会静默把「约好」也算成陪跑中，
    /// 表现是人还在家里就再也收不到邀请提示。
    var isEscortUnderway: Bool {
        activeOrder?.status.isEscortUnderway ?? false
    }

    /// 横幅到时间收起，或者用户点了「查看」。**不动队列**：收起横幅不等于回复。
    func dismissInviteBanner() {
        bannerInvite = nil
    }

    /// 横幅上的「查看」：顶出邀请卡，横幅让位。
    func presentInviteSheetFromBanner() {
        bannerInvite = nil
        isInviteSheetPresented = true
    }

    /// 连续 3 次「去不了」之后，接单主页上那句不带惩罚的询问该不该出现（§4.4.3）。
    var shouldAskAboutAvailability: Bool { declineStreak.shouldAskAboutAvailability }

    /// 问过一次就够。反复问就成了惩罚，而设计稿写死了「不做任何惩罚」。
    func acknowledgeAvailabilityPrompt() {
        declineStreak.reset()
        objectWillChange.send()
    }

    /// 与 `AppRealtimeCoordinator` 的队列对账。
    ///
    /// 🚩 **是对账不是覆盖**：本地这一队里可能有已经出结果的（`.accepted` / `.expired`），
    /// 而协调器那边一出结果就把它移走了。直接赋值会让「已约好」那张卡当场消失，
    /// 正是 §4.4.3 点名不要的「关掉再弹一个新的」。
    private func syncInvites(with prompts: [RealtimeDispatchPrompt]) {
        let known = Set(invites.map(\.id))
        for prompt in prompts where !known.contains(prompt.order.orderId) {
            enqueue(
                order: prompt.order,
                receivedAt: prompt.receivedAt,
                expiresAt: prompt.expiresAt
            )
        }
    }

    /// - Parameters:
    ///   - presentation: 这一条该怎么出现（设计交付 v3 §4.4.1）。默认按当下状态现算；
    ///     UI 测试的种子那条路**显式传 `.inviteCard`** —— 它验的就是邀请卡的无障碍形状，
    ///     而种子是在 `configure` 里跑的，那一刻接单主页还没打开，现算会落到 `.banner`。
    ///   - announces: 震动 / 提示音 / 播报的总闸。UI 测试的种子那条路传 `false` ——
    ///     种下 N 条就响 N 声，而那台真机正拿在跑测的人手里。
    private func enqueue(
        order: WSNewOrder,
        receivedAt: Date,
        expiresAt: Date,
        supplement: VolunteerInviteSupplement? = nil,
        presentation: VolunteerInvitePresentation? = nil,
        announces: Bool = true
    ) {
        guard !invites.contains(where: { $0.id == order.orderId }) else { return }
        let remaining = max(0, Int(ceil(expiresAt.timeIntervalSinceNow)))
        guard remaining > 0 else { return }
        let mode = presentation ?? VolunteerInvitePresentation.resolve(
            isEscortUnderway: isEscortUnderway,
            isOnDispatchHub: isDispatchHubVisible
        )
        let invite = VolunteerInviteState(
            order: order,
            receivedAt: receivedAt,
            expiresAt: expiresAt,
            remainingSeconds: remaining,
            outcome: nil,
            // 推送自带就用推送的（后端 #306 / #357 起全都有）；老服务端才等 `/available` 来补。
            supplement: supplement ?? VolunteerInviteSupplement(order),
            arrivedDuringEscort: mode == .stashedDuringRun
        )
        invites.append(invite)
        invites.sort { $0.expiresAt < $1.expiresAt }
        if currentInviteID == nil { currentInviteID = invites.first?.id }
        if mode.presentsInviteSheet { isInviteSheetPresented = true }
        // 🚩 横幅只在**没有**邀请卡开着时顶出来。他已经在看卡了，再在头顶压一条
        // 「新的陪跑邀请 · 查看」是在请他打开他正看着的那个东西。
        if mode.showsBanner, !isInviteSheetPresented { bannerInvite = invite }
        appState?.realtimeCoordinator.markDispatchPresented(orderID: order.orderId)
        if announces {
            // 设计交付 v3 §4.4.1：邀请卡那一档「轻震一次 + 短提示音一次（跟随静音开关）」，
            // 横幅那一档「轻震一次，**无声音**」，陪跑中那一档三样都不要。
            //
            // 震动留在同步路径上：`HapticFeedback` 只是往 `UIImpactFeedbackGenerator` 递一下，
            // 不碰音频会话，也不做 IO。
            if mode.vibrates { HapticFeedback.play(.tick) }

            // 🔴 **提示音与播报必须让出这一拍。** 上面那行 `isInviteSheetPresented = true`
            // 已经把 spring 起跑了，而这两样都是**同步占住主线程**的重活：
            // `VolunteerInviteCue` 首次要合成 WAV、写盘、`AudioServicesCreateSystemSoundID`；
            // `speak` 要激活音频会话。跟动画挤在同一拍里，掉的就是卡片升起的头几帧
            // —— 表现是「弹出来一顿一顿的」，而没有任何东西会报错。
            //
            // 挪到下一个 runloop：动画的第一帧先画出去，声音晚十几毫秒没人听得出来。
            var vocalization: (() -> Void)?
            if mode.makesSound {
                vocalization = { [weak self] in
                    // 三条通道各说一遍同一件事 —— 震动对听觉被占用的人、
                    // 提示音对没看屏幕的人、播报对读屏用户。
                    VolunteerInviteCue.play()
                    self?.speechService?.speak("新的陪跑邀请，请在\(remaining)秒内回复")
                }
            } else if mode.showsBanner {
                vocalization = { [weak self] in
                    // 走 `announce` 而不是 `speak`：`announce` 在 VoiceOver 关着时是 no-op，
                    // 正好满足「无声音」；开着时读屏用户仍然知道头顶多了一条东西
                    // —— SwiftUI 不会为凭空出现的 overlay 自己发通告。
                    self?.speechService?.announce(VolunteerInviteCopy.bannerTitle)
                }
            }
            if let vocalization {
                DispatchQueue.main.async(execute: vocalization)
            }
        }
        startInviteTicker()
        loadInviteSupplements()
    }

    /// 去 `GET /api/orders/available` 给队列里还缺三项的邀请补上视力 / 引导方式 / 跑多久。
    ///
    /// 🚩 **补不到就那一行不渲染，不占位、不编、不报错。** 后端有两种合法的空数组
    /// （志愿者还没上报过位置、资质未通过审核），而这一条对志愿者是纯增益 ——
    /// 为它弹一句错误提示只会盖住正在走的回复窗口。
    ///
    /// 已经在飞的那条不重开：一条派单进来时队列里往往还有别的，它们要的是同一份列表。
    private func loadInviteSupplements() {
        guard inviteSupplementTask == nil,
              invites.contains(where: { $0.supplement == nil }),
              let appState else { return }
        inviteSupplementTask = Task { [weak self] in
            let orders = try? await appState.orders.availableOrders()
            guard let self else { return }
            // **先清再判**：清晚了的话一次取消就把这条路永久堵死，
            // 而症状只是「跑者那一行再也不出现」—— 没有任何东西会报警。
            self.inviteSupplementTask = nil
            guard !Task.isCancelled, let orders else { return }
            // 🚩 补上来的是跑者那一行（视力 / 引导方式 / 跑多久），它一落地卡片就长高一截。
            // 这条请求常常正好在弹卡的 spring 还没走完时回来，于是卡片在升起途中「跳」一下。
            // **过渡动画挂在视图那一侧**（`VolunteerInviteSheet.cardContent` 上的
            // `.animation(…, value: hasRunnerSupplement)`）—— 它才拿得到
            // `accessibilityReduceMotion`，view model 里写 `withAnimation` 会绕过那道降级。
            self.invites = VolunteerInviteState.merge(orders, into: self.invites)
        }
    }

    private func markInvite(orderID: Int64, outcome: VolunteerInviteState.Outcome) {
        guard let index = invites.firstIndex(where: { $0.id == orderID }) else { return }
        invites[index].outcome = outcome
        currentInviteID = orderID
    }

    /// 从队列移走一条。
    ///
    /// 🔴 **同时把协调器那一份也清掉，这一行不能挪到调用方。** `syncInvites` 是「只增不减」的
    /// （结果卡要留在屏幕上，而协调器一出结果就把它移走了），所以只删本地的话，
    /// **下一条推送到达时它会被重新灌回来** —— 表现是已经回复过 / 已经收掉的邀请又弹出来。
    /// 收成一处是因为调用点有五个（回复成功、结果卡收起、去不了、过期、登出），
    /// 而「忘了清协调器」在任何一处都是同一个 bug。
    private func removeInvite(orderID: Int64) {
        appState?.realtimeCoordinator.clearDispatch(orderID: orderID)
        invites.removeAll { $0.id == orderID }
        if currentInviteID == orderID { currentInviteID = invites.first?.id }
        // 横幅指的就是这一条时一起收掉 —— 留着的话它会在这条邀请已经过期 / 已经回复之后
        // 继续挂 4 秒，点「查看」弹出的是一张别人的卡。
        if bannerInvite?.id == orderID { bannerInvite = nil }
        if invites.isEmpty {
            isInviteSheetPresented = false
            countdownTask?.cancel()
            countdownTask = nil
        }
    }

    /// 用户在结果卡上点「知道了 / 回到接单」：把这一条收掉，自动翻到下一条；
    /// 全部回复完就收起整张 sheet（§4.4.2「回复一个后自动切到下一个，全部回复完自动收起」）。
    func dismissInvite(orderID: Int64) {
        removeInvite(orderID: orderID)
    }

    /// 结果卡上的「查看订单」。**这是接下之后唯一进订单页的路**（不再自动 push）。
    func openAcceptedOrder(orderID: Int64) {
        removeInvite(orderID: orderID)
        acceptedDispatchOrderId = orderID
    }

    /// 一条 ticker 刷整队。归零那一刻**不发 `DECLINE`** ——
    /// 后端 `app.dispatch.per-volunteer-timeout-seconds` 到点自己 `dispatchToNext`
    /// （`DispatchScheduler.java:140-143`），客户端再发一条只会撞上「这一单已经不归他了」的 409，
    /// 而那个错误既没法处理也不该弹给用户。
    private func startInviteTicker() {
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.tickInvites() else { return }
            }
        }
    }

    /// 返回「还要不要继续跑 ticker」。
    private func tickInvites() -> Bool {
        guard !invites.isEmpty else {
            countdownTask = nil
            return false
        }
        for index in invites.indices where invites[index].isAwaitingReply {
            invites[index].remainingSeconds = max(0, Int(ceil(invites[index].expiresAt.timeIntervalSinceNow)))
            if invites[index].remainingSeconds == 0 {
                invites[index].outcome = .expired
            }
        }
        // 正在看的那一条过期了就留在原地变「已失效」（§4.4.3 最后一行）；
        // 其余过期的静默移除 —— 给一张他从没看过的卡再弹一次「已失效」是纯噪音。
        let staleIDs = invites
            .filter { $0.outcome == .expired && $0.id != currentInviteID }
            .map(\.id)
        for id in staleIDs { removeInvite(orderID: id) }
        // 队列里只剩结果卡（已约好 / 已失效）时也停：它们没有任何还在走的数字，
        // 而用户可能就把那张卡开着不动。让一条每秒醒一次的任务在那儿空转是白烧电。
        if invites.allSatisfy({ !$0.isAwaitingReply }) {
            countdownTask = nil
            return false
        }
        return true
    }

    // MARK: 这次去不了（5 秒撤销窗口）

    /// §4.4.3：卡片立刻收起、底部 toast 给 5 秒撤销，**到点才真的发 `DECLINE`**。
    ///
    /// 🔴 **只能这么做。** 后端 `POST /{id}/respond` 只有三个 action，`handleDecline` 一进去就
    /// `dispatchToNext`（`DispatchService.java:602-623`），**没有任何撤销入口**。
    /// 先发再撤是撤不回来的，所以「撤销」只能实现成「还没发」。
    ///
    /// 代价写在这里：这一单的拒绝晚 5 秒到后端，正在等的跑者多等 5 秒；用户在 5 秒内杀掉 App
    /// 则这条 `DECLINE` 不会发出 —— 但后端 30 秒超时会兜住，结局一样。
    func declineInvite(orderID: Int64) {
        guard let invite = invites.first(where: { $0.id == orderID }) else { return }
        // 上一条还在窗口里就先把它落地，不然两条会互相顶掉。
        flushPendingDecline()
        removeInvite(orderID: orderID)
        pendingDecline = invite
        // 卡片收起那一刻屏幕上只剩一条 toast，而看不见屏幕的人需要知道两件事：
        // 回复出去了、还能反悔。秒数取配置值，不写字面量 —— 两处各写一个 5 必然分叉。
        speechService?.speak("\(VolunteerInviteCopy.declineToastText)，\(Int(declineUndoWindow))秒内可以撤销")
        pendingDeclineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, self?.declineUndoWindow ?? 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flushPendingDecline()
        }
    }

    /// toast 上的「撤销」：请求还没发，把这条邀请放回队列。
    func undoPendingDecline() {
        pendingDeclineTask?.cancel()
        pendingDeclineTask = nil
        guard let invite = pendingDecline else { return }
        pendingDecline = nil
        // 撤销窗口里倒计时**没有停**，所以放回去的可能已经是一张过期卡。
        // 那就让它以「已失效」出现 —— 假装它还能接才是骗人。
        let remaining = max(0, Int(ceil(invite.expiresAt.timeIntervalSinceNow)))
        var restored = invite
        restored.remainingSeconds = remaining
        restored.outcome = remaining == 0 ? .expired : nil
        invites.append(restored)
        invites.sort { $0.expiresAt < $1.expiresAt }
        currentInviteID = restored.id
        isInviteSheetPresented = true
        startInviteTicker()
        // 撤销窗口里倒计时没停，所以「放回来了」和「放回来但已经过期了」是两句不同的话。
        // 只说「已撤销」而屏幕上是一张灰卡，对看不见屏幕的人就是一次白跑。
        speechService?.speak(
            restored.outcome == .expired
                ? "已撤销，不过这个邀请已经过期了"
                : "已撤销，邀请回来了"
        )
    }

    /// 窗口到点（或被下一次「去不了」挤掉）：真的把 `DECLINE` 发出去。
    private func flushPendingDecline() {
        pendingDeclineTask?.cancel()
        pendingDeclineTask = nil
        guard let invite = pendingDecline else { return }
        pendingDecline = nil
        declineStreak.recordDecline()
        objectWillChange.send()
        guard let appState else { return }
        appState.realtimeCoordinator.clearDispatch(orderID: invite.id)
        Task {
            // 失败**不弹给用户**：他已经表达完意图、卡片早就收起了，而后端超时会兜住同一个结果。
            // 这一刻弹「操作失败」只会让他以为自己还得再点一次。
            try? await appState.orders.respond(orderId: invite.id, action: .decline)
        }
    }

    /// 通话磨合结束（成单 / 换人 / 超时）后把入口收掉。
    ///
    /// ⚠️ **不清 `autoOpenedIntroCallOrderId`。** 用户手动返回也走这里，
    /// 清了的话下一次 `dispatch-summary` 刷新会把他重新推回通话页 —— 见那个字段的注释。
    /// 那个记号跟着 orderId 走，换一单自然失效。
    func clearIntroCall() {
        pendingIntroCallOrder = nil
    }

    private func refreshAfterDispatchResponse(
        acceptedOrderId: Int64?,
        appState: AppState
    ) async -> OrderDetailResponse? {
        var acceptedOrder: OrderDetailResponse?

        // 两处 `try?` 是**迁移前就有的**，这里原样保留：这一步跑在「已经响应成功」之后，
        // 播报与导航都不依赖它，拿不到只是首页少刷一次，5 秒后的下一轮会补上。
        if let acceptedOrderId {
            acceptedOrder = try? await appState.orders.orderDetail(orderId: acceptedOrderId)
            activeOrder = acceptedOrder
        }

        if let summary = try? await appState.orders.dispatchSummary() {
            apply(summary: summary)
        }

        if let acceptedOrder {
            activeOrder = acceptedOrder
        }

        return acceptedOrder
    }

    private func subscribeToRealtimeCoordinator(_ appState: AppState) {
        guard realtimeDispatchCancellable == nil else { return }
        realtimeDispatchCancellable = appState.realtimeCoordinator.$pendingDispatches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prompts in
                self?.syncInvites(with: prompts)
            }
        realtimeRecoveryCancellable = appState.realtimeCoordinator.recoveryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                guard signal.role == .volunteer else { return }
                self?.recoverDispatchReadinessAfterReconnect()
            }
        realtimeStatusCancellable = appState.realtimeCoordinator.statusUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      let current = self.activeOrder,
                      current.orderId == update.orderId else { return }
                let updated = current.replacingStatus(with: update.toStatus)
                if updated.status.isActiveForVolunteer {
                    self.activeOrder = updated
                    self.appState?.liveEscortCoordinator.updateOwnedOrder(
                        orderID: updated.orderId,
                        status: updated.status
                    )
                } else {
                    self.activeOrder = nil
                    self.appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
                    self.appState?.liveEscortCoordinator.clearOwnedOrder()
                }
                self.speechService?.speakStatusChange(updated.status)
                self.dispatchSummaryErrorMessage = nil
                if let summary = self.dispatchSummary {
                    self.dispatchLoadState = .loaded(summary)
                }
            }
    }

    func load(currentLocation: CLLocationCoordinate2D?, locationAuthorized: Bool) async {
        guard let appState else { return }
        if let activeLoadTask {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-home-refresh")
            await activeLoadTask.value
            return
        }
        ClientFlowDiagnostics.record(event: "started", operation: "volunteer-home-refresh")
        let requestID = UUID()
        activeRequestID = requestID
        refreshPhase = .refreshing(requestID: requestID)
        if dispatchSummary == nil {
            dispatchLoadState = .loading(requestID: requestID)
        }
        errorMessage = nil
        dispatchSummaryErrorMessage = nil
        needsCertificateUpload = false

        let workTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            await self.performInitialLoad(
                appState: appState,
                requestID: requestID,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized
            )
        }
        activeLoadTask = workTask

        await withTaskCancellationHandler {
            await workTask.value
        } onCancel: {
            workTask.cancel()
            Task { @MainActor [weak self] in
                self?.cancelRequestIfCurrent(requestID)
            }
        }

        guard activeRequestID == requestID else { return }
        activeLoadTask = nil
        activeRequestID = nil
        refreshPhase = .idle
        ClientFlowDiagnostics.record(event: "finished", operation: "volunteer-home-refresh")
        if dispatchLoadState.isLoading {
            if let dispatchSummary {
                dispatchLoadState = .loaded(dispatchSummary)
            } else {
                dispatchLoadState = .failed(message: "派单状态加载失败，请重试。")
            }
        }
    }

    func cancelLoading() {
        activeLoadTask?.cancel()
        auxiliaryLoadTask?.cancel()
        activeLoadTask = nil
        auxiliaryLoadTask = nil
        auxiliaryRequestID = nil
        activeRequestID = nil
        refreshPhase = .idle
        if dispatchLoadState.isLoading {
            if let dispatchSummary {
                dispatchLoadState = .loaded(dispatchSummary)
            } else {
                dispatchLoadState = .idle
            }
        }
    }

    private func performInitialLoad(
        appState: AppState,
        requestID: UUID,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async {
        let didReportLocation = reportVolunteerLocation(appState, currentLocation, locationAuthorized)
        updateLocationDispatchWarning(didReportLocation: didReportLocation, appState: appState)

        do {
            let orders = appState.orders
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-initial"
            ) {
                try await orders.dispatchSummary()
            }
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            apply(summary: summary)
            dispatchLoadState = .loaded(summary)
            dispatchSummaryErrorMessage = nil
        } catch HomeLoadCoordinatorError.timedOut {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            let message = "加载超过 20 秒，请重试。"
            dispatchSummaryErrorMessage = message
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: message)
            speechService?.speakError(message)
        } catch let apiError as APIError {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            if appState.handleAuthenticatedAPIError(apiError) { return }
            dispatchSummaryErrorMessage = apiError.localizedMessage
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: apiError.localizedMessage)
            speechService?.speakError(apiError.localizedMessage)
        } catch is CancellationError {
            return
        } catch {
            guard activeRequestID == requestID, !Task.isCancelled else { return }
            let message = "派单状态加载失败，请重试。"
            dispatchSummaryErrorMessage = message
            dispatchLoadState = dispatchSummary.map(AsyncLoadState.loaded) ?? .failed(message: message)
            speechService?.speakError(message)
        }

        guard activeRequestID == requestID, !Task.isCancelled else { return }
        startAuxiliaryLoad(appState: appState)
    }

    private func startAuxiliaryLoad(appState: AppState) {
        auxiliaryLoadTask?.cancel()
        let requestID = UUID()
        auxiliaryRequestID = requestID
        // 这两条是**档案·资质片**的端点（`ProfileServing.volunteerProfile` /
        // `.volunteerRegistrationStatus`），不在订单片里再开一条同路径 ——
        // 同一个端点两处字面量迟早漂移。
        //
        // 它们原先暂放在 `AuthServing` 上（订单片就是照那个写的），档案片落 main 时
        // 搬回了自己家。两片并行开发看不见对方的搬迁，这里跟着改指向。
        let profile = appState.profile
        auxiliaryLoadTask = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            async let profileResult: Result<VolunteerProfileResponse, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-profile"
                ) {
                    try await profile.volunteerProfile()
                }
            }
            async let registrationResult: Result<VolunteerRegistrationStatus, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-registration"
                ) {
                    try await profile.volunteerRegistrationStatus()
                }
            }

            // 「接下来要去的单」两条（后端 `dispatch-summary` 两态都拿不到，
            // 见 `OrderServing.volunteerOrders(status:)` 的注释）。一次只能问一个状态，
            // 所以是两条请求而不是一条带两个值的。
            //
            // 与档案那两条**并行**，也彼此并行，不串在后面 —— 首页已经有三次往返，
            // 每多排一条就让面板多等一个 RTT。
            let orders = appState.orders
            async let scheduledResult: Result<PagedOrderResponse, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-scheduled-orders"
                ) {
                    try await orders.volunteerOrders(status: .scheduledConfirmed)
                }
            }
            // 🔴 **`PENDING_ACCEPT` 这一条是 2026-09-18 补的，它此前是个黑洞。**
            // 陪跑员谈成之后点「确认我还会去」，订单 `SCHEDULED_CONFIRMED → PENDING_ACCEPT`，
            // 而那一态**两个数据源都不含它**：预约列表按 `SCHEDULED_CONFIRMED` 拉，
            // `dispatch-summary.activeOrders` 的后端白名单也没有它。
            // 真机表现是「刚接下的那一单，一退出订单页就从自己的 App 里消失了」。
            async let pendingAcceptResult: Result<PagedOrderResponse, Error> = Self.fetchResult {
                try await HomeLoadCoordinator.run(
                    timeout: self.loadTimeout,
                    operationName: "volunteer-pending-accept-orders"
                ) {
                    try await orders.volunteerOrders(status: .pendingAccept)
                }
            }

            let (profile, registration, scheduled, pendingAccept) = await (
                profileResult, registrationResult, scheduledResult, pendingAcceptResult
            )
            guard !Task.isCancelled, self.auxiliaryRequestID == requestID else { return }
            if case .success(let value) = profile {
                appState.updateVolunteerProfile(value)
                self.apply(profile: value)
            }
            if case .success(let value) = registration {
                appState.updateVolunteerRegistrationStatus(value)
            }
            self.applyUpcoming(scheduled: scheduled, pendingAccept: pendingAccept)
            // 三岔路的另一岔（2 小时内开始的陪跑）只有等这条请求回来才判得了 —— 跨天预约单
            // 不在 `dispatch-summary` 里。判完这一轮就关窗，之后每 10 秒的刷新不再自动导航。
            self.resolveLaunchRouteIfNeeded()
            self.didResolveLaunchRoute = true
            self.auxiliaryLoadTask = nil
            self.auxiliaryRequestID = nil
        }
    }

    /// 客户端这一侧认哪几个状态算「接下来要去的单」。
    ///
    /// 🚩 **两态都要，缺一个就是一个黑洞。** `SCHEDULED_CONFIRMED` 是还没临期确认的跨天单，
    /// `PENDING_ACCEPT` 是确认完、等着按「我出发了」的那一单 —— 后者此前两个数据源都取不到。
    ///
    /// ⚠️ 这里**不是**「志愿者眼里的活跃订单」那个更宽的白名单
    /// （`RunOrderStatus.isActiveForVolunteer`，含 `DRIVER_EN_ROUTE` 等三态）：
    /// 那三态由后端 `dispatch-summary.activeOrders` 承担，两边重复取会让同一单
    /// 既出现在深蓝卡又出现在「之后还有 N 次」里。
    static let upcomingVolunteerStatuses: Set<RunOrderStatus> = [.scheduledConfirmed, .pendingAccept]

    /// 两条请求的结果合并后落进 `scheduledOrders`。
    ///
    /// 🚨 **失败时不清空已有列表**：预约区块上挂着一个 60 分钟到期的确认动作，
    /// 一次网络抖动把整块抹掉，志愿者就会以为那张单已经没了、不必再管它 ——
    /// 而后端那边计时照走。失败只留一句说明，列表保持上一次的内容。
    ///
    /// 🚩 **两条都失败才算失败。** 一条回来了就按回来的那部分渲染 —— 半份列表
    /// 也比「暂时没有约好的陪跑」诚实，后者是一句**关于事实的断言**。
    ///
    /// ⚠️ 服务端返回的顺序是 `createdAt` 倒序（`OrderController.getMyOrders` 写死的），
    /// 这里按 `plannedStart` 重排成升序：这一块回答的是「下一件事什么时候」，
    /// 不是「我什么时候接的单」。缺 `plannedStart` 的排最后而不是丢掉。
    private func applyUpcoming(
        scheduled: Result<PagedOrderResponse, Error>,
        pendingAccept: Result<PagedOrderResponse, Error>
    ) {
        let pages = [scheduled, pendingAccept].compactMap { try? $0.get() }
        if !pages.isEmpty {
            // 同一单**不可能**同时出现在两条响应里（一个订单只有一个状态），
            // 但按 orderId 去一次重是防后端某天放宽 status 语义时悄悄出现两张卡。
            var seen = Set<Int64>()
            scheduledOrders = pages
                .flatMap(\.content)
                .filter { Self.upcomingVolunteerStatuses.contains($0.status) && seen.insert($0.orderId).inserted }
                .sorted { ($0.plannedStart ?? "\u{FFFF}") < ($1.plannedStart ?? "\u{FFFF}") }
        }
        switch (scheduled, pendingAccept) {
        case (.success, _), (_, .success):
            scheduledOrdersMessage = nil
        case (.failure, .failure):
            ClientFlowDiagnostics.record(event: "failed", operation: "volunteer-scheduled-orders")
            // 🚨 **列表空时也要说话。** 早先这里是 `guard !scheduledOrders.isEmpty else { return }`，
            // 于是首次加载失败时既不渲染区块、也不设提示 —— 志愿者看到的与「我没有预约单」
            // 一模一样，而他可能正有一张单在倒计时。判据是「这个失败态下屏幕上会**多**出什么」，
            // 当时的答案是「什么都不多」，那就是静默失败。
            scheduledOrdersMessage = scheduledOrders.isEmpty
                ? "预约列表没能加载，如果你有还没到时间的预约，请下拉刷新再看一次。"
                : "预约列表没能刷新，显示的是上一次的内容。"
        }
    }

    nonisolated private static func fetchResult<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }

    /// 临期确认「我还会去」（`SCHEDULED_CONFIRMED → PENDING_ACCEPT`）。
    ///
    /// 🚩 **成功后必须把他带进服务页，不能只把卡片移除。**
    /// 确认之后订单是 `PENDING_ACCEPT`，而那一态**既不在预约列表里**（这个列表按
    /// `status=SCHEDULED_CONFIRMED` 拉）、**也不在「当前订单」里**（后端
    /// `VolunteerService.loadActiveOrders` 的白名单只有陪跑中那三态）⇒ 只移除卡片的话，
    /// 他刚确认完就在首页上再也找不到这一单，而下一步「我已出发」要靠他自己翻回去。
    ///
    /// 复用派单接单后那条既有的导航（`acceptedDispatchOrderId` + `navigationDestination`），
    /// 不另起一套：两者要去的是同一个页面、同一个状态。
    func confirmScheduledDeparture(orderID: Int64) async {
        let order = scheduledOrders.first { $0.orderId == orderID }
        let confirmed = await submitScheduled(
            orderID: orderID,
            successSpeech: "已确认，到时间请按约定前往。"
        ) { orders in
            try await orders.confirmDeparture(orderId: orderID)
        }
        guard confirmed else { return }
        // 带上手里这份详情当初值，服务页就不必空着等第一次 GET 回来。
        acceptedDispatchInitialOrder = order?.replacingStatus(with: .pendingAccept)
        acceptedDispatchOrderId = orderID
    }

    /// 「我去不了」（走取消端点，订单转 `REMATCHING` 回到派单池）。
    ///
    /// 与确认共用同一条提交路径，**刻意不做得更难** —— 释放做得难只会把 no-show 从
    /// 「提前告知」变成「当天失联」，那对盲人差得多（`docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二.1）。
    /// 二次确认在 View 上（`confirmationDialog`），因为它不可逆：抢不回同一个盲人。
    func releaseScheduledOrder(orderID: Int64) async {
        // 🚩 **不说「会转给其他志愿者」**：后端 `enterRematching` 在重匹次数达上限时是直接
        // 置 `CANCELLED` 而不是重派（`OrderLifecycleService`），那时这句话就是假的。
        // 只说他自己那一半 —— 那一半永远为真。
        _ = await submitScheduled(orderID: orderID, successSpeech: "已经告诉系统你去不了，这一单不在你名下了。") { orders in
            try await orders.cancel(orderId: orderID)
        }
    }

    /// 两个动作共用的提交路径。返回**这次提交是不是真的成功了**（调用方据此决定要不要导航）。
    ///
    /// 成功与 409 都从列表移除：两种情况下这一单都不再是「待你确认的预约」。
    private func submitScheduled(
        orderID: Int64,
        successSpeech: String,
        operation: @escaping (any OrderServing) async throws -> Void
    ) async -> Bool {
        guard submittingScheduledOrderID == nil, let appState else { return false }
        submittingScheduledOrderID = orderID
        scheduledOrdersMessage = nil
        defer { submittingScheduledOrderID = nil }
        do {
            try await operation(appState.orders)
            scheduledOrders.removeAll { $0.orderId == orderID }
            speechService?.speak(successSpeech)
            return true
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return false }
            // 409 `ORDER_STATUS_NOT_ALLOWED`：订单已经不在 `SCHEDULED_CONFIRMED` 上了。
            //
            // 🚨 **不许断言是哪一种。** 至少三种成因，客户端一个都分不出：
            // 闸门已经把它退回重新匹配、盲人取消了、以及**上一次其实已经提交成功**
            // （请求到了服务端、响应在回来的路上丢了，用户以为没成功又点了一次）。
            // 早先这里写死「这一单已经转给其他志愿者了」——在第三种情况下那是句假话，
            // 而且紧跟着把卡片删掉，他从此在首页上再也看不到一张仍在自己名下的单。
            // 现在这句话对三种成因**都为真**，且给出的下一步（不用再确认）也都对。
            if case .serverError(let response) = error, response.errorCode == .invalidOrderStatus {
                scheduledOrders.removeAll { $0.orderId == orderID }
                let message = "这一单的状态已经变了，不用再确认。可以到「近期服务」里看它现在怎么样。"
                scheduledOrdersMessage = message
                speechService?.speakError(message)
                return false
            }
            scheduledOrdersMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return false
        } catch {
            let message = "操作没有成功，请重试。"
            scheduledOrdersMessage = message
            speechService?.speakError(message)
            return false
        }
    }

    private func cancelRequestIfCurrent(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        cancelLoading()
    }

    func setAvailability(_ value: Bool) {
        guard !isUpdatingAvailability, let appState else { return }

        let previousValue = isAvailable
        isAvailable = value
        Task {
            await updateAvailability(value, previousValue: previousValue, appState: appState)
        }
    }

    private func updateAvailability(_ value: Bool, previousValue: Bool, appState: AppState) async {
        isUpdatingAvailability = true
        errorMessage = nil

        do {
            try await appState.orders.setDispatchStatus(wantsDispatch: value)
            let existingProfile = appState.volunteerProfile
                let profile = VolunteerProfileResponse(
                    name: existingProfile?.name,
                    verificationStatus: existingProfile?.verificationStatus,
                    adminReviewStatus: existingProfile?.adminReviewStatus,
                    registrationStep: existingProfile?.registrationStep,
                    canAcceptOrders: existingProfile?.canAcceptOrders,
                    isAvailable: value,
                    wantsDispatch: value,
                    availableTimeSlots: existingProfile?.availableTimeSlots,
                acceptsGuideDog: existingProfile?.acceptsGuideDog,
                paceRange: existingProfile?.paceRange
            )
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                isUpdatingAvailability = false
                return
            }
            // `try?` 是迁移前就有的：开关本身已经切成功并播报过了，这一步只是把摘要刷新一下，
            // 拿不到不改变「已上线 / 已下线」这个既成事实。
            if let summary = try? await appState.orders.dispatchSummary() {
                apply(summary: summary)
            }
            isUpdatingAvailability = false
        } catch let error as APIError {
            isAvailable = previousValue
            isUpdatingAvailability = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = "可服务状态更新失败，请重试"
            speechService?.speakError("可服务状态更新失败，请重试")
        }
    }

    private func apply(profile: VolunteerProfileResponse?) {
        guard let profile else { return }
        nickname = profile.name ?? ""
        isAvailable = profile.isAvailable ?? false
    }

    /// 摘要的唯一漏斗 —— 冷启动首屏、下拉刷新、接单后回读全从这里过，
    /// 所以 `recoverIntroCallIfNeeded` 挂在这里就够，不必在每个调用点各接一次。
    ///
    /// 非 private 是为了让单测能直接喂一份摘要进来：起真实的加载流程会顺带打三四个端点、
    /// 动状态机，把「摘要里有 introCallOrderId 会怎样」这一条断言埋进一堆无关请求里。
    func apply(
        summary: VolunteerDispatchSummaryResponse,
        statusRequestToken: OrderStatusRequestToken? = nil
    ) {
        let previousOrderID = activeOrder?.orderId
        dispatchSummary = summary
        isAvailable = summary.wantsDispatch ?? isAvailable
        if let active = summary.activeOrders?.first {
            let candidate = active.orderDetail
            if let statusRequestToken,
               statusRequestToken.orderID == candidate.orderId {
                activeOrder = appState?.realtimeCoordinator.reconcileOrderDetail(
                    candidate,
                    requestToken: statusRequestToken
                )
            } else {
                activeOrder = candidate
                appState?.realtimeCoordinator.registerActiveOrder(
                    candidate.orderId,
                    status: candidate.status
                )
            }
        } else if let statusRequestToken,
                  appState?.realtimeCoordinator.isOrderStatusRequestCurrent(statusRequestToken) == false {
            ClientFlowDiagnostics.record(
                event: "late_empty_discarded",
                operation: "volunteer-summary-refresh"
            )
        } else {
            activeOrder = nil
        }
        if let previousOrderID, previousOrderID != activeOrder?.orderId {
            appState?.realtimeCoordinator.unregisterActiveOrder(previousOrderID)
        }
        if let activeOrder {
            appState?.liveEscortCoordinator.updateOwnedOrder(
                orderID: activeOrder.orderId,
                status: activeOrder.status
            )
        } else {
            appState?.liveEscortCoordinator.clearOwnedOrder()
        }
        recoverIntroCallIfNeeded(summary: summary)
        // 三岔路的「有进行中订单」那一岔在这里就判得了，不必等预约单那条请求回来。
        // 另一岔（2 小时内开始的陪跑）在 `startAuxiliaryLoad` 的收尾里。
        resolveLaunchRouteIfNeeded()
    }

    /// 冷启动恢复：App 被杀之后回到那一通没打完的电话。
    ///
    /// 🚨 **这不是「顺手多接一个字段」，它补的是一个真实的失联**：通话磨合态
    /// `order.volunteer` 还是 null ⇒ `GET /api/orders/{id}` 恒 403、`/api/orders/mine` 也不返回，
    /// 而派单推送不会重放 —— 志愿者重开 App 之后**没有任何入口**回到通话页，
    /// 只能等 20 分钟窗口超时，而盲人在等他这通电话。
    /// `introCallOrderId` 是那一刻唯一的线索（后端为此专门加的字段）。
    ///
    /// 三道闸缺一不可：
    /// 1. `introCallOrderId` 非空 —— 绝大多数时候它是 null。
    /// 2. `pendingIntroCallOrder == nil` —— 已经在通话页上了就别再动导航。
    /// 3. `autoOpenedIntroCallOrderId != id` —— **同一单只自动跳一次**。
    ///    没有第 3 条，用户手动返回后每次摘要刷新都会把他拽回去，20 分钟内出不来。
    ///
    /// `dispatchOrder` 传 nil：那条推送早随进程一起没了，客户端拿不回来，也不许编。
    private func recoverIntroCallIfNeeded(summary: VolunteerDispatchSummaryResponse) {
        guard let introCallOrderId = summary.introCallOrderId,
              pendingIntroCallOrder == nil,
              autoOpenedIntroCallOrderId != introCallOrderId else { return }
        autoOpenedIntroCallOrderId = introCallOrderId
        pendingIntroCallOrder = VolunteerIntroCallRoute(orderId: introCallOrderId)
    }

    /// 冷启动三岔路（设计交付 v3 §4.1）：有进行中订单或 2 小时内开始的陪跑就直接进订单页。
    ///
    /// 调用点有两个，都在**首次加载**这一轮上：`apply(summary:)` 末尾（在途订单那一岔，
    /// 不必等预约单那条请求回来）、`applyUpcoming(scheduled:pendingAccept:)` 之后（预约单那一岔）。
    /// 窗口由 `didResolveLaunchRoute` 关上 —— 见它的注释，那不是优化。
    ///
    /// 🚩 **复用派单接单后那条既有导航**（`acceptedDispatchOrderId` + 首页 tab 的
    /// `navigationDestination`），不另起一条路由：要去的是同一个页面。
    /// `confirmScheduledDeparture` 也是这么做的。
    ///
    /// 🚩 通话磨合让路：`pendingIntroCallOrder` 在场时一律不动。那一态有 20 分钟窗口、
    /// 对面有人在等电话，而订单页随时可以再进（`navigationDestination` 里的顺序也是这个优先级）。
    ///
    /// 🚩 **邀请卡的结果卡同样让路，理由一模一样。** 刚接下那一刻屏幕上是「已约好」，
    /// 而它是唯一一处告诉陪跑员「跑者的全名和电话已经放进订单」的地方（设计交付 v3 §4.4.3）。
    /// 这一岔会在**首次加载还没跑完时收到派单**的情况下真的撞上：首次加载的窗口还开着，
    /// 而接单后的 `refreshAfterDispatchResponse` 会再走一遍 `apply(summary:)` ——
    /// 于是这条路由把那张确认卡一闪而过。由
    /// `testAcceptingDispatchShowsTheBookedCardAndOnlyNavigatesOnTap` 红出来。
    private func resolveLaunchRouteIfNeeded() {
        guard !didResolveLaunchRoute,
              pendingIntroCallOrder == nil,
              acceptedDispatchOrderId == nil,
              invites.allSatisfy(\.isAwaitingReply),
              let order = Self.launchOrderToOpen(
                  activeOrder: activeOrder,
                  scheduledOrders: scheduledOrders
              ) else { return }
        didResolveLaunchRoute = true
        // 带上手里这份详情当初值，订单页就不必空着等第一次 GET 回来。
        acceptedDispatchInitialOrder = order
        acceptedDispatchOrderId = order.orderId
    }

    func refreshDispatchSummary() async {
        guard let appState else { return }
        if let activeLoadTask {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-summary-refresh")
            await activeLoadTask.value
            return
        }
        if let summaryRefreshTask {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "volunteer-summary-refresh")
            await summaryRefreshTask.value
            return
        }

        let refreshID = UUID()
        summaryRefreshID = refreshID
        ClientFlowDiagnostics.record(event: "started", operation: "volunteer-summary-refresh")
        refreshPhase = .refreshing(requestID: refreshID)
        let task = Task { [weak self, weak appState] in
            guard let self, let appState else { return }
            await self.performDispatchSummaryRefresh(appState: appState, refreshID: refreshID)
        }
        summaryRefreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if summaryRefreshID == refreshID {
            summaryRefreshTask = nil
            summaryRefreshID = nil
            refreshPhase = .idle
            ClientFlowDiagnostics.record(event: "finished", operation: "volunteer-summary-refresh")
        }
    }

    private func performDispatchSummaryRefresh(appState: AppState, refreshID: UUID) async {
        do {
            let orders = appState.orders
            let statusRequestToken = activeOrder.map {
                appState.realtimeCoordinator.beginOrderStatusRequest(orderID: $0.orderId)
            }
            let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                timeout: loadTimeout,
                operationName: "volunteer-dispatch-refresh"
            ) {
                try await orders.dispatchSummary()
            }
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
            apply(summary: summary, statusRequestToken: statusRequestToken)
            dispatchLoadState = .loaded(summary)
            dispatchSummaryErrorMessage = nil
        } catch HomeLoadCoordinatorError.timedOut {
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
            dispatchSummaryErrorMessage = "派单状态刷新超过 20 秒，请重试"
        } catch let error as APIError {
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            dispatchSummaryErrorMessage = error.localizedMessage
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, summaryRefreshID == refreshID else { return }
            dispatchSummaryErrorMessage = "派单状态刷新失败，请重试"
        }
    }

    func startRefreshLoop() {
        guard isSceneActive, refreshLoopTask == nil else { return }
        refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isSceneActive {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, self.isSceneActive else { return }
                await self.reportLocationThenRefreshSummary(
                    currentLocation: self.currentLocationProvider(),
                    locationAuthorized: self.locationAuthorizedProvider()
                )
            }
        }
    }

    func reportLocationThenRefreshSummary(
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async {
        guard let appState else { return }
        let didReportLocation = reportVolunteerLocation(
            appState,
            currentLocation,
            locationAuthorized
        )
        updateLocationDispatchWarning(
            didReportLocation: didReportLocation,
            appState: appState
        )
        if didReportLocation {
            try? await Task.sleep(nanoseconds: UInt64(dispatchPropagationDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
        }
        await refreshDispatchSummary()
    }

    private func recoverDispatchReadinessAfterReconnect() {
        guard isSceneActive else { return }
        delayedSummaryRefreshTask?.cancel()
        delayedSummaryRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.reportLocationThenRefreshSummary(
                currentLocation: self.currentLocationProvider(),
                locationAuthorized: self.locationAuthorizedProvider()
            )
        }
    }

    private func updateLocationDispatchWarning(
        didReportLocation: Bool,
        appState: AppState
    ) {
        guard appState.currentEnvironment != .mock else {
            consecutiveLocationReportFailures = 0
            locationDispatchWarning = nil
            return
        }
        if didReportLocation {
            consecutiveLocationReportFailures = 0
            locationDispatchWarning = nil
            return
        }
        consecutiveLocationReportFailures += 1
        // 未达阈值的瞬态失败完全静默：横幅不出现（也就不会闪），更不播报。
        guard consecutiveLocationReportFailures >= Self.locationReportFailureThreshold else { return }
        let message = "定位暂不可用，可能无法收到派单"
        let shouldSpeak = locationDispatchWarning != message
        locationDispatchWarning = message
        if shouldSpeak {
            speechService?.speakError(message)
        }
    }
}

// MARK: - Volunteer Home Layout Helpers

/// 志愿者首页这一屏的圆角档位。**四档各有语义，不是四个可以互换的数。**
///
/// 立这个表的起因：全 App 的 `cornerRadius` 实测有 10 个取值
/// （8×46 / 12×36 / 16×17 / 14×11 / 18×4 / 20·28·999×2 / 10·24×1），
/// 而同一屏上派单状态卡是 16、当前订单卡是 20、卡内小格是 12 —— 没有规律可循，
/// 下一个人加卡片时只能随手挑一个，于是取值继续发散。
///
/// ⛔ **作用域刻意只到这一屏。** 跨屏共用的 `IncentiveCard` / `IncentiveHeroCard` /
/// `PartnerRowCard` 都是 14，改它们会波及盲人端的固定搭档页 —— 那不在本次范围内，
/// 且纯视觉收敛没有任何测试守得住，改坏了不会有信号。要全 App 统一是另一件事。
enum VolunteerHomeRadius {
    /// 居中弹出的模态对话框（派单弹窗）。
    static let modal: CGFloat = 24
    /// 内容流里的每一张卡片。
    static let card: CGFloat = 16
    /// 卡片**内部**的元素：小格子、整行按钮、内嵌地图。
    /// 比外层小是为了套着好看，不是另一套体系。
    static let tile: CGFloat = 12
}

// MARK: - Volunteer Home View

/// 志愿者端「首页」tab 的内容。**它本身只剩三件事**：装第一屏、把可服务开关挂在底部、
/// 管这一条 `NavigationStack` 上的三个落点。内容**全部**在 `VolunteerProfileFirstScreen` 里，
/// 志愿者端主屏现在只有这一屏，没有任何二级的「工作台」。
///
/// > 2026-09-14 从「地图铺满 + 底部可拖面板」的叠层结构改成这样。原结构有两个硬伤：
/// > ① 那张底图 `annotations` 恒为 `[]`，只画「我在哪」，却占着整屏；
/// > ② 面板拖到 `.compact` 档时**整块内容不渲染**，志愿者的服务量、勋章、最近陪跑
/// >   随手一拖就全没了。设计稿与依据见
/// >   `docs/ui/mockups/volunteer-profile-first-screen-20260914/`。
/// >
/// > 2026-09-15 又删掉了那一轮引入的二级页 `VolunteerDispatchWorkbenchView`（用户原话
/// > 「好像是没什么用的」）。连带删掉那张辅助地图：它的 `annotations` 仍恒为 `[]`，
/// > 唯一信息「我在哪」在派单卡的覆盖范围文字里已经有一份。**删地图 ≠ 停定位** ——
/// > 那两行现在在 `VolunteerTabView` 上，不许跟着删。
/// >
/// > 2026-09-17 它**不再是志愿者端的根**（设计交付 v3 §4.1 的底部三标签）。
/// > 根是 `VolunteerTabView`，view model 的所有权、生命周期与派单弹窗都在那一层 ——
/// > 搬上去的理由见那个文件，不是为了好看，是 `TabView` 的硬约束。
struct VolunteerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    /// **由 `VolunteerTabView` 注入，不再自己 `@StateObject` 持有。**
    /// 派单弹窗挂在 tab 容器上，而它和这一屏必须读同一份派单状态。
    @ObservedObject var viewModel: VolunteerHomeViewModel
    /// 接单主页（设计交付 v3 的 S3/S4）。滑块向右滑过阈值时置位。
    @State private var showsDispatchHub = false

    var body: some View {
        NavigationStack {
            VolunteerProfileFirstScreen(viewModel: viewModel, onReload: loadHome)
                .navigationTitle("")
                .navigationBarHidden(true)
                // 一个 destination 分三种落点，不是三个 `navigationDestination(isPresented:)` ——
                // 同一个视图上挂多条 `isPresented` 版本在 iOS 16 上会互相顶掉。
                //
                // 🚩 顺序即优先级：通话磨合 > 已接下的单 > 接单主页。前两者是**有时限**的
                // （通话窗口 20 分钟、订单在走），接单主页随时可以再进。
                .navigationDestination(
                    isPresented: Binding(
                        get: {
                            viewModel.acceptedDispatchOrderId != nil
                                || viewModel.pendingIntroCallOrder != nil
                                || showsDispatchHub
                        },
                        set: { isPresented in
                            if !isPresented {
                                viewModel.acceptedDispatchOrderId = nil
                                viewModel.acceptedDispatchInitialOrder = nil
                                viewModel.clearIntroCall()
                                showsDispatchHub = false
                            }
                        }
                    )
                ) {
                    if let introCallRoute = viewModel.pendingIntroCallOrder {
                        VolunteerIntroCallView(route: introCallRoute)
                    } else if let orderId = viewModel.acceptedDispatchOrderId {
                        VolunteerInServiceView(
                            orderId: orderId,
                            initialOrder: viewModel.acceptedDispatchInitialOrder
                        )
                    } else if showsDispatchHub {
                        VolunteerDispatchHubView(viewModel: viewModel, onReload: loadHome)
                    }
                }
                // 🚩 **挂在栈内的根视图上，不是挂在 `NavigationStack` 或 `TabView` 上。**
                // 挂高一层的话 push 出去的接单主页 / 订单页底部也会长出一个滑块，
                // 与那一页自己的「暂停接单」直接打架；而设计交付 v3 §4.2 总表里
                // S3/S4 的主按钮一栏写的就是「无」。
                .safeAreaInset(edge: .bottom) {
                    availabilityCTA
                }
        }
    }

    /// 底部的可服务开关。**它替代了原来那个 `Toggle`** —— 依据是 Uber Base
    /// Sliding button 的用途判据「引入摩擦以确认意图」，而「从这一刻起开始收派单」
    /// 正是一个有后果的动作（`docs/research/volunteer-profile-first-screen-20260914.md` §3）。
    ///
    /// 🚩 **向右滑同时做两件事：开启接单 + 进入接单主页。** 设计交付 v3 的流程就是这一条
    /// （主页 → 滑动 → 接单主页），理由是开启之后志愿者要看的「下一次陪跑 / 待回复的邀请」
    /// 都不在首页上。已经开启时向右滑只做后一件。
    private var availabilityCTA: some View {
        VolunteerAvailabilitySlider(
            isAvailable: viewModel.isAvailable,
            isEnabled: appState.isVolunteerProfileApproved,
            isUpdating: viewModel.isUpdatingAvailability,
            statusText: viewModel.statusText,
            onChange: { viewModel.setAvailability($0) },
            onEnterHub: { showsDispatchHub = true }
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func loadHome() async {
        await viewModel.load(
            currentLocation: locationService.currentLocation,
            locationAuthorized: locationService.isAuthorized
        )
    }
}

struct VolunteerCurrentOrderCard: View {
    let order: OrderDetailResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.title3)
                .foregroundColor(order.status.statusColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("当前订单")
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                    Text(order.status.displayName)
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(order.status.statusColor)
                }

                Text(order.blindName ?? "盲人跑者")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(order.startAddress ?? "")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text((order.plannedStart ?? "").displayDateTime)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Label("进入", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(AppColors.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 5)
    }
}

/// 派单状态卡：覆盖范围 + 完成·评分·接单率 + 派单·接受·拒绝·超时。
///
/// 🚩 **internal 而不是 private**：唯一的渲染点在 `VolunteerProfileFirstScreen.dispatchSection`
/// （另一个文件）。它被刻意摆在首屏**最底部**、接替 2026-09-15 删掉的那行工作台入口 ——
/// 「等待派单」页出来时搬走它 = 删首屏 `VStack` 里的一行 + 整个 struct 挪过去，不用重构。
/// 调研 §1 的三档分类里它是第三档「普通信息卡片」，不该占中段。
///
/// 🔴 **卡里不再有「去培训」按钮。** 那个入口以前是这张卡的兄弟节点，小得用户找不到
/// （原话「一个贼小的去培训，一点都不显眼」），已整体升级成首屏作业区里的整卡入口。
struct VolunteerDispatchSummaryCard: View {
    let summary: VolunteerDispatchSummaryResponse

    /// 三格，不是四格。此前第一格是「积分」，值是 `totalCompleted * 100` ——
    /// 后端从来没有 `pointsBalance` 字段，那个数字只是「完成 N 单」换了个说法，
    /// 却被命名成一种可累积、可兑换的东西。
    ///
    /// ponytail: 删掉后**不补第四格凑数**。`totalDispatched` / `totalDeclined` /
    /// `totalTimeout` 在下面本来就有一行专门展示，挪上来只是重复。
    private var metrics: [(String, String)] {
        [
            ("完成", "\(summary.completedCount)"),
            ("评分", summary.ratingText),
            ("接单率", summary.acceptanceRateText)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.canDispatch == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(summary.canDispatch == true ? AppColors.success : AppColors.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.dispatchStatusText)
                        .font(AppFonts.body().weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary.coverageText)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer(minLength: 0)
            }

            // 列数跟着 `metrics` 走，不写字面量 —— `be4e030` 删掉「积分」那格时列数留在 4，
            // 于是三格挤在左边、右边空一格挂了很久。
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: metrics.count), spacing: 8) {
                ForEach(metrics, id: \.0) { metric in
                    VolunteerMetricTile(title: metric.0, value: metric.1)
                }
            }

            HStack(spacing: 8) {
                Text("派单 \(summary.totalDispatched ?? 0)")
                Text("接受 \(summary.totalAccepted ?? 0)")
                Text("拒绝 \(summary.totalDeclined ?? 0)")
                Text("超时 \(summary.totalTimeout ?? 0)")
            }
            .font(AppFonts.caption())
            .foregroundColor(AppColors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        // 「积分 N」也从这条 label 里删掉 —— 数字从视觉上消失了，但读屏用户还在听，
        // 这一处最容易漏。
        .accessibilityLabel("派单状态：\(summary.dispatchStatusText)，\(summary.coverageText)，完成 \(summary.completedCount) 次，评分 \(summary.ratingText)")
    }
}

/// internal 与 `VolunteerDispatchSummaryCard` 同理：它只被那张卡用，而那张卡已经跨文件了。
struct VolunteerMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile, style: .continuous))
    }
}

/// 首页的「我的预约」区块 —— 跨天预约单（`SCHEDULED_CONFIRMED`）以及它们的临期确认动作。
///
/// **为什么它必须独立于「当前订单」和「近期服务」两块**：
/// - 与「当前订单」共用一个位会被即时单顶掉（见 `VolunteerHomeViewModel.scheduledOrders`）。
/// - 「近期服务」在语义上是历史（空态文案逐字是「完成服务后会显示在这里」），
///   而且只渲染 `prefix(3)`。把一个 60 分钟到期的待办混进历史列表，可发现性接近零。
///
/// 确认按钮直接摆在卡上、**不进二级页也不进溢出菜单** —— Rover 把改期藏进三点菜单、
/// 把接受放在会话线程里，是本轮调研里唯一被点名的反面教材。
struct VolunteerScheduledOrdersSection: View {
    let orders: [OrderDetailResponse]
    let submittingOrderID: Int64?
    let message: String?
    let onConfirm: (Int64) -> Void
    let onRelease: (Int64) -> Void

    /// 要释放的那一单。二次确认是因为释放不可逆 —— 订单回派单池，抢不回同一个盲人。
    @State private var pendingReleaseOrder: OrderDetailResponse?

    var body: some View {
        // `message` 非空时即使没有卡片也要渲染：加载失败而列表恰好为空是最需要说话的一刻，
        // 只按 `orders.isEmpty` 判会让那条提示无处可去（见 `applyUpcoming` 的失败分支）。
        if !orders.isEmpty || message != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("我的预约")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)

                if let message {
                    Text(message)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(message)
                }

                ForEach(orders) { order in
                    card(order)
                }
            }
            .confirmationDialog(
                "确认去不了？",
                isPresented: Binding(
                    get: { pendingReleaseOrder != nil },
                    set: { if !$0 { pendingReleaseOrder = nil } }
                ),
                presenting: pendingReleaseOrder
            ) { order in
                Button("确认去不了", role: .destructive) { onRelease(order.orderId) }
                Button("再想想", role: .cancel) {}
            } message: { _ in
                Text("这一单会转给其他志愿者，之后不一定还能接回来。")
            }
        }
    }

    /// 一张预约卡。整块 `children: .contain` —— 容器上的无障碍设置会向下盖掉子元素，
    /// 而这张卡上的两个按钮必须各自可被读屏聚焦、也必须能被 UI 测试分别找到。
    private func card(_ order: OrderDetailResponse) -> some View {
        let isSubmitting = submittingOrderID == order.orderId
        let anySubmitting = submittingOrderID != nil
        return VStack(alignment: .leading, spacing: 10) {
            // 缺 `plannedStart` 时给一句话而不是空串：这一行是整张卡最重要的内容
            // （「什么时候」就是这一态的全部），空 `Text` 对读屏用户等于这张卡没有时间。
            Text(order.plannedStart?.nilIfBlank?.displayDateTime ?? "开跑时间待同步")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(order.blindName ?? "盲人跑者") · \(order.startAddress ?? "出发地待同步")")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // 竖直堆叠而不是并排：对标产品无一把两个动作并排放
            // （`blind-ui-visual-benchmark-20260808.md`「次级操作一律整行铺满竖直堆叠」），
            // 而且并排会让每个按钮的可点宽度减半，AX5 下文字直接被压成省略号。
            PrimaryButton(
                VolunteerServiceActionKind.confirmDeparture.title,
                isLoading: isSubmitting,
                action: { onConfirm(order.orderId) }
            )
            .disabled(anySubmitting)
            .accessibilityLabel(VolunteerServiceActionKind.confirmDeparture.title)
            .accessibilityHint("告诉跑者你仍然会来。不确认这一单会转给其他志愿者")
            .accessibilityIdentifier("volunteerScheduledConfirm-\(order.orderId)")

            Button(role: .destructive) {
                pendingReleaseOrder = order
            } label: {
                Text(VolunteerServiceActionKind.releaseScheduled.title)
                    .font(AppFonts.body().weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(AppColors.destructive.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile, style: .continuous))
            }
            .disabled(anySubmitting)
            .accessibilityLabel(VolunteerServiceActionKind.releaseScheduled.title)
            .accessibilityHint("这一单会转给其他志愿者，需要确认后释放")
            .accessibilityIdentifier("volunteerScheduledRelease-\(order.orderId)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview {
    VolunteerTabView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
}
#endif
