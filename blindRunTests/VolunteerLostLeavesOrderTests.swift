import Combine
import XCTest
@testable import blindRun

/// 陪跑员出发后失联、单被系统转走（`ORDER_VOLUNTEER_LOST`，后端 #616 M6 / #683 第 3 问，iOS #456）。
///
/// 后端 `OrderLifecycleService.handleVolunteerLost` 的发送顺序：先给原陪跑员一条 `ORDER_VOLUNTEER_LOST`
/// （模板通知，**不带 `orderId`**），再推 `ORDER_STATUS_CHANGED`（→`REMATCHING`）。
/// 修之前：后一条让订单页同档念「订单已取消，这一单不在你名下了。」，把横幅正在念的后端 `ttsText`
/// 从半句切断，然后停在「正在获取订单状态...」转圈，不会自己离开。
@MainActor
final class VolunteerLostLeavesOrderTests: XCTestCase {

    /// 后端 `data.sql` 里陪跑员那一行模板的 `tts_text`。
    private static let volunteerTTS = "已经过了约定的开跑时间，陪跑一直没能开始，系统已经把这一单转给其他志愿者。如果你仍然有空，可以在应用里接新的单。"

    // MARK: - 判据

    /// 后端看门狗只在「已出发 / 已到达」动手。`IN_PROGRESS` 刻意不算：跑步页被一条认错单的事件踢走代价太大。
    func testOnlyDepartedAndArrivedOrdersAreTakenAway() {
        let taken = (RunOrderStatus.allCases + [.unknown]).filter(\.isTakenAwayWhenVolunteerLost)
        XCTAssertEqual(Set(taken), [.driverEnRoute, .driverArrived])
    }

    // MARK: - 收到事件 → 离开，只念横幅那一句

    func testVolunteerLostLeavesThePageAndTheHomeAndOnlyTheBannerSpeaks() async throws {
        for status in [RunOrderStatus.driverEnRoute, .driverArrived] {
            let fixture = makeFixture(status: status)
            let coordinator = fixture.appState.realtimeCoordinator

            coordinator.simulateIncomingEventForTesting(.notification(Self.notification("ORDER_VOLUNTEER_LOST")))
            // 照 `ContentView` 的做法念横幅；之后任何一句同档播报都会出现在历史里。
            let banner = try XCTUnwrap(coordinator.currentNotification, "\(status)")
            fixture.speech.speak(banner.speechText)
            pushStatus(coordinator, orderId: fixture.orderId, from: status, to: .rematching)
            try await Task.sleep(nanoseconds: 300_000_000)

            XCTAssertTrue(fixture.page.didLoseOrder, "\(status)：订单页没有离开")
            XCTAssertNil(fixture.page.order, "\(status)")
            XCTAssertNil(fixture.home.activeOrder, "\(status)：首页的当前订单还在")
            XCTAssertEqual(
                fixture.speech.spokenHistoryForTesting, [Self.volunteerTTS],
                "\(status)：横幅那一句之后又念了别的（同档会把它切断）"
            )
        }
    }

    /// 断线期间被转走：回到信号范围后靠 `/api/notifications/since` 补读到这条，同样离开。
    /// 补读那条日志的 `orderId` 也是 null（后端 `logNotification(null, ...)`）。
    func testCatchUpOfTheEventLeavesTheOrderToo() async throws {
        let fixture = makeFixture(status: .driverArrived)

        fixture.appState.realtimeCoordinator.ingestCatchUp([
            MissedNotificationResponse(
                id: 45_601,
                eventType: "ORDER_VOLUNTEER_LOST",
                body: "陪跑一直没能开始，这一单已转给其他志愿者",
                ttsText: Self.volunteerTTS,
                priority: "HIGH",
                sentAt: "2026-10-19T10:00:00",
                orderId: nil
            )
        ])
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(fixture.page.didLoseOrder)
        XCTAssertNil(fixture.home.activeOrder)
        XCTAssertEqual(fixture.appState.realtimeCoordinator.currentNotification?.speechText, Self.volunteerTTS)
    }

    /// 跑步中收到（不该发生，或是认错单的旧事件）：不动。
    func testRunningOrderIsNotLeftOnTheEvent() async throws {
        let fixture = makeFixture(status: .inProgress)

        fixture.appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .notification(Self.notification("ORDER_VOLUNTEER_LOST"))
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(fixture.page.didLoseOrder)
        XCTAssertEqual(fixture.page.order?.status, .inProgress)
        XCTAssertNotNil(fixture.home.activeOrder)
    }

    /// 跑者也收到同名事件（文案不同）。那一端没有陪跑员订单页，通道不发。
    func testTheChannelOnlyFiresOnTheVolunteerSide() async {
        for (role, expected) in [(WSRole.blind, 0), (.volunteer, 1)] {
            let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
            let service = WebSocketService()
            coordinator.attach(to: service, role: role)
            var fired = 0
            let cancellable = coordinator.volunteerLostPublisher.sink { fired += 1 }

            service.simulateIncomingEventForTesting(.notification(Self.notification("ORDER_VOLUNTEER_LOST")))
            await Task.yield()

            XCTAssertEqual(fired, expected, "\(role)")
            cancellable.cancel()
        }
    }

