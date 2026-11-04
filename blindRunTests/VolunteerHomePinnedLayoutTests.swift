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

    /// 非空却一个都认不出（将来改了卡名、旧值全部失效）⇒ 退回默认五张，不让首页置顶整块变空。
    func testDecodeFallsBackToDefaultWhenNothingIsRecognised() {
        XCTAssertEqual(Layout.decode("foo,bar"), Layout.defaultOrder)
        XCTAssertEqual(Layout.decode(","), [], "只有分隔符等同空串：志愿者一张都不要")
    }

    /// 一张都没置顶 ⇒ 说明「点编辑」；新人态只置顶了连续陪跑 / 评分 ⇒ 另一句说明，不能是一片空白。
    func testNoticeCoversNothingPinnedAndNewcomerWithOnlyHalfCards() {
        XCTAssertEqual(Layout.notice(pinned: [], visible: []), .nothingPinned)

        let newcomerOnlyHalfCards = Layout.visibleSegments([.streak, .rating], showsHalfCards: false)
        XCTAssertEqual(newcomerOnlyHalfCards, [])
        XCTAssertEqual(Layout.notice(pinned: [.streak, .rating], visible: newcomerOnlyHalfCards), .waitingForFirstRun)

        let regular = Layout.visibleSegments([.streak, .rating], showsHalfCards: true)
        XCTAssertEqual(regular, [.pair(.streak, .rating)])
        XCTAssertNil(Layout.notice(pinned: [.streak, .rating], visible: regular))
    }

    /// 新人态只滤掉连续陪跑 / 评分，其余照常；滤掉之后两边的卡不会因此凑成一对。
    func testNewcomerHidesOnlyTheHalfCards() {
        XCTAssertEqual(
            Layout.visibleSegments([.rating, .duration, .streak, .badges], showsHalfCards: false),
            [.single(.duration), .single(.badges)]
        )
    }

    /// 置顶是这台手机上的显示偏好：登出（`reset()` 只清 `AppStatePersistenceKeys.all`）不能把它清掉。
    func testPinnedPreferenceSurvivesLogout() {
        XCTAssertFalse(AppStatePersistenceKeys.all.contains(AppConstants.UserDefaultsKeys.volunteerHomePinnedCards))
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
