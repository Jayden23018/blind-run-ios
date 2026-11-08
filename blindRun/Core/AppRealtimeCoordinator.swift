import Combine
import Foundation

import SwiftUI

/// App-lifetime owner for decoded realtime routing. Feature ViewModels retain authoritative REST state.
@MainActor
final class AppRealtimeCoordinator: ObservableObject {
    struct OrderStatusEventFingerprint: Equatable {
        let orderID: Int64
        let fromStatus: String?
        let toStatus: String
    }

    enum RetainedOrderStatusIdentity: Equatable {
        case fingerprint(OrderStatusEventFingerprint)
        case collision
    }

    enum OrderStatusIdentityDecision {
        case process(messageID: String?)
        case duplicate
        case collision
    }

    @Published var connectionState: WSConnectionState = .disconnected
    @Published var pendingOrderRefreshIDs: Set<Int64> = []
    @Published var pendingOrderRefreshRequests: [Int64: RealtimeOrderRefreshRequest] = [:]
    /// 当前还没被回复、也还没过期的派单，**按回复期限升序**（设计交付 v3 §4.4.2）。
    ///
    /// 🔴 **这里从「一条」改成「一队」是在修一个真缺陷，不是为了设计稿的分页点。**
    /// 后端对同一个志愿者的派单**跨订单零互斥** —— `DispatchService.java:403-406` 的注释
    /// 自己写着「接单锁是 per-order 的…拦不到同一个志愿者接两单」「候选池过滤是尽力而为的优化，
    /// 拦不住两条派单链路同时把他选中」。而这里原先一句 `guard pendingDispatch == nil`
    /// 把第二条**静默丢掉**：志愿者丢单、盲人白等一轮 30 秒，而没有任何东西会报警。
    @Published var pendingDispatches: [RealtimeDispatchPrompt] = []

    /// 队列里最靠前的那一条。保留它是因为「只有一条派单」仍然是绝大多数情况，
    /// 而六处既有断言读的就是这个语义。
    var pendingDispatch: RealtimeDispatchPrompt? { pendingDispatches.first }

    @Published var dispatchDiagnostic: WSDispatchDiagnostic?
    @Published var currentNotification: RealtimeForegroundNotification?
    /// 陪跑员按了「让 TA 的手机响起来」。盲人端 `BlindRunnerTabView` 据此响铃，响完调 `dismissRunnerRing`。
    @Published var runnerRing: RunnerRingRequest?
    @Published var latestSeparationAlert: RealtimeSeparationAlert?
    @Published var latestSafetyEvent: RealtimeSafetyEvent?

    /// 最近一次（实时推送或重连补读）看到的通知 ISO-8601 timestamp。
    /// 作为 `GET /api/notifications/since?after=` 的游标，由 `AppState` 持久化。
    var lastObservedNotificationTimestamp: String?

    let peerLocationSubject = PassthroughSubject<RealtimePeerLocationSample, Never>()
    let recoverySubject = PassthroughSubject<RealtimeRecoverySignal, Never>()
    let statusUpdateSubject = PassthroughSubject<RealtimeOrderStatusUpdate, Never>()
    let orderLiveUpdateSubject = PassthroughSubject<RealtimeOrderLiveUpdate, Never>()
    var orderLiveUpdatePublisher: AnyPublisher<RealtimeOrderLiveUpdate, Never> {
        orderLiveUpdateSubject.eraseToAnyPublisher()
    }
    /// 盲人点了「可以开始」（后端 #307 ①）。**不带订单号**：该事件的信封里没有 `orderId`
    /// （`websocket-protocol.md`，早于 orderId 约定），消费方自己判「当前是不是汇合态」。
    /// 通知本身照常入队播报，这条只是让页面把「等待对方确认」收回去。
    let blindStartConfirmedSubject = PassthroughSubject<Void, Never>()
    var blindStartConfirmedPublisher: AnyPublisher<Void, Never> {
        blindStartConfirmedSubject.eraseToAnyPublisher()
    }
    static let blindStartConfirmedEventType = "BLIND_START_CONFIRMED"
    /// 跑者在接单前通话里按了拨号（`INTRO_CALL_INCOMING`，#433 V1′）。值是**后端发出的时刻**
    /// （解析不出用收到的时刻）：重连补读会把几分钟前的那条再投一次，消费方据此判断提醒还在不在 2 分钟内。
    /// **不带订单号**（后端发这条时 `orderId` 为 null）；陪跑员同一时刻只可能锁在一轮通话里。
    private let introCallIncomingSubject = PassthroughSubject<Date, Never>()
    var introCallIncomingPublisher: AnyPublisher<Date, Never> {
        introCallIncomingSubject.eraseToAnyPublisher()
    }
    static let introCallIncomingEventType = "INTRO_CALL_INCOMING"
    /// 陪跑员出发后失联 / 迟迟不到，系统已把这一单转走（`ORDER_VOLUNTEER_LOST`，后端 #616 M6，iOS #456）。
    /// **不带订单号**：后端用模板通知发它（`sendNotification(..., null)`），信封和补读那条日志都没有 `orderId`；
    /// 消费方自己判「手上这一单是不是出发中 / 已到达」（`RunOrderStatus.isTakenAwayWhenVolunteerLost`）。
    /// 只有实时推送发、补读不发（见 `ingestCatchUp`，#476）。通知本身照常入队念 `ttsText`，这条**不念任何话**。
    private let volunteerLostSubject = PassthroughSubject<Void, Never>()
    var volunteerLostPublisher: AnyPublisher<Void, Never> {
        volunteerLostSubject.eraseToAnyPublisher()
    }
    static let volunteerLostEventType = "ORDER_VOLUNTEER_LOST"

