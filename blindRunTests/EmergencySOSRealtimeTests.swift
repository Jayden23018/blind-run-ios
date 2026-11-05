import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSRealtimeTests: XCTestCase, EmergencySOSTestSupport {

    // MARK: - 求助状态的刷新机制

    /// `EmergencyActionSection` 用 `@ObservedObject` 跟随 coordinator 重绘，**前提是 coordinator
    /// 真的会在状态变化时发布**。这条断言就是把那个前提钉住。
    ///
    /// 为什么值得单独一条：`AppState.emergencyCoordinator` 是 `let` 不是 `@Published`，
    /// `AppState` 也没有转发子对象的 `objectWillChange`。所以求助状态的刷新**完全**依赖
    /// 「显示它的那个视图自己订阅 coordinator」这一条链路。一旦 `state` 不再是 `@Published`，
    /// 屏幕会静默停在旧值 —— 盲人听到的是过期结论（还在念「正在发送」而其实已经失败），
    /// 而这正是 `AGENTS.md` §6「每一种结果都必须可见且可听地如实告知」要挡的事。
    /// 编译不会报错，UI 也不会崩，只有这条用例会红。
    func testCoordinatorPublishesWhenSosStateChanges() async {
        let coordinator = EmergencyCoordinator()
        var emissions = 0
        let cancellable = coordinator.objectWillChange.sink { _ in emissions += 1 }
        defer { cancellable.cancel() }

        // 非 IN_PROGRESS 直接落到 finish(.failed)，是最短的一条真实状态变化路径。
        await coordinator.trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .blind,
            userID: 7,
            safety: FakeSafetyService(),
            locate: { Self.coordinate() }
        )

        XCTAssertGreaterThan(
            emissions,
            0,
            "coordinator 必须在状态变化时发布，否则订阅它的求助区块会静默停在旧值"
        )
        XCTAssertTrue(coordinator.state.isFailure)
    }

    // MARK: - Realtime follow-ups

    func testContactNotifiedEventAdvancesTheActiveEvent() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "VOLUNTEER_NOTIFIED"))
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )

        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified))

        XCTAssertEqual(coordinator.activeEvent?.status, .contactNotified)
        XCTAssertEqual(coordinator.state, .acknowledged(.contactNotified))
        XCTAssertEqual(coordinator.state.message, EmergencySafetyCopy.contactNotified)
    }

    func testEventForAnotherOrderIsIgnored() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "VOLUNTEER_NOTIFIED"))
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )

        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified, orderID: 999))

        XCTAssertEqual(coordinator.activeEvent?.status, .volunteerNotified)
    }

    func testSafetyEventWithoutAnActiveEmergencyIsIgnored() {
        let coordinator = EmergencyCoordinator()
        coordinator.apply(Self.safetyEvent(kind: .emergencyContactNotified))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.activeEvent)
    }

    func testResetClearsEverythingAtSessionBoundaries() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 9, status: "PENDING"))
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertNotNil(coordinator.activeEvent)

        coordinator.reset()

        XCTAssertNil(coordinator.activeEvent)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.repeatStatusSuffix)
    }

    // MARK: - Backend copy substitution

    /// The backend template body ("已通知紧急联系人{contactName}") must never reach the user.
    func testEmergencyEventTypesMapToLocalCopyNotBackendBody() {
        let mapped: [(String, RealtimeSafetyEvent.Kind, String)] = [
            ("EMERGENCY_TRIGGERED", .emergencyTriggered, EmergencySafetyCopy.triggeredAcknowledged),
            ("EMERGENCY_CONTACT_NOTIFIED", .emergencyContactNotified, EmergencySafetyCopy.contactNotified),
            ("EMERGENCY_NO_CONTACT", .emergencyNoContact, EmergencySafetyCopy.noContact),
            ("EMERGENCY_VOLUNTEER_TIMEOUT", .emergencyVolunteerTimeout, EmergencySafetyCopy.volunteerTimeout)
        ]
        for (eventType, expectedKind, expectedCopy) in mapped {
            XCTAssertEqual(AppRealtimeCoordinator.emergencyKind(forEventType: eventType), expectedKind)
            XCTAssertEqual(AppRealtimeCoordinator.emergencyCopy(for: expectedKind), expectedCopy)
        }
        XCTAssertNil(AppRealtimeCoordinator.emergencyKind(forEventType: "SERVICE_STARTED"))
    }

    // MARK: - Contract shape

    /// Shape comes from `EmergencyController.java:34-38`, which returns a bare `Map` rather than the
    /// usual `ApiResponse` envelope; `api_spec.yaml:1024-1030` only says `type: object`.
    func testTriggerResponseDecodesTheControllerShape() throws {
        let json = Data(#"{"success":true,"eventId":512,"status":"VOLUNTEER_NOTIFIED"}"#.utf8)
        let decoded = try JSONDecoder().decode(EmergencyTriggerResponse.self, from: json)
        XCTAssertEqual(decoded.eventId, 512)
        XCTAssertEqual(decoded.eventStatus, .volunteerNotified)
    }

    /// A status this client cannot name must degrade to `.unknown`, never to a rescue claim.
    func testUnrecognisedStatusDegradesToUnknown() throws {
        let json = Data(#"{"success":true,"eventId":1,"status":"SOMETHING_NEW"}"#.utf8)
        let decoded = try JSONDecoder().decode(EmergencyTriggerResponse.self, from: json)
        XCTAssertEqual(decoded.eventStatus, .unknown)
        XCTAssertFalse(EmergencySafetyCopy.submitted(.unknown).contains("已通知"))
    }

    /// Guards against drift from backend `entity/EmergencyStatus.java`.
    func testEmergencyStatusMirrorsTheBackendEnum() {
        // 2026-09-15 后端 PR #279 加了 COUNTDOWN / CANCELLED（9 个值）。
        let backendNames: Set<String> = [
            "COUNTDOWN", "PENDING", "VOLUNTEER_NOTIFIED", "VOLUNTEER_CONFIRMED",
            "CS_HANDLING", "CONTACT_NOTIFIED", "RESOLVED", "FALSE_ALARM", "CANCELLED"
        ]
        let clientNames = Set(EmergencyEventStatus.allCases.map(\.rawValue)).subtracting(["UNKNOWN"])
        XCTAssertEqual(clientNames, backendNames)
        // 终态与后端 `EmergencyStatus.terminalStatuses()` 一致：RESOLVED / FALSE_ALARM / CANCELLED。
        XCTAssertTrue(EmergencyEventStatus.resolved.isTerminal)
        XCTAssertTrue(EmergencyEventStatus.falseAlarm.isTerminal)
        XCTAssertTrue(EmergencyEventStatus.cancelled.isTerminal)
        XCTAssertFalse(EmergencyEventStatus.countdown.isTerminal)
        XCTAssertFalse(EmergencyEventStatus.contactNotified.isTerminal)
    }

    private static func safetyEvent(
        kind: RealtimeSafetyEvent.Kind,
        orderID: Int64? = nil,
        coordinate: LocatedCoordinate? = nil
    ) -> RealtimeSafetyEvent {
        RealtimeSafetyEvent(
            eventID: "msg-1",
            orderID: orderID,
            kind: kind,
            displayText: "ignored",
            speechText: "ignored",
            timestamp: nil,
            coordinate: coordinate
        )
    }
}
