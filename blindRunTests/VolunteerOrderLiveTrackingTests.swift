import Combine
import XCTest
@testable import blindRun

/// 陪跑员订单页迁到订单跟踪（OpenSpec `unify-order-live-tracking` 第 3 批，#888）。
///
/// 首页与订单页同时开着、都收到同一条状态推送。订单页处理完回话（`OrderLiveTrack.acknowledge`），
/// 首页念之前问 `pageAnnouncement`，据此决定念不念（design §6）。只断言播报内容分不出「回了 true」和
/// 「回了 false 但被去重键挡掉」，所以几条用例另外直接问一次 `pageAnnouncement`。
@MainActor
final class VolunteerOrderLiveTrackingTests: XCTestCase {
    private let orderID: Int64 = 8_880
    /// view model 对 `AppState` 是 `weak` 引用：测试必须自己持有它
    /// （记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private var retained: [AppState] = []
    private var subscriptions: [AnyCancellable] = []

    // MARK: - 状态句只念一句

    /// 跑者取消：只念「…不算你的取消…」那一整句，首页的通用句「这一单已取消。」不念。
    func testRunnerCancelSpeaksOnlyTheNotYourCancelSentence() async throws {
        let fixture = makeFixture(status: .pendingAccept)
        let updates = recordStatusUpdates(fixture)

        pushStatus(fixture, from: .pendingAccept, to: .cancelled)
        try await Task.sleep(nanoseconds: 300_000_000)

        let spoken = fixture.speech.spokenHistoryForTesting
        XCTAssertNil(fixture.home.activeOrder, "前提：首页也收到了推送")
        XCTAssertEqual(spoken.count, 1, "\(spoken)")
        XCTAssertTrue(spoken.first?.contains("不算你的取消") == true, "\(spoken)")
        XCTAssertFalse(spoken.contains(RunOrderStatus.cancelled.volunteerAnnouncement), "首页又念了通用句：\(spoken)")
        XCTAssertEqual(fixture.page.order?.status, .cancelled, "「跑者已取消」那一屏要留着订单")
        let answer = await pageAnnouncement(fixture, updates)
        XCTAssertEqual(answer, .pageSpoke, "订单页念了整句却没回 spoke: true")
    }

    /// 自己取消（推送 `REMATCHING`）：只念「订单已取消。」一句，不念「系统正在重新匹配」。
    func testOwnCancelSpeaksOneSentenceAndTellsTheHomeItSpoke() async throws {
        let fixture = makeFixture(status: .driverEnRoute)
        await settleInitialPoll(fixture)
        fixture.service.cancelResult = .success(CancelOrderResponse(success: true, countedAsLateCancel: false))
        // 取消后已不是参与者：确认拉取被后端 403，订单页只能靠推送知道。
        fixture.service.orderDetailResult = .failure(Self.notParticipant)
        await fixture.page.cancel()
        fixture.speech.resetSpokenHistoryForTesting()
        let updates = recordStatusUpdates(fixture)

        pushStatus(fixture, from: .driverEnRoute, to: .rematching)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(fixture.speech.spokenHistoryForTesting, [VolunteerCancelAnnouncement.cancelledByVolunteer])
        XCTAssertTrue(fixture.page.didCancelOrder)
        XCTAssertFalse(fixture.page.didLoseOrder)
        let answer = await pageAnnouncement(fixture, updates)
        XCTAssertEqual(answer, .pageSpoke)
    }

    /// 失联事件后紧跟 `REMATCHING`：订单页已放下这一单、丢弃推送（回 `spoke: false`），
    /// 首页也已清掉当前订单 —— 两边都不念，「订单已取消」不出现，横幅不被切断。
    func testVolunteerLostThenRematchingDoesNotSayCancelled() async throws {
        let fixture = makeFixture(status: .driverEnRoute)
        let updates = recordStatusUpdates(fixture)

        fixture.appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .notification(Self.notification(eventType: "ORDER_VOLUNTEER_LOST", messageID: "888-lost"))
        )
        pushStatus(fixture, from: .driverEnRoute, to: .rematching)
        try await Task.sleep(nanoseconds: 300_000_000)

