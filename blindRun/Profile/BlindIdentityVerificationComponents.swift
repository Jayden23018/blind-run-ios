import SwiftUI
import UIKit

// 实名认证页（#751）的界面零件。只给 `BlindIdentityVerificationView` 用，单独成文件是因为那个文件超过 400 行上限。

// MARK: - Status Row Style

/// 状态行的内边距与读屏标签。看得见的字比读屏念的短，读屏仍念完整引导，和改版前一致。
struct BlindIdentityStatusRowStyle: ViewModifier {
    let status: BlindVerifyStatus

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("当前实名状态，\(status.displayName)")
            .accessibilityValue(status.guidanceMessage)
            .accessibilityIdentifier("blindIdentityStatusRow")
    }
}

// MARK: - Headers

/// 未认证 / 未通过 / 状态未知：左上一块图标，下面大标题和一句说明（照钱包「添加身份证」、陪跑员 #699）。
struct BlindIdentityLeadingHeader: View {
    let systemImage: String
    let tileColor: Color
    let title: String
    let subtitle: String
    @ScaledMetric(relativeTo: .largeTitle) private var tileSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 图标只是装饰，读屏不念；白字压在 `primarySolidSurface` / `destructive` 上。
            Image(systemName: systemImage)
                .font(.system(size: tileSize * 0.48, weight: .bold))
                .foregroundColor(.white)
                .frame(width: tileSize, height: tileSize)
                .background(tileColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
                .padding(.bottom, 4)
            Text(title)
                .font(.title.bold())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// 已认证：居中的绿色徽章、「已实名认证」、一句「可以正常预约跑步。」。
struct BlindIdentityVerifiedHeader: View {
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: badgeSize * 0.5))
                .foregroundColor(AppColors.success)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(AppColors.success.opacity(0.14)))
                .accessibilityHidden(true)
                .padding(.bottom, 4)
            Text("已实名认证")
                .font(.title.bold())
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("可以正常预约跑步。")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Identity Field Row

/// 字段名在左、输入在右的一行（照健康「详细信息」、陪跑员 `RegistrationTextFieldRow`）。
/// 那个组件没有密文输入，读屏标签也只念字段名，这里要保留原有的「必填」标签与密文，所以另写一个。
/// 辅助功能字号下改成上下排：并排时输入框会被挤到只剩一两个字宽。
struct BlindIdentityFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    let errorMessage: String?
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 84

    var body: some View {
        let stacksVertically = dynamicTypeSize.isAccessibilitySize
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        VStack(alignment: .leading, spacing: 4) {
            layout {
                // 读屏念的是输入框自己的标签，这一行字只给眼睛看，免得同一个字段名念两遍。
                Text(title)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .frame(width: stacksVertically ? nil : labelWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                field
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(accessibilityValue)
                    .accessibilityHint(accessibilityHint)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(errorMessage)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.top, stacksVertically ? 12 : 0)
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

// MARK: - Repeat Status Row

/// 状态卡最后一行「重复当前状态」（同 #747 紧急联系人页）。整行 ≥ 64pt 可点，图标只是装饰。
struct BlindIdentityRepeatStatusRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)
                Text("重复当前状态")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重复当前状态")
        .accessibilityHint("点击后重新播报当前实名状态")
        .accessibilityIdentifier("blindIdentityRepeatStatusRow")
    }
}

// MARK: - Messages

/// 表单下面的几条提示：进后台被清空、不同意、提交结果。文案与标识和改版前一样。
struct BlindIdentityMessageList: View {
    let clearedOnBackgroundNotice: String?
    let consentDeclinedNotice: String?
    let successMessage: String?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let clearedOnBackgroundNotice {
                message(clearedOnBackgroundNotice, color: AppColors.textPrimary)
                    .accessibilityIdentifier("blindIdentityClearedOnBackgroundNotice")
            }
            if let consentDeclinedNotice {
                message(consentDeclinedNotice, color: AppColors.textSecondary)
                    .accessibilityIdentifier("blindIdentityConsentDeclinedNotice")
            }
            if let successMessage {
                message(successMessage, color: AppColors.textPrimary)
            }
            if let errorMessage {
                message(errorMessage, color: AppColors.destructive)
            }
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}
