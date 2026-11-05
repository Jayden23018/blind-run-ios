import SwiftUI

// MARK: - Primary Button

/// 全宽大按钮，盲人端主操作按钮最小高度 `AppTouchTarget.blindPrimary`（64pt）。
/// 支持普通和危险操作两种样式。
struct PrimaryButton: View {
    let title: String
    /// 标题下面一行小字（屏 3b「拨打120 / 急救电话」）。默认 nil，其余调用点不变。
    let subtitle: String?
    let isDestructive: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        subtitle: String? = nil,
        isDestructive: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isDestructive = isDestructive
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                VStack(spacing: 2) {
                    Text(title)
                        .font(AppFonts.primaryButton())
                    if let subtitle {
                        // 粗体：暗色档 `destructive`（#FF453A）压白字只有约 3.4:1，常规字重的正文过不了 4.5:1；
                        // 粗体按 WCAG 算「大字」，门槛 3:1（#506 真机截图发现）。
                        Text(subtitle)
                            .font(AppFonts.body().weight(.bold))
                    }
                }
                // 只在有副标题时居中，其余调用点保持原来的默认对齐（#506 code review B1）。
                .multilineTextAlignment(subtitle == nil ? .leading : .center)
            }
            .padding(.vertical, subtitle == nil ? 0 : AppSpacing.small)
        }
        .buttonStyle(PrimaryButtonStyle(isDestructive: isDestructive, isLoading: isLoading))
        .disabled(isLoading)
        .accessibilityLabel(subtitle.map { "\(title)，\($0)" } ?? title)
        .accessibilityHint(isDestructive ? "危险操作，需要二次确认" : "点击执行操作")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Primary Button Style

/// 实心主按钮的外观：`PrimaryButton` 自己用它，标签要自定义（带转圈、`NavigationLink`）的实心按钮也用它。
///
/// 🔴 **不要换回 `.buttonStyle(.borderedProminent)`**（守卫 `bordered-prominent` 会拦）。那个样式的字恒为白，
/// 底色取环境里的 tint，而 tint 在不同容器里是三个不同的值（#527）：
/// - 标签页容器里是 `AppColors.Flow.tabSelected`，**暗色档是纯白** ⇒ 白底白字，按钮整个看不见
///   （`VolunteerRunRecordView` 2026-09-25 截图撞过一次）；
/// - 标签页外面是 `AccentColor`，它没定义颜色时是系统蓝：白字亮色 4.02:1、暗色 3.65:1，正文过不了 4.5:1。
/// 所以底色与字色在这里成对给出，不读环境 tint。
///
/// 外形（#749，负责人 2026-11-05 定稿）：实心胶囊，看得见的部分 52pt 高、左右各收 12pt，可点区仍整行 ≥64pt。
/// 尺寸与理由在 `AppButtonMetrics`。
///
/// 对比度（WCAG 相对亮度公式，`PrimaryButtonContrastTests` / `ButtonChromeTests` 重算钉住）：
/// - 白字压主按钮底色 `ButtonPalette.primaryFill`：亮 `#0058C7` 6.52:1；暗 `#0A6FE0` 4.81:1。
/// - 危险操作白字压 `destructive`：亮 5.75:1；暗 `#FF453A` 3.41:1 —— 字是 `title3.bold`（20pt 粗体），
///   属 WCAG「大字」，门槛 3:1。**所以标签里别再挂常规字重的 `.font`**，那会让暗色危险按钮掉到门槛以下。
/// - 不可用态：`textSecondary` 压 `systemGray5`，亮 5.3:1、暗 6.5:1。原来登录页白字压 `systemGray4` 只有 1.5:1，
///   低视力用户读不出这枚按钮是什么，也就不知道「填好手机号它就会亮」。
/// - 按下：底色加深（白字 8.84 / 6.80）。原来整块变 75% 透明，白字掉到 3.91 / 3.15。
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive = false
    /// 提交中：按钮被 `.disabled` 挡住重复点击，但仍按可用态画（转圈压在原色上），
    /// 免得一按下去就变灰，看起来像出错。
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let looksDisabled = !isEnabled && !isLoading
        let ink = looksDisabled ? AppColors.textSecondary : Color.white
        configuration.label
            .font(AppFonts.primaryButton())
            .foregroundColor(ink)
            .tint(ink)
            .multilineTextAlignment(.center)
            // 换 `ButtonStyle` 会接管掉默认的按下反馈：按下态在 `fill` 里，不补按下去屏幕上什么都不动。
            .capsuleButtonChrome(fill: fill(looksDisabled: looksDisabled, isPressed: configuration.isPressed))
    }

    private func fill(looksDisabled: Bool, isPressed: Bool) -> Color {
        if looksDisabled { return AppColors.ButtonPalette.disabledFill }
        if isDestructive {
            return isPressed ? AppColors.ButtonPalette.destructiveFillPressed : AppColors.destructive
        }
        return isPressed ? AppColors.ButtonPalette.primaryFillPressed : AppColors.ButtonPalette.primaryFill
    }
}

