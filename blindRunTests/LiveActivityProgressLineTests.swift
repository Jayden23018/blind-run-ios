import XCTest
@testable import blindRun

/// 实时活动底部进度线（两端共用，`blindRunWidget/Shared/LiveActivityProgressLine.swift`）。
///
/// 卡片在系统进程里渲染，样子只能真机人工看；这里守的是**会静默漂移**的取值：
/// 越界夹值、读屏念的那一句、两端共用的五步标签。
final class LiveActivityProgressLineTests: XCTestCase {

    func testStepTitlesAreTheFiveOrderPageSteps() {
        XCTAssertEqual(LiveActivityProgressLine.stepTitles, ["匹配", "商量", "出发", "汇合", "开跑"])
        XCTAssertEqual(LiveActivityProgressLine.spokenStepTitles.count, LiveActivityProgressLine.stepCount)
        XCTAssertEqual(LiveActivityProgressLine.stepTitles.count, LiveActivityProgressLine.stepCount)
    }

    func testStepsModeReadsCurrentStepOutOfFive() {
        XCTAssertEqual(LiveActivityProgressMode.steps(current: 3).accessibilityLabel, "第 3 步，共 5 步，等出发")
        XCTAssertEqual(LiveActivityProgressMode.steps(current: 1).accessibilityLabel, "第 1 步，共 5 步，匹配陪跑员")
    }

    /// 越界的步数夹回 1...5，而不是数组越界崩在 widget 进程里（那时锁屏卡整张空白）。
    func testOutOfRangeStepIsClampedInsteadOfCrashing() {
        XCTAssertEqual(LiveActivityProgressMode.steps(current: 0).accessibilityLabel, "第 1 步，共 5 步，匹配陪跑员")
        XCTAssertEqual(LiveActivityProgressMode.steps(current: 9).accessibilityLabel, "第 5 步，共 5 步，开跑")
    }

    func testProgressIsClampedAndNaNFallsBackToZero() {
        XCTAssertEqual(LiveActivityProgressLine.clampedProgress(-0.2), 0)
        XCTAssertEqual(LiveActivityProgressLine.clampedProgress(1.7), 1)
        XCTAssertEqual(LiveActivityProgressLine.clampedProgress(.nan), 0)
        XCTAssertEqual(LiveActivityProgressLine.clampedProgress(0.4), 0.4)
    }

    func testMileageReadsAPercentOfTheTarget() {
        XCTAssertEqual(LiveActivityProgressMode.mileage(progress: 0.48).accessibilityLabel, "已完成目标的 48%")
        XCTAssertEqual(LiveActivityProgressMode.mileage(progress: 2).accessibilityLabel, "已完成目标的 100%")
    }

    func testDistanceReadsWhereTheVolunteerIsHeading() {
        XCTAssertEqual(
            LiveActivityProgressMode.distance(progress: 0.5, endLabel: "你 · 南门").accessibilityLabel,
            "陪跑员在路上，前往你 · 南门"
        )
        XCTAssertEqual(LiveActivityProgressMode.distance(progress: 0.5, endLabel: " ").accessibilityLabel, "陪跑员在路上")
    }
}
