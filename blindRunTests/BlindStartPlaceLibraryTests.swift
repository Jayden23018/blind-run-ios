import XCTest
@testable import blindRun

/// 「默认出发地点」资料库（#817）：收藏图标按地名自动配、距离副标题的写法。
@MainActor
final class BlindStartPlaceLibraryTests: XCTestCase {

    // MARK: - 图标按地名配

    func testEachKeywordPicksItsIcon() {
        let cases: [(String, BlindStartPlaceIcon.Kind)] = [
            ("滨海公园南门", .park),
            ("河畔绿道入口", .park),
            ("科技园地铁 A 口", .metro),
            ("深圳北站", .metro),
            ("家附近操场", .track),
            ("市体育中心", .track),
            ("城南学校", .school),
            ("城南书院", .school),
        ]
        for (title, expected) in cases {
            XCTAssertEqual(BlindStartPlaceIcon.kind(forTitle: title), expected, title)
        }
    }

    func testUnmatchedTitleFallsBackToThePin() {
        XCTAssertEqual(BlindStartPlaceIcon.kind(forTitle: "市民中心"), .other)
        XCTAssertEqual(BlindStartPlaceIcon.favorite(title: "市民中心").symbol, "mappin")
    }

    /// 两类关键词都命中时按定稿列出的顺序取前一类：「公园站」是公园，不是地铁。
    func testFirstMatchingRuleWins() {
        XCTAssertEqual(BlindStartPlaceIcon.kind(forTitle: "公园站"), .park)
        XCTAssertEqual(BlindStartPlaceIcon.kind(forTitle: "体育学校"), .track)
    }

    // MARK: - 距离

    func testDistanceUnderTenKilometresKeepsOneDecimal() {
        XCTAssertEqual(BlindStartPlaceDistance.text(meters: 3_140), "3.1 公里")
        XCTAssertEqual(BlindStartPlaceDistance.text(meters: 600), "0.6 公里")
    }

    /// 几十米不写「0.0 公里」：最少写 0.1。
    func testVeryShortDistanceNeverReadsZero() {
        XCTAssertEqual(BlindStartPlaceDistance.text(meters: 30), "0.1 公里")
    }

    func testTenKilometresAndBeyondAreRounded() {
        XCTAssertEqual(BlindStartPlaceDistance.text(meters: 12_600), "13 公里")
    }

    func testSpokenDistanceSaysFromYou() {
        XCTAssertEqual(BlindStartPlaceDistance.spoken(meters: 3_140), "离你 3.1 公里")
    }

    /// 拿不到定位时不写距离（定稿）。
    func testNoDeviceLocationMeansNoDistance() {
        let place = ResolvedPlace(
            id: "p", title: "滨海公园南门", addressText: "",
            latitude: 22.5, longitude: 113.9, source: .manual
        )
        XCTAssertNil(BlindStartPlaceDistance.meters(from: nil, to: place))
    }
}
