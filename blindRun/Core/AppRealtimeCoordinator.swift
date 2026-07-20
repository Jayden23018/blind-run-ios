import Combine
import Foundation
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
    @Published private(set) var connectionState: WSConnectionState = .disconnected
    @Published private(set) var pendingOrderRefreshIDs: Set<Int64> = []
    @Published private(set) var pendingOrderRefreshRequests: [Int64: RealtimeOrderRefreshRequest] = [:]
    @Published private(set) var pendingDispatch: RealtimeDispatchPrompt?
    @Published private(set) var currentNotification: RealtimeForegroundNotification?
    @Published private(set) var latestSeparationAlert: RealtimeSeparationAlert?
    @Published private(set) var latestSafetyEvent: RealtimeSafetyEvent?

    private let peerLocationSubject = PassthroughSubject<RealtimePeerLocationSample, Never>()
    private let recoverySubject = PassthroughSubject<RealtimeRecoverySignal, Never>()
    var peerLocationPublisher: AnyPublisher<RealtimePeerLocationSample, Never> { peerLocationSubject.eraseToAnyPublisher() }
    var recoveryPublisher: AnyPublisher<RealtimeRecoverySignal, Never> { recoverySubject.eraseToAnyPublisher() }

    private weak var attachedService: WebSocketService?
    private var attachedRole: WSRole?
    private var eventCancellable: AnyCancellable?
    private var connectionCancellable: AnyCancellable?
    private var notificationTask: Task<Void, Never>?
    private var dispatchExpiryTask: Task<Void, Never>?
    private var orderRefreshRetryTasks: [Int64: Task<Void, Never>] = [:]
    private var orderRefreshRetryCounts: [Int64: Int] = [:]
    private var queuedNotifications: [RealtimeForegroundNotification] = []
    private var deduplicationDates: [String: Date] = [:]
    private var activeOrderIDs: Set<Int64> = []
    private var latestPeerSamples: [String: RealtimePeerLocationSample] = [:]
    private var hasConnectedOnce = false
    private let now: () -> Date
    private let notificationDuration: TimeInterval
    private let deduplicationWindow: TimeInterval
    private let orderRefreshRetryDelays: [TimeInterval]
    private let maximumQueuedNotifications: Int
    private let maximumDeduplicationEntries = 128

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
    }

    func detach(clearSessionState: Bool) {
        eventCancellable?.cancel()
        connectionCancellable?.cancel()
        eventCancellable = nil
        connectionCancellable = nil
        attachedService = nil
        attachedRole = nil
        hasConnectedOnce = false
        connectionState = .disconnected
        if clearSessionState { clearInMemoryState() }
    }

    func registerActiveOrder(_ orderID: Int64) {
        activeOrderIDs.insert(orderID)
    }

    func unregisterActiveOrder(_ orderID: Int64) {
        activeOrderIDs.remove(orderID)
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
            requestOrderRefresh(message.orderId, reason: .statusChanged)
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
        case .separationAlert(let message):
            routeSeparation(message)
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
            routeSafety(
                eventID: String(message.eventId),
                orderID: nil,
                kind: .emergencyContactNotified,
                displayText: message.message ?? "已通知紧急联系人",
                speechText: message.ttsText ?? message.message ?? "已通知紧急联系人",
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
        if let existing = pendingDispatch, existing.order.orderId != message.orderId { return }
        let receivedAt = now()
        let timeout = max(0, message.dispatchTimeoutSeconds ?? 30)
        let sentAt = Self.parseISO8601(message.timestamp) ?? receivedAt
        let expiresAt = sentAt.addingTimeInterval(TimeInterval(timeout))
        guard expiresAt > receivedAt else { return }
        pendingDispatch = RealtimeDispatchPrompt(order: message, receivedAt: receivedAt, expiresAt: expiresAt)
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
        guard activeOrderIDs.isEmpty || activeOrderIDs.contains(sample.orderId) else { return }
        latestPeerSamples[peerKey(orderID: sample.orderId, ownerRole: sample.ownerRole)] = sample
        peerLocationSubject.send(sample)
    }

    private func routeNotification(_ message: WSAppNotification) {
        let speechText = message.ttsText?.nilIfBlank ?? message.body
        guard !message.body.trimmed.isEmpty else { return }
        if !activeOrderIDs.isEmpty && Self.isLifecycleTemplate(speechText) { return }
        let notification = RealtimeForegroundNotification(
            stableEventID: message.eventId.map(String.init),
            title: message.title,
            displayText: message.body,
            speechText: speechText,
            priority: RealtimePriority(rawValue: message.priority),
            timestamp: message.timestamp,
            isSafetyEvent: false
        )
        enqueue(notification, type: message.type)
    }

    private func routeSeparation(_ message: WSSeparationAlert) {
        guard activeOrderIDs.isEmpty || activeOrderIDs.contains(message.orderId) else { return }
        let event = RealtimeSeparationAlert(
            eventID: String(message.eventId),
            orderID: message.orderId,
            distanceMeters: message.distanceMeters,
            displayText: message.message,
            speechText: message.ttsText ?? message.message,
            timestamp: message.timestamp
        )
        latestSeparationAlert = event
        enqueue(
            RealtimeForegroundNotification(
                stableEventID: "separation:\(event.eventID)",
                title: "安全提醒",
                displayText: event.displayText,
                speechText: event.speechText,
                priority: .high,
                timestamp: event.timestamp,
                isSafetyEvent: true
            ),
            type: message.type
        )
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
        notificationTask = nil
        dispatchExpiryTask = nil
        orderRefreshRetryTasks = [:]
        orderRefreshRetryCounts = [:]
        pendingOrderRefreshIDs = []
        pendingOrderRefreshRequests = [:]
        pendingDispatch = nil
        currentNotification = nil
        latestSeparationAlert = nil
        latestSafetyEvent = nil
        queuedNotifications = []
        deduplicationDates = [:]
        activeOrderIDs = []
        latestPeerSamples = [:]
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
