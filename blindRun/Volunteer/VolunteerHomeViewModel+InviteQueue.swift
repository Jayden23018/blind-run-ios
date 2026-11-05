import Combine
import SwiftUI

// MARK: - 邀请队列（设计交付 v3 §4.4，后端 #371 / #366）
//
// 写在类外、同一个文件里：仍能动 private 状态（同文件扩展看得见），又不让类体继续变大（SwiftLint 棘轮 #488）。
extension VolunteerHomeViewModel {
    /// 首页标签上的数字角标（§4.4.1「首页标签加数字角标」）。
    ///
    /// 陪跑进行中恒 0：那一档设计稿要求「不推送、不横幅、不震动」，
    /// 而一枚红点同样是打断。它们会在他跑完回到接单主页时以卡片出现。
    var inviteBadgeCount: Int {
        guard !isEscortUnderway else { return 0 }
        return invitesAwaitingReply.count
    }

    /// 他此刻正走在某一单里（§4.4.1 那行「已出发 / 汇合 / 跑步中 / 等待中」）。
    ///
    /// 取 `activeOrder` 的状态而不是 `activeOrder != nil`：后端
    /// `VolunteerService.loadActiveOrders` 的白名单今天恰好就是这三态，
    /// 而「恰好相等」不是契约 —— 白名单一旦放宽，`!= nil` 会静默把「约好」也算成陪跑中，
    /// 表现是人还在家里就再也收不到邀请提示。
    var isEscortUnderway: Bool {
        activeOrder?.status.isEscortUnderway ?? false
    }

    /// 横幅到时间收起，或者用户点了「查看」。**不动队列**：收起横幅不等于回复。
    func dismissInviteBanner() {
        bannerInvite = nil
    }

    /// 横幅上的「查看」：顶出邀请卡，横幅让位。
    func presentInviteSheetFromBanner() {
        bannerInvite = nil
        isInviteSheetPresented = true
    }

    /// 连续 3 次「去不了」之后，接单主页上那句不带惩罚的询问该不该出现（§4.4.3）。
    var shouldAskAboutAvailability: Bool { declineStreak.shouldAskAboutAvailability }
    /// 每次现取当前账号的（#552）：换账号后读到的是新账号自己的数，不会带上上一个人的。
    var declineStreak: VolunteerDeclineStreak {
        VolunteerDeclineStreak(persistence: appState?.persistence, userID: appState?.userId)
    }

    /// 问过一次就够。反复问就成了惩罚，而设计稿写死了「不做任何惩罚」。
    func acknowledgeAvailabilityPrompt() {
        declineStreak.acknowledgeAsked()
        objectWillChange.send()
    }

    /// 与 `AppRealtimeCoordinator` 的队列对账。
    ///
    /// 🚩 **是对账不是覆盖**：本地这一队里可能有已经出结果的（`.accepted` / `.expired`），
    /// 而协调器那边一出结果就把它移走了。直接赋值会让「已约好」那张卡当场消失，
    /// 正是 §4.4.3 点名不要的「关掉再弹一个新的」。
    func syncInvites(with prompts: [RealtimeDispatchPrompt]) {
        // 按**邀请身份**判认不认识（后端 #371）：同一张单的新邀请（新 `inviteId`）不能因为 `orderId` 见过就被跳过。
        for prompt in prompts where !invites.contains(where: {
            $0.id == prompt.order.orderId && !AppRealtimeCoordinator.isDifferentInvite($0.order, prompt.order)
        }) {
            enqueue(
                order: prompt.order,
                receivedAt: prompt.receivedAt,
                expiresAt: prompt.expiresAt
            )
        }
        resolveLockScreenAccept()
    }

