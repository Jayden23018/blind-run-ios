import XCTest
@testable import blindRun

/// 订单进 `REMATCHING` 但不是陪跑员自己按的取消（系统转走，#477）。
///
/// 后端两条路径（`OrderLifecycleService`，blind-run-backend origin/main）：
/// - `handleDepartureGateMissed`：跨天预约闸门到点未确认。**先**给陪跑员发 HIGH 横幅
///   `SCHEDULED_DEPARTURE_GATE_MISSED`，**再**推 `ORDER_STATUS_CHANGED`（→`REMATCHING`）。
/// - `handleStalledDeparture`：接单后迟迟不出发。**不给陪跑员发横幅**，只有状态推送。
///
/// 修之前：两条路径都念「订单已取消，这一单不在你名下了。」—— 订单其实没取消；
/// 且与横幅同档，闸门到点时把正在念的横幅从半句切断（记忆 `later-speak-silently-cuts-the-earlier-one`）。
@MainActor
final class VolunteerRematchingAnnouncementTests: XCTestCase {

    /// 后端陪跑员那条 `SCHEDULED_DEPARTURE_GATE_MISSED` 的意思（issue #477 原文）。
    private static let gateMissedTTS = "你没有确认出发，这一单已转给其他志愿者"

    // MARK: - 系统转走

    /// 闸门到点：横幅先念，状态句排在它后面，不切断它；也不说「已取消」。
    func testGateMissedRematchingQueuesBehindTheBannerInsteadOfCuttingIt() async throws {
        let fixture = makeFixture(status: .scheduledConfirmed, opensOrderPage: true)
        let coordinator = fixture.appState.realtimeCoordinator

        coordinator.simulateIncomingEventForTesting(.notification(Self.gateMissedNotification))
        let banner = try XCTUnwrap(coordinator.currentNotification)
        // 照 `ContentView` 的做法念横幅（默认档）。
        fixture.speech.speak(banner.speechText)
        pushStatus(coordinator, orderId: fixture.orderId, from: .scheduledConfirmed, to: .rematching)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(
            fixture.speech.spokenHistoryForTesting, [banner.speechText],
            "横幅之后立刻又念了别的（同档会把它切断）"
        )
        XCTAssertEqual(
            fixture.speech.pendingTextsForTesting, [VolunteerCancelAnnouncement.reassignedBySystem],
            "状态句没排在横幅后面（首页与订单页应只排一句）"
        )
        XCTAssertTrue(try XCTUnwrap(fixture.page).didLoseOrder, "订单页没有离开")
    }

    /// 迟迟不出发：没有横幅，这一句是唯一的告知 —— 照常立刻念，只念一次，不说「已取消」。
    func testStalledDepartureRematchingTellsTheVolunteerOnce() async throws {
        let fixture = makeFixture(status: .pendingAccept, opensOrderPage: true)

        pushStatus(fixture.appState.realtimeCoordinator, orderId: fixture.orderId, from: .pendingAccept, to: .rematching)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(fixture.speech.spokenHistoryForTesting, [VolunteerCancelAnnouncement.reassignedBySystem])
        XCTAssertTrue(try XCTUnwrap(fixture.page).didLoseOrder)
    }

    /// 订单页没开、陪跑员在首页：首页那条状态订阅同样念新句，不念「订单已取消」。
    func testHomeAloneSaysTheOrderIsBeingRematched() async throws {
        let fixture = makeFixture(status: .scheduledConfirmed, opensOrderPage: false)

        pushStatus(fixture.appState.realtimeCoordinator, orderId: fixture.orderId, from: .scheduledConfirmed, to: .rematching)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(fixture.speech.spokenHistoryForTesting, [VolunteerCancelAnnouncement.reassignedBySystem])
        XCTAssertNil(fixture.home.activeOrder)
    }

    // MARK: - 自己按的取消不变

