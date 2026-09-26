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
/// 求助二次确认弹窗是给谁看的。
///
/// 分两档而不是复用 `UserRole`：这里要回答的是「按下之后撤不撤得回来」，
/// 而不是「这个人是什么角色」。两者现在一一对应，但前者才是文案的真实依据 ——
/// 哪天客服端也有了触发入口，它的角色是第三种，撤销权却和跑者同档。
enum EmergencyConfirmationAudience {
    /// 受助者本人。有「撤销求助」按钮（`PUT /api/emergency/{id}/cancel`）。
    case runner
    /// 同行志愿者。**没有撤销入口**，后端恒 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`。
    case volunteer
}

enum EmergencySafetyCopy {
    static let title = "一键求助"
    static let confirmButtonTitle = "确认求助"
    static let cancelButtonTitle = "取消"

    /// Mandated verbatim by `AGENTS.md` section 10. Do not reword.
    ///
    /// ⚠️ **这个常量本身一个字都不能动**（两条用例逐字钉着它）。志愿者侧需要多说一句，
    /// 走下面的 `confirmationMessage(for:)` **追加**，不是改写。
    static let confirmationMessage = "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"

    /// 志愿者侧追加的那一句。
    ///
    /// 🔴 **为什么非说不可**：志愿者按下求助之后**没有任何撤销入口** —— 后端对志愿者的
    /// `FALSE_ALARM` 恒 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`，撤销权只在跑者本人和客服手里。
    /// 而上面那句对**盲人**是完整的（他本人有「撤销求助」按钮），对志愿者漏掉了这个动作
    /// **最不可逆的那一半后果** —— 而那恰恰是二次确认存在的理由。
    ///
    /// 🚩 **不要试图把它做成「让志愿者也能撤销」**：一对一陪跑里志愿者可能就是威胁来源
    /// （`AGENTS.md` §6），给他一个「把报警撤掉」的按钮是这条红线本身要防的事。
    /// 后端也不会放行，前端加了只能吃 403。
    ///
    /// 代价照说：紧急场景下多一句会拖慢阅读。但拖慢的是**按下确认之前**，
    /// 而这一句正是他做决定需要的那个事实。
    static let volunteerIrreversibleSuffix = "本次求助只有跑者本人或客服能撤销。"

    static func confirmationMessage(for audience: EmergencyConfirmationAudience) -> String {
        switch audience {
        case .runner:
            return confirmationMessage
        case .volunteer:
            return "\(confirmationMessage)\n\(volunteerIrreversibleSuffix)"
        }
    }

    static let accessibilityLabel = "一键求助，遇到紧急情况时点击"
    static let accessibilityHint = "需要二次确认，确认后会向后台发送求助并上报当前位置"

    /// Appended to every terminal-ish state. The app is not a rescue service and says so.
    static let emergencyCallReminder = "若情况危急请立即拨打110。"

    static let locating = "正在获取当前位置，请稍候。"
    static let submitting = "正在发送求助，请稍候。"

    // MARK: 紧急倒计时（屏 3）

    /// 倒计时那一屏的标题。**用「即将发出」不用「正在发出」** ——
    /// 这三秒里一个字节都还没发出去，而说成进行时会让人以为取消已经来不及。
    static let countdownTitle = "紧急求助即将发出"

    /// 每一秒念一次。**「可以取消」必须每秒都在** —— 看不见屏幕的人不会知道
    /// 屏幕下方有一个取消按钮，除非有人一直在告诉他。
    static func countdown(secondsRemaining: Int) -> String {
        "紧急求助将在 \(max(secondsRemaining, 0)) 秒后发出，现在取消还来得及。"
    }

    /// 进倒计时那一刻念一次的「即将发生什么」。
    ///
    /// 🔴 **三条都是进行时或将来时，一条完成时都没有。** 这不是文风选择：
    /// 短信是在触发事务提交之后异步发的、失败也从不回告盲人（`AGENTS.md` §6），
    /// 所以 App 永远不能说「已经通知了谁」。这里说的是**我们会去做什么**，不是做成了什么。
    static let countdownPendingEffects = [
        "通知你的陪跑志愿者",
        "转给客服并回拨你",
        "把你的实时位置一起发出",
    ]

    static let countdownCancelTitle = "取消"
    static let countdownCancelAccessibilityHint = "立刻停止倒计时，不会发出任何求助"

    /// 倒计时被取消。**第一句先说「没有发出」**，与 `locationUnavailable` / `homeCallDialogMessage`
    /// 同源：看不见屏幕的人最需要先知道的是什么都没发生。
    static let countdownCancelled = "已取消，没有发出求助。"

    /// 服务端倒计时内撤回成功（`PUT /cancel` 回 `CANCELLED`）。iOS 定稿文案，后端 #388 ②。
    ///
    /// 🔴 **一个字都不提家属和短信** —— 那一路是 `cancelOwnerSucceeded`（`FALSE_ALARM`，发出过、
    /// 要补解除短信）。这一态外面一个人都不知道，说「已更正」等于告诉他刚才有人被惊动了。
    static let withdrawnBeforeSending = "已撤回。求助没有发出，没有通知任何人。"

    /// 倒计时里按了取消，但撤回请求没成功。**服务端的倒计时不会因此停下**，
    /// 所以必须说「可能已经发出」，而不是「已取消」。
    static let withdrawFailedTitle = "撤回没有成功"
    static func withdrawFailed(_ reason: String?) -> String {
        let detail = reason?.trimmed.isEmpty == false ? reason!.trimmed : "网络异常"
        return "撤回没有成功：\(detail)。求助可能已经发出，不要当作已经取消。\(emergencyCallReminder)"
    }

    // MARK: 求助已发出（屏 3b）

    static let sentTitle = "求助已发出"

    /// 🔴 **这一屏顶部那句大标题，必须与此刻的真实状态一致。**
    ///
    /// 2026-09-15 code review 抓到的缺陷长这样：原实现是三行 `if`，`.locating` 与
    /// `.submitting` 两态既不是倒计时、又没有 `activeEvent`、又不是失败，于是落进最后那个
    /// `else` —— 屏幕顶部 44pt 的红色大标题写着**「求助已发出」**，而正文写着
    /// 「正在获取当前位置，请稍候」，此刻**一个字节都还没发出去**。
    /// 那段窗口最长约 20 秒（等定位 5 秒 + 请求超时 15 秒），而标题带 `.isHeader`，
    /// VoiceOver 用户滑到页首听到的就是这句。这是 `AGENTS.md` §6
    /// 「App 永远不得宣称求助已发出」的同一形状。
    ///
    /// 失败时它又会回落成「紧急求助即将发出」—— 一句将来时的**承诺**，
    /// 而事实是这条求助已经死了、必须手动再发一次。
    ///
    /// 改成**穷举 switch 的纯函数**：新增状态时编译器逼一次决策，而且能被单测直接钉住
    /// （`if/else` 的取值 `testNoEmergencyCopyClaimsAnSMSWasDelivered` 那种扫常量的用例够不着）。
    static let sendingTitle = "正在发出求助"
    static let unsentTitle = "求助未发出"
    static let cancelledTitle = "求助已撤销"

