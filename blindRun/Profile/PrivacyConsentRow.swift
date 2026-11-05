import SwiftUI

/// 一个撤回动作：可见标题、读屏标签、标识、是否可点、做什么。两端共用。
struct PrivacyRevokeAction {
    /// 可见标题。各项不相同：语音控制按可见标题找按钮。
    let title: String
    let label: String
    let identifier: String
    var isDisabled = false
    let perform: () -> Void
}

/// 「隐私与授权」一页摊开的那种版式：管什么、当前状态、撤回按钮、撤回结果。
/// 现在只有陪跑员端用（#530，只有一项）；盲人端 #754 起拆成两层，用下面的组件。
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

// MARK: - 盲人端两层版式（#754）

/// 第一层一行：图标、名称、灰字状态、箭头。可点区由 `contentShape` 撑满整行，高度不低于 64pt。
struct PrivacyConsentListRowLabel: View {
    /// 图标 32 + 间距 12 + 左边距 16：分隔线从文字起点画，和健康 App 一样。
    static let dividerInset: CGFloat = 60

    let title: String
    let status: String
    let systemImage: String
    let rgb: UInt32

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: UIColor(rgb: rgb)))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            SettingsChevron()
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 第二层的红字撤回行，放在一张分组卡里。整行可点、不低于 64pt
/// （64pt 在标签内部：外挂在按钮外的 frame 撑不大可点区，记忆 button-frame-outside-label-does-not-grow-hit-area）。
struct PrivacyRevokeRowButton: View {
    let action: PrivacyRevokeAction

    var body: some View {
        Button(action: action.perform) {
            // 同账户页「退出登录」的红字行写法：`SettingsRowLabel` 自带 64pt 与整行 `contentShape`。
            SettingsRowLabel(
                title: action.title,
                titleColor: action.isDisabled ? AppColors.textSecondary : AppColors.destructive,
                showsChevron: false
            )
        }
        .buttonStyle(.plain)
        .disabled(action.isDisabled)
        .accessibilityLabel(action.label)
        // 读屏标签比可见标题长；语音控制按可见标题找，所以把可见标题登记成输入名。
        .accessibilityInputLabels([Text(action.title)])
        .accessibilityIdentifier(action.identifier)
    }
}

/// 撤回之后那一句：成功、陪跑中被拦、保存失败。留在撤回行下面，同时由调用方朗读。
struct PrivacyRevokeNotice: Equatable {
    let text: String
    let isSuccess: Bool
}

/// 成功是绿字加对勾；被拦和失败是正文色加叹号。颜色不是唯一区分，句子本身说清了结果。
struct PrivacyRevokeNoticeLabel: View {
    let notice: PrivacyRevokeNotice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: notice.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(notice.isSuccess ? AppColors.success : AppColors.warning)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(AppFonts.body())
                .foregroundColor(notice.isSuccess ? AppColors.success : AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("privacyRevokeNotice")
    }
}
