import SwiftUI

// MARK: - Blind Runner Home View (Placeholder)

/// 盲人跑者首页占位。
/// 后续 PR 将替换为完整的首页实现（地图、订单状态、预约入口等）。
struct BlindRunnerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            HighContrastText("盲人跑者首页", style: .title)
            HighContrastText("待实现", style: .caption)
                .padding(.top, 8)

            Spacer()

            // 重复当前状态按钮（盲人端必需）
            PrimaryButton("重复当前状态") {
                speechService.repeatCurrentStatus()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.background)
        .onAppear {
            speechService.speak("欢迎来到助盲跑")
        }
    }
}

#if DEBUG
#Preview {
    BlindRunnerHomeView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
