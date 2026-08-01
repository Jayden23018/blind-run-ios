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

enum EmergencySOSState: Equatable {
    case idle
    case locating
    case submitting
    case acknowledged(EmergencyEventStatus)
    case unsentNoLocation
    case failed(String)
    case cooldown(retryAfterSeconds: Int?)

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
        case .unsentNoLocation:
            return EmergencySafetyCopy.locationUnavailable
        case .failed(let reason):
            return EmergencySafetyCopy.failure(reason)
        case .cooldown(let seconds):
            return EmergencySafetyCopy.cooldown(retryAfterSeconds: seconds)
        }
    }

    /// `true` when the request was not accepted, so the UI can colour it as an error and the copy
    /// leads with 未发出.
    var isFailure: Bool {
        switch self {
        case .unsentNoLocation, .failed, .cooldown:
            return true
        case .idle, .locating, .submitting, .acknowledged:
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

    @Published private(set) var state: EmergencySOSState = .idle
    @Published private(set) var activeEvent: ActiveEmergencyEvent?

    private var cancellables = Set<AnyCancellable>()

    // MARK: Wiring

    /// Emergency follow-ups arrive on the realtime channel long after the screen that triggered
    /// them may have gone. Subscribing here — not in a ViewModel — is what makes the state survive
    /// navigation, backgrounding, and lock.
    func observe(_ realtimeCoordinator: AppRealtimeCoordinator) {
        realtimeCoordinator.$latestSafetyEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.apply(event)
            }
            .store(in: &cancellables)
    }

    /// Cleared on logout, account deletion, session expiration, user change, and role switch.
    /// Nothing about an emergency event is persisted to disk: the backend exposes no recovery
    /// endpoint or event replay (handoff Q⑤, unanswered), so retained metadata could only ever be
    /// presented as unverified state — and unverified rescue state is exactly what must not be
    /// shown to someone who cannot see the screen.
    func reset() {
        state = .idle
        activeEvent = nil
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
    @discardableResult
    func trigger(
        order: OrderDetailResponse,
        role: UserRole?,
        userID: Int64?,
        apiClient: any APIClientProtocol,
        locate: () async -> LocatedCoordinate?
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
                return finish(.unsentNoLocation)
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
        guard var active = activeEvent else { return }
        if let orderID = event.orderID, orderID != active.orderID { return }

        switch event.kind {
        case .emergencyContactNotified:
            active.status = .contactNotified
        case .emergencyResolved:
            active.status = .resolved
        case .emergencyNoContact, .emergencyVolunteerTimeout:
            active.status = .csHandling
        case .emergencyTriggered:
            // Nothing new: the HTTP response already told us, and with more detail.
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
