import XCTest

@testable import blindRun

/// `AppSpacing` / `AppCornerRadius` / `AppTouchTarget` 的取值约束。
///
/// 这套 token 的价值全在「同屏一致」，而一致性没有任何编译期保证：
/// 有人加一档 `case weird = 13`，或者为了排版好看把 `blindPrimary` 调成 56，
/// **编译照过、界面照跑、没有一个地方会红** —— 那正是这几条断言存在的理由。
///
/// ⚠️ 触达尺寸那两条是**规范下限**不是当前值：`AGENTS.md` §8 与
/// `docs/ui/ui-review-checklist.md` 要求盲人端主按钮 ≥64pt，HIG 要求任何可点元素 ≥44pt。
/// 断言写成 `>=` 而不是 `==`，是因为**调大是允许的、调小是事故**。
final class AppSpacingTests: XCTestCase {

    func testEverySpacingSitsOnTheFourPointGrid() {
        for (name, value) in AppSpacing.all {
            XCTAssertEqual(
                value.truncatingRemainder(dividingBy: AppSpacing.unit), 0,
                "AppSpacing.\(name) = \(value)，不在 \(AppSpacing.unit)pt 网格上。"
                    + "散值（6/10/14/18）正是这套 token 要消掉的东西，别从这里加回去。"
            )
            XCTAssertGreaterThan(value, 0, "AppSpacing.\(name) 必须为正；要不留间距请直接写 0。")
        }
    }

    func testSpacingScaleIsStrictlyIncreasingAndHasNoDuplicates() {
        let values = AppSpacing.all.map(\.value)
        for (index, value) in values.enumerated().dropFirst() {
            XCTAssertGreaterThan(
                value, values[index - 1],
                "AppSpacing.\(AppSpacing.all[index].name) 没有比前一档大。"
                    + "档位必须严格递增 —— 两档取值相同等于其中一档没有意义，"
                    + "而调用点看名字选档时分不出该用哪个。"
            )
        }
    }

    func testCornerRadiusScaleIsStrictlyIncreasing() {
        let values = AppCornerRadius.all.map(\.value)
        for (index, value) in values.enumerated().dropFirst() {
            XCTAssertGreaterThan(
                value, values[index - 1],
                "AppCornerRadius.\(AppCornerRadius.all[index].name) 没有比前一档大。"
            )
        }
        for (name, value) in AppCornerRadius.all {
            XCTAssertGreaterThan(value, 0, "AppCornerRadius.\(name) 必须为正。")
        }
    }

    /// 盲人端主按钮的 64pt 是无障碍硬要求，不是审美选择。
    func testBlindPrimaryTouchTargetNeverDropsBelowSixtyFour() {
        XCTAssertGreaterThanOrEqual(
            AppTouchTarget.blindPrimary, 64,
            "盲人端主操作按钮最小高度被调到了 \(AppTouchTarget.blindPrimary)pt。"
                + "AGENTS.md §8 与 ui-review-checklist.md 都要求 ≥64pt —— "
                + "盲人用户靠摸索命中而不是靠看准，调小它是无障碍事故不是排版优化。"
        )
    }

    func testMinimumTouchTargetMeetsHIG() {
        XCTAssertGreaterThanOrEqual(
            AppTouchTarget.minimum, 44,
            "任何可点元素都不得低于 HIG 的 44pt，当前是 \(AppTouchTarget.minimum)pt。"
        )
        XCTAssertGreaterThan(
            AppTouchTarget.blindPrimary, AppTouchTarget.minimum,
            "盲人端主按钮必须比通用最小触达尺寸更大 —— 两者相等说明盲人端那条要求被抹掉了。"
        )
    }
}
