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
