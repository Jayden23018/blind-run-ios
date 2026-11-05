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
        let fill = AppColors.ButtonPalette.primaryFillTone
        let destructive = try XCTUnwrap(AppColors.tones.first { $0.name == "destructive" }?.tone)

        // 暗色危险按钮只过得了大字门槛，所以字号是这条断言成立的前提，一起钉住。
        XCTAssertEqual(AppFonts.primaryButton(), Font.title3.bold(), "主按钮字号变了，暗色危险按钮白字压 #FF453A 只剩 3.41:1，要按正文门槛重判")

        // #749：主按钮底色换成按钮专用的 `primaryFill`，暗色 `#0A6FE0` 让白字过正文门槛，不再靠大字例外。
        XCTAssertGreaterThanOrEqual(Self.contrast(white, fill.light), Self.bodyText)
        XCTAssertGreaterThanOrEqual(Self.contrast(white, fill.dark), Self.bodyText)
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

    // MARK: - #749 胶囊按钮的尺寸与成套配色

    /// 看得见的胶囊只有 52pt，可点区靠样式里上下各 6pt 的透明边距凑足 64pt。
    /// 有人把胶囊调高或边距调小时，这一条先红，而不是等真机审计。
    func testCapsuleButtonKeepsTheBlindTouchTargetAroundASmallerCapsule() {
        let metrics = AppButtonMetrics.self
        XCTAssertGreaterThanOrEqual(
            metrics.visibleHeight + 2 * metrics.verticalInset, AppTouchTarget.blindPrimary,
            "胶囊高 + 上下透明边距 < 64pt：盲人端可点区不够"
        )
        XCTAssertLessThan(metrics.visibleHeight, AppTouchTarget.blindPrimary, "定稿 ② 要求看得见的胶囊比可点区矮")
        XCTAssertEqual(metrics.cornerRadius, metrics.visibleHeight / 2, "默认高度时应正好是胶囊")
    }

    func testPressedFillsKeepTheLabelReadable() {
        let white: UInt32 = 0xFFFFFF
        let palette = AppColors.ButtonPalette.self
        for (name, tone) in [("primaryFillPressed", palette.primaryFillPressedTone)] {
            XCTAssertGreaterThanOrEqual(Self.contrast(white, tone.light), Self.bodyText, "\(name) 亮")
            XCTAssertGreaterThanOrEqual(Self.contrast(white, tone.dark), Self.bodyText, "\(name) 暗")
        }
        XCTAssertGreaterThanOrEqual(Self.contrast(white, palette.destructiveFillPressedTone.light), Self.bodyText)
        XCTAssertGreaterThanOrEqual(Self.contrast(white, palette.destructiveFillPressedTone.dark), Self.largeText)

        // 验红：原来的按下态是整块 75% 透明。白字压在 75% 的 `#0058C7`（叠在白底上 ≈ `#4082D5`）上
        // 只有 3.91:1 —— 那是这次改成「底色加深」的理由，公式必须真的拒它。
        XCTAssertLessThan(Self.contrast(0xFFFFFF, 0x4082D5), Self.bodyText)
    }

    func testSecondaryAndNeutralButtonsKeepTheirLabelsReadable() {
        let palette = AppColors.ButtonPalette.self
        let ink = palette.secondaryInkTone
        for fill in [palette.secondaryFillTone, palette.secondaryFillPressedTone] {
            XCTAssertGreaterThanOrEqual(Self.contrast(ink.light, fill.light), Self.bodyText, "次按钮蓝字压浅蓝底（亮）")
            XCTAssertGreaterThanOrEqual(Self.contrast(ink.dark, fill.dark), Self.bodyText, "次按钮蓝字压浅蓝底（暗）")
        }
        let label = (light: Self.rgb(.label, .light), dark: Self.rgb(.label, .dark))
        for fill in [palette.neutralFillTone, palette.neutralFillPressedTone] {
            XCTAssertGreaterThanOrEqual(Self.contrast(label.light, fill.light), Self.bodyText, "灰按钮字（亮）")
            XCTAssertGreaterThanOrEqual(Self.contrast(label.dark, fill.dark), Self.bodyText, "灰按钮字（暗）")
        }

        // 验红：暗色次按钮的字原来就是 `primary` 的 `#0A84FF`，压暗色浅蓝底过不了正文门槛 —— 这是换 `#409CFF` 的理由。
        XCTAssertLessThan(Self.contrast(0x0A84FF, palette.secondaryFillPressedTone.dark), Self.bodyText)
    }

    /// 浅底按钮压页面只有约 1.2:1，低视力用户靠描边认出它是按钮（WCAG 1.4.11 控件边界 3:1）。
    /// 页面底取两种：亮 白 / 分组灰 `#F2F2F7`，暗 黑 / `#1C1C1E`。
    func testButtonOutlinesStandOutFromThePage() {
        let palette = AppColors.ButtonPalette.self
        let lightPages: [UInt32] = [0xFFFFFF, 0xF2F2F7]
        let darkPages: [UInt32] = [0x000000, 0x1C1C1E]
        let boundary = Self.largeText
        for (name, tone) in [("次按钮描边", palette.secondaryInkTone), ("灰按钮描边", palette.neutralStrokeTone), ("主按钮底色", palette.primaryFillTone)] {
            for page in lightPages {
                XCTAssertGreaterThanOrEqual(Self.contrast(tone.light, page), boundary, "\(name) 压亮色页面 #\(String(page, radix: 16))")
            }
            for page in darkPages {
                XCTAssertGreaterThanOrEqual(Self.contrast(tone.dark, page), boundary, "\(name) 压暗色页面 #\(String(page, radix: 16))")
            }
        }
        // 验红：原来「关闭」（`FlowActionButton(.ghost)`）的描边 `#CDD2DC` 压白底只有 1.52:1。
        XCTAssertLessThan(Self.contrast(AppColors.Flow.ghostStrokeTone.light, 0xFFFFFF), boundary)
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
