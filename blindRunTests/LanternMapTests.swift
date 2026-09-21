import XCTest
@testable import blindRun

/// 「一束光地图」原型的数据层检查。
///
/// 视图层（Canvas 绘制、手势、辉光）**没有检查也不该有** —— 那是渲染几何，
/// 只能真机目视（同 `flexible-spacer-steals-half-the-row` 那条记忆的判据）。
/// 这里只钉三件在代码里会静默错掉、而画面上看不出来的东西。
@MainActor
final class LanternMapTests: XCTestCase {

    // MARK: - 投影

    func testProjectionPinsTheFourCornersOfTheBasemap() {
        let west = LanternMap.normalizedPoint(longitude: 73, latitude: 54)
        XCTAssertEqual(west.x, 0, accuracy: 0.0001, "西边界应落在画布左缘")
        XCTAssertEqual(west.y, 0, accuracy: 0.0001, "北边界应落在画布上缘")

        let east = LanternMap.normalizedPoint(longitude: 136, latitude: 17)
        XCTAssertEqual(east.x, 1, accuracy: 0.0001, "东边界应落在画布右缘")
        XCTAssertEqual(east.y, 1, accuracy: 0.0001, "南边界应落在画布下缘")
    }

    /// 纬度方向**必须是反的**（纬度越大越靠上，而画布 y 越大越靠下）。
    ///
    /// 这条单独立一个用例，是因为它是这类线性映射唯一会被写反的地方，
    /// 而写反之后画面上是一张**上下颠倒但看着很正常**的中国图 —— 北京跑到广东的位置，
    /// 只有认得出地理的人才会发现。上面那条四角用例挡不住它（角点对称）。
    func testLatitudeAxisIsFlippedRelativeToTheCanvas() {
        let north = LanternMap.normalizedPoint(longitude: 116, latitude: 45)
        let south = LanternMap.normalizedPoint(longitude: 116, latitude: 25)
        XCTAssertLessThan(north.y, south.y, "纬度高的点应该画得更靠上（y 更小）")
    }

    // MARK: - 聚合

    /// 🔑 **人数守恒**：聚合最容易出的 bug 是把「合并」写成「取第一个」，
    /// 而那在画面上完全看不出来 —— 光点位置对、数量对，只有数字悄悄变小。
    ///
    /// 这条用例能区分正确实现与被打回的实现，因为假数据里**至少有一个省份含多个人数不同的区县**
    /// （北京 37/29/14，上海 33/41/18）。若假数据退化成每省一个区县，这条断言会恒真 ——
    /// 下面那条 `testSampleDataActuallyExercisesTheMerge` 就是守这个前提的。
    func testClusteringPreservesTheTotalHeadcount() {
        let expected = LanternMap.sampleSites.reduce(0) { $0 + $1.volunteerCount }

        for tier in [LanternMap.Tier.region, .site] {
            let total = LanternMap.cluster(LanternMap.sampleSites, tier: tier)
                .reduce(0) { $0 + $1.volunteerCount }
            XCTAssertEqual(total, expected, "\(tier) 档聚合后总人数不守恒")
        }
    }

    /// 守上面那条用例的前提：假数据真的有可合并的组，且组内人数不同。
    func testSampleDataActuallyExercisesTheMerge() {
        let grouped = Dictionary(grouping: LanternMap.sampleSites, by: \.region)
        let mergeable = grouped.values.filter { members in
            members.count > 1 && Set(members.map(\.volunteerCount)).count > 1
        }
        XCTAssertFalse(
            mergeable.isEmpty,
            "假数据里没有「同省多个区县且人数不同」的组，人数守恒那条断言会恒真"
        )
    }

    /// 区县名全国不唯一（假数据里「和平区」有天津和辽宁两个）。
    /// id 若只取区县名，其中一个会在 `ForEach` 里被静默吃掉 —— 画面上只是少了一个点。
    func testSiteIdentifiersStayUniqueEvenWhenDistrictNamesCollide() {
        let names = Set(LanternMap.sampleSites.map(\.name))
        XCTAssertLessThan(
            names.count,
            LanternMap.sampleSites.count,
            "假数据里已经没有重名区县了，这条用例失去了守护对象"
        )

        let ids = Set(LanternMap.sampleSites.map(\.id))
        XCTAssertEqual(ids.count, LanternMap.sampleSites.count, "有区县的 id 撞了")
    }

    /// 档位阈值要能区分两侧。取值刻意落在阈值**两边最近的位置**，
    /// 而不是随手取 1 和 10 —— 后者在阈值被偷偷改成任何值时都照样通过。
    func testTierThresholdSeparatesTheTwoSidesOfItsOwnBoundary() {
        let threshold = LanternMap.siteTierScale
        XCTAssertEqual(LanternMap.tier(forScale: threshold), .site, "到阈值就该散开到区县")
        XCTAssertEqual(LanternMap.tier(forScale: threshold - 0.01), .region, "阈值以下应按省聚合")
    }

