import XCTest
@testable import blindRun

/// 陪跑员订单页补齐盲人端 v7 的两个纯判定（#962）：⑨「跑者已取消」的竖线停在哪一步（第 2 项），
/// 进页加载外壳走哪一支（第 1 项）。放单独的文件：`VolunteerOrderFlowPresentationTests.swift` 已到棘轮上限。
///
/// 此前写死停在「等出发」。下面每条都挑「写死实现」与「读记录实现」结果不同的取值：
/// 汇合时取消在写死实现下会停在「等出发」，没有记录在写死实现下照样画竖线。
final class VolunteerRunnerCancelledTimelineTests: XCTestCase {

    /// 跑者在汇合时（`DRIVER_ARRIVED`，满门槛后）取消：停在「去集合点汇合」，不是「等出发」。
    func testCancelAfterArrivalStopsAtMeetUp() throws {
        let logs = [
            log(id: 5, from: .driverArrived, to: .cancelled),
            log(id: 4, from: .driverEnRoute, to: .driverArrived),
            log(id: 3, from: .pendingAccept, to: .driverEnRoute),
        ]
        let input = try XCTUnwrap(VolunteerRunnerCancelledTimeline.input(logs: logs))
        XCTAssertEqual(input.position, .stopped(.meetUp))
        XCTAssertEqual(input.details[.meetUp], VolunteerOrderFlowCopy.runnerCancelledStepDetail)
        XCTAssertEqual(input.vocabulary, .volunteer)
    }

    /// 已出发时取消同样停在「去集合点汇合」。
    func testCancelWhileEnRouteStopsAtMeetUp() {
        let logs = [log(id: 2, from: .driverEnRoute, to: .cancelled)]
        XCTAssertEqual(VolunteerRunnerCancelledTimeline.input(logs: logs)?.position, .stopped(.meetUp))
    }

    /// 约好 / 临期确认时取消：停在「等出发」。取错成最早那条记录的 `fromStatus` 会停在第 1 步。
    func testCancelWhileAgreedStopsAtAwaitDeparture() {
        for from in [RunOrderStatus.scheduledConfirmed, .pendingAccept] {
            let logs = [
                log(id: 3, from: from, to: .cancelled),
                log(id: 2, from: .pendingIntroCall, to: from),
                log(id: 1, from: .pendingMatch, to: .pendingIntroCall),
            ]
            XCTAssertEqual(
                VolunteerRunnerCancelledTimeline.input(logs: logs)?.position,
                .stopped(.awaitDeparture),
                from.rawValue
            )
        }
    }

    /// 记录没拿到：不画竖线，不猜。
    func testNoLogsDrawsNoTimeline() {
        XCTAssertNil(VolunteerRunnerCancelledTimeline.input(logs: []))
    }

    /// 有记录但没有转 `CANCELLED` 的那条：同样不画。
    func testLogsWithoutCancellationDrawNoTimeline() {
        let logs = [log(id: 1, from: .pendingAccept, to: .driverEnRoute)]
        XCTAssertNil(VolunteerRunnerCancelledTimeline.input(logs: logs))
    }

    // MARK: - 进页加载外壳（第 1 项）

    /// 订单还没拿到的两种走 v7 外壳（#962，同盲人端 #946）；有订单的只读说明不走 —— 否则 `.unknown`
    /// 会被画成「正在获取订单状态」，永远在转圈。
    func testOnlyTheNoOrderYetBranchesUseTheV7LoadingShell() {
        XCTAssertTrue(VolunteerOrderFallback.resolve(status: nil, errorMessage: nil).usesV7Shell)
        XCTAssertTrue(VolunteerOrderFallback.resolve(status: nil, errorMessage: "获取订单状态失败").usesV7Shell)
        XCTAssertFalse(VolunteerOrderFallback.resolve(status: .unknown, errorMessage: nil).usesV7Shell)
        XCTAssertFalse(VolunteerOrderFallback.resolve(status: .rematching, errorMessage: "操作失败").usesV7Shell)
    }

    /// 有 `initialOrder` 时 view model 一构造就有订单：页面第一帧画那一态，不先闪加载外壳。
    /// 打回成「只在 `configure` 里写入」的实现，这里会是 nil。
    @MainActor
    func testInitialOrderIsAvailableBeforeConfigure() {
        let seeded = OrderDetailResponse.preview(status: .pendingAccept)
        XCTAssertEqual(VolunteerInServiceViewModel(initialOrder: seeded).order?.orderId, seeded.orderId)
        XCTAssertNil(VolunteerInServiceViewModel().order)
    }

    private func log(id: Int64, from: RunOrderStatus?, to: RunOrderStatus) -> OrderStatusLog {
        OrderStatusLog(id: id, fromStatus: from, toStatus: to, changedAt: "2026-11-12T07:00:00", remark: "取消方=BLIND")
    }
}
