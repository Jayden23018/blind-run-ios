import Combine
import SwiftUI

extension VolunteerHomeViewModel {
    func subscribeToRealtimeCoordinator(_ appState: AppState) {
        guard realtimeDispatchCancellable == nil else { return }
        realtimeDispatchCancellable = appState.realtimeCoordinator.$pendingDispatches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prompts in
                self?.syncInvites(with: prompts)
            }
        subscribeToInviteEvents(appState)
        realtimeRecoveryCancellable = appState.realtimeCoordinator.recoveryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                guard signal.role == .volunteer else { return }
                self?.recoverDispatchReadinessAfterReconnect()
            }
        realtimeStatusCancellable = appState.realtimeCoordinator.statusUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self,
                      let current = self.activeOrder,
                      current.orderId == update.orderId else { return }
                let updated = current.replacingStatus(with: update.toStatus)
                if updated.status.isActiveForVolunteer {
                    self.activeOrder = updated
                    self.appState?.liveEscortCoordinator.updateOwnedOrder(
                        orderID: updated.orderId,
                        status: updated.status
                    )
                } else {
                    self.dropActiveOrder(updated.orderId)
                }
                self.announceStatusChange(update, status: updated.status)
                self.dispatchSummaryErrorMessage = nil
                if let summary = self.dispatchSummary {
                    self.dispatchLoadState = .loaded(summary)
                }
            }
        // 出发后失联、单已转走（`ORDER_VOLUNTEER_LOST`，#456）：「当前订单」静默清掉。
        // 不念：横幅在念后端那句。清掉之后，紧跟着的 `REMATCHING` 推送在上面那条订阅里就认不出这一单，
        // 也就不会再念「订单已取消」把横幅切断。
        realtimeVolunteerLostCancellable = appState.realtimeCoordinator.volunteerLostPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self,
                      let current = self.activeOrder,
                      current.status.isTakenAwayWhenVolunteerLost else { return }
                self.dropActiveOrder(current.orderId)
            }
    }

    /// 陪跑员这一侧的那张表（#333；`REMATCHING` 那句与订单页相同）。念不念等订单页回话
    /// （OpenSpec `unify-order-live-tracking` design §6）：订单页在跟这一单、且这一次念了（或用自己的整句覆盖了，
    /// 如跑者取消的「不算你的取消」、自己取消的「订单已取消」），首页就不念；订单页没开、没念或 1 秒内没回话，首页照念。
    /// 「当前订单」在调用方已经同步更新，不等这个结果。取代原来在主队列上推迟一拍的做法（#462 / #477）。
    private func announceStatusChange(_ update: RealtimeOrderStatusUpdate, status: RunOrderStatus) {
        guard let tracker = appState?.realtimeCoordinator.orderLiveTracker else {
            speechService?.speakVolunteerStatusChange(status)
            return
        }
        Task { [weak self] in
            guard await tracker.pageAnnouncement(for: update, role: .volunteer) == .homeShouldSpeak else { return }
            self?.speechService?.speakVolunteerStatusChange(status)
        }
    }

    /// 撤回推送与待回复快照（后端 #371 / #366）。从 `subscribeToRealtimeCoordinator` 分出来：那个函数只许变短。
    private func subscribeToInviteEvents(_ appState: AppState) {
        inviteWithdrawalCancellable = appState.realtimeCoordinator.inviteWithdrawalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] withdrawal in
                self?.invalidateInvite(
                    orderID: withdrawal.orderId,
                    inviteID: withdrawal.inviteId,
                    outcome: .withdrawn(withdrawal.reason)
                )
            }
        inviteSnapshotCancellable = appState.realtimeCoordinator.pendingInviteSnapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.reconcileInvites(with: snapshot)
            }
        lockScreenAcceptCancellable = appState.realtimeCoordinator.$lockScreenInviteAction
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resolveLockScreenAccept()
            }
    }

    /// 锁屏邀请操作（#338）落地。这张邀请在**当前账号的队列里**还等着回复 ⇒ 翻到它、弹出卡片：
    /// 「接下」走卡片上同一个 `respondToDispatch`（定位取宿主注入的提供者），「这次去不了」走同一个 `declineInvite`（带撤销）。
    /// 按下时记下的账号与当前账号不同 ⇒ 丢掉，不替别人回复。
    /// 邀请期限已过，或按下之后的那次对账里没有它 ⇒ 已失效，告诉他（他按了，就得有回应）。两样都不是就再等。
    ///
    /// 只认身份对得上的那张（`inviteId`，否则期限）：同一单撤回后的新邀请、换账号后旧账号的通知，都不会被它回复。
    func resolveLockScreenAccept(after snapshot: RealtimePendingInviteSnapshot? = nil, now: Date = Date()) {
        guard let coordinator = appState?.realtimeCoordinator, let request = coordinator.lockScreenInviteAction else { return }
        if let owner = coordinator.lockScreenInviteActionUserID, owner != appState?.userId {
            coordinator.consumeLockScreenInviteAction()
            return
        }
        let target = request.invite
        if let invite = invites.first(where: {
            $0.isAwaitingReply && target.matches(orderId: $0.id, inviteId: $0.order.inviteId, expiresAt: $0.expiresAt)
        }) {
            coordinator.consumeLockScreenInviteAction()
            currentInviteID = invite.id
            switch request.action {
            case .accept:
                isInviteSheetPresented = true
                // 第一次接单要先说明手机号去向（#660 V-17）：只把邀请卡打开，让他在卡上再按一次、看到说明。
                guard let appState, VolunteerOnceNotice(.phoneShare, appState: appState).isDone else { return }
                respondToDispatch(
                    action: invite.order.dispatchRespondAction,
                    currentLocation: currentLocationProvider(),
                    locationAuthorized: locationAuthorizedProvider(),
                    orderId: invite.id
                )
            case .decline:
                declineInvite(orderID: invite.id)
            }
            return
        }
        let expired = target.expiresAt.map { $0 <= now } ?? false
        let gone = snapshot.map { snapshot in
            snapshot.requestedAt >= (coordinator.lockScreenInviteActionAt ?? .distantFuture)
                && !snapshot.invites.contains { target.matches(orderId: $0.orderId, inviteId: $0.inviteId, expiresAt: $0.expiresAt?.backendTimestamp) }
        } ?? false
        guard expired || gone else { return }
        coordinator.consumeLockScreenInviteAction()
        speechService?.speak("\(VolunteerInviteCopy.expiredTitle)，\(VolunteerInviteCopy.withdrawnDetail(.noLongerPending))")
    }
}
