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
    /// 🚩 **标题是「求助」不是「一键求助」。** 后者在本 App 里专指云端那条链路（会记录事件、
    /// 通知同行志愿者与客服）。这一层只是个菜单，打开它什么都还没发生 ——
    /// 用同一个词会让看不见屏幕的人以为求助已经发出。云端那一项在菜单里仍叫「一键求助」。
    static let hubTitle = "求助"
    static let hubAccessibilityLabel = "求助，打开求助选项"
    static let hubAccessibilityHint =
        "打开后可以联系志愿者、播报你的位置、拨打120或110，或者发出一键求助。打开这个菜单不会发送求助。"

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
}

/// 陪跑中求助中心里的那几项。
///
/// **做成可单测的纯数据**，理由与 `BlindHomeSOSMode.resolve` 同源：这是安全路径上的
/// 顺序与可见性，而 `confirmationDialog` 的内容在单测里够不着、在 UI 测试里又只有真机一条通道。
/// 漏掉一项或顺序漂了，不会有任何东西变红。
///
/// 🚩 弹窗**由这个列表驱动**（见 `blindActiveRunSafetyHubDialog`），不是并排维护第二份 ——
/// 并排两份的下场是测试钉住了一份、用户看到的是另一份。
enum BlindActiveRunSafetyHubOption: Equatable, CaseIterable {
    case contactVolunteer
    case announceLocation
    case callPrimaryContact
    case callMedical
    case callPolice
    case triggerEmergency

    /// 顺序固定、不随状态变 —— 盲人靠位置记忆，顺序会变的菜单等于没有位置记忆。
    /// 只有「有没有那个号码」决定某一项在不在，**不改其余各项的相对次序**。
    ///
    /// 拨号三项的集合与先后（联系人 → 120 → 110）与首页那套**逐项一致**，
    /// 理由见 `emergencyCallOptionsDialog`：用户记住的是「往下第二个是 120」。
    static func options(
        volunteerPhone: String?,
        primaryContact: EmergencyContactResponse?
    ) -> [BlindActiveRunSafetyHubOption] {
        var options: [BlindActiveRunSafetyHubOption] = []
        // 判据是「拼不拼得出 tel: URL」而不是「字符串非空」：掩码串 `138****1234`
        // 只取数字位会拼成空号，而空号在界面上看不出任何异常（`EmergencyDialer.telURL`）。
        if EmergencyDialer.telURL(for: volunteerPhone) != nil { options.append(.contactVolunteer) }
        options.append(.announceLocation)
        if EmergencyDialer.telURL(for: primaryContact?.phone) != nil { options.append(.callPrimaryContact) }
        options.append(.callMedical)
        options.append(.callPolice)
        options.append(.triggerEmergency)
        return options
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

    var dialogMessage: String {
        switch self {
        case .homeIdle: return EmergencySafetyCopy.homeCallDialogMessage
        case .cloudFailed: return EmergencySafetyCopy.cloudFailedCallDialogMessage
        }
    }

    var accessibilityHint: String {
        switch self {
        case .homeIdle: return EmergencySafetyCopy.homeCallAccessibilityHint
        case .cloudFailed: return EmergencySafetyCopy.cloudFailedCallAccessibilityHint
        }
    }
}

/// 拨号 URL 的唯一构造点。
///
/// 只取数字：后端返回的手机号是明文，但可能带空格或横线，直接拼进 `tel://` 会拼出无效 URL，
/// 而无效 URL 的表现是「点了没反应」—— 对盲人端就是事故。
enum EmergencyDialer {
    static let policeNumber = "110"
    /// 医疗急救。跑步途中摔倒、扭伤、心脏不适对应的是它，不是 110。
    static let medicalNumber = "120"

