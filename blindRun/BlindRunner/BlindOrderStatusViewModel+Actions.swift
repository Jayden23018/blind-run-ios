import SwiftUI

extension BlindOrderStatusViewModel {
    /// 刷新后端的等待超时窗口，让订单不被自动取消。
    ///
    /// **按状态分派，且只打这一个端点。** 两个端点的前置状态互斥，409
    /// `ORDER_STATUS_NOT_ALLOWED` 的含义是「你手上的状态已经过期了」——
    /// 此时正确的动作是刷新订单，不是换一个 URL 再打一次。盲人听不见网络请求，
    /// 连打两次的唯一可见结果是等待时间翻倍。
    ///
    /// 刻意**不做二次确认**：这个动作幂等、可重复，且方向是保住订单。误触的代价是多等一会儿，
    /// 而多一轮确认对读屏用户的代价是实打实的十几秒。（取消订单那条的二次确认不受影响。）
    func keepWaiting() async {
        guard let order, let appState else { return }
        guard let endpoint = order.status.keepWaitingEndpoint else {
            let message = "当前订单状态不能继续等待。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        isPerformingAction = true
        errorMessage = nil
        do {
            try await appState.orders.keepWaiting(endpoint, orderId: order.orderId)
            isPerformingAction = false
            // 成功不改状态（后端只回 `{"success": true}`），所以反馈只能由本地这句话给出。
            speechService?.speak(KeepWaitingCopy.success)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            switch error.errorCode {
            case .keepWaitingLimitReached:
                keepWaitingLimitReached = true
                errorMessage = KeepWaitingCopy.limitReached
                speechService?.speakError(KeepWaitingCopy.limitReached)
            case .invalidOrderStatus:
                // 本地状态过期。刷订单让页面回到真实状态，**不重试另一个端点**。
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
                await loadOrder(orderId: order.orderId, speakChanges: true)
            default:
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            }
        } catch {
            isPerformingAction = false
            let message = "继续等待没有成功，请再试一次。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }

    /// 汇合态的「开始跑步」：`POST /start-service`，盲人按下 = 同意 + 开始（后端 #346）。
    ///
    /// 成功后**只重拉订单**，不在这里起倒计时：倒计时挂在 `DRIVER_ARRIVED → IN_PROGRESS`
    /// 这次转移上（`updateRunCountdown`），陪跑员先按时走的也是同一条路。两处各起一次
    /// 会在「两人几乎同时按」时数两遍。
    ///
    /// 不单独调 `/confirm-start`：开始本身就记下了盲人的同意（契约写 `blindStartConfirmedAt`）。
    ///
    /// 错误分三种，处理不同：
    /// - `SERVICE_START_TOO_EARLY`：念映射文案，不在客户端算「还差几分钟」——
    ///   后端没下发最早可开始时刻（后端 #307 ②），自己减就是把阈值抄一份。
    /// - `ORDER_STATUS_NOT_ALLOWED`：本地状态过期（例如陪跑员刚取消），刷新而不是重试。
    ///   另一端先开始了**不会**走到这里：契约规定那种情况两端都回 200。
    /// - 其余：念出来，按钮留着可以再按（接口幂等）。
    func startRun() async {
        guard let order, let appState, order.status.canStartService, !isStartingRun else { return }
        isStartingRun = true
        defer { isStartingRun = false }
        errorMessage = nil
        // 按下去先给一句：成功之前可能要等网络，而读屏焦点停在按钮上时，按钮文字变了不会自动重读。
        speechService?.speak(BlindRunCopy.startingAnnouncement)
        do {
            try await appState.orders.startService(orderId: order.orderId)
            // 重拉在 `isStartingRun` 复位之前做：重拉回来之前订单还是 `DRIVER_ARRIVED`，
            // 按钮若先恢复成可点，这一段里还能再发一次。
            await loadOrder(orderId: order.orderId, speakChanges: true)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            let message = error.localizedMessage
            speechService?.speakError(message)
            if error.errorCode == .invalidOrderStatus {
                await loadOrder(orderId: order.orderId, speakChanges: true)
            }
            // 在重拉**之后**设：`loadOrder` 第一步会清空 `errorMessage`（同 `cancelOrder` 的写法）。
            errorMessage = message
        } catch {
            let message = BlindRunCopy.startRunFailed
            speechService?.speakError(message)
            errorMessage = message
        }
    }

    func cancelOrder() async {
        guard let order, let appState else { return }
        // 汇合态另走后端给的时刻（#682）。到点前那一行是置灰的，正常走不到这里；
        // 时钟有偏差时照发，由后端 409 `BLIND_CANCEL_TOO_EARLY` 把时刻念出来。
        let isArrivalCancel = BlindArrivalCancelGate.resolve(order: order, now: Date()) != nil
        guard order.status.canBlindRunnerCancel || isArrivalCancel else {
            let message = "当前订单状态不能由盲人取消。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        isPerformingAction = true
        errorMessage = nil
        do {
            try await appState.orders.cancel(orderId: order.orderId)
            isPerformingAction = false
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
        } catch let error as APIError {
            isPerformingAction = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            let message = Self.cancelFailureMessage(for: error)
            speechService?.speakError(message)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        } catch {
            isPerformingAction = false
            let message = "取消失败。"
            speechService?.speakError(message)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        }
    }

    /// 跑者取消失败时念哪一句。`BLIND_CANCEL_TOO_EARLY` 由 `APIError.localizedMessage` 念后端 message；
    /// `ORDER_HAS_ACTIVE_EMERGENCY` 的通用文案是写给陪跑员「结束服务」的，这一路换成跑者口径。
    nonisolated static func cancelFailureMessage(for error: APIError) -> String {
        if error.errorCode == .orderHasActiveEmergency {
            return BlindArrivalCancelCopy.activeEmergency
        }
        return error.localizedMessage
    }

    /// 保存出发前留言。返回错误文案，`nil` = 已保存。成功与失败都念出来（表单页上看不到订单页）。
    ///
    /// 成功后就地换掉 `order.messageToVolunteer`，不等下一轮轮询 —— 表单页一关，
    /// 留言行要立刻显示刚写的那句，否则跑者会以为没存上再写一遍。
    func saveRunnerMessage(_ text: String) async -> String? {
        guard let order, let appState else { return "订单信息还没加载好，请稍后再试。" }
        let trimmed = text.trimmed
        guard trimmed.utf16.count <= RunnerMessageRequest.maxLength else {
            let message = "留言最多 \(RunnerMessageRequest.maxLength) 个字，现在是 \(trimmed.utf16.count) 个字。"
            speechService?.speakError(message)
            return message
        }
        do {
            let response = try await appState.orders.updateRunnerMessage(trimmed, orderId: order.orderId)
            let saved = response.messageToVolunteer?.nilIfBlank
            self.order?.messageToVolunteer = saved
            speechService?.speak(saved == nil ? "留言已清空" : "留言已发给陪跑员")
            return nil
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return nil }
            speechService?.speakError(error.localizedMessage)
            return error.localizedMessage
        } catch {
            let message = "留言没有发出去，请再试一次。"
            speechService?.speakError(message)
            return message
        }
    }

    /// Sends one SOS for the current `IN_PROGRESS` order.
    ///
    /// Every outcome — including "not sent" — is both shown and spoken. A blind runner decides
    /// whether to look for help another way based on this announcement, so silence on failure
    /// would be the worst possible bug here.
    func enterEmergency() async {
        guard let order, let appState else { return }
        let coordinator = appState.emergencyCoordinator
        let outcome = await coordinator.trigger(
            order: order,
            role: appState.activeRole,
            userID: appState.userId,
            safety: appState.safety,
            locate: { await self.freshEmergencyCoordinate() },
            locationFailureReason: { self.emergencyLocationFailureReason() }
        )
        // The visible surface is `EmergencyStatusNotice`, driven by the coordinator's state.
        // Deliberately not also setting `errorMessage`: that would render the same sentence twice
        // and make VoiceOver read the failure twice over.
        if outcome.isFailure {
            speechService?.speakError(outcome.message, priority: .emergency)
        } else {
            speechService?.speak(outcome.message, priority: .emergency)
        }
    }

    /// 进发出前的 3 秒反悔窗口（屏 3）。
    ///
    /// **两条路径都落到这里**：长按 3 秒 / 自定义无障碍动作直接进来，轻点则先过
    /// `AGENTS.md` §6 那句逐字锁定的二次确认再进来。合成一条不是为了省代码 ——
    /// 发出求助只有一个出口，「两条路的行为哪里不一样」这个问题就不存在，
    /// 而屏 3b 也只需要从一个地方到达。
    ///
    /// 播报交给 `announce` 回调而不是在 coordinator 里播：coordinator 不该知道
    /// 有没有 TTS 这回事（它在志愿者端也跑）。
    func beginEmergencyCountdown() {
        guard let order, let appState else { return }
        appState.emergencyCoordinator.beginCountdown(
            order: order,
            role: appState.activeRole,
            userID: appState.userId,
            safety: appState.safety,
            locate: { await self.freshEmergencyCoordinate() },
            locationFailureReason: { self.emergencyLocationFailureReason() },
            announce: { [weak self] message in
                // 倒计时每一秒都要盖掉上一秒那句 —— 合成器全进程只有一个、
                // `speak` 自带 `stopSpeaking`，所以「谁后说谁赢」正是这里想要的行为
                // （记忆 `later-speak-silently-cuts-the-earlier-one`）。
                // 🔴 播报队列**刻意保留了同档打断**，这条链路就是它必须保留的理由之一：
                // 同档改成排队的话，三秒倒计时会念成「3」「3」「2」这样的一串旧数字。
                self?.speechService?.speak(message, priority: .emergency)
            }
        )
    }

    /// Withdraws one's own false alarm. The only user-side exit that exists: the escorting volunteer
    /// is refused this action server-side on purpose.
    func cancelEmergency() async {
        guard let appState else { return }
        let outcome = await appState.emergencyCoordinator.cancelByOwner(safety: appState.safety)
        if outcome.isFailure {
            speechService?.speakError(outcome.message, priority: .emergency)
        } else {
            speechService?.speak(outcome.message, priority: .emergency)
        }
    }

    /// 新鲜真实坐标，实现在 `EmergencyCoordinator.freshEmergencyCoordinate(using:)`。
    ///
    /// 2026-08-07 从这里提走：首页 SOS 条是第二个求助入口，而这段逻辑的每一条都是安全约束
    /// （只接受真实设备采样、演示坐标进不来、拿不到就返回 nil 让上层如实播报「未发出」）。
    /// 两份实现意味着这条保证要守两遍，迟早漂移。
    ///
    /// `IN_PROGRESS` 期间实时陪跑会话每 5 秒采样一次，所以那次有界重试只在刚起跑
    /// 或位置更新短暂暂停时才用得上。
    private func freshEmergencyCoordinate() async -> LocatedCoordinate? {
        await EmergencyCoordinator.freshEmergencyCoordinate(
            using: locationService,
            sharingBlocked: isEmergencyLocationSharingBlocked
        )
    }

    private func emergencyLocationFailureReason() -> LocationError? {
        EmergencyCoordinator.locationFailureReason(
            using: locationService,
            sharingBlocked: isEmergencyLocationSharingBlocked
        )
    }

    /// 本角色没同意共享位置（#368，判据见 `AppState.isEmergencyLocationSharingBlocked`）。
    /// `appState` 是 weak，拿不到时按「被拦」算 —— 不发比带着一个用户说过不的位置发出去安全。
    private var isEmergencyLocationSharingBlocked: Bool {
        appState?.isEmergencyLocationSharingBlocked ?? true
    }
}