// MARK: - Outline Secondary Button Style

/// 盲人端的次级按钮：浅蓝底 + 同色细描边 + 蓝字，形状与尺寸同主按钮（#749 定稿，照健康「请求他人共享」）。
///
/// 浅底而非实心，是为了让同一屏那个实心主操作保持唯一的主次地位；而**始终画出描边**
/// （苹果原样没有描边）是因为浅底压页面只有约 1.2:1，低视力用户靠轮廓认出「这是能按的」。
///
/// 原是 `BlindBookingView` 的私有 `VoiceStageSecondaryButtonStyle`，2026-10-05 提出来给
/// 通话确认页共用（真机截图评审：那一页两枚次按钮只是两行字，「重复当前状态」又是实心蓝、
/// 与拨号大按钮抢主次）。
struct OutlineSecondaryButtonStyle: ButtonStyle {
    /// 字色。不传 = 蓝色次按钮（浅蓝底、`secondaryInk` 字与描边，暗色 `#409CFF` 压浅蓝底 5.5:1）。
    /// 传了（目前只有求助「已发出」页传 `textPrimary`）= 中性操作：灰底、灰描边，同 `NeutralButtonStyle`。
    var tint: Color?
    /// false 时按内容收窄，给一排可选短语这类小标签用：只有胶囊底与描边，留白与可点高度由标签自己的 frame 决定。
    var fillsWidth = true
    /// 提交中被 `.disabled` 时要**看得出**按不了：底、描边与文字一起淡下去。不读它的话，
    /// 低视力用户看到的按钮与可用时一模一样，只会以为「按了没反应」。
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = AppColors.ButtonPalette.self
        let isAccent = tint == nil
        let ink = tint ?? palette.secondaryInk
        let fill: Color = isAccent
            ? (configuration.isPressed ? palette.secondaryFillPressed : palette.secondaryFill)
            : (configuration.isPressed ? palette.neutralFillPressed : palette.neutralFill)
        configuration.label
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .modifier(SecondaryChrome(fill: fill, stroke: isAccent ? ink : palette.neutralStroke, fillsWidth: fillsWidth))
            // 按下态在 `fill` 里（底色加深），字不变淡。
            .opacity(isEnabled ? 1 : 0.4)
    }

    private struct SecondaryChrome: ViewModifier {
        let fill: Color
        let stroke: Color
        let fillsWidth: Bool

        func body(content: Content) -> some View {
            if fillsWidth {
                content.capsuleButtonChrome(fill: fill, stroke: stroke)
            } else {
                // 固定圆角而不是 `Capsule()`：大字号下短语折成多行时，半径随高度变大的胶囊两端弧线会压到字。
                // 单行时 SwiftUI 把圆角夹到高度的一半，看起来仍是胶囊。
                let shape = RoundedRectangle(cornerRadius: AppButtonMetrics.cornerRadius, style: .continuous)
                content
                    .background(shape.fill(fill))
                    .overlay(shape.strokeBorder(stroke, lineWidth: AppButtonMetrics.strokeWidth))
                    .contentShape(shape)
            }
        }
    }
}

#Preview {
    VStack(spacing: AppSpacing.large) {
        PrimaryButton("提交预约") {}
        PrimaryButton("取消订单", isDestructive: true) {}
        PrimaryButton("加载中", isLoading: true) {}
    }
    .padding()
}
