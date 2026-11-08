import Foundation

// 订单实时跟踪（OpenSpec `unify-order-live-tracking`，#857 候选 5，第 1 批 #886）。
//
// 两端订单页「跟住一张单」的全部机制都在这里：状态更新、刷新调度、5 秒轮询兜底、
// 对方位置的新鲜度与过期、陪跑员端的几条附带推送，以及「状态句这一次谁念」的回话。
//
// 🔴 这个 module **不判订单状态**：它只转交 `AppRealtimeCoordinator` 已经校验过的更新，
// 不调任何流转或求助端点。状态机的一切判定留在页面与协调器（AGENTS §5、§6）。
// 内部只用 async/await，不持有 `AnyCancellable`：协调器在自己的发布点旁直接调用这里。

/// 订单页从一条 track 收到的事件。页面同步处理，处理时机不等任何网络请求。
enum OrderTrackingEvent: Sendable {
    /// 协调器校验过的状态更新（两端）。页面处理后**必须**调 `OrderLiveTrack.acknowledge`。
    case status(RealtimeOrderStatusUpdate)
    /// 已过新鲜度判据的对方位置（两端）。
    case peerLocation(FreshPeerLocation)
    /// 对方位置过期、离页或换单（两端）。页面据此清掉标记。
    case peerLocationExpired
    /// ETA / 汇合距离档位（陪跑员）。
    case liveUpdate(RealtimeOrderLiveUpdate)
    /// 跑者点了「可以开始」（陪跑员）。信封没有 `orderId`，页面自己判是不是汇合态。
    case blindStartConfirmed
    /// 出发后失联、单已转走（陪跑员）。信封没有 `orderId`，页面自己判。
    case volunteerLost
    /// 本单的 `ESCORT_DISTANCE_ALERT`（陪跑员），只发 track 打开之后到的。只是提示，不改状态。
    case separationAlert(RealtimeSeparationAlert)
}

/// 两端轮询的先后顺序不同，逐行照搬原有循环（design §4）。
enum OrderPollingPolicy: Sendable {
    /// 第一次拉之后：判停 → 睡 → 拉。停：暂缓中，或页面手上的状态不再需要轮询。
    case blindRunner
    /// 第一次拉之后：睡 → 拉 → 判停。停：页面手上的状态是终态，或暂缓中。
    case volunteer
}

/// 首页念某单的状态句之前问到的结果（design §6）。
enum PageAnnouncement: Sendable, Equatable {
    /// 订单页这一次已经念了，首页不念。
    case pageSpoke
    /// 没有订单页在跟这一单，或订单页这一次没念，或等回话超时：首页照念。
    case homeShouldSpeak
}

@MainActor
final class OrderLiveTracker {
    /// 首页等订单页回话的上限。宁可偶尔两句，不能零播报。
    nonisolated static let pageAnnouncementTimeout: TimeInterval = 1

    private weak var coordinator: AppRealtimeCoordinator?
    private let pollingInterval: TimeInterval
    private let announcementTimeout: TimeInterval
    private let now: () -> Date
    private var tracks: [WeakTrack] = []

    init(
        coordinator: AppRealtimeCoordinator,
        pollingInterval: TimeInterval? = nil,
        announcementTimeout: TimeInterval = OrderLiveTracker.pageAnnouncementTimeout,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        // 默认值在函数体里取：`AppConstants` 默认隔离在 MainActor，默认参数里引用会报隔离警告。
        self.pollingInterval = max(0.001, pollingInterval ?? AppConstants.Timing.orderPollingInterval)
        self.announcementTimeout = max(0, announcementTimeout)
        self.now = now
    }