    static func screenTitle(for state: EmergencySOSState, hasActiveEvent: Bool) -> String {
        switch state {
        case .countingDown:
            return countdownTitle
        // 还在路上。**进行时**，因为此刻确实什么都还没发出去。
        case .locating, .submitting:
            return sendingTitle
        // 后端受理了。`contactNotifyFailed` 也在这里：失败的是**通知联系人**，
        // 求助本身已经发出去了（正文会把「对方没收到短信」说清楚）。
        case .acknowledged, .contactSmsDelivered, .contactNotifyFailed:
            return sentTitle
        case .cancelledByOwner:
            return cancelledTitle
        // 一个字节都没发出去的三种，加上倒计时内撤回（事件落过库，但求助从未发出）。
        case .unsentNoLocation, .failed, .cooldown, .withdrawnBeforeSending:
            return unsentTitle
        // 撤回失败：服务端倒计时还在走，发没发出不知道 —— 两个完成时都不许用。
        case .withdrawFailed:
            return withdrawFailedTitle
        // `.idle` 在这一屏只可能来自恢复（`activeEvent` 先到、状态还没跟上）
        // 或对账把陈旧事件清掉之后。有事件就是已发出，没有就是没发出 —— 不猜。
        case .idle:
            return hasActiveEvent ? sentTitle : unsentTitle
        }
    }

    /// 屏 3b 上那两个号码。**只调起系统拨号，不自动拨出** —— 自动拨号会把一个
    /// 还在判断情况的人直接接进 110 接警台。
    static let sentCallMedicalHint = "调起拨号界面，由你按下通话键"
    static let sentCallPoliceHint = "调起拨号界面，由你按下通话键"

    /// 没发出去时的重试。**由用户按，不自动重发。**
    ///
    /// 后端 `POST /api/emergency/trigger` 没有幂等 key，自动重发要么建出第二个事件、
    /// 要么撞 60 秒冷却回 429 —— 而 429 的文案是「请稍后再试」，会把一个**已经生效**
    /// 的求助说成被拒绝。「刚才那条到底发出去没有」由只读的 `GET /api/emergency/active`
    /// 对账（`EmergencyCoordinator.reconcile(after:)`），不靠重发去试。
    static let retrySendTitle = "再发一次求助"
    static let retrySendAccessibilityHint = "重新发送这次求助。如果上一次其实已经发出，系统会告诉你。"

    /// Not sent, because no fresh real coordinate was available. Says "未发出" first: the most
    /// important fact for someone who cannot see the screen is that nothing has been sent.
    ///
    /// **第二句必须跟着 `LocationService.locationError` 分岔。** 原文对所有定位失败都说
    /// 「请在设置中允许定位后重试」，可是室内 / 隧道 / 遮挡拿不到 GPS 时权限是好的 ——
    /// 让一个正处在紧急状态的盲人去翻设置，是把最贵的那几十秒花在一个不存在的问题上。
    /// `.timeout` 与 `nil`（Core Location 没报错，只是还没给出定位）归到同一支：
    /// 对用户而言可做的动作相同，都是换个地方重试。
    static func locationUnavailable(_ reason: LocationError?) -> String {
        switch reason {
        case .permissionDenied:
            return "求助未发出：App 没有定位权限。请在设置中允许定位后重试，或直接拨打110。"
        case .locationUnavailable, .timeout, .none:
            return "求助未发出：当前无法获取你的位置，可能在室内或信号被遮挡。请到室外开阔处重试，或直接拨打110。"
        }
    }

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
        // 恢复时可能读到（截止已过、服务端还没来得及推成正式求助）。不说「已发出」。
        case .countdown:
            return "求助正在倒计时，马上就会发出。\(emergencyCallReminder)"
        case .cancelled:
            return withdrawnBeforeSending
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

    // MARK: 志愿者端·陪跑中（屏 4）

    static func volunteerEscortHeadline(name: String?) -> String {
        "你正在陪跑 · \(name?.nilIfBlank ?? "被陪同者")"
    }

    static let volunteerPeerStatusLabel = "他的状态"
    static let volunteerPeerStatusNormal = "正常"
    static let volunteerPeerStatusEmergency = "求助中"

    /// 志愿者按过「我在他身边，去处理」之后。
    ///
    /// 🔴 **不能回落成「正常」。** 他按的那一下只是告诉客服「现场有人了」，求助本身
    /// 仍然是开的 —— 同一屏上另一句话写着「这条求助只有他本人或客服能撤销」
    /// （`volunteerAlertNoDismissNotice`）。写「正常」会让志愿者扫一眼就得出
    /// 「这事过去了」，而那与屏 5 刻意不写「客服已接入」是同一条红线：
    /// **不知道的事不许说**，已经结束同样是一件我们不知道的事。
    ///
    /// 也不能继续顶着红色的「求助中」—— 那会让一个**新的**求助在视觉上完全淹没掉。
    /// 所以是第三档：既不宣称结束，也不再报警。
    static let volunteerPeerStatusAcknowledged = "已确认，客服处理中"
    static let volunteerPeerLocationLabel = "位置共享"
    static let volunteerPeerLocationOn = "已开启"

    /// 🚩 措辞是「暂时收不到」不是「已断开」。
    ///
    /// 客户端判的只是「最近一条 `BLIND_LOCATION_UPDATE` 还新不新鲜」
    /// （`VolunteerServiceViewModel.latestBlindSample` 过期即置 nil）——
    /// 那可能是对方进了地下通道、也可能是他关了权限，**两者我们分不出来**。
    /// 说成「已断开」像是在陈述一个已经查明的事实，会让志愿者据此做判断
    /// （比如认为对方故意关了共享）。
    static let volunteerPeerLocationStale = "暂时收不到"

    /// ⛔ **没有「他的电量」这一行。** 设计稿上有，但后端没有这个字段
    /// （`api_spec.yaml` 的订单与轨迹响应里都没有电量），编一个数字出来比不显示危险得多 ——
    /// 志愿者会据此判断「他手机还能撑多久」。缺口已投递后端，回来了再加这一行。
    static let volunteerSafetyHubTitle = "求助与安全"

    // MARK: 志愿者端·收到紧急求助（屏 5）

    static func volunteerAlertTitle(name: String?) -> String {
        "\(name?.nilIfBlank ?? "被陪同者")发起紧急求助"
    }

