import XCTest
@testable import blindRun

/// #825 首页同时显示几张未完成预约。
final class BlindHomeUpcomingOrdersTests: XCTestCase {

    func testActiveOrderStaysFirstAndOthersFollowEarliestFirst() {
        // 列表里那份 1 号是旧的（还在匹配），`/active` 给的是新的（已确认）：要用新的。
        let active = OrderDetailResponse.preview(orderId: 1, status: .scheduledConfirmed, plannedStart: "2026-11-08T07:00:00")
        let mine: [OrderDetailResponse] = [
            // 不能用 `.preview(plannedStart: nil)`：工厂会把 nil 补成「明天 7:00」，用例随运行日期变红（#959）。
            Self.orderWithoutPlannedStart(orderId: 4, status: .pendingMatch),
            .preview(orderId: 3, status: .pendingMatch, plannedStart: "2026-11-15T06:30:00"),
            .preview(orderId: 1, status: .pendingMatch, plannedStart: "2026-11-08T07:00:00"),
            .preview(orderId: 9, status: .completed, plannedStart: "2026-11-01T07:00:00"),
            .preview(orderId: 2, status: .pendingMatch, plannedStart: "2026-11-12T18:30:00"),
        ]

        let merged = BlindHomeUpcomingOrders.merge(active: active, mine: mine)

        XCTAssertEqual(merged.map(\.orderId), [1, 2, 3, 4], "终态不进；有计划开始的按时间先后，没有的排最后")
        XCTAssertEqual(merged.first?.status, .scheduledConfirmed, "同号用 `/active` 那份")
    }

    func testOthersStillShowWhenTheEarliestJustFinished() {
        let mine: [OrderDetailResponse] = [.preview(orderId: 2, status: .pendingMatch, plannedStart: "2026-11-12T18:30:00")]

        XCTAssertEqual(BlindHomeUpcomingOrders.merge(active: nil, mine: mine).map(\.orderId), [2])
    }

    func testAnnouncementSaysHowManyOnlyWhenMoreThanOne() {
        XCTAssertEqual(BlindHomeUpcomingOrders.countAnnouncement(count: 1), "", "一张时播报与改版前逐字相同")
        XCTAssertEqual(BlindHomeUpcomingOrders.countAnnouncement(count: 3), "你有 3 张预约。最近一张：")
    }

    func testCompactCardIsReadTimeFirst() {
        let order = OrderDetailResponse.preview(
            orderId: 2, status: .pendingMatch, startAddress: "香蜜湖体育中心", plannedStart: "2026-11-12T18:30:00"
        )

        let content = BlindHomeCompactOrderContent(order: order, size: .third)

        let time = order.plannedStartForAnnouncement ?? "<无时间>"
        XCTAssertTrue(content.accessibilityLabel.hasPrefix(time), content.accessibilityLabel)
        XCTAssertTrue(content.accessibilityLabel.contains("出发地 香蜜湖体育中心"), content.accessibilityLabel)
        XCTAssertTrue(content.accessibilityLabel.hasSuffix("正在匹配陪跑员"), content.accessibilityLabel)
    }

    func testThirdSizeFoldsThePartnerIntoTheCaption() {
        let order = OrderDetailResponse.preview(orderId: 1, status: .scheduledConfirmed, volunteerName: "张*")

        XCTAssertNil(BlindHomeCompactOrderContent(order: order, size: .third).partnerText)
        XCTAssertTrue(BlindHomeCompactOrderContent(order: order, size: .third).caption.hasSuffix("陪跑员 张*"))
        XCTAssertEqual(BlindHomeCompactOrderContent(order: order, size: .half).partnerText, "陪跑员 张*")
    }

    private static func orderWithoutPlannedStart(orderId: Int64, status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "测试出发点",
            startLatitude: 39.9,
            startLongitude: 116.4,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: nil,
            plannedEnd: nil,
            blindName: "测试盲人",
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: 60,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}
