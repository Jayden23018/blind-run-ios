import Combine
import CoreLocation
import Foundation

enum LiveEscortHealthState: Equatable, Sendable {
    case idle
    case waitingForLocation
    case permissionRequired
    case networkDisconnected
    case active(background: Bool)

    var userMessage: String? {
        switch self {
        case .idle: return nil
        case .waitingForLocation: return "设备位置暂时不可用，已暂停同行位置共享。"
        case .permissionRequired: return "定位权限已关闭，同行位置与路线记录已暂停，请前往系统设置开启。"
        case .networkDisconnected: return "网络连接已中断，同行位置将在重连后自动恢复。"
        case .active(let background) where background:
            return "路线记录正在运行，锁屏后仍会持续使用定位，可能增加电量消耗。"
        case .active:
            return "同行位置共享已开启；服务开始后锁屏仍会持续记录路线，可能增加电量消耗，并受系统定位限制影响。"
        }
    }
}

/// App 生命周期内唯一的同行会话所有者。ViewModel 只提交权威订单状态，不自行发位置或转换坐标。
@MainActor
final class LiveEscortSessionCoordinator: ObservableObject {
    nonisolated static let peerFreshness: TimeInterval = 15
    nonisolated static let reportInterval: TimeInterval = 5

    /// 锁屏卡刷新的节流间隔。与盲人端 `BlindOrderStatusViewModel.trackPollingInterval` 取同一个数：
    /// 两边拉的是同一个 `GET /api/orders/{id}/track`，盲人端推过来一次就算一次
    /// （见 `submitTrackStats`），所以盲人端不会因为多了锁屏卡而多发请求。
    nonisolated static let liveActivityRefreshInterval: TimeInterval = 10

    @Published private(set) var healthState: LiveEscortHealthState = .idle
    @Published private(set) var activeOrderID: Int64?
    @Published private(set) var activeStatus: RunOrderStatus?

    private let realtimeCoordinator: AppRealtimeCoordinator
    private let reportInterval: TimeInterval
    private let sendLocation: @MainActor @Sendable (WebSocketService, LocatedCoordinate) async -> Void
    private weak var webSocketService: WebSocketService?
    private weak var locationService: LocationService?
    private var role: UserRole?
    private var identityKey: String?
    private var reportTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var sendGeneration: UInt64 = 0
    private var shouldSendLatestAfterCurrent = false
    private var cancellables: Set<AnyCancellable> = []
    private var lastSentAt: Date?

    // MARK: 锁屏实时活动
    //
    // 起停挂在这里而不是两端各自的订单页上：`updateOwnedOrder` / `clearOwnedOrder` 是两端
    // **共用的漏斗**（盲人端 5 个调用点、志愿者端 4 个），挂一次就两端都有，
    // 且不需要碰 `blindRun/Volunteer/**`。

    /// 拉三个数字的方式。由 `AppState` 在装配时注入（协调器自己不认识 `SafetyServing`）。
    ///
    /// **只有陪跑员端会真的用到它**：盲人端的订单页本来就每 10 秒拉一次 `/track`，
    /// 拉到就通过 `submitTrackStats` 推过来，节流器随之复位，这里就不会重复发请求。
    /// 陪跑员端那半屏的数字在 `blindRun/Volunteer/**` 里（本轮不可改），所以由这里自己拉。
    var trackStatsProvider: (@MainActor @Sendable (Int64) async throws -> TrackStats)?

    private var liveActivityPartnerName: String?
    private var lastLiveActivityRefreshAt: Date?
    private var latestTrackStats: TrackStats?
    private var liveActivityRefreshTask: Task<Void, Never>?

    #if DEBUG
    private(set) var reconciliationCountForTesting = 0
    #endif