    /// 「X 秒前」。**读的是本机收到的时刻**，不是后端时间戳 —— 两端时钟差几秒到几分钟时，
    /// 屏幕上会出现「-40 秒前」或凭空多出的「3 分钟前」，而志愿者正据此判断
    /// 「这事刚发生，还是我漏看了很久」。
    static func volunteerAlertElapsed(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds) 秒前" }
        return "\(seconds / 60) 分钟前"
    }

    /// ⛔ **不写「客服已接入」。** 设计稿上有这一句，但志愿者端**无从知道** ——
    /// `EMERGENCY_VOLUNTEER_ALERT` 的字段里没有客服状态（`websocket-protocol.md:546`），
    /// 而 `GET /api/emergency/active` 角色限 `BLIND`，志愿者调不了。
    /// 写上去就是编造一个「已经有人在处理了」的安心感，而它可能是假的。
    static let volunteerAlertLocationUnknown = "暂时收不到他的位置"
    static let volunteerAlertLocationResolving = "正在确定他的位置…"

    static func volunteerAlertCallTitle(name: String?) -> String {
        "呼叫\(name?.nilIfBlank ?? "被陪同者")"
    }

    /// 底部主动作。**这句话是一个承诺**：按下去等于告诉客服「现场有人了」，
    /// 所以它说的必须是志愿者真的做得到的事 —— 人在旁边、正在处理。
    static let volunteerAlertAcknowledgeTitle = "我在他身边，去处理"

    /// 按钮下面那行小字。**只说「同步给客服」，不说客服会做什么** ——
    /// 后端拿到 `NEED_HELP` 之后怎么调度不在客户端的知识范围里。
    static let volunteerAlertAcknowledgeFootnote = "确认后同步给客服"
    static let volunteerAlertAcknowledgeHint = "确认被陪同者确实需要帮助，客服会介入"

    /// 🔴 **志愿者端没有「误触 / 关掉」。** 后端对 `action=FALSE_ALARM` 恒 403
    /// `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`：一对一陪跑里志愿者可能就是威胁来源，
    /// 撤销权只在受助者本人和客服手里。这一屏因此**没有关闭按钮** ——
    /// 它只会在志愿者确认之后、或求助被本人/客服结束之后消失。
    static let volunteerAlertNoDismissNotice = "这条求助只有他本人或客服能撤销。"

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

    /// 120 与 110 是两回事，不能只留一个：这个 App 的用户在**跑步**，
    /// 摔倒、扭伤、心脏不适是最可能发生的紧急情况，而它们对应的是急救不是报警。
    /// 2026-09-08 之前全仓只有 110 的可点入口，「110或120」只作为文字出现在状态提示里 ——
    /// 对看不见屏幕的人，念得出来而按不到，等于没有。
    static let homeCallMedicalTitle = "拨打120"

    static func homeCallContactTitle(name: String?) -> String {
        "拨打\(name?.nilIfBlank ?? "紧急联系人")"
    }

    /// 没有唯一主联系人时的提示。`singlePrimary` 在 0 个或多个时都返回 nil，
    /// 两种情况对用户是同一件事：现在没有一个确定该拨给谁的号码。
    static let homeCallNoContactHint = "尚未设置唯一的主紧急联系人，只能拨打120或110。"

    /// 陪跑员订单页的「求助」（非跑步中）。第一句同样先说「App 不会代你发送求助」。
    ///
    /// 不写「还没开始跑步」：完成页与跑者取消页也用这一句，那两态跑步要么结束了、要么不会发生。
    static let volunteerBeforeRunCallDialogMessage =
        "现在不在跑步中，App 不会代你发送求助。请选择要拨打的号码。"
    static let volunteerBeforeRunCallAccessibilityHint =
        "现在不在跑步中。点击后由你选择拨打120或110，App 不会代你发送求助。"

    // MARK: 云端求助失败后的本地拨号兜底

    /// 复用上面那套本地拨号弹窗，但**第一句不能照抄** —— `homeCall*` 那两句的开头是
    /// 「当前没有进行中的陪跑」，而这条分支恰恰发生在陪跑进行中、且刚刚按过求助键。
    /// 说错这一句会让盲人以为自己按错了地方。要说的事实只有一个：求助没发出去。
    ///
    /// 最坏时序是等定位 5 秒（`EmergencyCoordinator.locationWaitTimeout`）+ 请求超时 15 秒
    /// （`APIClient` 的 `timeoutIntervalForRequest`），按下按钮到听见「未发出」最长 20 秒。
    /// 那之后再让人退出 App 盲操作找电话，是本仓库能自己消掉的最贵一段延迟。
    static let cloudFailedCallAccessibilityHint =
        "求助没有发出去。点击后由你选择拨打紧急联系人或110，App 不会代你发送求助。"

    static let cloudFailedCallDialogMessage =
        "求助没有发出去，App 不会代你发送求助。请选择要拨打的号码。"

    // 2026-09-15 删掉了第三种语境 `inProgress`（「这是直接打电话，不是一键求助…」）。
    //
    // 它存在的理由是「两个红色按钮挨在一起，用户要靠第一句判断自己按的是哪一个」——
    // 而产品定稿把陪跑中那一屏改成执行屏之后，**屏幕上只剩一个红块**，那个歧义源头没有了。
    // 现在从求助中心进拨号，第一句由 `hubDialogMessage` 承担（「还没有发送求助」）。
    //
    // 连同那个 case 一起删，而不是留着不调用：留一份没有调用点的安全文案，
    // 下一次改红线时没有任何东西会提醒它也要跟着改。

    // MARK: 陪跑中的求助中心（Safety Hub）

    /// 陪跑中那屏底部**唯一**的红块。产品定稿 2026-09-15：Active Run 是执行屏不是仪表盘 ——
    /// 「打电话给志愿者」不再常驻主屏，它和拨号、播位置、云端求助一起收进这一层。
    ///
    /// 🚩 **标题不含「一键求助」四个字。** 那四个字在本 App 里专指云端那条链路（会记录事件、
    /// 通知同行志愿者与客服）。这一层只是个菜单，打开它什么都还没发生 ——
    /// 用同一个词会让看不见屏幕的人以为求助已经发出。云端那一项在菜单里仍叫「一键求助」。
    static let hubTitle = "求助与安全"

    /// 屏 1 底部那块红色入口的副标题。**它是长按这条路径唯一的告知途径** ——
    /// 长按 3 秒会跳过二次确认直接进倒计时（见 `emergencyConfirmationAlert` 的注释），
    /// 一个不知道自己能长按的人不会误触，而一个不知道长按会跳过确认的人会。
    static let hubEntrySubtitle = "轻点打开 · 长按 3 秒紧急求助"

    static let hubAccessibilityLabel = "求助与安全，打开求助选项"
    static let hubAccessibilityHint =
        "双击打开求助中心，或上下轻扫选择紧急求助。打开这个菜单不会发送求助。"

    /// 求助中心的副标题。**「跑步仍在记录」不是装饰** —— 盲人从执行屏跳进一层盖满屏幕的
    /// 弹层之后，第一个会冒出来的疑问就是「我的跑步是不是停了」。不回答它，
    /// 有人会为了确认而退出弹层，而那正是他打开它时最不该做的事。
    static let hubSubtitle = "跑步仍在记录"

    /// 🔴 **非 `IN_PROGRESS` 时那句话是假的，必须换。**
    ///
    /// 2026-09-16 起求助中心也从订单页四步骨架打开，而那四态（匹配 / 约好 / 出发 / 汇合）
    /// **没有任何跑步在记录** —— 念「跑步仍在记录」不只是多余，它和同一段里紧接着的
    /// 「陪跑还没开始」直接打架。而这一段是 `.combine` 合成**一个**无障碍元素的，
    /// 读屏用户听到的是一句自相矛盾的话，中间没有停顿可以让他判断哪半句算数。
    ///
    /// 这一档要回答的是同一个问题的另一个答案：他刚离开的那一页还在不在。
    static let hubSubtitleBeforeTheRun = "这一单还没开始陪跑"

    static func hubSubtitle(for mode: BlindHomeSOSMode) -> String {
        switch mode {
        case .cloudTrigger: return hubSubtitle
        case .localCall: return hubSubtitleBeforeTheRun
        }
    }

    /// 收起弹层。**不是右上角的 ✕** —— 管状视力用户看不到角落，可操作元素一律走中间一列。
    static let hubDismissTitle = "收起，返回跑步"

    /// 同上：非 `IN_PROGRESS` 时「返回跑步」指向一个不存在的页面。
    /// 骨架那四态退回去看到的是订单页，不是跑步执行屏。
    static let hubDismissTitleBeforeTheRun = "收起，返回订单"

    static func hubDismissTitle(for mode: BlindHomeSOSMode) -> String {
        switch mode {
        case .cloudTrigger: return hubDismissTitle
        case .localCall: return hubDismissTitleBeforeTheRun
        }
    }

    /// 收起按钮的 hint。与标题同理，两档指向的页面不是同一个。
    static func hubDismissHint(for mode: BlindHomeSOSMode) -> String {
        switch mode {
        case .cloudTrigger: return "收起求助中心，回到跑步页面"
        case .localCall: return "收起求助中心，回到订单页面"
        }
    }

    /// 🔴 第一句必须是「还没有发送求助」。理由与 `locationUnavailable` / `homeCallDialogMessage`
    /// 同源：看不见屏幕的人按下一个红色大块之后，最需要先知道的是**什么都还没发生**。
    ///
    /// ⛔ **不得把 `confirmationMessage` 挪到这里。** 那句逐字锁定的话是**二次确认**的文案，
    /// 而这一层的第一项是「联系志愿者」这种无害动作 —— 把「是否确认进入求助状态？」
    /// 印在这份菜单上面，等于告诉用户选任何一项都会发出求助。
    /// 云端那一项选中后照常走 `emergencyConfirmationAlert`，`AGENTS.md` §6 的二次确认不减一步。
    static let hubDialogMessage = "还没有发送求助。请选择你现在要做的事。"

    static let hubContactVolunteerTitle = "联系志愿者"
    static let hubAnnounceLocationTitle = "播报我的位置"
    static let hubAskQuestionTitle = "问一句"

    /// 🔴 **非 `IN_PROGRESS` 打开求助中心时，底部那条必须说这句话。**
    ///
    /// 2026-09-16 起求助中心不再只从陪跑执行屏进入 —— 订单页四步骨架的底部也有一枚
    /// 「求助与安全」，而那四个状态（匹配 / 约好 / 出发 / 汇合）**一个都不是 `IN_PROGRESS`**。
    /// 云端求助两端都只在 `IN_PROGRESS` 开放（`AGENTS.md` §6），所以在那四态按下云端那条
    /// 红胶囊的真实结果是：`EmergencyCoordinator.beginCountdown` 在资格 guard 处落
    /// `.failed("当前订单状态不能发起求助")`、`startEmergencyCountdown` 因此不弹全屏，
    /// 而骨架那一屏**没有 `EmergencyStatusNotice` 的渲染点** ——
    /// 于是长按 3 秒或轻点确认之后，屏幕零变化、一个字也不播。
    /// 那正是记忆 `claimed-fallback-may-not-exist-in-release` 说的第二种吃法，
    /// 而它长在这个 App 唯一救命的那条路径上。
    ///
    /// 所以那四态的底部整条降级为**本地拨号**，与首页/「我的」tab 那条求助条同一条判据
    /// （`BlindHomeSOSMode.resolve`）、同一套弹窗（`emergencyCallOptionsDialog`）。
    static let hubLocalCallNotice = "陪跑还没开始，下方的紧急呼叫只会直接拨号，App 不会代你发送求助。"

    /// 「把这次行程告诉家人」那一格。
    ///
    /// 标题不在这里 —— 它随「分享中 / 未分享」变，取自 `RunPlanLiveShareCopy.buttonTitle`
    /// 与 `stopButtonTitle`（那两串上记着不许宣称送达的约束，不复制第二份）。
    static let hubShareLiveLocationSubtitle = "家人能看到你的位置"
    static let hubStopShareLiveLocationSubtitle = "链接立刻失效"

    /// 每一格标题下面那行小字。**说的是「按下去会发生什么」，不是同义词复述** ——
    /// 「联系志愿者 / 陪跑员」对看不见的人等于把同一个词说两遍。
    ///
    /// 做成穷举 switch 而不是给每个 case 配一个静态串：新增一项时编译器逼一次决策，
    /// 漏写一格的表现是「屏幕上少一行字」，而那种缺陷不会有任何东西变红。
    static func hubTileSubtitle(
        _ option: BlindActiveRunSafetyHubOption,
        contactName: String?,
        isLiveSharing: Bool = false
    ) -> String {
        switch option {
        case .contactVolunteer: return "直接拨给陪跑员"
        case .announceLocation: return "读出你现在的位置"
        case .askQuestion: return "用说的问，比如还有多久"
        case .callPrimaryContact: return contactName?.nilIfBlank ?? "紧急联系人"
        case .callMedical: return "摔倒、受伤、身体不适"
        case .callPolice: return "报警"
        case .shareLiveLocation:
            return isLiveSharing ? hubStopShareLiveLocationSubtitle : hubShareLiveLocationSubtitle
        case .triggerEmergency: return hubTriggerSubtitle
        }
    }

    /// 云端求助那一项。**只有它走后端**，所以它是这一层里唯一不可逆的动作。
    static let hubTriggerSubtitle = "按住 3 秒"
    static let hubTriggerAccessibilityHint =
        "双击并按住 3 秒发出紧急求助；也可以直接双击，双击需要再确认一次。发出前有 3 秒倒计时可以取消。"

    /// 屏 1 与屏 2 共用的那条自定义无障碍动作名。
    ///
    /// 🔴 **它按「长按」算，不再弹二次确认。** VoiceOver 下的「双击并按住」不稳定
    /// （这正是 Apple 建议用自定义动作替代它的理由），而自定义动作本身是两步刻意操作：
    /// 上下轻扫选中 + 双击执行。把它降级成「轻点」等于让读屏用户永远多走一步确认，
    /// 而那一步对他们最贵 —— 弹窗会抢走焦点、要重新找按钮。倒计时是所有路径共同的反悔窗口。
    static let emergencyAccessibilityActionName = "紧急求助"

    /// 「播报我的位置」的答句。
    ///
    /// 拿不到就说拿不到，**不编**。陪跑中报错的位置会被当成真位置转述给 110 —— 这一句是
    /// 「盲人端给假数据的代价高于视觉端」那条原则里最贵的一处。
    static func locationAnnouncement(_ place: String?) -> String {
        guard let place, let name = place.nilIfBlank else {
            return "暂时定位不到你的位置。如果情况紧急，请直接拨打110或120说明你周围的情况。"
        }
        return "你现在在\(name)附近。"
    }

    /// 服务端坐标超过这个秒数就要说出它有多旧（`demo/docs/safety-hub-ui-spec.md` 屏 2）。
    /// 跑步时 28 秒前和 1 秒前差着几百米，而从地址字符串上听不出来。
    static let locationStaleAfterSeconds = 15

    /// 「这是 N 秒前的位置。」`ageSeconds` 为 null 时不提 —— 不知道就不说，不编一个 0。
    static func locationAgeNotice(_ ageSeconds: Int?) -> String? {
        guard let ageSeconds, ageSeconds > locationStaleAfterSeconds else { return nil }
        return "这是\(ageSeconds)秒前的位置。"
    }

    static func coordinateText(latitude: Double, longitude: Double) -> String {
        String(format: "北纬%.4f、东经%.4f", latitude, longitude)
    }

    /// 盲人端「播报我的位置」走 `GET /api/orders/{id}/location/address` 时的答句（三种结果，恒 200）。
    static func locationAnnouncement(server response: OrderLocationAddressResponse) -> String {
        let age = locationAgeNotice(response.ageSeconds) ?? ""
        if let address = response.formattedAddress?.nilIfBlank {
            return locationAnnouncement(address) + age
        }
        if let latitude = response.latitude, let longitude = response.longitude {
            return "暂时查不到地址。你的坐标是\(coordinateText(latitude: latitude, longitude: longitude))。" + age
        }
        return locationAnnouncement(nil)
    }

    /// 志愿者强提醒地址卡上「他在哪」那一行（拿到的是盲人的位置，不是自己的）。
    /// nil = 连坐标都没有，调用方显示 `volunteerAlertLocationUnknown`。
    static func volunteerAlertPlace(server response: OrderLocationAddressResponse) -> String? {
        let place: String
        if let address = response.formattedAddress?.nilIfBlank {
            place = address
        } else if let latitude = response.latitude, let longitude = response.longitude {
            place = coordinateText(latitude: latitude, longitude: longitude)
        } else {
            return nil
        }
        guard let age = locationAgeNotice(response.ageSeconds) else { return place }
        return "\(place)。\(age)"
    }
}

