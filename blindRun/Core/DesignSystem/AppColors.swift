import SwiftUI
import UIKit

// MARK: - App Colors

/// 语义色。**亮色模式下不用 iOS 系统语义色**，暗色模式下用。
///
/// 起因是实测：`systemOrange` 压在白底上只有 **2.20:1**、`systemGreen` **2.22:1**、
/// `systemRed` **3.55:1**、`systemBlue` **4.02:1** —— 正文阈值是 4.5:1（WCAG 1.4.3），
/// 四个全部不达标，而 `warning` 在本 App 里标的全是阻断提示。同一批颜色在**暗色模式下全部合格**
/// （10.22 / 10.39 / 6.16 / 5.76），所以问题只在亮色模式，暗色维持系统色不动 ——
/// 系统色随 iOS 版本微调，能不接管就不接管。
///
/// 这不是「顺手调深一点」：`VisionLevel.LOW_VISION` 在数据模型里是一等公民，
/// 低视力用户是本 App 的目标用户而不是边缘情况。对他们来说 2.20:1 的橙色阻断提示等于没有提示。
///
/// ⚠️ 改这里的任何取值，先跑 `AppColorContrastTests` —— 它按 WCAG 相对亮度公式重算，
/// 在**四种组合**（亮/白底、亮/次级底、暗/黑底、暗/次级底）上都要求 ≥ 4.5:1。
/// 靠肉眼看「够深了吧」是这条缺陷第一次出现的原因。
enum AppColors {
    /// 每个语义色的亮/暗两套取值，测试直接读这张表。
    ///
    /// 单独抽出来是为了让检查能覆盖**取值本身**而不是覆盖 `Color`——
    /// `Color` 要解析成 RGB 得先过 `UITraitCollection`，那在单测里是个不稳定的依赖。
    struct Tone {
        let light: UInt32
        let dark: UInt32
    }

    static let tones: [(name: String, tone: Tone)] = [
        ("primary", Tone(light: 0x0058C7, dark: 0x0A84FF)),
        ("destructive", Tone(light: 0xC81E14, dark: 0xFF453A)),
        ("warning", Tone(light: 0xB25000, dark: 0xFF9F0A)),
        ("success", Tone(light: 0x1B7F3B, dark: 0x30D158)),
        ("textSecondary", Tone(light: 0x5C5C61, dark: 0xAEAEB2)),
    ]

    static let primary = dynamic(0x0058C7, 0x0A84FF)
    static let destructive = dynamic(0xC81E14, 0xFF453A)
    static let warning = dynamic(0xB25000, 0xFF9F0A)
    static let success = dynamic(0x1B7F3B, 0x30D158)

    /// 次级文本。系统的 `secondaryLabel` 在亮色下只有 3.26:1 —— 它是给「可以看不清」的
    /// 装饰性文本准备的，而本 App 用它承载状态说明和位置摘要，那是必须读得清的内容。
    static let textSecondary = dynamic(0x5C5C61, 0xAEAEB2)

    // 这三个继续用系统语义色：`label` 已经是 21:1，两个背景色本来就是对比的**基准**而非前景。
    static let background = Color(uiColor: .systemBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    static let textPrimary = Color(uiColor: .label)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    /// `0xRRGGBB` → `UIColor`。只在本文件的调色板里用，不对外做通用工具。
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - App Fonts

enum AppFonts {
    static func largeTitle() -> Font {
        .largeTitle.bold()
    }

    static func title() -> Font {
        .title2.bold()
    }

    static func body() -> Font {
        .body
    }

    static func caption() -> Font {
        .caption
    }

    static func primaryButton() -> Font {
        .title3.bold()
    }
}
