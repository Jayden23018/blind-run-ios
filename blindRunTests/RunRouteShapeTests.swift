import XCTest
@testable import blindRun

/// 纯 `Path` 路线缩略图（`RunRouteShape`）的投影与「画不画得出线」。
/// 从 `RunRecordHistoryTests` 挪出：跑步记录列表 11-07 起改用真实高德小地图（#823），
/// 这个形状只剩陪跑员首页与跑步数据页在画；列表小地图仍用 `hasExtent` 判要不要画图标。
final class RunRouteShapeTests: XCTestCase {
    /// 北在上、东在右、等比缩放、落在框内。经度要乘 cos(纬度)：
    /// 深圳（22.5°）一个「正方形」的路线在经度上跨度更大，不校正就会被画成扁长方形。
    func testThumbnailProjectionKeepsNorthUpAndTheShapeSquare() {
        let lat = 22.5
        let side = 0.001
        let lngSide = side / cos(lat * .pi / 180)
        let points = [
            RunLatLng(lat: lat, lng: 113.9),
            RunLatLng(lat: lat, lng: 113.9 + lngSide),
            RunLatLng(lat: lat + side, lng: 113.9 + lngSide),
            RunLatLng(lat: lat + side, lng: 113.9),
        ]
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)

        let projected = RunRouteShape.project(points, into: rect)

        XCTAssertEqual(projected.count, 4)
        XCTAssertLessThan(projected[2].y, projected[1].y, "北边的点应该在上面")
        XCTAssertGreaterThan(projected[1].x, projected[0].x, "东边的点应该在右边")
        let width = projected.map(\.x).max()! - projected.map(\.x).min()!
        let height = projected.map(\.y).max()! - projected.map(\.y).min()!
        XCTAssertEqual(width, height, accuracy: 0.5, "按米是正方形，画出来也该是正方形")
        XCTAssertTrue(projected.allSatisfy { rect.insetBy(dx: -0.01, dy: -0.01).contains($0) })
    }

    func testThumbnailProjectionOfASinglePointIsTheCentre() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        XCTAssertEqual(RunRouteShape.project([RunLatLng(lat: 22.5, lng: 113.9)], into: rect), [CGPoint(x: 20, y: 20)])
        XCTAssertEqual(RunRouteShape.project([], into: rect), [])
    }

    /// 没有点、一个点、只有定位抖动（只跑了几秒）都画不出有意义的线，缩略图改画图标。
    /// 阈值 10 米：取 5 米（应判否）和 20 米（应判是）两侧，换成「点不重合就画」的实现会在 5 米那条红。
    func testThumbnailDrawsARouteOnlyWhenItSpansAtLeastTenMetres() {
        let a = RunLatLng(lat: 22.5, lng: 113.9)
        XCTAssertFalse(RunRouteShape.hasExtent([]))
        XCTAssertFalse(RunRouteShape.hasExtent([a]))
        XCTAssertFalse(RunRouteShape.hasExtent([a, a, a]))
        XCTAssertFalse(RunRouteShape.hasExtent([a, RunLatLng(lat: 22.5 + 5.0 / 111_000, lng: 113.9)]), "5 米是抖动")
        XCTAssertTrue(RunRouteShape.hasExtent([a, RunLatLng(lat: 22.5 + 20.0 / 111_000, lng: 113.9)]), "20 米是路线")
    }
}
