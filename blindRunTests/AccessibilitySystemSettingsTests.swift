import SwiftUI
import XCTest
@testable import blindRun

/// 批次 D 里**能被单测钉住**的那一块（预约时间提示行随旧表单删了，#810）。
///
/// 其余几项（焦点转移、进度点实心/空心、Reduce Motion 的抖动与转场、按钮描边、
/// 遮罩不透明）都是纯视图行为，XCTest 够不到，只能真机开系统开关人眼验 ——
/// 那份清单写在 PR 描述里，不在这里假装被覆盖了。
@MainActor
final class AccessibilitySystemSettingsTests: XCTestCase {

    // MARK: - 增强对比度

    /// `HighContrastText` 这个名字承诺了高对比度，而它此前对系统「增强对比度」开关
    /// 一个像素都不变。次要色那两档要并到最深的 `textPrimary`。
    func testIncreasedContrastDeepensTheSecondaryStyles() {
        XCTAssertEqual(
            HighContrastText.TextStyle.caption.color(increasedContrast: true),
            AppColors.textPrimary
        )
        XCTAssertEqual(
            HighContrastText.TextStyle.status.color(increasedContrast: true),
            AppColors.textPrimary
        )
    }

    /// 没开就一个字不动 —— 默认取值由 `LowVisionChannelTests` 按 4.5:1 逐条验过，
    /// 这里若顺手改了默认色，那套断言会在别处红，而红的地方和原因对不上。
    func testDefaultColorsAreUntouchedWhenContrastIsNotIncreased() {
        for style in [
            HighContrastText.TextStyle.title,
            .body,
            .status,
            .caption
        ] {
            XCTAssertEqual(
                style.color(increasedContrast: false),
                style.color,
                "未开启增强对比度时取色必须与既有色板一致"
            )
        }
    }

    /// `.title` / `.body` 本来就是 `textPrimary`，增强对比度下没有可提升的空间，
    /// 不该被改成别的颜色。
    func testPrimaryStylesStayPrimaryUnderIncreasedContrast() {
        XCTAssertEqual(
            HighContrastText.TextStyle.title.color(increasedContrast: true),
            AppColors.textPrimary
        )
        XCTAssertEqual(
            HighContrastText.TextStyle.body.color(increasedContrast: true),
            AppColors.textPrimary
        )
    }
}
