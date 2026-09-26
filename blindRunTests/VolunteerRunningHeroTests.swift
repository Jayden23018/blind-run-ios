import XCTest
@testable import blindRun

/// 陪跑员跑步中头卡（`VolunteerRunningHero`，v2 画布 ⑤，#218）。
///
/// 边界取值都挑在两种实现会给出不同结果的地方：刚好跑满目标（`>=` 与 `>` 在这里分叉）、
/// 多跑 5 米与 320 米（「多跑了」阈值 10 米的两侧）、两条提示同时成立（优先级）。
final class VolunteerRunningHeroTests: XCTestCase {
    private func hero(
        planned: Int? = 5_000,
        run: Double? = 2_400,
        startAddress: String? = "深圳湾公园",
        fresh: Bool = true,
        acknowledged: Bool = false
    ) -> VolunteerRunningHero {
        let order = OrderDetailResponse.preview(
            status: .inProgress,
            startAddress: startAddress,
            plannedDistanceMeters: planned
        )
        let stats = run.map { TrackStats(distanceMeters: $0, durationSeconds: 1_112, avgPaceSecPerKm: 463) }
        return .make(order: order, stats: stats, isPeerLocationFresh: fresh, isPeerAlertAcknowledged: acknowledged)
    }

    func testShowsRunnerStatsInStopwatchFormat() {
        let h = hero()
        XCTAssertEqual(h.eyebrow, "陪跑中 · 深圳湾公园")
        XCTAssertEqual(h.distance, "2.40")
        XCTAssertEqual(h.duration, "18:32")
        XCTAssertEqual(h.pace, "7'43\"")
    }

    func testGoalShowsWhatIsLeftBeforeTheTarget() {
        let goal = hero(run: 2_400).goal
        XCTAssertEqual(goal?.text, "还剩 2.60 公里 · 目标 5.00")
        XCTAssertEqual(goal?.progress ?? -1, 0.48, accuracy: 0.0001)
        XCTAssertEqual(goal?.isReached, false)
    }

    /// 刚好跑满：写成 `over > 0` 的实现会在这里说「还剩 0.00 公里」。
    func testReachingTheTargetExactlyCountsAsReached() {
        let goal = hero(run: 5_000).goal
        XCTAssertEqual(goal?.isReached, true)
        XCTAssertEqual(goal?.text, "已完成 5.00 公里目标")
        XCTAssertEqual(goal?.progress, 1)
    }

    func testOverrunIsOnlyMentionedPastTheThreshold() {
        XCTAssertEqual(hero(run: 5_005).goal?.text, "已完成 5.00 公里目标", "多跑 5 米不该说「多跑了 0.01」")
        XCTAssertEqual(hero(run: 5_320).goal?.text, "已完成 5.00 公里目标 · 多跑了 0.32")
        XCTAssertEqual(hero(run: 5_320).goal?.progress, 1, "跑过目标进度条钳在满格")
    }

    func testNoPlannedDistanceMeansNoProgressBar() {
        XCTAssertNil(hero(planned: nil).goal)
        XCTAssertNil(hero(planned: 0).goal)
    }

    /// 刚起跑还没有轨迹：屏幕上是 `--`，读屏说「正在获取」而不是念「杠杠」。
    func testMissingStatsShowDashesAndSayFetching() {
        let h = hero(run: nil)
        XCTAssertEqual(h.distance, "--")
        XCTAssertEqual(h.goal?.text, "目标 5.00 公里")
        XCTAssertEqual(h.goal?.progress, 0)
        XCTAssertTrue(h.accessibilityLabel.contains("已跑，正在获取"), h.accessibilityLabel)
        XCTAssertFalse(h.accessibilityLabel.contains("--"))
    }

    func testEyebrowFallsBackToTitleWithoutAPlace() {
        XCTAssertEqual(hero(startAddress: nil).eyebrow, "陪跑中")
    }

    /// 求助已确认比位置断了更要紧：两条同时成立时只出前者。
    func testAcknowledgedAlertOutranksStaleLocation() {
        let h = hero(fresh: false, acknowledged: true)
        XCTAssertEqual(h.notice, "李*的求助\(EmergencySafetyCopy.volunteerPeerStatusAcknowledged)")
    }

    func testStaleLocationNoticeNeverSpeaksTheMaskAsterisk() {
        let h = hero(fresh: false)
        XCTAssertEqual(h.notice, "暂时收不到李*的位置")
        XCTAssertFalse(h.noticeSpoken?.contains("*") ?? true, "读屏会把星号念出来：\(h.noticeSpoken ?? "nil")")
    }

    func testNoNoticeWhenEverythingIsFine() {
        XCTAssertNil(hero().notice)
    }
}
