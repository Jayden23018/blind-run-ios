import XCTest
@testable import blindRun

/// `OrderLiveTrackerTests` 与 `OrderLiveTrackerPeerTests` 共用的构造与等待（类直接继承 XCTestCase，共享走协议扩展）。
@MainActor
protocol OrderLiveTrackerTestSupport: XCTestCase {}

extension OrderLiveTrackerTestSupport {
    var orderID: Int64 { 42 }
    var fixedNow: Date { Date(timeIntervalSince1970: 1_800_000_000) }


    func makePair(
        pollingInterval: TimeInterval = 60,
        announcementTimeout: TimeInterval = 1
    ) -> (AppRealtimeCoordinator, OrderLiveTracker) {
        let coordinator = AppRealtimeCoordinator()
        let now = fixedNow
        let start = Date()
        // 真实流逝的时间叠在固定起点上：过期任务按真实时钟睡，样本年龄按同一条时间线算。
        let tracker = OrderLiveTracker(
            coordinator: coordinator,
            pollingInterval: pollingInterval,
            announcementTimeout: announcementTimeout,
            now: { now.addingTimeInterval(Date().timeIntervalSince(start)) }
        )
        coordinator.replaceOrderLiveTrackerForTesting(tracker)
        return (coordinator, tracker)
    }

    func openTrack(
        _ tracker: OrderLiveTracker,
        role: WSRole,
        polling: OrderPollingPolicy = .blindRunner,
        loads: OrderTrackerLoadCounter,
        coordinator: AppRealtimeCoordinator,
        peerFreshness: TimeInterval = 15,
        status: OrderTrackerStatusBox? = nil,
        deferred: OrderTrackerFlag? = nil
    ) -> OrderLiveTrack {
        tracker.open(
            role: role,
            polling: polling,
            peerFreshness: peerFreshness,
            currentStatus: { status?.value },
            isSessionExpiryDeferred: { deferred?.value ?? false },
            load: { [weak coordinator] orderID in
                loads.count += 1
                // 模拟页面 `load` 的记账：拿到权威结果就清掉挂着的刷新。
                coordinator?.completeOrderRefresh(orderID)
            }
        )
    }

    func statusEvent(messageID: String?, orderID: Int64? = nil, from: String?, to: String) -> WSOrderStatusChanged {
        WSOrderStatusChanged(
            type: WSMessageType.orderStatusChanged.rawValue,
            messageId: messageID,
            orderId: orderID ?? self.orderID,
            fromStatus: from,
            toStatus: to,
            message: nil,
            ttsText: nil,
            priority: "NORMAL",
            timestamp: "2026-11-08T12:00:00Z"
        )
    }

    func update() -> RealtimeOrderStatusUpdate {
        RealtimeOrderStatusUpdate(orderId: orderID, fromStatus: .driverArrived, toStatus: .inProgress, receivedAt: fixedNow)
    }

    func sample(ageSeconds: TimeInterval, owner: RealtimePeerRole) -> RealtimePeerLocationSample {
        RealtimePeerLocationSample(
            orderId: orderID,
            ownerRole: owner,
            latitude: 39.9,
            longitude: 116.4,
            timestampMilliseconds: Int64((fixedNow.timeIntervalSince1970 - ageSeconds) * 1_000)
        )
    }

    /// 采样时刻相对 tracker 时间线的「现在」往前推 `ageSeconds`；`timestampOffset` 毫秒让后一条比前一条新。
    func volunteerLocation(ageSeconds: TimeInterval, timestampOffset: Int64 = 0) -> WSVolunteerLocationUpdate {
        WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: orderID,
            lat: 39.9,
            lng: 116.4,
            timestamp: Int64((fixedNow.timeIntervalSince1970 - ageSeconds) * 1_000) + timestampOffset
        )
    }

    func alert(orderID: Int64, type: String) -> RealtimeSeparationAlert {
        RealtimeSeparationAlert(
            eventID: UUID().uuidString, orderID: orderID, eventType: type,
            distanceMeters: nil, displayText: "", speechText: "", timestamp: nil
        )
    }

    func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    func waitUntil(timeout: TimeInterval = 1, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "等待超时")
    }
}

@MainActor
final class OrderTrackerLoadCounter {
    var count = 0
}

@MainActor
final class OrderTrackerFlag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

@MainActor
final class OrderTrackerStatusBox {
    var value: RunOrderStatus?
    init(_ value: RunOrderStatus?) { self.value = value }
}

@MainActor
final class OrderTrackerEventRecorder {
    private(set) var statuses: [RealtimeOrderStatusUpdate] = []
    private(set) var peers: [FreshPeerLocation] = []
    private(set) var expiredCount = 0
    private(set) var separationCount = 0
    private(set) var liveUpdateCount = 0
    private(set) var startConfirmedCount = 0
    private(set) var volunteerLostCount = 0
    private var task: Task<Void, Never>?

    init(_ track: OrderLiveTrack) {
        let events = track.events
        task = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .status(let update): self.statuses.append(update)
                case .peerLocation(let peer): self.peers.append(peer)
                case .peerLocationExpired: self.expiredCount += 1
                case .separationAlert: self.separationCount += 1
                case .liveUpdate: self.liveUpdateCount += 1
                case .blindStartConfirmed: self.startConfirmedCount += 1
                case .volunteerLost: self.volunteerLostCount += 1
                }
            }
        }
    }

    func reset() {
        statuses = []
        peers = []
        expiredCount = 0
        separationCount = 0
        liveUpdateCount = 0
        startConfirmedCount = 0
        volunteerLostCount = 0
    }

    deinit { task?.cancel() }
}