/// 陪跑中求助中心里的那几项。
///
/// **做成可单测的纯数据**，理由与 `BlindHomeSOSMode.resolve` 同源：这是安全路径上的
/// 顺序与可见性，而 `confirmationDialog` 的内容在单测里够不着、在 UI 测试里又只有真机一条通道。
/// 漏掉一项或顺序漂了，不会有任何东西变红。
///
/// 🚩 弹层**由这个列表驱动**（见 `BlindSafetyHubView`），不是并排维护第二份 ——
/// 并排两份的下场是测试钉住了一份、用户看到的是另一份。
enum BlindActiveRunSafetyHubOption: Equatable, CaseIterable {
    case contactVolunteer
    case announceLocation
    /// 语音问一句。它**早就实现好了**（`BlindOrderStatusViewModel.askVoiceQuestion()`），
    /// 2026-09-15 之前一直是执行屏上的一个安静文字按钮，这次随其余四项一起收进这一层。
    case askQuestion
    case callPrimaryContact
    case callMedical
    case callPolice
    /// 把这次行程告诉家人（实时分享链接）。
    ///
    /// 🚩 **它是迁移进来的，不是新功能**（设计稿 §3.5 的迁移表：「分享实时位置给家人 →
    /// 求助与安全中心」）。改版前它是订单页那条滚动列表里的一个 64pt 次级按钮
    /// （`BlindOrderStatusView.runPlanShareSection`），而四步骨架替换了那条列表 ——
    /// 不迁进来的话，`PENDING_MATCH` → `DRIVER_ARRIVED` 这四态**一个入口都没有**，
    /// 而 `offersRunPlanShare` 恰好覆盖的就是这四态。
    ///
    /// ⚠️ 排在**最后一格**，不是插在中间：拨号三项的位置一格都不许动
    /// （见 `options` 的注释）。
    case shareLiveLocation
    case triggerEmergency

