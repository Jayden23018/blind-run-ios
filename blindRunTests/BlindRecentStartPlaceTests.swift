import XCTest
@testable import blindRun

/// 「添加常用地点」页的最近跑过的地点（#807）：只取已完成的单、新的在前、同名只留最近一次、最多 5 个。
final class BlindRecentStartPlaceTests: XCTestCase {
    private func order(_ id: Int64, _ status: RunOrderStatus, _ address: String?, _ start: String) -> OrderDetailResponse {
        .preview(orderId: id, status: status, startAddress: address, plannedStart: start)
    }

    func testKeepsOnlyCompletedOrdersWithAnAddress() {
        let places = BlindRecentStartPlace.from([
            order(1, .completed, "深圳湾公园 南门", "2026-11-03T07:00:00"),
            order(2, .cancelled, "大沙河生态长廊", "2026-11-04T07:00:00"),
            order(3, .completed, "  ", "2026-11-05T07:00:00"),
        ])

        XCTAssertEqual(places.map(\.place.title), ["深圳湾公园 南门"], "取消的单与没有地名的单都不该出现")
    }

    func testNewestFirstAndADuplicateAddressKeepsItsLatestRun() {
        let places = BlindRecentStartPlace.from([
            order(1, .completed, "科技园地铁站 A 口", "2026-10-01T07:00:00"),
            order(2, .completed, "深圳湾公园 南门", "2026-10-20T07:00:00"),
            order(3, .completed, "科技园地铁站 A 口", "2026-11-03T07:00:00"),
        ])

        XCTAssertEqual(places.map(\.place.title), ["科技园地铁站 A 口", "深圳湾公园 南门"])
        // 留下的必须是 11-03 那次，不是 10-01：按「先出现先留」去重会留下旧的那次。
        XCTAssertEqual(places.first?.usedOnText, "11月3日跑过")
    }

    func testListsAtMostFive() {
        let orders = (1...7).map { index in
            order(Int64(index), .completed, "地点\(index)", "2026-10-0\(index)T07:00:00")
        }

        let places = BlindRecentStartPlace.from(orders)

        XCTAssertEqual(places.count, 5)
        XCTAssertEqual(places.first?.place.title, "地点7", "最新的一次应排第一")
    }
}
