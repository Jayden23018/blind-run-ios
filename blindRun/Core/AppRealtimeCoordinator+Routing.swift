import Combine
import Foundation
import SwiftUI

extension AppRealtimeCoordinator {
    func route(_ event: WSIncomingEvent) {
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
                    publishStatusUpdate(update)
                }
                requestOrderRefresh(message.orderId, reason: .statusChanged)
            }
        case .newOrder, .inviteWithdrawn:
            routeInviteEvent(event)
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
                    timestampMilliseconds: message.timestamp,
                    accuracyMeters: message.accuracyM
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
                displayText: message.message ?? "紧急事件已由陪跑员确认",
                speechText: message.ttsText ?? message.message ?? "紧急事件已由陪跑员确认",
                timestamp: message.timestamp
            )
        case .emergencyAlert(let message):
            routeSafety(
                eventID: String(message.eventId),
                orderID: message.orderId,
                kind: .emergencyVolunteerAlert,
                displayText: message.message ?? "关联服务出现安全事件",
                speechText: message.ttsText ?? message.message ?? "关联服务出现安全事件",
                timestamp: message.timestamp,
                // 两个字段任一为 null 就整体没有坐标 —— 只有纬度的「位置」是个陷阱，
                // 而这条链路的下游会拿它算「距你多远」。契约里它们各自可空。
                coordinate: message.gpsLat.flatMap { lat in
                    message.gpsLng.flatMap { BackendCoordinateNormalizer.backend(latitude: lat, longitude: $0) }
                },
                serverDistanceMeters: message.fallbackDistanceMeters
            )
        case .orderEtaUpdated(let message):
            publishLiveUpdate(.eta(orderId: message.orderId, message.eta))
        case .meetDistanceBucket(let message):
            publishLiveUpdate(.meet(orderId: message.orderId, message.meet))
        case .pong, .unknown:
            break
        }
    }

    func requestOrderRefresh(_ orderID: Int64, reason: RealtimeOrderRefreshRequest.Reason) {
        orderRefreshRetryTasks.removeValue(forKey: orderID)?.cancel()
        guard !pendingOrderRefreshIDs.contains(orderID) else { return }
        pendingOrderRefreshIDs.insert(orderID)
        pendingOrderRefreshRequests[orderID] = RealtimeOrderRefreshRequest(orderId: orderID, reason: reason)
        orderLiveTracker.refreshRequested(orderID)
    }

    /// 原有发布 + 交给订单页跟踪（`unify-order-live-tracking` design §2）。
    private func publishStatusUpdate(_ update: RealtimeOrderStatusUpdate) {
        statusUpdateSubject.send(update)
        orderLiveTracker.receiveStatus(update)
    }

    private func publishLiveUpdate(_ update: RealtimeOrderLiveUpdate) {
        orderLiveUpdateSubject.send(update)
        orderLiveTracker.receiveLiveUpdate(update)
    }

    /// 队列上限。**防的是异常堆积，不是产品规则** —— 后端没有「一次最多派几单给一个人」这回事。
    /// 超了就丢最新的那条：队列按期限升序，先到期的更紧急，留着它们比留一条刚来的更有用。
    private static let maxPendingDispatches = 5

    func retainDispatch(_ message: WSNewOrder) {
        guard attachedRole == nil || attachedRole == .volunteer else { return }
        guard !retiredInvites.contains(message, now: now()) else { return }
        // 同一张邀请重发（后端重试 / 快照与推送都带着它）不进第二条。判据是邀请身份而不是整条消息相等：
        // 重发的 `timestamp` 会变，按值去重等于去不掉。
        // 🚩 **身份是 `inviteId`**（后端 #371）：同一张单撤回后可能发来**新的**一张邀请，
        // 那时旧的那条（若还在）让位给新的，而不是把新的当重复丢掉。
        if let index = pendingDispatches.firstIndex(where: { $0.order.orderId == message.orderId }) {
            guard Self.isDifferentInvite(pendingDispatches[index].order, message) else { return }
            dispatchExpiryTasks.removeValue(forKey: message.orderId)?.cancel()
            pendingDispatches.remove(at: index)
        }
        guard pendingDispatches.count < Self.maxPendingDispatches else { return }
        let receivedAt = now()
        let expiresAt = Self.dispatchExpiry(message, receivedAt: receivedAt)
        guard expiresAt > receivedAt else {
            // 到手时就已过期：后端的期限比本机时钟早（时钟误差、或推送在路上太久）。不静默 —— 留一条诊断。
            ClientFlowDiagnostics.record(event: "dropped-expired", operation: "dispatch-retain")
            return
        }
        pendingDispatches.append(
            RealtimeDispatchPrompt(order: message, receivedAt: receivedAt, expiresAt: expiresAt)
        )
        // 按回复期限升序（设计交付 v3 §4.4.2「多个邀请：按回复期限升序」）。
        // 设计稿还有一句「同等期限下一起跑过的跑者优先」—— `NEW_ORDER` 里没有这个字段，
        // **不编一个出来**，已投 handoff。
        pendingDispatches.sort { $0.expiresAt < $1.expiresAt }
        if let diagnostic = dispatchDiagnostic,
           diagnostic.orderID == message.orderId,
           diagnostic.stage == .received {
            dispatchDiagnostic = diagnostic.advancing(to: .retained, recordedAt: receivedAt)
        }
        dispatchExpiryTasks.removeValue(forKey: message.orderId)?.cancel()
        let inviteID = message.inviteId
        dispatchExpiryTasks[message.orderId] = Task { [weak self] in
            let nanos = UInt64(max(0, expiresAt.timeIntervalSince(receivedAt)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.dispatchExpiryTasks.removeValue(forKey: message.orderId)
            self.pendingDispatches.removeAll { $0.order.orderId == message.orderId && $0.order.inviteId == inviteID }
        }
    }

    /// REST 兜底拿到的对方位置。**只入库，不发布。**
    ///
    /// 存在的理由：`LiveEscortSessionCoordinator.freshPeerCoordinate` 只读这个存量
    /// （`latestPeerLocation`）—— 也就是说陪跑途中 WebSocket 一断，走散检测就没有输入了。
    /// 而后端**恰好**在 `IN_PROGRESS` 提供 `GET /api/blind/volunteer-location`
    /// （`sharesLiveLocation()` 的三态之一）：数据一直在，从前只是没人把它接过来。
    ///
    /// 🚩 **刻意不走 `routePeerLocation` 的发布那一半。** 发布会回流到
    /// `BlindOrderStatusViewModel.handleVolunteerLocationUpdate`，把 `latestVolunteerWebSocketDate`
    /// 也一并推新 —— 而那个字段正是「WebSocket 还在给我样本吗」这个判断的依据，
    /// 拿 REST 的结果去喂它，下一轮兜底就会被自己刚写进去的值劝退。
    /// 入库这一半共用 `retainPeerLocation`，所以「只进不退」那条守卫两条路一模一样。
    ///
    /// ⚠️ 调用方必须传**真实采样时刻**（后端的 `updatedAt`），不许拿「现在」凑：
    /// 那会让一个 29 秒前的坐标伪装成刚采的，直接削弱走散检测。
    func ingestFallbackPeerLocation(_ sample: RealtimePeerLocationSample) {
        _ = retainPeerLocation(sample, expectedReceiver: .blind)
    }

    /// 入库并回答「这条样本是不是新的」。抽出来只为一件事：REST 兜底与 WebSocket
    /// 共用同一条「只进不退」的守卫，不各写一份。
    private func retainPeerLocation(
        _ sample: RealtimePeerLocationSample,
        expectedReceiver: WSRole
    ) -> Bool {
        guard (attachedRole == nil || attachedRole == expectedReceiver), sample.isValid else { return false }
        guard activeOrderIDs.contains(sample.orderId) else { return false }
        let key = peerKey(orderID: sample.orderId, ownerRole: sample.ownerRole)
        if let previous = latestPeerSamples[key],
           previous.timestampMilliseconds >= sample.timestampMilliseconds {
            return false
        }
        latestPeerSamples[key] = sample
        return true
    }

    private func routePeerLocation(_ sample: RealtimePeerLocationSample, expectedReceiver: WSRole) {
        guard retainPeerLocation(sample, expectedReceiver: expectedReceiver) else { return }
        let key = peerKey(orderID: sample.orderId, ownerRole: sample.ownerRole)
        guard peerPublishTasks[key] == nil else {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "peer-location-event")
            return
        }
        peerPublishTasks[key] = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, let latest = self.latestPeerSamples[key] else { return }
            self.peerLocationSubject.send(latest)
            self.orderLiveTracker.receivePeerLocation(latest)
            self.peerPublishTasks.removeValue(forKey: key)
        }
    }
}
