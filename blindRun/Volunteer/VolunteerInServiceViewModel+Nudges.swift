import CoreLocation
import SwiftUI

extension VolunteerInServiceViewModel {
    // MARK: - 快捷消息 / 响铃 / 结束等待（交付包 02 ③④）

    /// 「我快到了」「再等我 5 分钟」。按 type 冷却 60 秒，冷却内按钮显示「已发送」。
    func sendQuickMessage(_ code: QuickMessageCode) async {
        guard let order, let appState else { return }
        if let sent = quickMessageSentAt[code], Date().timeIntervalSince(sent) < Self.quickMessageCooldown { return }
        do {
            let response = try await appState.orders.sendQuickMessage(code, orderId: order.orderId)
            quickMessageSentAt[code] = Date()
            reportNudge(delivered: response.delivered, success: "已告诉\(order.blindNameForSpeech)：\(code.title)")
        } catch {
            reportNudgeFailure(error, appState: appState)
        }
    }

    /// 让跑者的手机响起来。`ringingUntil` 之前按钮不可点（宿主按它置灰）。
    func ringRunner() async {
        guard let order, let appState else { return }
        if let ringingUntil, ringingUntil > Date() { return }
        do {
            let response = try await appState.orders.ringRunner(orderId: order.orderId)
            ringingUntil = response.ringingUntil?.backendTimestamp
            reportNudge(delivered: response.delivered, success: "\(order.blindNameForSpeech)的手机正在响")
        } catch {
            reportNudgeFailure(error, appState: appState)
        }
    }

    /// 等满时限后结束等待：订单转 `CANCELLED`（`cancelledBy=SYSTEM`），宿主直接关页。
    ///
    /// 🚩 **不走 `submitTransition`**：那条路径以「订单落到目标状态」为确认，而这里的目标
    /// `CANCELLED` 恰好也是「跑者取消」那一屏的入口 —— 走过去等于让陪跑员看到一句不属于他的话。
    func endWaiting() async {
        guard let order, let appState, !isPerformingAction else { return }
        isPerformingAction = true
        isEndingWait = true
        errorMessage = nil
        defer {
            isPerformingAction = false
            isEndingWait = false
        }
        do {
            try await appState.orders.endWaiting(orderId: order.orderId)
            appState.realtimeCoordinator.unregisterActiveOrder(order.orderId)
            appState.liveEscortCoordinator.clearOwnedOrder()
            // 手上的订单还停在 `DRIVER_ARRIVED`（宿主直接关页，不再刷新），锁屏卡不会自己走到结束分支。
            if #available(iOS 16.2, *) { GuideRunActivityController.shared.end() }
            stopPolling()
            speechService?.speak("已结束等待。订单已取消，不算你的取消。")
            didEndWaiting = true
        } catch let error as APIError {
            if error.endsSession { return }
            // 409 `END_WAIT_TOO_EARLY`：手上的 `earliestEndWaitAt` 过期了，刷一次让主按钮换回去。
            // 先刷新再报（同 `submitTransition` 的冲突分支）。
            if case .serverError(let response) = error, response.errorCode == .endWaitTooEarly {
                await load(orderId: order.orderId, speakChanges: false)
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            errorMessage = "结束等待失败，请重试。"
            speechService?.speakError("结束等待失败，请重试。")
        }
    }

    private func reportNudge(delivered: Bool?, success: String) {
        guard delivered != false else {
            let message = "对方可能没收到，可以打电话。"
            nudgeNotice = message
            speechService?.speakError(message)
            return
        }
        nudgeNotice = nil
        HapticFeedback.play(.tick)
        speechService?.speak(success)
    }

    private func reportNudgeFailure(_ error: Error, appState: AppState) {
        let message: String
        switch error as? APIError {
        case .some(let apiError) where apiError.endsSession:
            return
        case .some(.rateLimited(let info)):
            message = info.retryAfterSeconds.map { "操作过于频繁，\($0) 秒后再试。" } ?? "操作过于频繁，请稍后再试。"
        case .some(let apiError):
            message = apiError.localizedMessage
        case .none:
            message = "没有发出去，请重试。"
        }
        nudgeNotice = message
        speechService?.speakError(message)
    }

    /// 跑者位置。新鲜度（15 秒）、单号与 GCJ-02 边界都由订单跟踪判过（`PeerLocationFreshness`），
    /// 到期由它发 `.peerLocationExpired`，页面不再自己排过期任务。
    func showBlindLocation(_ peer: FreshPeerLocation) {
        latestBlindSample = peer.located
        latestBlindAccuracyMeters = peer.accuracyMeters
    }
}
