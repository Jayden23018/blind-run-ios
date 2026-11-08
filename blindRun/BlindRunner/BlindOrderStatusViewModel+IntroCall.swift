import SwiftUI

extension BlindOrderStatusViewModel {
    // MARK: - 接单前通话磨合

    /// 拉通话页数据。跟着订单轮询走，不另起一条定时器 —— 这一页本来就每 5 秒刷一次订单。
    ///
    /// **拿不到仍然清空 `introCall`，但必须同时立起 `introCallUnavailable`。**
    ///
    /// 清空是对的，别改成「保留上一轮的号码」：同一个 `PENDING_INTRO_CALL` 里候选人是会换的
    /// （后端 `INTRO_CALL_NOT_ACTIVE` 的说明逐字写着「本轮候选人已换人」），
    /// 留着旧号码就会把电话打给上一位候选人 —— 而屏幕上看不出任何异常。
    ///
    /// 🚨 缺的从来不是「保留数据」，是**说出来**。原来这里是 `try?`，失败与
    /// 「不在通话态」塌缩成同一个 `nil`，于是整块操作区静默消失。
    func refreshIntroCallIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status == .pendingIntroCall else {
            clearIntroCallState()
            return
        }
        do {
            let view = try await appState.orders.introCallView(orderId: order.orderId)
            introCall = view
            if let id = view.counterpartUserId { introCallCounterpartUserId = id }
            introCallUnavailable = false
            // 服务端说了话就以它为准。换了候选人时它是 nil，本地记号跟着作废 ——
            // 见 `submittedIntroCallDecision` 的注释。
            submittedIntroCallDecision = view.myDecisionValue
            handleIntroCallViewUpdate(view)
        } catch {
            introCall = nil
            // 🚩 **已经表过态就不算失败。** 表态服务端已经记下了，拉不到 view 不改变这件事，
            // 而此刻用户没有任何该做而做不了的事 —— 报错只会盖掉他刚听到的确认，
            // 并在屏幕上摆出一个他不该在这一刻碰到的「换一位」。
            guard submittedIntroCallDecision == nil else { return }
            // **只在 false → true 那一跳播一次。** `loadOrder` 每 5 秒重跑一遍，
            // 每轮都播会把读屏用户淹掉 —— 而他要听的是「这次没拿到，可以重试」，
            // 不是同一句话每 5 秒一遍。
            if !introCallUnavailable {
                introCallUnavailable = true
                speechService?.speakError(IntroCallCopy.loadFailed)
            }
        }
    }

    /// 离开通话态、或换单时把这一族状态整组清掉。**三个字段必须一起动** ——
    /// 少清一个就会让下一单一进通话态就顶着上一单的错误块或表态。
    func clearIntroCallState() {
        introCall = nil
        introCallCounterpartUserId = nil
        introCallUnavailable = false
        submittedIntroCallDecision = nil
        clearIntroCallPlanState()
    }

    /// 见面安排单那一族本地状态，**与上面三个同生同灭**：它们都是「这一轮」的，
    /// 留到下一位候选人身上就是在他还没打电话时显示 B2、或者念上一位的安排单。
    private func clearIntroCallPlanState() {
        // 每 5 秒轮询都会经过这里（非通话态）。只在这一轮真看到过安排单时才去撤通知，
        // 免得每轮都打一次系统通知中心。
        if lastSeenIntroCallPlanVersion != nil, let orderId = order?.orderId ?? currentOrderId {
            introCallPlanReminderNotifier.cancel(orderId: orderId)
        }
        hasReturnedFromIntroCallDialer = false
        didDialThisIntroCallRound = false
        confirmedIntroCallPlanVersion = nil
        introCallConfirmFailed = false
        introCallPlanChangedNotice = false
        lastSeenIntroCallPlanVersion = nil
        planChangeAnnouncedFromVersion = nil
        introCallCountdownAnnouncer = IntroCallCountdownAnnouncer()
        introCallPlanReminder = IntroCallPlanReminder()
        introCallNotifyThrottle = IntroCallIncomingNotifyThrottle()
        introCallReminderScheduledFor = nil
        didAnnounceUnreadableIntroCallPlan = false
    }

    /// 每次成功拉到通话数据之后：认出「安排单刚到 / 改了一版」、5 / 1 分钟播报、10 分钟提醒。
    private func handleIntroCallViewUpdate(_ view: IntroCallView) {
        let now = introCallNow()
        let plan = view.meetupPlan
        // 服务端说了话就以它为准：我的表态不是 ACCEPT（换了候选人、或陪跑员改版作废了我的确认），
        // 本地「已确认」跟着作废。
        if view.myDecisionValue != .accept {
            confirmedIntroCallPlanVersion = nil
        }
        // 看过安排单、现在服务端说没有了：同一个 `PENDING_INTRO_CALL` 里换了候选人
        // （后端 `INTRO_CALL_NOT_ACTIVE` 的说明：「本轮候选人已换人」）。上一位的 B2 标记、提醒、
        // 节流都是那一轮的，不许带到新的人身上。
        if view.plan == nil, lastSeenIntroCallPlanVersion != nil {
            clearIntroCallPlanState()
        }
        // 服务端说有安排单、客户端读不懂：通话页显示「暂时拿不到」+ 重新加载（`hasUnreadablePlan`），
        // 这里补上听得到的那半 —— 只在 false → true 那一跳念一次，每 5 秒一遍会把人淹掉。
        if view.hasUnreadablePlan {
            if !didAnnounceUnreadableIntroCallPlan {
                didAnnounceUnreadableIntroCallPlan = true
                speechService?.speakError(IntroCallCopy.loadFailed)
            }
        } else {
            didAnnounceUnreadableIntroCallPlan = false
        }
        if let plan {
            if let last = lastSeenIntroCallPlanVersion {
                if last != plan.version {
                    if planChangeAnnouncedFromVersion == last {
                        // 409 那一刻已经播过「请重新收听」，这是紧接着的那次刷新。
                        planChangeAnnouncedFromVersion = nil
                    } else {
                        announceIntroCallPlanChanged()
                    }
                }
            } else {
                // 安排单第一次出现（含关页重进、杀进程重启）：焦点落标题，并念标题那一句。
                introCallPlanFocusRequest += 1
                let speech = IntroCallMeetupCopy.planSpeech(
                    plan: plan,
                    original: view.originalArrangement,
                    volunteerName: view.counterpartDisplayName(fallback: ""),
                    now: now
                )
                speechService?.speak(speech.title)
            }
            lastSeenIntroCallPlanVersion = plan.version
        }

        let step = introCallRunnerStep
        let windowEndsAt = view.windowEndsAt?.nilIfBlank?.backendTimestamp
        if let windowEndsAt,
           introCallCountdownAnnouncer.nodeToAnnounce(windowEndsAt: windowEndsAt, now: now) != nil {
            speechService?.speak(IntroCallMeetupCopy.countdownAnnouncement(
                windowEndsAt: windowEndsAt, now: now, isReviewingPlan: step == .reviewingPlan
            ))
        }

        introCallPlanReminder.observe(
            planVersion: plan?.version,
            submittedAt: view.plan?.submittedAt?.nilIfBlank?.backendTimestamp,
            isAwaitingConfirmation: step == .reviewingPlan,
            windowEndsAt: windowEndsAt,
            now: now
        )
        if isAppActive, introCallPlanReminder.consumeIfDue(now: now) {
            speechService?.speak(IntroCallCopy.blindPlanReminderSpeech)
        }
    }

    /// 陪跑员改了一版（轮询看到版本变了，或确认时 409 `INTRO_CALL_PLAN_STALE`）。
    /// **不是错误**：不配红条、不念「失败」，焦点回标题、念「请重新收听」。
    private func announceIntroCallPlanChanged() {
        introCallConfirmFailed = false
        introCallPlanChangedNotice = true
        introCallPlanFocusRequest += 1
        speechService?.speak(IntroCallMeetupCopy.planChangedRelisten)
    }

    /// App 前后台切换。由订单页的 `scenePhase` 喂进来 —— 通话页盖在它上面时它也一直在。
    ///
    /// - 回前台判据只认「进过后台」（`IntroCallForegroundReturnDetector`）：拨号确认框点取消、
    ///   权限弹窗走的是 `.inactive → .active`，不许把它们当成「打完电话回来了」（修审查 #8）。
    /// - 10 分钟提醒：进后台时排本地通知，回前台时撤掉；**真排过通知**、且离开期间已经到点的，
    ///   才记成「已提醒」不补播。只走过 `.inactive`（控制中心）、或进后台时已经过点没排上的，
    ///   回来照样由前台轮询念出来 —— 否则这一轮的提醒一次都没响就被记成响过了。
    func observeScenePhase(_ phase: ScenePhase) {
        let returnedFromBackground = introCallForegroundDetector.observe(phase)
        let orderId = order?.orderId
        switch phase {
        case .background:
            isAppActive = false
            let now = introCallNow()
            if let orderId, let dueAt = introCallPlanReminder.dueAt, dueAt > now {
                introCallPlanReminderNotifier.schedule(orderId: orderId, at: dueAt)
                introCallReminderScheduledFor = dueAt
            }
        case .active:
            isAppActive = true
            if let scheduledFor = introCallReminderScheduledFor {
                introCallReminderScheduledFor = nil
                if introCallNow() >= scheduledFor {
                    introCallPlanReminder.markDeliveredWhileAway(now: introCallNow())
                }
                if let orderId { introCallPlanReminderNotifier.cancel(orderId: orderId) }
            }
            guard returnedFromBackground, order?.status == .pendingIntroCall else { return }
            if didDialThisIntroCallRound { hasReturnedFromIntroCallDialer = true }
            // 打完电话回来，陪跑员很可能已经填好了：马上拉一次，别让人对着 B2 等下一轮轮询。
            Task { [weak self] in await self?.reloadIntroCall() }
        default:
            break
        }
    }

    /// 「重新加载」按下时走这里。也是单测的入口：正常路径下通话数据跟着订单轮询一起拉，
    /// 而用例要的是「只拉这一次」—— 起轮询会顺带打订单详情、动状态机，
    /// 把断言埋进一堆无关请求里。
    ///
    /// 2026-08-26 从 `#if DEBUG` 的 `loadIntroCallForTesting` 提成正式方法：
    /// 失败态那个「重新加载」按钮要的正是同一件事，没有理由再留一个只给测试的孪生入口。
    func reloadIntroCall() async {
        guard let order, let appState else { return }
        await refreshIntroCallIfNeeded(for: order, appState: appState)
    }

    /// 先通知对方，然后**立刻**回拨号 URL 给调用方。
    ///
    /// 🚨 **不等响应**：对盲人来说「点了没反应」是最糟的反馈。APNs 到达与对方手机响铃之间
    /// 本就有几秒差，时序天然对得上；推送晚到还有派单文案兜底
    /// （后端 `notify-incoming` 的端点说明逐字写着这一条）。
    ///
    /// 🚨 返回的号码**只能**来自 `dialableCounterpartPhone`。掩码串拼进 `tel:` 会被
    /// `EmergencyDialer.telURL` 取成 `1381234` 拨出去 —— 空号，而界面上看不出任何异常。
    func introCallDialURL() -> URL? {
        guard let order, let appState, let phone = introCall?.dialableCounterpartPhone else { return nil }
        // 在这里就记下「拨过号」，而不是等 `openURL` 回调 —— 系统拨号确认框弹出本身就会让 App 离开前台，
        // 回来时要能认出「刚才去拨号了」（`observeScenePhase`）。
        didDialThisIntroCallRound = true
        // `notify-incoming` 60 秒内最多一次（修审查 #10）。**拨号本身从不拦。**
        if introCallNotifyThrottle.shouldNotify(now: introCallNow()) {
            let orders = appState.orders
            let orderId = order.orderId
            Task {
                // 唯一一处刻意吞掉的错误，理由在上面：这是给对方的一条**预告推送**，
                // 不是拨号的前置条件。它失败时用户该做的事（打这通电话）没有任何变化，
                // 屏幕上也不该多出任何东西 —— 拨号 URL 已经返回，电话照打。
                try? await orders.notifyIntroCallIncoming(orderId: orderId)
            }
        }
        return EmergencyDialer.telURL(for: phone)
    }

    /// B3「确认见面安排」＝ 盲人的「合适」。**带版本号确认**，取代 v6 的「聊过了，合适」
    /// （那条走老入口 `submitIntroCallDecision(.accept)`、不带版本，开关打开后会被 409 `INTRO_CALL_PLAN_REQUIRED`）。
    ///
    /// 三种结局，屏幕与声音各不相同（视觉稿 ④）：
    /// - `.confirmed`：刷订单，订单页那边状态一变就念「约定完成……」（`statusChangeAnnouncement`）；
    /// - `.planChanged`（409 `INTRO_CALL_PLAN_STALE`）：**不是错误**，焦点回标题、念「请重新收听」；
    /// - 其余失败：留在 B3，按钮上方红条 + 念「确认未送达，请重试」（修审查 #3）。
    func confirmIntroCallPlan() async {
        guard let order, let appState, let plan = introCall?.meetupPlan else { return }
        isPerformingAction = true
        errorMessage = nil
        introCallConfirmFailed = false
        do {
            let result = try await appState.orders.confirmIntroCallPlan(orderId: order.orderId, version: plan.version)
            isPerformingAction = false
            switch result {
            case .confirmed:
                confirmedIntroCallPlanVersion = plan.version
                // 理由同 `submittedIntroCallDecision` 的注释：表过态之后再拉不到通话数据不算失败。
                submittedIntroCallDecision = .accept
                introCallPlanChangedNotice = false
                introCallPlanReminderNotifier.cancel(orderId: order.orderId)
                await loadOrder(orderId: order.orderId, speakChanges: true)
            case .planChanged:
                planChangeAnnouncedFromVersion = plan.version
                announceIntroCallPlanChanged()
                await reloadIntroCall()
            }
        } catch let error as APIError {
            isPerformingAction = false
            if error.endsSession { return }
            if error.errorCode == .introCallNotActive {
                // 窗口刚好到点：这一轮已经结束，刷订单让页面回到真实状态，念的是后端的那句。
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
                await loadOrder(orderId: order.orderId, speakChanges: true)
                return
            }
            introCallConfirmFailed = true
            speechService?.speakError(IntroCallMeetupCopy.confirmNotDelivered)
        } catch {
            isPerformingAction = false
            introCallConfirmFailed = true
            speechService?.speakError(IntroCallMeetupCopy.confirmNotDelivered)
        }
    }

    /// 「更换陪跑员」（`DECLINE`）。盲人侧的「合适」**只剩** `confirmIntroCallPlan` 一条路，
    /// 所以这里不再收 `IntroCallDecision` 参数 —— 老的 `ACCEPT` 入口在类型上就调不到了。
    ///
    /// ⚠️ 请求体**没有 reason 字段**，这是后端刻意的：要求填理由等于要求当面说「不」。
    func declineIntroCall() async {
        guard let order, let appState else { return }
        isPerformingAction = true
        errorMessage = nil
        // 听过安排单再换人：先说「本次见面安排未生效」。在刷订单之前取，刷完这一轮的数据就清了。
        let hadPlan = introCall?.plan != nil
        do {
            try await appState.orders.submitIntroCallDecision(.decline, orderId: order.orderId)
            isPerformingAction = false
            // 先落本地记号，再刷订单 —— `loadOrder` 紧接着就会去拉通话数据，
            // 而那一步拉失败时要靠这个记号判「已经表过态，不算失败」。
            // 顺带把失败态收掉：用户是从失败块里按的「更换陪跑员」时，那个块该消失了。
            submittedIntroCallDecision = .decline
            introCallUnavailable = false
            // 🚨 中性、进行时，与常规等待读起来完全一样：不许出现「重新」「换了一位」
            // 这类暗示前面失败过的措辞（无声拒绝）。
            speechService?.speak(BlindIntroCallOutcomeCopy.roundEnded(hadPlan: hadPlan))
            await loadOrder(orderId: order.orderId, speakChanges: false)
        } catch let error as APIError {
            isPerformingAction = false
            if error.endsSession {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            // 409 `INTRO_CALL_NOT_ACTIVE` 的常见成因是窗口已经超时。刷订单让页面回到真实状态，
            // 不重试 —— 重试只会得到同一个 409。
            await loadOrder(orderId: order.orderId, speakChanges: true)
        } catch {
            isPerformingAction = false
            let message = "没有提交成功，请再试一次。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }
}
