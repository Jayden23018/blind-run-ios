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

    /// 「已到达」的请求在路上时这一单被转走：结果回来时不念（失败那句会切断横幅），成功也不起确认拉取。
    func testAnInFlightActionThatReturnsAfterLeavingIsDiscarded() async throws {
        let outcomes: [Result<Void, Error>] = [
            .failure(APIError.serverError(ErrorResponse(code: "NOT_ORDER_PARTICIPANT", message: "后端原文"))),
            .success(()),
        ]
        for outcome in outcomes {
            let fixture = makeFixture(status: .driverEnRoute)
            fixture.service.arrivedResult = outcome
            fixture.service.arrivedDelayNanoseconds = 400_000_000

            let action = Task { await fixture.page.arrive() }
            try await Task.sleep(nanoseconds: 100_000_000)
            fixture.appState.realtimeCoordinator.simulateIncomingEventForTesting(
                .notification(Self.notification("ORDER_VOLUNTEER_LOST"))
            )
            await action.value
            try await Task.sleep(nanoseconds: 200_000_000)

            XCTAssertEqual(fixture.service.callCount("arrived(orderId:)"), 1, "前提：请求确实发出去了")
            XCTAssertTrue(fixture.page.didLoseOrder)
            XCTAssertTrue(fixture.speech.spokenHistoryForTesting.isEmpty, "\(outcome)：\(fixture.speech.spokenHistoryForTesting)")
            XCTAssertEqual(fixture.service.callCount("orderDetail(orderId:)"), 0, "\(outcome)：离开后还在拉此订单的确认")
            XCTAssertEqual(fixture.page.transitionState, .idle, "\(outcome)")
        }
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

    /// `initialOrderLoaded: false` = 从推送冷启动、订单页还没拉到第一份详情（#476 ①）。
    /// `realtimeSocket`：要演断线重连时传入。必须在登记订单**之前**接上 —— `attach` 会清掉会话状态。
    private func makeFixture(
        status: RunOrderStatus,
        initialOrderLoaded: Bool = true,
        realtimeSocket: WebSocketService? = nil
    ) -> Fixture {
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
        page.configure(with: appState, speechService: speech, initialOrder: initialOrderLoaded ? order : nil)
        if let realtimeSocket {
            appState.realtimeCoordinator.attach(to: realtimeSocket, role: .volunteer)
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
                message: "陪跑一直没能开始，正在重新匹配",
                ttsText: "已经过了约定的开跑时间，陪跑一直没能开始，系统正在重新匹配志愿者",
                priority: "NORMAL",
                timestamp: "2026-10-19T10:00:00"
            ))
        )
    }

    /// 后端 `OrderQueryService.getOrder` 对非参与者抛的那一条。
    private static let notParticipant = APIError.serverError(
        ErrorResponse(code: "ORDER_PERMISSION_DENIED", message: "您无权查看此订单")
    )

    /// 补读那条日志同样没有 `orderId`。
    private static let missedVolunteerLost = MissedNotificationResponse(
        id: 45_601,
        eventType: "ORDER_VOLUNTEER_LOST",
        body: "陪跑一直没能开始，这一单已转给其他志愿者",
        ttsText: volunteerTTS,
        priority: "HIGH",
        sentAt: "2026-10-19T10:00:00",
        orderId: nil
    )

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

// MARK: - #476：补读的旧事件 / 详情还没拉到就被转走
// 放在扩展里：同文件的扩展能用上面的私有夹具，又不撑大类型体（SwiftLint 棘轮）。
@MainActor
extension VolunteerLostLeavesOrderTests {
    /// 补读回放的旧事件（#476 ②）：补读那条日志的 `orderId` 也是 null（后端 `logNotification(null, ...)`），
    /// 认不出说的是哪一单。陪跑员此刻手上可能是**另一单**的出发中 —— 不能凭它放下。
    /// 横幅照念；这一单还是不是他的，由重连后那次详情重拉说了算（下一条用例）。
    func testCatchUpOfTheEventDoesNotDropAnOrderItCannotIdentify() async throws {
        for status in [RunOrderStatus.driverEnRoute, .driverArrived] {
            let fixture = makeFixture(status: status)

            fixture.appState.realtimeCoordinator.ingestCatchUp([Self.missedVolunteerLost])
            try await Task.sleep(nanoseconds: 300_000_000)

            XCTAssertFalse(fixture.page.didLoseOrder, "\(status)：凭一条认不出订单的旧事件放下了手上此订单")
            XCTAssertEqual(fixture.page.order?.status, status, "\(status)")
            XCTAssertNotNil(fixture.home.activeOrder, "\(status)：首页的当前订单被清掉了")
            XCTAssertEqual(
                fixture.appState.realtimeCoordinator.currentNotification?.speechText, Self.volunteerTTS,
                "\(status)：横幅那一句没进队列"
            )
        }
    }