    func testRegionTierMergesSameProvinceIntoOneLantern() {
        let clusters = LanternMap.cluster(LanternMap.sampleSites, tier: .region)
        let beijing = clusters.filter { $0.label == "北京" }
        XCTAssertEqual(beijing.count, 1, "北京的三个区应该合成一束光")
        XCTAssertEqual(beijing.first?.volunteerCount, 37 + 29 + 14)
    }

    // MARK: - 红线：文案里只能有地名和人数

    /// 🔴 点击光点不得显示任何个人信息（报告 §3 维度 12，三个视觉方向共用）。
    ///
    /// 这条守不住「有人另写一处文案绕过 `caption(for:)`」—— 那是人的问题。
    /// 它守的是**这个出口本身**不被加字段：真实数据接进来时，
    /// 给 `Cluster` 加一个 `latestVolunteerName` 再拼进文案是最自然的一步。
    func testCaptionExposesNothingBeyondPlaceAndHeadcount() {
        let cluster = LanternMap.Cluster(
            id: "北京朝阳区",
            label: "北京朝阳区",
            longitude: 116.5,
            latitude: 39.9,
            volunteerCount: 37
        )
        XCTAssertEqual(LanternMap.caption(for: cluster), "北京朝阳区，37 位志愿者")
    }

    /// 摘要行是全盲用户唯一真正能用的东西，所以它不能依赖任何视觉元素才成立。
    func testSummaryStandsOnItsOwnWithoutTheMap() {
        let summary = LanternMap.summary(LanternMap.sampleSites)
        let total = LanternMap.sampleSites.reduce(0) { $0 + $1.volunteerCount }
        XCTAssertTrue(summary.contains("\(LanternMap.sampleSites.count) 个区县"))
        XCTAssertTrue(summary.contains("\(total) 位志愿者"))
    }

    // MARK: - 几何

    /// 底图按 `fit` 落进容器后，光点必须按**底图的矩形**算坐标而不是容器矩形，
    /// 否则光点整体拉伸、离开灯火。这条钉住那个矩形的算法。
    func testBasemapRectKeepsTheProjectionAspectInBothOrientations() {
        let aspect = LanternMap.basemapAspectRatio

        let tall = LanternMapView.basemapRect(in: CGSize(width: 390, height: 800))
        XCTAssertEqual(tall.width, 390, accuracy: 0.001, "窄容器应按宽度铺满")
        XCTAssertEqual(tall.width / tall.height, aspect, accuracy: 0.001)

        let wide = LanternMapView.basemapRect(in: CGSize(width: 1200, height: 300))
        XCTAssertEqual(wide.height, 300, accuracy: 0.001, "扁容器应按高度铺满")
        XCTAssertEqual(wide.width / wide.height, aspect, accuracy: 0.001)
    }

    /// 半径按开方增长：人数差 10 倍，半径不该差 10 倍。
    func testRadiusGrowsSublinearlyWithHeadcount() {
        let small = LanternMapView.radius(forCount: 4)
        let large = LanternMapView.radius(forCount: 40)
        XCTAssertLessThan(large / small, 3.0, "半径增长过快，密集区会糊成一团")
        XCTAssertGreaterThan(large, small)
    }

    /// 🔑 半径必须封顶，否则规模一大整张图糊成白团、底层灯火完全消失 ——
    /// 而「底层灯火撑着画面」正是方向 C 被选中的**全部理由**。
    ///
    /// 这条能区分正确实现与被打回的实现：去掉 `min` 之后，5000 人的半径是 51.5pt、
    /// 光晕直径 432pt，比整个 iPhone 屏幕还宽，而第一条断言会直接红。
    /// 取 4000 而不是「一个大数」是因为它落在**真实可能达到的规模**上
    /// （2026-09-21 渲染实测：省级聚合下 5000 人分到 43 处 ≈ 116 人/处）。
    func testRadiusIsCappedSoDenseClustersDoNotWashOutTheBasemap() {
        XCTAssertEqual(
            LanternMapView.radius(forCount: 4000),
            LanternMapView.maximumRadius,
            accuracy: 0.0001,
            "大簇的半径没有封顶"
        )

        let uncapped = 2.0 + Double(4000).squareRoot() * 0.7
        XCTAssertLessThan(
            LanternMapView.radius(forCount: 4000),
            uncapped,
            "封顶没有真的在起作用（不封顶时是 \(uncapped)pt）"
        )

        // 封顶不能把小簇一起压平 —— 那样人数就完全看不出来了。
        XCTAssertLessThan(
            LanternMapView.radius(forCount: 1),
            LanternMapView.radius(forCount: 20),
            "封顶压到了常见规模上，光点失去层次"
        )
    }
}
