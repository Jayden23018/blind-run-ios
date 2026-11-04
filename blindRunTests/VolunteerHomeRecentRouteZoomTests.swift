import CoreLocation
import XCTest
@testable import blindRun

/// 首页最近陪跑卡的地图缩放（#694）。地图默认 15 级时，一圈 1 公里的路线在 140pt 高的扁图上下半截出框
/// （2026-11-04 真机），所以缩放按路线范围算。算错时界面不报错，只是路线出框或缩成一个点，只能在这里钉住。
final class VolunteerHomeRecentRouteZoomTests: XCTestCase {
    private let latitude = 39.93
    private let mapSize = CGSize(width: 345, height: 140)
    @MainActor private var padding: CGFloat { VolunteerProfileFirstScreen.routeMapPadding }

    private func route(northSouthMetres: Double, eastWestMetres: Double) -> [CLLocationCoordinate2D] {
        let dLat = northSouthMetres / 111_320
        let dLng = eastWestMetres / (111_320 * cos(latitude * .pi / 180))
        return [
            CLLocationCoordinate2D(latitude: latitude, longitude: 116.47),
            CLLocationCoordinate2D(latitude: latitude + dLat, longitude: 116.47 + dLng)
        ]
    }

    private func metresPerPoint(atZoom zoom: CGFloat) -> Double {
        156_543.03 * cos(latitude * .pi / 180) / pow(2, Double(zoom))
    }

    /// 南北 600 米、东西 400 米：扁图里是高度卡住。算出的级别要正好放得下（多放大半级就出框），
    /// 而且必须低于默认的 15 级 —— 默认值放不下，正是这条用例要守的缺陷。
    @MainActor
    func testTallRouteIsLimitedByTheMapHeight() {
        let zoom = VolunteerProfileFirstScreen.fittingZoomLevel(
            route(northSouthMetres: 600, eastWestMetres: 400), in: mapSize, padding: padding
        )
        let usableHeight = Double(mapSize.height - 2 * padding)
        XCTAssertGreaterThanOrEqual(metresPerPoint(atZoom: zoom) * usableHeight, 600 * 0.999, "算出的级别下路线放不进地图高度")
        XCTAssertLessThan(metresPerPoint(atZoom: zoom + 0.5) * usableHeight, 600, "级别算得太保守：再放大半级也放得下")
        XCTAssertLessThan(zoom, 15, "默认 15 级放不下这条路线，算出来的级别必须更小")
    }

    /// 东西 3 公里、南北 100 米：换成宽度卡住。
    @MainActor
    func testWideRouteIsLimitedByTheMapWidth() {
        let zoom = VolunteerProfileFirstScreen.fittingZoomLevel(
            route(northSouthMetres: 100, eastWestMetres: 3_000), in: mapSize, padding: padding
        )
        let usableWidth = Double(mapSize.width - 2 * padding)
        XCTAssertGreaterThanOrEqual(metresPerPoint(atZoom: zoom) * usableWidth, 3_000 * 0.999)
        XCTAssertLessThan(metresPerPoint(atZoom: zoom + 0.5) * usableWidth, 3_000)
    }

    /// 卡片里的地图只是装饰：不显示 / 不跟随定位、对读屏隐藏、蓝色主路线、起终点各一枚，缩放用上面算的级别。
    /// UI 测试构建默认关地图、截图用例不断言，这些参数被改了没有别的信号。
    @MainActor
    func testRecentRouteMapIsADecorativeRouteOnlyMap() {
        let coordinates = route(northSouthMetres: 600, eastWestMetres: 400)
        let map = VolunteerProfileFirstScreen.recentRouteMap(coordinates, size: mapSize)

        XCTAssertFalse(map.showsUserLocation)
        XCTAssertFalse(map.tracksUserLocation)
        XCTAssertFalse(map.animatesCenterChanges)
        XCTAssertTrue(map.isDecorative, "不是装饰时 MapViewWrapper 会合成一个读屏元素")
        XCTAssertEqual(map.polylines.count, 1)
        XCTAssertEqual(map.polylines.first?.isPrimary, true, "非主路线画成 4pt 灰线")
        XCTAssertEqual(map.annotations.map(\.kind), [.routeStart, .routeEnd])
        XCTAssertEqual(map.annotations.first?.coordinate.latitude, coordinates.first?.latitude)
        XCTAssertEqual(map.annotations.last?.coordinate.latitude, coordinates.last?.latitude)
        XCTAssertEqual(map.zoomLevel, VolunteerProfileFirstScreen.fittingZoomLevel(coordinates, in: mapSize, padding: padding))
    }

    /// 很短的路线不无限放大，停在 18 级；没有点时同样给 18 级，不崩。
    @MainActor
    func testTinyOrEmptyRouteStopsAtTheMaximumZoom() {
        let tiny = VolunteerProfileFirstScreen.fittingZoomLevel(
            route(northSouthMetres: 2, eastWestMetres: 2), in: mapSize, padding: padding
        )
        XCTAssertEqual(tiny, 18)
        XCTAssertEqual(VolunteerProfileFirstScreen.fittingZoomLevel([], in: mapSize, padding: padding), 18)
    }
}
