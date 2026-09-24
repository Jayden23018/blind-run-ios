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
/// ⚠️ 改这里的任何取值，先跑 `LowVisionChannelTests` —— 它按 WCAG 相对亮度公式重算，
/// 在**四种组合**（亮/白底、亮/次级底、暗/黑底、暗/次级底）上都要求 ≥ 4.5:1。
/// 靠肉眼看「够深了吧」是这条缺陷第一次出现的原因。
///
/// 2026-09-21 改名：此前这里写的是 `AppColorContrastTests`，**全仓不存在这个类型** ——
/// 照着去跑只会「找不到就跳过」，而这行字的全部作用就是拦住凭肉眼改色值。
/// 指向一个不存在的检查，比不写更糟：它让人以为有东西在守着。
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

    /// 语音下单那块占满内容区的蓝底（`BlindBookingView.voiceStatusBlock`）。
    ///
    /// **它是背景色，所以不进 `tones`。** 那张表验的是「这个色当前景压在两种背景上」，
    /// 而这个色从不当前景 —— 硬塞进去只会得到一条方向反了的断言（暗色值压在纯黑上
    /// 只有 2.6:1，会把一个正确的取值判成不达标）。它自己的检查在
    /// `LowVisionChannelTests.testVoiceStageSurfaceKeepsWhiteTextReadable`：白字压在
    /// 它上面，亮暗两套都要过 4.5:1。
    ///
    /// 暗色**不能**沿用 `primary` 的 `#0A84FF`：白字压上去只有 3.38:1，正文不达标。
    /// 而这一块是**整个内容区**而不是一枚按钮，大面积亮蓝在暗色下也刺眼。
    /// `#0B4DA2` 白字 8.08:1。
    static let voiceStageSurface = dynamic(voiceStageSurfaceTone.light, voiceStageSurfaceTone.dark)

    /// `voiceStageSurface` 的取值，单独暴露给对比度用例 —— 理由同 `tones`：
    /// `Color` 要解析成 RGB 得先过 `UITraitCollection`，那在单测里是个不稳定的依赖。
    static let voiceStageSurfaceTone = Tone(light: 0x0058C7, dark: 0x0B4DA2)

    /// 志愿者「可服务」已开启时那条状态条的绿底（`VolunteerAvailabilitySlider`）。
    ///
    /// **和 `voiceStageSurface` 完全同一个形状，所以同样不进 `tones`**：它是背景，
    /// 白字压在它上面，而那张表验的是「这个色当前景压在两种背景上」。
    ///
    /// 🔴 **暗色不能沿用 `success` 的 `#30D158`：白字压上去只有 2.02:1**，
    /// 正文阈值是 4.5:1（WCAG 1.4.3）—— 那是本文件顶部点名的同一类缺陷
    /// （`systemGreen` 压白底 2.22:1）换了个方向又来一次。而这条状态条是志愿者首屏
    /// **底部唯一的常驻控件**，它读不清等于「我到底开没开」这件事没有视觉答案。
    /// 亮色 `#1B7F3B` 白字 5.07:1，暗色 `#0F5C2E` 白字 8.11:1。
    ///
    /// 自己的检查在 `LowVisionChannelTests.testAvailabilityOnSurfaceKeepsWhiteTextReadable`。
    static let availabilityOnSurfaceTone = Tone(light: 0x1B7F3B, dark: 0x0F5C2E)

    static let availabilityOnSurface = dynamic(
        availabilityOnSurfaceTone.light,
        availabilityOnSurfaceTone.dark
    )

    /// 陪跑进行中那一屏铺满的深灰底（`BlindActiveRunView`）。
    ///
    /// **亮暗两套取同一个值，是全 App 唯一一处不跟随系统外观的表面。** 理由不是审美：
    /// 这一屏是跑动中**户外**看的，内容只有几个巨数字 —— 深底白字在阳光下的可读性
    /// 远好于白底黑字（大面积白在户外会整片泛光，低视力用户尤其受影响）。
    /// 设计规格 `docs/research/blind-runner-ui-reference-study-20260915.md` §27 也把它锁成
    /// 「深灰而非纯黑」：纯黑会让 OLED 上的字出现拖影，`#1C1C1E` 正是系统在暗色下用的那一档。
    ///
    /// **它是背景色，所以不进 `tones`**（同 `voiceStageSurface` 的理由：那张表验的是
    /// 「这个色当前景压在两种背景上」，而它从不当前景）。它自己的检查在
    /// `LowVisionChannelTests` —— 白字与次级灰字压上去都要过 4.5:1。
    ///
    /// ⛔ **这里不会出现柠檬绿 `#D7FF3E`。** 那个色到今天为止**只存在于调研文档的提议里**，
    /// 代码中零处使用。就算将来引入，它也只属于「能按的东西」，而这一屏能按的是红色求助块
    /// —— 主数字用白（§28.1：行动色不与语义色混用，用它做主数字会稀释「哪里能按」这条线索）。
    static let activeRunSurface = dynamic(activeRunSurfaceTone.light, activeRunSurfaceTone.dark)

    /// `activeRunSurface` 的取值，单独暴露给对比度用例，理由同上。
    static let activeRunSurfaceTone = Tone(light: 0x1C1C1E, dark: 0x1C1C1E)

    /// 压在 `activeRunSurface` 上的次级文字（指标标签、顶部状态行）。
    ///
    /// **不能用 `textSecondary`**：那个色是为系统的亮/暗两种背景调的，亮色那一档 `#5C5C61`
    /// 压在 `#1C1C1E` 上只有 **2.56:1** —— 而这一屏在亮色模式下**底色仍然是深灰**，
    /// 于是整排标签会在亮色模式下糊掉。规格里那个 `#8A8A8F` 压 `#1C1C1E` 是 **4.95:1**。
    /// （两个数都按 WCAG 相对亮度公式手算，`LowVisionChannelTests` 会重算一遍钉住。）
    static let activeRunSecondaryText = dynamic(activeRunSecondaryTextTone.light, activeRunSecondaryTextTone.dark)

    static let activeRunSecondaryTextTone = Tone(light: 0x8A8A8F, dark: 0x8A8A8F)

    /// 陪跑中那块贴底的求助红块。同样亮暗同值，理由和上面那条是同一个，只是更隐蔽：
    ///
    /// 🔴 `destructive` 的**亮色档** `#C81E14` 压在 `#1C1C1E` 上只有 **2.96:1** ——
    /// 卡在 WCAG 1.4.11（用来识别控件边界的非文本内容要 3:1）线**下面**。
    /// 底色固定成深灰之后，跟随系统外观的红在亮色模式下就成了「深红压深灰」，
    /// 块的边界对低视力用户糊掉。暗色档 `#FF453A` 压同一个底是 4.99:1。
    ///
    /// 这不是理论问题：这块是陪跑中屏幕上**唯一**的控件，边界看不见等于这一屏没有可按的东西。
    /// 白色 31pt 粗体压在 `#FF453A` 上是 3.41:1 —— 按 WCAG 大字阈值（3:1）达标，
    /// 且与全 App 暗色模式下每一个 `PrimaryButton(isDestructive:)` 完全一致，不是新引入的取值。
    static let activeRunDestructive = dynamic(activeRunDestructiveTone.light, activeRunDestructiveTone.dark)

    static let activeRunDestructiveTone = Tone(light: 0xFF453A, dark: 0xFF453A)

    // MARK: 跑后运动记录（DECISIONS D8）

    /// 跑后记录的五个颜色。浅色取值是项目负责人定的（D8），深色取值按对比度补。
    ///
    /// **它们都不是正文色，所以不进 `tones`**（那张表按正文 4.5:1 卡，这里一个都过不了，也不该过）。
    /// 各自的用途决定了该用哪条线来验，检查在 `LowVisionChannelTests.testRunRecordPalette…`：
    /// - `tactileYellow`：**只当底色**，上面压黑字（12.32:1，亮暗同值）。
    /// - 其余四个：图形（路线、配速条、图标底），按 WCAG 1.4.11 的 3:1。
    ///
    /// ⚠️ 浅色下 `ropeOrange` 2.87、`paceMid` 2.61、`paceSlow` 1.88 压白底**都不到 3:1** ——
    /// 不能单独压在白底上当唯一的信息载体。阶段 4 的地图路线有白色描边，它们要对着描边与底图判，
    /// 且配速信息另有数字冗余（HANDOFF §7）。这是 D8 的取值，不在这里改。
    /// `paceFast` 的深色原值 `#3558F0` 压 `#1C1C1E` 只有 3.08，贴线，换成 `#5B7CFA`（4.63）。
    /// 盲道黄。视障跑者视图的主按钮底色（文字用黑色）、「最快」标签。
    static let tactileYellowTone = Tone(light: 0xF7BE00, dark: 0xF7BE00)
    /// 陪跑绳橙。回放里两点之间的连线、志愿时长图标底色。
    static let ropeOrangeTone = Tone(light: 0xFF6A13, dark: 0xFF6A13)
    /// 配速三档（快→中→慢），故意避开红绿（HANDOFF §5.1）。列表缩略图的路线用 `paceFast`。
    static let paceFastTone = Tone(light: 0x3558F0, dark: 0x5B7CFA)
    static let paceMidTone = Tone(light: 0x19B3A6, dark: 0x19B3A6)
    static let paceSlowTone = Tone(light: 0xF5B100, dark: 0xF5B100)

    static let runRecordTones: [(name: String, tone: Tone)] = [
        ("tactileYellow", tactileYellowTone),
        ("ropeOrange", ropeOrangeTone),
        ("paceFast", paceFastTone),
        ("paceMid", paceMidTone),
        ("paceSlow", paceSlowTone),
    ]

    static let tactileYellow = dynamic(tactileYellowTone.light, tactileYellowTone.dark)
    static let ropeOrange = dynamic(ropeOrangeTone.light, ropeOrangeTone.dark)
    static let paceFast = dynamic(paceFastTone.light, paceFastTone.dark)
    static let paceMid = dynamic(paceMidTone.light, paceMidTone.dark)
    static let paceSlow = dynamic(paceSlowTone.light, paceSlowTone.dark)

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
