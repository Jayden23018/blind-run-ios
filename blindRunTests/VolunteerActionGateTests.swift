import XCTest
@testable import blindRun

/// 后端 #546：订单详情下发三道闸的放行时刻，陪跑员主按钮照它锁，不再「按了才 409」。
///
/// 每条判据都在时刻**两侧**各取一点：只测一侧分不出「判据写反了」与「根本没判」。
@MainActor
final class VolunteerActionGateTests: XCTestCase {
    private let now = Date()

    private func order(
        _ status: RunOrderStatus,
        earliestDeparture: TimeInterval? = nil,
        earliestServiceStart: TimeInterval? = nil,
        blindConfirmDeadline: TimeInterval? = nil
    ) -> OrderDetailResponse {
        var order = OrderDetailResponse.preview(status: status)
        let format: (TimeInterval?) -> String? = { offset in
            offset.map { DateFormatter.aidRunBackendLocalDateTime.string(from: self.now.addingTimeInterval($0)) }
        }
        order.earliestDepartureAt = format(earliestDeparture)
        order.earliestServiceStartAt = format(earliestServiceStart)
        order.blindConfirmDeadlineAt = format(blindConfirmDeadline)
        return order
    }

    func testDepartureActionsLockUntilTheServerTimeAndSayWhen() {
        for action in [VolunteerOrderFlowPresentation.PrimaryAction.confirmDeparture, .enRoute, .alreadyDeparted] {
            let locked = VolunteerActionGate.resolve(action: action, order: order(.pendingAccept, earliestDeparture: 600), now: now)
            XCTAssertTrue(locked.isLocked, "\(action) 没到放行时刻却能按")
            XCTAssertTrue(locked.caption?.contains("起可以按") == true)

            let open = VolunteerActionGate.resolve(action: action, order: order(.pendingAccept, earliestDeparture: -1), now: now)
            XCTAssertFalse(open.isLocked, "\(action) 过了放行时刻还锁着")
        }
    }

    func testStartRunLocksUntilEarliestServiceStart() {
        let locked = VolunteerActionGate.resolve(action: .startRun, order: order(.driverArrived, earliestServiceStart: 300), now: now)
        XCTAssertTrue(locked.isLocked)
        let open = VolunteerActionGate.resolve(action: .startRun, order: order(.driverArrived, earliestServiceStart: -1), now: now)
        XCTAssertEqual(open, .open)
    }

    /// 同意闸**不锁**（契约：按钮不要置灰），只把「跑者还没按、几点起你也能开始」说在前面。
    func testConsentGateNeverLocksButSaysWhenYouCanStartAlone() {
        let gate = VolunteerActionGate.resolve(
            action: .startRun,
            order: order(.driverArrived, earliestServiceStart: -60, blindConfirmDeadline: 900),
            now: now
        )
        XCTAssertFalse(gate.isLocked, "同意闸把按钮锁住了 —— 跑者随时可能按，锁住就会错过")
        XCTAssertTrue(gate.caption?.contains("跑者还没按开始跑步") == true)

        let past = VolunteerActionGate.resolve(
            action: .startRun,
            order: order(.driverArrived, earliestServiceStart: -60, blindConfirmDeadline: -1),
            now: now
        )
        XCTAssertEqual(past, .open, "宽限已过，陪跑员可以单方面开始，不该再提示等跑者")
    }

    /// 时间闸先于同意闸：还没到可以开始的时刻时，说「几点可以按」，而不是「等跑者」。
    func testTimeGateOutranksTheConsentCaption() {
        let gate = VolunteerActionGate.resolve(
            action: .startRun,
            order: order(.driverArrived, earliestServiceStart: 300, blindConfirmDeadline: 1200),
            now: now
        )
        XCTAssertTrue(gate.isLocked)
        XCTAssertTrue(gate.caption?.contains("起可以按") == true)
    }

    /// 字段缺失时不锁：由后端判（按下去最多一句 409 文案）。锁住而后端其实放行才是更糟的那种。
    func testMissingTimesNeverLock() {
        for action in [VolunteerOrderFlowPresentation.PrimaryAction.confirmDeparture, .enRoute, .startRun, .arrived, .endWaiting] {
            XCTAssertEqual(VolunteerActionGate.resolve(action: action, order: order(.driverArrived), now: now), .open)
        }
        XCTAssertEqual(VolunteerActionGate.resolve(action: nil, order: order(.driverArrived), now: now), .open)
    }

    /// 状态推送换状态时这两个字段要带过去，否则推送与重拉之间那几秒按钮会闪成可按。
    func testReplacingStatusKeepsTheGateTimes() {
        var order = OrderDetailResponse.preview(status: .scheduledConfirmed)
        order.earliestDepartureAt = "2026-10-06T08:00:00"
        order.blindConfirmDeadlineAt = "2026-10-06T09:15:00"
        let replaced = order.replacingStatus(with: .pendingAccept)
        XCTAssertEqual(replaced.earliestDepartureAt, "2026-10-06T08:00:00")
        XCTAssertEqual(replaced.blindConfirmDeadlineAt, "2026-10-06T09:15:00")
    }
}
