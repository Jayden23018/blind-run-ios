import CoreLocation
import XCTest
@testable import blindRun

/// 引导绳几何与汇合方位的纯函数（交付包 03 §一、02 ④）。
///
/// 这两块画错了屏幕上不会报错：头像在出发时叠在一起、方位描述在「前方 / 右前方」之间来回跳、
/// 转一圈过 0° 时扇形甩到反方向 —— 所以每条都挑能区分正确实现与错误实现的取值。
final class RopeAndDirectionTests: XCTestCase {

    // MARK: - 引导绳

    func testDepartedProgressIsClampedSoAvatarsNeverOverlapOrTouch() {
        // 没有夹取时 0.02 → x = 28.88，头像与出发地小圈叠在一起。
        XCTAssertEqual(RopeGeometry.make(for: .departed(progress: 0.02)).volunteerX, 24 + 244 * 0.1, accuracy: 0.001)
        // 没有夹取时 0.99 → x = 265.56，已经贴到跑者身上，而人还没到。
        XCTAssertEqual(RopeGeometry.make(for: .departed(progress: 0.99)).volunteerX, 24 + 244 * 0.85, accuracy: 0.001)
        XCTAssertEqual(RopeGeometry.make(for: .departed(progress: 0.5)).volunteerX, 146, accuracy: 0.001)
    }

    /// 下垂量按文档公式 `max(2, 18·长度/242)`，不按画板示意的 10。
    func testDepartedSagFollowsTheDocumentedFormulaNotTheArtboard() {
        let g = RopeGeometry.make(for: .departed(progress: 0.68))
        let length = 292 - (24 + 244 * 0.68 + 24)
        XCTAssertEqual(g.sag, 18 * length / 242, accuracy: 0.001)
        XCTAssertNotEqual(g.sag, 10, accuracy: 0.5)
        XCTAssertEqual(g.ropeStartX, g.volunteerX + 24, accuracy: 0.001, "绳子从陪跑员右缘起，不画走过的路")
        XCTAssertTrue(g.showsOrigin)
        XCTAssertTrue(g.showsVolunteerHalo)
    }

    func testInviteIsDashedWithAHollowRunnerAndAgreedIsSolid() {
        let invited = RopeGeometry.make(for: .invited)
        XCTAssertEqual(invited.ropeStyle, .dashed)
        XCTAssertEqual(invited.runnerStyle, .hollow)
        let agreed = RopeGeometry.make(for: .agreed)
        XCTAssertEqual(agreed.ropeStyle, .solid)
        XCTAssertEqual(agreed.runnerStyle, .solid)
        XCTAssertEqual(agreed.sag, 18)
    }

    func testArrivedPutsTheGoldRingOnTheRunnerAndTogetherHangsTheRopeBelow() {
        let arrived = RopeGeometry.make(for: .arrived)
        XCTAssertEqual(arrived.volunteerX, 268)
        XCTAssertTrue(arrived.showsRunnerRing)
        let together = RopeGeometry.make(for: .together)
        XCTAssertEqual(together.ropeY, 49)
        XCTAssertEqual(together.ropeStyle, .gold)
    }

    /// 跑者取消：头像停在取消前的位置，绳子断开、跑者变灰、循环动效停。
    func testCancelledKeepsThePreviousPositionsAndBreaksTheRope() {
        let before = RopeGeometry.make(for: .departed(progress: 0.5))
        let after = RopeGeometry.make(for: .cancelled(after: .departed(progress: 0.5)))
        XCTAssertEqual(after.volunteerX, before.volunteerX)
        XCTAssertEqual(after.ropeStyle, .broken)
        XCTAssertEqual(after.runnerStyle, .greyed)
        XCTAssertFalse(after.showsVolunteerHalo)
    }

    func testRopeAnnouncesStepAndRemainingMinutesOnlyWhileDeparted() {
        XCTAssertEqual(RopeState.departed(progress: 0.3).accessibilityLabel(remainingMinutes: 8),
                       "第 3 步，共 4 步，正在赶去，还有 8 分钟到")
        XCTAssertEqual(RopeState.agreed.accessibilityLabel(remainingMinutes: 8), "第 2 步，共 4 步，已约好")
        XCTAssertEqual(RopeState.invited.accessibilityLabel(), "第 1 步，共 4 步，邀请，还没约好")
    }

