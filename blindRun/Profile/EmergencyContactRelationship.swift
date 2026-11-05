import SwiftUI

// MARK: - 关系预设

/// 紧急联系人的「关系」预设（#746）。
///
/// 照苹果「健康 › 医疗急救卡」：选好联系人之后从列表里选关系，不用手打 —— 读屏用户打字最慢。
/// 后端字段是自由文本（长度上限见 `EmergencyContactRules.maxRelationshipLength`），预设只在客户端；
/// 存的值不在预设里时按「自定义」显示，原样保留。
enum EmergencyContactRelationship {
    /// Mock 种子用的是「家人」，所以它必须在预设里，否则老数据全显示成自定义。
    static let presets = ["家人", "父母", "配偶", "子女", "兄弟姐妹", "朋友", "同事", "邻居"]

    enum Selection: Equatable {
        case none
        case preset(String)
        case custom(String)
    }

    static func selection(for stored: String) -> Selection {
        let value = stored.trimmed
        if value.isEmpty { return .none }
        return presets.contains(value) ? .preset(value) : .custom(value)
    }

    /// 表单上「关系」那一行右侧显示的字。
    static func displayValue(for stored: String) -> String {
        switch selection(for: stored) {
        case .none: return "未填写"
        case .preset(let value), .custom(let value): return value
        }
    }
}

// MARK: - 关系选择页

/// 表单里点「关系」推进来的一页：预设一组、自定义一组、「不填写」一组。选完自动返回。
struct EmergencyContactRelationshipPicker: View {
    @Binding var relationship: String
    @Environment(\.dismiss) private var dismiss
    @State private var customText = ""
    @FocusState private var isCustomFocused: Bool

    private var selection: EmergencyContactRelationship.Selection {
        EmergencyContactRelationship.selection(for: relationship)
    }

    var body: some View {
        List {
            Section {
                ForEach(EmergencyContactRelationship.presets, id: \.self) { preset in
                    choiceRow(preset, isSelected: selection == .preset(preset)) { choose(preset) }
                }
            }

            Section {
                TextField("输入其他关系", text: $customText)
                    .focused($isCustomFocused)
                    .submitLabel(.done)
                    .onSubmit(useCustom)
                    .frame(minHeight: AppTouchTarget.blindPrimary)
                    .accessibilityLabel("自定义关系")
                    .accessibilityHint("输入后按完成")
                    .accessibilityIdentifier("emergencyContactRelationshipCustomField")
                Button(action: useCustom) {
                    rowLabel("使用这个关系", color: customText.trimmed.isEmpty ? AppColors.textSecondary : AppColors.primary)
                }
                .disabled(customText.trimmed.isEmpty)
                .accessibilityHint("把上面输入的关系填进表单")
            } header: {
                Text("其他").foregroundColor(AppColors.textSecondary)
            }

            Section {
                choiceRow("不填写", isSelected: selection == .none) { choose("") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关系")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if case .custom(let value) = selection { customText = value }
        }
    }

    private func choose(_ value: String) {
        relationship = value
        dismiss()
    }

    private func useCustom() {
        let value = customText.trimmed
        guard !value.isEmpty else { return }
        choose(value)
    }

    private func choiceRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                Text(title)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.primary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func rowLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
    }
}