    /// 顺序固定、不随状态变 —— 盲人靠位置记忆，顺序会变的菜单等于没有位置记忆。
    /// 只有「有没有那个号码」决定某一项在不在，**不改其余各项的相对次序**。
    ///
    /// 拨号三项的集合与先后（联系人 → 120 → 110）与首页那套**逐项一致**，
    /// 理由见 `emergencyCallOptionsDialog`：用户记住的是「往下第二个是 120」。
    ///
    /// 🚩 **三个拨号项没有被折进一个「紧急呼叫」二级入口。** 那样确实能凑成设计稿上的
    /// 2×2，但代价是跑步途中拨 120 从一跳变成两跳 —— 而 `AGENTS.md` §6 把 120 列成
    /// 与 110 并列的常驻入口，理由恰恰是「念得出来而按不到等于没有」。
    /// 格子数由这个列表决定（最多 7 格），不由设计稿的行数决定。
    ///
    /// - Parameter offersLiveShare: 这一单此刻能不能开分享链接。由调用方按
    ///   `RunOrderStatus.offersRunPlanShare` 传进来 —— 终态后端返 409，摆一个
    ///   按下去必然报错的格子对读屏用户是纯噪音。
    static func options(
        volunteerPhone: String?,
        primaryContact: EmergencyContactResponse?,
        offersLiveShare: Bool = false
    ) -> [BlindActiveRunSafetyHubOption] {
        var options: [BlindActiveRunSafetyHubOption] = []
        // 判据是「拼不拼得出 tel: URL」而不是「字符串非空」：掩码串 `138****1234`
        // 会被 `telURL` 的掩码闸拦掉（不拦则拼成 `tel://1381234`，一个可能真打给别人的号码）。
        if EmergencyDialer.telURL(for: volunteerPhone) != nil { options.append(.contactVolunteer) }
        options.append(.announceLocation)
        options.append(.askQuestion)
        if EmergencyDialer.telURL(for: primaryContact?.phone) != nil { options.append(.callPrimaryContact) }
        options.append(.callMedical)
        options.append(.callPolice)
        if offersLiveShare { options.append(.shareLiveLocation) }
        options.append(.triggerEmergency)
        return options
    }