    /// - Parameters:
    ///   - presentation: 这一条该怎么出现（设计交付 v3 §4.4.1）。默认按当下状态现算；
    ///     UI 测试的种子那条路**显式传 `.inviteCard`** —— 它验的就是邀请卡的无障碍形状，
    ///     而种子是在 `configure` 里跑的，那一刻接单主页还没打开，现算会落到 `.banner`。
    ///   - announces: 震动 / 提示音 / 播报的总闸。UI 测试的种子那条路传 `false` ——
    ///     种下 N 条就响 N 声，而那台真机正拿在跑测的人手里。
    func enqueue(
        order: WSNewOrder,
        receivedAt: Date,
        expiresAt: Date,
        supplement: VolunteerInviteSupplement? = nil,
        presentation: VolunteerInvitePresentation? = nil,
        announces: Bool = true
    ) {
        guard makeRoomForInvite(order) else { return }
        let remaining = max(0, Int(ceil(expiresAt.timeIntervalSinceNow)))
        guard remaining > 0 else { return }
        let mode = presentation ?? VolunteerInvitePresentation.resolve(
            isEscortUnderway: isEscortUnderway,
            isOnDispatchHub: isDispatchHubVisible
        )
        let invite = VolunteerInviteState(
            order: order,
            receivedAt: receivedAt,
            expiresAt: expiresAt,
            remainingSeconds: remaining,
            outcome: nil,
            // 推送自带就用推送的（后端 #306 / #357 起全都有）；老服务端才等 `/available` 来补。
            supplement: supplement ?? VolunteerInviteSupplement(order),
            arrivedDuringEscort: mode == .stashedDuringRun
        )
        invites.append(invite)
        invites.sort { $0.expiresAt < $1.expiresAt }
        if currentInviteID == nil { currentInviteID = invites.first?.id }
        if mode.presentsInviteSheet { isInviteSheetPresented = true }
        // 🚩 横幅只在**没有**邀请卡开着时顶出来。他已经在看卡了，再在头顶压一条
        // 「新的陪跑邀请 · 查看」是在请他打开他正看着的那个东西。
        if mode.showsBanner, !isInviteSheetPresented { bannerInvite = invite }
        appState?.realtimeCoordinator.markDispatchPresented(orderID: order.orderId)
        if announces {
            // 设计交付 v3 §4.4.1：邀请卡那一档「轻震一次 + 短提示音一次（跟随静音开关）」，
            // 横幅那一档「轻震一次，**无声音**」，陪跑中那一档三样都不要。
            //
            // 震动留在同步路径上：`HapticFeedback` 只是往 `UIImpactFeedbackGenerator` 递一下，
            // 不碰音频会话，也不做 IO。
            if mode.vibrates { HapticFeedback.play(.tick) }

            // 🔴 **提示音与播报必须让出这一拍。** 上面那行 `isInviteSheetPresented = true`
            // 已经把 spring 起跑了，而这两样都是**同步占住主线程**的重活：
            // `VolunteerInviteCue` 首次要合成 WAV、写盘、`AudioServicesCreateSystemSoundID`；
            // `speak` 要激活音频会话。跟动画挤在同一拍里，掉的就是卡片升起的头几帧
            // —— 表现是「弹出来一顿一顿的」，而没有任何东西会报错。
            //
            // 挪到下一个 runloop：动画的第一帧先画出去，声音晚十几毫秒没人听得出来。
            var vocalization: (() -> Void)?
            if mode.makesSound {
                vocalization = { [weak self] in
                    // 三条通道各说一遍同一件事 —— 震动对听觉被占用的人、
                    // 提示音对没看屏幕的人、播报对读屏用户。
                    VolunteerInviteCue.play()
                    self?.speechService?.speak("新的陪跑邀请，\(VolunteerOrderFlowCopy.replyCountdown(seconds: remaining))")
                }
            } else if mode.showsBanner {
                vocalization = { [weak self] in
                    // 走 `announce` 而不是 `speak`：`announce` 在 VoiceOver 关着时是 no-op，
                    // 正好满足「无声音」；开着时读屏用户仍然知道头顶多了一条东西
                    // —— SwiftUI 不会为凭空出现的 overlay 自己发通告。
                    self?.speechService?.announce(VolunteerInviteCopy.bannerTitle)
                }
            }
            if let vocalization {
                DispatchQueue.main.async(execute: vocalization)
            }
        }
        startInviteTicker()
        loadInviteSupplements()
    }

    /// 去 `GET /api/orders/available` 给队列里还缺三项的邀请补上视力 / 引导方式 / 跑多久。
    ///
    /// 🚩 **补不到就那一行不渲染，不占位、不编、不报错。** 后端有两种合法的空数组
    /// （志愿者还没上报过位置、资质未通过审核），而这一条对志愿者是纯增益 ——
    /// 为它弹一句错误提示只会盖住正在走的回复窗口。
    ///
    /// 已经在飞的那条不重开：一条派单进来时队列里往往还有别的，它们要的是同一份列表。
    private func loadInviteSupplements() {
        guard inviteSupplementTask == nil,
              invites.contains(where: { $0.supplement == nil }),
              let appState else { return }
        inviteSupplementTask = Task { [weak self] in
            let orders = try? await appState.orders.availableOrders()
            guard let self else { return }
            // **先清再判**：清晚了的话一次取消就把这条路永久堵死，
            // 而症状只是「跑者那一行再也不出现」—— 没有任何东西会报警。
            self.inviteSupplementTask = nil
            guard !Task.isCancelled, let orders else { return }
            // 🚩 补上来的是跑者那一行（视力 / 引导方式 / 跑多久），它一落地卡片就长高一截。
            // 这条请求常常正好在弹卡的 spring 还没走完时回来，于是卡片在升起途中「跳」一下。
            // **过渡动画挂在视图那一侧**（`VolunteerInviteSheet.cardContent` 上的
            // `.animation(…, value: hasRunnerSupplement)`）—— 它才拿得到
            // `accessibilityReduceMotion`，view model 里写 `withAnimation` 会绕过那道降级。
            self.invites = VolunteerInviteState.merge(orders, into: self.invites)
        }
    }

