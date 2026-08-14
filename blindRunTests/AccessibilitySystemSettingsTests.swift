import SwiftUI
import XCTest
@testable import blindRun

/// 批次 D 里**能被单测钉住**的那两块。
///
/// 其余几项（焦点转移、进度点实心/空心、Reduce Motion 的抖动与转场、按钮描边、
/// 遮罩不透明）都是纯视图行为，XCTest 够不到，只能真机开系统开关人眼验 ——
/// 那份清单写在 PR 描述里，不在这里假装被覆盖了。
@MainActor
final class AccessibilitySystemSettingsTests: XCTestCase {

    // MARK: - 预约时间提示：颜色不再是唯一信号

    /// 合法与不合法此前是**同一句话**，只有颜色不同（灰 / 红）。
    /// 读屏用户没有颜色这条通道，选了过近的时间只会听到那句中性的规则说明。
    func testAppointmentHintChangesWordsNotJustColor() {
        let viewModel = BlindBookingViewModel()

        viewModel.appointmentTime = Date().addingTimeInterval(3 * 3600)
        let valid = viewModel.appointmentTimeHint

        viewModel.appointmentTime = Date().addingTimeInterval(60)
        let invalid = viewModel.appointmentTimeHint

        XCTAssertNotEqual(valid, invalid, "两种状态必须说不同的话，否则颜色仍是唯一信号")
    }

    /// 不合法那句要说清**当前这个选择**不行，不能只重复规则。
    func testInvalidAppointmentHintNamesTheProblem() {
        let viewModel = BlindBookingViewModel()
        viewModel.appointmentTime = Date().addingTimeInterval(60)

        let hint = viewModel.appointmentTimeHint
        XCTAssertTrue(hint.contains("太近"), "要指出当前选择哪里不行：\(hint)")
        XCTAssertTrue(hint.contains("改到"), "要给出下一步动作：\(hint)")
    }

    /// 两句都必须带那个分钟数：听的人无论落在哪一句，拿到的动作都是完整的。
    /// 且数字取自 `AppConstants`，写死 30 会在后端调整提前量时变成一句骗人的话。
    func testBothHintsCarryTheLeadTimeFromConstants() {
        let viewModel = BlindBookingViewModel()
        let minutes = "\(AppConstants.Timing.minimumBookingLeadMinutes)"

        viewModel.appointmentTime = Date().addingTimeInterval(3 * 3600)
        XCTAssertTrue(viewModel.appointmentTimeHint.contains(minutes))

        viewModel.appointmentTime = Date().addingTimeInterval(60)
        XCTAssertTrue(viewModel.appointmentTimeHint.contains(minutes))
    }

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
