import Combine
import Foundation

struct RealtimeOrderStatusUpdate: Equatable, Sendable {
    let messageId: String?
    let orderId: Int64
    let fromStatus: RunOrderStatus
    let toStatus: RunOrderStatus
    let receivedAt: Date

    init(
        messageId: String? = nil,
        orderId: Int64,
        fromStatus: RunOrderStatus,
        toStatus: RunOrderStatus,
        receivedAt: Date
    ) {
        self.messageId = messageId
        self.orderId = orderId
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.receivedAt = receivedAt
    }
}

struct OrderStatusRequestToken: Equatable, Sendable {
    let orderID: Int64
    fileprivate let generation: UInt64
}

enum OrderStatusReconciliationResult: Equatable, Sendable {
    case applied(RunOrderStatus)
    case duplicate(RunOrderStatus)
    case rejectedStale(current: RunOrderStatus, candidate: RunOrderStatus)
    case rejectedInvalid(current: RunOrderStatus?, candidate: RunOrderStatus)

    var resolvedStatus: RunOrderStatus? {
        switch self {
        case .applied(let status), .duplicate(let status):
            return status
        case .rejectedStale(let current, _):
            return current
        case .rejectedInvalid(let current, _):
            return current
        }
    }
}

/// Serial, in-memory authority for status candidates from REST and WebSocket.
/// It prevents a request that started before a realtime transition from
/// overwriting the newer state when its response arrives late.
struct OrderStatusReconciler {
    private struct Entry {
        var status: RunOrderStatus
        var generation: UInt64
    }

    private var entries: [Int64: Entry] = [:]

    mutating func register(orderID: Int64, status: RunOrderStatus) {
        guard let current = entries[orderID] else {
            entries[orderID] = Entry(status: status, generation: 0)
            return
        }
        if current.status == status { return }
        if current.status.canReach(status) {
            entries[orderID] = Entry(status: status, generation: current.generation &+ 1)
        }
    }

    mutating func unregister(orderID: Int64) {
        entries.removeValue(forKey: orderID)
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    func requestToken(orderID: Int64) -> OrderStatusRequestToken {
        OrderStatusRequestToken(
            orderID: orderID,
            generation: entries[orderID]?.generation ?? 0
        )
    }

    func currentStatus(orderID: Int64) -> RunOrderStatus? {
        entries[orderID]?.status
    }

    func isCurrent(_ token: OrderStatusRequestToken) -> Bool {
        (entries[token.orderID]?.generation ?? 0) == token.generation
    }

    mutating func reconcileRealtime(
        orderID: Int64,
        fromStatus: RunOrderStatus,
        toStatus: RunOrderStatus
    ) -> OrderStatusReconciliationResult {
        let current = entries[orderID]?.status
        guard current == nil || current == fromStatus else {
            if current == toStatus { return .duplicate(toStatus) }
            return current.map {
                $0.canReach(fromStatus)
                    ? .rejectedInvalid(current: $0, candidate: toStatus)
                    : .rejectedStale(current: $0, candidate: toStatus)
            } ?? .rejectedInvalid(current: nil, candidate: toStatus)
        }
        guard fromStatus.isDirectlyFollowed(by: toStatus) else {
            return .rejectedInvalid(current: current, candidate: toStatus)
        }

        let nextGeneration = (entries[orderID]?.generation ?? 0) &+ 1
        entries[orderID] = Entry(status: toStatus, generation: nextGeneration)
        return .applied(toStatus)
    }

    mutating func reconcileREST(
        orderID: Int64,
        candidate: RunOrderStatus,
        token: OrderStatusRequestToken
    ) -> OrderStatusReconciliationResult {
        guard token.orderID == orderID else {
            return .rejectedInvalid(current: entries[orderID]?.status, candidate: candidate)
        }
        guard let current = entries[orderID] else {
            entries[orderID] = Entry(status: candidate, generation: 0)
            return .applied(candidate)
        }
        if candidate == current.status { return .duplicate(candidate) }
        if current.status.lifecycleRank > candidate.lifecycleRank,
           !candidate.isTerminal,
           candidate != .rematching {
            return .rejectedStale(current: current.status, candidate: candidate)
        }

        if current.status.canReach(candidate) {
            entries[orderID] = Entry(status: candidate, generation: current.generation &+ 1)
            return .applied(candidate)
        }
        if candidate.canReach(current.status) || token.generation < current.generation {
            return .rejectedStale(current: current.status, candidate: candidate)
        }
        return .rejectedInvalid(current: current.status, candidate: candidate)
    }
}

private extension RunOrderStatus {
    var lifecycleRank: Int {
        switch self {
        // `.pendingIntroCall` 与 `.pendingMatch` **同档**，这不是偷懒。
        // 这一档只被 `reconcileREST` 用来拒绝「倒退的」REST 结果，而这两态之间的倒退是真的：
        // 本轮没聊成时后端把订单退回 `PENDING_MATCH`（`IntroCallService.releaseToQueue`，
        // 刻意不是 `REMATCHING`）。给通话态排更高的档，那条真实迁移会被判成陈旧丢掉，
        // 盲人的页面就永远停在「等待通话确认」。
        case .pendingMatch, .pendingIntroCall: return 0
        case .pendingAccept, .rematching: return 1
        case .driverEnRoute: return 2
        case .driverArrived: return 3
        case .inProgress: return 4
        case .completed, .cancelled, .noVolunteer: return 5
        // 排在所有真实状态之前，这样「当前是未知态」永远不会把一个真实状态判成陈旧。
        case .unknown: return -1
        }
    }