        let spoken = fixture.speech.spokenHistoryForTesting
        XCTAssertFalse(spoken.contains { $0.contains("订单已取消") }, "\(spoken)")
        XCTAssertTrue(spoken.isEmpty, "横幅之外又念了别的：\(spoken)")
        XCTAssertTrue(fixture.page.didLoseOrder)
        XCTAssertFalse(fixture.page.didCancelOrder, "失联不是自己取消")
        XCTAssertNil(fixture.home.activeOrder)
        let answer = await pageAnnouncement(fixture, updates)
        XCTAssertEqual(answer, .homeShouldSpeak, "订单页丢弃的推送不能回 spoke: true")
    }

    // MARK: - 只改提示、不改状态

    /// 走散告警：只点亮提示条（`separationAlertAt`），订单状态、求助与流转一概不动。
    func testSeparationAlertOnlyRaisesTheBannerAndLeavesTheOrderAlone() async throws {
        let fixture = makeFixture(status: .inProgress)
        await settleInitialPoll(fixture)
        XCTAssertNil(fixture.page.separationAlertAt, "前提：进页时没有提示条")

        fixture.appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .notification(Self.notification(eventType: "ESCORT_DISTANCE_ALERT", messageID: UUID().uuidString))
        )
        let raised = await waitUntil { fixture.page.separationAlertAt != nil }

        XCTAssertTrue(raised, "本单的走散告警没点亮提示条")
        XCTAssertEqual(fixture.page.order?.status, .inProgress)
        XCTAssertFalse(fixture.page.didLoseOrder)
        XCTAssertFalse(fixture.page.didCancelOrder)
        XCTAssertEqual(fixture.page.transitionState, .idle)
        XCTAssertEqual(fixture.page.supportRequestState, .idle)
        XCTAssertFalse(fixture.page.isAcknowledgingEmergency)
    }

    /// `BLIND_START_CONFIRMED` 没有 `orderId`：只在汇合态清「等待对方确认」；别的状态下一律不动、也不重拉。
    func testBlindStartConfirmedClearsTheWaitOnlyAtTheMeetingPoint() async throws {
        let arrived = makeFixture(status: .driverArrived)
        await settleInitialPoll(arrived)
        arrived.page.awaitingBlindConfirmation = true

        arrived.appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .notification(Self.notification(eventType: "BLIND_START_CONFIRMED", messageID: "888-start-1"))
        )
        let cleared = await waitUntil { !arrived.page.awaitingBlindConfirmation }
        XCTAssertTrue(cleared, "汇合态没清「等待对方确认」")

        var enRouteOrder = OrderDetailResponse.preview(orderId: orderID, status: .driverEnRoute)
        enRouteOrder.blindConfirmDeadlineAt = "2026-11-08T10:00:00"
        let enRoute = makeFixture(status: .driverEnRoute, order: enRouteOrder)
        await settleInitialPoll(enRoute)
        let detailCalls = enRoute.service.callCount("orderDetail(orderId:)")

        enRoute.appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .notification(Self.notification(eventType: "BLIND_START_CONFIRMED", messageID: "888-start-2"))
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(enRoute.page.order?.blindConfirmDeadlineAt, "2026-11-08T10:00:00", "出发中被当成汇合态处理了")
        XCTAssertEqual(enRoute.service.callCount("orderDetail(orderId:)"), detailCalls, "出发中不该为它重拉")
    }
}

// MARK: - Fixture

@MainActor
extension VolunteerOrderLiveTrackingTests {
    private struct Fixture {
        let appState: AppState
        let service: FakeOrderService
        let speech: SpeechService
        let page: VolunteerInServiceViewModel
        let home: VolunteerHomeViewModel
    }

    /// 首页与订单页都开着，订单页照生产在同一个 `.task` 里 `configure` + `startPolling`。
    private func makeFixture(status: RunOrderStatus, order: OrderDetailResponse? = nil) -> Fixture {
        let order = order ?? .preview(orderId: orderID, status: status)
        let service = FakeOrderService()
        service.orderDetailResult = .success(order)
        let appState = AppState(orders: service)
        appState.currentEnvironment = .mock
        retained.append(appState)
        let speech = SpeechService()
        let home = VolunteerHomeViewModel()
        home.configure(with: appState, speechService: speech)
        home.activeOrder = order
        let page = VolunteerInServiceViewModel()
        page.configure(with: appState, speechService: speech, initialOrder: order)
        page.startPolling(orderId: orderID)
        // 带状态登记：协调器只把推送发给登记过的订单，走散告警还要认出唯一一张跑步中的单。
        appState.realtimeCoordinator.registerActiveOrder(orderID, status: status)
        speech.resetSpokenHistoryForTesting()
        return Fixture(appState: appState, service: service, speech: speech, page: page, home: home)
    }

    /// 等进页轮询那一次拉完，免得它和下面的动作交错。
    private func settleInitialPoll(_ fixture: Fixture) async {
        _ = await waitUntil { fixture.service.callCount("orderDetail(orderId:)") >= 1 }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    /// 协调器发出的那一条更新（含 `receivedAt`）只能从发布点拿到：`pageAnnouncement` 按整条比对。
    private func recordStatusUpdates(_ fixture: Fixture) -> () -> [RealtimeOrderStatusUpdate] {
        let box = UpdateBox()
        fixture.appState.realtimeCoordinator.statusUpdatePublisher
            .sink { box.values.append($0) }
            .store(in: &subscriptions)
        return { box.values }
    }

    private func pageAnnouncement(
        _ fixture: Fixture,
        _ updates: () -> [RealtimeOrderStatusUpdate]
    ) async -> PageAnnouncement? {
        guard let update = updates().last else {
            XCTFail("前提：协调器没发出状态更新")
            return nil
        }
        return await fixture.appState.realtimeCoordinator.orderLiveTracker.pageAnnouncement(for: update, role: .volunteer)
    }

    private func pushStatus(_ fixture: Fixture, from: RunOrderStatus, to: RunOrderStatus) {
        fixture.appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: orderID,
                fromStatus: from.rawValue,
                toStatus: to.rawValue,
                message: nil,
                ttsText: nil,
                priority: "NORMAL",
                timestamp: "2026-11-08T12:00:00"
            ))
        )
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// 后端 `OrderQueryService.getOrder` 对非参与者抛的那一条。
    private static let notParticipant = APIError.serverError(
        ErrorResponse(code: "ORDER_PERMISSION_DENIED", message: "您无权查看此订单")
    )

    /// 信封与后端 `sendNotification(..., null)` 一致：**没有 `orderId`**。走散告警要 HIGH + UUID 的 `messageId`。
    private static func notification(eventType: String, messageID: String) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: messageID,
            eventType: eventType,
            title: nil,
            body: "推送正文",
            ttsText: "推送正文",
            priority: "HIGH",
            timestamp: "2026-11-08T12:00:00"
        )
    }
}

@MainActor
private final class UpdateBox {
    var values: [RealtimeOrderStatusUpdate] = []
}
