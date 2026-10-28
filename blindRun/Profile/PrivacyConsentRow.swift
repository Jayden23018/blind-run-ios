import SwiftUI

/// 「隐私与授权」页一项同意的版式（#393 盲人端、#530 陪跑员端共用）：管什么、当前状态、撤回按钮、撤回结果。
/// 两端用同一份，交互才一致。
struct PrivacyRevokeAction {
    /// 可见标题。各项不相同：语音控制按可见标题找按钮。
    let title: String
    let label: String
    let identifier: String
    var isDisabled = false
    let perform: () -> Void
}

struct PrivacyConsentRow: View {
    let title: String
    let purpose: String
    let status: String
    let revoke: PrivacyRevokeAction?
    let notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(purpose)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(status)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let revoke {
                // 64pt 写在标签内部：外挂在按钮外的 frame 撑不大可点区（记忆 button-frame-outside-label-does-not-grow-hit-area）。
                Button(action: revoke.perform) {
                    Text(revoke.title)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(12)
                }
                .disabled(revoke.isDisabled)
                .accessibilityLabel(revoke.label)
                .accessibilityIdentifier(revoke.identifier)
            }
            if let notice {
                Text(notice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