    func isDirectlyFollowed(by candidate: RunOrderStatus) -> Bool {
        switch self {
        case .pendingMatch:
            return [.pendingIntroCall, .pendingAccept, .cancelled, .noVolunteer].contains(candidate)
        // 后端 `OrderStatus.java` 的通话磨合分支：双方认可 → PENDING_ACCEPT；
        // 任一方不认可 / 没接到 / 窗口超时 → 退回 PENDING_MATCH（**不是 REMATCHING**）；
        // 轮次达上限 → NO_VOLUNTEER；盲人取消 → CANCELLED。
        case .pendingIntroCall:
            return [.pendingAccept, .pendingMatch, .cancelled, .noVolunteer].contains(candidate)
        case .pendingAccept:
            return [.driverEnRoute, .cancelled, .rematching].contains(candidate)
        case .driverEnRoute:
            return [.driverArrived, .rematching].contains(candidate)
        case .driverArrived:
            return [.inProgress, .rematching].contains(candidate)
        case .inProgress:
            return [.completed, .rematching].contains(candidate)
        // `REMATCHING` 与 `PENDING_MATCH` 在后端 `isDispatchable()` 下行为一致，
        // 所以它同样能被一个候选人「有意向」拽进通话磨合。
        case .rematching:
            return [.pendingIntroCall, .pendingAccept, .cancelled, .noVolunteer].contains(candidate)
        case .completed, .cancelled, .noVolunteer:
            return false
        // 未知态没有任何可信的后继约束，一律放行，让下一个认识的状态把界面救回来。
        // 反方向不通：`.unknown` 不在 `allCases` 里，`canReach` 的遍历永远到不了它，
        // 所以一个未知的候选状态也顶不掉已经确定的状态。
        case .unknown:
            return true
        }
    }

    func canReach(_ candidate: RunOrderStatus) -> Bool {
        if self == candidate { return true }
        var visited: Set<RunOrderStatus> = [self]
        var pending = [self]
        while let status = pending.popLast() {
            for next in RunOrderStatus.allCases where status.isDirectlyFollowed(by: next) {
                if next == candidate { return true }
                if visited.insert(next).inserted {
                    pending.append(next)
                }
            }
        }
        return false
    }
}
import SwiftUI

enum RealtimePriority: Int, Codable, Comparable, Sendable {
    case normal = 0
    case high = 1

    init(rawValue: String?) {
        self = rawValue?.uppercased() == "HIGH" ? .high : .normal
    }

    static func < (lhs: RealtimePriority, rhs: RealtimePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum RealtimePeerRole: String, Sendable {
    case blind
    case volunteer
}

struct RealtimePeerLocationSample: Sendable {
    let orderId: Int64
    let ownerRole: RealtimePeerRole
    let latitude: Double
    let longitude: Double
    let timestampMilliseconds: Int64

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct RealtimeOrderRefreshRequest: Sendable {
    enum Reason: Sendable { case statusChanged, reconnected }
    let orderId: Int64
    let reason: Reason
}

struct RealtimeDispatchPrompt: Sendable {
    let order: WSNewOrder
    let receivedAt: Date
    let expiresAt: Date

    func remainingSeconds(at date: Date = Date()) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(date))))
    }
}

struct RealtimeForegroundNotification: Identifiable, Sendable {
    let id = UUID()
    let stableEventID: String?
    let title: String?
    let displayText: String
    let speechText: String
    let priority: RealtimePriority
    let timestamp: String?
    let isSafetyEvent: Bool
}

struct RealtimeSeparationAlert: Sendable {
    let eventID: String
    let orderID: Int64
    let eventType: String
    let distanceMeters: Double?
    let displayText: String
    let speechText: String
    let timestamp: String?
}

struct RealtimeSafetyEvent: Sendable {
    enum Kind: String, Sendable {
        case emergencyVolunteerAlert
        case emergencyResolved
        case emergencyContactNotified
        // The ones below reach iOS as `APP_NOTIFICATION` envelopes carrying an `eventType`, not as
        // top-level WebSocket types (`NotificationService.sendNotification`, :93-99).
        case emergencyTriggered
        case emergencyNoContact
        case emergencyVolunteerTimeout
        // 2026-07-31 batch (handoff.md): volunteer-initiated SOS, SMS delivery receipts, and the
        // close-out events that previously left the blind runner with zero notification.
        case emergencyTriggeredByVolunteer
        case emergencyContactSmsDelivered
        case emergencyContactNotifyFailed
        case emergencyVolunteerAck
        case emergencyClosedResolved
        case emergencyClosedFalseAlarm

        /// Kinds that mean "an emergency involving this user is open right now". Used to decide
        /// whether an event arriving with no local state is worth a recovery fetch — close-out and
        /// observer events are not, so a resolved event never resurrects itself.
        var impliesLiveEmergency: Bool {
            switch self {
            case .emergencyTriggered, .emergencyTriggeredByVolunteer, .emergencyContactNotified,
                 .emergencyContactSmsDelivered, .emergencyContactNotifyFailed, .emergencyNoContact,
                 .emergencyVolunteerTimeout, .emergencyVolunteerAck:
                return true
            case .emergencyResolved, .emergencyClosedResolved, .emergencyClosedFalseAlarm,
                 .emergencyVolunteerAlert:
                return false
            }
        }
    }

    let eventID: String
    let orderID: Int64?
    let kind: Kind
    let displayText: String
    let speechText: String
    let timestamp: String?
}

struct RealtimeRecoverySignal: Sendable {
    let role: WSRole
    let connectedAt: Date
}

/// App-lifetime owner for decoded realtime routing. Feature ViewModels retain authoritative REST state.
@MainActor
final class AppRealtimeCoordinator: ObservableObject {
    private struct OrderStatusEventFingerprint: Equatable {
        let orderID: Int64
        let fromStatus: String?
        let toStatus: String
    }

    private enum RetainedOrderStatusIdentity: Equatable {
        case fingerprint(OrderStatusEventFingerprint)
        case collision
    }

    private enum OrderStatusIdentityDecision {
        case process(messageID: String?)
        case duplicate
        case collision
    }

    @Published private(set) var connectionState: WSConnectionState = .disconnected
    @Published private(set) var pendingOrderRefreshIDs: Set<Int64> = []
    @Published private(set) var pendingOrderRefreshRequests: [Int64: RealtimeOrderRefreshRequest] = [:]
    @Published private(set) var pendingDispatch: RealtimeDispatchPrompt?
    @Published private(set) var dispatchDiagnostic: WSDispatchDiagnostic?
    @Published private(set) var currentNotification: RealtimeForegroundNotification?
    @Published private(set) var latestSeparationAlert: RealtimeSeparationAlert?
    @Published private(set) var latestSafetyEvent: RealtimeSafetyEvent?

    /// 最近一次（实时推送或重连补读）看到的通知 ISO-8601 timestamp。
    /// 作为 `GET /api/notifications/since?after=` 的游标，由 `AppState` 持久化。
    private(set) var lastObservedNotificationTimestamp: String?

