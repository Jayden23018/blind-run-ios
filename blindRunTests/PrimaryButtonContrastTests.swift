import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// 实心主按钮的底色与字色（#527）。
///
/// 起因：`AccentColor` 资源没定义颜色、全仓又没有根 `.tint`，`.borderedProminent` 的白字压在系统蓝上
/// （亮 4.02:1、暗 3.65:1）；标签页容器里 tint 是 `Flow.tabSelected`，暗色档纯白 ⇒ 白底白字。
/// 修法是 `AccentColor` 取 `primary` 同值，实心按钮一律走 `PrimaryButtonStyle`（底色与字色成对给出）。
final class PrimaryButtonContrastTests: XCTestCase {

    private static let bodyText = 4.5
    /// WCAG 1.4.3 的「大字」（≥14pt 粗体）门槛。`PrimaryButtonStyle` 的字是 `title3.bold`（20pt 粗体）。
    private static let largeText = 3.0

    func testAccentColorAssetIsThePrimaryTone() throws {
        let primary = try Self.primaryTone()
        let accent = try XCTUnwrap(
            UIColor(named: "AccentColor", in: Bundle(for: AppState.self), compatibleWith: nil),
            "AccentColor 资源没有定义颜色，系统样式会落到系统蓝"
        )
        XCTAssertEqual(Self.rgb(accent, .light), primary.light, "AccentColor 亮色档应与 AppColors.primary 同值")
        XCTAssertEqual(Self.rgb(accent, .dark), primary.dark, "AccentColor 暗色档应与 AppColors.primary 同值")
    }

    func testPrimaryButtonStyleKeepsItsLabelReadable() throws {
        let white: UInt32 = 0xFFFFFF
        let primary = try Self.primaryTone()
        let destructive = try XCTUnwrap(AppColors.tones.first { $0.name == "destructive" }?.tone)

        // 暗色档只过得了大字门槛，所以字号是这条断言成立的前提，一起钉住。
        XCTAssertEqual(AppFonts.primaryButton(), Font.title3.bold(), "主按钮字号变了，暗色档白字压 primary 只剩 3.65:1，要按正文门槛重判")

        XCTAssertGreaterThanOrEqual(Self.contrast(white, primary.light), Self.bodyText)
        XCTAssertGreaterThanOrEqual(Self.contrast(white, primary.dark), Self.largeText)
        XCTAssertGreaterThanOrEqual(Self.contrast(white, destructive.light), Self.bodyText)
        XCTAssertGreaterThanOrEqual(Self.contrast(white, destructive.dark), Self.largeText)

        // 验红：被换掉的两种底色必须真的算不过，否则上面几条可能在一个恒真的公式上通过。
        XCTAssertLessThan(
            Self.contrast(white, AppColors.Flow.tabSelectedTone.dark), Self.largeText,
            "标签页里 `.borderedProminent` 的暗色底是 tabSelected（纯白），白字压上去看不见"
        )
        XCTAssertLessThan(Self.contrast(white, 0x0A84FF), Self.bodyText, "系统蓝暗色档压常规字重的白字过不了正文门槛")
    }

    func testDisabledPrimaryButtonLabelIsReadable() throws {
        let secondary = try XCTUnwrap(AppColors.tones.first { $0.name == "textSecondary" }?.tone)
        let lightFill = Self.rgb(.systemGray5, .light)
        let darkFill = Self.rgb(.systemGray5, .dark)

        XCTAssertGreaterThanOrEqual(Self.contrast(secondary.light, lightFill), Self.bodyText)
        XCTAssertGreaterThanOrEqual(Self.contrast(secondary.dark, darkFill), Self.bodyText)

        // 验红：登录页原来的不可用态是白字压 systemGray4（约 1.5:1）。
        XCTAssertLessThan(Self.contrast(0xFFFFFF, Self.rgb(.systemGray4, .light)), Self.largeText)
    }

    // MARK: - 辅助

    private static func primaryTone() throws -> AppColors.Tone {
        try XCTUnwrap(AppColors.tones.first { $0.name == "primary" }?.tone)
    }

    private static func rgb(_ color: UIColor, _ style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }

    /// https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
    private static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ rgb: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let raw = Double((rgb >> UInt32(shift)) & 0xFF) / 255
                return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (high, low) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (high + 0.05) / (low + 0.05)
    }
}
