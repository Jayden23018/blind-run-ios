import SwiftUI

// MARK: - Emergency Safety

/// All user-facing SOS copy lives here so the truthfulness rules below can be asserted in one place.
///
/// **The app may claim an emergency SMS was delivered only on carrier receipt.** `EMERGENCY_CONTACT_NOTIFIED`
/// is still pushed synchronously inside the trigger transaction
/// (`demo/.../service/EmergencyService.java:370-373`) while the SMS is sent afterwards by
/// `@TransactionalEventListener(AFTER_COMMIT)` + `@Async`
/// (`demo/.../service/EmergencyContactNotifier.java:60-62`) — at that moment the SMS has not been
/// attempted even once, so `contactNotified` stays in the progressive tense.
///
/// Since 2026-07-31 the backend polls Aliyun `QuerySendDetails`
/// (`TimeoutScheduler.checkSmsDeliveryReceipts`) and splits the truth three ways:
/// `EMERGENCY_CONTACT_NOTIFIED` = 已发起，未提交给服务商；`EMERGENCY_CONTACT_SMS_DELIVERED` = 运营商回执
/// 确认送达；`EMERGENCY_CONTACT_NOTIFY_FAILED` = 服务商拒绝或投递失败。A query that itself fails
/// (`UNKNOWN`) changes nothing and pushes nothing — "查不到" must never be spoken as "失败".
/// **Only the delivered branch is allowed a completed tense**; every other state stays progressive and
/// carries the 110 reminder — a blind user decides whether to seek help another way based on exactly
/// these words.
enum EmergencySafetyCopy {
    static let title = "一键求助"
    static let confirmButtonTitle = "确认求助"
    static let cancelButtonTitle = "取消"

    /// Mandated verbatim by `AGENTS.md` section 10. Do not reword.
    static let confirmationMessage = "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"

    static let accessibilityLabel = "一键求助，遇到紧急情况时点击"
    static let accessibilityHint = "需要二次确认，确认后会向后台发送求助并上报当前位置"

    /// Appended to every terminal-ish state. The app is not a rescue service and says so.
    static let emergencyCallReminder = "若情况危急请立即拨打110。"

    static let locating = "正在获取当前位置，请稍候。"
    static let submitting = "正在发送求助，请稍候。"

    /// Not sent, because no fresh real coordinate was available. Says "未发出" first: the most
    /// important fact for someone who cannot see the screen is that nothing has been sent.
    static let locationUnavailable =
        "求助未发出：当前无法获取你的位置。请在设置中允许定位后重试，或直接拨打110。"

    static func failure(_ reason: String?) -> String {
        let detail = reason?.trimmed.isEmpty == false ? reason!.trimmed : "网络异常"
        return "求助未发出：\(detail)。请重试，或直接拨打110。"
    }

    static func cooldown(retryAfterSeconds: Int?) -> String {
        guard let seconds = retryAfterSeconds, seconds > 0 else {
            return "刚刚已经发送过求助，请稍后再试。\(emergencyCallReminder)"
        }
        return "刚刚已经发送过求助，请 \(seconds) 秒后再试。\(emergencyCallReminder)"
    }

    /// Copy for a backend-acknowledged trigger. Never promises that anyone has been reached —
    /// only that the request is recorded and being processed.
    static func submitted(_ status: EmergencyEventStatus) -> String {
        switch status {
        case .volunteerNotified:
            return "求助已记录，正在通知同行志愿者确认情况。\(emergencyCallReminder)"
        case .contactNotified:
            return contactNotified
        case .csHandling:
            return "求助已记录，已转由客服处理。\(emergencyCallReminder)"
        case .volunteerConfirmed:
            return "求助已记录，志愿者已确认，正在联系你的紧急联系人。\(emergencyCallReminder)"
        case .resolved, .falseAlarm:
            return "求助已记录并已结束。\(emergencyCallReminder)"
        case .pending, .unknown:
            return "求助已记录，系统正在处理。\(emergencyCallReminder)"
        }
    }

    /// Replaces the backend's `EMERGENCY_CONTACT_NOTIFIED` template text
    /// ("已通知紧急联系人{contactName}" / "已通知你的联系人{contactName}，请保持冷静",
    /// `demo/src/main/resources/data.sql:72`), which is completed-tense and not true at send time.
    static let contactNotified =
        "系统正在联系你的紧急联系人，尚未确认对方是否收到。\(emergencyCallReminder)"

