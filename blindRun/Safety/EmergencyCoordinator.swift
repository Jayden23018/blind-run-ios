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
    /// 受助者触发那一刻的位置（已归一到 GCJ-02）。可为 nil —— 契约里那两个字段各自可空，
    /// 而「盲人当时拿不到定位」在室内 / 高楼间是常态，不是异常。
    var coordinate: LocatedCoordinate?
    /// 收到这条告警的本机时刻。屏 5 上那句「X 秒前」读的是它。
    ///
    /// **不用后端的 `timestamp`**：那是服务端时钟，而两端时钟可能差几秒到几分钟，
    /// 差出来的结果是屏幕上写着「-40 秒前」或者「3 分钟前」——
    /// 而志愿者正据此判断「这事刚发生还是我漏看了很久」。
    let receivedAt: Date
    var isAcknowledged = false
    /// 服务端算的两人距离（只在档位可用时才有）。本机定位拿不到时的兜底 ——
    /// 锁屏推送刚把手机唤醒、GPS 还冷着的那几秒，恰恰是这条告警最常见的到达场景。
    var serverDistanceMeters: Double?

    init(
        eventID: Int64,
        orderID: Int64?,
        message: String,
        coordinate: LocatedCoordinate? = nil,
        receivedAt: Date = Date(),
        isAcknowledged: Bool = false,
        serverDistanceMeters: Double? = nil
    ) {
        self.eventID = eventID
        self.orderID = orderID
        self.message = message
        self.coordinate = coordinate
        self.receivedAt = receivedAt
        self.isAcknowledged = isAcknowledged
        self.serverDistanceMeters = serverDistanceMeters
    }

    /// 「距你多远」，只给分档（`DistanceCalculator.proximityBand`），不给精确数字。
    ///
    /// 本机实时定位优先 —— 服务端那份用的是志愿者最近一次上报，最旧可能 30 秒。
    /// 两份都没有就返回 nil、整行不显示，**不猜**：「就在附近」会让他以为人就在脚边。
    func distanceText(from device: CLLocationCoordinate2D?) -> String? {
        let meters: CLLocationDistance
        if let peer = coordinate, let device {
            meters = DistanceCalculator.distanceFromDeviceToBackend(
                deviceCoordinate: device,
                backendCoordinate: peer.coordinate
            )
        } else if let serverDistanceMeters {
            meters = serverDistanceMeters
        } else {
            return nil
        }
        return "距你\(DistanceCalculator.proximityBand(meters))"
    }
}

