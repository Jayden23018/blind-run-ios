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
        // guard:allow sos-copy 运营商回执支撑的唯一完成时分支，见上方注释与 testOnlyTheCarrierReceiptBranchMayClaimDelivery
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
    ///
    /// 解除短信走的是与求助短信同一条 `@TransactionalEventListener(AFTER_COMMIT)` + `@Async` 异步路径，
    /// **没有**对应的运营商回执事件（回执只有 `EMERGENCY_CONTACT_SMS_DELIVERED` 一个，且只覆盖触发时那条）。
    /// 所以这里和 `cancelOwnerSucceeded` 一样只能用进行时 —— 2026-08-04 由 `scripts/hooks/guard.mjs`
    /// 抓出：原文写的是「紧急联系人已收到解除通知」，是本仓库红线的同类违规，只是它比触发路径晚加、
    /// 从没被 `testNoEmergencyCopyClaimsAnSMSWasDelivered` 的清单收进去。
    static let closedResolved = "本次求助已由客服确认处理完毕。"
    static let closedFalseAlarm = "本次求助已按误触撤销，系统正在给你的紧急联系人发送解除通知。"

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

    // MARK: 首页常驻求助条（非 IN_PROGRESS 的本地拨号分支）

    /// **刻意不叫「一键求助」。** 那四个字在本 App 里专指云端求助 —— 会记录事件、通知同行志愿者
    /// 与客服。而这条分支只是拨一通电话，App 什么都没发出去。
    /// `POST /api/emergency/trigger` 两端都只在 `IN_PROGRESS` 开放且必须带 `orderId`（`AGENTS.md` §6），
    /// 没有进行中的订单时它根本不可调用。用同一个词会让看不见屏幕的人以为求助已经发出。
    static let homeCallTitle = "紧急呼叫"
    static let homeCallAccessibilityLabel = "紧急呼叫，直接拨打电话"
    static let homeCallAccessibilityHint =
        "当前没有进行中的陪跑。点击后由你选择拨打紧急联系人或110，App 不会代你发送求助。"

    /// 第一句先说「App 不会代你发送求助」，理由与 `locationUnavailable` 相同：
    /// 看不见屏幕的人最需要先知道的是**什么都还没发生**。
    static let homeCallDialogMessage =
        "当前没有进行中的陪跑，App 不会代你发送求助。请选择要拨打的号码。"

    static let homeCallPoliceTitle = "拨打110"

    static func homeCallContactTitle(name: String?) -> String {
        "拨打\(name?.nilIfBlank ?? "紧急联系人")"
    }

    /// 没有唯一主联系人时的提示。`singlePrimary` 在 0 个或多个时都返回 nil，
    /// 两种情况对用户是同一件事：现在没有一个确定该拨给谁的号码。
    static let homeCallNoContactHint = "尚未设置唯一的主紧急联系人，只能拨打110。"
}

/// 拨号 URL 的唯一构造点。
///
/// 只取数字：后端返回的手机号是明文，但可能带空格或横线，直接拼进 `tel://` 会拼出无效 URL，
/// 而无效 URL 的表现是「点了没反应」—— 对盲人端就是事故。
enum EmergencyDialer {
    static let policeNumber = "110"

    static func telURL(for rawNumber: String?) -> URL? {
        guard let digits = rawNumber?.filter(\.isNumber), !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }
}

/// 首页求助条的两种模式。**由订单状态决定，不由用户选择。**
enum BlindHomeSOSMode: Equatable {
    /// `IN_PROGRESS`：走云端求助，与订单状态页同一条 `EmergencyCoordinator.trigger` 链路。
    case cloudTrigger
    /// 其余任何状态：本地拨号，绝不调 `POST /api/emergency/trigger`。
    case localCall

    /// 判据复用 `canTriggerEmergency(as:)` —— 与 `EmergencyCoordinator.trigger` 发送前的复核
    /// 是同一个，免得两处对「什么算可以发起云端求助」各有一套理解而慢慢漂开。
    ///
    /// 独立成静态方法而不是写在 View 里，是为了能被单测直接钉住：真机 UI 测试通道
    /// 目前起不来（code 74），把这条安全判据只放在 UI 断言里等于没有覆盖。
    static func resolve(order: OrderDetailResponse?, role: UserRole?) -> BlindHomeSOSMode {
        guard let order, let role, order.status.canTriggerEmergency(as: role) else {
            return .localCall
        }
        return .cloudTrigger
    }
}

