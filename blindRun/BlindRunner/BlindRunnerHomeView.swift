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

            #if DEBUG
            DebugTestingPanel()
                .environmentObject(appState)
                .padding(.horizontal, 32)
            #endif

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
struct DebugTestingPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var showEnvironmentConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("测试入口")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            Button {
                appState.returnToRoleSelectionForTesting()
            } label: {
                Text("返回角色选择")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("返回角色选择")
            .accessibilityHint("回到角色选择页，用于测试不同身份")

            Button {
                showEnvironmentConfirmation = true
            } label: {
                Text("切换测试模式：\(appState.currentEnvironment.displayName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("切换测试模式")
            .accessibilityHint("当前模式 \(appState.currentEnvironment.displayName)，点击后可切换并重新登录")
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .confirmationDialog("切换测试模式", isPresented: $showEnvironmentConfirmation) {
            Button("切换到 \(nextEnvironment.displayName) 并重新登录", role: .destructive) {
                appState.switchToNextEnvironmentForTesting()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("切换测试模式会清除当前登录状态，并返回登录页。")
        }
    }

    private var nextEnvironment: APIEnvironment {
        let allEnvironments = APIEnvironment.allCases
        guard let currentIndex = allEnvironments.firstIndex(of: appState.currentEnvironment) else {
            return .mock
        }
        return allEnvironments[(currentIndex + 1) % allEnvironments.count]
    }
}
#endif

#if DEBUG
#Preview {
    BlindRunnerHomeView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