enum EmergencySOSState: Equatable {
    case idle
    /// 发出前的反悔窗口（屏 3）。**这三秒里一个字节都还没发给后端。**
    ///
    /// 🔴 为什么不照 Apple 紧急 SOS 那样「进倒计时就发、取消再撤」：后端
    /// `POST /api/emergency/trigger` 是**触发即升级** —— 紧急联系人在那一个请求里就被通知
    /// （异步发短信），撤销会给他再补一条解除短信，而冷却 60 秒是**按触发者计**的
    /// （`demo/docs/api_spec.yaml:2242`）。也就是说「先发再撤」的代价是：每一次误触都真的
    /// 惊动家人两次，并且**在随后的 60 秒里锁死真正的求助**（429）。
    /// 换来的只是「手机恰好在这三秒内没电或崩溃」这一种情形。
    case countingDown(secondsRemaining: Int)
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
        case .countingDown(let seconds):
            return EmergencySafetyCopy.countdown(secondsRemaining: seconds)
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
        case .idle, .countingDown, .locating, .submitting, .acknowledged,
             .contactSmsDelivered, .cancelledByOwner:
            return false
        }
    }

    /// 「这一刻不该再接受一次新的求助触发」。倒计时在列 —— 倒计时期间再按一下不该
    /// 叠出第二个倒计时，而这正是重复提交保护要防的事（`trigger` 开头那道 guard 读的就是它）。
    var isBusy: Bool {
        switch self {
        case .countingDown, .locating, .submitting:
            return true
        case .idle, .acknowledged, .unsentNoLocation, .failed, .cooldown,
             .contactSmsDelivered, .contactNotifyFailed, .cancelledByOwner:
            return false
        }
    }

    /// 倒计时那一屏该不该占满整屏。做成属性而不是让每个 view 各写一遍
    /// `if case .countingDown` —— 屏 3 与屏 3b 的呈现条件必须只有一处。
    var isCountingDown: Bool {
        if case .countingDown = self { return true }
        return false
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

    /// 🔴 **离开 `.countingDown` 与「掐掉倒计时任务」绑成同一件事，不靠调用方各自记得。**
    ///
    /// 2026-09-15 code review 抓到的洞：取消倒计时的唯一入口 `cancelCountdown()` 以
    /// `guard state.isCountingDown` 为前置条件，而这三秒里**别的路径也会改写 `state`** ——
    /// 任一条 `impliesLiveEmergency` 的 WS 通知、或 WS 重连触发的
    /// `catchUpMissedNotifications()`，都会走到 `refreshActiveEvent()`；只要后端存在任何一条
    /// 未终态事件（哪怕是客服还没关掉的旧的），`state` 就被写成 `.acknowledged`。
    /// 户外跑步途中断线重连是常态。
    ///
    /// 此后：圆环消失、底部按钮从「取消」变成「撤销求助」、`cancelCountdown()` 即使被调用
    /// 也会在 guard 处返回 false —— 而那个任务照样在跑，3 秒到点**发出一条用户已经无从阻止的求助**。
    @Published private(set) var state: EmergencySOSState = .idle {
        didSet {
            guard oldValue.isCountingDown, !state.isCountingDown else { return }
            countdownTask?.cancel()
            countdownTask = nil
        }
    }
    @Published private(set) var activeEvent: ActiveEmergencyEvent?
    /// Set only on the escorting volunteer's device, from `EMERGENCY_VOLUNTEER_ALERT`.
    @Published private(set) var volunteerAlert: VolunteerEmergencyAlert?

    private var cancellables = Set<AnyCancellable>()
    /// Supplied by `AppState` so the coordinator can recover an event it never saw the trigger for
    /// (volunteer-initiated SOS, cold start, reconnect). Returns `nil` outside the blind role:
    /// on a volunteer session the same endpoint answers a different question (the *runner's*
    /// event), which `refreshVolunteerAlert(safety:)` handles — it must not land in `activeEvent`.
    private var recoverySafetyProvider: (() -> (any SafetyServing)?)?

    // MARK: Wiring

    /// Emergency follow-ups arrive on the realtime channel long after the screen that triggered
    /// them may have gone. Subscribing here — not in a ViewModel — is what makes the state survive
    /// navigation, backgrounding, and lock.
    func observe(
        _ realtimeCoordinator: AppRealtimeCoordinator,
        recoverySafetyProvider: (() -> (any SafetyServing)?)? = nil
    ) {
        self.recoverySafetyProvider = recoverySafetyProvider
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
        // 倒计时必须跟着会话一起结束。漏掉它的后果很具体：上一个账号退出登录之后，
        // 三秒前按下的那个求助**照样会发出去**，而且带着新账号的 token。
        countdownTask?.cancel()
        countdownTask = nil
        EmergencyAlarm.stopAll()
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
        guard let safety = recoverySafetyProvider?() else { return }
        do {
            let envelope = try await safety.activeEmergency()
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

    /// 志愿者端的冷启动 / 重连恢复：把「对方正在求助」那条强提醒找回来（后端 #387 ②）。
    ///
    /// 此前只有盲人调 `GET /api/emergency/active`，于是志愿者 App 被杀掉再打开，
    /// 强提醒再也回不来 —— WS 的 `EMERGENCY_*` 不带 `eventId`，补读反推不出来。
    /// 2026-09-15 起后端对志愿者开放，返回的是**他正在陪的那位盲人**的事件。
    ///
    /// - 没有未结束事件 → 收起本地告警（断线期间已被本人 / 客服结束）。
    /// - `COUNTDOWN` → 同样当没有：求助还没发出，在线的志愿者此刻也收不到告警。
    /// - `volunteerConfirmedAt` 非空 → 他已经确认过，只恢复状态，不再弹全屏。
    ///
    /// 恢复出来的告警没有坐标（契约：这个端点一律不给原始坐标），地址行会如实说拿不到。
    /// 失败静默，理由同 `refreshActiveEvent`。
    func refreshVolunteerAlert(safety: any SafetyServing, now: Date = Date()) async {
        guard let envelope = try? await safety.activeEmergency() else { return }
        guard let event = envelope.data, !event.eventStatus.isTerminal, !event.isCountingDown else {
            volunteerAlert = nil
            return
        }
        let acknowledged = event.volunteerConfirmedAt != nil
        if var existing = volunteerAlert, existing.eventID == event.id {
            // 同一条已经在屏上（WS 先到了）：别换掉它 —— WS 那份带坐标和距离。
            if acknowledged, !existing.isAcknowledged {
                existing.isAcknowledged = true
                volunteerAlert = existing
            }
            return
        }
        volunteerAlert = VolunteerEmergencyAlert(
            eventID: event.id,
            orderID: event.orderId,
            message: EmergencySafetyCopy.volunteerAlertNotice,
            // 从触发时刻起算，「刚刚」和「已经过去几分钟」对他是两种判断。
            // 夹到不晚于本机此刻：两端时钟差出来的「-3 秒前」比「0 秒前」更糟。
            receivedAt: min(event.triggeredAt?.backendTimestamp ?? now, now),
            isAcknowledged: acknowledged
        )
    }

    // MARK: Cancel (owner only)

    /// The one user-side exit from a false alarm. Volunteers deliberately have no equivalent:
    /// `action=FALSE_ALARM` on the volunteer endpoint is a hard 403
    /// (`EMERGENCY_VOLUNTEER_CANNOT_DISMISS`), because in a one-to-one escort the companion is the
    /// person a victim may need protection from.
    @discardableResult
    func cancelByOwner(safety: any SafetyServing) async -> TriggerOutcome {
        guard let active = activeEvent else {
            return finish(.failed("当前没有进行中的求助"))
        }
        do {
            let response = try await safety.cancelEmergencyByOwner(eventId: active.eventID)
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
        safety: any SafetyServing
    ) async -> Bool {
        do {
            let response = try await safety.acknowledgeEmergencyAsVolunteer(eventId: eventID)
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

    // MARK: Countdown（屏 3）

    /// 倒计时秒数。3 秒取自 Apple 紧急 SOS，也与长按时长一致 —— 两个 3 秒不是巧合：
    /// 「按住 3 秒 → 再给你 3 秒反悔」是一条完整的、可预期的节奏。
    static let countdownSeconds = 3

    /// 正在跑的那个倒计时。**挂在 coordinator 上而不是 view 上**，理由与整个类的存在理由同源：
    /// 这段时间里用户可能锁屏、切后台、或被系统弹窗打断，而倒计时不能因为某个 view 消失就停摆。
    private var countdownTask: Task<Void, Never>?

    /// 开始发出前的倒计时。**长按 3 秒 / 自定义无障碍动作**这两条刻意路径走它，
    /// 轻点那条仍然先过 `AGENTS.md` §6 的二次确认（确认之后也落到这里）。
    ///
    /// 每一秒播一次声音 + 震动 + 交给调用方播报 —— 屏幕上那个圆环对跑步中的盲人不存在。
    func beginCountdown(
        order: OrderDetailResponse,
        role: UserRole?,
        userID: Int64?,
        safety: any SafetyServing,
        locate: @escaping () async -> LocatedCoordinate?,
        locationFailureReason: @escaping () -> LocationError? = { nil },
        announce: @escaping (String) -> Void = { _ in }
    ) {
        // 与 `trigger` 同一道重复提交保护：倒计时期间再按一下不该叠出第二个倒计时。
        guard !state.isBusy else { return }
        // 发起资格在这里先判一次，倒数完 `trigger` 还会再判一次（订单状态可能在这三秒里变）。
        // 先判是为了不让一个根本发不出去的求助白白数三秒 —— 那三秒里用户以为求助在路上。
        guard let role, order.status.canTriggerEmergency(as: role) else {
            state = .failed("当前订单状态不能发起求助")
            return
        }

        countdownTask?.cancel()
        state = .countingDown(secondsRemaining: Self.countdownSeconds)
        announce(EmergencySafetyCopy.countdownTitle)

        countdownTask = Task { [weak self] in
            for remaining in stride(from: Self.countdownSeconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.state = .countingDown(secondsRemaining: remaining)
                    EmergencyAlarm.countdownTick()
                    EmergencyHaptics.countdownTick()
                    announce(EmergencySafetyCopy.countdown(secondsRemaining: remaining))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            // 🚩 **先松开句柄，再改状态。** 顺序反了会自杀：`state` 的 `didSet` 在离开
            // `.countingDown` 时会 `countdownTask?.cancel()`，而此刻 `countdownTask` 正是
            // 我们自己 —— 取消之后下面 `trigger` 里的 `Task.sleep` 会立刻抛，
            // `freshEmergencyCoordinate` 那个 `while Date() < deadline { try? await ... }`
            // 就变成 5 秒空转，然后报「拿不到定位」。
            self.countdownTask = nil
            // 归零才发。`trigger` 开头那道 `guard !state.isBusy` 会被 `.countingDown` 挡住，
            // 所以先回到 `.idle` —— 这一步不是形式：漏掉它的表现是倒数完什么都没发生。
            self.state = .idle
            let outcome = await self.trigger(
                order: order,
                role: role,
                userID: userID,
                safety: safety,
                locate: locate,
                locationFailureReason: locationFailureReason
            )
            announce(outcome.message)
        }
    }

    /// 用户在倒计时里按了取消。**一个字节都没发出去过**，所以这里没有任何后端调用。
    @discardableResult
    func cancelCountdown() -> Bool {
        guard state.isCountingDown else { return false }
        countdownTask?.cancel()
        countdownTask = nil
        EmergencyAlarm.stopAll()
        state = .idle
        return true
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
        safety: any SafetyServing,
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
                safety: safety
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
            safety: safety
        )
    }

    private func send(
        request: EmergencyTriggerRequest,
        orderID: Int64,
        userID: Int64?,
        safety: any SafetyServing
    ) async -> TriggerOutcome {
        state = .submitting
        do {
            let response = try await safety.triggerEmergency(request)
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
                return await reconcile(after: .cooldown(retryAfterSeconds: info.retryAfterSeconds))
            }
            return await reconcile(after: .failed(error.localizedMessage))
        } catch {
            return await reconcile(after: .failed("网络异常"))
        }
    }

    /// 发送失败之后**去问一句后端到底有没有收到**。
    ///
    /// 🔴 解决的是一个会说谎的失败：请求在服务端处理完了、响应在回程丢了（弱网、切基站、
    /// 后台挂起），客户端只看见一个 `网络异常`。那一刻屏幕上写着「求助未发出」，
    /// 而家属的短信其实已经在路上 —— 盲人会据此以为没人知道他出事了。
    /// `429 冷却` 更直接：后端按触发者 SETNX 占位，命中它几乎就等于**刚才那条真的发出去了**。
    ///
    /// **没有做成自动重发。** 后端 `POST /api/emergency/trigger` 没有幂等 key，重发要么
    /// 建出第二个事件、要么撞上 60 秒冷却回 429 —— 而 429 的文案是「请稍后再试」，
    /// 会把一个**已经生效**的求助说成被拒绝。查询是只读的，没有这一类代价，
    /// 而 `GET /api/emergency/active` 本来就是「事件 id 与当前状态的唯一权威来源」（契约原话）。
    ///
    /// 查不到（或这一侧没装恢复入口，比如志愿者 —— 他问到的是对方的事件，不是自己这一条）就老老实实保留失败态 ——
    /// 对账失败不许制造任何救援状态。
    private func reconcile(after failure: EmergencySOSState) async -> TriggerOutcome {
        _ = finish(failure)
        await refreshActiveEvent()
        guard activeEvent != nil else { return TriggerOutcome(state: failure) }
        return TriggerOutcome(state: state)
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
        state.message
    }
}
