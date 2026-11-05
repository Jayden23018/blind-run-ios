import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class OrderEndLocationTests: XCTestCase, BlindRunTestSupport {
    // MARK: - 终点在状态流转中不许丢

    /// `replacingStatus` 是每一条 WebSocket 状态变更的必经之路（7 个调用点），
    /// 而它是全参构造 —— 漏传一个字段不会报错，只会让终点在**第一次状态更新之后**静默消失：
    /// 志愿者详情页上一秒有「结束地点」下一秒没有，而没人会去查一个「本来就可能为空」的字段。
    /// 这是本仓库记过案的那一类静默降级。
    func testReplacingStatusKeepsTheEndLocation() {
        let order = makeOrder(
            orderId: 9_001,
            status: .pendingAccept,
            endAddress: "上海市杨浦区五角场",
            endLatitude: 31.2989,
            endLongitude: 121.5036
        )

        let updated = order.replacingStatus(with: .driverEnRoute)

        XCTAssertEqual(updated.status, .driverEnRoute)
        XCTAssertEqual(updated.endAddress, "上海市杨浦区五角场", "状态流转不得抹掉终点")
        XCTAssertEqual(updated.endLatitude, 31.2989)
        XCTAssertEqual(updated.endLongitude, 121.5036)
    }

    /// 展示口径：没有终点整行不渲染；有地名没坐标要把「没定位到」标出来 ——
    /// 志愿者据此决定是导航过去还是当面问。
    func testEndAddressForDisplayMarksUnlocatedPlacesAndHidesEmptyOnes() {
        let none = makeOrder(orderId: 9_002, status: .inProgress)
        let located = makeOrder(
            orderId: 9_003, status: .inProgress,
            endAddress: "上海市杨浦区五角场", endLatitude: 31.2989, endLongitude: 121.5036
        )
        let unlocated = makeOrder(orderId: 9_004, status: .inProgress, endAddress: "老王家门口")

        XCTAssertNil(none.endAddressForDisplay, "没说终点就整行不渲染，不许摆一句「未指定」")
        XCTAssertEqual(located.endAddressForDisplay, "上海市杨浦区五角场")
        XCTAssertEqual(unlocated.endAddressForDisplay, "老王家门口（未定位到）")
    }
}