    /// `EMERGENCY_CONTACT_SMS_DELIVERED`：运营商回执确认送达手机，这是唯一允许用完成时的一句。
    ///
    /// ponytail: 后端文案带联系人姓名（「{contactName}已收到你的求助短信」），这里刻意不取 —— 紧急文案
    /// 一律用本地文案，是因为后端模板行可改可缺、且历史上就出现过完成时的不实文案。要带姓名的话，
    /// 得先让 `EMERGENCY_CONTACT_SMS_DELIVERED` 走结构化字段而不是模板正文。
    static let contactSmsDelivered =
        "你的紧急联系人已收到求助短信。\(emergencyCallReminder)"

    /// `EMERGENCY_CONTACT_NOTIFY_FAILED`：服务商拒绝或运营商投递失败 —— 确定没送到，必须说得最重。
    static let contactNotifyFailed =
        "联系紧急联系人失败，对方没有收到短信。请立即拨打110或120。"

    static let triggeredAcknowledged = "已收到你的求助，系统正在处理。\(emergencyCallReminder)"

    /// `EMERGENCY_TRIGGERED_BY_VOLUNTEER`：陪跑志愿者代盲人发起的求助。盲人自己没按过按钮，
    /// 所以第一句必须先说清是谁发起的，否则他会以为是误触。
    static let triggeredByVolunteer =
        "同行志愿者已为你发出紧急求助，系统正在联系你的紧急联系人。\(emergencyCallReminder)"

    /// `EMERGENCY_VOLUNTEER_ACK`：志愿者点了「确认需要帮助」后给志愿者本人的回执。
    static let volunteerAcknowledged = "已确认需要帮助，客服正在跟进。\(emergencyCallReminder)"

    /// `EMERGENCY_CLOSED_RESOLVED` / `EMERGENCY_CLOSED_FALSE_ALARM`：客服解除 / 标记误触后的收尾。
    static let closedResolved = "本次求助已由客服确认处理完毕。"
    static let closedFalseAlarm = "本次求助已按误触撤销，紧急联系人已收到解除通知。"

    /// 受助者本人撤销误触（`PUT /api/emergency/{eventId}/cancel`）。
    static let cancelButtonTitleForOwner = "撤销求助"
    static let cancelOwnerConfirmation = "确认撤销本次求助？系统会给已通知的紧急联系人补发一条解除短信。"
    static let cancelOwnerSucceeded = "求助已撤销，系统正在给你的紧急联系人发送解除通知。"

    static func cancelOwnerFailed(_ reason: String?) -> String {
        let detail = reason?.trimmed.isEmpty == false ? reason!.trimmed : "网络异常"
        return "撤销失败：\(detail)。求助仍然有效。"
    }

    /// 志愿者收到 `EMERGENCY_VOLUNTEER_ALERT` 后唯一能做的动作。**不提供「误触」按钮** ——
    /// 一对一陪跑里志愿者本身可能就是威胁来源，后端对 `action=FALSE_ALARM` 恒 403。
    static let volunteerNeedHelpButtonTitle = "确认需要帮助"
    static let volunteerAlertNotice = "被陪同者发出了紧急求助，请确认对方情况。"

    /// Backend `EMERGENCY_NO_CONTACT`: no primary contact exists, so nobody will be texted at all.
    static let noContact = "未找到你的紧急联系人，求助已转客服处理。\(emergencyCallReminder)"

    static let volunteerTimeout = "志愿者暂未响应你的求助，系统正在升级处理。\(emergencyCallReminder)"
}

struct EmergencyActionButton: View {
    let isLoading: Bool
    let action: () -> Void

    init(isLoading: Bool = false, action: @escaping () -> Void) {
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        PrimaryButton(EmergencySafetyCopy.title, isDestructive: true, isLoading: isLoading, action: action)
            .accessibilityLabel(EmergencySafetyCopy.accessibilityLabel)
            .accessibilityHint(EmergencySafetyCopy.accessibilityHint)
    }
}

/// Latest SOS state rendered next to the action. Announced separately via TTS by the view model,
/// so this view carries the text for VoiceOver without duplicating the announcement.
struct EmergencyStatusNotice: View {
    let message: String
    let isFailure: Bool

    var body: some View {
        Text(message)
            .font(AppFonts.caption())
            .foregroundColor(isFailure ? AppColors.destructive : AppColors.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(message)
    }
}

extension View {
    func emergencyConfirmationAlert(
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(EmergencySafetyCopy.title, isPresented: isPresented) {
            Button(EmergencySafetyCopy.confirmButtonTitle, role: .destructive, action: onConfirm)
            Button(EmergencySafetyCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(EmergencySafetyCopy.confirmationMessage)
        }
    }
}