    private let peerLocationSubject = PassthroughSubject<RealtimePeerLocationSample, Never>()
    private let recoverySubject = PassthroughSubject<RealtimeRecoverySignal, Never>()
    private let statusUpdateSubject = PassthroughSubject<RealtimeOrderStatusUpdate, Never>()
    var peerLocationPublisher: AnyPublisher<RealtimePeerLocationSample, Never> { peerLocationSubject.eraseToAnyPublisher() }
    var recoveryPublisher: AnyPublisher<RealtimeRecoverySignal, Never> { recoverySubject.eraseToAnyPublisher() }
    var statusUpdatePublisher: AnyPublisher<RealtimeOrderStatusUpdate, Never> {
        statusUpdateSubject.eraseToAnyPublisher()
    }

    private weak var attachedService: WebSocketService?
    private var attachedRole: WSRole?
    private var eventCancellable: AnyCancellable?
    private var connectionCancellable: AnyCancellable?
    private var dispatchDiagnosticCancellable: AnyCancellable?
    private var notificationTask: Task<Void, Never>?
    private var dispatchExpiryTask: Task<Void, Never>?
    private var orderRefreshRetryTasks: [Int64: Task<Void, Never>] = [:]
    private var orderRefreshRetryCounts: [Int64: Int] = [:]
    private var queuedNotifications: [RealtimeForegroundNotification] = []
    private var deduplicationDates: [String: Date] = [:]
    private var activeOrderIDs: Set<Int64> = []
    private var activeOrderStatuses: [Int64: RunOrderStatus] = [:]
    private var orderStatusReconciler = OrderStatusReconciler()
    private var retainedOrderStatusIdentities: [String: RetainedOrderStatusIdentity] = [:]
    private var retainedOrderStatusIdentityOrder: [String] = []
    private var recentLifecycleStatusDates: [RunOrderStatus: Date] = [:]
    private var latestPeerSamples: [String: RealtimePeerLocationSample] = [:]
    private var peerPublishTasks: [String: Task<Void, Never>] = [:]
    private var hasConnectedOnce = false
    private let now: () -> Date
    private let notificationDuration: TimeInterval
    private let deduplicationWindow: TimeInterval
    private let orderRefreshRetryDelays: [TimeInterval]
    private let maximumQueuedNotifications: Int
    private let maximumDeduplicationEntries = 128
    private let maximumOrderStatusIdentities = 256
    private let lifecycleNotificationSuppressionWindow: TimeInterval = 30

    #if DEBUG
    private(set) var attachmentCount = 0

    func simulateIncomingEventForTesting(_ event: WSIncomingEvent) {
        route(event)
    }
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

    func registerActiveOrder(_ orderID: Int64) {
        activeOrderIDs.insert(orderID)
    }

    func registerActiveOrder(_ orderID: Int64, status: RunOrderStatus) {
        activeOrderIDs.insert(orderID)
        orderStatusReconciler.register(orderID: orderID, status: status)
        activeOrderStatuses[orderID] = orderStatusReconciler.currentStatus(orderID: orderID) ?? status
    }

    func unregisterActiveOrder(_ orderID: Int64) {
        activeOrderIDs.remove(orderID)
        orderStatusReconciler.unregister(orderID: orderID)
        activeOrderStatuses.removeValue(forKey: orderID)
        for role in [RealtimePeerRole.blind, .volunteer] {
            let key = peerKey(orderID: orderID, ownerRole: role)
            peerPublishTasks.removeValue(forKey: key)?.cancel()
            latestPeerSamples.removeValue(forKey: key)
        }
    }

    func beginOrderStatusRequest(orderID: Int64) -> OrderStatusRequestToken {
        orderStatusReconciler.requestToken(orderID: orderID)
    }

    func isOrderStatusRequestCurrent(_ token: OrderStatusRequestToken) -> Bool {
        orderStatusReconciler.isCurrent(token)
    }

    /// Returns nil only when the response is associated with the wrong request.
    /// Stale status values are replaced with the already accepted newer status,
    /// while every other decoded detail field remains available to the caller.
    func reconcileOrderDetail(
        _ candidate: OrderDetailResponse,
        requestToken: OrderStatusRequestToken
    ) -> OrderDetailResponse? {
        guard candidate.orderId == requestToken.orderID else {
            ClientFlowDiagnostics.record(event: "wrong_order_rejected", operation: "order-status-rest")
            return nil
        }
        let result = orderStatusReconciler.reconcileREST(
            orderID: candidate.orderId,
            candidate: candidate.status,
            token: requestToken
        )
        guard let resolved = result.resolvedStatus else {
            ClientFlowDiagnostics.record(event: "invalid_rejected", operation: "order-status-rest")
            return nil
        }
        activeOrderStatuses[candidate.orderId] = resolved
        switch result {
        case .rejectedStale:
            ClientFlowDiagnostics.record(event: "late_response_discarded", operation: "order-status-rest")
        case .rejectedInvalid:
            ClientFlowDiagnostics.record(event: "invalid_rejected", operation: "order-status-rest")
        case .applied:
            ClientFlowDiagnostics.record(event: "applied", operation: "order-status-rest")
        case .duplicate:
            break
        }
        return candidate.status == resolved
            ? candidate
            : candidate.replacingStatus(with: resolved)
    }

    func completeOrderRefresh(_ orderID: Int64) {
        orderRefreshRetryTasks.removeValue(forKey: orderID)?.cancel()
        orderRefreshRetryCounts.removeValue(forKey: orderID)
        pendingOrderRefreshIDs.remove(orderID)
        pendingOrderRefreshRequests.removeValue(forKey: orderID)
    }

    func failOrderRefresh(_ orderID: Int64) {
        guard pendingOrderRefreshRequests[orderID] != nil,
              orderRefreshRetryTasks[orderID] == nil else { return }

        pendingOrderRefreshIDs.remove(orderID)
        let retryCount = orderRefreshRetryCounts[orderID, default: 0]
        guard retryCount < orderRefreshRetryDelays.count else {
            completeOrderRefresh(orderID)
            return
        }

        orderRefreshRetryCounts[orderID] = retryCount + 1
        let delay = orderRefreshRetryDelays[retryCount]
        orderRefreshRetryTasks[orderID] = Task { [weak self] in
            let nanos = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self,
                  self.pendingOrderRefreshRequests[orderID] != nil else { return }
            self.orderRefreshRetryTasks.removeValue(forKey: orderID)
            self.pendingOrderRefreshIDs.insert(orderID)
        }
    }

    func clearDispatch(orderID: Int64) {
        guard pendingDispatch?.order.orderId == orderID else { return }
        dispatchExpiryTask?.cancel()
        dispatchExpiryTask = nil
        pendingDispatch = nil
    }

