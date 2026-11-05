import Combine
import Foundation
import SwiftUI

extension AppRealtimeCoordinator {
    /// 重连补读：把 `/api/notifications/since` 返回的遗漏通知按时间正序喂回前台队列，
    /// 复用既有的优先级排队与去重逻辑（去重键用数据库主键，和实时推送的 messageId 不会互撞）。
    ///
    /// 注意：后端只保证 24h/50 条窗口，重复投递同一条时 id 相同，因此 `missed:<id>` 足够防重。
    func ingestCatchUp(_ notifications: [MissedNotificationResponse]) {
        let sorted = notifications.sorted { ($0.sentAt ?? "") < ($1.sentAt ?? "") }
        for missed in sorted {
            recordObservedNotificationTimestamp(missed.sentAt)
            // 补读的 `ORDER_VOLUNTEER_LOST` 不发失联通道（#476）：不带 `orderId`，可能放错另一单。真被转走的那一单
            // 由重连时 `handleConnectionState` 发起的重拉判定（详情 403 → 订单页离开；首页靠摘要刷新）。
            guard !missed.body.trimmed.isEmpty else { continue }
            // 补读走**同一条**正文覆盖。漏掉这里的后果只在断线重连那条路径上出现
            // （最容易漏测、也最难在真机上复现）：屏幕上那行字是替代文案、补读念的却是
            // 后端原文「点击继续等待可延长」。
            let eventType = (missed.eventType ?? "").uppercased()
            if eventType == Self.introCallIncomingEventType, routeIntroCallIncoming(sentAt: missed.sentAt) { continue }
            // 补读不退回「唯一活跃订单」：窗口有 24 小时，不带订单号的旧通知可能属于上一单。
            BlindMidRunDepartureRecord.shared.note(eventType: eventType, orderID: missed.orderId)
            let override = overriddenBody(forEventType: eventType)
            let speechText = override ?? missed.ttsText?.nilIfBlank ?? missed.body
            enqueue(
                RealtimeForegroundNotification(
                    stableEventID: "missed:\(missed.id)",
                    title: nil,
                    displayText: override ?? missed.body,
                    speechText: speechText,
                    // 补读走同一条抬优先级的规则。断线期间错过的 `ORDER_OVERDUE` 恰恰是最该
                    // 被听见的那条 —— 重连时它已经迟了，再排在派单进度后面就更迟。
                    priority: Self.clientPriority(
                        forEventType: eventType,
                        serverPriority: missed.priority
                    ),
                    timestamp: missed.sentAt,
                    // 补读同样按类型判呈现强度。断线期间错过的 `REMATCHING_MID_RUN` 是这批里
                    // 最该被听见的一条 —— 它意味着盲人当时已经独自在户外，而他到现在都不知道。
                    isSafetyEvent: Self.isSafetyEventType(eventType)
                ),
                type: WSMessageType.appNotification.rawValue
            )
        }
    }

    func routeSafety(
        eventID: String,
        orderID: Int64?,
        kind: RealtimeSafetyEvent.Kind,
        displayText: String,
        speechText: String,
        timestamp: String?,
        coordinate: LocatedCoordinate? = nil,
        serverDistanceMeters: Double? = nil
    ) {
        let event = RealtimeSafetyEvent(
            eventID: eventID,
            orderID: orderID,
            kind: kind,
            displayText: displayText,
            speechText: speechText,
            timestamp: timestamp,
            coordinate: coordinate,
            serverDistanceMeters: serverDistanceMeters
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

    func enqueue(_ notification: RealtimeForegroundNotification, type: String) {
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

    func shouldPresent(deduplicationKey: String) -> Bool {
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

    func presentNextNotificationIfNeeded() {
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
}
