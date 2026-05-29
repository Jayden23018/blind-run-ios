import Combine
import SwiftUI

// MARK: - Blind Runner Settings ViewModel

@MainActor
final class BlindRunnerSettingsViewModel: ObservableObject {
    @Published var errorMessage: String?

    func switchToVolunteer(appState: AppState) async {
        errorMessage = nil
        do {
            let request = SetRoleRequest(role: .volunteer)
            let response: SetRoleResponse = try await appState.apiClient.post("/api/user/role", body: request)
            appState.handleRoleSwitchSuccess(response: response, requestedRole: .volunteer)
        } catch let error as APIError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = "切换角色失败，请重试"
        }
    }
}

// MARK: - Blind Runner Settings View

struct BlindRunnerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = BlindRunnerSettingsViewModel()
    @State private var showLogoutConfirm = false
    @State private var showRoleSwitchConfirm = false

    var body: some View {
        List {
            Section {
                settingsRow("昵称", value: appState.blindProfile?.name ?? "未填写")
                settingsRow("当前角色", value: "视障跑者")
            }

            Section {
                NavigationLink("个人资料") {
                    BlindRunnerProfileView()
                }
                .accessibilityLabel("个人资料")
                .accessibilityHint("编辑盲人跑者资料和紧急联系人")

                Button("切换角色") {
                    showRoleSwitchConfirm = true
                }
                .accessibilityLabel("切换角色")
                .accessibilityHint("切换到志愿者身份")

                #if DEBUG
                if AppBuildChannel.current.allowsEnvironmentSwitcher {
                    Picker("API 环境", selection: $appState.currentEnvironment) {
                        ForEach(AppState.debugTestEnvironments, id: \.self) { environment in
                            Text(environment.displayName).tag(environment)
                        }
                    }
                    .accessibilityLabel("API 环境，\(appState.currentEnvironment.displayName)")
                }
                #endif

                NavigationLink("关于") {
                    AboutAidRunView()
                }
            }

            Section {
                Button("退出登录", role: .destructive) {
                    showLogoutConfirm = true
                }
                .accessibilityLabel("退出登录")
                .accessibilityHint("退出后需要重新登录，需要二次确认")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
        }
        .navigationTitle("设置")
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("确认退出", role: .destructive) {
                appState.clearSession()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后将清除当前登录状态，返回登录页。")
        }
        .alert("切换角色", isPresented: $showRoleSwitchConfirm) {
            Button("切换到志愿者") {
                Task { await viewModel.switchToVolunteer(appState: appState) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("如果有进行中的订单，系统会阻止切换角色。")
        }
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindRunnerSettingsView()
            .environmentObject(AppState())
    }
}
#endif
