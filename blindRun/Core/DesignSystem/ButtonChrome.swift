import SwiftUI
import UIKit

// MARK: - 按钮外形（#749）

/// 整行按钮的尺寸。负责人 2026-11-05 定稿：实心胶囊，「整个按钮的大小要做的克制一点」，选尺寸 ②。
///
/// **看得见的胶囊比可点区小**：胶囊高 52pt、左右各收 12pt，而可点区仍是整行、≥64pt。
/// 照的是 iOS 27 真机上量到的苹果按钮：健身「开始使用」325×51pt、健康问卷「完成」约 356×50pt
/// （`docs/research/primary-button-restyle-20261105.md` §3）。
///
/// 🔴 可点区靠的是 `chromeInset` 那两圈**挂在样式里面**的透明边距，加上 `contentShape(Rectangle())`。
/// 别把边距挪到 `Button` 外面：外面那层只撑大布局，撑不大可点区
/// （记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
/// `PrimaryButtonContrastTests` 钉住「胶囊高 + 上下边距 ≥ 64」。
enum AppButtonMetrics {
    /// 看得见的胶囊最小高度。字放大后胶囊跟着文字长高，这里只是下限。
    static let visibleHeight: CGFloat = 52
    /// 胶囊上下各留的透明可点区，凑足 `AppTouchTarget.blindPrimary`。
    static let verticalInset: CGFloat = (AppTouchTarget.blindPrimary - visibleHeight) / 2
    /// 胶囊左右各收进的距离。收进去的部分仍可点。
    static let horizontalInset: CGFloat = 12
    /// 圆角。默认高度时正好是胶囊（52 / 2）；大字号长高后封顶在这里，不会变成椭圆切掉字的四角。
    static let cornerRadius: CGFloat = visibleHeight / 2
    /// 字到胶囊左右边的最小距离：圆角那一段放不下字。
    static let labelHorizontalPadding: CGFloat = 20
    /// 字到胶囊上下边的最小距离：大字号时胶囊由字撑高，字不能贴边。
    static let labelVerticalPadding: CGFloat = 8
    /// 次按钮与灰按钮的描边宽度。
    static let strokeWidth: CGFloat = 1.5
}

// MARK: - 按钮颜色

extension AppColors {
    /// 按钮专用的底色与字色，**只给按钮用**，不进 `tones`、不当全局语义色。
    ///
    /// 都是不透明色：半透明底压在不同页面底上会算出不同的对比度，用例就钉不住了。
    /// 对比度由 `PrimaryButtonContrastTests` 逐对、亮暗各算一次（WCAG 相对亮度公式）。
    enum ButtonPalette {
        /// 主按钮底色。暗色不用 `primary` 的 `#0A84FF`（白字 3.65:1，只靠「20pt 粗体算大字」过线），
        /// 换深一档的 `#0A6FE0`：白字 4.81:1，压黑底仍有 4.36:1 的外形（负责人 2026-11-05 认可）。
        static let primaryFillTone = AppColors.Tone(light: 0x0058C7, dark: 0x0A6FE0)
        /// 按下：底色加深约 20%。原来是整块变 75% 透明，白字掉到 3.91:1（暗色 3.15:1）。
        static let primaryFillPressedTone = AppColors.Tone(light: 0x00469F, dark: 0x0859B3)
        static let destructiveFillPressedTone = AppColors.Tone(light: 0xA01810, dark: 0xCC372E)

        /// 次按钮：浅蓝底 + 同色细描边 + 蓝字（照健康「请求他人共享」，描边是我们加的：
        /// 浅底压页面只有约 1.2:1，低视力用户靠轮廓认出这是按钮）。
        static let secondaryFillTone = AppColors.Tone(light: 0xE0EBF8, dark: 0x0B2440)
        static let secondaryFillPressedTone = AppColors.Tone(light: 0xCCDDF3, dark: 0x0D2E52)
        /// 次按钮的字与描边。暗色用 `#409CFF`（系统蓝在「增强对比度」下的取值）：
        /// `#0A84FF` 压暗色浅蓝底只有 3.75:1。
        static let secondaryInkTone = AppColors.Tone(light: 0x0058C7, dark: 0x409CFF)

        /// 灰按钮（上一步、关闭）：灰底 + 灰描边 + 主文字色。
        static let neutralFillTone = AppColors.Tone(light: 0xE9E9EE, dark: 0x3A3A3C)
        static let neutralFillPressedTone = AppColors.Tone(light: 0xDCDCE1, dark: 0x48484A)
        /// 描边压白底 4.16:1、压黑底 4.14:1，过控件边界的 3:1。原来「关闭」的描边 `#CDD2DC` 压白底只有 1.52:1。
        static let neutralStrokeTone = AppColors.Tone(light: 0x7C7C80, dark: 0x6E6E73)

