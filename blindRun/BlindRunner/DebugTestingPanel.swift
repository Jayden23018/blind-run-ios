import SwiftUI

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
        let allEnvironments = AppState.debugTestEnvironments
        guard let currentIndex = allEnvironments.firstIndex(of: appState.currentEnvironment) else {
            return .mock
        }
        return allEnvironments[(currentIndex + 1) % allEnvironments.count]
    }
}
#endif