    func markDispatchPresented(orderID: Int64) {
        guard let diagnostic = dispatchDiagnostic,
              diagnostic.orderID == orderID,
              diagnostic.stage == .retained || diagnostic.stage == .received else { return }
        dispatchDiagnostic = diagnostic.advancing(to: .presented, recordedAt: now())
    }

    func latestPeerLocation(orderID: Int64, ownerRole: RealtimePeerRole) -> RealtimePeerLocationSample? {
        latestPeerSamples[peerKey(orderID: orderID, ownerRole: ownerRole)]
    }

    func dismissCurrentNotification() {
        notificationTask?.cancel()
        notificationTask = nil
        currentNotification = nil
        presentNextNotificationIfNeeded()
    }

    private func route(_ event: WSIncomingEvent) {
        switch event {
        case .orderStatusChanged(let message):
            switch retainOrderStatusIdentity(for: message) {
            case .duplicate:
                ClientFlowDiagnostics.record(event: "duplicate_dropped", operation: "order-status-event")
                return
            case .collision:
                ClientFlowDiagnostics.record(event: "identity_collision", operation: "order-status-event")
                requestOrderRefresh(message.orderId, reason: .statusChanged)
                return
            case .process(let messageID):
                if activeOrderIDs.contains(message.orderId),
                   let rawFromStatus = message.fromStatus,
                   let fromStatus = RunOrderStatus(rawValue: rawFromStatus),
                   let toStatus = RunOrderStatus(rawValue: message.toStatus),
                   fromStatus != toStatus {
                    let result = orderStatusReconciler.reconcileRealtime(
                        orderID: message.orderId,
                        fromStatus: fromStatus,
                        toStatus: toStatus
                    )
                    guard case .applied = result else {
                        ClientFlowDiagnostics.record(event: "rejected", operation: "order-status-event")
                        requestOrderRefresh(message.orderId, reason: .statusChanged)
                        return
                    }
                    let update = RealtimeOrderStatusUpdate(
                        messageId: messageID,
                        orderId: message.orderId,
                        fromStatus: fromStatus,
                        toStatus: toStatus,
                        receivedAt: now()
                    )
                    activeOrderStatuses[message.orderId] = toStatus
                    recentLifecycleStatusDates[toStatus] = update.receivedAt
                    ClientFlowDiagnostics.record(event: "applied", operation: "order-status-event")
                    statusUpdateSubject.send(update)
                }
                requestOrderRefresh(message.orderId, reason: .statusChanged)
            }
        case .newOrder(let message):
            retainDispatch(message)
        case .volunteerLocation(let message):
            routePeerLocation(
                RealtimePeerLocationSample(
                    orderId: message.orderId,
                    ownerRole: .volunteer,
                    latitude: message.lat,
                    longitude: message.lng,
                    timestampMilliseconds: message.timestamp
                ),
                expectedReceiver: .blind
            )
        case .blindLocation(let message):
            routePeerLocation(
                RealtimePeerLocationSample(
                    orderId: message.orderId,
                    ownerRole: .blind,
                    latitude: message.lat,
                    longitude: message.lng,
                    timestampMilliseconds: message.timestamp
                ),
                expectedReceiver: .volunteer
            )
        case .notification(let message):
            routeNotification(message)
        case .emergencyResolved(let message):
            routeSafety(
                eventID: String(message.eventId),
                orderID: nil,
                kind: .emergencyResolved,
                displayText: message.message ?? "紧急事件已由志愿者确认",
                speechText: message.ttsText ?? message.message ?? "紧急事件已由志愿者确认",
                timestamp: message.timestamp
            )
        case .emergencyAlert(let message):
            routeSafety(
                eventID: String(message.eventId),
                orderID: message.orderId,
                kind: .emergencyVolunteerAlert,
                displayText: message.message ?? "关联服务出现安全事件",
                speechText: message.ttsText ?? message.message ?? "关联服务出现安全事件",
                timestamp: message.timestamp
            )
        case .pong, .unknown:
            break
        }
    }

    private func requestOrderRefresh(_ orderID: Int64, reason: RealtimeOrderRefreshRequest.Reason) {
        orderRefreshRetryTasks.removeValue(forKey: orderID)?.cancel()
        guard !pendingOrderRefreshIDs.contains(orderID) else { return }
        pendingOrderRefreshIDs.insert(orderID)
        pendingOrderRefreshRequests[orderID] = RealtimeOrderRefreshRequest(orderId: orderID, reason: reason)
    }

    private func retainDispatch(_ message: WSNewOrder) {
        guard attachedRole == nil || attachedRole == .volunteer else { return }
        guard pendingDispatch == nil else { return }
        let receivedAt = now()
        let timeout = max(0, message.dispatchTimeoutSeconds ?? 30)
        let sentAt = Self.parseISO8601(message.timestamp) ?? receivedAt
        let expiresAt = sentAt.addingTimeInterval(TimeInterval(timeout))
        guard expiresAt > receivedAt else { return }
        pendingDispatch = RealtimeDispatchPrompt(order: message, receivedAt: receivedAt, expiresAt: expiresAt)
        if let diagnostic = dispatchDiagnostic,
           diagnostic.orderID == message.orderId,
           diagnostic.stage == .received {
            dispatchDiagnostic = diagnostic.advancing(to: .retained, recordedAt: receivedAt)
        }
        dispatchExpiryTask?.cancel()
        dispatchExpiryTask = Task { [weak self] in
            let nanos = UInt64(max(0, expiresAt.timeIntervalSince(receivedAt)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self, self.pendingDispatch?.order.orderId == message.orderId else { return }
            self.pendingDispatch = nil
        }
    }

    private func routePeerLocation(_ sample: RealtimePeerLocationSample, expectedReceiver: WSRole) {
        guard (attachedRole == nil || attachedRole == expectedReceiver), sample.isValid else { return }
        guard activeOrderIDs.contains(sample.orderId) else { return }
        let key = peerKey(orderID: sample.orderId, ownerRole: sample.ownerRole)
        if let previous = latestPeerSamples[key],
           previous.timestampMilliseconds >= sample.timestampMilliseconds {
            return
        }
        latestPeerSamples[key] = sample
        guard peerPublishTasks[key] == nil else {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "peer-location-event")
            return
        }
        peerPublishTasks[key] = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, let latest = self.latestPeerSamples[key] else { return }
            self.peerLocationSubject.send(latest)
            self.peerPublishTasks.removeValue(forKey: key)
        }
    }