    /// 跑者也会收到同名事件（文案不同），那一端没有可放下的订单页。未绑定角色（单测直接喂事件）时照发。
    func publishVolunteerLostIfNeeded(eventType: String) {
        guard eventType == Self.volunteerLostEventType,
              attachedRole == nil || attachedRole == .volunteer else { return }
        volunteerLostSubject.send()
        orderLiveTracker.receiveVolunteerLost()
    }
    /// 陪跑员通话页开着时为 true：那一页自己显示「跑者王*正在来电」并播一次，
    /// 这条通知就**不再进横幅** —— 两处各念一遍，读屏用户会听到同一件事两次。
    /// 页面不在时照旧走横幅（陪跑员在首页也要知道有人在打给他）。
    ///
    /// 计数而不是一个 Bool：通话页能从首页和派单中心两处进，一处的实例消失时不能把另一处还开着的那页也算没了。
    var isIntroCallPageShowingIncomingCalls: Bool { introCallPagesShowingIncomingCalls > 0 }
    private var introCallPagesShowingIncomingCalls = 0

    func introCallPageDidAppear() { introCallPagesShowingIncomingCalls += 1 }
    func introCallPageDidDisappear() { introCallPagesShowingIncomingCalls = max(0, introCallPagesShowingIncomingCalls - 1) }
    /// 一张还没回复的邀请失效了（撤回推送，或待回复快照里已经没有它）。
    /// 协调器自己的队列已经移走它；首页那张卡要不要原地变「已失效」由首页决定（它手里有「正在看哪一张」）。
    private let inviteWithdrawalSubject = PassthroughSubject<RealtimeInviteWithdrawal, Never>()
    var inviteWithdrawalPublisher: AnyPublisher<RealtimeInviteWithdrawal, Never> {
        inviteWithdrawalSubject.eraseToAnyPublisher()
    }
    /// 一次待回复快照到了。首页拿它对**自己手里的卡**对账 —— 协调器的队列在断线重连时会被清空，
    /// 而首页的卡还在，只在这里对账的话，离线期间被接走的那张卡会一直挂着一个点了必定 409 的按钮。
    private let pendingInviteSnapshotSubject = PassthroughSubject<RealtimePendingInviteSnapshot, Never>()
    var pendingInviteSnapshotPublisher: AnyPublisher<RealtimePendingInviteSnapshot, Never> {
        pendingInviteSnapshotSubject.eraseToAnyPublisher()
    }
    var peerLocationPublisher: AnyPublisher<RealtimePeerLocationSample, Never> { peerLocationSubject.eraseToAnyPublisher() }
    var recoveryPublisher: AnyPublisher<RealtimeRecoverySignal, Never> { recoverySubject.eraseToAnyPublisher() }
    var statusUpdatePublisher: AnyPublisher<RealtimeOrderStatusUpdate, Never> {
        statusUpdateSubject.eraseToAnyPublisher()
    }

