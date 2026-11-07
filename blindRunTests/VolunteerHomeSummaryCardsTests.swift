import XCTest
@testable import blindRun

/// 陪跑员首页 v3 卡片的取值（#694）。这些取舍出错时屏幕上仍是一张排版正常的卡片，
/// 所以每条都挑「对的实现与错的实现会得出不同结果」的输入。
final class VolunteerHomeSummaryCardsTests: XCTestCase {

    // MARK: - 星级进度

    /// 没到一星时说「一星 1 / 100 小时」：名字是**下一档**，不是当前档（当前是「尚未达到一星」）。
    func testStarProgressNamesTheNextStarAndItsTarget() {
        let progress = VolunteerHomeStarProgress(VolunteerStarLevelDto(current: 0, currentHours: 1, nextTarget: 100))
        XCTAssertEqual(progress.label, "一星 1 / 100 小时")
        XCTAssertEqual(progress.fraction, 0.01, accuracy: 0.0001)

        let second = VolunteerHomeStarProgress(VolunteerStarLevelDto(current: 1, currentHours: 150, nextTarget: 300))
        XCTAssertEqual(second.label, "二星 150 / 300 小时", "已到一星时要说下一档「二星」")
    }

    /// 五星之后没有下一档：说当前星级，进度满格，不除以 nil。
    func testStarProgressAtTheTopTierIsFull() {
        let top = VolunteerHomeStarProgress(VolunteerStarLevelDto(current: 5, currentHours: 1_600, nextTarget: nil))
        XCTAssertEqual(top.label, "五星 · 1600 小时")
        XCTAssertEqual(top.fraction, 1)
    }

    // MARK: - 半宽卡

    /// 有火花：连续周数 + 最好周数，读屏念搭档名时去掉掩码星号。
    func testLeftCardShowsTheStreakWhenOneIsLit() {
        let card = VolunteerHomeHalfCard.left(
            streak: PartnerStreakDisplay(currentWeeks: 3, bestWeeks: 7),
            streakPartnerName: "王*",
            favoritedByCount: 2
        )
        XCTAssertEqual(card.kind, .streak)
        XCTAssertEqual(card.value, "3")
        XCTAssertEqual(card.unit, "周")
        XCTAssertEqual(card.caption, "最好 7 周")
        XCTAssertTrue(card.hasDestination)
        XCTAssertTrue(card.spoken.contains("王"), card.spoken)
        XCTAssertFalse(card.spoken.contains("*"), "掩码星号被念出来了：\(card.spoken)")
    }

    /// 🔴 火花开关后端默认关着：没有火花时**退到固定搭档人数**，不画「连续陪跑 --」。
    /// 有人收藏时必须显示人数 —— 退成 `--` 的实现在这条上会红。
    func testLeftCardFallsBackToPartnersWhenNoStreakIsLit() {
        let withPartners = VolunteerHomeHalfCard.left(streak: nil, streakPartnerName: nil, favoritedByCount: 2)
        XCTAssertEqual(withPartners.kind, .partners)
        XCTAssertEqual(withPartners.title, VolunteerProfileCopy.partnersCaption)
        XCTAssertEqual(withPartners.value, "2")
        XCTAssertTrue(withPartners.hasDestination, "固定搭档有现成页面，要有箭头")

        let none = VolunteerHomeHalfCard.left(streak: nil, streakPartnerName: nil, favoritedByCount: 0)
        XCTAssertEqual(none.value, "--")
        XCTAssertFalse(none.spoken.contains("0"), none.spoken)
        XCTAssertFalse(none.spoken.contains("-"), none.spoken)
    }

    /// 评分卡**没有去处**（仓库里没有评价列表页），所以不画箭头、不可点。
    func testRatingCardHasNoDestinationAndNeverInventsANumber() {
        let empty = VolunteerHomeHalfCard.rating(average: nil, total: nil)
        XCTAssertFalse(empty.hasDestination)
        XCTAssertEqual(empty.value, "--")
        XCTAssertEqual(empty.caption, VolunteerProfileCopy.ratingCardEmptyCaption)
        XCTAssertFalse(empty.spoken.contains("-"), empty.spoken)

        let rated = VolunteerHomeHalfCard.rating(average: 4.94, total: 32)
        XCTAssertEqual(rated.value, "4.9")
        XCTAssertEqual(rated.caption, "32 条评价")

        let zeroCount = VolunteerHomeHalfCard.rating(average: 5, total: 0)
        XCTAssertFalse(zeroCount.caption.contains("0"), "不该显示 0 条：\(zeroCount.caption)")
    }

    // MARK: - 最近陪跑

    private static let spreadRoute = [
        RunLatLng(lat: 39.9900, lng: 116.3900),
        RunLatLng(lat: 39.9930, lng: 116.3950),
        RunLatLng(lat: 39.9960, lng: 116.3920)
    ]

