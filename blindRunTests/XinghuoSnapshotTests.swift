import CoreLocation
import MAMapKit
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

    // MARK: - 分档边界（取落在「差一」两侧的值，区分 <5 与 <=5 这类实现）

    func testTierBoundaries() {
        XCTAssertEqual(XinghuoSnapshot.tier(forCount: 1), 1)
        XCTAssertEqual(XinghuoSnapshot.tier(forCount: 4), 1)
        XCTAssertEqual(XinghuoSnapshot.tier(forCount: 5), 2)
        XCTAssertEqual(XinghuoSnapshot.tier(forCount: 14), 2)
        XCTAssertEqual(XinghuoSnapshot.tier(forCount: 15), 3)
        XCTAssertEqual(XinghuoSnapshot.tier(forCount: 500), 3)
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

    func testGlyphColorsComeFromThePaletteTable() {
        XCTAssertEqual(XinghuoGlyph.tone("warning", isDark: true), UIColor(rgb: 0xFF9F0A))
        XCTAssertEqual(XinghuoGlyph.tone("primary", isDark: false), UIColor(rgb: 0x0058C7))
    }

    func testOnlyXinghuoKindsGetCustomGlyphs() {
        XCTAssertNotNil(XinghuoGlyph.image(for: .volunteerStar(tier: 2), isDark: true))
        XCTAssertNotNil(XinghuoGlyph.image(for: .runnerCluster(tier: 1), isDark: false))
        XCTAssertNil(XinghuoGlyph.image(for: .orderStart, isDark: true), "既有大头针不能被换掉")
        XCTAssertLessThan(
            XinghuoGlyph.image(for: .volunteerStar(tier: 1), isDark: true)!.size.width,
            XinghuoGlyph.image(for: .volunteerStar(tier: 3), isDark: true)!.size.width
        )
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
