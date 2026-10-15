import CoreLocation
import XCTest
@testable import blindRun

/// 引导绳几何与汇合方位的纯函数（交付包 03 §一、02 ④）。
///
/// 这两块画错了屏幕上不会报错：头像在出发时叠在一起、方位描述在「前方 / 右前方」之间来回跳、
/// 转一圈过 0° 时扇形甩到反方向 —— 所以每条都挑能区分正确实现与错误实现的取值。
final class RopeAndDirectionTests: XCTestCase {

    // MARK: - 引导绳（2026-10-13 定稿 v6：进度与引导绳合成一根）

    /// 四个刻度等距，第四个就是对方头像的圆心。
    /// v3 初稿把「我」的停靠点 24/105/187/268 当刻度、对方在 318 —— 肉眼间距 81/81/131，负责人目视抓到的。
    /// 那组数在这里会红：最后一段 50 ≠ 98。
    func testTicksAreEvenlySpacedAndTheLastTickIsTheOtherAvatar() {
        let ticks = RopeGeometry.ticks
        XCTAssertEqual(ticks.count, 4)
        for index in 1..<ticks.count {
            XCTAssertEqual(ticks[index] - ticks[index - 1], 98, accuracy: 0.001, "第 \(index) 段")
        }
        XCTAssertEqual(ticks.last, RopeGeometry.make(for: .agreed).otherX)
    }

    /// 「我」停在当前阶段的刻度上。出发中**不随 `eta.progress` 移动** —— 0.02 与 0.99 落在同一点；
    /// 改版前按进度连续移动的实现在这里会红（两者分别是 48.4 与 231.4）。
    func testSelfStopsOnTheTickOfTheCurrentStep() {
        XCTAssertEqual(RopeGeometry.make(for: .invited).selfX, 24)
        XCTAssertEqual(RopeGeometry.make(for: .agreed).selfX, 122)
        XCTAssertEqual(RopeGeometry.make(for: .departed(progress: 0.02)).selfX, 220)
        XCTAssertEqual(RopeGeometry.make(for: .departed(progress: 0.99)).selfX, 220)
        XCTAssertEqual(
            [RopeState.invited, .agreed, .departed(progress: 0.5), .arrived].map { RopeGeometry.make(for: $0).step },
            [0, 1, 2, 3]
        )
    }

    /// 刻度圆点按 `curveY` 摆，绳子按同一条曲线画 —— 两端在头像那一行，中点低 12。
    func testTicksSitOnTheRopeCurve() {
        XCTAssertEqual(RopeGeometry.curveY(atX: 24), 28, accuracy: 0.001)
        XCTAssertEqual(RopeGeometry.curveY(atX: 318), 28, accuracy: 0.001)
        XCTAssertEqual(RopeGeometry.curveY(atX: 171), 40, accuracy: 0.001)
        XCTAssertEqual(RopeGeometry.curveY(atX: 122), 28 + 2 * (1.0 / 3) * (2.0 / 3) * 24, accuracy: 0.001)
        XCTAssertEqual(RopeGeometry.make(for: .agreed).selfY, RopeGeometry.curveY(atX: 122), accuracy: 0.001)
    }

    /// 绳子从「我」的右缘起、到对方左缘止（各让 24），不压在头像上。
    func testRopeRunsBetweenTheTwoAvatars() {
        let agreed = RopeGeometry.make(for: .agreed)
        XCTAssertEqual(agreed.ropeStartX, 146)
        XCTAssertEqual(agreed.ropeEndX, 294)
    }

    func testInviteIsDashedWithAHollowOtherAndAgreedIsSolid() {
        let invited = RopeGeometry.make(for: .invited)
        XCTAssertEqual(invited.ropeStyle, .dashed)
        XCTAssertEqual(invited.otherStyle, .hollow)
        let agreed = RopeGeometry.make(for: .agreed)
        XCTAssertEqual(agreed.ropeStyle, .solid)
        XCTAssertEqual(agreed.otherStyle, .solid)
    }

    /// 汇合不画刻度，改画完成页的并肩插图；跑步中衔接那根金绳原样保留（342×56）。
    func testArrivedSwitchesToTheIllustrationAndTogetherKeepsTheGoldRope() {
        let arrived = RopeGeometry.make(for: .arrived)
        XCTAssertEqual(arrived.layout, .illustration)
        XCTAssertEqual(arrived.aspectHeight, RopeGeometry.height)
        let together = RopeGeometry.make(for: .together)
        XCTAssertEqual(together.layout, .together)
        XCTAssertEqual(together.ropeStyle, .gold)
        XCTAssertEqual(together.aspectHeight, 56)
        XCTAssertEqual(RopeGeometry.make(for: .agreed).layout, .ticks)
    }

