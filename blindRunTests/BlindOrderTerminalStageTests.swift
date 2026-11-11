import XCTest
@testable import blindRun

/// 订单页 v7 终态（#946）：竖线停在哪一步、小字写谁取消的、拿不到记录时不猜。
final class BlindOrderTerminalStageTests: XCTestCase, BlindRunTestSupport {

    /// 在「等出发」取消：转 CANCELLED 那条的 fromStatus 是 SCHEDULED_CONFIRMED ⇒ 停在第 3 步。
    /// 取错成别的记录（例如最早那条的 fromStatus）会停在第 1 步。
    func testCancelledStopsAtTheStepBeforeCancellation() throws {
        let logs = [
            log(id: 3, from: .scheduledConfirmed, to: .cancelled, remark: "取消方=BLIND"),
            log(id: 2, from: .pendingIntroCall, to: .scheduledConfirmed, remark: nil),
            log(id: 1, from: .pendingMatch, to: .pendingIntroCall, remark: nil),
        ]
        let page = try XCTUnwrap(BlindOrderTerminalPresentation.make(order: makeOrder(orderId: 1, status: .cancelled), logs: logs))
        let timeline = try XCTUnwrap(page.timeline)
        XCTAssertEqual(timeline.position, .stopped(.awaitDeparture))
        XCTAssertEqual(timeline.details[.awaitDeparture], "你取消了订单")
        XCTAssertEqual(page.eyebrow, "已取消")
    }

    /// 已到达后被系统取消（盲人没到）：停在「在集合点汇合」，小字是系统。
    func testSystemCancelAfterArrivalStopsAtMeetUp() {
        let logs = [log(id: 9, from: .driverArrived, to: .cancelled, remark: "取消方=SYSTEM")]
        XCTAssertEqual(BlindOrderTerminalPresentation.stoppedStep(status: .cancelled, logs: logs), .meetUp)
        XCTAssertEqual(BlindOrderTerminalPresentation.stoppedDetail(status: .cancelled, logs: logs), "系统自动取消了订单")
    }

    /// 记录还没拿到：不画竖线，不猜（稿 D 屏）。
    func testCancelledWithoutLogsDrawsNoTimeline() throws {
        let page = try XCTUnwrap(BlindOrderTerminalPresentation.make(order: makeOrder(orderId: 1, status: .cancelled), logs: []))
        XCTAssertNil(page.timeline)
    }

    /// remark 为空时小字不重复「已取消」（头部已经说了）。
    func testMissingRemarkGivesNoDetail() {
        let logs = [log(id: 1, from: .pendingMatch, to: .cancelled, remark: nil)]
        XCTAssertEqual(BlindOrderTerminalPresentation.stoppedStep(status: .cancelled, logs: logs), .matchVolunteer)
        XCTAssertNil(BlindOrderTerminalPresentation.stoppedDetail(status: .cancelled, logs: logs))
    }

    /// 暂无陪跑员恒停在第 1 步，不用等记录。
    func testNoVolunteerAlwaysStopsAtTheFirstStep() throws {
        let page = try XCTUnwrap(BlindOrderTerminalPresentation.make(order: makeOrder(orderId: 1, status: .noVolunteer), logs: []))
        XCTAssertEqual(page.timeline?.position, .stopped(.matchVolunteer))
        XCTAssertEqual(page.title, BlindOrderTerminalCopy.noVolunteerTitle)
    }

    /// 非终态不走这一页。
    func testNonTerminalStatesHaveNoTerminalPresentation() {
        for status in RunOrderStatus.allCases where !status.usesBlindTerminalPage {
            XCTAssertNil(BlindOrderTerminalPresentation.make(order: makeOrder(orderId: 1, status: status), logs: []), status.rawValue)
        }
    }

    /// 暂无陪跑员不是取消：中断步的读屏不许说「取消」（头部念「这次没找到陪跑员」，两句不能打架）。
    @MainActor
    func testNoVolunteerStoppedStepDoesNotSayCancelled() throws {
        let page = try XCTUnwrap(BlindOrderTerminalPresentation.make(order: makeOrder(orderId: 1, status: .noVolunteer), logs: []))
        let rows = BlindOrderTimelineLayout.rows(try XCTUnwrap(page.timeline))
        let spoken = rows.map(BlindOrderTimelineLayout.accessibilityLabel(for:)).joined()
        XCTAssertFalse(spoken.contains("取消"), spoken)
    }

    /// 订单页的三条兜底分支：订单为空走 v7 加载外壳（不许回到改版前那页），`.unknown` 必须留在只读退路。
    func testPageFallbackRoutesLoadingTerminalAndUnknown() {
        XCTAssertEqual(BlindOrderPageFallback.resolve(nil), .loadingShell)
        XCTAssertEqual(BlindOrderPageFallback.resolve(.unknown), .readOnly)
        for status in RunOrderStatus.allCases where status != .unknown {
            let expected: BlindOrderPageFallback = status.usesBlindTerminalPage ? .terminal : .stateful
            XCTAssertEqual(BlindOrderPageFallback.resolve(status), expected, status.rawValue)
        }
        XCTAssertEqual(BlindOrderPageFallback.resolve(.cancelled), .terminal)
        XCTAssertEqual(BlindOrderPageFallback.resolve(.noVolunteer), .terminal)
    }

    private func log(id: Int64, from: RunOrderStatus?, to: RunOrderStatus, remark: String?) -> OrderStatusLog {
        OrderStatusLog(id: id, fromStatus: from, toStatus: to, changedAt: "2026-11-11T07:00:00", remark: remark)
    }
}
