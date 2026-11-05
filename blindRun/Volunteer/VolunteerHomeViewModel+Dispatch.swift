import CoreLocation
import SwiftUI

extension VolunteerHomeViewModel {
    // MARK: - WebSocket Dispatch

    /// 响应派单。
    ///
    /// 🚨 **发 `.accept` 还是 `.interested` 由推送里的 `requiresIntroCall` 决定，不由这里推算。**
    /// 后端 `app.intro-call.enabled` 默认 true，陌生人直接发 `ACCEPT` 会 409
    /// `INTRO_CALL_REQUIRED`（`DispatchService.handleAccept` 的守卫）。后端只在两种情况放行
    /// `ACCEPT`：这一对已经磨合成功过（`IntroCallPair.outcome == MATCHED`），或者距开跑时间
    /// 已经塞不下一轮通话窗口。两个判据客户端都拿不到 —— 前者在后端库里，后者的窗口长度是
    /// 后端配置（`app.intro-call.window-minutes`）。
    ///
    /// 所以判断只有一份，在后端（`DispatchService.introCallWindowFits`），结论随派单推送下发：
    /// `WSNewOrder.requiresIntroCall` → `WSNewOrder.dispatchRespondAction`。
    /// 调用方按那个属性传 `action` 进来，这里不再二次判断。
    ///
    /// **两个方向的 409 都要兜，因为推送是一个快照**：它发出之后，这一对的磨合记录
    /// 或 `app.intro-call.enabled` 都可能变，于是快照给的答案两边都可能过时。
    /// 志愿者已经点过这个动作了，30 秒倒计时里不该让他为后端改主意再点一遍。
    ///
    /// - `.accept` → 409 `INTRO_CALL_REQUIRED`：就地改发 `.interested` 重试一次
    ///   （下面那个内层 `do/catch`）。`.interested` 没有额外前置闸，就地重发是安全的。
    /// - `.interested` → 409 `INTRO_CALL_NOT_REQUIRED`：**递归重走本函数**而不是就地补一个
    ///   API 调用 —— `.accept` 有 `.interested` 没有的前置闸（定位权限判定 +
    ///   `VolunteerLocationReporter.reportIfNeeded`），就地补调用等于绕过它们。
    ///
    /// 两条各自只走一次，所以不会来回打：前者靠内层 `do` 的结构（重试不再被 catch 接住），
    /// 后者靠 `allowsIntroCallUpgrade` —— 递归时传 `false`。**调用方不要传这个参数。**
    ///
    /// ⚠️ 顺带一条历史：`requiresIntroCall` 曾经只挂在 `AvailableOrderResponse` 上，
    /// 而本 App 不调 `GET /api/orders/available`，所以那段时间客户端对陌生人一律发
    /// `.interested`，`AGENTS.md` §5 也据此写着「字段搬到推送上之前不要加 `.accept` 分支」。
    /// 后端已于 2026-08-22（迁移 `0031`）把它搬到 `NEW_ORDER` 上并标为**必填**
    /// （`websocket-protocol.md`「客户端按它决定 `/respond` 发哪个 `action`」），前提已解除。
    func respondToDispatch(
        action: OrderRespondAction,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        orderId: Int64? = nil,
        allowsIntroCallUpgrade: Bool = true
    ) {
        // 队列里可能同时有几条邀请（后端并发派单），所以**必须钉死是哪一条** ——
        // 不传就是「当前翻到的那张」，递归兜底那一支会把它原样传回来。
        let targetID = orderId ?? currentInvite?.id
        guard let order = invites.first(where: { $0.id == targetID })?.order else { return }
        guard let appState else { return }
        let accept = action == .accept
        if accept || action == .interested {
            // 定位权限只对 `.accept` 卡：`INTERESTED` 不上报位置，也还不是接单。
            // 为一件不需要定位的事拦住用户，代价落回正在等的盲人身上。
            // 资质（`verified`）两条路径都要过 —— 后端 `markInterested` 也跑同一套校验。
            let message = accept
                ? VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    registrationStatus: appState.volunteerRegistrationStatus,
                    locationAuthorized: locationAuthorized
                )
                : VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    registrationStatus: appState.volunteerRegistrationStatus
                )
            if let message {
                errorMessage = message
                speechService?.speakError(message)
                return
            }
        }
        isRespondingToDispatch = true
        Task {
            do {
                var effectiveAction = action
                do {
                    try await submitDispatchResponse(
                        action: action,
                        order: order,
                        appState: appState,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized
                    )
                } catch let error as APIError
                    where action == .accept && error.errorCode == .introCallRequired {
                    // 推送说「这一单可以直接接」，后端却说不行 —— 推送发出后这一对的磨合记录
                    // 或 `app.intro-call.enabled` 变了。这是同一个意图的两种发法，
                    // 不是一个需要用户重新决策的场景，所以自己改口，**只重试一次**。
                    // 重试仍失败就落到下面的正常错误分支。
                    effectiveAction = .interested
                    try await submitDispatchResponse(
                        action: .interested,
                        order: order,
                        appState: appState,
                        currentLocation: currentLocation,
                        locationAuthorized: locationAuthorized
                    )
                }
                // 请求已经在上面的 `submitDispatchResponse` 里发过了（`.accept` 撞上
                // `INTRO_CALL_REQUIRED` 时会自己改口重发一次），这里只是记结果。
                // 判据用 `effectiveAction` 而不是入参 `action`：改过口之后这一单没接成。
                let acceptedOrderId = effectiveAction == .accept ? order.orderId : nil
                appState.realtimeCoordinator.clearDispatch(orderID: order.orderId, inviteID: order.inviteId)

                // 🔴 **结果先落在卡上，再去刷新 —— 顺序不能反。**
                // `refreshAfterDispatchResponse` 里会走一遍 `apply(summary:)`，而那里面有
                // 冷启动三岔路 `resolveLaunchRouteIfNeeded()`。先刷新的话，那一刻这条邀请
                // 还是「待回复」状态，三岔路的 guard 放行 ⇒ 它直接把人推进订单页，
                // 「已约好」那张卡一闪而过。由
                // `testAcceptingDispatchShowsTheBookedCardAndOnlyNavigatesOnTap` 红出来
                // （第一版修在 guard 上，没用 —— 问题不在判据，在这两步的先后）。
                //
                // 穷举 switch：`OrderRespondAction` 将来加值时编译器会逼一次决策。
                // 此前这里是 `if .interested { … } else { … }`，而那个 `else` 把 `.decline`
                // 也当成了「已接下」。
                switch effectiveAction {
                case .interested:
                    // 通话磨合那一支**照旧直接跳走**，不停在结果卡上。
                    // 设计稿 §4.4.3 的成功态只有「已约好」一种，而 `INTERESTED` 不是接单：
                    // 那边 20 分钟的通话窗口已经在走，多一次「查看订单」的点击是在烧他的窗口。
                    removeInvite(orderID: order.orderId)
                    pendingIntroCallOrder = VolunteerIntroCallRoute(dispatchOrder: order)
                    declineStreak.reset()  // 后端「有意向」同样清零连续拒绝（#338）
                case .accept:
                    // 🚩 **接下之后不再自动 push 订单页。** §4.4.3：卡片**原地**变成「已约好」，
                    // 由用户点「查看订单」才走。自动跳等于把那张确认卡一闪而过 ——
                    // 而它是这一刻唯一一处告诉他「全名和电话已经放进订单」的地方。
                    markInvite(orderID: order.orderId, outcome: .accepted)
                    declineStreak.reset()
                    // 交付包 03 触感总表：接下邀请成功 `.success`。下一行那句播报就是它的语义。
                    HapticFeedback.play(.success)
                case .decline:
                    removeInvite(orderID: order.orderId)
                }
                speechService?.speak(Self.dispatchResponseSpeech(for: effectiveAction))

                let acceptedOrder = await refreshAfterDispatchResponse(
                    acceptedOrderId: acceptedOrderId,
                    appState: appState
                )
                isRespondingToDispatch = false
                acceptedDispatchInitialOrder = acceptedOrder
            } catch let error as APIError {
                handleDispatchResponseError(
                    error, action: action, order: order, appState: appState,
                    currentLocation: currentLocation, locationAuthorized: locationAuthorized,
                    allowsIntroCallUpgrade: allowsIntroCallUpgrade
                )
            } catch {
                isRespondingToDispatch = false
                errorMessage = "响应失败，请重试"
                speechService?.speakError("响应失败，请重试")
            }
        }
    }

    /// 只做「发出去」这一件事，成功后的刷新 / 收弹窗 / 播报都留在调用方 ——
    /// 409 兜底会把它调两次，而那些后处理只该跑一次。
    private func submitDispatchResponse(
        action: OrderRespondAction,
        order: WSNewOrder,
        appState: AppState,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) async throws {
        if action == .accept {
            VolunteerLocationReporter.reportIfNeeded(
                appState: appState,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized
            )
        }
        try await appState.orders.respond(orderId: order.orderId, action: action)
    }

    /// 三种动作各自的播报。`.interested` 刻意不说「已接单」——它不是接单，说错了志愿者
    /// 会以为事情已经定了，然后错过那通电话。
    static func dispatchResponseSpeech(for action: OrderRespondAction) -> String {
        switch action {
        case .accept:
            return "已接受订单"
        case .decline:
            return "已拒绝订单"
        case .interested:
            return "已告诉跑者你有意向，请留意他的来电"
        }
    }

    /// 清空整队邀请。**这不是「下滑收起」** —— 收起走 `isInviteSheetPresented = false`，
    /// 邀请留在队列里、倒计时继续走，接单主页上还有回来的入口（§4.4.2「不算回复」）。
    /// 这个函数只在登出 / 换角色 / 测试收尾这类「整个上下文没了」的时候用。
    func dismissDispatch() {
        countdownTask?.cancel()
        countdownTask = nil
        // 走 `removeInvite` 而不是 `invites.removeAll()`：协调器那一份也要清，
        // 不然下一条推送会把这些邀请整队灌回来。
        for id in invites.map(\.id) { removeInvite(orderID: id) }
        currentInviteID = nil
        bannerInvite = nil
        isRespondingToDispatch = false
    }

    /// 通话磨合结束（成单 / 换人 / 超时）后把入口收掉。
    ///
    /// ⚠️ **不清 `autoOpenedIntroCallOrderId`。** 用户手动返回也走这里，
    /// 清了的话下一次 `dispatch-summary` 刷新会把他重新推回通话页 —— 见那个字段的注释。
    /// 那个记号跟着 orderId 走，换一单自然失效。
    func clearIntroCall() {
        pendingIntroCallOrder = nil
    }

    private func refreshAfterDispatchResponse(
        acceptedOrderId: Int64?,
        appState: AppState
    ) async -> OrderDetailResponse? {
        var acceptedOrder: OrderDetailResponse?

        // 两处 `try?` 是**迁移前就有的**，这里原样保留：这一步跑在「已经响应成功」之后，
        // 播报与导航都不依赖它，拿不到只是首页少刷一次，5 秒后的下一轮会补上。
        if let acceptedOrderId {
            acceptedOrder = try? await appState.orders.orderDetail(orderId: acceptedOrderId)
            activeOrder = acceptedOrder
        }

        if let summary = try? await appState.orders.dispatchSummary() {
            apply(summary: summary)
        }

        if let acceptedOrder {
            activeOrder = acceptedOrder
        }

        return acceptedOrder
    }

    /// `respondToDispatch` 的 `APIError` 分支。分出来是因为那个函数只许变短（SwiftLint 棘轮 #488）。
    private func handleDispatchResponseError(
        _ error: APIError,
        action: OrderRespondAction,
        order: WSNewOrder,
        appState: AppState,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        allowsIntroCallUpgrade: Bool
    ) {
        isRespondingToDispatch = false
        if appState.handleAuthenticatedAPIError(error) {
            return
        }
        // 熟人误发 `INTERESTED`：后端 409 `INTRO_CALL_NOT_REQUIRED`（2026-08-26 新增）。
        //
        // 🚩 **必须重新走一遍本函数，不能就地补一个 API 调用**：`.accept` 有 `.interested`
        // 没有的前置闸（定位权限判定 + `VolunteerLocationReporter.reportIfNeeded`），
        // 就地补调用等于绕过它们，志愿者会在没给定位权限的情况下把单接下来。
        // 闸拦住时用户看到的是「需要定位权限」这类可执行的提示，也是对的。
        //
        // 不弹「操作失败」就停：派单弹窗只有「有意向」和「拒绝」两个按钮，
        // 停在这里等于让志愿者卡在一个本该能接的单上（后端在那条 handoff 里点名要求别这样）。
        if allowsIntroCallUpgrade,
           action == .interested,
           error.errorCode == .introCallNotRequired {
            respondToDispatch(
                action: .accept,
                currentLocation: currentLocation,
                locationAuthorized: locationAuthorized,
                // 队列化之后必须显式带上 orderId：递归这一跳发生在 `await` 之后，
                // 期间用户可能已经翻到了下一张卡，`currentInvite` 会指到另一个人身上。
                orderId: order.orderId,
                allowsIntroCallUpgrade: false
            )
            return
        }
        // 邀请已经不在了（后端 #371）：被同批别人抢先 → 409 `ORDER_ALREADY_ACCEPTED`；
        // 已过期（哪怕过期扫描还没跑到它）→ 409 `ORDER_DISPATCH_MISMATCH`。
        // 卡片原地变「已失效」并说原因，而不是念一句报错、把一个必定失败的按钮留在原处。
        switch error.errorCode {
        case .orderAlreadyAccepted:
            invalidateInvite(
                orderID: order.orderId, inviteID: order.inviteId, outcome: .withdrawn(.taken), userInitiated: true
            )
            return
        case .orderDispatchMismatch:
            invalidateInvite(
                orderID: order.orderId, inviteID: order.inviteId, outcome: .expired, userInitiated: true
            )
            return
        default:
            break
        }
        errorMessage = error.localizedMessage
        speechService?.speakError(error.localizedMessage)
    }
}
