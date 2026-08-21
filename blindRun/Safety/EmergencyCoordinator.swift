import Combine
import CoreLocation
import Foundation

// MARK: - SOS State

/// One in-flight or acknowledged SOS. Deliberately separate from `RunOrderStatus`: an emergency
/// event never mutates the order lifecycle (`AGENTS.md` section 6).
struct ActiveEmergencyEvent: Equatable, Sendable {
    let eventID: Int64
    let orderID: Int64
    /// Authenticated user the event belongs to. Guards against presenting one account's emergency
    /// under another after a role switch or re-login.
    let userID: Int64?
    var status: EmergencyEventStatus
}

/// An `EMERGENCY_VOLUNTEER_ALERT` addressed to the escorting volunteer as observer.
///
/// The volunteer's only possible answer is "确认需要帮助". There is deliberately no dismiss action:
/// `action=FALSE_ALARM` is a hard 403 server-side, because in a one-to-one escort the companion is
/// the person a victim may need protection from.
struct VolunteerEmergencyAlert: Equatable, Sendable {
    let eventID: Int64
    let orderID: Int64?
    let message: String
    var isAcknowledged = false
}

enum EmergencySOSState: Equatable {
    case idle
    case locating
    case submitting
    case acknowledged(EmergencyEventStatus)
    /// 没有新鲜真实坐标，所以一个字节都没发出去。带上 `LocationService` 当时的报错，
    /// 让文案能区分「权限被关」和「拿不到 GPS」—— 两者的下一步动作完全不同。
    case unsentNoLocation(LocationError?)
    case failed(String)
    case cooldown(retryAfterSeconds: Int?)
    /// Carrier receipt confirmed the SMS reached the contact's handset
    /// (`EMERGENCY_CONTACT_SMS_DELIVERED`). The only state allowed to speak in the completed tense.
    case contactSmsDelivered
    /// Provider rejected the SMS or the carrier failed to deliver it (`EMERGENCY_CONTACT_NOTIFY_FAILED`).
    /// Distinct from a failed *trigger*: the request was accepted, the notification was not.
    case contactNotifyFailed
    /// The owner cancelled their own false alarm (`PUT /api/emergency/{eventId}/cancel`).
    case cancelledByOwner

    /// Text shown next to the button and spoken. `nil` only for `.idle`.
    var message: String? {
        switch self {
        case .idle:
            return nil
        case .locating:
            return EmergencySafetyCopy.locating
        case .submitting:
            return EmergencySafetyCopy.submitting
        case .acknowledged(let status):
            return EmergencySafetyCopy.submitted(status)
        case .unsentNoLocation(let reason):
            return EmergencySafetyCopy.locationUnavailable(reason)
        case .failed(let reason):
            return EmergencySafetyCopy.failure(reason)
        case .cooldown(let seconds):
            return EmergencySafetyCopy.cooldown(retryAfterSeconds: seconds)
        case .contactSmsDelivered:
            return EmergencySafetyCopy.contactSmsDelivered
        case .contactNotifyFailed:
            return EmergencySafetyCopy.contactNotifyFailed
        case .cancelledByOwner:
            return EmergencySafetyCopy.cancelOwnerSucceeded
        }
    }

    /// `true` when the request was not accepted, so the UI can colour it as an error and the copy
    /// leads with 未发出.
    var isFailure: Bool {
        switch self {
        // `contactNotifyFailed` counts as a failure on purpose: nobody was reached, and that is the
        // one fact a blind user must hear in the error register so they call 110 themselves.
        case .unsentNoLocation, .failed, .cooldown, .contactNotifyFailed:
            return true
        case .idle, .locating, .submitting, .acknowledged, .contactSmsDelivered, .cancelledByOwner:
            return false
        }
    }

    var isBusy: Bool {
        self == .locating || self == .submitting
    }
}

// MARK: - Coordinator