    static func telURL(for rawNumber: String?) -> URL? {
        guard let digits = rawNumber?.filter(\.isNumber), !digits.isEmpty else { return nil }
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

/// 志愿者端「服务进行中」页的求助入口：地图右上角的圆形悬浮盾牌。
///
/// **为什么不复用 `EmergencyActionButton` 那个全宽横条。** 它此前就是全宽横条，夹在底部操作面板
/// 上方（`VolunteerOrderFlowViews.swift` 的 `emergencySection`），于是：与「结束服务」「取消订单」
/// 同一个组件、同一个宽度、同样落在拇指自然区，而垂直位置还随面板内容高度上下漂移。
/// 对标产品无一例外把安全入口做成「地图角落固定悬浮图标 + 二级确认」，没有一款混排进常规操作列表
/// （Uber Driver 左下盾牌 / Lyft Driver 右上图标 / 滴滴左下「安全中心」，见
/// `docs/research/volunteer-sos-button-placement-20260819.md`）。
///
/// **误触在这一侧的代价比打车场景更高**：后端对志愿者的 `action=FALSE_ALARM` 恒回 403
/// `EMERGENCY_VOLUNTEER_CANNOT_DISMISS` —— 一对一陪跑里志愿者可能就是威胁来源，撤销权只在受助者
/// 本人和客服手里。按错了自己撤不掉，所以「远离拇指区」不只是观感问题。
///
/// 尺寸取 64pt：`small-touch-target` 守卫显式排除 `/blindRun/Volunteer/`（那一侧是明眼人用的，
/// 走 Apple 的 44pt 线），64 只是更好按，不是被强制的。
///
/// 可见文字是「求助」两个字而不是「一键求助」—— 后者在本 App 里专指云端求助这一整套流程
/// （`EmergencySOSTests.swift` 里有断言钉着这个词的归属）。读屏听到的仍是完整的
/// `EmergencySafetyCopy.accessibilityLabel`，两者不冲突。
///
/// 和 `BlindHomeSOSBar` / `BlindActiveRunSafetyAnchor` 同样自己 `@ObservedObject` 持有
/// coordinator：`AppState.emergencyCoordinator` 是 `let` 不是 `@Published`，
/// 在页面 body 里读它的属性是**读得到值、但不跟着更新**（详见 `BlindHomeSOSBar` 的注释）。
struct VolunteerSOSFloatingButton: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if coordinator.state.isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("求助")
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 64, height: 64)
            .background(AppColors.destructive)
            .clipShape(Circle())
        }
        .disabled(coordinator.state.isBusy)
        .accessibilityLabel(EmergencySafetyCopy.accessibilityLabel)
        .accessibilityHint(EmergencySafetyCopy.accessibilityHint)
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
    /// 拼成空号，而空号在界面上看不出任何异常。
    func emergencyCallOptionsDialog(
        isPresented: Binding<Bool>,
        context: EmergencyCallContext,
        primaryContact: EmergencyContactResponse?
    ) -> some View {
        let contactURL = primaryContact.flatMap { EmergencyDialer.telURL(for: $0.phone) }
        let message = contactURL == nil
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

    /// 陪跑中那屏的求助中心。一层操作表，把「联系志愿者 / 播报位置 / 拨号 / 云端求助」收在一起。
    ///
    /// 🔴 **云端求助仍然走二次确认** —— 选了「一键求助」之后弹 `emergencyConfirmationAlert`，
    /// `AGENTS.md` §6 那句逐字锁定的文案留在它该在的地方，一个字不动，一步不减。
    ///
    /// 各项由 `BlindActiveRunSafetyHubOption.options` 驱动，这里只负责把每一项画成按钮 ——
    /// 顺序与可见性的判据在那个枚举上，能被单测直接钉住。
    func blindActiveRunSafetyHubDialog(
        isPresented: Binding<Bool>,
        primaryContact: EmergencyContactResponse?,
        volunteerPhone: String?,
        onAnnounceLocation: @escaping () -> Void,
        onTriggerEmergency: @escaping () -> Void
    ) -> some View {
        let options = BlindActiveRunSafetyHubOption.options(
            volunteerPhone: volunteerPhone,
            primaryContact: primaryContact
        )
        // 没有唯一主联系人时把原因说出来，与首页那套同一句 —— 不说的话菜单只是「少一项」，
        // 而看不见屏幕的人数不出少了哪一项。
        let message = options.contains(.callPrimaryContact)
            ? EmergencySafetyCopy.hubDialogMessage
            : "\(EmergencySafetyCopy.hubDialogMessage)\(EmergencySafetyCopy.homeCallNoContactHint)"

        return confirmationDialog(
            EmergencySafetyCopy.hubTitle,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            ForEach(options, id: \.self) { option in
                switch option {
                case .contactVolunteer:
                    Button(EmergencySafetyCopy.hubContactVolunteerTitle) {
                        EmergencyDialer.telURL(for: volunteerPhone).map { EmergencyDialer.dial($0) }
                    }
                case .announceLocation:
                    Button(EmergencySafetyCopy.hubAnnounceLocationTitle, action: onAnnounceLocation)
                case .callPrimaryContact:
                    Button(EmergencySafetyCopy.homeCallContactTitle(name: primaryContact?.name)) {
                        EmergencyDialer.telURL(for: primaryContact?.phone).map { EmergencyDialer.dial($0) }
                    }
                case .callMedical:
                    Button(EmergencySafetyCopy.homeCallMedicalTitle) {
                        EmergencyDialer.telURL(for: EmergencyDialer.medicalNumber).map { EmergencyDialer.dial($0) }
                    }
                case .callPolice:
                    Button(EmergencySafetyCopy.homeCallPoliceTitle) {
                        EmergencyDialer.telURL(for: EmergencyDialer.policeNumber).map { EmergencyDialer.dial($0) }
                    }
                case .triggerEmergency:
                    Button(EmergencySafetyCopy.title, role: .destructive, action: onTriggerEmergency)
                }
            }
            Button(EmergencySafetyCopy.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(message)
        }
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
