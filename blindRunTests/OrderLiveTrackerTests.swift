import XCTest
@testable import blindRun

/// 订单实时跟踪第 1 批（#886，OpenSpec `unify-order-live-tracking`）：状态与轮询。
/// 不起 WebSocket、不连服务器：直接往协调器喂解码后的事件。
@MainActor
final class OrderLiveTrackerTests: XCTestCase, OrderLiveTrackerTestSupport {
    // MARK: - 状态

    func testValidatedStatusUpdateReachesTheFollowingTrack() async {
        let (coordinator, tracker) = makePair()
        let loads = OrderTrackerLoadCounter()
        let track = openTrack(tracker, role: .blind, loads: loads, coordinator: coordinator)
        let recorder = OrderTrackerEventRecorder(track)
        coordinator.registerActiveOrder(orderID, status: .pendingAccept)
        track.follow(orderID: orderID)

        coordinator.simulateIncomingEventForTesting(.orderStatusChanged(statusEvent(
            messageID: "c4a2d3b1-2345-4bcd-8ef0-123456789abc", from: "PENDING_ACCEPT", to: "DRIVER_EN_ROUTE"
        )))

        await waitUntil { recorder.statuses.count == 1 }
        XCTAssertEqual(recorder.statuses.first?.toStatus, .driverEnRoute)
        track.end()
    }

    func testUnknownTargetStatusIsNotDeliveredButTriggersOneRefresh() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let loads = OrderTrackerLoadCounter()
        let track = openTrack(tracker, role: .blind, loads: loads, coordinator: coordinator)
        let recorder = OrderTrackerEventRecorder(track)
        coordinator.registerActiveOrder(orderID, status: .pendingAccept)
        track.follow(orderID: orderID)
        await waitUntil { loads.count == 1 }  // follow 立即拉的那一次

        coordinator.simulateIncomingEventForTesting(.orderStatusChanged(statusEvent(
            messageID: "d4a2d3b1-2345-4bcd-8ef0-123456789abc", from: "PENDING_ACCEPT", to: "SOMETHING_NEW"
        )))

        await waitUntil { loads.count == 2 }
        await settle()
        XCTAssertTrue(recorder.statuses.isEmpty, "未知状态值不许改页面状态")
        XCTAssertEqual(loads.count, 2, "只多拉一次详情")
        track.end()
    }

    func testReplayedMessageIDIsDeliveredOnce() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .volunteer, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let recorder = OrderTrackerEventRecorder(track)
        coordinator.registerActiveOrder(orderID, status: .pendingAccept)
        track.follow(orderID: orderID)
        let event = statusEvent(messageID: "e4a2d3b1-2345-4bcd-8ef0-123456789abc", from: "PENDING_ACCEPT", to: "DRIVER_EN_ROUTE")

        coordinator.simulateIncomingEventForTesting(.orderStatusChanged(event))
        coordinator.simulateIncomingEventForTesting(.orderStatusChanged(event))

        await waitUntil { recorder.statuses.count >= 1 }
        await settle()
        XCTAssertEqual(recorder.statuses.count, 1)
        track.end()
    }

    func testAnotherOrdersStatusDoesNotReachTheTrack() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let recorder = OrderTrackerEventRecorder(track)
        coordinator.registerActiveOrder(orderID, status: .pendingAccept)
        coordinator.registerActiveOrder(99, status: .pendingAccept)
        track.follow(orderID: orderID)

        coordinator.simulateIncomingEventForTesting(.orderStatusChanged(statusEvent(
            messageID: "f4a2d3b1-2345-4bcd-8ef0-123456789abc", orderID: 99, from: "PENDING_ACCEPT", to: "DRIVER_EN_ROUTE"
        )))

        await settle()
        XCTAssertTrue(recorder.statuses.isEmpty)
        track.end()
    }

    // MARK: - 轮询

    /// 两种策略都在第一次拉之后看到「不再需要轮询的终态」。跑者先判后拉 ⇒ 不再拉；
    /// 陪跑员先拉后判 ⇒ 还会再拉一次。同一个输入，两种顺序给出不同的拉取次数。
    func testBlindRunnerPollingChecksBeforeFetchingAgain() async {
        let (coordinator, tracker) = makePair(pollingInterval: 0.02)
        let loads = OrderTrackerLoadCounter()
        let status = OrderTrackerStatusBox(.completed)
        let track = openTrack(tracker, role: .blind, polling: .blindRunner, loads: loads, coordinator: coordinator, status: status)
        track.follow(orderID: orderID)

        await waitUntil { loads.count == 1 }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(loads.count, 1)
        track.end()
    }

    func testVolunteerPollingFetchesOnceMoreBeforeStoppingAtTerminal() async {
        let (coordinator, tracker) = makePair(pollingInterval: 0.02)
        let loads = OrderTrackerLoadCounter()
        let status = OrderTrackerStatusBox(.completed)
        let track = openTrack(tracker, role: .volunteer, polling: .volunteer, loads: loads, coordinator: coordinator, status: status)
        track.follow(orderID: orderID)

        await waitUntil { loads.count == 2 }
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(loads.count, 2)
        track.end()
    }

    func testPollingKeepsGoingWhileStatusNeedsIt() async {
        let (coordinator, tracker) = makePair(pollingInterval: 0.02)
        let loads = OrderTrackerLoadCounter()
        let track = openTrack(tracker, role: .blind, loads: loads, coordinator: coordinator, status: OrderTrackerStatusBox(.inProgress))
        track.follow(orderID: orderID)

        await waitUntil(timeout: 2) { loads.count >= 3 }
        track.end()
    }

    func testDeferredSessionSkipsEvenTheFirstPoll() async {
        let (coordinator, tracker) = makePair(pollingInterval: 0.02)
        let loads = OrderTrackerLoadCounter()
        let track = openTrack(tracker, role: .volunteer, polling: .volunteer, loads: loads, coordinator: coordinator, deferred: true)
        track.follow(orderID: orderID)

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(loads.count, 0)
        track.end()
    }

    func testRefreshAlreadyPendingWhenFollowingIsFetched() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        coordinator.requestOrderRefresh(orderID, reason: .reconnected)
        let loads = OrderTrackerLoadCounter()
        // 暂缓中：关掉轮询那一次，只留补拉（刷新不看暂缓）。
        let track = openTrack(tracker, role: .blind, loads: loads, coordinator: coordinator, deferred: true)
        track.follow(orderID: orderID)

        await waitUntil { loads.count == 1 }
        XCTAssertFalse(coordinator.pendingOrderRefreshIDs.contains(orderID), "拉到权威结果后清掉挂着的请求")
        track.end()
    }

    func testEndedTrackNoLongerFetches() async {
        let (coordinator, tracker) = makePair(pollingInterval: 0.02)
        let loads = OrderTrackerLoadCounter()
        let track = openTrack(tracker, role: .blind, loads: loads, coordinator: coordinator, status: OrderTrackerStatusBox(.inProgress))
        track.follow(orderID: orderID)
        await waitUntil { loads.count == 1 }

        track.end()
        let afterEnd = loads.count
        coordinator.requestOrderRefresh(orderID, reason: .statusChanged)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(loads.count, afterEnd)
    }
}