    private weak var attachedService: WebSocketService?
    /// 订单页的跟踪（OpenSpec `unify-order-live-tracking`）。协调器在原有发布点旁直接调它，原发布不删。
    /// 协调器强持有它、它弱引用回协调器。
    private(set) lazy var orderLiveTracker = OrderLiveTracker(coordinator: self)
    var attachedRole: WSRole?
    private var eventCancellable: AnyCancellable?
    private var connectionCancellable: AnyCancellable?
    private var dispatchDiagnosticCancellable: AnyCancellable?
    var notificationTask: Task<Void, Never>?
    /// 每条派单各自的到期任务。**按 orderId 分开存**：一个共享的 task 只能跟住最后一条，
    /// 其余的到期之后会永远留在队列里（而它们已经被后端转给别人了）。
    var dispatchExpiryTasks: [Int64: Task<Void, Never>] = [:]
    /// 本地已经了结的邀请，记到它原本的回复期限为止。为什么要记见 `RetiredInviteLedger`。
    var retiredInvites = RetiredInviteLedger()
    /// 已送达的邀请通知该收掉时调（撤回 / 回复 / 对账，#338）。默认什么都不做 —— 单测不碰系统通知中心，
    /// 真的那一半由 `PushNotificationsManager.configure` 接上。
    var pruneDeliveredInviteNotifications: @MainActor (InviteNotificationPrune) -> Void = { _ in }
    /// 锁屏上按了「接下 / 这次去不了」、App 刚被拉起（#338）。首页等这张邀请进了队列，就走卡片上同一条路径。
    ///
    /// 🚩 **会话清理（`detach(clearSessionState:)`）不清它**：冷启动时 WS 接上那一刻就会走一次清理，
    /// 而那时首页还没建出来，清了就是「按了接下、App 打开了、什么都没发生」（#338 安全复核 HIGH 1）。
    /// 不会替别的账号回复：首页只认**当前账号队列里**身份对得上、还在等回复的那张；邀请期限一过就作废。
    @Published private(set) var lockScreenInviteAction: InviteNotificationActions.Request?
    /// 按下的时刻。只有之后发出的那次对账才能判「这张已经没了」。
    private(set) var lockScreenInviteActionAt: Date?
    /// 按下时登录的账号（冷启动时可能还没恢复，是 `nil`）。首页对不上当前账号就丢掉。
    private(set) var lockScreenInviteActionUserID: Int64?
    var orderRefreshRetryTasks: [Int64: Task<Void, Never>] = [:]
    var orderRefreshRetryCounts: [Int64: Int] = [:]
    var queuedNotifications: [RealtimeForegroundNotification] = []
    var deduplicationDates: [String: Date] = [:]
    var activeOrderIDs: Set<Int64> = []
    var activeOrderStatuses: [Int64: RunOrderStatus] = [:]
    var orderStatusReconciler = OrderStatusReconciler()
    var retainedOrderStatusIdentities: [String: RetainedOrderStatusIdentity] = [:]
    var retainedOrderStatusIdentityOrder: [String] = []
    var recentLifecycleStatusDates: [RunOrderStatus: Date] = [:]
    var latestPeerSamples: [String: RealtimePeerLocationSample] = [:]
    var peerPublishTasks: [String: Task<Void, Never>] = [:]
    var hasConnectedOnce = false
    let now: () -> Date
    let notificationDuration: TimeInterval
    let deduplicationWindow: TimeInterval
    let orderRefreshRetryDelays: [TimeInterval]
    let maximumQueuedNotifications: Int
    let maximumDeduplicationEntries = 128
    let maximumOrderStatusIdentities = 256
    let lifecycleNotificationSuppressionWindow: TimeInterval = 30

    #if DEBUG
    private(set) var attachmentCount = 0

    func simulateIncomingEventForTesting(_ event: WSIncomingEvent) {
        route(event)
    }

    /// 注册进位置协同的单号。用例守「预约单不进位置协同」（#471）。
    var registeredActiveOrderIDsForTesting: Set<Int64> { activeOrderIDs }

    /// 单测换上一个可调轮询间隔 / 时钟的 tracker。
    func replaceOrderLiveTrackerForTesting(_ tracker: OrderLiveTracker) { orderLiveTracker = tracker }
    #endif

    init(
        now: @escaping () -> Date = Date.init,
        notificationDuration: TimeInterval = 5,
        deduplicationWindow: TimeInterval = 120,
        orderRefreshRetryDelays: [TimeInterval] = [1, 2, 4],
        maximumQueuedNotifications: Int = 24
    ) {
        self.now = now
        self.notificationDuration = notificationDuration
        self.deduplicationWindow = deduplicationWindow
        self.orderRefreshRetryDelays = orderRefreshRetryDelays
        self.maximumQueuedNotifications = max(1, maximumQueuedNotifications)
    }

