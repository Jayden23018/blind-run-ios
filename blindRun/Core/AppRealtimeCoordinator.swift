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
        case .pendingMatch: return 0
        case .pendingAccept, .rematching: return 1
        case .driverEnRoute: return 2
        case .driverArrived: return 3
        case .inProgress: return 4
        case .completed, .cancelled, .noVolunteer: return 5
        }
    }

    func isDirectlyFollowed(by candidate: RunOrderStatus) -> Bool {
        switch self {
        case .pendingMatch:
            return [.pendingAccept, .cancelled, .noVolunteer].contains(candidate)
        case .pendingAccept:
            return [.driverEnRoute, .cancelled, .rematching].contains(candidate)
        case .driverEnRoute:
            return [.driverArrived, .rematching].contains(candidate)
        case .driverArrived:
            return [.inProgress, .rematching].contains(candidate)
        case .inProgress:
            return [.completed, .rematching].contains(candidate)
        case .rematching:
            return [.pendingAccept, .cancelled, .noVolunteer].contains(candidate)
        case .completed, .cancelled, .noVolunteer:
            return false
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
        // The three below reach iOS as `APP_NOTIFICATION` envelopes carrying an `eventType`, not as
        // top-level WebSocket types (`NotificationService.sendNotification`, :93-99).
        case emergencyTriggered
        case emergencyNoContact
        case emergencyVolunteerTimeout
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
        case .emergencyContactNotified(let message):
            // Documented as a top-level type (`websocket-protocol.md:222-234`) but never emitted as
            // one today — the implementation sends it inside `APP_NOTIFICATION`. Handled anyway, and
            // with the same local copy substitution, so a backend fix cannot silently reintroduce
            // the "已通知你的联系人" claim.
            routeSafety(
                eventID: String(message.eventId),
                orderID: nil,
                kind: .emergencyContactNotified,
                displayText: EmergencySafetyCopy.contactNotified,
                speechText: EmergencySafetyCopy.contactNotified,
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
        if shouldSuppressLifecycleNotification(body: message.body, speechText: speechText) { return }
        let notification = RealtimeForegroundNotification(
            stableEventID: message.messageId ?? message.eventId.map(String.init),
            title: message.title,
            displayText: message.body,
            speechText: speechText,
            priority: RealtimePriority(rawValue: message.priority),
            timestamp: message.timestamp,
            isSafetyEvent: false
        )
        enqueue(notification, type: message.type)
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

    private func shouldSuppressLifecycleNotification(body: String, speechText: String) -> Bool {
        let combinedText = "\(body) \(speechText)"
        guard Self.isLifecycleTemplate(combinedText) else { return false }
        if !activeOrderIDs.isEmpty { return true }

        let cutoff = now().addingTimeInterval(-lifecycleNotificationSuppressionWindow)
        recentLifecycleStatusDates = recentLifecycleStatusDates.filter { $0.value >= cutoff }
        return Self.lifecycleStatuses(matching: combinedText).contains {
            recentLifecycleStatusDates[$0] != nil
        }
    }

    static func emergencyKind(forEventType eventType: String) -> RealtimeSafetyEvent.Kind? {
        switch eventType {
        case "EMERGENCY_TRIGGERED": return .emergencyTriggered
        case "EMERGENCY_CONTACT_NOTIFIED": return .emergencyContactNotified
        case "EMERGENCY_NO_CONTACT": return .emergencyNoContact
        case "EMERGENCY_VOLUNTEER_TIMEOUT": return .emergencyVolunteerTimeout
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
                    priority: RealtimePriority(rawValue: missed.priority),
                    timestamp: missed.sentAt,
                    isSafetyEvent: false
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

    static func isLifecycleTemplate(_ text: String) -> Bool {
        let fragments = [
            "已接单", "待出发", "已出发", "正在前往", "距您", "距出发地点", "已到达",
            "服务已开始", "服务已完成", "订单已完成", "订单已取消", "预约已取消", "已为您匹配",
            "正在确认行程", "志愿者已取消", "重新匹配", "暂无志愿者", "暂无可用志愿者", "暂时没有可用志愿者"
        ]
        return fragments.contains { text.contains($0) }
    }

    private static func lifecycleStatuses(matching text: String) -> Set<RunOrderStatus> {
        var statuses: Set<RunOrderStatus> = []
        let fragments: [(RunOrderStatus, [String])] = [
            (.pendingAccept, ["已接单", "待出发", "已为您匹配"]),
            (.driverEnRoute, ["已出发", "正在前往"]),
            (.driverArrived, ["已到达"]),
            (.inProgress, ["服务已开始"]),
            (.completed, ["服务已完成", "订单已完成"]),
            (.cancelled, ["订单已取消", "预约已取消"]),
            (.rematching, ["正在确认行程", "志愿者已取消", "重新匹配"]),
            (.noVolunteer, ["暂无志愿者", "暂无可用志愿者", "暂时没有可用志愿者"])
        ]
        for (status, candidates) in fragments
        where candidates.contains(where: text.contains) {
            statuses.insert(status)
        }
        return statuses
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
