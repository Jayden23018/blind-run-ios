import SwiftUI

extension BlindOrderStatusViewModel {
    // MARK: - 订单实时跟踪（OpenSpec `unify-order-live-tracking` 第 2 批，#887）

    /// 第一次 `configure` 时打开一条 track，之后的 `configure`（每次 `onAppear`）复用它。
    /// 状态推送在页面被盖住时照常送达；对方位置只在 `follow` 与 `pause` 之间收（design §1）。
    func openOrderTrackIfNeeded(appState: AppState) {
        guard orderTrack == nil else { return }
        let track = appState.realtimeCoordinator.orderLiveTracker.open(
            role: .blind,
            polling: .blindRunner,
            peerFreshness: peerFreshness,
            currentStatus: { [weak self] in self?.order?.status },
            isSessionExpiryDeferred: { [weak appState] in appState?.isSessionExpiryDeferred ?? false },
            load: { [weak self] orderID in
                await self?.loadOrder(orderId: orderID, speakChanges: true)
            }
        )
        orderTrack = track
        let events = track.events
        orderTrackTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    /// 每种事件同步处理，处理时机不等任何网络请求（REST 详情在路上时，状态推送立即生效）。
    func handle(_ event: OrderTrackingEvent) {
        switch event {
        case .status(let update):
            handleStatusUpdate(update)
        case .peerLocation(let peer):
            handleVolunteerLocation(peer)
        case .peerLocationExpired:
            clearPeerLocation()
        case .liveUpdate, .blindStartConfirmed, .volunteerLost, .separationAlert:
            // 只发给陪跑员端的 track，跑者端收不到。
            break
        }
    }

    /// 判据原样照搬原来的 Combine 订阅：`order` 还没拉回来或不是这一单就丢弃。
    /// 处理完**必须** `acknowledge`：首页据此决定这一句它念不念（design §6）。
    private func handleStatusUpdate(_ update: RealtimeOrderStatusUpdate) {
        guard let current = order, current.orderId == update.orderId else {
            orderTrack?.acknowledge(update, spoke: false)
            return
        }
        // 完成态那句走独立任务（`startCompletionAnnouncement`），首页照现状也念，所以算没念。
        let spoke = apply(current.replacingStatus(with: update.toStatus), speakChanges: true)
        isLoading = false
        errorMessage = nil
        orderTrack?.acknowledge(update, spoke: spoke)
    }
}