    func markInvite(orderID: Int64, outcome: VolunteerInviteState.Outcome) {
        guard let index = invites.firstIndex(where: { $0.id == orderID }) else { return }
        invites[index].outcome = outcome
        currentInviteID = orderID
    }

    /// 一张还在等回复的邀请失效了（撤回推送 / 快照里已没有 / 「接下」被 409 拒）。
    ///
    /// 规则与本地过期（`tickInvites`）一致：**正在看的那一张**原地变「已失效」并念出原因
    /// （§4.4.3，后端原话「卡片上会留着一个点了必定失败的按钮」不行）；其余的静默移除 ——
    /// 给一张他从没看过的卡再弹一次「已失效」是纯噪音。
    ///
    /// - Parameter userInitiated: 是他刚按了「接下」才知道的（409）。那时**无论卡片开没开着**都要原地变化并念出来 ——
    ///   他按了，就得有回应；静默移除就是「点了没反应」。
    func invalidateInvite(
        orderID: Int64,
        inviteID: Int64?,
        outcome: VolunteerInviteState.Outcome,
        userInitiated: Bool = false
    ) {
        // 撤销窗口里的那张不在 `invites` 里：记下来，撤销时以「已失效」恢复，而不是复活一个必定 409 的按钮（审查 A5）。
        if let declined = pendingDecline, declined.matches(orderID: orderID, inviteID: inviteID) {
            pendingDeclineInvalidation = outcome
            return
        }
        guard let index = invites.firstIndex(where: { $0.matches(orderID: orderID, inviteID: inviteID) }),
              invites[index].isAwaitingReply else {
            // 他刚按了「接下」，而卡片已经因为撤回推送被收走了：仍然要回应他，否则就是「点了没反应」（审查 B2）。
            if userInitiated {
                speechService?.speak("\(VolunteerInviteCopy.expiredTitle)，\(VolunteerInviteCopy.invalidatedDetail(outcome))")
            }
            return
        }
        guard userInitiated || (invites[index].id == currentInviteID && isInviteSheetPresented) else {
            removeInvite(orderID: orderID)
            return
        }
        currentInviteID = orderID
        invites[index].outcome = outcome
        appState?.realtimeCoordinator.clearDispatch(
            orderID: orderID,
            inviteID: invites[index].order.inviteId,
            retiredUntil: invites[index].expiresAt
        )
        speechService?.speak("\(VolunteerInviteCopy.expiredTitle)，\(VolunteerInviteCopy.invalidatedDetail(outcome))")
    }

    /// 与服务端待回复快照对账（后端 #366）。只看**请求发出之前**就到手的卡：请求在路上时到的新邀请不在快照里。
    func reconcileInvites(with snapshot: RealtimePendingInviteSnapshot) {
        let stale = invites.filter { invite in
            invite.isAwaitingReply
                && invite.receivedAt < snapshot.requestedAt
                && !snapshot.contains(orderID: invite.id, inviteID: invite.order.inviteId)
        }
        for invite in stale {
            invalidateInvite(orderID: invite.id, inviteID: invite.order.inviteId, outcome: .withdrawn(.noLongerPending))
        }
        // 撤销窗口里那张不在 `invites` 里，同样要对：快照里没有它 ⇒ 撤销时以「已失效」恢复。
        if let declined = pendingDecline,
           declined.receivedAt < snapshot.requestedAt,
           !snapshot.contains(orderID: declined.id, inviteID: declined.order.inviteId) {
            pendingDeclineInvalidation = .withdrawn(.noLongerPending)
        }
        if let count = snapshot.consecutiveDeclineCount {
            declineStreak.adoptServerCount(count)
            objectWillChange.send()
        }
        resolveLockScreenAccept(after: snapshot)
    }