/// App-lifetime owner of the in-run SOS. Lives on `AppState` so a triggered event keeps updating
/// while the participant navigates away from the service screen, and is cleared on every session
/// boundary alongside the rest of the authenticated state.
@MainActor
final class EmergencyCoordinator: ObservableObject {
    /// Strict GPS gate: without a fresh real coordinate the request is not sent at all.
    ///
    /// The backend *would* accept it — `EmergencyTriggerRequest.gpsLat/gpsLng` are optional
    /// (`demo/.../dto/EmergencyTriggerRequest.java`) and `EmergencyContactNotifier.formatLocation`
    /// degrades to "位置获取失败，请尽快拨打其电话或报警110" in the SMS. That degraded path is a
    /// product/safety call, not an engineering one (handoff Q①, unanswered): a rescue sent to the
    /// wrong place is worse than no rescue, and a blind user cannot tell the difference. Flip this
    /// single constant once product/safety approve; nothing else needs to change.
    static let allowsSubmissionWithoutLocation = false

    /// Longest we will make someone wait for a fresh fix before giving up and saying so.
    static let locationWaitTimeout: TimeInterval = 5

    /// 取一份新鲜的真实 GCJ-02 坐标，拿不到就返回 nil（由 `trigger` 决定不发并如实播报）。
    ///
    /// 放在这里而不是各调用方各写一份：求助入口现在有两个（订单状态页、首页 SOS 条），
    /// 而这段逻辑的每一条都是安全约束 —— `latestBackendSample()` 只返回经单一后端边界
    /// 归一化过的**真实设备采样**，Demo / UI 测试的定位路径压根产不出设备采样，
    /// 所以演示坐标无法经由这里混进云端求助。两份实现意味着这条保证要守两遍。
    static func freshEmergencyCoordinate(using locationService: LocationService?) async -> LocatedCoordinate? {
        guard let locationService else { return nil }
        if let sample = locationService.latestBackendSample() {
            return sample
        }
        locationService.requestOneTimeLocation()
        let deadline = Date().addingTimeInterval(locationWaitTimeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let sample = locationService.latestBackendSample() {
                return sample
            }
        }
        return nil
    }

    @Published private(set) var state: EmergencySOSState = .idle
    @Published private(set) var activeEvent: ActiveEmergencyEvent?
    /// Set only on the escorting volunteer's device, from `EMERGENCY_VOLUNTEER_ALERT`.
    @Published private(set) var volunteerAlert: VolunteerEmergencyAlert?

    private var cancellables = Set<AnyCancellable>()
    /// Supplied by `AppState` so the coordinator can recover an event it never saw the trigger for
    /// (volunteer-initiated SOS, cold start, reconnect). Returns `nil` when recovery does not apply —
    /// `GET /api/emergency/active` is `BLIND`-only, so a volunteer session must not call it at all.
    private var recoveryAPIClientProvider: (() -> (any APIClientProtocol)?)?

    // MARK: Wiring

