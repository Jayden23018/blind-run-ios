import CoreLocation
import MAMapKit
import QuartzCore
import XCTest
@testable import blindRun

@MainActor
final class XinghuoSnapshotTests: XCTestCase {
    private let shenzhenBay = CLLocationCoordinate2D(latitude: 22.5159, longitude: 113.9446)

    // MARK: - 摘要句

    func testBlindSummaryCountsVolunteersButNotOtherRunners() {
        let text = makeSnapshot(volunteers: 48, runners: 9).summaryText(for: .blind)
        XCTAssertEqual(text, "本市现在有 48 位志愿者在线。今天完成了 5 次陪跑，一共 12.5 公里。")
        XCTAssertFalse(text.contains("视障跑者"), "盲人端要的是有人愿意帮忙，不是还有别的盲人")
    }

    func testVolunteerSummaryAlsoCountsWaitingRunnersAndPairs() {
        let text = makeSnapshot(volunteers: 48, runners: 9).summaryText(for: .volunteer)
        XCTAssertEqual(
            text,
            "本市现在有 48 位志愿者在线，9 位视障跑者在等待陪跑，3 对正在同行。今天完成了 5 次陪跑，一共 12.5 公里。"
        )
    }

    func testSummarySaysNobodyInsteadOfInventingNumbers() {
        let text = makeSnapshot(volunteers: 0, runners: 0, todayRuns: 0).summaryText(for: .blind)
        XCTAssertEqual(text, "本市暂时没有志愿者在线。今天还没有完成的陪跑。")
    }

    // MARK: - 片区可见性

    func testBlindRunnerSeesOnlyVolunteerCells() {
        let snapshot = XinghuoSnapshot.demo(around: shenzhenBay)
        XCTAssertTrue(snapshot.cells.contains { $0.kind == .runner }, "演示数据里本来就该有跑者片区，否则下面的断言恒真")
        XCTAssertTrue(snapshot.cells(for: .blind).allSatisfy { $0.kind == .volunteer })
        XCTAssertEqual(snapshot.cells(for: .volunteer).count, snapshot.cells.count)
    }

    // MARK: - 演示数据

    func testDemoIsDeterministicAndConservesHeadcount() {
        let first = XinghuoSnapshot.demo(around: shenzhenBay)
        XCTAssertEqual(first, XinghuoSnapshot.demo(around: shenzhenBay))
        let volunteers = first.cells.filter { $0.kind == .volunteer }.reduce(0) { $0 + $1.count }
        let runners = first.cells.filter { $0.kind == .runner }.reduce(0) { $0 + $1.count }
        XCTAssertEqual(volunteers, first.volunteersOnline)
        XCTAssertEqual(runners, first.runnersWaiting)
    }

    func testDemoCellsStayWithinAboutThreeKilometres() {
        let origin = CLLocation(latitude: shenzhenBay.latitude, longitude: shenzhenBay.longitude)
        for cell in XinghuoSnapshot.demo(around: shenzhenBay).cells {
            let distance = CLLocation(latitude: cell.center.latitude, longitude: cell.center.longitude)
                .distance(from: origin)
            // 单轴最远 6 格 ≈ 3 km，对角格是 3 km × √2 ≈ 4.25 km。阈值卡在 4.5 km：
            // 正确实现的对角格能过，而网格跨度翻倍（±12 格 ≈ 6 km）这类错误过不了。
            XCTAssertLessThan(distance, 4_500, "片区 \(cell.id) 离中心 \(Int(distance)) 米")
        }
    }

    // MARK: - 地图明暗与图形

    func testMapTypeFollowsColorScheme() {
        XCTAssertEqual(AMapContainer.mapType(isDark: true), .standardNight)
        XCTAssertEqual(AMapContainer.mapType(isDark: false), .standard)
    }

    // MARK: - 片区 → 一簇星（纯视觉散布）

    func testSparksAreDeterministicCappedAndStayInsideTheirCell() {
        let cell = XinghuoSnapshot.Cell(id: "volunteer-1-2", center: shenzhenBay, kind: .volunteer, count: 30)
        let first = XinghuoSnapshot.sparks(for: cell, origin: shenzhenBay)
        let second = XinghuoSnapshot.sparks(for: cell, origin: shenzhenBay)

        XCTAssertEqual(first.count, XinghuoSnapshot.maxSparksPerCell, "人再多也封顶，否则星糊成一团光")
        XCTAssertEqual(first.map { $0.spark }, second.map { $0.spark }, "同一个片区每次要画得一样，不能一刷新就跳")
        XCTAssertEqual(first.map { $0.coordinate.latitude }, second.map { $0.coordinate.latitude })

        let center = CLLocation(latitude: cell.center.latitude, longitude: cell.center.longitude)
        for placed in first {
            let distance = CLLocation(latitude: placed.coordinate.latitude, longitude: placed.coordinate.longitude)
                .distance(from: center)
            // 卡在 180 m（+1 m 容差）而不是片区半宽 250 m：半径 250 的实现 12 颗全落在 181 m 内的
            // 概率约 0.04%，所以这条能区分「散进隔壁片区」的实现。
            XCTAssertLessThanOrEqual(distance, XinghuoSnapshot.sparkScatterMeters + 1, "\(placed.id) 散出了片区")
        }

        let few = XinghuoSnapshot.Cell(id: "runner-0-0", center: shenzhenBay, kind: .runner, count: 3)
        XCTAssertEqual(XinghuoSnapshot.sparks(for: few, origin: shenzhenBay).count, 3)
    }

