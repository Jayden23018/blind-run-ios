import XCTest
@testable import blindRun

/// 跑步记录两端的数字色（#823，负责人 2026-11-07 批准「数字照健身上色」）。
///
/// 颜色只是 `VolunteerHome` 四色 + `success` 的别名，但用的地方换了：
/// 这里是指标格、单段表、汇总卡里的**数字**，压白卡（亮）/ `#1C1C1E` 卡（暗）各算一次 4.5:1。
/// 公式与阈值复用 `LowVisionChannelTests`。
final class RunRecordMetricColorContrastTests: XCTestCase {
    private let lightCard: UInt32 = 0xFFFFFF
    private let darkCard: UInt32 = 0x1C1C1E

    func testMetricColorsAreReadableOnBothCardSurfaces() {
        XCTAssertEqual(AppColors.Flow.surfaceTone.light, lightCard)
        XCTAssertEqual(AppColors.Flow.surfaceTone.dark, darkCard)
        XCTAssertEqual(AppColors.RunRecordMetric.tones.count, 5)
        for (name, tone) in AppColors.RunRecordMetric.tones {
            let light = LowVisionChannelTests.contrastRatio(tone.light, lightCard)
            XCTAssertGreaterThanOrEqual(light, LowVisionChannelTests.minimumContrast, "\(name) 压白卡只有 \(String(format: "%.2f", light)):1")
            let dark = LowVisionChannelTests.contrastRatio(tone.dark, darkCard)
            XCTAssertGreaterThanOrEqual(dark, LowVisionChannelTests.minimumContrast, "\(name) 压 #1C1C1E 卡只有 \(String(format: "%.2f", dark)):1")
        }
    }

    /// 验红：亮色档压暗卡必须不达标 —— 防止暗色直接沿用亮色，也防止公式恒真。
    func testLightMetricColorsFailOnTheDarkCard() {
        for (name, tone) in AppColors.RunRecordMetric.tones {
            XCTAssertLessThan(
                LowVisionChannelTests.contrastRatio(tone.light, darkCard), LowVisionChannelTests.minimumContrast,
                "\(name) 的亮色值压在暗色卡上不该达标，暗色档必须单独取值"
            )
        }
    }

    /// 只许是已批准取值的别名（design-direction §2 例外段）：不能悄悄长出第六种颜色。
    func testMetricColorsAreAliasesOfApprovedTones() {
        let approved = AppColors.VolunteerHome.cardTitleTones.map(\.tone)
            + AppColors.tones.filter { $0.name == "success" }.map(\.tone)
        for (name, tone) in AppColors.RunRecordMetric.tones {
            XCTAssertTrue(
                approved.contains { $0.light == tone.light && $0.dark == tone.dark },
                "\(name) 不是已批准的取值"
            )
        }
    }
}
