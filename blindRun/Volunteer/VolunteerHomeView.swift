import SwiftUI

// MARK: - Volunteer Home View (Placeholder)

/// 志愿者首页占位。
/// 后续 PR 将替换为完整的首页实现（地图、附近订单、可服务开关等）。
struct VolunteerHomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            HighContrastText("志愿者首页", style: .title)
            HighContrastText("待实现", style: .caption)
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.background)
    }
}

#if DEBUG
#Preview {
    VolunteerHomeView()
        .environmentObject(AppState())
}
#endif