    private static func item(
        orderId: Int64 = 1,
        finishedAt: String = "2026-11-03T07:42:00",
        place: String? = "奥林匹克森林公园",
        partnerName: String? = "王*",
        distanceM: Int? = 5_000,
        thumbnail: [RunLatLng]? = spreadRoute
    ) -> RunHistoryItem {
        RunHistoryItem(
            orderId: orderId,
            finishedAt: finishedAt,
            place: place,
            partnerName: partnerName,
            distanceM: distanceM,
            thumbnail: thumbnail
        )
    }

    func testRecentRunCardShowsDistancePartnerPlaceAndRoute() {
        let content = VolunteerHomeRecentRunContent(item: Self.item())
        XCTAssertEqual(content.dateText, "11月3日")
        XCTAssertEqual(content.distanceText, "5")
        XCTAssertEqual(content.detailText, "和王* · 奥林匹克森林公园")
        XCTAssertEqual(content.route, Self.spreadRoute)
        XCTAssertTrue(content.spoken.contains("和王"), content.spoken)
        XCTAssertFalse(content.spoken.contains("*"), "掩码星号被念出来了：\(content.spoken)")
    }

    /// 🔴 `thumbnail` 为 null、空，或点全部重合（只跑了几秒）时**不画图** —— 不画占位图标（#694）。
    func testRecentRunCardDrawsNoRouteWithoutAUsableThumbnail() {
        XCTAssertNil(VolunteerHomeRecentRunContent(item: Self.item(thumbnail: nil)).route)
        XCTAssertNil(VolunteerHomeRecentRunContent(item: Self.item(thumbnail: [])).route)
        let stacked = Array(repeating: RunLatLng(lat: 39.99, lng: 116.39), count: 5)
        XCTAssertNil(VolunteerHomeRecentRunContent(item: Self.item(thumbnail: stacked)).route)
    }

    /// 缺什么就少画什么，不编：没有里程不显示「0 公里」，对方注销时副标题只剩地点。
    func testRecentRunCardOmitsWhatTheContractDidNotSend() {
        let content = VolunteerHomeRecentRunContent(item: Self.item(partnerName: nil, distanceM: nil))
        XCTAssertNil(content.distanceText)
        XCTAssertEqual(content.detailText, "奥林匹克森林公园")
        XCTAssertFalse(content.spoken.contains("公里"), content.spoken)

        let bare = VolunteerHomeRecentRunContent(item: Self.item(finishedAt: "not-a-date", place: nil, partnerName: nil))
        XCTAssertNil(bare.detailText)
        XCTAssertNil(bare.dateText, "解析不了的时间不能拿今天顶上")
    }

    /// 本月为空才退上月；本月有就不看上月（取反的实现在第二条上会红）。
    func testRecentRunPicksThisMonthFirstThenLastMonth() {
        let thisMonth = Self.item(orderId: 10)
        let lastMonth = Self.item(orderId: 20)
        XCTAssertEqual(VolunteerHomeRecentRunContent.pick(current: [], previous: [lastMonth])?.orderId, 20)
        XCTAssertEqual(VolunteerHomeRecentRunContent.pick(current: [thisMonth], previous: [lastMonth])?.orderId, 10)
        XCTAssertNil(VolunteerHomeRecentRunContent.pick(current: [], previous: []))
        XCTAssertNil(VolunteerHomeRecentRunContent.pick(current: [], previous: nil))
    }

    // MARK: - 文案红线

    /// 首页 v3 新增的文案过同一张禁用词表（民政部令第 67 号、不折算金额、不做月度目标、不催促），
    /// 理由见 `VolunteerProfileFirstScreenTests.testFirstScreenCopyNeverClaimsCredentialsOrPushesForMoreRuns`。
    func testHomeV3CopyNeverClaimsCredentialsOrPushesForMoreRuns() {
        let strings = [
            VolunteerProfileCopy.durationCardTitle,
            VolunteerProfileCopy.durationCardRunsLine(24),
            VolunteerProfileCopy.streakCardTitle,
            VolunteerProfileCopy.streakBestCaption(7),
            VolunteerProfileCopy.partnersCardCaption,
            VolunteerProfileCopy.partnersCardEmptyCaption,
            VolunteerProfileCopy.partnersCardHint,
            VolunteerProfileCopy.ratingCardEmptyCaption,
            VolunteerProfileCopy.recentLinkTitle,
            VolunteerProfileCopy.recentCardTitle,
            VolunteerProfileCopy.recentCardHint,
            VolunteerProfileCopy.recentNoneLately,
            VolunteerProfileCopy.recentLoadFailure,
            VolunteerProfileCopy.recentRetry,
            VolunteerAvailabilityCopy.keepAppOpenNote,
            VolunteerDispatchHubCopy.nextSectionTitle,
            VolunteerDispatchHubCopy.laterRowLabel,
            VolunteerDispatchHubCopy.statusPendingTitle,
            VolunteerDispatchHubCopy.statusLoadingMessage,
            VolunteerDispatchHubCopy.reloadTitle
        ]
        for text in strings {
            for word in VolunteerProfileFirstScreenTests.bannedCopyWords {
                XCTAssertFalse(text.contains(word), "首页 v3 文案出现禁用词「\(word)」：\(text)")
            }
        }
    }
}
