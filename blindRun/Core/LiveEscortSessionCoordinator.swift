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
                }
            }
        }
        scheduleSendLatest(now: Date())
        refreshHealth(now: Date())
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

    private func clearRuntimeSession() {
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