    func attach(to service: WebSocketService?, role: WSRole?) {
        guard attachedService !== service || attachedRole != role else { return }
        detach(clearSessionState: true)
        guard let service else { return }

        attachedService = service
        attachedRole = role
        #if DEBUG
        attachmentCount += 1
        #endif
        eventCancellable = service.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.route(event) }
        connectionCancellable = service.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleConnectionState(state) }
        dispatchDiagnosticCancellable = service.$dispatchDiagnostic
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] diagnostic in self?.dispatchDiagnostic = diagnostic }
    }

    func detach(clearSessionState: Bool) {
        eventCancellable?.cancel()
        connectionCancellable?.cancel()
        dispatchDiagnosticCancellable?.cancel()
        eventCancellable = nil
        connectionCancellable = nil
        dispatchDiagnosticCancellable = nil
        attachedService = nil
        attachedRole = nil
        hasConnectedOnce = false
        connectionState = .disconnected
        if clearSessionState { clearInMemoryState() }
    }
}

// 邀请队列的增删（后端 #371 / #366）。写在类外、同一个文件里：仍能动 private 状态（同文件扩展看得见），
// 又不让类体继续变大（SwiftLint 棘轮 #488）。值类型与纯函数在 `AppRealtimeCoordinator+Invites.swift`。
extension AppRealtimeCoordinator {
    /// 首页了结一张邀请（回复、收起、失效）时调。**只清同一张**：同一张单可能已经有一张新邀请（新 `inviteId`）
    /// 进了队列，按 `orderId` 整单清会把它一起删掉 —— 而首页按「已了结」不会再把它补回来，就是丢单。
    ///
    /// - Parameters:
    ///   - inviteID: `nil` = 不知道是哪一张（老服务端），按 `orderId` 清。
    ///   - retiredUntil: 这张邀请原本的期限。到期之前快照里再出现它也不收（见 `retiredInvites`）。
    func clearDispatch(orderID: Int64, inviteID: Int64? = nil, retiredUntil: Date? = nil) {
        let matches: (RealtimeDispatchPrompt) -> Bool = { prompt in
            prompt.order.orderId == orderID
                && (inviteID == nil || prompt.order.inviteId == nil || prompt.order.inviteId == inviteID)
        }
        let removed = pendingDispatches.first(where: matches)
        if removed != nil {
            dispatchExpiryTasks.removeValue(forKey: orderID)?.cancel()
            pendingDispatches.removeAll(where: matches)
        }
        retiredInvites.retire(
            orderID: orderID,
            inviteID: inviteID ?? removed?.order.inviteId,
            until: retiredUntil ?? removed?.expiresAt,
            now: now()
        )
        pruneDeliveredInviteNotifications(.invites([InviteIdentity(
            orderId: orderID, inviteId: inviteID ?? removed?.order.inviteId, expiresAt: retiredUntil ?? removed?.expiresAt
        )]))
    }

    /// 撤回一张邀请：从队列里移走（**只移走同一张**），并告诉首页。
    ///
    /// 推送里的 `inviteId` 与队列里那张对不上时不动队列 —— 那是同一张单更早一张邀请的迟到撤回，
    /// 队列里的是新的那张。首页那边照样收到事件，由它按同一条规则自己判。
    private func withdrawDispatch(orderID: Int64, inviteID: Int64?, reason: InviteWithdrawReason) {
        let matches: (RealtimeDispatchPrompt) -> Bool = { prompt in
            prompt.order.orderId == orderID
                && (inviteID == nil || prompt.order.inviteId == nil || prompt.order.inviteId == inviteID)
        }
        let removed = pendingDispatches.first(where: matches)
        if removed != nil {
            dispatchExpiryTasks.removeValue(forKey: orderID)?.cancel()
            pendingDispatches.removeAll(where: matches)
        }
        // 早于这条撤回发出的那次快照回来时还带着它 —— 记下来，别让它被灌回来。
        retiredInvites.retire(orderID: orderID, inviteID: inviteID ?? removed?.order.inviteId, until: removed?.expiresAt, now: now())
        // 撤回不会销毁锁屏上那条旧通知（契约），点它只会得到 409 —— 自己收掉。只收这一张，同单的新邀请留着：
        // 队列里没有它时不知道它的期限，而 `NEW_ORDER` 的通知没有 `inviteId`，按单号收会连新邀请那条一起收掉。
        // 那时留给下一次对账收（快照里没有、且早于请求送达的才收）。
        if let removed {
            pruneDeliveredInviteNotifications(.invites([InviteIdentity(
                orderId: orderID, inviteId: inviteID ?? removed.order.inviteId, expiresAt: removed.expiresAt
            )]))
        }
        inviteWithdrawalSubject.send(RealtimeInviteWithdrawal(orderId: orderID, inviteId: inviteID, reason: reason))
    }