    /// 呼吸光晕只在出发中。
    func testDepartureHaloOnlyWhileDeparted() {
        XCTAssertTrue(RopeGeometry.make(for: .departed(progress: 0.3)).showsDepartureHalo)
        XCTAssertFalse(RopeGeometry.make(for: .agreed).showsDepartureHalo)
        XCTAssertFalse(RopeGeometry.make(for: .invited).showsDepartureHalo)
    }

    /// 跑者取消：头像停在取消前的位置，绳子断开、对方变灰、循环动效停。
    func testCancelledKeepsThePreviousPositionsAndBreaksTheRope() {
        let before = RopeGeometry.make(for: .departed(progress: 0.5))
        let after = RopeGeometry.make(for: .cancelled(after: .departed(progress: 0.5)))
        XCTAssertEqual(after.selfX, before.selfX)
        XCTAssertEqual(after.step, before.step)
        XCTAssertEqual(after.ropeStyle, .broken)
        XCTAssertEqual(after.otherStyle, .greyed)
        XCTAssertFalse(after.showsDepartureHalo)
    }

    func testRopeAnnouncesStepRemainingMinutesAndWhatComesNext() {
        XCTAssertEqual(RopeState.departed(progress: 0.3).accessibilityLabel(remainingMinutes: 8),
                       "第 3 步，共 4 步，正在赶去，还有 8 分钟到。接下来：汇合")
        XCTAssertEqual(RopeState.agreed.accessibilityLabel(remainingMinutes: 8), "第 2 步，共 4 步，已约好。接下来：出发、汇合")
        XCTAssertEqual(RopeState.invited.accessibilityLabel(), "第 1 步，共 4 步，邀请，还没约好。接下来：约好、出发、汇合")
    }

    /// 最后一格和取消没有「接下来」—— 说「接下来：」后面跟空串是在念一句没说完的话。
    func testLastStepAndCancellationHaveNoNextSteps() {
        XCTAssertEqual(RopeState.arrived.accessibilityLabel(), "第 4 步，共 4 步，已到集合点")
        XCTAssertEqual(RopeState.together.accessibilityLabel(), "第 4 步，共 4 步，已汇合")
        XCTAssertEqual(RopeState.cancelled(after: .agreed).accessibilityLabel(), "这次陪跑已取消")
    }

    /// 先通个电话：第 1 格、虚线、对方实心。电话只在「还没打」挂，小勾只在「已说合适」画。
    /// 电话挂在第 2、3 个刻度正中（171），不压任何刻度 —— v3 初稿挂在「我」与对方中点，压在了刻度上。
    func testIntroCallStaysOnTheFirstTickAndOnlyDrawsItsOwnSide() {
        for stage in [IntroCallRopeStage.beforeCall, .afterCall, .decided] {
            let g = RopeGeometry.make(for: .introCall(stage))
            XCTAssertEqual(g.step, 0, "\(stage)")
            XCTAssertEqual(g.selfX, 24)
            XCTAssertEqual(g.ropeStyle, .dashed, "通话阶段还没约好")
            XCTAssertEqual(g.otherStyle, .solid, "候选人已经有名字了，不是空心")
            XCTAssertEqual(g.showsPhone, stage == .beforeCall)
            XCTAssertEqual(g.showsSelfCheck, stage == .decided)
        }
        XCTAssertEqual(RopeGeometry.phoneX, 171)
        for tick in RopeGeometry.ticks {
            XCTAssertGreaterThan(abs(RopeGeometry.phoneX - tick), 26, "电话图标不压刻度 \(tick)")
        }
    }

    /// 读屏只说自己这一侧：「你已说合适」。🚨 不许出现对方的表态（无声拒绝）。
    func testIntroCallRopeSpeaksOnlyAboutItsOwnSide() {
        XCTAssertEqual(
            RopeState.introCall(.beforeCall).accessibilityLabel(perspective: .runner),
            "第 1 步，共 4 步，匹配中，先通个电话。接下来：约好、出发、汇合"
        )
        XCTAssertEqual(
            RopeState.introCall(.decided).accessibilityLabel(),
            "第 1 步，共 4 步，邀请，你已说合适。接下来：约好、出发、汇合"
        )
        for stage in [IntroCallRopeStage.beforeCall, .afterCall, .decided] {
            for perspective in [RopePerspective.runner, .volunteer] {
                let label = RopeState.introCall(stage).accessibilityLabel(perspective: perspective)
                for word in ["对方", "拒绝", "第 2 位", "第二位"] {
                    XCTAssertFalse(label.contains(word), "\(stage) \(perspective)：\(word)")
                }
            }
        }
    }

    func testFirstStepIsNamedForEachSide() {
        XCTAssertEqual(RopeState.stepTitles(perspective: .runner), ["匹配", "约好", "出发", "汇合"])
        XCTAssertEqual(RopeState.stepTitles(perspective: .volunteer), ["邀请", "约好", "出发", "汇合"])
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