        static let primaryFill = color(primaryFillTone)
        static let primaryFillPressed = color(primaryFillPressedTone)
        static let destructiveFillPressed = color(destructiveFillPressedTone)
        static let secondaryFill = color(secondaryFillTone)
        static let secondaryFillPressed = color(secondaryFillPressedTone)
        static let secondaryInk = color(secondaryInkTone)
        static let neutralFill = color(neutralFillTone)
        static let neutralFillPressed = color(neutralFillPressedTone)
        static let neutralStroke = color(neutralStrokeTone)
        /// 不可用：`textSecondary` 压 `systemGray5`，亮 5.3:1、暗 6.3:1（`PrimaryButtonContrastTests`）。
        static let disabledFill = Color(uiColor: .systemGray5)

        private static func color(_ tone: AppColors.Tone) -> Color {
            Color(uiColor: UIColor { traits in
                UIColor(rgb: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
            })
        }
    }
}

// MARK: - 外形修饰符

extension View {
    /// 整行按钮的外形：字 → 胶囊底（与可选描边）→ 透明的可点边距。各按钮样式共用，不直接在页面里调用。
    ///
    /// - Parameter minWidth: 看得见的胶囊最小宽度（「上一步」那种按内容收窄的按钮用）。
    func capsuleButtonChrome(
        fill: Color,
        stroke: Color? = nil,
        fillsWidth: Bool = true,
        minWidth: CGFloat? = nil
    ) -> some View {
        modifier(CapsuleButtonChrome(fill: fill, stroke: stroke, fillsWidth: fillsWidth, minWidth: minWidth))
    }

    /// 几枚按钮并排在一行里（下单页底栏「上一步 / 提交预约」）：胶囊只变矮、不左右收进，字边距也收小。
    ///
    /// 定稿 ② 的规则（负责人 2026-11-05）。不这样做的话，最大字号下「提交预约」被两边各 12pt 的收进
    /// 加 20pt 的字边距挤到一行只放得下一个字。挂在那一行的 `HStack` 上。
    func capsuleButtonsInRow() -> some View {
        environment(\.capsuleButtonInRow, true)
    }
}

private struct CapsuleButtonInRowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var capsuleButtonInRow: Bool {
        get { self[CapsuleButtonInRowKey.self] }
        set { self[CapsuleButtonInRowKey.self] = newValue }
    }
}

private struct CapsuleButtonChrome: ViewModifier {
    let fill: Color
    let stroke: Color?
    let fillsWidth: Bool
    let minWidth: CGFloat?
    @Environment(\.capsuleButtonInRow) private var inRow

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppButtonMetrics.cornerRadius, style: .continuous)
        content
            .padding(.horizontal, inRow ? AppSpacing.medium : AppButtonMetrics.labelHorizontalPadding)
            .padding(.vertical, AppButtonMetrics.labelVerticalPadding)
            .frame(minWidth: minWidth, maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: AppButtonMetrics.visibleHeight)
            .background(shape.fill(fill))
            .overlay {
                if let stroke {
                    shape.strokeBorder(stroke, lineWidth: AppButtonMetrics.strokeWidth)
                }
            }
            .padding(.horizontal, inRow ? 0 : AppButtonMetrics.horizontalInset)
            .padding(.vertical, AppButtonMetrics.verticalInset)
            .contentShape(Rectangle())
    }
}

// MARK: - 灰按钮

/// 灰按钮：「上一步」「关闭」这类退出 / 返回操作。灰底 + 灰描边 + 主文字色，形状同主按钮。
///
/// 弹层的「关闭」原来用 `FlowActionButton(.ghost)`（白底、`#CDD2DC` 描边，压白底 1.52:1）。
/// `.ghost` 本身没改：它在订单流程里与黄色主按钮成套，那一组的形状另议。
struct NeutralButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .capsuleButtonChrome(
                fill: configuration.isPressed ? AppColors.ButtonPalette.neutralFillPressed : AppColors.ButtonPalette.neutralFill,
                stroke: AppColors.ButtonPalette.neutralStroke
            )
            // 不可用时字与描边一起淡下去，免得「看着能按、按了没反应」（同 `OutlineSecondaryButtonStyle`）。
            .opacity(isEnabled ? 1 : 0.4)
    }
}
