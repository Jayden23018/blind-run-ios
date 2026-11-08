import SwiftUI

extension VolunteerInServiceViewModel {
    /// 实时状态推送（track 的 `.status`）。手上没有这一单（还没拉回来、或已放下）就丢弃，与原订阅相同。
    /// - Returns: 这一页有没有念这条状态句（或用自己的整句覆盖了它），交给 `acknowledge`（design §6）。
    func applyRealtimeStatus(_ update: RealtimeOrderStatusUpdate) -> Bool {
        guard let current = order, current.orderId == update.orderId else { return false }
        let spoke = apply(current.replacingStatus(with: update.toStatus), speakChanges: true)
        isLoading = false
        return spoke
    }

    /// - Returns: 这一次有没有念状态句：通用句、自己取消那句、跑者取消那句任一句都算。
    @discardableResult
    func apply(_ updated: OrderDetailResponse, speakChanges: Bool) -> Bool {
        let previousStatus = order?.status
        var spoke = false
        order = updated
        // 状态一变就清掉两样只属于上一状态的东西：
        // - 响铃 / 快捷消息的回执：跑步页也渲染它，免得汇合期那句「对方可能没收到」挂到跑步中。
        //   它从不随状态切换一起写，清了不会吞掉新报的话。
        // - 错误（#347：跑者按了开始、订单进了跑步中，页面还挂着「还需要跑者按开始跑步」）。
        //   **反过来要求**：先报错再刷新的分支必须改成先刷新再报，否则刷新带来的状态变化会把刚报的那句清掉
        //   （见 `submitTransition` / `endWaiting`）。
        if let previousStatus, previousStatus != updated.status {
            nudgeNotice = nil
            errorMessage = nil
        }
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: updated.orderId, status: updated.status)
        // 同 `configure`：换单时上面那行会清掉 `didSet` 先写的姓氏。
        appState?.liveEscortCoordinator.updateLiveActivityPartnerName(updated.blindSurname?.nilIfBlank)
        // 要念取消那一句时不念通用状态句：两句都念的话，后一句同档打断前一句，
        // 陪跑员听到的是半句盲人端文案加一句取消说明。
        let announcesCancellation = cancelAnnouncement.announcesCancellation(entering: updated.status)
        // 跑者取消：下面终态分支会念「{名}取消了这次陪跑。不算你的取消…」整句。这里再念通用句，
        // 两句同档，后一句切断前一句，陪跑员听到半句加一整句（#333）。
        let cancelledByRunner = updated.status == .cancelled && !isEndingWait && !didEndWaiting
        // 系统转走的 `REMATCHING` 也走这里，低一档念，不切断闸门到点横幅（#477）。
        if speakChanges, previousStatus != updated.status, !announcesCancellation, !cancelledByRunner {
            speechService?.speakVolunteerStatusChange(updated.status)
            spoke = true
        }
        if let target = transitionState.targetStatus,
           updated.status.satisfiesVolunteerTransition(target: target) {
            transitionState = .idle
            ClientFlowDiagnostics.record(event: "confirmed", operation: "volunteer-service-transition")
            confirmationTask?.cancel()
            confirmationTask = nil
            errorMessage = nil
        }
        if announcesCancellation || updated.status == .rematching {
            releaseOrder(updated.orderId)
            didCancelOrder = true
            // 不是自己按的取消（跨天闸门到点、失联事件没送到只来了状态推送……）：没有取消面板的回调来关页，
            // 此前页面就停在「正在获取订单状态...」转圈（#456）。
            if !cancelAnnouncement.requested { didLoseOrder = true }
            order = nil
            if announcesCancellation, previousStatus != updated.status {
                announceCancellation(entering: updated.status)
                spoke = true
            }
            return spoke
        }
        if updated.status.isTerminal {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            stopPolling()
            if updated.status == .completed, let appState {
                refreshDispatchSummary(using: appState)
            }
            if cancelledByRunner,
               let sentence = VolunteerOrderFlowCopy.runnerCancelledAnnouncement(
                   from: previousStatus, to: updated.status, name: updated.blindNameForSpeech
               ) {
                // 🔴 **`order` 留着，不再置 nil。** 此前这里一置 nil，两个渲染分支就都取不到
                // 订单 ⇒ 屏幕退化成一片空白背景，只播一句 TTS，志愿者得自己按返回才能离开。
                // 现在它落在骨架的「跑者已取消」那一屏（`cancelledByRunner`）。
                //
                // `didCancelOrder` 也**不在这里置位**：它的含义是「这一单是我自己退掉的，
                // 关页面吧」（`REMATCHING` 那条分支），而这一次是盲人取消的，
                // 要留在页面上把「不算你的取消」说清楚。
                speechService?.speak(sentence)
                spoke = true
                // 首页念不念由订单页的回话决定（`OrderLiveTrack.acknowledge`，unify-order-live-tracking design §6），
                // 这一句回的是 `spoke: true`。去重键留作纵深防御：回话超时首页照念时，通用的「这一单已取消。」
                // 仍被挡掉，不把这一整句切成半句（#462）。
                speechService?.markStatusAnnounced(.cancelled)
            }
        }
        return spoke
    }

    /// 过期由 track 判（`.peerLocationExpired`，design §3）；离页、换单时页面也直接清。
    func clearPeerLocation() {
        latestBlindSample = nil
        latestBlindAccuracyMeters = nil
    }

    private func refreshDispatchSummary(using appState: AppState) {
        guard dispatchSummaryTask == nil else { return }
        let orders = appState.orders
        dispatchSummaryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.dispatchSummaryTask = nil }
            do {
                let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                    timeout: self.orderLoadTimeout,
                    operationName: "volunteer-service-summary-refresh"
                ) {
                    try await orders.dispatchSummary()
                }
                guard !Task.isCancelled else { return }
                self.dispatchSummary = summary
                ClientFlowDiagnostics.record(event: "confirmed", operation: "volunteer-service-summary-refresh")
            } catch is CancellationError {
                return
            } catch {
                ClientFlowDiagnostics.record(event: "failed", operation: "volunteer-service-summary-refresh")
            }
        }
    }
}

// 放下这一单（#456 / #476）。放在扩展里：同文件的扩展照样能读写私有状态，不再撑大类型体。
extension VolunteerInServiceViewModel {
    /// 请求在路上时这一单被转走了（#456）：结果不再播报、也不再起确认拉取。
    /// 这时横幅正在念后端那句，任何一句「操作失败 / 结果尚未确认」都会把它切断，而那一单已经不是他的了。
    func discardsResultOfLostOrder() -> Bool {
        guard didLoseOrder else { return false }
        transitionState = .idle
        return true
    }

    /// 系统把这一单转走了（#456）：放下订单、停掉对这一单的一切后台动作，**不念任何话** ——
    /// 横幅正在念后端的 `ttsText`，同档再念一句就会把它从半句切断。宿主看 `didLoseOrder` 关页。
    func leaveLostOrder(orderID: Int64) {
        releaseOrder(orderID)
        transitionState = .idle
        errorMessage = nil
        nudgeNotice = nil
        order = nil
        didLoseOrder = true
    }

    /// 这一单不再归这位陪跑员（自己取消 / 被系统转走）：注销活跃订单、停位置互推、停轮询。
    private func releaseOrder(_ orderID: Int64) {
        appState?.realtimeCoordinator.unregisterActiveOrder(orderID)
        appState?.liveEscortCoordinator.clearOwnedOrder()
        stopPolling()
    }
}
