import XCTest
@testable import blindRun

/// 首页「置顶」的存取与分段（#694）。出错时首页仍是一页排版正常的卡片，只是少一张或多一张，所以钉在这里。
final class VolunteerHomePinnedLayoutTests: XCTestCase {
    typealias Layout = VolunteerHomePinnedLayout

    /// 从没编辑过（nil）= 默认五张全在；**空串 = 志愿者自己一张都不要**，不能当成没存过又全放回来。
    func testNilMeansDefaultButEmptyStringMeansNothingPinned() {
        XCTAssertEqual(Layout.decode(nil), [.duration, .streak, .rating, .recentRun, .badges])
        XCTAssertEqual(Layout.decode(""), [])
    }

    /// 认不出的丢掉、重复的只留第一个、空白容忍；其余照常，不让整块消失。
    func testDecodeDropsUnknownAndDuplicateNames() {
        XCTAssertEqual(Layout.decode("rating, nope,duration,rating,,badges"), [.rating, .duration, .badges])
    }

    func testEncodeRoundTrips() {
        let kinds: [VolunteerHomeCardKind] = [.badges, .duration, .streak]
        XCTAssertEqual(Layout.decode(Layout.encode(kinds)), kinds)
    }

    /// 连续陪跑与评分**相邻**才并排，谁在前谁在左；隔开了就各占一行。
    func testStreakAndRatingPairOnlyWhenAdjacent() {
        XCTAssertEqual(
            Layout.segments([.duration, .streak, .rating, .recentRun]),
            [.single(.duration), .pair(.streak, .rating), .single(.recentRun)]
        )
        XCTAssertEqual(Layout.segments([.rating, .streak]), [.pair(.rating, .streak)])
        XCTAssertEqual(
            Layout.segments([.streak, .duration, .rating]),
            [.single(.streak), .single(.duration), .single(.rating)]
        )
        XCTAssertEqual(Layout.segments([]), [])
    }

    /// 读屏的上移 / 下移：到头了原样返回，不越界、不丢卡。
    func testMoveUpAndDownStopAtTheEnds() {
        let kinds: [VolunteerHomeCardKind] = [.duration, .streak, .rating]
        XCTAssertEqual(Layout.move(.streak, by: -1, in: kinds), [.streak, .duration, .rating])
        XCTAssertEqual(Layout.move(.streak, by: 1, in: kinds), [.duration, .rating, .streak])
        XCTAssertEqual(Layout.move(.duration, by: -1, in: kinds), kinds)
        XCTAssertEqual(Layout.move(.rating, by: 1, in: kinds), kinds)
        XCTAssertEqual(Layout.move(.badges, by: 1, in: kinds), kinds, "没置顶的卡不该被插进来")
    }

    /// 存储写进 `appState.persistence`、再开一次读得回来；移出与排序都落盘。
    @MainActor
    func testStorePersistsPinAndMove() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }

        let store = VolunteerHomePinnedStore()
        store.configure(persistence: persistence)
        XCTAssertEqual(store.pinned, Layout.defaultOrder)
        store.unpin(.rating)
        store.move(.badges, by: -1)
        XCTAssertEqual(store.unpinned, [.rating])

        let reopened = VolunteerHomePinnedStore()
        reopened.configure(persistence: persistence)
        XCTAssertEqual(reopened.pinned, [.duration, .streak, .badges, .recentRun])
    }
}
