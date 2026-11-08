import Combine // 只为 `@Published` / `ObservableObject`；订单跟踪不走 Combine（unify-order-live-tracking）
import SwiftUI

// MARK: - In Service

@MainActor
final class VolunteerInServiceViewModel: ObservableObject {
    /// 每一份新订单（轮询 / WS ETA / 汇合档位）都顺手喂给出发 / 汇合锁屏卡 ——
    /// 按下「我出发了」成功后订单落到 `DRIVER_EN_ROUTE`，卡就是从这里起的。
    @Published var order: OrderDetailResponse? {
        didSet {
            // 「等待对方确认」只在汇合态成立：订单离开 `DRIVER_ARRIVED`（开跑 / 取消 / 重派）就作废。
            if order?.status != .driverArrived { awaitingBlindConfirmation = false }
            guard #available(iOS 16.2, *) else { return }
            // 置 nil 的唯一来源是出发 / 汇合后被重派（`REMATCHING`）—— 那张卡必须跟着结束。
            guard let order else {
                GuideRunActivityController.shared.end()
                return
            }
            appState?.liveEscortCoordinator.updateLiveActivityTargetDistance(meters: order.plannedDistanceMeters)
            appState?.liveEscortCoordinator.updateLiveActivityPartnerName(order.blindSurname?.nilIfBlank)
            GuideRunActivityController.shared.sync(order: order)
        }
    }
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    @Published var dispatchSummary: VolunteerDispatchSummaryResponse?
    @Published var didCancelOrder = false
    /// 这一单被系统转走了（#456）：失联事件 `ORDER_VOLUNTEER_LOST`，或不是自己按的取消却收到 `REMATCHING`。
    /// 宿主据此收起面板并关页。与 `didCancelOrder` 分开：那条是「我自己退掉的」，由取消面板的回调关页。
    @Published var didLoseOrder = false
    @Published var latestBlindSample: LocatedCoordinate?
    /// 与盲人同步的里程 / 时长 / 配速。只在 `IN_PROGRESS` 有值。
    @Published private(set) var blindStats: TrackStats?
    @Published var transitionState: VolunteerOrderTransitionState = .idle
    @Published var isAcknowledgingEmergency = false
    /// 云端求助确定一个字节都没发出去时打开，页面据此弹只列 120 / 110 的本地拨号兜底（#407 第 1 项）。
    @Published var offersLocalCallAfterUnsentSOS = false
    /// 按下「开始跑步」后后端答 409 `BLIND_CONFIRMATION_PENDING`（盲人还没点头，后端 #307 ①）。
    /// 页面据此把按钮上方小字换成「等待对方确认」；**按钮不置灰**，对方随时可能点。
    /// 收到 WS `BLIND_START_CONFIRMED`、或订单离开 `DRIVER_ARRIVED` 时清除。
    @Published var awaitingBlindConfirmation = false

    // 陪跑员订单页 v2（交付包 02 ③④）。
    /// 跑者最近一次位置的精度（米），汇合页方位盘的扇形宽度用它。与 `latestBlindSample` 同生同灭。
    @Published var latestBlindAccuracyMeters: Double?
    /// 响铃到这一刻为止（后端 `ringingUntil`）。之前按钮不可点。
    @Published var ringingUntil: Date?
    /// 响铃 / 快捷消息那一下的结果：「对方可能没收到」或 429 的等待。
    @Published var nudgeNotice: String?
    /// 快捷消息的「已发送」冷却起点（对接说明：客户端按 type 冷却 60 秒，后端只按单限 3 条）。
    @Published var quickMessageSentAt: [QuickMessageCode: Date] = [:]
    /// 结束等待成功 ⇒ 宿主关页。**不进**「跑者已取消」那一屏：这一单是陪跑员等满后结束的。
    @Published var didEndWaiting = false
    static let quickMessageCooldown: TimeInterval = 60

