import XCTest
@testable import blindRun

/// 对账（`refreshActiveEvent`）只在带来新信息时改写状态（#546）。
///
/// 对账回来的是同一条事件、同一个状态时，它没有带来任何新信息；此前却照样写 `.acknowledged`，
/// 把比它多一层信息的状态抹成通用的「已发出」：
/// - 「这次没有新建求助」（屏 3b，刚才那一按被并进了旧事件）—— 倒计时到点后 3 秒宽限里再按一次就会撞上；
/// - 「短信没送到，请自己拨 110」—— 断线重连的补读就会撞上，盲人听到的从警告变成了安慰。
///
/// 单独成文件：`EmergencySOSTests.swift` 已超 SwiftLint 的长度上限，CI 棘轮不许它再变长。
@MainActor
final class EmergencyRefreshKeepsRicherStateTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run { EmergencySOSTests.teardownAlarmObservers() }
        try await super.tearDown()
    }

    /// 🔴 #546 原样：倒计时到点、宽限刷新还没回来时再按一次，被后端并进同一条 ——
    /// 宽限刷新回来后屏幕上仍是「这次没有新建求助」，不是通用的「已发出」。
    func testGraceRefreshAfterTheCountdownFiresKeepsTheMergedRetriggerCopy() async throws {
        let (coordinator, safety) = Self.makeRecoverableFixture()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(
            success: true, eventId: 950, status: "COUNTDOWN", countdownEndsAt: Self.backendTime(secondsFromNow: 2)
        ))
        _ = await Self.trigger(coordinator, safety: safety, useCountdown: true)
        XCTAssertTrue(coordinator.state.isCountingDown, "前提：服务端倒计时已登记，实际是 \(coordinator.state)")

        // 到点：本机写「已受理」，然后睡 `serverFireGrace` 再去对账。
        try await Self.waitUntil(seconds: 5) { coordinator.state == .acknowledged(.pending) }

        // 宽限期里再长按一次，后端并进同一条（同一个 eventId）。对账会读到同一条、同一个状态。
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 950, status: "PENDING"))
        safety.activeEmergencyResult = .success(try Self.openEvent(id: 950, status: "PENDING"))
        coordinator.beginCountdown(
            order: EmergencySOSTests.makeOrder(status: .inProgress), role: .blind, userID: 7, safety: safety,
            locate: { EmergencySOSTests.coordinate(latitude: 39.916, longitude: 116.404) }
        )
        try await Self.waitUntil(seconds: 3) { coordinator.state == .mergedIntoOpenEvent(.pending) }

        // 等宽限刷新真的落地（它是唯一会去问 `activeEmergency()` 的调用方）。
        try await Self.waitUntil(seconds: EmergencyCoordinator.serverFireGrace + 2) {
            safety.calls.contains("activeEmergency()")
        }
        await Task.yield()

        XCTAssertEqual(coordinator.state, .mergedIntoOpenEvent(.pending), "宽限刷新把合并文案盖掉了")
        XCTAssertTrue(coordinator.statusMessage?.hasPrefix("这次没有新建求助") == true, "\(coordinator.statusMessage ?? "nil")")
        coordinator.reset()
    }

    /// 同一条、同一个状态 → 保留合并文案。直接调对账，不依赖倒计时的计时。
    func testRefreshWithNoNewsKeepsTheMergedRetriggerCopy() async throws {
        let (coordinator, safety) = Self.makeRecoverableFixture()
        try await Self.triggerTwiceIntoOneEvent(coordinator, safety: safety, status: "CS_HANDLING")
        safety.activeEmergencyResult = .success(try Self.openEvent(id: 830, status: "CS_HANDLING"))

        await coordinator.refreshActiveEvent(userID: 7)

        XCTAssertEqual(coordinator.state, .mergedIntoOpenEvent(.csHandling))
        XCTAssertEqual(coordinator.activeEvent?.eventID, 830)
    }

    /// 对照组：对账带来了**新状态**就照新状态说。没有这一条，「合并态一律不许改写」的实现也能让上面两条变绿，
    /// 而那会让盲人一直听「这次没有新建」、听不到客服已经接手。
    func testRefreshWithANewStatusMovesOnFromTheMergedCopy() async throws {
        let (coordinator, safety) = Self.makeRecoverableFixture()
        try await Self.triggerTwiceIntoOneEvent(coordinator, safety: safety, status: "PENDING")
        safety.activeEmergencyResult = .success(try Self.openEvent(id: 830, status: "CONTACT_NOTIFIED"))

        await coordinator.refreshActiveEvent(userID: 7)

        XCTAssertEqual(coordinator.state, .acknowledged(.contactNotified))
    }

    /// 对照组：对账读到的是**另一条**事件（同一状态）就是新信息，照它说。
    func testRefreshWithADifferentEventIsNotTreatedAsNoNews() async throws {
        let (coordinator, safety) = Self.makeRecoverableFixture()
        try await Self.triggerTwiceIntoOneEvent(coordinator, safety: safety, status: "CS_HANDLING")
        safety.activeEmergencyResult = .success(try Self.openEvent(id: 831, status: "CS_HANDLING"))

        await coordinator.refreshActiveEvent(userID: 7)

        XCTAssertEqual(coordinator.state, .acknowledged(.csHandling))
        XCTAssertEqual(coordinator.activeEvent?.eventID, 831)
    }

    /// 🔴 短信回执两态（送达 / 没送到）不改事件状态（仍是 `CONTACT_NOTIFIED`），断线重连的补读读回来的正是同一状态。
    /// 「没送到」被抹成「已发出」= 盲人不再被提醒自己拨 110。
    func testRefreshWithNoNewsKeepsTheSmsReceiptStates() async throws {
        for kind in [RealtimeSafetyEvent.Kind.emergencyContactNotifyFailed, .emergencyContactSmsDelivered] {
            let (coordinator, safety) = Self.makeRecoverableFixture()
            safety.triggerEmergencyResult = .success(
                EmergencyTriggerResponse(success: true, eventId: 830, status: "CONTACT_NOTIFIED")
            )
            _ = await Self.trigger(coordinator, safety: safety)
            coordinator.apply(Self.safetyEvent(kind: kind))
            let receiptState = coordinator.state
            XCTAssertNotEqual(receiptState, .acknowledged(.contactNotified), "前提：\(kind) 应当改写状态")
            safety.activeEmergencyResult = .success(try Self.openEvent(id: 830, status: "CONTACT_NOTIFIED"))

            await coordinator.refreshActiveEvent(userID: 7)

            XCTAssertEqual(coordinator.state, receiptState, "\(kind) 被对账抹成了通用的已发出")
        }
    }

    // MARK: - Helpers

    private static func makeRecoverableFixture() -> (EmergencyCoordinator, FakeSafetyService) {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        // `refreshActiveEvent` 只在装了 provider 时才会去问。
        coordinator.observe(AppRealtimeCoordinator(notificationDuration: 60)) { safety }
        return (coordinator, safety)
    }

    private static func trigger(
        _ coordinator: EmergencyCoordinator,
        safety: FakeSafetyService,
        useCountdown: Bool = false
    ) async -> EmergencyCoordinator.TriggerOutcome {
        await coordinator.trigger(
            order: EmergencySOSTests.makeOrder(status: .inProgress), role: .blind, userID: 7, safety: safety,
            locate: { EmergencySOSTests.coordinate(latitude: 39.915, longitude: 116.404) },
            useCountdown: useCountdown
        )
    }

    /// 先发出一条，再按一次被并进同一条（后端 #841：同一个 `eventId`）。
    private static func triggerTwiceIntoOneEvent(
        _ coordinator: EmergencyCoordinator,
        safety: FakeSafetyService,
        status: String
    ) async throws {
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 830, status: status))
        _ = await trigger(coordinator, safety: safety)
        _ = await trigger(coordinator, safety: safety)
        guard case .mergedIntoOpenEvent = coordinator.state else {
            return XCTFail("前提：第二次应当被并进同一条，实际是 \(coordinator.state)")
        }
    }

    /// 用解码造 fixture，理由见 `EmergencySOSTests.openEventEnvelope`。
    private static func openEvent(id: Int64, status: String) throws -> EmergencyActiveEnvelope {
        let json = """
        {"success":true,"code":200,"data":{
          "id":\(id),"orderId":4242,"userId":7,
          "triggeredAt":"2026-10-28T10:00:00","triggerType":"BUTTON",
          "status":"\(status)","hasGpsLocation":true}}
        """
        return try APIPayloadDecoder.decodePayload(EmergencyActiveEnvelope.self, from: Data(json.utf8), decoder: JSONDecoder())
    }

    private static func safetyEvent(kind: RealtimeSafetyEvent.Kind) -> RealtimeSafetyEvent {
        RealtimeSafetyEvent(
            eventID: "msg-1", orderID: 4242, kind: kind,
            displayText: "ignored", speechText: "ignored", timestamp: nil, coordinate: nil
        )
    }

    private static func backendTime(secondsFromNow: TimeInterval) -> String {
        DateFormatter.aidRunBackendLocalDateTime.string(from: Date().addingTimeInterval(secondsFromNow))
    }

    private static func waitUntil(seconds: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else {
                return XCTFail("等了 \(seconds) 秒条件仍不成立")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
