import Combine
import SwiftUI

extension VolunteerHomeViewModel {
    // MARK: 这次去不了（5 秒撤销窗口）

    /// §4.4.3：卡片立刻收起、底部 toast 给 5 秒撤销，**到点才真的发 `DECLINE`**。
    ///
    /// 🔴 **只能这么做。** 后端 `POST /{id}/respond` 只有三个 action，`handleDecline` 一进去就
    /// `dispatchToNext`（`DispatchService.java:602-623`），**没有任何撤销入口**。
    /// 先发再撤是撤不回来的，所以「撤销」只能实现成「还没发」。
    ///
    /// 代价写在这里：这一单的拒绝晚 5 秒到后端，正在等的跑者多等 5 秒；用户在 5 秒内杀掉 App
    /// 则这条 `DECLINE` 不会发出 —— 但后端 30 秒超时会兜住，结局一样。
    func declineInvite(orderID: Int64) {
        guard let invite = invites.first(where: { $0.id == orderID }) else { return }
        // 上一条还在窗口里就先把它落地，不然两条会互相顶掉。
        flushPendingDecline()
        removeInvite(orderID: orderID)
        pendingDecline = invite
        pendingDeclineInvalidation = nil
        // 卡片收起那一刻屏幕上只剩一条 toast，而看不见屏幕的人需要知道两件事：
        // 回复出去了、还能反悔。秒数取配置值，不写字面量 —— 两处各写一个 5 必然分叉。
        speechService?.speak("\(VolunteerInviteCopy.declineToastText)，\(Int(declineUndoWindow))秒内可以撤销")
        pendingDeclineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, self?.declineUndoWindow ?? 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flushPendingDecline()
        }
    }

    /// toast 上的「撤销」：请求还没发，把这条邀请放回队列。
    func undoPendingDecline() {
        pendingDeclineTask?.cancel()
        pendingDeclineTask = nil
        guard let invite = pendingDecline else { return }
        pendingDecline = nil
        // 撤销窗口里倒计时**没有停**，所以放回去的可能已经是一张过期卡。
        // 那就让它以「已失效」出现 —— 假装它还能接才是骗人。
        let remaining = max(0, Int(ceil(invite.expiresAt.timeIntervalSinceNow)))
        var restored = invite
        restored.remainingSeconds = remaining
        // 窗口里被撤回 / 判失效的，以那个结果恢复（审查 A5）—— 复活一个「接下」按钮就是让他去撞 409。
        restored.outcome = pendingDeclineInvalidation ?? (remaining == 0 ? .expired : nil)
        pendingDeclineInvalidation = nil
        // 同一张单不许出现两张卡（`id` 重复会让 `ForEach` 与按 id 查找都出错）。
        invites.removeAll { $0.id == restored.id }
        invites.append(restored)
        invites.sort { $0.expiresAt < $1.expiresAt }
        currentInviteID = restored.id
        isInviteSheetPresented = true
        startInviteTicker()
        // 撤销窗口里倒计时没停，所以「放回来了」和「放回来但已经失效了」是两句不同的话。
        // 只说「已撤销」而屏幕上是一张灰卡，对看不见屏幕的人就是一次白跑。
        if case .withdrawn = restored.outcome {
            speechService?.speak(
                "已撤销，不过\(VolunteerInviteCopy.expiredTitle)，\(VolunteerInviteCopy.invalidatedDetail(restored.outcome!))"
            )
        } else {
            speechService?.speak(
                restored.outcome == .expired
                    ? "已撤销，不过这个邀请已经过期了"
                    : "已撤销，邀请回来了"
            )
        }
    }

    /// 窗口到点（或被下一次「去不了」挤掉）：真的把 `DECLINE` 发出去。
    private func flushPendingDecline() {
        pendingDeclineTask?.cancel()
        pendingDeclineTask = nil
        guard let invite = pendingDecline else { return }
        pendingDecline = nil
        let invalidation = pendingDeclineInvalidation
        pendingDeclineInvalidation = nil
        // 窗口里已经被撤回：后端那张邀请已经不在了，再发 `DECLINE` 只会 409；撤回也不计入连续拒绝（后端口径）。
        if case .withdrawn = invalidation { return }
        declineStreak.recordDecline()
        objectWillChange.send()
        guard let appState else { return }
        appState.realtimeCoordinator.clearDispatch(
            orderID: invite.id, inviteID: invite.order.inviteId, retiredUntil: invite.expiresAt
        )
        Task {
            // 失败**不弹给用户**：他已经表达完意图、卡片早就收起了，而后端超时会兜住同一个结果。
            // 这一刻弹「操作失败」只会让他以为自己还得再点一次。
            try? await appState.orders.respond(orderId: invite.id, action: .decline)
        }
    }
}
