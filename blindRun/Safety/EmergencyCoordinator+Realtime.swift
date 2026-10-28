import Foundation

// 从 `EmergencyCoordinator.swift` 原样搬来（#502）：那个文件超了 SwiftLint 长度上限，CI 棘轮不许再变长。
extension EmergencyCoordinator {
    // MARK: Realtime follow-ups

    /// Applies a backend safety event to the active emergency.
    ///
    /// Matching is by order ID where the backend provides one. `EMERGENCY_CONTACT_NOTIFIED` and
    /// friends arrive as `APP_NOTIFICATION` envelopes carrying neither `eventId` nor `orderId`
    /// (`NotificationService.sendNotification` → `buildEnvelope("APP_NOTIFICATION")`, :93-99), so
    /// the event-ID match the spec asks for is not expressible against today's backend. That is
    /// tolerable only because the copy these events produce never claims a delivered SMS — see
    /// `EmergencySafetyCopy`. Events arriving with no active emergency are ignored outright.
    func apply(_ event: RealtimeSafetyEvent) {
        if event.kind == .emergencyVolunteerAlert {
            // Observer-side alert: it never advances the initiator's own state, it opens the one
            // action the volunteer has. `eventID` is the numeric backend id stringified at decode.
            if let eventID = Int64(event.eventID) {
                volunteerAlert = VolunteerEmergencyAlert(
                    eventID: eventID,
                    orderID: event.orderID,
                    message: event.displayText,
                    coordinate: event.coordinate,
                    serverDistanceMeters: event.serverDistanceMeters
                )
            }
            return
        }
        guard var active = activeEvent else {
            // No local event, yet the backend is talking about one — the blind runner never saw a
            // trigger receipt because the volunteer pressed the button, or the app was restarted.
            // The envelope carries no `eventId`, so the id and status can only come from the
            // recovery endpoint.
            if event.kind.impliesLiveEmergency {
                Task { await refreshActiveEvent() }
            }
            return
        }
        if let orderID = event.orderID, orderID != active.orderID { return }

        switch event.kind {
        case .emergencyContactNotified:
            active.status = .contactNotified
        case .emergencyResolved, .emergencyClosedResolved:
            active.status = .resolved
        case .emergencyClosedFalseAlarm:
            active.status = .falseAlarm
        case .emergencyNoContact, .emergencyVolunteerTimeout:
            active.status = .csHandling
        case .emergencyVolunteerAck:
            // 志愿者点完「确认需要帮助」后**发给志愿者本人**的回执，不改升级进度。
            // 后端 2026-07-31 把升级线与志愿者线拆成正交的两组字段
            // （`status` vs `volunteerNotifiedAt`/`volunteerConfirmedAt`/`volunteerAction`），
            // `VOLUNTEER_CONFIRMED` 同日标记废弃、不再产生。往 `status` 上写它等于自造一个后端已经
            // 不存在的状态，还会把 `CONTACT_NOTIFIED` 覆盖掉、让文案退回更早的阶段。
            // 志愿者自己的回执由 `acknowledgeAsVolunteer` 的调用点播报，不经过这里。
            return
        case .emergencyContactSmsDelivered:
            // Delivery is orthogonal to the escalation status: the event stays CONTACT_NOTIFIED,
            // but the copy may finally move to the completed tense.
            activeEvent = active
            state = .contactSmsDelivered
            return
        case .emergencyContactNotifyFailed:
            activeEvent = active
            state = .contactNotifyFailed
            return
        case .emergencyTriggered, .emergencyTriggeredByVolunteer:
            // Nothing new: the HTTP response (or the recovery fetch above) already told us, with
            // more detail than the notification carries.
            return
        case .emergencyVolunteerAlert:
            // Addressed to the volunteer as observer; it does not advance the initiator's state.
            return
        }

        activeEvent = active
        state = .acknowledged(active.status)
    }

    /// Latest authoritative SOS line for blind "重复当前状态", appended after — never replacing —
    /// the canonical order announcement.
    var repeatStatusSuffix: String? {
        // 合并那句里的「这次」指的是刚才那一按。过一阵再点「重复当前状态」还念它，
        // 听的人会以为自己刚才又按了一次 —— 这里改回按状态说。
        if case .mergedIntoOpenEvent(let status) = state {
            return EmergencySafetyCopy.submitted(status)
        }
        return state.message
    }
}
