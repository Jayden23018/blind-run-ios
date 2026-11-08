import XCTest
@testable import blindRun

/// 订单实时跟踪第 1 批（#886）：对方位置、首页念不念、陪跑员端附带推送。
@MainActor
final class OrderLiveTrackerPeerTests: XCTestCase, OrderLiveTrackerTestSupport {
    // MARK: - 对方位置

    func testPeerFreshnessAcceptsFourteenSecondsAndRejectsSixteen() {
        let freshness = PeerLocationFreshness(threshold: 15)
        let fresh = sample(ageSeconds: 14, owner: .volunteer)
        let stale = sample(ageSeconds: 16, owner: .volunteer)

        XCTAssertNotNil(freshness.accept(fresh, expectedOwner: .volunteer, orderID: orderID, now: fixedNow))
        XCTAssertNil(freshness.accept(stale, expectedOwner: .volunteer, orderID: orderID, now: fixedNow))
        XCTAssertNil(freshness.accept(fresh, expectedOwner: .blind, orderID: orderID, now: fixedNow), "方向不对不收")
        XCTAssertNil(freshness.accept(fresh, expectedOwner: .volunteer, orderID: 7, now: fixedNow), "单号不对不收")
        XCTAssertTrue(freshness.isFresh(capturedAt: fixedNow.addingTimeInterval(-14), now: fixedNow))
        XCTAssertFalse(freshness.isFresh(capturedAt: fixedNow.addingTimeInterval(-16), now: fixedNow))
    }

    func testFreshPeerSampleIsDeliveredAndExpiresOnItsOwn() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator, peerFreshness: 0.3)
        let recorder = OrderTrackerEventRecorder(track)
        track.follow(orderID: orderID)
        await settle()
        recorder.reset()

        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 0.1)))

        await waitUntil { recorder.peers.count == 1 }
        XCTAssertEqual(recorder.expiredCount, 0)
        await waitUntil(timeout: 2) { recorder.expiredCount == 1 }
        track.end()
    }

    func testReplacedPeerSampleDoesNotLetTheOldExpiryClearTheNewOne() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator, peerFreshness: 0.5)
        let recorder = OrderTrackerEventRecorder(track)
        track.follow(orderID: orderID)
        await settle()
        recorder.reset()

        // 第一条离过期只剩 0.1 秒，第二条还有 0.5 秒。
        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 0.4, timestampOffset: 0)))
        await waitUntil { recorder.peers.count == 1 }
        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 0, timestampOffset: 1)))
        await waitUntil { recorder.peers.count == 2 }

        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(recorder.expiredCount, 0, "旧样本的过期不许清掉新样本")
        await waitUntil(timeout: 2) { recorder.expiredCount == 1 }
        track.end()
    }

    func testPausedTrackStopsPeerLocationsButStillDeliversStatus() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let recorder = OrderTrackerEventRecorder(track)
        coordinator.registerActiveOrder(orderID, status: .pendingAccept)
        track.follow(orderID: orderID)
        track.pause()
        await settle()
        recorder.reset()

        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 0)))
        coordinator.simulateIncomingEventForTesting(.orderStatusChanged(statusEvent(
            messageID: "a5a2d3b1-2345-4bcd-8ef0-123456789abc", from: "PENDING_ACCEPT", to: "DRIVER_EN_ROUTE"
        )))

        await waitUntil { recorder.statuses.count == 1 }
        await settle()
        XCTAssertTrue(recorder.peers.isEmpty, "离页后不再收对方位置")
        XCTAssertTrue(coordinator.registeredActiveOrderIDsForTesting.contains(orderID), "pause 不注销活跃订单")
        track.end()
    }

    // MARK: - 首页念不念

    func testHomeSpeaksWhenNoOrderPageFollowsTheOrder() async {
        let (_, tracker) = makePair()
        let result = await tracker.pageAnnouncement(for: update(), role: .volunteer)
        XCTAssertEqual(result, .homeShouldSpeak)
    }

    func testHomeStaysQuietWhenThePageSpoke() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .volunteer, polling: .volunteer, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        track.follow(orderID: orderID)
        let statusUpdate = update()

        async let decision = tracker.pageAnnouncement(for: statusUpdate, role: .volunteer)
        await Task.yield()
        track.acknowledge(statusUpdate, spoke: true)

        let result = await decision
        XCTAssertEqual(result, .pageSpoke)
        track.end()
    }

    func testHomeSpeaksWhenThePageAcknowledgedWithoutSpeakingEvenBeforeHomeAsked() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        track.follow(orderID: orderID)
        let statusUpdate = update()
        track.acknowledge(statusUpdate, spoke: false)

        let result = await tracker.pageAnnouncement(for: statusUpdate, role: .blind)
        XCTAssertEqual(result, .homeShouldSpeak)
        track.end()
    }

    func testHomeSpeaksAfterTheTimeoutWhenThePageNeverAnswers() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60, announcementTimeout: 0.05)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        track.follow(orderID: orderID)

        let result = await tracker.pageAnnouncement(for: update(), role: .blind)
        XCTAssertEqual(result, .homeShouldSpeak)
        track.end()
    }

    func testReleasedOrderPageCountsAsNoPage() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        var track: OrderLiveTrack? = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        track?.follow(orderID: orderID)
        XCTAssertEqual(tracker.liveTrackCountForTesting, 1)

        track = nil
        await settle()

        XCTAssertEqual(tracker.liveTrackCountForTesting, 0, "页面 ViewModel 释放后 tracker 不再认它")
        let result = await tracker.pageAnnouncement(for: update(), role: .blind)
        XCTAssertEqual(result, .homeShouldSpeak)
    }

    // MARK: - 陪跑员端附带推送

    func testSeparationAlertOnlyReachesVolunteerTracksForTheSameOrder() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let volunteer = openTrack(tracker, role: .volunteer, polling: .volunteer, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let blind = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let volunteerEvents = OrderTrackerEventRecorder(volunteer)
        let blindEvents = OrderTrackerEventRecorder(blind)
        volunteer.follow(orderID: orderID)
        blind.follow(orderID: orderID)

        tracker.receiveSeparationAlert(alert(orderID: orderID, type: "ESCORT_DISTANCE_ALERT"))
        tracker.receiveSeparationAlert(alert(orderID: 7, type: "ESCORT_DISTANCE_ALERT"))
        tracker.receiveSeparationAlert(alert(orderID: orderID, type: "ESCORT_SIGNAL_LOST"))

        await waitUntil { volunteerEvents.separationCount == 1 }
        await settle()
        XCTAssertEqual(volunteerEvents.separationCount, 1)
        XCTAssertEqual(blindEvents.separationCount, 0)
        volunteer.end()
        blind.end()
    }
}
