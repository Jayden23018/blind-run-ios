import Foundation

// 订单页那一侧的跟踪。由 `OrderLiveTracker.open` 创建，见 `OrderLiveTracker.swift` 顶部说明。

/// 一个订单页的跟踪。寿命跟页面 ViewModel：`pause()`（页面离开屏幕）不结束它。
@MainActor
final class OrderLiveTrack {
    let role: WSRole
    let events: AsyncStream<OrderTrackingEvent>
    private(set) var followedOrderID: Int64?
    private(set) var isEnded = false

    private let continuation: AsyncStream<OrderTrackingEvent>.Continuation
    private let policy: OrderPollingPolicy
    private let freshness: PeerLocationFreshness
    private let currentStatus: @MainActor () -> RunOrderStatus?
    private let isSessionExpiryDeferred: @MainActor () -> Bool
    private let load: @MainActor (Int64) async -> Void
    private weak var tracker: OrderLiveTracker?

    private var acceptsPeerLocations = false
    private var currentPeer: FreshPeerLocation?
    private var pollingTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var refreshTasks: [UUID: Task<Void, Never>] = [:]
    private var recentAcknowledgements: [(update: RealtimeOrderStatusUpdate, spoke: Bool)] = []
    private var waiters: [AcknowledgementWaiter] = []
    private static let maximumRecentAcknowledgements = 16

    init(
        role: WSRole,
        policy: OrderPollingPolicy,
        freshness: PeerLocationFreshness,
        currentStatus: @escaping @MainActor () -> RunOrderStatus?,
        isSessionExpiryDeferred: @escaping @MainActor () -> Bool,
        load: @escaping @MainActor (Int64) async -> Void,
        tracker: OrderLiveTracker
    ) {
        self.role = role
        self.policy = policy
        self.freshness = freshness
        self.currentStatus = currentStatus
        self.isSessionExpiryDeferred = isSessionExpiryDeferred
        self.load = load
        self.tracker = tracker
        var continuation: AsyncStream<OrderTrackingEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    /// 页面的 `startPolling` 里跟踪那一部分：登记活跃订单（不带 `status:` 的重载）、
    /// （重）开轮询并立即拉一次、开始收对方位置。重复调用会取消旧循环、立即重拉。
    func follow(orderID: Int64) {
        guard !isEnded else { return }
        if followedOrderID != orderID {
            clearPeer()
        }
        followedOrderID = orderID
        acceptsPeerLocations = true
        tracker?.register(orderID: orderID)
        startPolling(orderID: orderID)
        if tracker?.hasPendingRefresh(orderID) == true {
            runRefresh(orderID: orderID)
        }
        // 跑者页原本在订阅时回放一次已存的最新样本，陪跑员页不回放（design §3，负责人 11-08 定不改）。
        if role == .blind, let sample = tracker?.latestPeerLocation(orderID: orderID, ownerRole: .volunteer) {
            receivePeerLocation(sample, now: tracker?.currentDate ?? Date())
        }
    }

    /// 页面的 `stopPolling` 里跟踪那一部分：停轮询、停收对方位置、清标记。
    /// 🔴 不注销活跃订单（协调器依赖这一点，`+Notifications.swift` 的注释），其余事件照常送达。
    func pause() {
        pollingTask?.cancel()
        pollingTask = nil
        acceptsPeerLocations = false
        clearPeer()
    }

    /// 页面处理完一条 `.status` 后调：念了（或用自己的整句覆盖了）就 `spoke: true`，
    /// 被守卫丢弃或刻意不念（如完成态）就 `spoke: false`。
    /// 回话总是记下：已有人在等时也记，之后再问同一条更新会立即拿到同一个答案，而不是等满超时。
    func acknowledge(_ update: RealtimeOrderStatusUpdate, spoke: Bool) {
        let matching = waiters.filter { $0.update == update }
        waiters.removeAll { $0.update == update }
        matching.forEach { $0.resume(spoke) }
        recentAcknowledgements.append((update, spoke))
        if recentAcknowledgements.count > Self.maximumRecentAcknowledgements {
            recentAcknowledgements.removeFirst(recentAcknowledgements.count - Self.maximumRecentAcknowledgements)
        }
    }

    /// 结束跟踪。之后不再调 `load`、不再发事件。同样不注销活跃订单。
    func end() {
        guard !isEnded else { return }
        // 与 pause / 换单相同，先清对方标记（design §3），再结束流。
        clearPeer()
        isEnded = true
        pollingTask?.cancel()
        pollingTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        refreshTasks.values.forEach { $0.cancel() }
        refreshTasks.removeAll()
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(nil) }
        continuation.finish()
    }

    #if DEBUG
    /// 首页正挂着等回话的次数。单测据此确认「真的在等」再回话。
    var pendingAcknowledgementWaiterCountForTesting: Int { waiters.count }
    #endif

    deinit {
        // 页面释放时走到这里。任务都只弱引用 track，会在下一步自己退出；等回话的首页由超时兜底。
        continuation.finish()
    }

    // MARK: - tracker 调

    func deliver(_ event: OrderTrackingEvent) {
        guard !isEnded else { return }
        continuation.yield(event)
    }