    private func routeNotification(_ message: WSAppNotification) {
        // 记录最近一次通知的 ISO-8601 timestamp，供重连补读作为 `after` 参数
        // （与后端 `notification_logs.sent_at` 同格式）。escort 分支同样要推进，
        // 否则重连后会把已经播报过的告警再补读一遍。
        recordObservedNotificationTimestamp(message.timestamp)
        let eventType = message.eventType.uppercased()
        if eventType == "ESCORT_DISTANCE_ALERT" || eventType == "ESCORT_SIGNAL_LOST" {
            routeEscortAlert(message, eventType: eventType)
            return
        }
        if let kind = Self.emergencyKind(forEventType: eventType) {
            routeEmergencyNotification(message, kind: kind)
            return
        }
        let speechText = message.ttsText?.nilIfBlank ?? message.body
        guard !message.body.trimmed.isEmpty else { return }
        if shouldSuppressLifecycleNotification(eventType: eventType) { return }
        let notification = RealtimeForegroundNotification(
            stableEventID: message.messageId ?? message.eventId.map(String.init),
            title: message.title,
            displayText: message.body,
            speechText: speechText,
            priority: Self.clientPriority(forEventType: eventType, serverPriority: message.priority),
            timestamp: message.timestamp,
            isSafetyEvent: Self.isSafetyEventType(eventType)
        )
        enqueue(notification, type: message.type)
    }

    /// 展示优先级。默认照后端模板给的 `priority`，**只有一条例外**。
    ///
    /// `ORDER_OVERDUE`（陪跑超过约定结束时间）在后端盲人侧模板里是 `NORMAL`
    /// （`websocket-protocol.md:158`；志愿者侧同一个 eventType 是 `HIGH`，见 `:451`）。
    /// `NORMAL` 在这里的后果是它**排在派单进度那类通知后面**，用蓝色铃铛、不带 header trait。
    /// 而这条告警的语义是「跑者可能失联」—— 后端 N63 的复盘逐字写着：修复前失联和
    /// 「跑完了忘了点结束」在系统里长得一模一样，对看不见屏幕的人是安全缺口不是体验问题。
    ///
    /// 后端 2026-08-13 的通报把这件事划成了我们的边界：「播报文案和打断策略是你们的设计边界，
    /// 不自己改」。所以在这里抬，不去改后端模板。
    ///
    /// ⚠️ **这只影响 App 在前台时的横幅与播报顺序，改不了推送能不能到达。**
    /// 后端只对模板 `priority == HIGH` 的通知补发 APNs（`NotificationService.java:134`），
    /// 判据是模板值不是客户端的展示值 —— 所以盲人端 App 不在前台时**这条告警根本收不到**。
    /// 那一半只能后端把模板提到 HIGH，已投 handoff。别以为抬了这一下就补上了。
    static func clientPriority(forEventType eventType: String, serverPriority: String?) -> RealtimePriority {
        if eventType == "ORDER_OVERDUE" { return .high }
        return RealtimePriority(rawValue: serverPriority)
    }

    private func retainOrderStatusIdentity(
        for message: WSOrderStatusChanged
    ) -> OrderStatusIdentityDecision {
        guard let rawMessageID = message.messageId?.nilIfBlank else {
            ClientFlowDiagnostics.record(event: "missing_id", operation: "order-status-contract")
            return .process(messageID: nil)
        }
        guard let uuid = UUID(uuidString: rawMessageID) else {
            ClientFlowDiagnostics.record(event: "invalid_id", operation: "order-status-contract")
            return .process(messageID: nil)
        }

        let key = uuid.uuidString
        let fingerprint = OrderStatusEventFingerprint(
            orderID: message.orderId,
            fromStatus: message.fromStatus,
            toStatus: message.toStatus
        )
        if let retained = retainedOrderStatusIdentities[key] {
            switch retained {
            case .fingerprint(let previous) where previous == fingerprint:
                return .duplicate
            case .fingerprint:
                retainedOrderStatusIdentities[key] = .collision
                return .collision
            case .collision:
                return .duplicate
            }
        }

        retainedOrderStatusIdentities[key] = .fingerprint(fingerprint)
        retainedOrderStatusIdentityOrder.append(key)
        while retainedOrderStatusIdentityOrder.count > maximumOrderStatusIdentities {
            let expired = retainedOrderStatusIdentityOrder.removeFirst()
            retainedOrderStatusIdentities.removeValue(forKey: expired)
        }
        return .process(messageID: rawMessageID)
    }

    /// 订单页自己会播状态变化，所以「跟状态变化说同一件事」的那几条通知不再重复播一遍。
    ///
    /// **判据是 `eventType`，不是正文文案。** 2026-08-09 之前这里匹配的是一张中文片段表
    /// （「已接单」「重新匹配」……），代价是后端改任何一条模板的正文都会**静默**改变 iOS 的播报行为。
    /// 它已经咬过一次：后端新增的 `REMATCH_ACCEPTED`（正文「已为您**重新匹配**志愿者{name}」）
    /// 命中片段「重新匹配」被整条吞掉，而重匹配成功时用户必然有活跃订单 ——
    /// 于是「换了个志愿者」这件事在 iOS 上一个字都没播出去。
    ///
    /// 顺带修掉的另一处：`ORDER_ACCEPTED` 的正文含「正在确认行程」，旧表把它同时算成
    /// `.pendingAccept` 和 `.rematching` 两个状态。
    ///
    /// ⚠️ **未知 `eventType` 一律不抑制**（`lifecycleStatus` 返回 nil），这是有意的默认方向：
    /// 后端加了新通知而这张表没跟上时，盲人**多听一遍**好过**一个字都听不到**。
    private func shouldSuppressLifecycleNotification(eventType: String) -> Bool {
        guard let status = Self.lifecycleStatus(forEventType: eventType) else { return false }
        if !activeOrderIDs.isEmpty { return true }

        let cutoff = now().addingTimeInterval(-lifecycleNotificationSuppressionWindow)
        recentLifecycleStatusDates = recentLifecycleStatusDates.filter { $0.value >= cutoff }
        return recentLifecycleStatusDates[status] != nil
    }

