import XCTest
@testable import blindRun

/// 盲人端订单页 v2 头卡（#349）。
///
/// 头卡只从 `BlindOrderFlowPresentation` 派生，所以这里不再验文案本身（那边的用例在验），
/// 只验**哪句话放到了哪个位置、绳子画到第几格、读屏念什么** —— 这些放错了屏幕上不报任何错。
final class BlindOrderHeroTests: XCTestCase {

    /// 固定在上午 8 点：「明天」+「早上」两段都能落在确定的取值上。
    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 8))!
    }

    private func hero(
        _ status: RunOrderStatus,
        plannedStart: String? = nil,
        volunteerName: String? = "张*",
        distanceText: String? = nil,
        locationWarning: String? = nil,
        countdown: Int? = nil
    ) -> (BlindOrderHero?, BlindOrderFlowPresentation) {
        let order = OrderDetailResponse.preview(status: status, plannedStart: plannedStart, volunteerName: volunteerName)
        let presentation = BlindOrderFlowPresentation.make(
            order: order,
            distanceText: distanceText,
            canKeepWaiting: false,
            locationWarning: locationWarning,
            countdown: countdown,
            now: now
        )!
        return (BlindOrderHero.make(presentation: presentation, order: order, now: now), presentation)
    }

    // MARK: - 约好：开跑时刻当主角数字

    func testBookedOrderShowsStartClockAsTheHeroNumber() throws {
        let start = OrderDetailResponse.previewLocalTime(minutesFromNow: 24 * 60, now: now)
        let (hero, presentation) = hero(.scheduledConfirmed, plannedStart: start)
        let result = try XCTUnwrap(hero)

        XCTAssertEqual(result.eyebrow, "已约好 · 明天早上")
        XCTAssertEqual(result.number, VolunteerOrderTimeCopy.clock(try XCTUnwrap(start.backendTimestamp)))
        XCTAssertEqual(result.unit, "开跑")
        XCTAssertNil(result.headline, "有数字当主角时不再摆一行大字，否则时间说两遍")
        XCTAssertEqual(result.rope, .agreed)
        XCTAssertEqual(result.lines, presentation.subtitle.split(separator: "\n").map(String.init))
        // 屏幕上的「 · 」不进读屏。
        XCTAssertTrue(result.accessibilityLabel.hasPrefix("已约好，明天早上，"), result.accessibilityLabel)
        XCTAssertFalse(result.accessibilityLabel.contains("·"), result.accessibilityLabel)
    }

    func testBookedOrderWithoutStartFallsBackToThePresentationTitle() throws {
        let (hero, presentation) = hero(.pendingAccept, plannedStart: nil)
        let result = try XCTUnwrap(hero)

        XCTAssertNil(result.number, "拿不到时间不摆占位时间")
        XCTAssertEqual(result.headline, presentation.title)
        XCTAssertEqual(result.eyebrow, "已约好")
    }

    // MARK: - 其余三格：presentation 的标题当主角，开跑时刻进小标题

    func testMatchingUsesTheInvitedRopeAndThePresentationTitle() throws {
        let (hero, presentation) = hero(.pendingMatch, volunteerName: nil)
        let result = try XCTUnwrap(hero)

        XCTAssertEqual(result.rope, .invited)
        XCTAssertEqual(result.headline, presentation.title)
        XCTAssertEqual(result.eyebrow, "匹配中")
    }

    func testStepsOtherThanBookedPutTheStartTimeInTheEyebrow() throws {
        let start = OrderDetailResponse.previewLocalTime(minutesFromNow: 24 * 60, now: now)
        let clock = VolunteerOrderTimeCopy.clock(try XCTUnwrap(start.backendTimestamp))
        for status in [RunOrderStatus.pendingMatch, .driverEnRoute, .driverArrived] {
            let result = try XCTUnwrap(hero(status, plannedStart: start).0, "\(status)")
            XCTAssertEqual(result.eyebrow, "明天早上 \(clock) 开跑", "\(status)")
            XCTAssertNil(result.number, "\(status) 不该有主角数字")
        }
    }

    func testDepartedDrawsAFixedRopeProgressAndKeepsTheDistanceLine() throws {
        let (hero, presentation) = hero(.driverEnRoute, distanceText: "距出发地点约 600 米")
        let result = try XCTUnwrap(hero)

        // 固定值：盲人 token 拿不到 `eta.progress`（后端只给本单陪跑员）。
        XCTAssertEqual(result.rope, .departed(progress: BlindOrderHero.departedRopeProgress))
        XCTAssertEqual(result.headline, presentation.title)
        XCTAssertTrue(result.lines.contains("距出发地点约 600 米"), "距离是出发屏唯一会变的数字，不能丢：\(result.lines)")
    }

    func testMetUpDrawsTheArrivedRope() throws {
        XCTAssertEqual(try XCTUnwrap(hero(.driverArrived).0).rope, .arrived)
    }

    func testWarningIsCarriedIntoTheHeroAndItsSpokenLabel() throws {
        let result = try XCTUnwrap(hero(.driverEnRoute, locationWarning: "定位信号弱").0)
        XCTAssertEqual(result.warning, "定位信号弱")
        XCTAssertTrue(result.accessibilityLabel.hasSuffix("定位信号弱"), result.accessibilityLabel)
    }

    // MARK: - 倒计时与跑步中

    /// 三个数字走 announcement 通道。进了合成标签，焦点所在元素就会每秒换一次内容。
    func testCountdownShowsTheBeatButDoesNotSpeakIt() throws {
        let result = try XCTUnwrap(hero(.inProgress, countdown: 3).0)

        XCTAssertEqual(result.number, "3")
        XCTAssertEqual(result.countdownBeat, 3)
        XCTAssertEqual(result.accessibilityLabel, "已汇合，准备开始，握好引导绳")
    }

    /// 跑步中 / 已完成是原地变形后的跑步卡，不画头卡。
    func testRunningAndFinishedHaveNoHero() {
        XCTAssertNil(hero(.inProgress).0)
        XCTAssertNil(hero(.completed).0)
    }

    // MARK: - 引导绳读屏：跑者视角

    func testRopeSpeaksFromTheRunnersPerspective() {
        XCTAssertEqual(RopeState.invited.accessibilityLabel(perspective: .runner), "第 1 步，共 4 步，匹配中，还没约好")
        XCTAssertEqual(RopeState.agreed.accessibilityLabel(perspective: .runner), "第 2 步，共 4 步，已约好")
        // 不念分钟数：即使传进来也不念 —— 盲人 token 根本拿不到 eta。
        XCTAssertEqual(
            RopeState.departed(progress: 0.35).accessibilityLabel(remainingMinutes: 8, perspective: .runner),
            "第 3 步，共 4 步，陪跑员正在赶来"
        )
        XCTAssertEqual(RopeState.arrived.accessibilityLabel(perspective: .runner), "第 4 步，共 4 步，陪跑员已到达")
    }

    /// 陪跑员端默认参数不变：加视角参数不能悄悄改掉那一端。
    func testRopeKeepsTheVolunteerWordingByDefault() {
        XCTAssertEqual(
            RopeState.departed(progress: 0.5).accessibilityLabel(remainingMinutes: 8),
            "第 3 步，共 4 步，正在赶去，还有 8 分钟到"
        )
        XCTAssertEqual(RopeState.invited.accessibilityLabel(), "第 1 步，共 4 步，邀请，还没约好")
    }
}