    init(
        realtimeCoordinator: AppRealtimeCoordinator,
        reportInterval: TimeInterval = LiveEscortSessionCoordinator.reportInterval,
        sendLocation: @escaping @MainActor @Sendable (WebSocketService, LocatedCoordinate) async -> Void = { service, sample in
            #if DEBUG
            if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_HANG_ESCORT_SEND"] == "1" {
                await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
                return
            }
            #endif
            service.sendLocationUpdate(
                lat: sample.coordinate.latitude,
                lng: sample.coordinate.longitude
            )
        }
    ) {
        self.realtimeCoordinator = realtimeCoordinator
        self.reportInterval = reportInterval
        self.sendLocation = sendLocation
    }

    var isSessionEligible: Bool {
        guard let activeStatus else { return false }
        return [.driverEnRoute, .driverArrived, .inProgress].contains(activeStatus)
    }

    func configure(
        identityKey: String?,
        role: UserRole?,
        webSocketService: WebSocketService?,
        locationService: LocationService? = nil
    ) {
        if self.identityKey != identityKey || self.role != role || self.webSocketService !== webSocketService {
            reset(clearIdentity: false)
        }
        self.identityKey = identityKey
        self.role = role
        self.webSocketService = webSocketService
        if let locationService { self.locationService = locationService }
        bindDependencies()
        scheduleReconcile()
    }

    func attachLocationService(_ service: LocationService) {
        locationService = service
        bindDependencies()
        scheduleReconcile()
    }

    func updateOwnedOrder(orderID: Int64, status: RunOrderStatus) {
        guard activeOrderID != orderID || activeStatus != status else {
            ClientFlowDiagnostics.record(event: "coalesced", operation: "escort-session")
            return
        }
        if let previous = activeOrderID, previous != orderID {
            realtimeCoordinator.unregisterActiveOrder(previous)
            clearRuntimeSession()
        }
        activeOrderID = orderID
        activeStatus = status
        realtimeCoordinator.registerActiveOrder(orderID, status: status)

        if [.completed, .cancelled, .rematching, .noVolunteer].contains(status) {
            clearOwnedOrder()
            return
        }
        ClientFlowDiagnostics.record(event: "scheduled", operation: "escort-session")
        scheduleReconcile()
        syncLiveActivity()
    }

    func clearOwnedOrder() {
        if let activeOrderID { realtimeCoordinator.unregisterActiveOrder(activeOrderID) }
        activeOrderID = nil
        activeStatus = nil
        clearRuntimeSession()
    }

    func reset(clearIdentity: Bool = true) {
        clearOwnedOrder()
        cancellables.removeAll()
        webSocketService = nil
        if clearIdentity {
            identityKey = nil
            role = nil
            locationService = nil
        }
    }

    func freshPeerCoordinate(now: Date = Date()) -> LocatedCoordinate? {
        guard let orderID = activeOrderID, let role else { return nil }
        let peerRole: RealtimePeerRole = role == .blind ? .volunteer : .blind
        guard let sample = realtimeCoordinator.latestPeerLocation(orderID: orderID, ownerRole: peerRole) else {
            return nil
        }
        let capturedAt = Date(timeIntervalSince1970: TimeInterval(sample.timestampMilliseconds) / 1_000)
        guard now.timeIntervalSince(capturedAt) <= Self.peerFreshness else { return nil }
        return BackendCoordinateNormalizer.backend(
            latitude: sample.latitude,
            longitude: sample.longitude,
            capturedAt: capturedAt
        )
    }

    private func bindDependencies() {
        cancellables.removeAll()
        webSocketService?.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.canSendOrQueueMessages, self.isSessionEligible {
                    self.scheduleSendLatest(now: Date())
                }
                self.refreshHealth(now: Date())
            }
            .store(in: &cancellables)
        locationService?.latestDeviceSamplePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                guard let self, sample != nil else { return }
                if self.isSessionEligible, self.lastSentAt == nil {
                    self.scheduleSendLatest(now: Date())
                }
                self.refreshHealth(now: Date())
            }
            .store(in: &cancellables)
        locationService?.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshHealth(now: Date()) }
            .store(in: &cancellables)
        locationService?.$locationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshHealth(now: Date()) }
            .store(in: &cancellables)
    }

    private func scheduleReconcile() {
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            ClientFlowDiagnostics.record(event: "started", operation: "escort-session")
            self.evaluateSession()
            #if DEBUG
            self.reconciliationCountForTesting += 1
            #endif
            ClientFlowDiagnostics.record(event: "finished", operation: "escort-session")
            self.reconcileTask = nil
        }
    }

    private func evaluateSession() {
        guard identityKey != nil, role != nil, isSessionEligible else {
            clearRuntimeSession()
            return
        }
        let needsBackground = activeStatus == .inProgress
        locationService?.setEscortBackgroundMode(enabled: needsBackground)
        if reportTask == nil {
            reportTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: UInt64(self.reportInterval * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self.scheduleSendLatest(now: Date())
                    self.refreshHealth(now: Date())
                    self.refreshLiveActivityIfNeeded(now: Date())
                }
            }
        }
        scheduleSendLatest(now: Date())
        refreshHealth(now: Date())
        // 进 `IN_PROGRESS` 的那一刻先拉一次，否则锁屏卡要顶着「--」等满一个上报周期。
        refreshLiveActivityIfNeeded(now: Date())
    }

    private func scheduleSendLatest(now: Date) {
        guard sendTask == nil else {
            shouldSendLatestAfterCurrent = true
            ClientFlowDiagnostics.record(event: "coalesced", operation: "escort-location-send")
            return
        }
        sendGeneration &+= 1
        let generation = sendGeneration
        sendTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.sendLatestLocation(now: now)
            guard generation == self.sendGeneration else { return }
            self.sendTask = nil
            guard self.shouldSendLatestAfterCurrent else { return }
            self.shouldSendLatestAfterCurrent = false
            self.scheduleSendLatest(now: Date())
        }
    }

    private func sendLatestLocation(now: Date) async {
        guard isSessionEligible,
              webSocketService?.connectionState.canSendOrQueueMessages == true,
              let sample = locationService?.latestEscortBackendSample(now: now) else { return }
        guard let webSocketService else { return }
        ClientFlowDiagnostics.record(event: "started", operation: "escort-location-send")
        await sendLocation(webSocketService, sample)
        guard !Task.isCancelled, isSessionEligible else { return }
        lastSentAt = now
        ClientFlowDiagnostics.record(event: "finished", operation: "escort-location-send")
    }

    private func refreshHealth(now: Date) {
        guard isSessionEligible else {
            setHealthState(.idle)
            return
        }
        guard locationService?.isAuthorized == true else {
            setHealthState(.permissionRequired)
            return
        }
        guard webSocketService?.connectionState == .connected else {
            setHealthState(.networkDisconnected)
            return
        }
        // 样本年龄闸在 `latestEscortBackendSample` 里，所以「样本停更超过 60 秒」和
        // 「Core Location 明确报错」在这里是同一条分支 —— 对用户也确实是同一件事。
        // 不需要额外的定时器：上报循环每 `reportInterval`（5 秒）就会走一次这里。
        guard locationService?.latestEscortBackendSample(now: now) != nil else {
            setHealthState(.waitingForLocation)
            return
        }
        setHealthState(.active(background: activeStatus == .inProgress))
    }

    private func setHealthState(_ nextState: LiveEscortHealthState) {
        guard healthState != nextState else { return }
        healthState = nextState
    }

    // MARK: - 锁屏实时活动

    /// 盲人端订单页拉到 `/track` 之后把数字推过来。
    ///
    /// 推进来就复位节流器 —— 这条路径存在的全部意义就是**不让盲人端因为多了一张锁屏卡
    /// 而多发一倍的 `/track` 请求**。
    func submitTrackStats(_ stats: TrackStats, orderID: Int64) {
        guard orderID == activeOrderID else { return }
        latestTrackStats = stats
        lastLiveActivityRefreshAt = Date()
        syncLiveActivity()
    }

    /// 锁屏卡顶行要显示的对方姓名。**只有跑者端会传** —— 陪跑员端那张卡按项目负责人
    /// 2026-09-16 的决定不显示对方姓名，所以恒为 `nil`。
    func updateLiveActivityPartnerName(_ name: String?) {
        guard liveActivityPartnerName != name else { return }
        liveActivityPartnerName = name
        syncLiveActivity()
    }

    /// 该不该有这张卡、长什么样。`nil` = 不该有，结束掉。
    ///
    /// **抽成纯函数只为可测**：唯一调用点埋在 `@MainActor` + ActivityKit 后面，而这里要守的
    /// 两条都是红线 ——「锁屏卡只在 `IN_PROGRESS` 出现」（状态清单 §16/§17「IN_PROGRESS 期间常驻」）
    /// 与「陪跑员端不显示对方姓名」（项目负责人 2026-09-16 决定）。
    static func liveActivityPlan(
        orderID: Int64?,
        status: RunOrderStatus?,
        role: UserRole?,
        partnerName: String?
    ) -> (orderID: Int64, side: RunLiveActivitySide, partnerName: String?)? {
        guard let orderID, status == .inProgress, let role else { return nil }
        switch role {
        case .blind:
            return (orderID, .runner, partnerName)
        case .volunteer:
            return (orderID, .volunteer, nil)
        case .unset:
            return nil
        }
    }

    private func syncLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let plan = Self.liveActivityPlan(
            orderID: activeOrderID,
            status: activeStatus,
            role: role,
            partnerName: liveActivityPartnerName
        ) else {
            RunLiveActivityController.shared.end()
            return
        }
        RunLiveActivityController.shared.sync(
            orderID: plan.orderID,
            side: plan.side,
            partnerName: plan.partnerName,
            stats: latestTrackStats
        )
    }

    /// 跟着已有的上报循环走，节流到 `liveActivityRefreshInterval`。**不另起定时器。**
    ///
    /// 放在这条循环里而不是放在订单页的 `.task` 里，是因为锁屏卡要在**屏幕关着**的时候
    /// 继续更新，而那时候视图那条轮询未必还在跑；这条循环由后台定位撑着，是全 App
    /// 唯一一条确定还活着的定时链路。
    private func refreshLiveActivityIfNeeded(now: Date) {
        guard #available(iOS 16.2, *), activeStatus == .inProgress, let orderID = activeOrderID else { return }
        guard let provider = trackStatsProvider else { return }
        if let last = lastLiveActivityRefreshAt,
           now.timeIntervalSince(last) < Self.liveActivityRefreshInterval { return }
        guard liveActivityRefreshTask == nil else { return }
        lastLiveActivityRefreshAt = now
        liveActivityRefreshTask = Task { [weak self] in
            defer { self?.liveActivityRefreshTask = nil }
            // 失败不清空已有数字、不播报 —— 与 `BlindOrderStatusViewModel.refreshTrackStatsIfNeeded`
            // 逐字相同的理由：跑动中一次网络抖动把锁屏上的距离归零，比暂时不更新糟得多。
            guard let stats = try? await provider(orderID) else { return }
            guard let self, self.activeOrderID == orderID else { return }
            self.latestTrackStats = stats
            self.syncLiveActivity()
        }
    }

    private func clearRuntimeSession() {
        if #available(iOS 16.2, *) { RunLiveActivityController.shared.end() }
        liveActivityRefreshTask?.cancel()
        liveActivityRefreshTask = nil
        lastLiveActivityRefreshAt = nil
        latestTrackStats = nil
        liveActivityPartnerName = nil
        reconcileTask?.cancel()
        reconcileTask = nil
        reportTask?.cancel()
        reportTask = nil
        sendTask?.cancel()
        sendTask = nil
        sendGeneration &+= 1
        shouldSendLatestAfterCurrent = false
        lastSentAt = nil
        locationService?.setEscortBackgroundMode(enabled: false)
        setHealthState(.idle)
    }
}
