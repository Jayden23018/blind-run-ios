import XCTest
@testable import blindRun

/// 陪跑员 v8 卡片页（#972）的纯逻辑：跑完了彩色卡的数从哪来、副标题、响铃卡可不可点、彩色卡不念目标进度。
///
/// 输入都挑在「分支被打乱」会给出不同结果的地方：轨迹与订单两份数字故意不相等（先后顺序调换就会拿错那一份）；
/// 轨迹有统计但没里程（被当成「有数」就不会退回订单）；订单实跑里程为 0（当成真数就会显示 0.00）。
final class VolunteerRunFinishedSummaryTests: XCTestCase {
    private func order(actualMeters: Int? = nil, actualSeconds: Int? = nil, together: Int? = nil) -> OrderDetailResponse {
        var order = OrderDetailResponse.preview(status: .completed)
        order.actualDistanceMeters = actualMeters
        order.actualDurationSeconds = actualSeconds
        order.completedTogetherCount = together
        return order
    }

    private func track(distance: Double?, points: [String] = []) -> OrderTrackResponse {
        OrderTrackResponse(
            status: .completed,
            volunteerTrack: [],
            volunteerStats: TrackStats(distanceMeters: nil, durationSeconds: nil, avgPaceSecPerKm: nil),
            blindTrack: points.map { TrackPoint(lat: 22.5, lng: 113.9, recordedAt: $0) },
            blindStats: TrackStats(distanceMeters: distance, durationSeconds: 2_520, avgPaceSecPerKm: 484)
        )
    }

    // MARK: 彩色卡的数

    func testStatsPreferTrackWhenItHasDistance() {
        let stats = VolunteerRunFinishedSummary.stats(
            order: order(actualMeters: 9_999, actualSeconds: 100),
            track: track(distance: 5_200)
        )
        XCTAssertEqual(stats?.distanceMeters, 5_200)
        XCTAssertEqual(stats?.avgPaceSecPerKm, 484)
    }

    func testStatsFallBackToOrderWhenTrackHasNoDistance() {
        let stats = VolunteerRunFinishedSummary.stats(
            order: order(actualMeters: 5_120, actualSeconds: 2_360),
            track: track(distance: nil)
        )
        XCTAssertEqual(stats?.distanceMeters, 5_120)
        XCTAssertEqual(stats?.durationSeconds, 2_360)
        // 退回订单数字时不算配速。
        XCTAssertNil(stats?.avgPaceSecPerKm)
    }

    func testStatsHaveNoDistanceWhenNeitherSourceHasOne() {
        XCTAssertNil(VolunteerRunFinishedSummary.stats(order: order(), track: nil))
        // 订单实跑里程 0 不当真数：彩色卡要走「稍等一下」，不显示 0.00。
        let zero = VolunteerRunFinishedSummary.stats(order: order(actualMeters: 0, actualSeconds: 60), track: track(distance: nil))
        XCTAssertNil(zero?.distanceMeters)
    }

    // MARK: 副标题

    func testSubtitleShowsStartAndEndFromRunnerTrack() throws {
        let start = "2026-11-12T07:02:00"
        let end = "2026-11-12T07:44:00"
        let now = try XCTUnwrap("2026-11-12T09:00:00".backendTimestamp)
        let subtitle = VolunteerRunFinishedSummary.subtitle(
            order: order(together: 3),
            track: track(distance: 5_200, points: [start, "2026-11-12T07:20:00", end]),
            now: now
        )
        let endClock = DateFormatter.aidRunDisplayClock.string(from: try XCTUnwrap(end.backendTimestamp))
        let startText = try XCTUnwrap(RunPlanFormat.shortStart(start, now: now))
        XCTAssertEqual(subtitle, "和李*一起 · \(startText)–\(endClock)")
        XCTAssertTrue(subtitle.contains("今天"), subtitle)
    }

    func testSubtitleFallsBackToTogetherCountWithoutTwoTrackPoints() {
        let subtitle = VolunteerRunFinishedSummary.subtitle(
            order: order(together: 3),
            track: track(distance: 5_200, points: ["2026-11-12T07:02:00"])
        )
        XCTAssertEqual(subtitle, "和李*一起 · 第 3 次")
    }

    func testSubtitleOmitsCountForFirstRunTogether() {
        XCTAssertEqual(VolunteerRunFinishedSummary.subtitle(order: order(together: 1), track: nil), "和李*一起")
    }

    // MARK: 响铃卡

    func testRingCardTappableOnlyWhenSessionValidAndNotRinging() {
        XCTAssertTrue(VolunteerRunRingCard.isTappable(isRingEnabled: true, isRinging: false))
        XCTAssertFalse(VolunteerRunRingCard.isTappable(isRingEnabled: true, isRinging: true))
        XCTAssertFalse(VolunteerRunRingCard.isTappable(isRingEnabled: false, isRinging: false))
    }

    // MARK: 彩色卡不念目标进度

    func testHeroCardLabelLeavesGoalToPlanCard() {
        let order = OrderDetailResponse.preview(status: .inProgress, plannedDistanceMeters: 5_000)
        let stats = TrackStats(distanceMeters: 2_400, durationSeconds: 1_112, avgPaceSecPerKm: 463)
        let hero = VolunteerRunningHero.make(order: order, stats: stats, isPeerLocationFresh: true, isPeerAlertAcknowledged: false)
        XCTAssertTrue(hero.accessibilityLabel.contains("目标"), hero.accessibilityLabel)
        XCTAssertFalse(hero.cardAccessibilityLabel.contains("目标"), hero.cardAccessibilityLabel)
        XCTAssertTrue(hero.cardAccessibilityLabel.contains("已跑"), hero.cardAccessibilityLabel)
    }
}