    /// 该不该按「安全提醒」呈现（队列裁剪时最后被丢、抢占正在显示的 NORMAL 横幅）。
    ///
    /// 这不是求助事件（那条走 `emergencyKind`，还会落 `latestSafetyEvent`、驱动求助 UI），
    /// 只是**呈现强度**。后端把 `priority` 给到 HIGH 就到边界了，剩下的是端上的事
    /// （后端 2026-08-15 原话：「具体做成什么样是你们的决定，我们不越界」）。
    ///
    /// `REMATCHING_MID_RUN`：志愿者在**已经出发之后**取消（`DRIVER_EN_ROUTE` /
    /// `DRIVER_ARRIVED` / `IN_PROGRESS`），盲人很可能正独自在户外，而他看不见身边还有没有人。
    /// 同一件事在派单等待期取消走的是 `REMATCHING`(NORMAL) —— 那时人还没出门，
    /// 一起提上来只会制造噪音，而噪音会让真正紧急的那条被忽略。
    ///
    /// 🔴 **本表里的每一条都绝对不能进 `lifecycleStatus(forEventType:)` 那张表。**
    /// `shouldSuppressLifecycleNotification` 的第一条就是「有活跃订单 ⇒ 抑制」，
    /// 而这些通知发生时**必然**有活跃订单 ⇒ 一旦映射进去就是 100% 静默吞掉，
    /// 恰好是后端拆出这些档想避免的后果。未知 `eventType` 不抑制的默认方向在这里正好是对的，
    /// 所以这里只加呈现强度、不加状态映射。
    ///
    /// 无进展看门狗三条（后端 2026-09-04 新增，架构复核 S-2 / `ISSUES.md` N127 / 迁移 `0038`）：
    ///
    /// - `ORDER_DEPARTURE_STALLED` —— 志愿者接了单，但计划开始时间过了还没点「出发」⇒ 判失联。
    ///   🚨 **不是 `REMATCHING` 的同义词，别合并分支。** 两者都以订单转入 `REMATCHING` 收场，
    ///   但 `REMATCHING` 是志愿者**主动点了取消**（NORMAL，不补 APNs）；这一条是他**接了单之后
    ///   再无动静**（HIGH，补 APNs），触发的那一刻盲人正站在起跑点等着。紧跟着还会来一条
    ///   `ORDER_STATUS_CHANGED`(→`REMATCHING`)，而 `.rematching` 的本地播报是中性的
    ///   「正在确认志愿者状态，请稍候」—— 缺了这一条，「为什么没人来」就没有任何人告诉他。
    /// - `ORDER_ARRIVAL_STALLED` —— 志愿者标了「已到达」却迟迟没点「开始服务」，多半是没碰上头。
    ///   **双方各收一条、文案不同**（后端按 `TargetRole` 分模板），两端都在引导打电话，
    ///   而 `DRIVER_ARRIVED` 这一态两侧都有拨号入口，所以这条通知落地是有动作的。
    /// - `EMERGENCY_UNATTENDED` —— SOS 触发后长时间没推进到结案。要说的是「别再干等，
    ///   自己拨 120/110」，后端点名**不要做成普通提示**。
    ///
    /// ⚠️ `EMERGENCY_UNATTENDED` **刻意不走 `emergencyKind`**：那条链路会落 `latestSafetyEvent`
    /// 并驱动 `EmergencyCoordinator.apply` 改求助状态机，而这条事件本身不改变求助的任何状态
    /// （它是催办，不是新事实）。混进去只会让状态机按一条没有权威来源的事件跳档。
    /// 同理它的文案照后端原样播 —— 后端刻意没写「有没有人接手」（它同时覆盖「真的没人接手」
    /// 与「客服已接手但迟迟没结案」，写死任一种在另一种下就是假话），**客户端也不许自己补这句**。
    static func isSafetyEventType(_ eventType: String) -> Bool {
        switch eventType {
        case "REMATCHING_MID_RUN",
             "ORDER_DEPARTURE_STALLED",
             "ORDER_ARRIVAL_STALLED",
             "EMERGENCY_UNATTENDED":
            return true
        default:
            return false
        }
    }

    static func emergencyKind(forEventType eventType: String) -> RealtimeSafetyEvent.Kind? {
        switch eventType {
        case "EMERGENCY_TRIGGERED": return .emergencyTriggered
        case "EMERGENCY_CONTACT_NOTIFIED": return .emergencyContactNotified
        case "EMERGENCY_NO_CONTACT": return .emergencyNoContact
        case "EMERGENCY_VOLUNTEER_TIMEOUT": return .emergencyVolunteerTimeout
        case "EMERGENCY_TRIGGERED_BY_VOLUNTEER": return .emergencyTriggeredByVolunteer
        case "EMERGENCY_CONTACT_SMS_DELIVERED": return .emergencyContactSmsDelivered
        case "EMERGENCY_CONTACT_NOTIFY_FAILED": return .emergencyContactNotifyFailed
        case "EMERGENCY_VOLUNTEER_ACK": return .emergencyVolunteerAck
        case "EMERGENCY_CLOSED_RESOLVED": return .emergencyClosedResolved
        case "EMERGENCY_CLOSED_FALSE_ALARM": return .emergencyClosedFalseAlarm
        default: return nil
        }
    }

    /// Emergency copy is always the client's own, never the backend's notification body.
    ///
    /// The backend template for `EMERGENCY_CONTACT_NOTIFIED` reads "已通知紧急联系人{contactName}"
    /// / "已通知你的联系人{contactName}，请保持冷静" (`demo/src/main/resources/data.sql:72`). It is
    /// pushed synchronously inside the trigger transaction, strictly before the SMS is handed to
    /// the provider (`EmergencyService.java:370-373` vs `EmergencyContactNotifier.java:60-62`), and
    /// an SMS failure is never corrected back to the blind runner (`:126-135`). Rendering that text
    /// verbatim would tell a blind user their family already knows, which is the one thing the app
    /// must not do. Local progressive-tense copy is substituted for every emergency event type.
    static func emergencyCopy(for kind: RealtimeSafetyEvent.Kind) -> String? {
        switch kind {
        case .emergencyTriggered: return EmergencySafetyCopy.triggeredAcknowledged
        case .emergencyContactNotified: return EmergencySafetyCopy.contactNotified
        case .emergencyNoContact: return EmergencySafetyCopy.noContact
        case .emergencyVolunteerTimeout: return EmergencySafetyCopy.volunteerTimeout
        case .emergencyTriggeredByVolunteer: return EmergencySafetyCopy.triggeredByVolunteer
        // 唯一允许完成时的一句，依据是运营商回执，不是「已发起」。
        case .emergencyContactSmsDelivered: return EmergencySafetyCopy.contactSmsDelivered
        case .emergencyContactNotifyFailed: return EmergencySafetyCopy.contactNotifyFailed
        case .emergencyVolunteerAck: return EmergencySafetyCopy.volunteerAcknowledged
        case .emergencyClosedResolved: return EmergencySafetyCopy.closedResolved
        case .emergencyClosedFalseAlarm: return EmergencySafetyCopy.closedFalseAlarm
        case .emergencyResolved, .emergencyVolunteerAlert: return nil
        }
    }

