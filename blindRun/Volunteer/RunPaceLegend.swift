import SwiftUI

/// 「快 ▬ 慢」，渐变与路线同一套配色（原型 `.legend`）。
struct RunPaceLegend: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        HStack(spacing: 6) {
            Text("快")
            Capsule()
                .fill(LinearGradient(
                    colors: [0, 0.5, 1].map { Color(uiColor: RunPacePalette.color(fraction: $0, isDark: isDark)) },
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 56, height: 6)
            Text("慢")
        }
        .font(AppFonts.caption())
        .foregroundColor(AppColors.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(AppColors.background.opacity(0.88)))
    }
}
