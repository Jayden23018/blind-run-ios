import Combine
import CoreLocation
import Foundation

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
    /// constant once product/safety approve. One more place must change with it:
    /// `EmergencySafetyCopy.mergedIntoOpenEvent` says 「已更新你的位置」, which is only true when the
    /// request carried a coordinate (the backend skips the update otherwise, blind-run-backend#843).
    static let allowsSubmissionWithoutLocation = false

    // 🚩 拆文件（#502）放宽了访问级别：Swift 的 `private` 不跨文件，倒计时、发送、实时跟进挪进同目录的
    // `EmergencyCoordinator+*.swift` 之后，下面这些只能从 `private` / `private(set)` 放宽到 internal ——
    // `state` / `activeEvent` / `submittedLocationAccuracyMeters` / `mergedRetriggerCount` / `volunteerAlert` 的 setter，
    // `countdownTask` / `countdownAnnouncer` / `isWithdrawing`，`locationNote(for:)` / `outcome(_:)` / `finish(_:)` / `startServerCountdown`。
    // **写它们、调它们只许在 `EmergencyCoordinator*.swift` 里**：求助状态机的每一次改写都要经过这几个文件。

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
    @Published var state: EmergencySOSState = .idle {
        didSet {
            guard oldValue.isCountingDown, !state.isCountingDown else { return }
            countdownTask?.cancel()
            countdownTask = nil
        }
    }
    @Published var activeEvent: ActiveEmergencyEvent? {
        didSet {
            // 误差说明属于「本机发出的那一条」。事件结束或换成别的事件（陪跑员代发、冷启动恢复）就作废，
            // 否则上一条的「误差约 65 米」会挂到一条根本不是用这个坐标发出的求助上。
            guard oldValue != nil, oldValue?.eventID != activeEvent?.eventID else { return }
            submittedLocationAccuracyMeters = nil
        }
    }
    /// 本机发出的求助所附坐标的精度，只在差于 `LocationAccuracyPolicy.weakAccuracyMeters` 时有值。
    /// 由 `statusMessage` 读，见 `EmergencySafetyCopy.impreciseLocationNote`。
    @Published var submittedLocationAccuracyMeters: Double?
    /// 再次触发被并进同一条事件的次数。屏 3b 靠 `activeEvent?.eventID` 变化拉起来，
    /// 而合并时 id 不变 —— 不另给一个信号，第二次按下就只剩跑步页上的一行字。
    /// `EmergencyRecoveryPresentation` 看它变化再拉一次屏 3b。
    /// **只增不减，`reset()` 也不清**：清回 0 本身就是一次变化，会在退出登录时把屏 3b 弹出来。
    @Published var mergedRetriggerCount = 0
    /// 跑步中登录已过期（#376）：云端求助一律不发。由 `AppState.handleAuthenticatedAPIError` 在进入暂缓时打开，
    /// `reset()`（每个会话边界都会调）关上。
    ///
    /// 两端的求助入口在暂缓期间本该已经切到本地拨号；这一道是**兜底** —— 漏网的入口（陪跑员跑步中求助面板、
    /// 任何以后新加的入口）按下去也只会落到「求助未发出」，绝不会拿着过期凭证发请求、再被说成「网络异常，请重试」。
    private(set) var blocksCloudSOSForExpiredSession = false
    /// Set only on the escorting volunteer's device, from `EMERGENCY_VOLUNTEER_ALERT`.
    @Published var volunteerAlert: VolunteerEmergencyAlert?

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
        // 本机的倒数跟着会话一起结束。还在等定位时取消 = 一个字节都不发（`trigger` 里那道
        // `Task.isCancelled`）；已经落到服务端的倒计时**不会**因退出登录而撤回 —— 那是本人按下的
        // 求助、挂在本人身上，不存在带错 token 的问题，而且「手机没了也要发出」正是服务端计时的意义。
        countdownTask?.cancel()
        countdownTask = nil
        countdownAnnouncer = nil
        EmergencyAlarm.stopAll()
        state = .idle
        activeEvent = nil
        submittedLocationAccuracyMeters = nil
        volunteerAlert = nil
        blocksCloudSOSForExpiredSession = false
    }

    func blockCloudSOSForExpiredSession() {
        blocksCloudSOSForExpiredSession = true
    }

    /// 屏幕与播报该用的那一句：`state.message`，加上（适用时）所发坐标的误差说明。
    ///
    /// **界面渲染点一律读它，不读 `state.message`** —— 否则误差说明只在播报里出现，
    /// 屏幕上没有；低视力用户与读屏用户拿到的是两份不同的信息。
    var statusMessage: String? {
        guard let base = state.message else { return nil }
        return base + (locationNote(for: state) ?? "")
    }

    /// 只在「已发出或即将发出」的状态附加：未发出 / 失败 / 撤回时说坐标误差毫无意义。
    func locationNote(for state: EmergencySOSState) -> String? {
        guard let meters = submittedLocationAccuracyMeters, state.carriesSubmittedLocation else { return nil }
        return EmergencySafetyCopy.impreciseLocationNote(meters: meters)
    }

    func outcome(_ state: EmergencySOSState) -> TriggerOutcome {
        TriggerOutcome(state: state, locationNote: locationNote(for: state))
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
            let orderID = event.orderId ?? activeEvent?.orderID ?? 0
            // 🔴 倒计时中的事件：**接着倒数，不许被写成「已发出」**。重连 / 冷启动时这是唯一还能反悔的状态，
            // 写成 `.acknowledged` 会让取消按钮变成「撤销求助」、圆环消失（契约：恢复必须用 countdownEndsAt）。
            if event.eventStatus == .countdown,
               let endsAt = event.countdownEndsAt?.backendTimestamp,
               endsAt > Date() {
                if state.isCountingDown, activeEvent?.eventID == event.id { return }
                startServerCountdown(eventID: event.id, orderID: orderID, userID: event.userId ?? userID, endsAt: endsAt)
                return
            }
            // 截止已过、调度器还没来得及推：马上就会发出，按已受理处理。
            let status: EmergencyEventStatus = event.eventStatus == .countdown ? .pending : event.eventStatus
            // 自己的倒数正在跑（同一事件）就别打断它 —— 它到点会自己再来问一次。
            if state.isCountingDown, activeEvent?.eventID == event.id { return }
            // 同一条、同一个状态 = 对账没带来新信息（iOS #546）：倒计时到点后的宽限刷新、断线重连的补读都会撞上。
            let bringsNoNews = activeEvent?.eventID == event.id && activeEvent?.status == status
            activeEvent = .recovered(
                eventID: event.id, orderID: orderID, userID: event.userId ?? userID,
                status: status, triggeredAt: event.triggeredAt?.backendTimestamp, previous: activeEvent
            )
            guard !(bringsNoNews && state.refinesAcknowledgedEvent) else { return }
            state = .acknowledged(status)
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
            // 恢复出来的倒计时也可能从这个按钮撤：那一刻服务端回 `CANCELLED`，求助从未发出。
            return finish(response.status == EmergencyEventStatus.cancelled.rawValue
                ? .withdrawnBeforeSending
                : .cancelledByOwner)
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

    // MARK: Countdown state（逻辑在 `EmergencyCoordinator+Countdown.swift`）

    /// 正在跑的倒计时。**挂在 coordinator 上而不是 view 上**：这段时间里用户可能锁屏、切后台、
    /// 或被系统弹窗打断，而屏幕上的倒数不能因为某个 view 消失就停摆。
    /// 它**不再决定发不发** —— 那由服务端决定；取消它只是停掉本机的倒数播报。
    var countdownTask: Task<Void, Never>?
    /// 倒数时每秒那句播报。`beginCountdown` 装上；重连恢复出来的倒计时沿用它（没有就只响不念）。
    var countdownAnnouncer: ((String) -> Void)?
    /// 撤回请求在路上。挡住连按「取消」发出第二条撤回。
    var isWithdrawing = false
}
