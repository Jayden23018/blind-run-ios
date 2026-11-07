import XCTest
@testable import blindRun

/// 跑步记录照健身重做（#823）里能脱开视图钉住的两件事：通栏地图的路线取景框、配速竖条的距离区间。
final class RunRecordFitnessLayoutTests: XCTestCase {

    /// 负责人 11-07 第 11 条：路线不压返回键、右上圆钮、头部。
    /// 上 = 安全区顶 + 圆钮一行 64 + 16，下 = 头部高度 + 16，左右 28，四边再让出半个标注（12）。
    /// 有圆钮和没圆钮取一对：去掉「圆钮那一行」的实现会让两者相等。
    func testRouteInsetsClearTheButtonsAndTheHeader() {
        let withButtons = RunRecordHeroLayout.routeInsets(topInset: 103, hasTopButtons: true, headerHeight: 180)
        XCTAssertEqual(withButtons.top, 103 + 64 + 16 + 12)
        XCTAssertEqual(withButtons.bottom, 180 + 16 + 12)
        XCTAssertEqual(withButtons.left, 28 + 12)
        XCTAssertEqual(withButtons.right, 28 + 12)

        let volunteer = RunRecordHeroLayout.routeInsets(topInset: 103, hasTopButtons: false, headerHeight: 180)
        XCTAssertEqual(volunteer.top, 103 + 16 + 12, "陪跑员端右上没有圆钮，不多让那一行")
    }

    /// 大字号头部变高，取景框下沿跟着抬：路线不会钻到头部下面。
    func testRouteInsetsFollowTheMeasuredHeaderHeight() {
        let normal = RunRecordHeroLayout.routeInsets(topInset: 103, hasTopButtons: true, headerHeight: 180)
        let large = RunRecordHeroLayout.routeInsets(topInset: 103, hasTopButtons: true, headerHeight: 420)
        XCTAssertEqual(large.bottom - normal.bottom, 240)
    }

    /// 负责人 11-07 第二轮第 5 条：往上滑地图先模糊、再被页底色盖住；回到顶部完全不遮；往下拉过头也不遮。
    /// 取 0.4（模糊已过半、变暗才开始一点）：把两条曲线写成同一条、或去掉「先模糊后变暗」的实现在这里结果不同。
    func testMapVeilBlursFirstThenCoversAndClearsAtTheTop() {
        let top = RunRecordHeroLayout.veil(scrolled: 0, fadeDistance: 500)
        XCTAssertEqual(top.blur, 0)
        XCTAssertEqual(top.dim, 0)

        let pulled = RunRecordHeroLayout.veil(scrolled: -80, fadeDistance: 500)
        XCTAssertEqual(pulled.blur, 0, "往下拉过头不加遮罩")

        let partway = RunRecordHeroLayout.veil(scrolled: 200, fadeDistance: 500)
        XCTAssertEqual(partway.blur, 0.8, accuracy: 0.0001)
        XCTAssertEqual(partway.dim, 0.2, accuracy: 0.0001)

        let past = RunRecordHeroLayout.veil(scrolled: 900, fadeDistance: 500)
        XCTAssertEqual(past.blur, 1)
        XCTAssertEqual(past.dim, 1, "滑过地图高度时地图被页底色完全盖住")
    }

    /// 每根竖条占「上一个采样 → 本采样」那段距离，乱序采样按距离排好；第一根从 0 起。
    func testPaceBarsSpanTheDistanceSinceThePreviousSample() {
        let samples = [
            RunPaceSample(distanceM: 200, paceSecPerKm: 380),
            RunPaceSample(distanceM: 100, paceSecPerKm: 360),
            RunPaceSample(distanceM: 300, paceSecPerKm: 400)
        ]
        let bars = RunPaceChart.bars(samples)
        XCTAssertEqual(bars.map(\.sample.distanceM), [100, 200, 300])
        XCTAssertEqual(bars.map(\.endKm), [0.1, 0.2, 0.3])
        XCTAssertEqual(bars[0].startKm, 0.002, accuracy: 0.0001, "第一根从 0 起，留 2% 的缝")
        XCTAssertEqual(bars[1].startKm, 0.102, accuracy: 0.0001)
    }
}