    // 跑步中（DECISIONS-v2 V4–V8，`VolunteerRunningCompanion.swift`）。
    /// 最近一次**本单**走散告警（`ESCORT_DISTANCE_ALERT`）的收到时刻。提示条按它显示 60 秒。
    @Published private(set) var separationAlertAt: Date?
    /// 本机定位精度差于 50 米的起始时刻。
    @Published var weakLocationSince: Date?
    @Published var isTogglingPause = false
    @Published var supportRequestState: VolunteerSupportRequestState = .idle
    /// 上一次已经播报（或进页时已经跑过）的整公里数。`nil` = 还没拿到过数字，第一次只记不播。
    private var lastAnnouncedKilometer: Int?
    private let voiceBroadcastEnabled: () -> Bool
    /// 结束等待的请求在路上。那期间收到的 `CANCELLED` 是它自己造成的，不播「跑者取消了」。
    var isEndingWait = false

    /// 轨迹节流。订单每 5 秒轮一次，而三个数字没必要跟得那么紧 ——
    /// 与盲人端 `BlindOrderStatusViewModel.trackPollingInterval` 取同一个值，
    /// 两端刷新频率不同会让「他那边已经 3.2 公里，我这边还是 3.1」变成常态。
    static let trackPollingInterval: TimeInterval = 10
    private var lastTrackFetchAt: Date?

    weak var appState: AppState?
    var speechService: SpeechService?
    /// 这一页的订单跟踪（OpenSpec `unify-order-live-tracking` 第 3 批）：状态推送、刷新、5 秒轮询、
    /// 跑者位置与过期、汇合 / 失联 / 走散几条推送都从这一条流来。只在第一次 `configure` 时打开。
    private var track: OrderLiveTrack?
    private var trackingTask: Task<Void, Never>?
    var confirmationTask: Task<Void, Never>?
    /// 取消之后那一句与「已记一次临时取消」的先后（`VolunteerCancelAnnouncement`）。
    var cancelAnnouncement = VolunteerCancelAnnouncement()
    var dispatchSummaryTask: Task<Void, Never>?
    let actionDeadlineNanoseconds: UInt64
    let confirmationTimeout: TimeInterval
    let orderLoadTimeout: TimeInterval
    let peerFreshness: TimeInterval

