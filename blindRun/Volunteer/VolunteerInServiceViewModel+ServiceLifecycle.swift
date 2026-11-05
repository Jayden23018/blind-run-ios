import SwiftUI

extension VolunteerInServiceViewModel {
    func startService() async {
        guard let order, let appState else { return }
        guard order.status.canStartService else {
            let message = order.status.startServiceBlockedMessage
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .inProgress, orderID: orderID, appState: appState) {
            try await orders.startService(orderId: orderID)
        }
    }

    func cancel() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .rematching, orderID: orderID, appState: appState) { [weak self] in
            // 同 `VolunteerOrderDetailViewModel.cancel`：真发请求时才标「我自己取消的」。
            await self?.beginCancellation()
            let response = try await orders.cancel(orderId: orderID)
            await self?.recordCancelResponse(response)
        }
        if case .failed = transitionState {
            cancelAnnouncement = VolunteerCancelAnnouncement()
        }
    }

    func beginCancellation() {
        cancelAnnouncement.begin()
    }

    /// 同 `VolunteerOrderDetailViewModel.recordCancelResponse`。
    func recordCancelResponse(_ response: CancelOrderResponse) {
        if let followUp = cancelAnnouncement.recordResponse(response) {
            speechService?.speak(followUp, priority: .onDemand)
        }
    }

    /// 走 `speakStatusChange(_:text:)`：与首页那条状态订阅共用同一个去重键（两边都订阅了这条推送），
    /// 也带上这一态的震动。首页先念了的话，这里只补「已记一次临时取消」。
    func announceCancellation(entering status: RunOrderStatus) {
        let speech = speechService
        if let followUp = cancelAnnouncement.announceCancellation(speak: { sentence in
            speech?.speakStatusChange(status, text: sentence) ?? false
        }) {
            speech?.speak(followUp, priority: .onDemand)
        }
    }

    /// 结束服务。**没有参数** —— 2026-09-16 之前这里收一个 `summary: String`，
    /// 由一张「服务总结」表单填，而 `POST /api/orders/{id}/finish` 根本没有请求体
    /// （`api_spec.yaml:2110-2129`），那段文字从来没离开过这台手机。
    /// 那张表单随长按结束一起删了，见 `VolunteerFinishLongPress`。
    func complete() async {
        guard let order, let appState else { return }
        guard order.status.canFinishService else {
            let message = order.status.finishBlockedMessage
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .completed, orderID: orderID, appState: appState) {
            try await orders.finish(orderId: orderID)
        }
    }

    func retryTransitionConfirmation() {
        guard let order, let appState, let target = transitionState.targetStatus else { return }
        transitionState = .awaitingConfirmation(target: target)
        errorMessage = nil
        startTransitionConfirmation(
            orderID: order.orderId,
            target: target,
            appState: appState
        )
    }

    // MARK: - 紧急求助（志愿者侧）

    /// 代被陪同的盲人发起求助。与盲人侧同一条路径、同一个 GPS 严格门槛（拿不到真实定位就不发），
    /// 区别只在后端把事件挂在订单的盲人身上、并用 `VOLUNTEER_BUTTON` 标注来源。
    func enterEmergency(
        locate: @escaping @MainActor () async -> LocatedCoordinate?,
        locationFailureReason: @escaping () -> LocationError? = { nil }
    ) async {
        guard let order, let appState else { return }
        let outcome = await appState.emergencyCoordinator.trigger(
            order: order,
            role: appState.activeRole,
            userID: appState.userId,
            safety: appState.safety,
            locate: locate,
            locationFailureReason: locationFailureReason
        )
        if outcome.isFailure {
            speechService?.speakError(outcome.message)
        } else {
            speechService?.speak(outcome.message)
        }
        // 确定一个字节都没发：弹本地拨号兜底（#407 第 1 项）。先等确认框 / 求助面板收起 —— 立刻失败（没同意共享位置、
        // 登录过期）时同一拍里又弹一个对话框，iOS 16 会丢掉其中一个，只剩播报。
        guard outcome.state.isDefinitelyUnsent else { return }
        try? await Task.sleep(nanoseconds: VolunteerInServiceView.sheetDismissalDelayNanoseconds)
        offersLocalCallAfterUnsentSOS = true
    }

    /// 对被陪同者的求助回一句「确认需要帮助」。这是志愿者唯一能做的响应。
    func acknowledgeEmergency(eventID: Int64) async {
        guard let appState, !isAcknowledgingEmergency else { return }
        isAcknowledgingEmergency = true
        let succeeded = await appState.emergencyCoordinator.acknowledgeAsVolunteer(
            eventID: eventID,
            safety: appState.safety
        )
        isAcknowledgingEmergency = false
        if succeeded {
            speechService?.speak(EmergencySafetyCopy.volunteerAcknowledged)
        } else {
            let message = "确认失败，请重试。若情况危急请立即拨打120或110。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }
}