    /// 从队列移走一条。
    ///
    /// 🔴 **同时把协调器那一份也清掉，这一行不能挪到调用方。** `syncInvites` 是「只增不减」的
    /// （结果卡要留在屏幕上，而协调器一出结果就把它移走了），所以只删本地的话，
    /// **下一条推送到达时它会被重新灌回来** —— 表现是已经回复过 / 已经收掉的邀请又弹出来。
    /// 收成一处是因为调用点有五个（回复成功、结果卡收起、去不了、过期、登出），
    /// 而「忘了清协调器」在任何一处都是同一个 bug。
    func removeInvite(orderID: Int64) {
        // 带上邀请身份与原期限：只清同一张，并让协调器记下「已了结」—— 撤销窗口里的一次对账
        // 不会再把它灌回来（审查 A3），同一张单的新邀请也不会被顺手删掉（A2）。
        let card = invites.first { $0.id == orderID }
        appState?.realtimeCoordinator.clearDispatch(
            orderID: orderID,
            inviteID: card?.order.inviteId,
            retiredUntil: card?.expiresAt
        )
        invites.removeAll { $0.id == orderID }
        if currentInviteID == orderID { currentInviteID = invites.first?.id }
        // 横幅指的就是这一条时一起收掉 —— 留着的话它会在这条邀请已经过期 / 已经回复之后
        // 继续挂 4 秒，点「查看」弹出的是一张别人的卡。
        if bannerInvite?.id == orderID { bannerInvite = nil }
        if invites.isEmpty {
            isInviteSheetPresented = false
            countdownTask?.cancel()
            countdownTask = nil
        }
    }

    /// 用户在结果卡上点「知道了 / 回到接单」：把这一条收掉，自动翻到下一条；
    /// 全部回复完就收起整张 sheet（§4.4.2「回复一个后自动切到下一个，全部回复完自动收起」）。
    func dismissInvite(orderID: Int64) {
        removeInvite(orderID: orderID)
    }

    /// 结果卡上的「查看订单」。**这是接下之后唯一进订单页的路**（不再自动 push）。
    func openAcceptedOrder(orderID: Int64) {
        removeInvite(orderID: orderID)
        acceptedDispatchOrderId = orderID
    }

    /// 一条 ticker 刷整队。归零那一刻**不发 `DECLINE`** ——
    /// 后端 `app.dispatch.per-volunteer-timeout-seconds` 到点自己 `dispatchToNext`
    /// （`DispatchScheduler.java:140-143`），客户端再发一条只会撞上「这一单已经不归他了」的 409，
    /// 而那个错误既没法处理也不该弹给用户。
    func startInviteTicker() {
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.tickInvites() else { return }
            }
        }
    }

    /// 返回「还要不要继续跑 ticker」。
    private func tickInvites() -> Bool {
        guard !invites.isEmpty else {
            countdownTask = nil
            return false
        }
        for index in invites.indices where invites[index].isAwaitingReply {
            invites[index].remainingSeconds = max(0, Int(ceil(invites[index].expiresAt.timeIntervalSinceNow)))
            if invites[index].remainingSeconds == 0 {
                invites[index].outcome = .expired
            }
        }
        // 正在看的那一条过期了就留在原地变「已失效」（§4.4.3 最后一行）；
        // 其余过期的静默移除 —— 给一张他从没看过的卡再弹一次「已失效」是纯噪音。
        let staleIDs = invites
            .filter { $0.outcome?.isInvalidated == true && $0.id != currentInviteID }
            .map(\.id)
        for id in staleIDs { removeInvite(orderID: id) }
        // 队列里只剩结果卡（已约好 / 已失效）时也停：它们没有任何还在走的数字，
        // 而用户可能就把那张卡开着不动。让一条每秒醒一次的任务在那儿空转是白烧电。
        if invites.allSatisfy({ !$0.isAwaitingReply }) {
            countdownTask = nil
            return false
        }
        return true
    }

    /// 同一张单已经有一张卡时让不让位。返回 `false` = 这条不进队。
    ///
    /// 同一张邀请就不进第二条。**不同的一张**（新 `inviteId`，后端 #371：
    /// 撤回之后那轮通话没打成，会给你同一张单发新邀请）替掉旧卡 —— 旧卡可能已经失效，也可能
    /// 撤回推送还没到（断线期间被撤回、重连对账先把新的那张灌进来）；同一张单同一时刻只有一张邀请有效，
    /// 而新来的那张就是。只有「已接下」的卡不替（那时后端不会再发这张单的邀请）。
    /// 直接改数组而不走 `removeInvite`：后者会顺手清协调器，而协调器里那条正是这张新邀请。
    private func makeRoomForInvite(_ order: WSNewOrder) -> Bool {
        guard let index = invites.firstIndex(where: { $0.id == order.orderId }) else { return true }
        guard AppRealtimeCoordinator.isDifferentInvite(invites[index].order, order),
              invites[index].outcome != .accepted else { return false }
        invites.remove(at: index)
        return true
    }
}
