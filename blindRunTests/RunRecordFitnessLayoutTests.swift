import XCTest
@testable import blindRun

/// 跑步记录照健身重做（#823）里能脱开视图钉住的两件事：通栏地图的路线取景框、配速竖条的距离区间。
final class RunRecordFitnessLayoutTests: XCTestCase {

    /// 负责人 11-07 第 11 条：路线不压返回键、声音钮、头部。
    /// 上 = 安全区顶（导航栏，#830 起声音钮也在这一行）+ 16，下 = 头部高度 + 16，左右 28，四边再让出半个标注（12）。
    /// 上沿取 103 + 28：圆钮还叠在地图上时多让一行 64，会得到 103 + 92，这条能分辨。
    func testRouteInsetsClearTheNavigationBarAndTheHeader() {
        let insets = RunRecordHeroLayout.routeInsets(topInset: 103, headerHeight: 180)
        XCTAssertEqual(insets.top, 103 + 16 + 12, "声音钮在导航栏里，不再多让圆钮那一行")
        XCTAssertEqual(insets.bottom, 180 + 16 + 12)
        XCTAssertEqual(insets.left, 28 + 12)
        XCTAssertEqual(insets.right, 28 + 12)
    }

    /// 大字号头部变高，取景框下沿跟着抬：路线不会钻到头部下面。
    func testRouteInsetsFollowTheMeasuredHeaderHeight() {
        let normal = RunRecordHeroLayout.routeInsets(topInset: 103, headerHeight: 180)
        let large = RunRecordHeroLayout.routeInsets(topInset: 103, headerHeight: 420)
        XCTAssertEqual(large.bottom - normal.bottom, 240)
    }

    /// 负责人 11-07 装机反馈：地图渐变的终点是「标题滑到导航栏下沿」，不是固定的 pt。
    /// 标题要走 370pt：走到三分之一（≈123pt）时变暗只有 0.33、还没糊满；走满 370pt 才整个盖住。
    /// 上一版固定 240pt：同样走 123pt 时变暗已是 0.51，标题没到顶（走 240pt）就全白，这条取值能分辨。
    func testMapVeilFinishesWhenTheTitleReachesTheTop() {
        let distance: CGFloat = 370
        let top = RunRecordHeroLayout.veil(scrolled: 0, fadeDistance: distance)
        XCTAssertEqual(top.blur, 0)
        XCTAssertEqual(top.dim, 0)

        let pulled = RunRecordHeroLayout.veil(scrolled: -80, fadeDistance: distance)
        XCTAssertEqual(pulled.blur, 0, "往下拉过头不加遮罩")
        XCTAssertEqual(pulled.dim, 0)

        let third = RunRecordHeroLayout.veil(scrolled: distance / 3, fadeDistance: distance)
        XCTAssertEqual(third.dim, 1.0 / 3.0, accuracy: 0.0001, "标题走到三分之一，地图还剩三分之二")
        XCTAssertLessThan(third.blur, 1, "三分之一处还没糊满")

        let early = RunRecordHeroLayout.veil(scrolled: 240, fadeDistance: distance)
        XCTAssertLessThan(early.dim, 0.7, "固定 240pt 的旧曲线在这里已经全白，标题还没到顶")

        let arrived = RunRecordHeroLayout.veil(scrolled: distance, fadeDistance: distance)
        XCTAssertEqual(arrived.dim, 1, accuracy: 0.0001, "标题到顶时整个盖住")
        XCTAssertEqual(arrived.blur, 1)

        let past = RunRecordHeroLayout.veil(scrolled: 900, fadeDistance: distance)
        XCTAssertEqual(past.dim, 1)
    }

    /// 大字号头部变高 → 标题离顶更近 → 渐变距离变短；同样滑 100pt，距离短的遮得更多。
    func testMapVeilScalesWithTheTitleTravelDistance() {
        let long = RunRecordHeroLayout.veil(scrolled: 100, fadeDistance: 400)
        let short = RunRecordHeroLayout.veil(scrolled: 100, fadeDistance: 200)
        XCTAssertEqual(long.dim, 0.25, accuracy: 0.0001)
        XCTAssertEqual(short.dim, 0.5, accuracy: 0.0001)
    }

    /// 装机录屏（2026-11-07 目前实现.mov）量出：旧做法读内容块的 minY，地图前 150pt 纹丝不动。
    /// 现在直接读 `UIScrollView`：内容缩在导航栏下时静止偏移是 -边距，扣掉后静止 = 0，上滑 50pt = 50。
    /// 取「边距 106、偏移 -56」：不扣边距的实现在这里会得到 -56，被当成「还没开始滚」。
    func testScrolledIsZeroAtRestAndCountsFromTheFirstPoint() {
        XCTAssertEqual(RunRecordHeroLayout.scrolled(contentOffsetY: -106, adjustedTopInset: 106), 0)
        XCTAssertEqual(RunRecordHeroLayout.scrolled(contentOffsetY: -56, adjustedTopInset: 106), 50)
        XCTAssertEqual(RunRecordHeroLayout.scrolled(contentOffsetY: 50, adjustedTopInset: 0), 50)
        XCTAssertLessThan(RunRecordHeroLayout.scrolled(contentOffsetY: -130, adjustedTopInset: 106), 0, "往下拉过头为负")
    }

    /// 观察视图真的挂在 `UIScrollView` 里就能报出偏移，滚一下马上收到（同一帧，不经 SwiftUI 布局）。
    func testScrollObserverReportsContentOffsetFromEnclosingScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        scrollView.contentSize = CGSize(width: 300, height: 2000)
        scrollView.contentInset = UIEdgeInsets(top: 106, left: 0, bottom: 0, right: 0)
        scrollView.contentOffset = CGPoint(x: 0, y: -106)
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 2000))
        scrollView.addSubview(content)
        let observer = RunRecordScrollObserverView()
        content.addSubview(observer)
        var reported: [CGFloat] = []
        observer.onChange = { reported.append($0) }
        observer.attach()

        scrollView.contentOffset = CGPoint(x: 0, y: -56)
        scrollView.contentOffset = CGPoint(x: 0, y: -26)

        XCTAssertEqual(reported.last, 80, "-26 + 106")
        XCTAssertTrue(reported.contains(50))
        XCTAssertEqual(reported.first, 0, "挂上去的瞬间报一次静止位置")
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
