import XCTest
@testable import blindRun

final class BlindHomeBelowCardTests: XCTestCase {
    private let summary = BlindHomeRunSummary(monthTitle: "11月", runs: 3, distanceM: 12_400, spokenText: "11月跑了 3 次。")
    private let place = ResolvedPlace(
        id: "a", title: "朝阳公园南门", addressText: "朝阳公园南门", latitude: 39.9, longitude: 116.4, source: .manual
    )

    func testUnverifiedRunnerOnlySeesIdentityRowEvenWithHistory() {
        let content = BlindHomeBelowCard.resolve(isIdentityVerified: false, runSummary: summary, startPlace: place)

        XCTAssertTrue(content.showsIdentityRow)
        XCTAssertNil(content.runSummary)
        XCTAssertNil(content.startPlace)
    }

    func testVerifiedNewRunnerHasNothingBelowTheCard() {
        let content = BlindHomeBelowCard.resolve(isIdentityVerified: true, runSummary: nil, startPlace: nil)

        XCTAssertTrue(content.isEmpty)
    }

    func testReturningRunnerSeesSummaryAndPlace() {
        let content = BlindHomeBelowCard.resolve(isIdentityVerified: true, runSummary: summary, startPlace: place)

        XCTAssertFalse(content.showsIdentityRow)
        XCTAssertEqual(content.runSummary, summary)
        XCTAssertEqual(content.startPlace, place)
    }

    func testZeroRunsProducesNoSummary() {
        XCTAssertNil(BlindHomeRunSummary(monthTitle: "11月", runs: 0, distanceM: nil, spokenText: ""))
    }

    func testSummaryWithoutDistanceOnlyStatesRuns() {
        let summary = BlindHomeRunSummary(monthTitle: "11月", runs: 2, distanceM: nil, spokenText: "")

        XCTAssertEqual(summary?.headline, "2 次")
        XCTAssertEqual(summary?.period, "11月已跑")
    }
}