    init(
        actionDeadlineNanoseconds: UInt64 = 12_000_000_000,
        confirmationTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        orderLoadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness,
        voiceBroadcastEnabled: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: VolunteerRunVoiceBroadcast.defaultsKey)
        }
    ) {
        self.voiceBroadcastEnabled = voiceBroadcastEnabled
        self.actionDeadlineNanoseconds = actionDeadlineNanoseconds
        self.confirmationTimeout = max(0.05, confirmationTimeout)
        self.orderLoadTimeout = max(0.05, orderLoadTimeout)
        self.peerFreshness = max(0.01, peerFreshness)
    }

    var isTransitionPending: Bool { transitionState.blocksDuplicateSubmission }
    var transitionMessage: String? { transitionState.message }
    var canRetryTransitionConfirmation: Bool {
        if case .confirmationDelayed = transitionState { return true }
        return false
    }

    func configure(with appState: AppState, speechService: SpeechService, initialOrder: OrderDetailResponse?) {
        self.appState = appState
        self.speechService = speechService
        if order == nil {
            order = initialOrder
        }
        if let order {
            appState.liveEscortCoordinator.updateOwnedOrder(orderID: order.orderId, status: order.status)
            // 换单时 `updateOwnedOrder` 会清掉姓氏，所以这里再补一次（`didSet` 那次排在它前面）。
            appState.liveEscortCoordinator.updateLiveActivityPartnerName(order.blindSurname?.nilIfBlank)
        }
        openTrackIfNeeded(appState)
    }

    func startPolling(orderId: Int64) {
        if order?.orderId != orderId {
            clearPeerLocation()
        }
        // 登记活跃订单、（重）开轮询并立即拉一次、开始收跑者位置，都在 track 里（design §1、§4：
        // 暂缓中连第一次也不拉；之后睡 5 秒 → 拉 → 终态或暂缓中就停）。
        track?.follow(orderID: orderId)
    }

    /// 只停轮询与跑者位置；状态推送等其余事件照常送达（design §1）。不注销活跃订单。
    func stopPolling() {
        track?.pause()
        confirmationTask?.cancel()
        confirmationTask = nil
        clearPeerLocation()
    }

    func load(orderId: Int64, speakChanges: Bool) async {
        guard let appState else { return }
        var refreshedAuthoritativeOrder = false
        defer {
            if refreshedAuthoritativeOrder {
                appState.realtimeCoordinator.completeOrderRefresh(orderId)
            } else {
                appState.realtimeCoordinator.failOrderRefresh(orderId)
            }
        }
        isLoading = order == nil
        do {
            let orders = appState.orders
            let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderId)
            let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                timeout: orderLoadTimeout,
                operationName: "volunteer-order-poll"
            ) {
                try await orders.orderDetail(orderId: orderId)
            }
            guard let loaded = appState.realtimeCoordinator.reconcileOrderDetail(
                candidate,
                requestToken: requestToken
            ) else {
                isLoading = false
                return
            }
            refreshedAuthoritativeOrder = true
            apply(loaded, speakChanges: speakChanges)
            isLoading = false
            await refreshBlindStatsIfNeeded(for: loaded, appState: appState)
        } catch {
            isLoading = false
            // 401 必须交出去（#438）：跑步中这是暂缓退出最常见的入口（#376），此前被这里一并吞掉，
            // 横幅不出、求助面板停在云端那一档，要等陪跑员按了别的按钮撞上 401 才进暂缓。
            if let apiError = error as? APIError, apiError.endsSession { return }
            // 403 `ORDER_PERMISSION_DENIED` = 后端说我已不是这一单的参与者（转重派时 `order.volunteer` 置空），#476。
            // 这是唯一不依赖「手上有订单」的权威信号：冷启动还没拉到详情时，失联事件与 `REMATCHING` 推送都认不出这一单；
            // 补读来的旧失联事件不带 `orderId`，也不能凭它放下。与失联同一条静默离开路径，不与横幅抢播报。
            // 自己按的取消不走这里：关页由取消面板的回调做（见 `didLoseOrder`）。
            if (error as? APIError)?.errorCode == .orderPermissionDenied, !cancelAnnouncement.requested {
                refreshedAuthoritativeOrder = true
                leaveLostOrder(orderID: orderId)
                return
            }
            if order == nil {
                errorMessage = "获取订单状态失败"
            }
        }
    }

    /// 陪跑中那屏上跟盲人同步的三个数字。
    ///
    /// 走的是**和盲人端同一个端点** `GET /api/orders/{id}/track`，取的也是同一份
    /// `blindStats` —— 后端按订单参与方鉴权，志愿者读得到。两端各算一份的话，
    /// 「你俩看到的公里数不一样」会变成一个没人能复现的投诉。
    ///
    /// 🚩 **张梦蝶（2023）点名的助跑者痛点就是「无法了解视障跑者的状态」**，
    /// 而在此之前志愿者端这一态只有一张地图和几个流转按钮。
    ///
    /// 失败时**不清空已有数字、不播报**，理由与盲人端 `refreshTrackStatsIfNeeded` 逐字相同：
    /// 跑动中一次网络抖动把屏幕上的距离归零，比暂时不更新糟得多。
    private func refreshBlindStatsIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status == .inProgress else {
            blindStats = nil
            lastTrackFetchAt = nil
            return
        }
        let now = Date()
        if let last = lastTrackFetchAt, now.timeIntervalSince(last) < Self.trackPollingInterval { return }
        lastTrackFetchAt = now
        do {
            blindStats = try await appState.safety.orderTrack(orderId: order.orderId).blindStats
        } catch {
            return
        }
        announceKilometerIfNeeded(blindStats)
    }

    /// 耳机语音播报开着时，每跨过一个整公里念一次（08 §二）。进页时已经跑过的公里不补念。
    func announceKilometerIfNeeded(_ stats: TrackStats?) {
        guard let meters = stats?.distanceMeters, meters >= 0 else { return }
        let km = Int(meters / 1_000)
        defer { lastAnnouncedKilometer = max(km, lastAnnouncedKilometer ?? km) }
        guard let last = lastAnnouncedKilometer, km > last, voiceBroadcastEnabled(),
              let duration = stats?.durationText else { return }
        speechService?.speak(VolunteerRunCopy.kilometerAnnouncement(km: km, duration: duration))
    }

}