    /// 画成方格的那几项。云端求助**不在内** —— 它是弹层底部整条的红胶囊，
    /// 与其余各项不是同一个视觉层级，也不是同一种后果。
    static func tiles(
        volunteerPhone: String?,
        primaryContact: EmergencyContactResponse?,
        offersLiveShare: Bool = false
    ) -> [BlindActiveRunSafetyHubOption] {
        options(
            volunteerPhone: volunteerPhone,
            primaryContact: primaryContact,
            offersLiveShare: offersLiveShare
        )
        .filter { $0 != .triggerEmergency }
    }

    /// SF Symbol。图标是**冗余通道**：色盲用户与低视力用户靠形状区分，
    /// 而读屏用户完全听不到它 —— 所以每一格的标题必须独立成立，图标不承担语义。
    var symbolName: String {
        switch self {
        case .contactVolunteer: return "phone.fill"
        case .announceLocation: return "location.fill"
        case .askQuestion: return "mic.fill"
        case .callPrimaryContact: return "person.crop.circle.fill"
        case .callMedical: return "cross.case.fill"
        case .callPolice: return "shield.lefthalf.filled"
        // `person.2.wave.2.fill` 要 iOS 16.1 —— 同下面 `sos` 那条的坑。这个从 iOS 13 就有。
        case .shareLiveLocation: return "square.and.arrow.up.fill"
        // ⛔ **不用 `sos`。** 那个符号是 iOS **16.1** 才有的（SF Symbols 4，
        // `name_availability.plist` 里写着 2022.1 → iOS 16.1），而本仓库部署目标是 iOS 16.0 ——
        // 在 16.0 上它渲染成空白，而且不报错、不崩，只是这一格没有图标。
        case .triggerEmergency: return "exclamationmark.triangle.fill"
        }
    }

    /// - Parameter isLiveSharing: 分享中时这一格的标题换成「停止分享实时位置」。
    ///   `RunPlanLiveShareStore` 的注释里写着为什么这个状态只能来自本地记录
    ///   （后端没有查询分享状态的端点），而告知页逐字承诺了「你可以随时停止分享」——
    ///   所以这一格必须能变成「停止」，否则那句承诺在这一层里就不成立。
    func title(contactName: String?, isLiveSharing: Bool = false) -> String {
        switch self {
        case .contactVolunteer: return EmergencySafetyCopy.hubContactVolunteerTitle
        case .announceLocation: return EmergencySafetyCopy.hubAnnounceLocationTitle
        case .askQuestion: return EmergencySafetyCopy.hubAskQuestionTitle
        case .callPrimaryContact: return EmergencySafetyCopy.homeCallContactTitle(name: contactName)
        case .callMedical: return EmergencySafetyCopy.homeCallMedicalTitle
        case .callPolice: return EmergencySafetyCopy.homeCallPoliceTitle
        case .shareLiveLocation:
            return isLiveSharing
                ? RunPlanLiveShareCopy.stopButtonTitle
                : RunPlanLiveShareCopy.buttonTitle
        case .triggerEmergency: return EmergencySafetyCopy.title
        }
    }
}

/// 本地拨号弹窗的两种语境。**只差第一句**，而那一句每次都得说对：
/// 它回答的是「我刚才那一下到底发生了什么」，说错会让盲人把「什么都没发生」当成「求助已发出」。
///
/// 做成枚举而不是让调用方各传一个字符串：两处都在安全路径上，谁漏了一句
/// 都不会有任何运行时症状 —— 弹窗照常弹，只是话说错了。
///
/// 2026-09-15 由三种减为两种：`inProgress`（陪跑中主动拨号）的调用点已并入求助中心
/// `blindActiveRunSafetyHubDialog`，它的第一句由 `hubDialogMessage` 承担。
enum EmergencyCallContext {
    /// 首页，当前没有进行中的陪跑。
    case homeIdle
    /// 云端求助刚刚失败（首页与订单状态页共用）。
    case cloudFailed
    /// 陪跑员订单页右上角「求助」，不在跑步中（邀请到完成 / 跑者取消，`VolunteerOrderSOSMode.localCall`，2026-09-26）。
    ///
    /// 不复用 `homeIdle`：那句「当前没有进行中的陪跑」对一个正骑车赶去集合点的陪跑员不成立。
    case volunteerBeforeRun

    var dialogMessage: String {
        switch self {
        case .homeIdle: return EmergencySafetyCopy.homeCallDialogMessage
        case .cloudFailed: return EmergencySafetyCopy.cloudFailedCallDialogMessage
        case .volunteerBeforeRun: return EmergencySafetyCopy.volunteerBeforeRunCallDialogMessage
        }
    }

    var accessibilityHint: String {
        switch self {
        case .homeIdle: return EmergencySafetyCopy.homeCallAccessibilityHint
        case .cloudFailed: return EmergencySafetyCopy.cloudFailedCallAccessibilityHint
        case .volunteerBeforeRun: return EmergencySafetyCopy.volunteerBeforeRunCallAccessibilityHint
        }
    }

    /// 「尚未设置唯一的主紧急联系人」那句只对跑者成立 —— 陪跑员这里本来就不列联系人。
    var appendsNoContactHint: Bool { self != .volunteerBeforeRun }
}

/// 拨号 URL 的唯一构造点。
///
/// 只取数字：后端返回的手机号是明文，但可能带空格或横线，直接拼进 `tel://` 会拼出无效 URL，
/// 而无效 URL 的表现是「点了没反应」—— 对盲人端就是事故。
enum EmergencyDialer {
    static let policeNumber = "110"
    /// 医疗急救。跑步途中摔倒、扭伤、心脏不适对应的是它，不是 110。
    static let medicalNumber = "120"

    /// 掩码标记。`EmergencyContactResponse.maskPhone` 与后端下发的掩码串都用半角 `*`
    /// （契约里的样例逐字是 `138****1234`）；全角一并拦住，成本为零。
    ///
    /// **没有一个可拨号码含 `*`**，所以这条判据没有误报面。`*67` 那类电信功能码
    /// 本 App 从不拨（唯一的号码来源是后端明文号 + 写死的 110/120）。
    private static let redactionMarkers: Set<Character> = ["*", "＊"]

