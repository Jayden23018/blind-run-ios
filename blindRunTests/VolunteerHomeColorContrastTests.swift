import XCTest
@testable import blindRun

/// 陪跑员首页 v3 的三种卡名色（负责人 2026-11-04 看截图后要求：陪伴时长天青、连续陪跑橙、评分琥珀）。
///
/// 卡名是 15pt semibold 的**字**，够不上 large text 豁免，要 4.5:1。
/// 亮色压白卡 `#FFFFFF`、暗色压深色卡 `#1C1C1E`（`AppColors.Flow.surfaceTone`）各算一次。
/// 公式与阈值复用 `LowVisionChannelTests`，不另写一份。
final class VolunteerHomeColorContrastTests: XCTestCase {
    private let lightCard: UInt32 = 0xFFFFFF
    private let darkCard: UInt32 = 0x1C1C1E

    func testCardTitleColorsAreReadableOnBothCardSurfaces() {
        XCTAssertEqual(AppColors.VolunteerHome.cardTitleTones.count, 3, "三种卡名色都要进这张表")
        XCTAssertEqual(AppColors.Flow.surfaceTone.light, lightCard)
        XCTAssertEqual(AppColors.Flow.surfaceTone.dark, darkCard)
        for (name, tone) in AppColors.VolunteerHome.cardTitleTones {
            let light = LowVisionChannelTests.contrastRatio(tone.light, lightCard)
            XCTAssertGreaterThanOrEqual(light, LowVisionChannelTests.minimumContrast, "\(name) 亮色只有 \(String(format: "%.2f", light)):1")
            let dark = LowVisionChannelTests.contrastRatio(tone.dark, darkCard)
            XCTAssertGreaterThanOrEqual(dark, LowVisionChannelTests.minimumContrast, "\(name) 暗色只有 \(String(format: "%.2f", dark)):1")
        }
    }

    /// 验红：亮色档的深色字放到暗色卡上必须不达标 —— 防止只给一套取值、暗色直接沿用亮色，也防止公式恒真。
    func testLightTitleColorsFailOnTheDarkCard() {
        for (name, tone) in AppColors.VolunteerHome.cardTitleTones {
            XCTAssertLessThan(
                LowVisionChannelTests.contrastRatio(tone.light, darkCard), LowVisionChannelTests.minimumContrast,
                "\(name) 的亮色值压在暗色卡上不该达标，暗色档必须单独取值"
            )
        }
    }

    /// 连续陪跑与评分并排时要是**两种**颜色（负责人原话：「他们两个应该是不同的颜色」）。
    func testStreakAndRatingUseDifferentColors() {
        let streak = AppColors.VolunteerHome.streakOrangeTone
        let rating = AppColors.VolunteerHome.ratingAmberTone
        XCTAssertNotEqual(streak.light, rating.light)
        XCTAssertNotEqual(streak.dark, rating.dark)
    }
}