    /// Emergency follow-ups arrive on the realtime channel long after the screen that triggered
    /// them may have gone. Subscribing here — not in a ViewModel — is what makes the state survive
    /// navigation, backgrounding, and lock.
    func observe(
        _ realtimeCoordinator: AppRealtimeCoordinator,
        recoveryAPIClientProvider: (() -> (any APIClientProtocol)?)? = nil
    ) {
        self.recoveryAPIClientProvider = recoveryAPIClientProvider
        realtimeCoordinator.$latestSafetyEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.apply(event)
            }
            .store(in: &cancellables)
    }

    /// Cleared on logout, account deletion, session expiration, user change, and role switch.
    /// Nothing about an emergency event is persisted to disk — retained metadata could only ever be
    /// presented as unverified state, and unverified rescue state is exactly what must not be shown
    /// to someone who cannot see the screen. Recovery goes through `refreshActiveEvent()` instead,
    /// which re-reads the authoritative state from the backend.
    func reset() {
        state = .idle
        activeEvent = nil
        volunteerAlert = nil
    }

    // MARK: Recovery

    /// Re-reads the authoritative event from `GET /api/emergency/active`.
    ///
    /// Needed because two paths produce an emergency this client never saw a trigger receipt for:
    /// a volunteer raising the SOS on the blind runner's behalf, and a cold start / reconnect after
    /// the triggering screen is long gone. WS emergency notifications carry no `eventId`
    /// (`api_spec.yaml:1174-1176`), so this endpoint is the only place the id and the live status
    /// can come from. Silent on failure: a recovery attempt that did not land must not manufacture
    /// rescue state, and there is nothing actionable to announce.
    func refreshActiveEvent(userID: Int64? = nil) async {
        guard let apiClient = recoveryAPIClientProvider?() else { return }
        do {
            let envelope: EmergencyActiveEnvelope = try await apiClient.get("/api/emergency/active")
            guard let event = envelope.data, !event.eventStatus.isTerminal else {
                // Backend says nothing is open. Any local echo of a finished event goes with it.
                if activeEvent != nil {
                    activeEvent = nil
                    state = .idle
                }
                return
            }
            activeEvent = ActiveEmergencyEvent(
                eventID: event.id,
                orderID: event.orderId ?? activeEvent?.orderID ?? 0,
                userID: event.userId ?? userID,
                status: event.eventStatus
            )
            state = .acknowledged(event.eventStatus)
        } catch {
            return
        }
    }

    // MARK: Cancel (owner only)

    /// The one user-side exit from a false alarm. Volunteers deliberately have no equivalent:
    /// `action=FALSE_ALARM` on the volunteer endpoint is a hard 403
    /// (`EMERGENCY_VOLUNTEER_CANNOT_DISMISS`), because in a one-to-one escort the companion is the
    /// person a victim may need protection from.
    @discardableResult
    func cancelByOwner(apiClient: any APIClientProtocol) async -> TriggerOutcome {
        guard let active = activeEvent else {
            return finish(.failed("当前没有进行中的求助"))
        }
        do {
            let response: EmergencyCancelResponse = try await apiClient.put(
                "/api/emergency/\(active.eventID)/cancel"
            )
            guard response.success else {
                return finish(.failed(EmergencySafetyCopy.cancelOwnerFailed(nil)))
            }
            activeEvent = nil
            return finish(.cancelledByOwner)
        } catch let error as APIError {
            // 已经结束的事件不是错误，是状态过期：把本地状态对齐后按已结束处理。
            if error.errorCode == .emergencyAlreadyClosed {
                activeEvent = nil
                return finish(.idle)
            }
            return finish(.failed(EmergencySafetyCopy.cancelOwnerFailed(error.localizedMessage)))
        } catch {
            return finish(.failed(EmergencySafetyCopy.cancelOwnerFailed(nil)))
        }
    }

    /// Volunteer answering `EMERGENCY_VOLUNTEER_ALERT`. `NEED_HELP` is the only action that exists
    /// here on purpose — see `VolunteerEmergencyAcknowledgement`.
    @discardableResult
    func acknowledgeAsVolunteer(
        eventID: Int64,
        apiClient: any APIClientProtocol
    ) async -> Bool {
        do {
            let response: VolunteerEmergencyAcknowledgement = try await apiClient.request(
                method: .put,
                path: "/api/emergency/\(eventID)/volunteer-response",
                query: ["action": "NEED_HELP"],
                body: nil,
                requiresAuth: true
            )
            if response.success, volunteerAlert?.eventID == eventID {
                volunteerAlert?.isAcknowledged = true
            }
            return response.success
        } catch let error as APIError {
            // 事件已由客服/本人关掉：对志愿者来说等同于「不用再确认了」，收起入口而不是报错。
            if error.errorCode == .emergencyAlreadyClosed, volunteerAlert?.eventID == eventID {
                volunteerAlert = nil
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: Trigger

    /// Result of a trigger attempt, so callers can announce without re-deriving the state.
    struct TriggerOutcome: Equatable {
        let state: EmergencySOSState
        var message: String { state.message ?? "" }
        var isFailure: Bool { state.isFailure }
    }

    /// Sends one SOS for an owned `IN_PROGRESS` order.
    ///
    /// - Parameter locate: supplies the freshest **real** device sample, already normalized to
    ///   GCJ-02. Callers must source it from `LocationService.latestBackendSample()`, which returns
    ///   `nil` unless a genuine `CLLocation` arrived within its freshness window — the Demo/UI-test
    ///   fallback never produces one, so a demo coordinate cannot reach the cloud through here.
    ///   It is a closure rather than a value so the wait for a fresh fix happens *inside*
    ///   `.locating`: otherwise a blind runner gets several seconds of silence after tapping and the
    ///   duplicate-tap guard is not yet armed.
    /// - Parameter locationFailureReason: read **after** `locate` returns nil, so the copy can tell
    ///   「权限被关」from「拿不到 GPS」. Defaults to nil, which speaks the generic 拿不到定位 branch.
    @discardableResult
    func trigger(
        order: OrderDetailResponse,
        role: UserRole?,
        userID: Int64?,
        apiClient: any APIClientProtocol,
        locate: () async -> LocatedCoordinate?,
        locationFailureReason: () -> LocationError? = { nil }
    ) async -> TriggerOutcome {
        // Duplicate-submit protection: one tap at a time, regardless of how the alert was dismissed.
        guard !state.isBusy else {
            return TriggerOutcome(state: state)
        }

        // Re-check eligibility against canonical order state at send time. Stale screen state or a
        // WebSocket event must never widen this.
        guard let role, order.status.canTriggerEmergency(as: role) else {
            return finish(.failed("当前订单状态不能发起求助"))
        }

        state = .locating
        let coordinate = await locate()

        guard let coordinate, coordinate.system == .gcj02Backend else {
            guard Self.allowsSubmissionWithoutLocation else {
                return finish(.unsentNoLocation(locationFailureReason()))
            }
            return await send(
                request: EmergencyTriggerRequest(orderId: order.orderId, gpsLat: nil, gpsLng: nil),
                orderID: order.orderId,
                userID: userID,
                apiClient: apiClient
            )
        }

        return await send(
            request: EmergencyTriggerRequest(
                orderId: order.orderId,
                gpsLat: coordinate.coordinate.latitude,
                gpsLng: coordinate.coordinate.longitude
            ),
            orderID: order.orderId,
            userID: userID,
            apiClient: apiClient
        )
    }

    private func send(
        request: EmergencyTriggerRequest,
        orderID: Int64,
        userID: Int64?,
        apiClient: any APIClientProtocol
    ) async -> TriggerOutcome {
        state = .submitting
        do {
            let response: EmergencyTriggerResponse = try await apiClient.post(
                "/api/emergency/trigger",
                body: request
            )
            // Only a structured success enters submitted state. A 200 that does not decode into
            // `{success, eventId, status}` is a failure, not an acknowledgement.
            guard response.success else {
                return finish(.failed("服务器未受理求助"))
            }
            activeEvent = ActiveEmergencyEvent(
                eventID: response.eventId,
                orderID: orderID,
                userID: userID,
                status: response.eventStatus
            )
            return finish(.acknowledged(response.eventStatus))
        } catch let error as APIError {
            if case .rateLimited(let info) = error {
                return finish(.cooldown(retryAfterSeconds: info.retryAfterSeconds))
            }
            return finish(.failed(error.localizedMessage))
        } catch {
            return finish(.failed("网络异常"))
        }
    }

    private func finish(_ newState: EmergencySOSState) -> TriggerOutcome {
        state = newState
        return TriggerOutcome(state: newState)
    }

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
                    message: event.displayText
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
        state.message
    }
}
