import Combine
import Foundation
import SwiftUI

extension AppRealtimeCoordinator {
    func routeNotification(_ message: WSAppNotification) {
        // 记录最近一次通知的 ISO-8601 timestamp，供重连补读作为 `after` 参数
        // （与后端 `notification_logs.sent_at` 同格式）。escort 分支同样要推进，
        // 否则重连后会把已经播报过的告警再补读一遍。
        recordObservedNotificationTimestamp(message.timestamp)
        let eventType = message.eventType.uppercased()
        if Self.orderRefreshingEventTypes.contains(eventType), let orderId = message.orderId {
            requestOrderRefresh(orderId, reason: .statusChanged)
        }
        if Self.refreshOnlyEventTypes.contains(eventType) { return }
        if eventType == Self.blindStartConfirmedEventType { blindStartConfirmedSubject.send() }
        publishVolunteerLostIfNeeded(eventType: eventType)
        // `backendTimestamp` 而不是 `parseISO8601`：WS 信封的 timestamp 是无时区的 LocalDateTime，
        // ISO8601DateFormatter 解不出来，会让重连补读来的旧提醒一律当成「刚刚」。
        if eventType == Self.introCallIncomingEventType, routeIntroCallIncoming(sentAt: message.timestamp) { return }
        if eventType == "ESCORT_DISTANCE_ALERT" || eventType == "ESCORT_SIGNAL_LOST" {
            routeEscortAlert(message, eventType: eventType)
            return
        }
        if RunnerRingRequest.Kind(eventType: eventType) != nil, routeRunnerRing(message) { return }
        if let kind = Self.emergencyKind(forEventType: eventType) {
            routeEmergencyNotification(message, kind: kind)
            return
        }
        guard !message.body.trimmed.isEmpty else { return }
        // 排在抑制之前：普通 `REMATCHING` 有活跃订单时不播，但它说明这次不算半路退出。
        // 模板通知不带 `orderId` 时，只有一张活跃订单才认得出是哪一单（同 `routeEscortAlert`）。
        BlindMidRunDepartureRecord.shared.note(
            eventType: eventType, orderID: message.orderId ?? (activeOrderIDs.count == 1 ? activeOrderIDs.first : nil)
        )
        if shouldSuppressLifecycleNotification(eventType: eventType) { return }
        let body = overriddenBody(forEventType: eventType) ?? message.body
        // 覆盖时**两条通道一起换**。只换屏幕上那行、让 `ttsText` 照念后端原文，
        // 等于让读屏用户听到的仍是「点击继续等待」——而这条覆盖存在的全部理由就是那句话。
        let speechText = overriddenBody(forEventType: eventType)
            ?? message.ttsText?.nilIfBlank
            ?? message.body
        let notification = RealtimeForegroundNotification(
            stableEventID: message.messageId ?? message.eventId.map(String.init),
            title: message.title,
            displayText: body,
            speechText: speechText,
            priority: Self.clientPriority(forEventType: eventType, serverPriority: message.priority),
            timestamp: message.timestamp,
            isSafetyEvent: Self.isSafetyEventType(eventType)
        )
        enqueue(notification, type: message.type)
    }

    /// `RUNNER_RING` / `RUNNER_RING_LOST` 走响铃，不进横幅（响铃遮罩自己会念那一句，进横幅就念两遍）。
    /// 返回 `false` = 这一条响不了（非盲人端、缺 `until`、已过点），调用方按普通通知念一次。
    /// 同一条重复投递按 `messageId` 丢掉，复用横幅那套去重窗口。
    private func routeRunnerRing(_ message: WSAppNotification) -> Bool {
        guard attachedRole == nil || attachedRole == .blind,
              let ring = RunnerRingRequest.make(from: message, receivedAt: now()) else { return false }
        guard shouldPresent(deduplicationKey: "RUNNER_RING:\(ring.id)") else { return true }
        runnerRing = ring
        return true
    }

    /// 后端正文指向一个**客户端已经没有的控件**时的替代正文；`nil` = 照播后端原文。
    ///
    /// 盲人端 `ORDER_OVERDUE` 见 `BlindRunnerFinishCopy.overdueOverride`。下面说的是另一条：`ORDER_CANCELLATION_WARNING` 的模板正文逐字带着「点击继续等待可延长」，
    /// 而同一个 eventType 覆盖 `PENDING_MATCH` 与 `REMATCHING` 两态，前者那个按钮已删
    /// （`RunOrderStatus.offersBlindRunnerKeepWaitingControl`）。
    ///
    /// 🔴 **判据是「此刻有没有那个按钮」，不是 eventType 本身。** `REMATCHING` 那一侧按钮
    /// 还在，而且那一按是真延长 —— 在那一态改文案会把一条准确且可执行的提示，换成一句
    /// 「去取消订单重新预约」，而重新下单要求 ≥30 分钟提前量。两个方向各有代价，
    /// 所以必须看状态。
    ///
    /// 🚩 **`WSAppNotification` 里没有 `orderId`**（`WebSocketModels.swift` 的字段只有
    /// type / eventId / messageId / eventType / title / body / ttsText / priority / timestamp），
    /// 所以判不出这条预警说的是哪一张单 —— 这是契约的盲区，不是这里的疏漏。
    ///
    /// 已登记的订单可能**同时有两张**：首页登记它那一张、订单详情页登记它那一张，
    /// 而详情页的 `onDisappear` 只 `stopPolling()`、**不 unregister**，所以退出之后那张还在。
    ///
    /// ⇒ 判据取**保守的那一侧**：候选单（`offersKeepWaiting`，也就是这个 eventType 唯一
    /// 可能指向的两态）**全都**有按钮才照播原文；只要有一张没有、或者一张候选都看不到，
    /// 就换成不提按钮的说法。
    ///
    /// **两个方向的代价不对称，所以不能取 `contains`**：多覆盖一次，`REMATCHING` 的用户
    /// 少听到一句「可以点继续等待」（按钮还在屏幕上，他能看见/摸到）；少覆盖一次，
    /// `PENDING_MATCH` 的盲人被明确指去按一个不存在的控件，而他无从判断是自己没找到
    /// 还是它根本不在。后者更贵。
    ///
    /// ⛔ **不许改成匹配正文里的中文片段。** 那正是
    /// `testSuppressionFollowsEventTypeNotBodyText` 钉住的旧实现：后端改一个字，
    /// iOS 的播报行为就静默变一次。
    func overriddenBody(forEventType eventType: String) -> String? {
        guard eventType == "ORDER_CANCELLATION_WARNING" else { return BlindRunnerFinishCopy.overdueOverride(eventType: eventType, role: attachedRole) }
        // 只看这条预警可能指向的那两态，别把 `DRIVER_EN_ROUTE` 这类无关订单算进来 ——
        // 它们既不是候选，也永远没有那个按钮，算进来等于恒定覆盖。
        let candidates = activeOrderStatuses.values.filter(\.offersKeepWaiting)
        let everyCandidateHasTheControl = !candidates.isEmpty
            && candidates.allSatisfy(\.offersBlindRunnerKeepWaitingControl)
        return everyCandidateHasTheControl
            ? nil
            : KeepWaitingCopy.cancellationWarningWithoutControl
    }

    func retainOrderStatusIdentity(
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
    func recordObservedNotificationTimestamp(_ timestamp: String?) {
        guard let timestamp = timestamp?.nilIfBlank else { return }
        guard let current = lastObservedNotificationTimestamp else {
            lastObservedNotificationTimestamp = timestamp
            return
        }
        if timestamp > current { lastObservedNotificationTimestamp = timestamp }
    }
}
