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
/// 对比度（WCAG 相对亮度公式，`LowVisionChannelTests.testPrimaryButtonStyleKeepsItsLabelReadable` 重算钉住）：
/// - 白字压 `primary`：亮 `#0058C7` 6.53:1；暗 `#0A84FF` 3.65:1 —— 字是 `title3.bold`（20pt 粗体），
///   属 WCAG「大字」，门槛 3:1。**所以标签里别再挂常规字重的 `.font`**，那会让暗色档掉到正文门槛以下。
/// - 不可用态：`textSecondary` 压 `systemGray5`，亮 5.3:1、暗 6.5:1。原来登录页白字压 `systemGray4` 只有 1.5:1，
///   低视力用户读不出这枚按钮是什么，也就不知道「填好手机号它就会亮」。
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
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTouchTarget.blindPrimary)
            .background(fill(looksDisabled: looksDisabled))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            // 换 `ButtonStyle` 会接管掉默认的按下反馈，不补这一行按下去屏幕上什么都不动。
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private func fill(looksDisabled: Bool) -> Color {
        if looksDisabled { return Color(uiColor: .systemGray5) }
        return isDestructive ? AppColors.destructive : AppColors.primary
    }
}

// MARK: - Outline Secondary Button Style

/// 盲人端的次级按钮：整行、描边、不填充，`minHeight` 同主按钮（64pt）。
///
/// 描边而非填充，是为了让同一屏那个实心主操作保持唯一的主次地位；而**始终画出描边**
/// （不是只在系统「按钮形状」打开时才画）是因为低视力用户靠轮廓认出「这是能按的」——
/// 只有一行彩色文字时，它和一句说明长得一样。
///
/// 原是 `BlindBookingView` 的私有 `VoiceStageSecondaryButtonStyle`，2026-10-05 提出来给
/// 通话确认页共用（真机截图评审：那一页两枚次按钮只是两行字，「重复当前状态」又是实心蓝、
/// 与拨号大按钮抢主次）。
struct OutlineSecondaryButtonStyle: ButtonStyle {
    var tint: Color = AppColors.primary
    /// false 时按内容收窄，给一排可选短语这类小标签用。可点高度由标签自己的 frame 决定。
    var fillsWidth = true
    /// 提交中被 `.disabled` 时要**看得出**按不了：描边与文字一起淡下去。不读它的话，
    /// 低视力用户看到的按钮与可用时一模一样，只会以为「按了没反应」。
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(tint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(minHeight: fillsWidth ? AppTouchTarget.blindPrimary : nil)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    .strokeBorder(tint, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            // 换 `ButtonStyle` 会接管掉默认的按下反馈，不补这一行按下去屏幕上什么都不动。
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
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