// 订单跟踪的接入（design §1、§7）。放在同文件的扩展里：要写 `private(set)` 的 `separationAlertAt`，又不撑大类型体。
extension VolunteerInServiceViewModel {
    func openTrackIfNeeded(_ appState: AppState) {
        guard track == nil else { return }
        let track = appState.realtimeCoordinator.orderLiveTracker.open(
            role: .volunteer,
            polling: .volunteer,
            peerFreshness: peerFreshness,
            currentStatus: { [weak self] in self?.order?.status },
            isSessionExpiryDeferred: { [weak appState] in appState?.isSessionExpiryDeferred ?? false },
            load: { [weak self] orderID in await self?.loadForTracking(orderId: orderID) }
        )
        self.track = track
        // 只拿流，不捕获 track：页面释放 ⇒ track 释放 ⇒ 流结束 ⇒ 这个任务退出。
        let events = track.events
        trackingTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    /// 轮询与协调器请求的刷新共用这一个入口。这一单已经放下（自己取消 / 被转走，`order` 已置空）就不再拉：
    /// 原来的刷新订阅只认手上的 `order`，放下之后不为它发请求（否则会把已放下的单再念一遍）。
    private func loadForTracking(orderId: Int64) async {
        if order == nil, didLoseOrder || didCancelOrder { return }
        await load(orderId: orderId, speakChanges: true)
    }

    /// 每种事件同步处理，判据照搬原来的 7 个订阅。
    private func handle(_ event: OrderTrackingEvent) {
        switch event {
        case .status(let update):
            // 必调（design §6）：首页据此决定念不念通用状态句。
            track?.acknowledge(update, spoke: applyRealtimeStatus(update))
        case .peerLocation(let peer):
            showBlindLocation(peer)
        case .peerLocationExpired:
            clearPeerLocation()
        case .liveUpdate(let update):
            // ETA / 汇合距离档位。不落通知日志，只就地合进手上这份订单，重连后以详情为准。
            guard let current = order else { return }
            order = current.merging(update)
        case .blindStartConfirmed:
            confirmBlindStartIfMeeting()
        case .volunteerLost:
            // 出发后失联、单已转走（`ORDER_VOLUNTEER_LOST`，#456）。信封同样不带 `orderId`，判据见
            // `isTakenAwayWhenVolunteerLost`。后端紧接着还会推 `REMATCHING`：这里先把 `order` 置空，
            // 那条推送到达时 `applyRealtimeStatus` 就认不出这一单，不会再念「订单已取消」把横幅切断。
            guard let order, order.status.isTakenAwayWhenVolunteerLost else { return }
            leaveLostOrder(orderID: order.orderId)
        case .separationAlert(let alert):
            raiseSeparationAlert(alert)
        }
    }

    private func confirmBlindStartIfMeeting() {
        // 盲人点了「可以开始」（`BLIND_START_CONFIRMED`）。信封**不带 `orderId`**
        // （`websocket-protocol.md`，早于 orderId 约定），所以只认「当前这张是汇合态」；
        // 陪跑员同一时刻只会有一张汇合态订单（`VOLUNTEER_ALREADY_ENGAGED` 时段闸）。
        guard let order, order.status == .driverArrived else { return }
        awaitingBlindConfirmation = false
        // 跑者确认后后端把它置 `null`。先在本地清掉：下面那次重拉失败时，
        // 按钮上方不能还说「跑者还没按开始跑步」（`VolunteerActionGate`）。
        self.order?.blindConfirmDeadlineAt = nil
        Task { await self.load(orderId: order.orderId, speakChanges: false) }
    }

    private func raiseSeparationAlert(_ alert: RealtimeSeparationAlert) {
        // 走散提示条的驱动（V7：沿用现有告警，阈值不改）。track 只送打开之后到的、本单的
        // `ESCORT_DISTANCE_ALERT`；手上的单已放下就不认（原订阅比的是 `order?.orderId`）。
        guard alert.orderID == order?.orderId else { return }
        separationAlertAt = Date()
        // 前台横幅已经在念这条告警，这一下是它的冗余通道（08 §五「额外 .warning 一次」）。
        HapticFeedback.play(.warning)
    }
}
