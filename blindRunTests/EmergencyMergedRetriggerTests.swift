import XCTest
@testable import blindRun

/// 再次触发被后端并进未结案事件（后端 #841，交接 blind-run-backend#843）。
///
/// 单独成文件：`EmergencySOSTests.swift` 已超 SwiftLint 的长度上限，CI 棘轮不许它再变长。
/// 桩数据与夹具沿用 `EmergencySOSTests` 的同名 helper。
@MainActor
final class EmergencyMergedRetriggerTests: XCTestCase {
    /// 后端合并时回的是**旧事件**：同一个 `eventId`，状态是它已发出的状态，
    /// `countdownEndsAt` 还留着当初那次倒计时的截止时刻（后端从不清它）。
    private static let mergedResponse = EmergencyTriggerResponse(
        success: true, eventId: 830, status: "CS_HANDLING", countdownEndsAt: "2020-01-01T09:00:00"
    )

    private static func trigger(
        _ coordinator: EmergencyCoordinator,
        safety: FakeSafetyService,
        latitude: Double,
        useCountdown: Bool = false
    ) async -> EmergencyCoordinator.TriggerOutcome {
        await coordinator.trigger(
            order: EmergencySOSTests.makeOrder(status: .inProgress), role: .blind, userID: 7, safety: safety,
            locate: { EmergencySOSTests.coordinate(latitude: latitude, longitude: 116.404) },
            useCountdown: useCountdown
        )
    }

    /// 先按一次、发出，再按一次（长按 = `useCountdown: true`）被并进同一条。
    private static func triggerTwiceIntoOneEvent(
        coordinator: EmergencyCoordinator,
        safety: FakeSafetyService
    ) async -> EmergencyCoordinator.TriggerOutcome {
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 830, status: "CS_HANDLING")
        )
        _ = await trigger(coordinator, safety: safety, latitude: 39.915)
        safety.triggerEmergencyResult = .success(mergedResponse)
        return await trigger(coordinator, safety: safety, latitude: 39.916, useCountdown: true)
    }

    override func tearDown() async throws {
        await MainActor.run { EmergencySOSTests.teardownAlarmObservers() }
        try await super.tearDown()
    }

    /// 🔴 合并时不许念得和「新求助」一模一样 —— 听的人会以为又发出了一条、家属又收到一条短信。
    func testRetriggerMergedIntoTheOpenEventSaysNoNewRequestWasCreated() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()

        let outcome = await Self.triggerTwiceIntoOneEvent(coordinator: coordinator, safety: safety)

        XCTAssertTrue(outcome.message.contains("这次没有新建求助"), "合并被念成了新求助：\(outcome.message)")
        // 负责人 2026-10-22 批准的原句，逐字锁住：改成「已通知客服 / 已通知家属」或丢掉 110 提示都要红。
        // 逐字相等也就覆盖了 `EmergencySOSTests` 那份「不得宣称送达」清单（那个文件长度已冻结，不往里加）。
        XCTAssertEqual(
            outcome.message,
            "这次没有新建求助：你上一次的求助还在处理中，已更新你的位置，系统正在再次提醒客服跟进。若情况危急请立即拨打120或110。"
        )
        XCTAssertEqual(coordinator.statusMessage, outcome.message, "屏幕和读屏不是同一句")
        XCTAssertEqual(coordinator.activeEvent?.eventID, 830)
        XCTAssertFalse(outcome.message.contains("新求助已发出"))
        XCTAssertFalse(outcome.message.contains("短信"), "原事件还在 PENDING 时后端这次才第一次通知家属，任何关于短信的说法都可能是假的")
        XCTAssertEqual(
            coordinator.repeatStatusSuffix,
            EmergencySafetyCopy.submitted(.csHandling),
            "「重复当前状态」不该一直念「这次没有新建」，那句只属于刚才那一按"
        )
    }

    /// 合并回来的 `countdownEndsAt` 非空但已过去、状态已发出 —— 只认状态，不许进倒计时、不许给「取消」。
    func testMergedResponseWithAStaleCountdownDeadlineDoesNotCountDown() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()

        let outcome = await Self.triggerTwiceIntoOneEvent(coordinator: coordinator, safety: safety)

        XCTAssertFalse(outcome.state.isCountingDown)
        XCTAssertFalse(coordinator.state.isCountingDown)
        XCTAssertFalse(outcome.message.contains("秒后发出"))
    }

    /// 对照组：换了 `eventId` 就是一条新求助，照状态文案说，不算合并。
    /// 没有这一条，「每次触发都念合并文案」的实现也能让上面那条变绿。
    func testRetriggerWithANewEventIdIsANewRequestNotAMerge() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 830, status: "CS_HANDLING")
        )
        _ = await Self.trigger(coordinator, safety: safety, latitude: 39.915)
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 831, status: "CS_HANDLING")
        )
        let outcome = await Self.trigger(coordinator, safety: safety, latitude: 39.916)

        XCTAssertEqual(outcome.state, .acknowledged(.csHandling))
        XCTAssertFalse(outcome.message.contains("这次没有新建求助"))
        XCTAssertEqual(coordinator.mergedRetriggerCount, 0, "新求助被当成了合并")
    }

    /// 屏 3b 靠 `eventID` 变化拉起来，合并时 id 不变 —— 每一次合并都要给出一个「再拉一次」的信号。
    /// 第一次按下（新事件）不算，否则第一次也会被拉两遍。
    func testEachMergedRetriggerAsksForTheSentScreenAgain() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()

        _ = await Self.triggerTwiceIntoOneEvent(coordinator: coordinator, safety: safety)
        XCTAssertEqual(coordinator.mergedRetriggerCount, 1)

        _ = await Self.trigger(coordinator, safety: safety, latitude: 39.917)
        XCTAssertEqual(coordinator.mergedRetriggerCount, 2)
        XCTAssertEqual(
            EmergencySafetyCopy.screenTitle(for: coordinator.state, hasActiveEvent: true),
            EmergencySafetyCopy.sentTitle,
            "原来那一条确实已发出，标题照旧"
        )
    }

    /// 计数器只增不减：`reset()`（退出登录、换账号）清回 0 本身就是一次变化，会把屏 3b 弹出来。
    func testResetDoesNotRewindTheMergedRetriggerCount() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        _ = await Self.triggerTwiceIntoOneEvent(coordinator: coordinator, safety: safety)

        coordinator.reset()

        XCTAssertEqual(coordinator.mergedRetriggerCount, 1)
    }

    /// 合并也是「已发出」：所附坐标的误差说明照样适用（`PreciseLocationGateTests` 守其余状态）。
    func testMergedStateCarriesTheSubmittedLocation() {
        XCTAssertTrue(EmergencySOSState.mergedIntoOpenEvent(.csHandling).carriesSubmittedLocation)
        XCTAssertFalse(EmergencySOSState.mergedIntoOpenEvent(.resolved).carriesSubmittedLocation)
    }
}