    /// 断线期间真被转走：重连后协调器对已登记订单发起重拉，详情回 403 `ORDER_PERMISSION_DENIED`
    /// （后端 `enterRematching` 把 `order.volunteer` 置空，`OrderQueryService.getOrder` 判非参与者）⇒ 静默离开。
    /// 走真实链路：断线 → 重连（协调器请求重拉）→ 订单页的重拉订阅发起 `load` → 403。
    func testCatchUpOfAGenuineLossLeavesOnTheRefreshThatFollows() async throws {
        let socket = WebSocketService()
        let fixture = makeFixture(status: .driverArrived, realtimeSocket: socket)
        socket.simulateConnectionStateForTesting(.connected)
        socket.simulateConnectionStateForTesting(.disconnected)
        await Task.yield()
        fixture.service.orderDetailResult = .failure(Self.notParticipant)

        socket.simulateConnectionStateForTesting(.connected)
        fixture.appState.realtimeCoordinator.ingestCatchUp([Self.missedVolunteerLost])
        await waitUntil { fixture.page.didLoseOrder }

        XCTAssertGreaterThanOrEqual(fixture.service.callCount("orderDetail(orderId:)"), 1, "前提：重连后确实重拉了详情")
        XCTAssertTrue(fixture.page.didLoseOrder)
        XCTAssertNil(fixture.page.order)
        XCTAssertNil(fixture.page.errorMessage)
        XCTAssertTrue(fixture.speech.spokenHistoryForTesting.isEmpty, "\(fixture.speech.spokenHistoryForTesting)")
    }

    // MARK: - 详情还没拉到就被转走（#476 ①）

    /// 从推送冷启动、`initialOrder` 为 nil：失联事件与 `REMATCHING` 推送都认不出这一单（手上还没有订单），
    /// 之后的轮询回 403。修之前这条 403 被吞掉，页面停在「获取订单状态失败」兜底页。
    func testPermissionDeniedBeforeTheFirstDetailLeavesThePage() async throws {
        let fixture = makeFixture(status: .driverEnRoute, initialOrderLoaded: false)
        fixture.service.orderDetailResult = .failure(Self.notParticipant)
        let coordinator = fixture.appState.realtimeCoordinator

        coordinator.simulateIncomingEventForTesting(.notification(Self.notification("ORDER_VOLUNTEER_LOST")))
        let banner = try XCTUnwrap(coordinator.currentNotification)
        fixture.speech.speak(banner.speechText)
        pushStatus(coordinator, orderId: fixture.orderId, from: .driverEnRoute, to: .rematching)
        await fixture.page.load(orderId: fixture.orderId, speakChanges: true)

        XCTAssertTrue(fixture.page.didLoseOrder, "403 被吞掉，页面停在兜底页")
        XCTAssertNil(fixture.page.errorMessage, "离开前还挂出了「获取订单状态失败」")
        XCTAssertEqual(
            fixture.speech.spokenHistoryForTesting, [Self.volunteerTTS],
            "横幅那一句之后又念了别的（同档会把它切断）"
        )
    }

    /// 详情已拉到、但失联事件与状态推送都没送到：轮询回 403 同样离开（不论手上停在哪一态）。
    func testPermissionDeniedOnAPollLeavesALoadedOrder() async {
        for status in [RunOrderStatus.driverEnRoute, .inProgress] {
            let fixture = makeFixture(status: status)
            fixture.service.orderDetailResult = .failure(Self.notParticipant)

            await fixture.page.load(orderId: fixture.orderId, speakChanges: true)

            XCTAssertTrue(fixture.page.didLoseOrder, "\(status)")
            XCTAssertNil(fixture.page.order, "\(status)")
            XCTAssertTrue(fixture.speech.spokenHistoryForTesting.isEmpty, "\(status)：\(fixture.speech.spokenHistoryForTesting)")
        }
    }

    /// 自己按的取消已被后端接下、`REMATCHING` 推送还没到时，轮询先回了 403：不另置 `didLoseOrder`。
    /// 关页由取消那条路做（推送 → `didCancelOrder`）；两条同时 dismiss 会多出栈一层。
    func testPermissionDeniedAfterOwnCancelDoesNotCountAsLosingTheOrder() async {
        let fixture = makeFixture(status: .driverEnRoute)
        fixture.service.cancelResult = .success(CancelOrderResponse(success: true, countedAsLateCancel: false))
        fixture.service.orderDetailResult = .failure(Self.notParticipant)
        await fixture.page.cancel()

        await fixture.page.load(orderId: fixture.orderId, speakChanges: true)

        XCTAssertEqual(fixture.service.callCount("cancel(orderId:)"), 1, "前提：取消请求确实发出去了")
        XCTAssertFalse(fixture.page.didLoseOrder)
    }

    /// 其他失败（断网等）不是「已不是参与者」：还没拉到详情时照旧落兜底页，不离开。
    func testOtherLoadFailuresDoNotLeaveThePage() async {
        let fixture = makeFixture(status: .driverEnRoute, initialOrderLoaded: false)
        fixture.service.orderDetailResult = .failure(APIError.networkError(URLError(.notConnectedToInternet)))

        await fixture.page.load(orderId: fixture.orderId, speakChanges: true)

        XCTAssertFalse(fixture.page.didLoseOrder)
        XCTAssertEqual(fixture.page.errorMessage, "获取订单状态失败")
    }
}
