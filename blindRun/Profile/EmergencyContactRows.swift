import SwiftUI

// 紧急联系人页的几种行（#746）。照苹果「健康 › 医疗急救卡」与「通讯录」的分组列表：
// 联系人行带姓名首字头像；添加区一行一个动作，前面一枚系统样式的图标。

// MARK: - 联系人行

/// 行里只放内容，整行进编辑页（#606）。读屏标签由页面传进来，这里不拼。
struct EmergencyContactRowLabel: View {
    let contact: EmergencyContactResponse

    @ScaledMetric(relativeTo: .body) private var avatarSide: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var name: String { contact.name?.nilIfBlank ?? "未命名联系人" }

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            // AX 字号下头像会把名字挤成一字一行，那一档不画（纯装饰，读屏本来就不念）。
            if !dynamicTypeSize.isAccessibilitySize {
                FlowAvatar(
                    name: name,
                    diameter: avatarSide,
                    background: AppColors.primary.opacity(0.12),
                    foreground: AppColors.primary,
                    placeholder: "联"
                )
            }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(name)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if contact.isPrimary == true {
                    EmergencyContactPrimaryBadge()
                }
                Text(detailLine)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AppFonts.caption().weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppSpacing.xSmall)
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 关系在前、掩码号码在后：和医疗急救卡一样先说「这是谁」，再说号码。
    private var detailLine: String {
        let phone = contact.maskedPhone ?? "未填写手机号"
        guard let relationship = contact.relationship?.nilIfBlank else { return phone }
        return "\(relationship) · \(phone)"
    }
}

/// 「主联系人」标记。放在名字下面单独一行，不和名字挤一行：长名字和大字号下不会把它挤成「主…」。
struct EmergencyContactPrimaryBadge: View {
    var body: some View {
        Label("主联系人", systemImage: "star.fill")
            .font(AppFonts.caption().weight(.semibold))
            .foregroundColor(AppColors.primary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 2)
            .background(AppColors.primary.opacity(0.12), in: Capsule())
            .accessibilityHidden(true)
    }
}

// MARK: - 添加区的行

/// 「从通讯录添加」「手动输入」两行共用：左边一枚实心圆图标，右边一句动词。
struct EmergencyContactAddRowLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(isEnabled ? tint : AppColors.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(AppFonts.body().weight(.semibold))
                // 写死颜色后系统不再把禁用态变灰，要自己分开。
                .foregroundColor(isEnabled ? AppColors.textPrimary : AppColors.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - 表单里的标签行

/// 照「健康 › 编辑信息」：左边标签、右边输入。标签对读屏隐藏，输入框自己的标签已经说了是哪一格。
/// AX 字号下改成标签在上、输入框在下，免得输入框被挤成一字宽。
struct EmergencyContactLabelledField<Input: View>: View {
    let title: String
    @ViewBuilder let input: () -> Input

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 64

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    label
                    input()
                }
            } else {
                HStack(spacing: AppSpacing.medium) {
                    label.frame(width: labelWidth, alignment: .leading)
                    input()
                }
            }
        }
        .frame(minHeight: AppTouchTarget.blindPrimary)
    }

    private var label: some View {
        Text(title)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityHidden(true)
    }
}
