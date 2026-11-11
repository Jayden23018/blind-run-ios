import Combine
import Foundation
import SwiftUI

extension AppRealtimeCoordinator {
    func handleConnectionState(_ state: WSConnectionState) {
        let wasConnected = connectionState == .connected
        connectionState = state
        guard state == .connected else { return }
        if hasConnectedOnce && !wasConnected, let attachedRole {
            for orderID in activeOrderIDs { requestOrderRefresh(orderID, reason: .reconnected) }
            recoverySubject.send(RealtimeRecoverySignal(role: attachedRole, connectedAt: now()))
        }
        hasConnectedOnce = true
    }

    func clearInMemoryState() {
        notificationTask?.cancel()
        for task in dispatchExpiryTasks.values { task.cancel() }
        for task in orderRefreshRetryTasks.values { task.cancel() }
        for task in peerPublishTasks.values { task.cancel() }
        notificationTask = nil
        dispatchExpiryTasks = [:]
        retiredInvites = RetiredInviteLedger()
        orderRefreshRetryTasks = [:]
        orderRefreshRetryCounts = [:]
        pendingOrderRefreshIDs = []
        pendingOrderRefreshRequests = [:]
        pendingDispatches = []
        dispatchDiagnostic = nil
        currentNotification = nil
        latestSeparationAlert = nil
        latestSafetyEvent = nil
        dispatchProgressTask?.cancel()
        dispatchProgressTask = nil
        dispatchProgressAnnouncement = nil
        widenedDispatchOrderIDs = []
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

    func peerKey(orderID: Int64, ownerRole: RealtimePeerRole) -> String {
        "\(orderID):\(ownerRole.rawValue)"
    }

    static func fallbackDeduplicationKey(type: String, text: String, timestamp: String?) -> String {
        let normalized = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined()
        let timeBucket = parseISO8601(timestamp).map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "no-time"
        return "\(type)|\(normalized)|\(timeBucket)"
    }

    static func parseISO8601(_ value: String?) -> Date? {
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
