import SwiftUI

// MARK: - Primary Button

/// 全宽大按钮，盲人端主操作按钮最小高度 `AppTouchTarget.blindPrimary`（64pt）。
/// 支持普通和危险操作两种样式。
struct PrimaryButton: View {
    let title: String
    let isDestructive: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        isDestructive: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
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
                Text(title)
                    .font(AppFonts.primaryButton())
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTouchTarget.blindPrimary)
            .background(isDestructive ? AppColors.destructive : AppColors.primary)
            .cornerRadius(AppCornerRadius.medium)
        }
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityHint(isDestructive ? "危险操作，需要二次确认" : "点击执行操作")
        .accessibilityAddTraits(.isButton)
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
    /// 提交中被 `.disabled` 时要**看得出**按不了：描边与文字一起淡下去。不读它的话，
    /// 低视力用户看到的按钮与可用时一模一样，只会以为「按了没反应」。
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(tint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTouchTarget.blindPrimary)
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
