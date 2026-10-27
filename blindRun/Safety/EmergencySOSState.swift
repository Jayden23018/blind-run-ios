import Foundation

// 从 `EmergencyCoordinator.swift` 原样搬来（#502）：那个文件超了 SwiftLint 长度上限，CI 棘轮不许再变长。

enum EmergencySOSState: Equatable {
    case idle
    /// 发出前的反悔窗口（屏 3），**由服务端计时**（后端 #388 ③，2026-09-25 起）。
    ///
    /// 此时后端已经有一条 `COUNTDOWN` 事件，但**什么都没发**：不发家属短信、不推志愿者、
    /// 不推客服。到点由服务端推成正式求助 —— 所以手机在这几秒里没电、崩溃或被杀掉，求助照样发出。
    ///
    /// 🔄 此前是客户端数完 3 秒再调 trigger，理由是「先发再撤」会惊动家人两次、并占住 60 秒冷却。
    /// 服务端倒计时把这两条都拿掉了：倒计时内撤回回 `CANCELLED`、一条短信都不发，
    /// 且后端会放掉冷却位（`EmergencyService.releaseCooldown`）。
    case countingDown(secondsRemaining: Int)
    case locating
    case submitting
    case acknowledged(EmergencyEventStatus)
    /// 再次触发被后端并进本人那条未结案的求助（后端 #841，交接 blind-run-backend#843）：
    /// 回的是**同一个** `eventId`，没有新建，家属短信不重发，客服被再提醒一次、位置已更新。
    /// 与 `.acknowledged` 分开，是因为两者念同一句的话，听的人会以为又发出了一条新求助。
    case mergedIntoOpenEvent(EmergencyEventStatus)
    /// 没有新鲜真实坐标，所以一个字节都没发出去。带上 `LocationService` 当时的报错，
    /// 让文案能区分「权限被关」和「拿不到 GPS」—— 两者的下一步动作完全不同。
    case unsentNoLocation(LocationError?)
    /// 跑步中登录已过期（#376）：云端求助发不出去，一个字节都没发。
    case unsentSessionExpired
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
    /// 倒计时内撤回成功（`CANCELLED`）：求助从未发出。
    case withdrawnBeforeSending
    /// 倒计时里撤回失败。服务端倒计时不受影响，求助可能已经发出 —— 事件保留，「撤销求助」可再试。
    case withdrawFailed(String?)

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
        case .mergedIntoOpenEvent:
            return EmergencySafetyCopy.mergedIntoOpenEvent
        case .unsentNoLocation(let reason):
            return EmergencySafetyCopy.locationUnavailable(reason)
        case .unsentSessionExpired:
            return EmergencySafetyCopy.sessionExpiredUnsent
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
        case .withdrawnBeforeSending:
            return EmergencySafetyCopy.withdrawnBeforeSending
        case .withdrawFailed(let reason):
            return EmergencySafetyCopy.withdrawFailed(reason)
        }
    }

    /// `true` when the request was not accepted, so the UI can colour it as an error and the copy
    /// leads with 未发出.
    var isFailure: Bool {
        switch self {
        // `contactNotifyFailed` counts as a failure on purpose: nobody was reached, and that is the
        // one fact a blind user must hear in the error register so they call 110 themselves.
        case .unsentNoLocation, .unsentSessionExpired, .failed, .cooldown, .contactNotifyFailed, .withdrawFailed:
            return true
        case .idle, .countingDown, .locating, .submitting, .acknowledged, .mergedIntoOpenEvent,
             .contactSmsDelivered, .cancelledByOwner, .withdrawnBeforeSending:
            return false
        }
    }

    /// 「这一刻不该再接受一次新的求助触发」。倒计时在列 —— 倒计时期间再按一下不该
    /// 叠出第二个倒计时，而这正是重复提交保护要防的事（`trigger` 开头那道 guard 读的就是它）。
    var isBusy: Bool {
        switch self {
        case .countingDown, .locating, .submitting:
            return true
        case .idle, .acknowledged, .mergedIntoOpenEvent, .unsentNoLocation, .unsentSessionExpired, .failed,
             .cooldown, .contactSmsDelivered, .contactNotifyFailed, .cancelledByOwner,
             .withdrawnBeforeSending, .withdrawFailed:
            return false
        }
    }

    /// 倒计时那一屏该不该占满整屏。做成属性而不是让每个 view 各写一遍
    /// `if case .countingDown` —— 屏 3 与屏 3b 的呈现条件必须只有一处。
    var isCountingDown: Bool {
        if case .countingDown = self { return true }
        return false
    }

    /// 这一刻求助是否「已发出或即将发出」—— 只有这些状态下说「所附位置误差约 N 米」才有意义。
    var carriesSubmittedLocation: Bool {
        switch self {
        case .countingDown, .contactSmsDelivered, .contactNotifyFailed:
            return true
        // 合并时后端用这次请求里的坐标更新了那条事件，所以误差说明照样适用。
        case .acknowledged(let status), .mergedIntoOpenEvent(let status):
            return !status.isTerminal
        // `.submitting`：误差在事件落地（`activeEvent` 写入）之后才记，提交中恒无值，列进来是死分支。
        case .idle, .locating, .submitting, .unsentNoLocation, .unsentSessionExpired, .failed, .cooldown,
             .cancelledByOwner, .withdrawnBeforeSending, .withdrawFailed:
            return false
        }
    }
}
