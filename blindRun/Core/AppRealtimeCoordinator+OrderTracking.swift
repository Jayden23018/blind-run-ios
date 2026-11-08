import Combine
import Foundation
import SwiftUI

extension AppRealtimeCoordinator {
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
            self.orderLiveTracker.refreshRequested(orderID)
        }
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

    func dismissRunnerRing() {
        runnerRing = nil
    }

    func dismissCurrentNotification() {
        notificationTask?.cancel()
        notificationTask = nil
        currentNotification = nil
        presentNextNotificationIfNeeded()
    }
}
