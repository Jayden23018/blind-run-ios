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
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator, peerFreshness: 0.6)
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
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator, peerFreshness: 1.0)
        let recorder = OrderTrackerEventRecorder(track)
        track.follow(orderID: orderID)
        await settle()
        recorder.reset()

        // 第一条离过期剩约 0.4 秒，第二条还有约 1 秒。留出的余量远大于调度抖动。
        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 0.6, timestampOffset: 0)))
        await waitUntil { recorder.peers.count == 1 }
        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 0, timestampOffset: 1)))
        await waitUntil { recorder.peers.count == 2 }

        // 睡过第一条原本的到期点（约 0.4 秒），但不到第二条的（约 1 秒）。
        try? await Task.sleep(nanoseconds: 600_000_000)
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
        // 确认首页真的挂起在等，再回话：只查已有记录的实现在这里会拿不到 `.pageSpoke`。
        await waitUntil { track.pendingAcknowledgementWaiterCountForTesting == 1 }
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

        let startedAt = Date()
        let result = await tracker.pageAnnouncement(for: update(), role: .blind)
        XCTAssertEqual(result, .homeShouldSpeak)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 0.04, "超时之前不许先放首页念")
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

    func testBlindTrackReplaysTheStoredVolunteerSampleOnFollow() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        coordinator.registerActiveOrder(orderID)
        coordinator.ingestFallbackPeerLocation(sample(ageSeconds: 1, owner: .volunteer))
        let blind = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let volunteer = openTrack(tracker, role: .volunteer, polling: .volunteer, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let blindEvents = OrderTrackerEventRecorder(blind)
        let volunteerEvents = OrderTrackerEventRecorder(volunteer)

        blind.follow(orderID: orderID)
        volunteer.follow(orderID: orderID)

        await waitUntil { blindEvents.peers.count == 1 }
        await settle()
        XCTAssertTrue(volunteerEvents.peers.isEmpty, "陪跑员页照现状不回放")
        blind.end()
        volunteer.end()
    }

    func testPauseAndEndBothClearThePeerMarker() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let recorder = OrderTrackerEventRecorder(track)
        track.follow(orderID: orderID)
        await settle()
        recorder.reset()

        track.pause()
        await waitUntil { recorder.expiredCount == 1 }
        track.follow(orderID: orderID)
        await settle()
        recorder.reset()
        track.end()
        await waitUntil { recorder.expiredCount == 1 }
    }

    func testVolunteerOnlyEventsReachVolunteerTracksAndLiveUpdatesAreFilteredByOrder() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let volunteer = openTrack(tracker, role: .volunteer, polling: .volunteer, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let blind = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let volunteerEvents = OrderTrackerEventRecorder(volunteer)
        let blindEvents = OrderTrackerEventRecorder(blind)
        volunteer.follow(orderID: orderID)
        blind.follow(orderID: orderID)

        tracker.receiveBlindStartConfirmed()
        tracker.receiveVolunteerLost()
        tracker.receiveLiveUpdate(.eta(orderId: orderID, EtaView(remainingMinutes: 5)))
        tracker.receiveLiveUpdate(.eta(orderId: 7, EtaView(remainingMinutes: 5)))

        await waitUntil { volunteerEvents.liveUpdateCount == 1 && volunteerEvents.volunteerLostCount == 1 }
        await settle()
        XCTAssertEqual(volunteerEvents.startConfirmedCount, 1)
        XCTAssertEqual(volunteerEvents.liveUpdateCount, 1, "别的单的 ETA 不进来")
        XCTAssertEqual(blindEvents.startConfirmedCount + blindEvents.volunteerLostCount + blindEvents.liveUpdateCount, 0)
        volunteer.end()
        blind.end()
    }

    func testSixteenSecondOldSampleThroughTheCoordinatorNeverReachesTheTrack() async {
        let (coordinator, tracker) = makePair(pollingInterval: 60)
        let track = openTrack(tracker, role: .blind, loads: OrderTrackerLoadCounter(), coordinator: coordinator)
        let recorder = OrderTrackerEventRecorder(track)
        track.follow(orderID: orderID)
        await settle()

        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 16)))
        coordinator.simulateIncomingEventForTesting(.volunteerLocation(volunteerLocation(ageSeconds: 14, timestampOffset: 1)))

        await waitUntil { recorder.peers.count == 1 }
        await settle()
        XCTAssertEqual(recorder.peers.count, 1, "只有 14 秒那条进来")
        track.end()
    }
}