    private func routeEmergencyNotification(_ message: WSAppNotification, kind: RealtimeSafetyEvent.Kind) {
        // `APP_NOTIFICATION` carries no `eventId`; `messageId` is the only stable identity the
        // backend provides here (`buildEnvelope`), and it is what escort alerts already dedupe on.
        let eventID = message.messageId?.nilIfBlank
            ?? message.eventId.map(String.init)
            ?? message.timestamp
            ?? kind.rawValue
        let copy = Self.emergencyCopy(for: kind) ?? message.body
        routeSafety(
            eventID: eventID,
            orderID: nil,
            kind: kind,
            displayText: copy,
            speechText: copy,
            timestamp: message.timestamp
        )
    }

    private func routeEscortAlert(_ message: WSAppNotification, eventType: String) {
        guard message.priority?.uppercased() == "HIGH",
              let messageID = message.messageId?.nilIfBlank,
              UUID(uuidString: messageID) != nil else { return }
        let inProgress = activeOrderStatuses.compactMap { key, value in
            value == .inProgress ? key : nil
        }
        guard inProgress.count == 1, let orderID = inProgress.first else { return }

        let event = RealtimeSeparationAlert(
            eventID: messageID,
            orderID: orderID,
            eventType: eventType,
            distanceMeters: nil,
            displayText: message.body,
            speechText: message.ttsText ?? message.body,
            timestamp: message.timestamp
        )
        latestSeparationAlert = event
        enqueue(
            RealtimeForegroundNotification(
                stableEventID: "escort:\(messageID)",
                title: message.title?.nilIfBlank ?? "安全提醒",
                displayText: event.displayText,
                speechText: event.speechText,
                priority: .high,
                timestamp: event.timestamp,
                isSafetyEvent: true
            ),
            type: eventType
        )
    }

    /// 游标只前进不后退：补读结果乱序或后端补发旧记录时，不能把 `after` 推回过去。
    private func recordObservedNotificationTimestamp(_ timestamp: String?) {
        guard let timestamp = timestamp?.nilIfBlank else { return }
        guard let current = lastObservedNotificationTimestamp else {
            lastObservedNotificationTimestamp = timestamp
            return
        }
        if timestamp > current { lastObservedNotificationTimestamp = timestamp }
    }

    /// 重连补读：把 `/api/notifications/since` 返回的遗漏通知按时间正序喂回前台队列，
    /// 复用既有的优先级排队与去重逻辑（去重键用数据库主键，和实时推送的 messageId 不会互撞）。
    ///
    /// 注意：后端只保证 24h/50 条窗口，重复投递同一条时 id 相同，因此 `missed:<id>` 足够防重。
    func ingestCatchUp(_ notifications: [MissedNotificationResponse]) {
        let sorted = notifications.sorted { ($0.sentAt ?? "") < ($1.sentAt ?? "") }
        for missed in sorted {
            recordObservedNotificationTimestamp(missed.sentAt)
            guard !missed.body.trimmed.isEmpty else { continue }
            let speechText = missed.ttsText?.nilIfBlank ?? missed.body
            enqueue(
                RealtimeForegroundNotification(
                    stableEventID: "missed:\(missed.id)",
                    title: nil,
                    displayText: missed.body,
                    speechText: speechText,
                    // 补读走同一条抬优先级的规则。断线期间错过的 `ORDER_OVERDUE` 恰恰是最该
                    // 被听见的那条 —— 重连时它已经迟了，再排在派单进度后面就更迟。
                    priority: Self.clientPriority(
                        forEventType: (missed.eventType ?? "").uppercased(),
                        serverPriority: missed.priority
                    ),
                    timestamp: missed.sentAt,
                    // 补读同样按类型判呈现强度。断线期间错过的 `REMATCHING_MID_RUN` 是这批里
                    // 最该被听见的一条 —— 它意味着盲人当时已经独自在户外，而他到现在都不知道。
                    isSafetyEvent: Self.isSafetyEventType((missed.eventType ?? "").uppercased())
                ),
                type: WSMessageType.appNotification.rawValue
            )
        }
    }

    private func routeSafety(
        eventID: String,
        orderID: Int64?,
        kind: RealtimeSafetyEvent.Kind,
        displayText: String,
        speechText: String,
        timestamp: String?
    ) {
        let event = RealtimeSafetyEvent(
            eventID: eventID,
            orderID: orderID,
            kind: kind,
            displayText: displayText,
            speechText: speechText,
            timestamp: timestamp
        )
        latestSafetyEvent = event
        enqueue(
            RealtimeForegroundNotification(
                stableEventID: "\(kind.rawValue):\(eventID)",
                title: "安全提醒",
                displayText: displayText,
                speechText: speechText,
                priority: .high,
                timestamp: timestamp,
                isSafetyEvent: true
            ),
            type: kind.rawValue
        )
    }

    private func enqueue(_ notification: RealtimeForegroundNotification, type: String) {
        let key = notification.stableEventID ?? Self.fallbackDeduplicationKey(
            type: type,
            text: notification.displayText,
            timestamp: notification.timestamp
        )
        guard shouldPresent(deduplicationKey: key) else { return }

        if notification.priority == .high, currentNotification?.priority == .normal {
            if let currentNotification { queuedNotifications.insert(currentNotification, at: 0) }
            trimNotificationQueueIfNeeded()
            notificationTask?.cancel()
            currentNotification = notification
            scheduleNotificationDismissal()
            return
        }
        if notification.priority == .high,
           let firstNormalIndex = queuedNotifications.firstIndex(where: { $0.priority == .normal }) {
            queuedNotifications.insert(notification, at: firstNormalIndex)
        } else {
            queuedNotifications.append(notification)
        }
        trimNotificationQueueIfNeeded()
        presentNextNotificationIfNeeded()
    }