    /// 离开之后页面上的按钮不再对这一单发请求（拨号入口在视图里随订单一起消失）。
    func testActionsAfterLeavingSendNothing() async throws {
        let fixture = makeFixture(status: .driverEnRoute)
        fixture.appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .notification(Self.notification("ORDER_VOLUNTEER_LOST"))
        )
        try await Task.sleep(nanoseconds: 300_000_000)
        fixture.speech.resetSpokenHistoryForTesting()

        await fixture.page.arrive()
        await fixture.page.sendQuickMessage(.almostThere)

        XCTAssertEqual(fixture.service.callCount("arrived(orderId:)"), 0)
        XCTAssertEqual(fixture.service.callCount("sendQuickMessage(_:orderId:)"), 0)
        XCTAssertTrue(fixture.speech.spokenHistoryForTesting.isEmpty, "\(fixture.speech.spokenHistoryForTesting)")
    }

    // MARK: - REMATCHING 且本人已不是参与者 → 离开

    /// 失联事件没送到、只来了状态推送：仍然离开，不停在兜底页的转圈上。
    func testRematchingPushWithoutOwnCancelLeavesThePage() async throws {
        let fixture = makeFixture(status: .driverEnRoute)

        pushStatus(fixture.appState.realtimeCoordinator, orderId: fixture.orderId, from: .driverEnRoute, to: .rematching)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(fixture.page.order)
        XCTAssertTrue(fixture.page.didLoseOrder, "推送来的 REMATCHING 没有取消面板的回调来关页")
    }

    /// 自己按的取消：关页由取消面板的回调做，不另置 `didLoseOrder`（两处同时 dismiss 会抢）。
    func testOwnCancelDoesNotCountAsLosingTheOrder() async {
        let fixture = makeFixture(status: .driverEnRoute)
        fixture.service.cancelResult = .success(CancelOrderResponse(success: true, countedAsLateCancel: false))
        fixture.service.orderDetailResult = .success(.preview(orderId: fixture.orderId, status: .rematching))

        await fixture.page.cancel()
        await waitUntil { fixture.page.didCancelOrder }

        XCTAssertTrue(fixture.page.didCancelOrder)
        XCTAssertFalse(fixture.page.didLoseOrder)
    }

    // MARK: - 其他安全事件不误触发

    /// 后端点名：它不是 `ORDER_DEPARTURE_STALLED` / `REMATCHING_MID_RUN` 的同义词。
    /// 这几条都不带「这一单已经不是你的了」的含义，或根本不是发给陪跑员的。
    func testOtherSafetyEventsDoNotLeaveTheOrder() async throws {
        for eventType in [
            "ORDER_ARRIVAL_STALLED", "ORDER_DEPARTURE_STALLED", "REMATCHING_MID_RUN", "SCHEDULED_DEPARTURE_GATE_MISSED",
        ] {
            let fixture = makeFixture(status: .driverArrived)

            fixture.appState.realtimeCoordinator.simulateIncomingEventForTesting(
                .notification(Self.notification(eventType))
            )
            try await Task.sleep(nanoseconds: 200_000_000)

            XCTAssertFalse(fixture.page.didLoseOrder, eventType)
            XCTAssertEqual(fixture.page.order?.status, .driverArrived, eventType)
            XCTAssertNotNil(fixture.home.activeOrder, eventType)
        }
    }

    // MARK: - Fixture

    private struct Fixture {
        let appState: AppState
        let service: FakeOrderService
        let speech: SpeechService
        let page: VolunteerInServiceViewModel
        let home: VolunteerHomeViewModel
        let orderId: Int64
    }

    /// view model 对 `AppState` 是 `weak` 引用：测试必须自己持有它
    /// （记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private var retained: [AppState] = []

    private func makeFixture(status: RunOrderStatus) -> Fixture {
        let orderId: Int64 = 4_560
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
        let page = VolunteerInServiceViewModel()
        page.configure(with: appState, speechService: speech, initialOrder: order)
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
                message: "陪跑一直没能开始，正在重新匹配",
                ttsText: "已经过了约定的开跑时间，陪跑一直没能开始，系统正在重新匹配志愿者",
                priority: "NORMAL",
                timestamp: "2026-10-19T10:00:00"
            ))
        )
    }

    /// 信封与后端 `sendNotification(..., null)` 一致：**没有 `orderId`**。
    private static func notification(_ eventType: String) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "456-\(eventType)",
            eventType: eventType,
            title: nil,
            body: eventType == "ORDER_VOLUNTEER_LOST" ? "陪跑一直没能开始，这一单已转给其他志愿者" : "安全提醒正文",
            ttsText: eventType == "ORDER_VOLUNTEER_LOST" ? volunteerTTS : "安全提醒正文",
            priority: "HIGH",
            timestamp: "2026-10-19T10:00:00"
        )
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
