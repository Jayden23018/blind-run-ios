import XCTest
@testable import blindRun

/// 已取消 / 暂无志愿者走终态页，其余状态不走（#818）。
///
/// 错的形态是静默的：判错的状态要么整屏退回改版前的只读列表，要么在不该出现终态页的态出现「返回首页」。
final class BlindOrderTerminalPageTests: XCTestCase {

    /// 穷举全部状态。漏一个状态不会让任何断言变红，所以这条同时核对「期望表覆盖了所有 case」。
    func testOnlyCancelledAndNoVolunteerUseTheTerminalPage() {
        let expected: [RunOrderStatus: Bool] = [
            .cancelled: true,
            .noVolunteer: true,
            .pendingMatch: false,
            .pendingIntroCall: false,
            .rematching: false,
            .scheduledConfirmed: false,
            .pendingAccept: false,
            .driverEnRoute: false,
            .driverArrived: false,
            .inProgress: false,
            // 已完成是四步骨架的第四幕，走终态页会让 VoiceOver 焦点在完成那一刻回到顶部。
            .completed: false,
            // 未知态必须留在只读退路：后端加状态时它是唯一落点。
            .unknown: false,
        ]
        XCTAssertEqual(expected.count, RunOrderStatus.allCases.count, "有状态没写进期望表")
        for (status, usesTerminal) in expected {
            XCTAssertEqual(status.usesBlindTerminalPage, usesTerminal, "\(status.rawValue)")
        }
    }

    /// 终态页与四步骨架互斥：一个状态不能两边都走（两处各判一次的下场是整屏叠两套底栏）。
    func testTerminalPageAndFlowSkeletonNeverOverlap() {
        for status in RunOrderStatus.allCases where status.usesBlindTerminalPage {
            XCTAssertNil(status.blindOrderFlowStep, "\(status.rawValue) 同时走了骨架和终态页")
        }
    }
}
