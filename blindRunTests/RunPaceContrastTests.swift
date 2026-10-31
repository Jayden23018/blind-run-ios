import XCTest
@testable import blindRun

/// 「增强对比度」下配速颜色的形状冗余（#579，负责人 2026-10-28 定方案 A）：开关打开时路线描边加宽、
/// 色条有边框；关掉时与原来逐值相同。亮色、暗色都验。
@MainActor
final class RunPaceContrastTests: XCTestCase {

    func testIncreaseContrastAddsBordersAndWidensTheRouteOutlineInBothAppearances() {
        for isDark in [false, true] {
            let on = RunPaceContrast(isIncreased: true, isDark: isDark)
            XCTAssertGreaterThan(on.barBorderWidth, 0, "isDark=\(isDark)：开了增强对比度，色条要有边框")
            XCTAssertGreaterThan(on.routeOutlineWidth, RunRouteGlyph.outlineWidth, "isDark=\(isDark)：路线描边要加宽")
            // 描边宽出配速线的部分（两侧合计）至少翻一倍，才算看得出的差别。
            XCTAssertGreaterThanOrEqual(
                on.routeOutlineWidth - RunRouteGlyph.paceWidth,
                2 * (RunRouteGlyph.outlineWidth - RunRouteGlyph.paceWidth)
            )

            let off = RunPaceContrast(isIncreased: false, isDark: isDark)
            XCTAssertEqual(off.barBorderWidth, 0, "isDark=\(isDark)：没开时不加边框，外观与原来相同")
            XCTAssertEqual(off.routeOutlineWidth, RunRouteGlyph.outlineWidth, "isDark=\(isDark)：没开时描边宽度不变")
        }
    }

    /// 边框颜色压各自的页面底色要过 3:1（WCAG 1.4.11 图形对象）：亮色近黑压白，暗色纯白压黑。
    func testBorderColourStandsOutAgainstThePageInBothAppearances() {
        XCTAssertGreaterThanOrEqual(Self.contrast(RunPaceContrast(isIncreased: true, isDark: false).barBorderRGB, 0xFFFFFF), 3)
        XCTAssertGreaterThanOrEqual(Self.contrast(RunPaceContrast(isIncreased: true, isDark: true).barBorderRGB, 0x000000), 3)
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func luminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let raw = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
