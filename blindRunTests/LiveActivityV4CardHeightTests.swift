import SwiftUI
import XCTest
@testable import blindRun

/// 实时活动 v4（#919）锁屏卡高度 ≤ 160pt。量法同 `LiveActivityCardHeightTests`：
/// 在真机上按锁屏卡宽度把同一个 SwiftUI 视图排一次版，量它想要的高度（XCUITest 读不到锁屏卡）。
/// 稿里是 HTML 实测，SwiftUI 会有出入，所以每种最高的一屏各量一次。
@available(iOS 17.0, *)
@MainActor
final class LiveActivityV4CardHeightTests: XCTestCase {
    private func height(_ view: some View) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: LiveActivityCardHeightTests.lockScreenCardWidth, height: .greatestFiniteMagnitude))
            .height
    }

    private static let maximumHeight = LiveActivityCardHeightTests.maximumHeight

    /// 跑者跑步卡（B8）：三个数字 + 52pt 圆键 + 里程线。
    func testRunnerRunCardFitsTheLockScreen() {
        let state = RunLiveActivityContentBuilder.contentState(
            from: TrackStats(distanceMeters: 12_400, durationSeconds: 5_112, avgPaceSecPerKm: 463),
            partnerName: nil, targetDistanceMeters: 15_000
        )
        let measured = height(RunLiveActivityLockScreenView(side: .runner, state: state))
        XCTContext.runActivity(named: "[card-height] runner B8 = \(measured)") { _ in }
        XCTAssertLessThanOrEqual(measured, Self.maximumHeight)
    }

    /// 跑完（B9）。
    func testFinishedRunCardFitsTheLockScreen() {
        let state = RunLiveActivityContentBuilder.contentState(
            from: TrackStats(distanceMeters: 5_200, durationSeconds: 2_530, avgPaceSecPerKm: 484),
            partnerName: nil, targetDistanceMeters: 5_000, isFinished: true
        )
        let measured = height(RunLiveActivityLockScreenView(side: .runner, state: state))
        XCTContext.runActivity(named: "[card-height] runner B9 = \(measured)") { _ in }
        XCTAssertLessThanOrEqual(measured, Self.maximumHeight)
    }

    /// 盲人约跑进度卡里最高的几屏：B7（26pt 大标题 + 看距离的线）、B3（倒计时副标题 + 五节点线）、B6、B1。
    func testBlindOrderCardsFitTheLockScreen() {
        let start = Date().addingTimeInterval(20 * 60)
        func card(_ phase: BlindOrderActivityPhase) -> BlindOrderActivityAttributes.ContentState {
            BlindOrderActivityAttributes.ContentState(
                phase: phase, plannedStart: start, confirmDeadline: Date().addingTimeInterval(540),
                placeName: "朝阳公园南门", volunteerTopColor: "蓝色",
                distanceMeters: 300, departureDistanceMeters: 1_200
            )
        }
        for phase in [BlindOrderActivityPhase.arrived, .confirmPlan, .enRoute, .matching] {
            let presentation = BlindOrderActivityPresentation(state: card(phase), isStale: false)
            let measured = height(BlindOrderLockScreenView(presentation: presentation))
            XCTContext.runActivity(named: "[card-height] blind \(phase.rawValue) = \(measured)") { _ in }
            XCTAssertLessThanOrEqual(measured, Self.maximumHeight, "\(phase)")
        }
    }
}