    /// 拼 `tel:` URL。**两道闸，缺一条都会拨错号。**
    ///
    /// ① 只取数字位 —— 后端明文号可能带空格或横线，直接拼会拼出无效 URL，
    ///    而无效 URL 的表现是「点了没反应」。
    ///
    /// ② 🚨 **带掩码标记的一律拒掉。** 这一条是 2026-08-11 那个真实缺陷的机器守卫。
    ///    在它之前，判据只有「取完数字位还剩不剩」，于是掩码串 `138****1234`
    ///    **拼得出** `tel://1381234` —— 不是空号，是一个**七位的、可能真打给别人**的号码，
    ///    而界面上看不出任何异常。
    ///
    ///    `IntroCallTests.testVolunteerSideViewHasNothingDialable` 原先逐字写着
    ///    「类型上拦不住（两个字段都是 String?），只能靠『拨号入口只读另一个字段』」——
    ///    **类型上拦不住，值上拦得住。** 靠「记得读对字段」的规则已经失效过一次，
    ///    而它有 15 个调用点；按 `AGENTS.md` §1，这种事该落成检查而不是留在注释里。
    ///
    /// 🚩 provenance 那道防线（`IntroCallView.dialableCounterpartPhone` 恒 nil）
    /// **保留不动**。两道互不替代：那道管「这个字段该不该用来拨号」（语义），
    /// 这道管「这个值长得能不能拨」（形状）。后端某天真下发了掩码串时只有这道拦得住。
    static func telURL(for rawNumber: String?) -> URL? {
        guard let rawNumber else { return nil }
        guard !rawNumber.contains(where: redactionMarkers.contains) else { return nil }
        let digits = rawNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }

    /// **唯一的拨出点。** 三处调用方（首页本地拨号、订单状态页拨志愿者、语音确认拨号）都走这里，
    /// 所以「测试期不许真的拨出去」只需要拦一处。新增拨号入口也必须走它 ——
    /// `scripts/hooks/guard.mjs` 的 `raw-open-url` 会拦住绕开这里的 `UIApplication.shared.open`。
    ///
    /// 2026-08-14：真机 UI 测试里一次误触走到了 `tel://110`，只因那台 iPhone 是双卡、
    /// iOS 多弹了一层选号单才没拨出去 —— 单卡设备上会直接拨给警方。误触本身已修（断言前先滚动），
    /// 但只要拨号这条路在测试构建里通着，下一次触点飘到底部常驻求助条上就会重演。
    ///
    /// 拦截**只存在于 DEBUG**：Demo / Release 里 `#if` 整段不编译，真实拨号行为一个字节没变
    /// （`AGENTS.md` §6）。所以走 DemoRelease 的云端冒烟用例仍然拨得出去，那条通道靠用例自己
    /// 先滚动再点来保证。
    static func dial(_ url: URL, open: (URL) -> Void = { UIApplication.shared.open($0) }) {
        #if DEBUG
        if isDialBlockedForUITesting {
            blockedDialCount += 1
            // 不静默：留一条能断言、也能在真机日志里看见的痕迹 ——
            // 「按下去确实要拨」和「没有真的拨」都得能证明。
            ClientFlowDiagnostics.record(event: "blocked", operation: "tel-dial")
            return
        }
        #endif
        open(url)
    }

    #if DEBUG
    static let uiTestBlockEnvironmentKey = "AIDRUN_UI_TEST_BLOCK_TEL_DIAL"

    /// 默认值取自启动环境。做成可写的 var 是为了单测能直接翻开关，不必去改进程环境。
    static var isDialBlockedForUITesting =
        resolveDialBlock(from: ProcessInfo.processInfo.environment)

    /// 显式开关优先；没设时，**只要这是 UI 测试注入的启动环境就默认拦**。
    ///
    /// 不要求每个启动 helper 都记得设那个键：本仓库有四处 `launchEnvironment` 装配
    /// （`blindRunUITests.launchApp`、`AccessibilityAuditTests` 的两个、`blindRunUITestsLaunchTests`），
    /// 「新加一处时记得也加一行」正是 `AGENTS.md` §1 说的挡不住的做法。
    /// 真要在某条用例里放行真实拨号，显式传 `AIDRUN_UI_TEST_BLOCK_TEL_DIAL=0`。
    static func resolveDialBlock(from environment: [String: String]) -> Bool {
        if let explicit = environment[uiTestBlockEnvironmentKey] {
            return explicit == "1"
        }
        return environment["AIDRUN_UI_TEST_RESET_STATE"] == "1"
    }

    private(set) static var blockedDialCount = 0

    static func resetBlockedDialCountForTesting() {
        blockedDialCount = 0
    }
    #endif
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
    /// 云端求助失败后的兜底出口。与 `.localCall` 分支按的是**同一个**拨号弹窗，
    /// 只是文案换成不再声称「没有进行中的陪跑」。
    let onLocalCall: () -> Void

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

                // 求助没发出去时，屏幕上必须有一个**能按的东西**，而不只是一段说明。
                // 覆盖 `.unsentNoLocation` / `.failed` / `.cooldown` / `.contactNotifyFailed`
                // 四种 `isFailure`，判据直接读 `state.isFailure`，新增失败态自动进来。
                if coordinator.state.isFailure {
                    PrimaryButton(
                        EmergencySafetyCopy.homeCallTitle,
                        isDestructive: true,
                        action: onLocalCall
                    )
                    .accessibilityLabel(EmergencySafetyCopy.homeCallAccessibilityLabel)
                    .accessibilityHint(EmergencySafetyCopy.cloudFailedCallAccessibilityHint)
                    .accessibilityIdentifier("blindRunnerHomeSOSFailureCallButton")
                }
            }
        }
        .accessibilityIdentifier("blindRunnerHomeSOSBar")
    }
}

