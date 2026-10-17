import XCTest
@testable import blindRun

/// 跑者在汇合态满后端给的时刻后可以取消（后端 #682，iOS #395）。
///
/// 这一路坏掉的形态全是静默的：字段解不出 = 入口永远不出现，看起来像「后端关了这条出口」；
/// 判据写反 = 到点前可按、按下去只听到 409；陪跑员那条通知被吞 = 人在集合点一直等。
@MainActor
final class BlindArrivalCancelTests: XCTestCase {

    // MARK: - 解码

    private static let baseFields = """
    "orderId": 7, "status": "DRIVER_ARRIVED", "startAddress": "深圳湾公园 3 号入口",
    "startLatitude": 22.5, "startLongitude": 113.95,
    "plannedStart": "2026-10-10T10:00:00", "plannedEnd": "2026-10-10T11:00:00", "createdAt": "2026-10-09T09:00:00"
    """

    private func decodeOrder(_ extra: String) throws -> OrderDetailResponse {
        try JSONDecoder().decode(OrderDetailResponse.self, from: Data("{ \(Self.baseFields)\(extra) }".utf8))
    }

    func testEarliestBlindCancelAtDecodesFromALocalTimestamp() throws {
        let order = try decodeOrder(#", "earliestBlindCancelAt": "2026-10-10T10:10:00""#)
        XCTAssertEqual(order.earliestBlindCancelAt, "2026-10-10T10:10:00")
    }

    func testMissingOrNullEarliestBlindCancelAtDecodesAsNil() throws {
        XCTAssertNil(try decodeOrder("").earliestBlindCancelAt)
        XCTAssertNil(try decodeOrder(#", "earliestBlindCancelAt": null"#).earliestBlindCancelAt)
    }

    /// 类型不对不许连累整张订单 —— 解码失败 = 订单页整屏空白（`AGENTS.md` 硬约束）。
    func testMalformedEarliestBlindCancelAtDoesNotBreakTheOrder() throws {
        let order = try decodeOrder(#", "earliestBlindCancelAt": 1760061000"#)
        XCTAssertEqual(order.status, .driverArrived)
        XCTAssertNil(order.earliestBlindCancelAt)
        XCTAssertNil(try decodeOrder(#", "earliestBlindCancelAt": {"at": "x"}"#).earliestBlindCancelAt)
    }

    /// 状态推送换状态时要带过去，否则推送与重拉之间那几秒入口会闪没。
    func testReplacingStatusKeepsTheEarliestBlindCancelTime() {
        var order = OrderDetailResponse.preview(status: .driverArrived)
        order.earliestBlindCancelAt = "2026-10-10T10:10:00"
        XCTAssertEqual(order.replacingStatus(with: .driverArrived).earliestBlindCancelAt, "2026-10-10T10:10:00")
    }

    // MARK: - 门槛

    private func arrivedOrder(opensIn seconds: TimeInterval?, now: Date) -> OrderDetailResponse {
        var order = OrderDetailResponse.preview(status: .driverArrived, volunteerName: "张*", volunteerPhone: "13800000001")
        order.earliestBlindCancelAt = seconds.map {
            DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval($0))
        }
        return order
    }

    func testNoEntryWhenTheServerGivesNoTime() {
        let now = Date()
        XCTAssertNil(BlindArrivalCancelGate.resolve(order: arrivedOrder(opensIn: nil, now: now), now: now))
        var blank = arrivedOrder(opensIn: nil, now: now)
        blank.earliestBlindCancelAt = "  "
        XCTAssertNil(BlindArrivalCancelGate.resolve(order: blank, now: now))
    }

    /// 两侧各取一个点：只测一侧分不出「判据写反」与「根本没判」。
    func testLockedBeforeTheServerTimeAndOpenFromIt() throws {
        let now = Date()
        let order = arrivedOrder(opensIn: 10 * 60, now: now)
        let opensAt = try XCTUnwrap(order.earliestBlindCancelAt?.backendTimestamp)
        let clock = DateFormatter.aidRunDisplayClock.string(from: opensAt)

        XCTAssertEqual(BlindArrivalCancelGate.resolve(order: order, now: opensAt.addingTimeInterval(-1)), .locked(opensAt: clock))
        XCTAssertEqual(BlindArrivalCancelGate.resolve(order: order, now: opensAt), .open, "到点那一秒就该可按")
        XCTAssertEqual(BlindArrivalCancelGate.resolve(order: order, now: opensAt.addingTimeInterval(60)), .open)
    }

    /// 有值但解析不出：不锁，由后端判。锁住而后端其实放行，跑者就被关在一个本该能出去的门里。
    func testUnparsableTimeLeavesTheEntryOpen() {
        var order = arrivedOrder(opensIn: nil, now: Date())
        order.earliestBlindCancelAt = "十点十分"
        XCTAssertEqual(BlindArrivalCancelGate.resolve(order: order, now: Date()), .open)
    }

    /// 只在汇合态。`DRIVER_EN_ROUTE` / `IN_PROGRESS` 跑者仍不能取消（`AGENTS.md` §5），
    /// 哪怕字段因为 `replacingStatus` 带过去了还挂着。
    func testOnlyTheArrivedStateOffersTheEntry() {
        let now = Date()
        for status in RunOrderStatus.allCases where status != .driverArrived {
            let order = arrivedOrder(opensIn: -60, now: now).replacingStatus(with: status)
            XCTAssertNil(BlindArrivalCancelGate.resolve(order: order, now: now), "\(status) 不该有汇合态取消入口")
        }
    }

    // MARK: - 页面

    func testArrivedPresentationCarriesTheGateAndKeepsTheHelpRow() throws {
        let now = Date()
        let locked = try XCTUnwrap(BlindOrderFlowPresentation.make(
            order: arrivedOrder(opensIn: 5 * 60, now: now), distanceText: nil, canKeepWaiting: false, now: now
        ))
        guard case .locked = locked.arrivalCancel else {
            return XCTFail("到点前应是置灰的取消入口，实际：\(String(describing: locked.arrivalCancel))")
        }
        XCTAssertEqual(locked.arrivalCancel?.isEnabled, false)
        XCTAssertEqual(locked.lastRowTitle, "遇到问题", "「遇到问题」那一行不能被取消入口顶掉")

        let open = try XCTUnwrap(BlindOrderFlowPresentation.make(
            order: arrivedOrder(opensIn: -1, now: now), distanceText: nil, canKeepWaiting: false, now: now
        ))
        XCTAssertEqual(open.arrivalCancel, .open)

        let closed = try XCTUnwrap(BlindOrderFlowPresentation.make(
            order: arrivedOrder(opensIn: nil, now: now), distanceText: nil, canKeepWaiting: false, now: now
        ))
        XCTAssertNil(closed.arrivalCancel)
    }

    /// 负责人 2026-10-17 的原话是「X 点之后可以取消，先给陪跑员打电话」。
    func testLockedLabelSaysWhenAndToCallFirst() {
        XCTAssertEqual(
            BlindArrivalCancelCopy.lockedAccessibilityLabel(opensAt: "10:10"),
            "取消本单，10:10 之后可以取消，先给陪跑员打电话"
        )
    }

    // MARK: - 跨点播报

    func testUnlockIsAnnouncedOnlyOnTheLockedToOpenEdge() {
        let locked = BlindArrivalCancelGate.locked(opensAt: "10:10")
        XCTAssertEqual(
            BlindArrivalCancelGate.unlockAnnouncement(from: locked, to: .open),
            BlindArrivalCancelCopy.unlockedAnnouncement
        )
        XCTAssertNil(BlindArrivalCancelGate.unlockAnnouncement(from: nil, to: .open), "冷启动直接可按，不是「刚刚变了」")
        XCTAssertNil(BlindArrivalCancelGate.unlockAnnouncement(from: .open, to: .open), "5 秒一次的刷新不许重播")
        XCTAssertNil(BlindArrivalCancelGate.unlockAnnouncement(from: locked, to: locked))
        XCTAssertNil(BlindArrivalCancelGate.unlockAnnouncement(from: locked, to: nil), "离开汇合态不是「可以取消了」")
    }

    // MARK: - 错误朗读

    private static let tooEarlyMessage = "陪跑员刚到不久，请先打电话联系对方；若一直没碰上，10月10日 10:10之后可以取消"

    /// 后端 message 带着时刻，本地文案说不出来 —— 识别出码之后仍要念 message。
    func testTooEarlyReadsTheServerMessage() {
        let error = APIError.serverError(ErrorResponse(code: "BLIND_CANCEL_TOO_EARLY", message: Self.tooEarlyMessage))
        XCTAssertEqual(error.errorCode, .blindCancelTooEarly)
        XCTAssertEqual(error.localizedMessage, Self.tooEarlyMessage)
        XCTAssertEqual(BlindOrderStatusViewModel.cancelFailureMessage(for: error), Self.tooEarlyMessage)
    }

    func testTooEarlyFallsBackWhenTheServerMessageIsBlank() {
        let error = APIError.serverError(ErrorResponse(code: "BLIND_CANCEL_TOO_EARLY", message: " "))
        XCTAssertEqual(error.localizedMessage, BlindArrivalCancelCopy.tooEarlyFallback)
    }

    /// 其余已识别的码仍是本地文案优先 —— 别把「念 message」扩成全局默认。
    func testOtherKnownCodesStillUseLocalCopy() {
        let error = APIError.serverError(ErrorResponse(code: "END_WAIT_TOO_EARLY", message: "后端原文"))
        XCTAssertEqual(error.localizedMessage, ErrorCode.endWaitTooEarly.localizedMessage)
    }

    /// 通用那句是写给陪跑员「结束服务」的；跑者取消这一路要说跑者能做的事。
    func testActiveEmergencyIsReadInTheRunnersTerms() {
        let error = APIError.serverError(ErrorResponse(code: "ORDER_HAS_ACTIVE_EMERGENCY", message: "x"))
        let message = BlindOrderStatusViewModel.cancelFailureMessage(for: error)
        XCTAssertEqual(message, BlindArrivalCancelCopy.activeEmergency)
        XCTAssertFalse(message.contains("结束服务"))
    }

    // MARK: - Mock 照后端演

    func testMockRejectsAnEarlyArrivalCancelAndAcceptsALateOne() throws {
        let mock = MockAPIClient()
        mock.mockRole = .blind
        let now = Date()
        var early = OrderDetailResponse.preview(orderId: 51, status: .driverArrived)
        early.earliestBlindCancelAt = DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(600))
        var late = OrderDetailResponse.preview(orderId: 52, status: .driverArrived)
        late.earliestBlindCancelAt = DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval(-60))
        let closed = OrderDetailResponse.preview(orderId: 53, status: .driverArrived)
        mock.orders = [early, late, closed]

        XCTAssertThrowsError(try mock.handleCancel(orderId: 51)) { error in
            XCTAssertEqual((error as? APIError)?.errorCode, .blindCancelTooEarly)
        }
        XCTAssertEqual(try mock.handleCancel(orderId: 52).countedAsLateCancel, false)
        XCTAssertEqual(mock.orders.first { $0.orderId == 52 }?.status, .cancelled)
        XCTAssertThrowsError(try mock.handleCancel(orderId: 53), "后端关了出口时汇合态仍不能取消")
    }

    // MARK: - 陪跑员端

    private func afterArrivalNotification() -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: "after-arrival-1",
            eventType: "ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL",
            title: nil,
            body: "跑者没能和你碰上，已取消本单",
            ttsText: "你标记已到达之后，跑者一直没能和你碰上面，已经取消了这一单。你可以离开集合点了，这一单不算你取消。",
            priority: "HIGH",
            timestamp: "2026-10-10T10:12:00"
        )
    }

    /// 🔴 它绝不能被「有活跃订单 ⇒ 抑制」吃掉：只发给标了已到达的陪跑员 ⇒ 必然有活跃订单。
    /// 在真实场景（已注册活跃订单）下跑，只钉判定函数看不住组合。
    func testVolunteerHearsTheAfterArrivalCancelEvenWhileTheOrderIsActive() async {
        XCTAssertNil(AppRealtimeCoordinator.lifecycleStatus(forEventType: "ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL"))

        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .volunteer)
        coordinator.registerActiveOrder(7)

        service.simulateIncomingEventForTesting(.notification(afterArrivalNotification()))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, "跑者没能和你碰上，已取消本单")
        XCTAssertTrue(coordinator.currentNotification?.speechText.contains("你可以离开集合点了") == true)
        XCTAssertEqual(coordinator.currentNotification?.priority, .high)
    }

    func testVolunteerPageSentenceTellsThemToLeaveOnlyAfterArrival() {
        let afterArrival = VolunteerOrderFlowCopy.runnerCancelledAnnouncement(name: "李", afterArrival: true)
        XCTAssertTrue(afterArrival.contains("你可以离开集合点了"), afterArrival)
        XCTAssertTrue(afterArrival.contains("不算你的取消"), afterArrival)

        let earlier = VolunteerOrderFlowCopy.runnerCancelledAnnouncement(name: "李", afterArrival: false)
        XCTAssertFalse(earlier.contains("集合点"), "约好阶段取消时人多半还在家，说「离开集合点」是假话")
        XCTAssertEqual(earlier, "李取消了这次陪跑。不算你的取消，不需要做什么")
    }
}