    // MARK: - 方位

    func testSectorBoundariesBelongWhereTheSpecPutsThemOnBothSides() {
        let cases: [(Double, DirectionSector)] = [
            (0, .front), (22.5, .front), (22.6, .frontRight), (-22.5, .front), (-22.6, .frontLeft),
            (67.5, .frontRight), (-67.5, .frontLeft), (67.6, .right), (-67.6, .left),
            (112.5, .right), (-112.5, .left), (157.5, .backRight), (-157.5, .backLeft),
            (157.6, .back), (180, .back), (-180, .back), (540, .back), (-270, .right),
        ]
        for (degrees, expected) in cases {
            XCTAssertEqual(DirectionSector.raw(relativeDegrees: degrees), expected, "θ = \(degrees)")
        }
    }

    /// 5° 滞回：θ 在 21° 与 25° 之间抖动时描述不跳（交付包 02 / openspec 场景 Hysteresis）。
    func testHysteresisKeepsTheWordingStableAcrossTheBoundary() {
        var previous: DirectionSector?
        for degrees in [21.0, 25, 21, 25, 26] {
            previous = DirectionSector.describe(relativeDegrees: degrees, previous: previous)
            XCTAssertEqual(previous, .front, "θ = \(degrees)")
        }
        // 超出 22.5 + 5 才换。
        XCTAssertEqual(DirectionSector.describe(relativeDegrees: 28, previous: .front), .frontRight)
        // 反方向同理：从右前方回来，要低于 45 − 27.5 = 17.5 才换回前方。
        XCTAssertEqual(DirectionSector.describe(relativeDegrees: 18, previous: .frontRight), .frontRight)
        XCTAssertEqual(DirectionSector.describe(relativeDegrees: 17, previous: .frontRight), .front)
    }

    func testBearingPointsNorthAndEast() {
        let origin = CLLocationCoordinate2D(latitude: 22.5, longitude: 113.95)
        let north = CLLocationCoordinate2D(latitude: 22.5009, longitude: 113.95)
        let east = CLLocationCoordinate2D(latitude: 22.5, longitude: 113.9509)
        XCTAssertEqual(DirectionSector.bearing(from: origin, to: north), 0, accuracy: 0.5)
        XCTAssertEqual(DirectionSector.bearing(from: origin, to: east), 90, accuracy: 0.5)
    }

    /// 朝向跨过 0° 时不能往反方向甩一圈。
    func testHeadingFilterWrapsAroundNorthAndIgnoresTinyChanges() {
        // 朴素的 350 + 0.2·(10 − 350) = 282；正确的是往前走 4° 到 354。
        XCTAssertEqual(try XCTUnwrap(HeadingFilter.next(previous: 350, raw: 10)), 354, accuracy: 0.001)
        // 平滑后只变 2°（< 3°）→ 不更新。
        XCTAssertNil(HeadingFilter.next(previous: 100, raw: 110))
        XCTAssertEqual(try XCTUnwrap(HeadingFilter.next(previous: 100, raw: 120)), 104, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(HeadingFilter.next(previous: nil, raw: -30)), 330, accuracy: 0.001)
    }

    func testSectorWidthHasAFloorOfSixtyAndACeilingOfOneTwenty() {
        XCTAssertEqual(DirectionDialGeometry.sectorWidth(accuracyMeters: 10, distanceMeters: 100), 60)
        XCTAssertEqual(DirectionDialGeometry.sectorWidth(accuracyMeters: 50, distanceMeters: 50), 90, accuracy: 0.001)
        XCTAssertEqual(DirectionDialGeometry.sectorWidth(accuracyMeters: 100, distanceMeters: 10), 120)
        XCTAssertEqual(DirectionDialGeometry.sectorWidth(accuracyMeters: 5, distanceMeters: 0), 120)
    }
}