    /// 棋盘感的直接成因是「每格一颗、正好在格子中心、一模一样大」。三件事各钉一条。
    func testSparksAreSpreadOutAndVaried() {
        let cell = XinghuoSnapshot.Cell(id: "volunteer-3-3", center: shenzhenBay, kind: .volunteer, count: 12)
        let sparks = XinghuoSnapshot.sparks(for: cell, origin: shenzhenBay)
        let center = CLLocation(latitude: cell.center.latitude, longitude: cell.center.longitude)
        let squares = sparks.map {
            pow(CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: center), 2)
        }
        let rms = (squares.reduce(0, +) / Double(squares.count)).squareRoot()
        // 半径 180 m 圆内均匀分布的均方根是 127 m；全堆在中心是 0。
        XCTAssertGreaterThan(rms, 40, "星挤在片区中心，画出来还是一格一个点")
        XCTAssertGreaterThan(Set(sparks.map { $0.spark.scale }).count, 1, "每颗一样大")
        XCTAssertGreaterThan(Set(sparks.map { $0.spark.phase }).count, 1, "每颗同时闪")
    }

    func testSparksIgniteOutwardFromTheViewer() {
        let far = CLLocationCoordinate2D(latitude: shenzhenBay.latitude + 0.027, longitude: shenzhenBay.longitude)  // 约 3 km
        func meanDelay(_ center: CLLocationCoordinate2D) -> Double {
            let cell = XinghuoSnapshot.Cell(id: "volunteer-\(center.latitude)", center: center, kind: .volunteer, count: 12)
            let delays = XinghuoSnapshot.sparks(for: cell, origin: shenzhenBay).map { $0.spark.igniteDelay }
            return delays.reduce(0, +) / Double(delays.count)
        }
        // 原型：每公里晚 0.33 s。近处约 0.85 s、3 km 外约 1.8 s；随机抖动只有 0–0.25 s，分得开。
        XCTAssertLessThan(meanDelay(shenzhenBay) + 0.5, meanDelay(far))
    }

    /// 种子不能用 `String.hashValue`：它每次启动加盐，同一个片区会换一种撒法。钉死一个常数。
    func testSparkSeedIsStableAcrossLaunches() {
        XCTAssertEqual(XinghuoRandom.fnv1a("volunteer-0-0"), 3_636_356_901_234_404_313)
    }

    // MARK: - 动效与「减弱动态效果」

    func testSparkViewAddsNoAnimationWhenReduceMotionIsOn() throws {
        let cell = XinghuoSnapshot.Cell(id: "volunteer-0-0", center: shenzhenBay, kind: .volunteer, count: 1)
        let spark = try XCTUnwrap(XinghuoSnapshot.sparks(for: cell, origin: shenzhenBay).first).spark
        let view = try XCTUnwrap(XinghuoSparkView(annotation: nil, reuseIdentifier: XinghuoSparkView.reuseID))
        let epoch = CACurrentMediaTime()

        view.configure(spark: spark, animates: true, epoch: epoch)
        XCTAssertTrue(view.activeAnimationKeys.contains { $0.hasPrefix("twinkle") }, "动效开着却没有闪烁 —— 下面那条断言恒真")
        XCTAssertTrue(view.activeAnimationKeys.contains("ignite"), "刚进页面的星该有点亮动画")

        // 运行中打开「减弱动态效果」：同一个视图重新配置后一个动画都不能剩。
        view.configure(spark: spark, animates: false, epoch: epoch)
        XCTAssertEqual(view.activeAnimationKeys, [])
    }

    // MARK: - 演示足迹

    func testDemoFootprintLoopStaysAroundTheViewer() {
        let loop = XinghuoFootprints.demoLoop(around: shenzhenBay)
        XCTAssertGreaterThanOrEqual(loop.count, 2)
        let origin = CLLocation(latitude: shenzhenBay.latitude, longitude: shenzhenBay.longitude)
        for point in loop {
            let distance = CLLocation(latitude: point.latitude, longitude: point.longitude).distance(from: origin)
            XCTAssertLessThan(distance, 1_500, "演示足迹离「你」\(Int(distance)) 米，屏幕上看不到")
        }
    }

    // MARK: - 我的足迹

    func testFootprintsKeepOnlyTodaysCompletedOrders() {
        let now = Date()
        let formatter = DateFormatter.aidRunBackendLocalDateTime
        let today = formatter.string(from: now)
        let yesterday = formatter.string(from: now.addingTimeInterval(-86_400))
        let orders = [
            makeOrder(id: 1, status: .completed, plannedStart: today),
            makeOrder(id: 2, status: .completed, plannedStart: yesterday),
            makeOrder(id: 3, status: .inProgress, plannedStart: today),
            makeOrder(id: 4, status: .completed, plannedStart: nil),
        ]
        XCTAssertEqual(XinghuoFootprints.todaysCompletedOrderIDs(in: orders, now: now), [1])
    }

    // MARK: - Helpers

    private func makeSnapshot(volunteers: Int, runners: Int, todayRuns: Int = 5) -> XinghuoSnapshot {
        XinghuoSnapshot(
            regionName: "本市",
            volunteersOnline: volunteers,
            runnersWaiting: runners,
            pairsRunning: 3,
            todayRuns: todayRuns,
            todayKm: 12.5,
            cells: []
        )
    }

    private func makeOrder(id: Int64, status: RunOrderStatus, plannedStart: String?) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: id,
            status: status,
            startAddress: nil,
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStart,
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
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
