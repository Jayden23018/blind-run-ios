import XCTest
@testable import blindRun

/// 精确位置关着时跑步中的后果要说清（#407 第 2 项文案更正，OpenSpec `warn-signal-lost-escalation-when-precise-off`）。
/// 后端在 `IN_PROGRESS` 读不到一方坐标，几分钟后按失联升级求助；横幅此前说「走散提醒用不了」，不对。
@MainActor
final class EscortPreciseLocationEscalationTests: XCTestCase {

    /// 四句文案（两端 × 跑步前后）都说清会按失联处理，且守住求助红线：只说将来，不说已发出 / 已通知，不提短信，不写死时长。
    func testEscalationCopyStatesTheFutureWithoutClaimingDeliveryOrAFixedDuration() {
        for role in [UserRole.blind, .volunteer] {
            for running in [false, true] {
                let message = EscortPreciseLocationCopy.message(role: role, running: running)
                let name = "\(role) running=\(running)：\(message)"
                for word in ["失联", "几分钟后", "求助流程", "暂停同行位置共享", "系统设置"] {
                    XCTAssertTrue(message.contains(word), "缺「\(word)」，\(name)")
                }
                // AGENTS.md §6：App 永远不说短信已发出、已送达，或家属已被通知。
                for word in ["已发出", "已发送", "已通知", "已送达", "短信"] {
                    XCTAssertFalse(message.contains(word), "不许出现「\(word)」，\(name)")
                }
                // 宽限时长是后端配置项（默认 180 秒），客户端不知道它改没改。
                for word in ["180", "3 分钟", "3分钟", "三分钟"] {
                    XCTAssertFalse(message.contains(word), "不许写死时长「\(word)」，\(name)")
                }
                XCTAssertFalse(message.contains("走散提醒用不了"), "旧的错误说法，\(name)")
            }
        }
        XCTAssertTrue(EscortPreciseLocationCopy.message(role: .blind, running: true).contains("发不出去"), "盲人端仍要说自己按求助发不出去（#380）")
        XCTAssertFalse(EscortPreciseLocationCopy.message(role: .volunteer, running: true).contains("发不出去"), "陪跑员端的求助不受影响")
        XCTAssertTrue(EscortPreciseLocationCopy.message(role: .blind, running: true).contains("跑步中"))
        XCTAssertTrue(EscortPreciseLocationCopy.message(role: .blind, running: false).contains("开始跑步后"))
    }

    /// 开跑时的那次提醒：出发时进「精确位置已关闭」一档，汇合不变（不重复念），进 `IN_PROGRESS` 换成跑步中那一句，
    /// 根视图的朗读闸（`CurrentValueReplayGate`，与 `ContentView` 同一个类型）因此再放行一次。两端都要。
    func testEnteringInProgressWithPreciseLocationOffRemindsOnceMore() async {
        for role in [UserRole.blind, .volunteer] {
            let location = EscortPreciseLocationGateTests.locationService(accuracy: 5000)
            location.simulatePreciseLocationOffForTesting()
            let (coordinator, service) = EscortPreciseLocationGateTests.makeEscortCoordinator(role: role, location: location)
            var gate = CurrentValueReplayGate<LiveEscortHealthState>()

            coordinator.updateOwnedOrder(orderID: 95, status: .driverEnRoute)
            let beforeRun = await Self.waitUntil {
                coordinator.healthState == .preciseLocationOff(role, running: false)
            }
            XCTAssertTrue(beforeRun, "\(role)：出发时应进精确位置那一档：\(coordinator.healthState)")
            XCTAssertTrue(gate.accepts(coordinator.healthState), "\(role)：出发时念一次")

            coordinator.updateOwnedOrder(orderID: 95, status: .driverArrived)
            _ = await Self.waitUntil(timeout: 0.3) { false }
            XCTAssertFalse(gate.accepts(coordinator.healthState), "\(role)：出发到汇合不重复念：\(coordinator.healthState)")

            coordinator.updateOwnedOrder(orderID: 95, status: .inProgress)
            let running = await Self.waitUntil {
                coordinator.healthState == .preciseLocationOff(role, running: true)
            }
            XCTAssertTrue(running, "\(role)：进跑步应换成跑步中那一句：\(coordinator.healthState)")
            XCTAssertTrue(gate.accepts(coordinator.healthState), "\(role)：开跑时要再念一次")
            XCTAssertTrue(coordinator.healthState.userMessage?.contains("跑步中") == true, "\(role)：横幅也要换字")
            coordinator.reset()
            withExtendedLifetime(service) {}
        }
    }

    /// 轮询到条件成立或超时。`{ false }` 当作「等一小段」用（同 `EscortPreciseLocationGateTests` 那份）。
    private static func waitUntil(timeout: TimeInterval = 1, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