    /// 订单页上自己取消、推送随后到达：首页与订单页都订阅了这条推送，只念「订单已取消」一次，
    /// 不先念首页那句「系统正在重新匹配」再被切断（首页推迟一拍，让订单页先念、记去重键）。
    func testOwnCancelStillSaysCancelledOnceWithTheHomeListening() async throws {
        let fixture = makeFixture(status: .driverEnRoute, opensOrderPage: true)
        let page = try XCTUnwrap(fixture.page)
        fixture.service.cancelResult = .success(CancelOrderResponse(success: true, countedAsLateCancel: false))
        // 取消后已不是参与者：确认拉取被后端 403，订单页只能靠推送知道。
        fixture.service.orderDetailResult = .failure(APIError.serverError(
            ErrorResponse(code: "ORDER_PERMISSION_DENIED", message: "您无权查看此订单")
        ))

        await page.cancel()
        fixture.speech.resetSpokenHistoryForTesting()
        pushStatus(fixture.appState.realtimeCoordinator, orderId: fixture.orderId, from: .driverEnRoute, to: .rematching)
        try await Task.sleep(nanoseconds: 300_000_000)

        let spoken = fixture.speech.spokenHistoryForTesting
        XCTAssertEqual(spoken.filter { $0.contains("订单已取消") }, [VolunteerCancelAnnouncement.cancelledByVolunteer], "\(spoken)")
        XCTAssertFalse(spoken.contains(VolunteerCancelAnnouncement.reassignedBySystem), "\(spoken)")
        XCTAssertFalse(fixture.speech.pendingTextsForTesting.contains(VolunteerCancelAnnouncement.reassignedBySystem))
        XCTAssertTrue(page.didCancelOrder)
    }

    /// 档位只给 `REMATCHING` 降一档：其余状态句照旧默认档。
    func testOnlyRematchingIsAnnouncedOneTierLower() {
        for status in RunOrderStatus.allCases + [.unknown] {
            XCTAssertEqual(
                status.volunteerAnnouncementPriority,
                status == .rematching ? .onDemand : .counterpartAction,
                "\(status)"
            )
        }
    }

    // MARK: - Fixture

    private struct Fixture {
        let appState: AppState
        let service: FakeOrderService
        let speech: SpeechService
        let page: VolunteerInServiceViewModel?
        let home: VolunteerHomeViewModel
        let orderId: Int64
    }

    /// view model 对 `AppState` 是 `weak` 引用：测试必须自己持有它
    /// （记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private var retained: [AppState] = []

    private func makeFixture(status: RunOrderStatus, opensOrderPage: Bool) -> Fixture {
        let orderId: Int64 = 4_770
        let order = OrderDetailResponse.preview(orderId: orderId, status: status)
        let service = FakeOrderService()
        service.orderDetailResult = .success(order)
        let appState = AppState(orders: service)
        appState.currentEnvironment = .mock
        retained.append(appState)
        let speech = SpeechService()
        let home = VolunteerHomeViewModel()
        home.configure(with: appState, speechService: speech)
        home.activeOrder = order
        var page: VolunteerInServiceViewModel?
        if opensOrderPage {
            let viewModel = VolunteerInServiceViewModel()
            viewModel.configure(with: appState, speechService: speech, initialOrder: order)
            page = viewModel
        }
        // 生产上首页加载 / 订单页轮询时登记；协调器只把状态推送发给登记过的订单。
        appState.realtimeCoordinator.registerActiveOrder(orderId, status: status)
        speech.resetSpokenHistoryForTesting()
        return Fixture(appState: appState, service: service, speech: speech, page: page, home: home, orderId: orderId)
    }

    private func pushStatus(_ coordinator: AppRealtimeCoordinator, orderId: Int64, from: RunOrderStatus, to: RunOrderStatus) {
        coordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: orderId,
                fromStatus: from.rawValue,
                toStatus: to.rawValue,
                message: "原志愿者未确认出发，正在重新匹配",
                ttsText: "原来的志愿者没有确认出发，系统正在为您重新匹配志愿者",
                priority: "NORMAL",
                timestamp: "2026-10-22T10:00:00"
            ))
        )
    }

    /// 后端用模板通知发它（`sendNotification(..., null)`），信封没有 `orderId`。
    private static let gateMissedNotification = WSAppNotification(
        type: WSMessageType.appNotification.rawValue,
        eventId: nil,
        messageId: "477-gate-missed",
        eventType: "SCHEDULED_DEPARTURE_GATE_MISSED",
        title: nil,
        body: gateMissedTTS,
        ttsText: gateMissedTTS,
        priority: "HIGH",
        timestamp: "2026-10-22T10:00:00"
    )
}