    /// 页面第一次 `configure` 时调一次（`appState.realtimeCoordinator.orderLiveTracker.open`）。页面强持有返回的 track，tracker 只弱引用它：
    /// 页面 ViewModel 释放，track 随之释放，首页就会把这一单当成「没有订单页」。
    ///
    /// - Parameters:
    ///   - currentStatus: 读页面手上 `order?.status`（含推送改写过的值），轮询判停用。
    ///   - isSessionExpiryDeferred: 读 `appState.isSessionExpiryDeferred`。只拦轮询，不拦刷新（与原有循环相同）。
    ///   - load: 页面自己的拉详情函数。刷新记账（`completeOrderRefresh` / `failOrderRefresh`）留在它里面。
    func open(
        role: WSRole,
        polling: OrderPollingPolicy,
        peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness,
        currentStatus: @escaping @MainActor () -> RunOrderStatus?,
        isSessionExpiryDeferred: @escaping @MainActor () -> Bool,
        load: @escaping @MainActor (Int64) async -> Void
    ) -> OrderLiveTrack {
        let track = OrderLiveTrack(
            role: role,
            policy: polling,
            freshness: PeerLocationFreshness(threshold: peerFreshness),
            currentStatus: currentStatus,
            isSessionExpiryDeferred: isSessionExpiryDeferred,
            load: load,
            tracker: self
        )
        compact()
        tracks.append(WeakTrack(track: track))
        return track
    }

    /// 首页念某单的状态句之前调（design §6）。首页的「当前订单」更新不要等它。
    func pageAnnouncement(for update: RealtimeOrderStatusUpdate, role: WSRole) async -> PageAnnouncement {
        guard let track = liveTracks().first(where: { $0.role == role && $0.followedOrderID == update.orderId }) else {
            return .homeShouldSpeak
        }
        let spoke = await track.awaitAcknowledgement(of: update, timeout: announcementTimeout)
        return spoke == true ? .pageSpoke : .homeShouldSpeak
    }

    // MARK: - 协调器的直接调用（原有发布不删，design §2）

    func receiveStatus(_ update: RealtimeOrderStatusUpdate) {
        for track in liveTracks() where track.followedOrderID == update.orderId {
            track.deliver(.status(update))
        }
    }

    func receivePeerLocation(_ sample: RealtimePeerLocationSample) {
        let at = now()
        for track in liveTracks() {
            track.receivePeerLocation(sample, now: at)
        }
    }

    func receiveLiveUpdate(_ update: RealtimeOrderLiveUpdate) {
        for track in liveTracks() where track.role == .volunteer && track.followedOrderID == update.orderId {
            track.deliver(.liveUpdate(update))
        }
    }

    func receiveBlindStartConfirmed() {
        for track in liveTracks() where track.role == .volunteer {
            track.deliver(.blindStartConfirmed)
        }
    }

    func receiveVolunteerLost() {
        for track in liveTracks() where track.role == .volunteer {
            track.deliver(.volunteerLost)
        }
    }

    func receiveSeparationAlert(_ alert: RealtimeSeparationAlert) {
        guard alert.eventType == "ESCORT_DISTANCE_ALERT" else { return }
        for track in liveTracks() where track.role == .volunteer && track.followedOrderID == alert.orderID {
            track.deliver(.separationAlert(alert))
        }
    }

    /// 协调器把这一单放进 `pendingOrderRefreshIDs` 时调（首次请求与 1/2/4 秒重试两处）。
    func refreshRequested(_ orderID: Int64) {
        for track in liveTracks() where track.followedOrderID == orderID {
            track.runRefresh(orderID: orderID)
        }
    }

    // MARK: - 给 track 用

    func register(orderID: Int64) {
        coordinator?.registerActiveOrder(orderID)
    }

    func hasPendingRefresh(_ orderID: Int64) -> Bool {
        coordinator?.pendingOrderRefreshIDs.contains(orderID) ?? false
    }

    func latestPeerLocation(orderID: Int64, ownerRole: RealtimePeerRole) -> RealtimePeerLocationSample? {
        coordinator?.latestPeerLocation(orderID: orderID, ownerRole: ownerRole)
    }

    var currentDate: Date { now() }
    var interval: TimeInterval { pollingInterval }

    #if DEBUG
    var liveTrackCountForTesting: Int { liveTracks().count }
    #endif

    private func liveTracks() -> [OrderLiveTrack] {
        compact()
        return tracks.compactMap(\.track).filter { !$0.isEnded }
    }

    private func compact() {
        tracks.removeAll { $0.track == nil || $0.track?.isEnded == true }
    }

    private struct WeakTrack {
        weak var track: OrderLiveTrack?
    }
}