    private func trimNotificationQueueIfNeeded() {
        while queuedNotifications.count > maximumQueuedNotifications {
            if let normalIndex = queuedNotifications.firstIndex(where: { $0.priority == .normal }) {
                queuedNotifications.remove(at: normalIndex)
            } else if let nonSafetyIndex = queuedNotifications.firstIndex(where: { !$0.isSafetyEvent }) {
                queuedNotifications.remove(at: nonSafetyIndex)
            } else {
                queuedNotifications.removeFirst()
            }
        }
    }

    private func shouldPresent(deduplicationKey: String) -> Bool {
        let date = now()
        deduplicationDates = deduplicationDates.filter { date.timeIntervalSince($0.value) <= deduplicationWindow }
        if deduplicationDates[deduplicationKey] != nil { return false }
        deduplicationDates[deduplicationKey] = date
        if deduplicationDates.count > maximumDeduplicationEntries,
           let oldest = deduplicationDates.min(by: { $0.value < $1.value })?.key {
            deduplicationDates.removeValue(forKey: oldest)
        }
        return true
    }

    private func presentNextNotificationIfNeeded() {
        guard currentNotification == nil, !queuedNotifications.isEmpty else { return }
        currentNotification = queuedNotifications.removeFirst()
        scheduleNotificationDismissal()
    }

    private func scheduleNotificationDismissal() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, self?.notificationDuration ?? 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissCurrentNotification()
        }
    }

    private func handleConnectionState(_ state: WSConnectionState) {
        let wasConnected = connectionState == .connected
        connectionState = state
        guard state == .connected else { return }
        if hasConnectedOnce && !wasConnected, let attachedRole {
            for orderID in activeOrderIDs { requestOrderRefresh(orderID, reason: .reconnected) }
            recoverySubject.send(RealtimeRecoverySignal(role: attachedRole, connectedAt: now()))
        }
        hasConnectedOnce = true
    }

    private func clearInMemoryState() {
        notificationTask?.cancel()
        dispatchExpiryTask?.cancel()
        for task in orderRefreshRetryTasks.values { task.cancel() }
        for task in peerPublishTasks.values { task.cancel() }
        notificationTask = nil
        dispatchExpiryTask = nil
        orderRefreshRetryTasks = [:]
        orderRefreshRetryCounts = [:]
        pendingOrderRefreshIDs = []
        pendingOrderRefreshRequests = [:]
        pendingDispatch = nil
        dispatchDiagnostic = nil
        currentNotification = nil
        latestSeparationAlert = nil
        latestSafetyEvent = nil
        // 换账号/登出后不能把上一个用户的补读游标带过去。
        lastObservedNotificationTimestamp = nil
        queuedNotifications = []
        deduplicationDates = [:]
        activeOrderIDs = []
        activeOrderStatuses = [:]
        orderStatusReconciler.removeAll()
        retainedOrderStatusIdentities = [:]
        retainedOrderStatusIdentityOrder = []
        recentLifecycleStatusDates = [:]
        latestPeerSamples = [:]
        peerPublishTasks = [:]
    }

    private func peerKey(orderID: Int64, ownerRole: RealtimePeerRole) -> String {
        "\(orderID):\(ownerRole.rawValue)"
    }

    /// 通知 `eventType` → 它宣布的订单状态。返回 nil 表示「这条不是状态变化的重复播报」，一律照播。
    ///
    /// 常量取自后端 `docs/websocket-protocol.md` §2.2（盲人端）与 §3.2（志愿者端）事件表 ——
    /// 那份表明写着「不应依赖 body/ttsText 文案匹配」，这里就是照它办。
    ///
    /// **刻意不在表里的，每一条都有理由：**
    /// - `REMATCH_ACCEPTED` —— 状态与 `ORDER_ACCEPTED` 同为 `PENDING_ACCEPT`，但订单页两次念的是
    ///   同一句「志愿者已接单」，既没有「重新」也没有新志愿者的名字。抑制它，用户就分不出
    ///   这是新人还是原来那个 —— 而他刚被告知上一个志愿者取消了。这条**必须播**。
    /// - `DISPATCH_STARTED` / `DISPATCH_EXPANDING` / `REMATCH_TIMEOUT` /
    ///   `ORDER_CANCELLATION_WARNING` / `ORDER_OVERDUE` —— **不改订单状态**，订单页不会播。
    ///   抑制它们等于让派单期（最长 30 分钟、3 轮扩圈）整段静音。
    /// - `ROUTE_CONFIRM_REQUIRED*` / `PROXIMITY_ALERT` / `CERT_*` / `ID_VERIFY_*` ——
    ///   与订单状态无关，本来就不该进这条闸。
    static func lifecycleStatus(forEventType eventType: String) -> RunOrderStatus? {
        switch eventType {
        case "ORDER_ACCEPTED": return .pendingAccept
        case "DRIVER_EN_ROUTE": return .driverEnRoute
        case "DRIVER_ARRIVED": return .driverArrived
        case "ORDER_COMPLETED": return .completed
        case "ORDER_AUTO_CANCELLED", "ORDER_CANCELLED_BY_BLIND": return .cancelled
        case "REMATCHING": return .rematching
        case "NO_VOLUNTEER_AVAILABLE": return .noVolunteer
        default: return nil
        }
    }

    private static func fallbackDeduplicationKey(type: String, text: String, timestamp: String?) -> String {
        let normalized = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined()
        let timeBucket = parseISO8601(timestamp).map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "no-time"
        return "\(type)|\(normalized)|\(timeBucket)"
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value) ?? ISO8601DateFormatter.withoutFractionalSeconds.date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct RealtimeForegroundNotificationBanner: View {
    let notification: RealtimeForegroundNotification
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.priority == .high ? "exclamationmark.triangle.fill" : "bell.fill")
                .foregroundColor(notification.priority == .high ? AppColors.destructive : AppColors.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let title = notification.title?.nilIfBlank {
                    Text(title).font(AppFonts.body().weight(.bold))
                }
                Text(notification.displayText).font(AppFonts.body())
            }
            Spacer(minLength: 8)
            Button("关闭", action: onDismiss)
                .accessibilityHint("关闭当前通知并显示下一条通知")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(notification.priority == .high ? AppColors.destructive : AppColors.primary, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notification.speechText)
        .accessibilityAddTraits(notification.priority == .high ? .isHeader : [])
        .accessibilityIdentifier("realtimeForegroundNotification")
    }
}
