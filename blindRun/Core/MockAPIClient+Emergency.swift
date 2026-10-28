//
//  MockAPIClient+Emergency.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 紧急求助 分段（#500）：那个文件已超 SwiftLint 长度上限，
//  而这一段要加「合并进未结案事件」。存储属性留在类体里（extension 放不了），访问级别随之放宽到 internal。
//

import Foundation

extension MockAPIClient {
    // MARK: - Emergency Handler

    /// Mirrors `EmergencyController.triggerEmergency` after the 2026-07-31 rewrite: escalation to the
    /// emergency contacts happens at trigger time (no 30s serial wait on the volunteer), so the
    /// receipt `status` collapses to **two** values — `CONTACT_NOTIFIED` when a primary contact
    /// exists, `PENDING` when none does. `VOLUNTEER_NOTIFIED` is no longer produced: notifying the
    /// volunteer is a parallel bypass that does not move `status`. The order status itself is
    /// deliberately left untouched — an emergency is a separate event, never an order state
    /// (`AGENTS.md` section 6).
    func handleEmergencyTrigger(body: (any Encodable & Sendable)?) throws -> EmergencyTriggerResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyTriggerRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        guard let order = orders.first(where: { $0.orderId == request.orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "订单不存在"))
        }
        guard order.status == .inProgress else {
            throw APIError.serverError(
                ErrorResponse(code: "NOT_ORDER_PARTICIPANT", message: "您无权操作此订单")
            )
        }
        if let merged = mergeIntoOpenMockEmergency(request) {
            return merged
        }
        emergencyEventSequence += 1
        let hasPrimaryContact = emergencyContacts.contains { $0.isPrimary == true }
        let firedStatus: EmergencyEventStatus = hasPrimaryContact ? .contactNotified : .pending
        // 照后端演服务端倒计时：`useCountdown` 时先落 COUNTDOWN，截止时刻取后端默认 3 秒。
        // 「到点推成正式求助」在下面 `handleActiveEmergency` 里按读取时刻判，Mock 没有调度器。
        let countdownEndsAt = request.useCountdown == true
            ? DateFormatter.aidRunBackendLocalDateTime.string(
                from: Date().addingTimeInterval(TimeInterval(EmergencyCoordinator.countdownSeconds))
            )
            : nil
        let status: EmergencyEventStatus = countdownEndsAt == nil ? firedStatus : .countdown
        mockFiredEmergencyStatus = firedStatus
        activeEmergencyEvent = EmergencyEventResponse(
            id: emergencyEventSequence,
            orderId: order.orderId,
            userId: nil,
            status: status.rawValue,
            triggerType: "BUTTON",
            hasGpsLocation: request.gpsLat != nil && request.gpsLng != nil,
            countdownEndsAt: countdownEndsAt
        )
        return EmergencyTriggerResponse(
            success: true,
            eventId: emergencyEventSequence,
            status: status.rawValue,
            countdownEndsAt: countdownEndsAt
        )
    }

    /// 后端 #841（交接 blind-run-backend#843）：本人已有一条**已发出**、未结案的求助时再按不新建 ——
    /// 回同一个 `eventId` 与它当下的状态，并用这次的坐标更新那条事件。Mock 只有一个事件槽，「本人的」就是它。
    /// 倒计时中的不在此列（后端 `MERGEABLE_STATUSES` 不含 COUNTDOWN）；也只并同一张订单（后端 `findMergeTarget` 比 `orderId`）。
    /// 此前 Mock 每次都新建，于是「再按一次被合并、屏 3b 重新弹出」只有连真实后端才走得到（#500）。
    ///
    /// ponytail: 比后端宽的三处是有意的 —— 不演 60 秒冷却（真实后端 60 秒内再按先回 429，UI 用例不想干等）、
    /// 不演 30 分钟合并窗口、不给 PENDING 补一次升级。要验这三条只能连真实后端。
    private func mergeIntoOpenMockEmergency(_ request: EmergencyTriggerRequest) -> EmergencyTriggerResponse? {
        fireDueMockCountdown()
        guard let open = activeEmergencyEvent,
              open.orderId == request.orderId,
              open.eventStatus != .countdown,
              !open.eventStatus.isTerminal else { return nil }
        activeEmergencyEvent = EmergencyEventResponse(
            id: open.id,
            orderId: open.orderId,
            userId: open.userId,
            status: open.status,
            triggerType: open.triggerType,
            hasGpsLocation: open.hasGpsLocation == true || (request.gpsLat != nil && request.gpsLng != nil),
            triggeredAt: open.triggeredAt,
            volunteerConfirmedAt: open.volunteerConfirmedAt,
            countdownEndsAt: open.countdownEndsAt
        )
        return EmergencyTriggerResponse(
            success: true,
            eventId: open.id,
            status: open.status ?? EmergencyEventStatus.pending.rawValue,
            countdownEndsAt: open.countdownEndsAt
        )
    }

    /// 截止已过的 COUNTDOWN 视为服务端已开火。
    private func fireDueMockCountdown() {
        guard let event = activeEmergencyEvent, event.eventStatus == .countdown,
              let endsAt = event.countdownEndsAt?.backendTimestamp, endsAt <= Date() else { return }
        activeEmergencyEvent = EmergencyEventResponse(
            id: event.id,
            orderId: event.orderId,
            userId: event.userId,
            status: mockFiredEmergencyStatus.rawValue,
            triggerType: event.triggerType,
            hasGpsLocation: event.hasGpsLocation
        )
    }

    /// `GET /api/emergency/active` —— 冷启动/重连恢复。没有未终态事件时 `data` 为 null。
    func handleActiveEmergency() -> EmergencyActiveEnvelope {
        fireDueMockCountdown()
        return EmergencyActiveEnvelope(success: true, data: activeEmergencyEvent)
    }

    /// `PUT /api/emergency/{eventId}/cancel` —— 受助者本人撤销误触。
    func handleCancelEmergency(eventId: Int64) throws -> EmergencyCancelResponse {
        guard let event = activeEmergencyEvent else {
            throw APIError.serverError(
                ErrorResponse(code: "EMERGENCY_ALREADY_CLOSED", message: "该求助已经结束")
            )
        }
        guard event.id == eventId else {
            throw APIError.serverError(
                ErrorResponse(code: "EMERGENCY_NOT_OWNER", message: "只能撤销自己的紧急求助")
            )
        }
        fireDueMockCountdown()
        // 倒计时内撤回 = CANCELLED（从未发出）；已开火后撤销 = FALSE_ALARM。与后端 `cancelByOwner` 同。
        let wasCountingDown = event.id == eventId && activeEmergencyEvent?.eventStatus == .countdown
        activeEmergencyEvent = nil
        return EmergencyCancelResponse(
            success: true,
            eventId: eventId,
            status: (wasCountingDown ? EmergencyEventStatus.cancelled : .falseAlarm).rawValue
        )
    }

    /// `PUT /api/emergency/{eventId}/volunteer-response` —— **只接受 `NEED_HELP`**。
    /// `FALSE_ALARM` 在线上是 403，Mock 必须同样拒绝，否则开发期会长出一个线上根本不存在的「误触」按钮。
    func handleVolunteerEmergencyResponse(
        eventId: Int64,
        action: String?
    ) throws -> VolunteerEmergencyAcknowledgement {
        guard action == "NEED_HELP" else {
            throw APIError.serverError(
                ErrorResponse(
                    code: "EMERGENCY_VOLUNTEER_CANNOT_DISMISS",
                    message: "志愿者无权撤销求助，请确认对方是否需要帮助"
                )
            )
        }
        return VolunteerEmergencyAcknowledgement(success: true, eventId: eventId, action: action)
    }
}