    func receivePeerLocation(_ sample: RealtimePeerLocationSample, now: Date) {
        guard !isEnded, acceptsPeerLocations,
              let fresh = freshness.accept(
                  sample,
                  expectedOwner: role == .blind ? .volunteer : .blind,
                  orderID: followedOrderID,
                  now: now
              ) else { return }
        currentPeer = fresh
        continuation.yield(.peerLocation(fresh))
        scheduleExpiry(for: fresh)
    }

    /// 刷新与轮询可以并行（负责人 11-08 定不改成单飞），过时的响应由协调器的 request token 挡掉。
    /// 刷新不看登录暂缓，与原有订阅相同。
    func runRefresh(orderID: Int64) {
        guard !isEnded else { return }
        let id = UUID()
        let load = self.load
        refreshTasks[id] = Task { [weak self] in
            await load(orderID)
            self?.refreshTasks.removeValue(forKey: id)
        }
    }

    func awaitAcknowledgement(of update: RealtimeOrderStatusUpdate, timeout: TimeInterval) async -> Bool? {
        if let known = recentAcknowledgements.first(where: { $0.update == update }) {
            return known.spoke
        }
        guard !isEnded else { return nil }
        let waiter = AcknowledgementWaiter(update: update)
        waiters.append(waiter)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            waiter.attach(continuation)
            // 超时任务强持有 waiter 而不是 track：track 先被释放时，首页照样会在上限到点时拿到结果。
            Task { [weak self, waiter] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.waiters.removeAll { $0 === waiter }
                waiter.resume(nil)
            }
        }
    }

    // MARK: - 轮询

    private func startPolling(orderID: Int64) {
        pollingTask?.cancel()
        let policy = self.policy
        pollingTask = Task { [weak self] in
            let currentTrack: () -> OrderLiveTrack? = { [weak self] in self }
            // 暂缓中连第一次也不拉（两端原有循环相同）。
            guard let load = currentTrack().flatMap({ $0.isDeferred ? nil : $0.load }) else { return }
            await load(orderID)
            switch policy {
            case .blindRunner:
                await Self.pollBlindRunner(orderID: orderID, currentTrack: currentTrack)
            case .volunteer:
                await Self.pollVolunteer(orderID: orderID, currentTrack: currentTrack)
            }
        }
    }

    // 两个循环每一步都临时取回 track，睡眠期间不强持有它：页面释放后 track 能立即释放。
    private static func pollBlindRunner(orderID: Int64, currentTrack: () -> OrderLiveTrack?) async {
        while !Task.isCancelled {
            guard let nanos = currentTrack().flatMap({ $0.shouldContinueBlindRunnerPolling ? $0.intervalNanoseconds : nil }) else { return }
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            guard let load = currentTrack()?.load else { return }
            await load(orderID)
        }
    }

    private static func pollVolunteer(orderID: Int64, currentTrack: () -> OrderLiveTrack?) async {
        while !Task.isCancelled {
            guard let nanos = currentTrack()?.intervalNanoseconds else { return }
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            guard let load = currentTrack()?.load else { return }
            await load(orderID)
            guard let track = currentTrack() else { return }
            if track.currentStatus()?.isTerminal == true { return }
            if track.isDeferred { return }
        }
    }

    private var shouldContinueBlindRunnerPolling: Bool {
        if isDeferred { return false }
        guard let status = currentStatus() else { return true }
        return status.shouldPoll
    }

    private var isDeferred: Bool { isSessionExpiryDeferred() }

    private var intervalNanoseconds: UInt64 {
        UInt64((tracker?.interval ?? AppConstants.Timing.orderPollingInterval) * 1_000_000_000)
    }

    // MARK: - 对方位置过期

    private func scheduleExpiry(for peer: FreshPeerLocation) {
        expiryTask?.cancel()
        let remaining = max(0.01, peer.remaining)
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            } catch {
                return
            }
            // 只清它自己：期间来过更新的样本就不动。
            guard !Task.isCancelled, let self, self.currentPeer == peer else { return }
            self.currentPeer = nil
            self.expiryTask = nil
            self.continuation.yield(.peerLocationExpired)
        }
    }

    private func clearPeer() {
        expiryTask?.cancel()
        expiryTask = nil
        currentPeer = nil
        continuation.yield(.peerLocationExpired)
    }
}

/// 首页等订单页回话的一次等待。单独成类，让超时任务能在 track 已释放时仍把结果交回去。
@MainActor
final class AcknowledgementWaiter {
    let update: RealtimeOrderStatusUpdate
    private var continuation: CheckedContinuation<Bool?, Never>?
    private var result: Bool??

    init(update: RealtimeOrderStatusUpdate) {
        self.update = update
    }

    func attach(_ continuation: CheckedContinuation<Bool?, Never>) {
        if let result {
            continuation.resume(returning: result)
            return
        }
        self.continuation = continuation
    }

    func resume(_ spoke: Bool?) {
        guard result == nil else { return }
        result = .some(spoke)
        continuation?.resume(returning: spoke)
        continuation = nil
    }
}
