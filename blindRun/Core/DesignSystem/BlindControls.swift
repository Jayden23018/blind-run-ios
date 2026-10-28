import SwiftUI

// MARK: - Text Button Style

/// 盲人端的文字按钮：一行彩色字，没有底也没有描边 —— 比 `OutlineSecondaryButtonStyle` 再轻一档，
/// 给「展开填邀请码」「复制」「重试」这类附带操作用。
///
/// 可点区仍是**整行、≥64pt**（#527）：原来这些按钮没挂 frame，可点区只有那一行字高（约 22pt），
/// 并排时还会挤在一起。`.disabled` 时字与描边一起淡下去，免得「看着能按、按了没反应」。
/// `role: .destructive` 的按钮自动用 `destructive` 色，调用点不用再写一遍。
struct TextButtonStyle: ButtonStyle {
    var tint: Color = AppColors.primary
    var alignment: Alignment = .leading
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let color = configuration.role == .destructive ? AppColors.destructive : tint
        configuration.label
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(color)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: alignment)
            .contentShape(Rectangle())
            .buttonShapeOutlineIfNeeded(color: color)
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
    }
}

// MARK: - Menu Picker

/// 盲人端「点开选一项」：整行 ≥64pt 可点，当前选中的值写在行内。
///
/// 不用 `Picker(.menu)` 外挂 frame：外面那层只撑大布局，可点的菜单按钮真机量到 34pt
/// （记忆 `button-frame-outside-label-does-not-grow-hit-area`）。也不用分段控件：高度固定约 32pt，
/// AX5 下中文选项被挤成省略号。写法沿用资料页导盲犬三选一（#472）：`Menu` 包 `Picker`，64pt 写进标签内部。
///
/// `showsTitle` 为 false 时行内只显示当前值 —— 给上方已经有一行区块标题的地方用，免得同一句念两遍。
struct BlindMenuPicker<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    let valueText: String
    var showsTitle = true
    let accessibilityLabel: String
    let accessibilityHint: String
    @ViewBuilder let options: () -> Options

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                options()
            }
        } label: {
            HStack(spacing: 8) {
                if showsTitle {
                    Text(title)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                }
                Text(valueText)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(valueText)
        .accessibilityHint(accessibilityHint)
    }
}
