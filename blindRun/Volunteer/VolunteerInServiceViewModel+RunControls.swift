import SwiftUI

extension VolunteerInServiceViewModel {
    // MARK: - 跑步中：暂停 / 继续 / 联系客服 / 定位精度（V5、V8、V15）

    func pauseRun() async { await setRunPaused(true) }
    func resumeRun() async { await setRunPaused(false) }

    private func setRunPaused(_ paused: Bool) async {
        // 面板是在 `IN_PROGRESS` 打开的，但按下去的那一刻订单可能已经结束（security review A1）。
        guard let order, let appState, !isTogglingPause, order.status == .inProgress else { return }
        isTogglingPause = true
        errorMessage = nil
        defer { isTogglingPause = false }
        do {
            if paused {
                try await appState.orders.pauseRun(orderId: order.orderId)
            } else {
                try await appState.orders.resumeRun(orderId: order.orderId)
            }
            // 先就地改，再以详情为准：不改的话要等下一次 GET 回来按钮才换，那几百毫秒里会被按第二次。
            var run = self.order?.run ?? RunView()
            run.paused = paused
            self.order?.run = run
            HapticFeedback.play(.medium)
            speechService?.speak(paused ? VolunteerRunCopy.pausedSpoken : VolunteerRunCopy.resumedSpoken)
            await load(orderId: order.orderId, speakChanges: false)
        } catch let error as APIError {
            if error.endsSession { return }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            let message = paused ? "暂停没有成功，请重试。" : "继续没有成功，请重试。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }

    /// 「联系客服」：一键提交带订单号的工单（V5）。成功后不可重复提交（同一单的同一件事）。
    func requestSupportCallback() async {
        guard let order, let appState, supportRequestState != .submitting, supportRequestState != .submitted,
              let request = SupportTicketRequest(
                category: .orderService,
                content: VolunteerRunCopy.supportTicketContent,
                orderId: order.orderId
              ) else { return }
        supportRequestState = .submitting
        do {
            try await appState.safety.submitSupportTicket(request)
            supportRequestState = .submitted
            speechService?.speak(VolunteerRunCopy.supportSubmitted)
        } catch let error as APIError where error.endsSession {
            supportRequestState = .idle
        } catch {
            supportRequestState = .failed
            speechService?.speakError(VolunteerRunCopy.supportFailed)
        }
    }

    /// 本机定位精度的输入。页面在每次定位更新时调。
    func observeOwnLocationAccuracy(_ accuracy: Double?, now: Date = Date()) {
        let next = VolunteerRunTip.weakSince(previous: weakLocationSince, accuracy: accuracy, now: now)
        if next != weakLocationSince { weakLocationSince = next }
    }

    func enRoute() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverEnRoute, orderID: orderID, appState: appState) {
            try await orders.enRoute(orderId: orderID)
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverArrived, orderID: orderID, appState: appState) {
            try await orders.arrived(orderId: orderID)
        }
    }

    /// 跨天预约单的临期确认：`SCHEDULED_CONFIRMED → PENDING_ACCEPT`。
    ///
    /// 走与其余流转动作**同一条** `submitTransition`，而不是自己写一遍 —— 那条路径自带
    /// 提交去重、「已提交待确认」态、超时后的「重新确认状态」。这个动作恰恰最需要它们：
    /// 提交成功但确认没回来时，志愿者会以为没点上而重复点，而重复点在 409 之后
    /// 看起来和「真的没确认成功」一模一样。
    ///
    /// 🚩 目标是 `.pendingAccept` 而不是 `.scheduledConfirmed`：确认之后订单就进即时链路了。
    /// 它与 `/en-route` **不是一回事**（那条会打开位置互推），别把两个动作合并。
    func confirmDeparture() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(
            target: .pendingAccept,
            orderID: orderID,
            appState: appState,
            // 不断言成因（转走了 / 盲人取消了 / 上一次其实已经成功），客户端分不出这三种。
            // 这句话对三种都为真，而且这条路径紧接着会 `load()` 刷新，屏幕自己会给出真相。
            statusConflictMessage: "此订单的状态已经变了，不用再确认。"
        ) {
            try await orders.confirmDeparture(orderId: orderID)
        }
    }
}
