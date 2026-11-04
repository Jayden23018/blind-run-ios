import XCTest
@testable import blindRun

/// 陪跑员首页 v3 底部胶囊的对比度（#694）。公式与阈值复用 `LowVisionChannelTests`，不另写一份。
final class AvailabilityPillContrastTests: XCTestCase {
    /// 陪跑员首页 v3 底部「接单中 · 进入接单」胶囊：深绿字压浅绿底（#694）。
    ///
    /// 字是 17pt semibold，够不上 large text 豁免，要 4.5:1。亮暗两套各算一次。
    func testAvailabilityPillTextReadableOnItsSurface() {
        let surface = AppColors.availabilityPillSurfaceTone
        let text = AppColors.availabilityPillTextTone

        let lightRatio = LowVisionChannelTests.contrastRatio(text.light, surface.light)
        XCTAssertGreaterThanOrEqual(
            lightRatio, LowVisionChannelTests.minimumContrast,
            "亮色模式下接单中胶囊只有 \(String(format: "%.2f", lightRatio)):1"
        )

        let darkRatio = LowVisionChannelTests.contrastRatio(text.dark, surface.dark)
        XCTAssertGreaterThanOrEqual(
            darkRatio, LowVisionChannelTests.minimumContrast,
            "暗色模式下接单中胶囊只有 \(String(format: "%.2f", darkRatio)):1"
        )

        // 验红：亮色那一对放到暗色外观里（字不换）只有约 1.4:1，必须算不过 ——
        // 防止有人只给暗色档换底色、忘了换字色，也防止公式恒真。
        XCTAssertLessThan(
            LowVisionChannelTests.contrastRatio(text.light, surface.dark), LowVisionChannelTests.minimumContrast,
            "浅色档的深绿字压暗色档的底，这条必须不达标"
        )
    }
}