    /// 与服务端的待回复列表对账（`GET /api/volunteer/pending-invites`，后端 #366）。
    ///
    /// 为什么需要：撤回只走 WS、不能重连补读；锁屏 / 杀 App / 断网期间收到的新邀请也只有 APNs。
    /// 契约：「冷启动、从后台回前台、WS 重连成功后，各调一次」。
    ///
    /// - 快照里有、队列里没有的 ⇒ 补进来（期限读 `expiresAt`）。
    /// - 队列里有、快照里没有的 ⇒ 移走。**只移请求发出之前就在队列里的**（`receivedAt < requestedAt`）：
    ///   请求在路上时推送来的新邀请不在这份快照里，移走它就是丢单。
    /// - 快照整份发给首页，首页对自己手里的卡做同样的判断并决定原地变「已失效」还是静默移除。
    /// - 快照里没有的单，早于这次请求送达的邀请通知一并从通知中心收掉（#338）。
    func reconcilePendingInvites(_ invites: [WSNewOrder], requestedAt: Date, consecutiveDeclineCount: Int? = nil) {
        guard attachedRole == nil || attachedRole == .volunteer else { return }
        let snapshot = RealtimePendingInviteSnapshot(
            invites: invites, requestedAt: requestedAt, consecutiveDeclineCount: consecutiveDeclineCount
        )
        pruneDeliveredInviteNotifications(.allExcept(Set(invites.map(\.orderId)), deliveredBefore: requestedAt))
        let stale = pendingDispatches.filter { prompt in
            prompt.receivedAt < requestedAt
                && !snapshot.contains(orderID: prompt.order.orderId, inviteID: prompt.order.inviteId)
        }
        for prompt in stale {
            dispatchExpiryTasks.removeValue(forKey: prompt.order.orderId)?.cancel()
            pendingDispatches.removeAll { $0.order.orderId == prompt.order.orderId }
        }
        for invite in invites {
            retainDispatch(invite)
        }
        pendingInviteSnapshotSubject.send(snapshot)
    }

    /// `INTRO_CALL_INCOMING`（实时与重连补读两条路）：交给通话页，并判这条要不要再进横幅。返回 `true` = 不进。
    ///
    /// 通话页开着时由页面自己显示并念一次；页面不在时，**过了 2 分钟的不进横幅、不念**（#448）——
    /// 离线 10 分钟后重连补读来的「跑者正在打给你」会让人以为跑者此刻在打电话。
    /// 时效判据与通话页同一条（`IntroCallCopy.incomingCallDisplayUntil`）；时刻解不出时按「刚刚」算（与通话页一致）。
    func routeIntroCallIncoming(sentAt raw: String?) -> Bool {
        let sentAt = raw?.nilIfBlank?.backendTimestamp ?? now()
        introCallIncomingSubject.send(sentAt)
        return isIntroCallPageShowingIncomingCalls || IntroCallCopy.incomingCallDisplayUntil(sentAt: sentAt, now: now()) == nil
    }

    /// 锁屏邀请操作（`ACCEPT_INVITE` / `DECLINE_INVITE`，#338）：记下来，等首页拿走。只记最后按的那一下。
    func requestLockScreenInviteAction(_ request: InviteNotificationActions.Request, userID: Int64? = nil) {
        lockScreenInviteActionAt = now()
        lockScreenInviteActionUserID = userID
        lockScreenInviteAction = request
    }

    /// 首页已经接手（开始回复，或已告诉他这张失效了）。
    func consumeLockScreenInviteAction() {
        lockScreenInviteAction = nil
        lockScreenInviteActionAt = nil
        lockScreenInviteActionUserID = nil
    }

    /// 邀请类事件：新邀请进队，撤回从队里移走同一张。从 `route` 分出来，那个 switch 只许变短。
    func routeInviteEvent(_ event: WSIncomingEvent) {
        switch event {
        case .newOrder(let message):
            retainDispatch(message)
        case .inviteWithdrawn(let message):
            withdrawDispatch(orderID: message.orderId, inviteID: message.inviteId, reason: message.withdrawReason)
        default:
            break
        }
    }
}