/// 志愿者端「服务进行中」页的求助入口：**系统导航栏右侧**的红色「求助」胶囊（2026-09-26 起）。
///
/// **为什么不复用 `EmergencyActionButton` 那个全宽横条。** 它此前就是全宽横条，夹在底部操作面板
/// 上方（`VolunteerOrderFlowViews.swift` 的 `emergencySection`），于是：与「结束服务」「取消订单」
/// 同一个组件、同一个宽度、同样落在拇指自然区，而垂直位置还随面板内容高度上下漂移。
/// 对标产品无一例外把安全入口做成「屏幕角落的固定图标 + 二级确认」，没有一款混排进常规操作列表
/// （Uber Driver 左下盾牌 / Lyft Driver 右上图标 / 滴滴左下「安全中心」，见
/// `docs/research/volunteer-sos-button-placement-20260819.md`）。
///
/// 🔴 **为什么从「地图右上角的 64pt 悬浮圆盾」挪进导航栏（#217）。** 悬浮圆盾和底部那一叠是 ZStack 的
/// 两层，靠「右上 vs 贴底，几何上不重叠」才没被盖住。09-15 三数字卡加进底部那一叠之后假设破了：
/// iPhone 16 Pro 上它被整张卡盖住，看不到也点不到，而且没有任何东西报错。试过把它和底部那一叠
/// 放进同一个 VStack —— 竖屏修好了，横屏（高 402pt）却把底部面板压到 0，「长按结束」被挤出屏幕。
/// 导航栏**不占内容区**：横竖屏都不会被盖、也不挤面板。读屏在返回键、标题之后就念到它。
/// 方向与陪跑员订单页 v2 右上角的求助胶囊一致。
///
/// **误触在这一侧的代价比打车场景更高**：后端对志愿者的 `action=FALSE_ALARM` 恒回 403
/// `EMERGENCY_VOLUNTEER_CANNOT_DISMISS` —— 一对一陪跑里志愿者可能就是威胁来源，撤销权只在受助者
/// 本人和客服手里。按错了自己撤不掉，所以「远离拇指区」不只是观感问题 —— 导航栏在屏幕最上方。
///
/// 触达 ≥44pt：`small-touch-target` 守卫显式排除 `/blindRun/Volunteer/`（那一侧是明眼人用的，
/// 走 Apple 的 44pt 线）。字号封顶 `xxxLarge`：导航栏高度是固定的，再大就会被裁掉。
///
/// 可见文字是「求助」两个字而不是「一键求助」—— 后者在本 App 里专指云端求助这一整套流程
/// （`EmergencySOSTests.swift` 里有断言钉着这个词的归属）。读屏听到的仍是完整的
/// `EmergencySafetyCopy.accessibilityLabel`，两者不冲突。
///
/// 和 `BlindHomeSOSBar` / `BlindRunSafetyResultSection` 同样自己 `@ObservedObject` 持有
/// coordinator：`AppState.emergencyCoordinator` 是 `let` 不是 `@Published`，
/// 在页面 body 里读它的属性是**读得到值、但不跟着更新**（详见 `BlindHomeSOSBar` 的注释）。
struct VolunteerSOSNavButton: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if coordinator.state.isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("求助")
                    .font(AppFonts.caption().weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(AppColors.destructive, in: Capsule())
        }
        // 导航栏里的按钮默认会被染成 tint 色、去掉自定义底色，`.plain` 保住红底白字。
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .disabled(coordinator.state.isBusy)
        // 2026-09-26 起它打开的是跑步中求助面板（DECISIONS-v2 V5），不再直接进求助确认框 ——
        // 读屏再念「一键求助」就是在说一件按下去不会发生的事。「一键求助」四个字留给面板里那枚紧急按钮。
        .accessibilityLabel(VolunteerRunCopy.navButtonLabel)
        .accessibilityHint(VolunteerRunCopy.navButtonHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("volunteerServiceSOSButton")
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

extension View {
    /// 本地拨号弹窗的**唯一**构造点。首页与订单状态页共用，理由不是省代码：
    /// 号码集合（联系人 / 120 / 110）和它们的先后顺序必须两页一致 —— 看不见屏幕的人
    /// 靠位置记住「往下第二个是 120」，两页排得不一样，记住的那个位置就成了陷阱。
    ///
    /// 号码一律经 `EmergencyDialer.telURL`：它只取数字位，掩码串（`138****1234`）会被
    /// 拼成 `tel://1381234` —— 不是空号，是个可能真打给别人的七位号码，而界面上看不出任何异常。
    func emergencyCallOptionsDialog(
        isPresented: Binding<Bool>,
        context: EmergencyCallContext,
        primaryContact: EmergencyContactResponse?
    ) -> some View {
        let contactURL = primaryContact.flatMap { EmergencyDialer.telURL(for: $0.phone) }
        let message = contactURL == nil && context.appendsNoContactHint
            ? "\(context.dialogMessage)\(EmergencySafetyCopy.homeCallNoContactHint)"
            : context.dialogMessage

        return confirmationDialog(
            EmergencySafetyCopy.homeCallTitle,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            if let contactURL {
                Button(EmergencySafetyCopy.homeCallContactTitle(name: primaryContact?.name)) {
                    EmergencyDialer.dial(contactURL)
                }
            }
            if let medicalURL = EmergencyDialer.telURL(for: EmergencyDialer.medicalNumber) {
                Button(EmergencySafetyCopy.homeCallMedicalTitle) { EmergencyDialer.dial(medicalURL) }
            }
            if let policeURL = EmergencyDialer.telURL(for: EmergencyDialer.policeNumber) {
                Button(EmergencySafetyCopy.homeCallPoliceTitle) { EmergencyDialer.dial(policeURL) }
            }
            Button(EmergencySafetyCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    /// 陪跑中那屏的求助中心（屏 2）。
    ///
    /// **从 `confirmationDialog` 换成自定义弹层**（2026-09-15）。系统操作表扛不住这一屏的三条要求：
    /// 它的按钮不接受长按手势、遍历顺序由系统定（求助排不到第一）、也放不下每项的说明小字。
    /// 换来的代价是焦点管理要自己做，见 `BlindSafetyHubView`。
    ///
    /// 🔴 **轻点「一键求助」仍然走二次确认** —— `AGENTS.md` §6 那句逐字锁定的文案一个字不动、
    /// 一步不减。只有**长按 3 秒**和**自定义无障碍动作**这两条刻意路径跳过它（换成倒计时）。
    ///
    /// - Parameter mode: 底部整条走云端求助还是本地拨号。判据复用
    ///   `BlindHomeSOSMode.resolve` —— 与首页/「我的」tab 那条求助条同一条，
    ///   理由见 `EmergencySafetyCopy.hubLocalCallNotice`。
    func blindActiveRunSafetyHubSheet(
        isPresented: Binding<Bool>,
        mode: BlindHomeSOSMode,
        primaryContact: EmergencyContactResponse?,
        volunteerPhone: String?,
        locationError: LocationError?,
        offersLiveShare: Bool = false,
        isLiveSharing: Bool = false,
        onAnnounceLocation: @escaping () -> Void,
        onAskQuestion: @escaping () -> Void,
        onToggleLiveShare: @escaping () -> Void = {},
        onLocalCall: @escaping () -> Void,
        onTriggerEmergency: @escaping () -> Void,
        onTriggerEmergencyImmediately: @escaping () -> Void
    ) -> some View {
        modifier(
            SafetyHubPresentation(
                isPresented: isPresented,
                mode: mode,
                primaryContact: primaryContact,
                volunteerPhone: volunteerPhone,
                locationError: locationError,
                offersLiveShare: offersLiveShare,
                isLiveSharing: isLiveSharing,
                onAnnounceLocation: onAnnounceLocation,
                onAskQuestion: onAskQuestion,
                onToggleLiveShare: onToggleLiveShare,
                onLocalCall: onLocalCall,
                onTriggerEmergency: onTriggerEmergency,
                onTriggerEmergencyImmediately: onTriggerEmergencyImmediately
            )
        )
    }

    /// 求助的二次确认。
    ///
    /// 🔴 **`audience` 没有默认值是刻意的。** 两侧的后果不一样（志愿者按下去撤销不了），
    /// 而「哪一侧」是调用点才知道的事。给了默认值，将来新增的入口会默默拿到另一侧的文案，
    /// 而那正是这次要修的缺陷本身。
    func emergencyConfirmationAlert(
        isPresented: Binding<Bool>,
        audience: EmergencyConfirmationAudience,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(EmergencySafetyCopy.title, isPresented: isPresented) {
            Button(EmergencySafetyCopy.confirmButtonTitle, role: .destructive, action: onConfirm)
            Button(EmergencySafetyCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(EmergencySafetyCopy.confirmationMessage(for: audience))
        }
    }
}