/// 首页底部常驻求助条。挂在 `.safeAreaInset(edge: .bottom)` 上，所以滚动时不会离开屏幕。
///
/// 直接 `@ObservedObject` 持有 coordinator，而不是通过 `AppState` 读 ——
/// `AppState.emergencyCoordinator` 是个 `let`（不是 `@Published`），嵌套 ObservableObject 的变化
/// 不会经由 `AppState` 重新发布。订单状态页能刷新是因为它自己的 view model 恰好在 5 秒轮询里
/// 一直发布，靠的是巧合；这里不重复那个巧合。
struct BlindHomeSOSBar: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let mode: BlindHomeSOSMode
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            switch mode {
            case .cloudTrigger:
                EmergencyActionButton(isLoading: coordinator.state.isBusy, action: action)
            case .localCall:
                PrimaryButton(EmergencySafetyCopy.homeCallTitle, isDestructive: true, action: action)
                    .accessibilityLabel(EmergencySafetyCopy.homeCallAccessibilityLabel)
                    .accessibilityHint(EmergencySafetyCopy.homeCallAccessibilityHint)
            }

            // 只有云端求助才有状态可播报；本地拨号不产生任何后端状态。
            if mode == .cloudTrigger, let message = coordinator.state.message {
                EmergencyStatusNotice(
                    message: message,
                    isFailure: coordinator.state.isFailure
                )
            }
        }
        .accessibilityIdentifier("blindRunnerHomeSOSBar")
    }
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

/// 求助按钮 + 状态提示 + 撤销入口的组合，**自己 `@ObservedObject` 持有 coordinator**。
///
/// 为什么必须持有而不能由页面直接读 `appState.emergencyCoordinator.state`：
/// `AppState.emergencyCoordinator` 是 `let`，不是 `@Published`（`AppState.swift:63`），
/// 而 `AppState` 没有把子对象的 `objectWillChange` 转发上来。SwiftUI 只订阅 `AppState`
/// 自己的变化，所以在页面 body 里读嵌套 ObservableObject 的属性是**读得到值、但不跟着更新**。
///
/// 这不是理论问题：`BlindOrderStatusView` 原先就是那么写的，它看起来能刷新，靠的是本页
/// view model 恰好在 5 秒轮询里持续发布、把整个 body 重算了 —— 巧合而非设计。而这里显示的是
/// **盲人端求助状态**：停在旧值意味着用户听到的是过期结论（比如仍念「正在发送」而其实已经失败），
/// 直接违反「每一种结果都必须可见且可听地如实告知」（`AGENTS.md` §6）。
///
/// 反过来**不要**在 `AppState` 里转发所有子对象的 `objectWillChange`：那会让每次定位采样、
/// 每条 WebSocket 消息都重绘所有订阅 `AppState` 的视图（盲人首页、地图、志愿者首页都在内）。
/// 由需要跟随的那个视图自己订阅，代价才是局部的。
struct EmergencyActionSection: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let onTrigger: () -> Void
    let onCancelOwnEmergency: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            EmergencyActionButton(isLoading: coordinator.state.isBusy, action: onTrigger)

            if let message = coordinator.state.message {
                EmergencyStatusNotice(message: message, isFailure: coordinator.state.isFailure)
            }

            // 只有本人发出、且还没结束的求助才谈得上撤销。判据直接读被观察的 coordinator，
            // 不再经由 view model 绕一手 —— 绕一手就又回到「值对但不刷新」。
            if coordinator.activeEvent != nil {
                Button(EmergencySafetyCopy.cancelButtonTitleForOwner, action: onCancelOwnEmergency)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .accessibilityLabel(EmergencySafetyCopy.cancelButtonTitleForOwner)
                    .accessibilityHint("误触时撤销本次求助，需要确认")
            }
        }
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
