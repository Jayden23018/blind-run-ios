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
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = "切换角色失败，请重试"
        }
    }
}

// MARK: - Blind Runner Settings View

struct BlindRunnerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindRunnerSettingsViewModel()
    @StateObject private var deletionViewModel = AccountDeletionViewModel()
    @State private var showLogoutConfirm = false
    @State private var showRoleSwitchConfirm = false
    @State private var showDeletionInitialConfirmation = false

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

                Button("删除账户", role: .destructive) {
                    showDeletionInitialConfirmation = true
                }
                .disabled(appState.accountDeletionState == .inProgress)
                .accessibilityLabel("删除账户")
                .accessibilityHint("永久停用当前账户，需要再次确认")
            }

            if let message = deletionViewModel.preflightMessage {
                Section { Text(message).foregroundColor(AppColors.destructive).accessibilityLabel(message) }
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
                Task { await appState.logout() }
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
        .alert("确认删除账户", isPresented: $showDeletionInitialConfirmation) {
            Button("继续删除账户", role: .destructive) {
                Task {
                    await deletionViewModel.preflight(
                        appState: appState,
                        speechService: speechService
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("系统将先检查是否存在进行中的服务。检查通过后仍需再次确认，才会提交账户删除请求。")
        }
        .alert("最终确认删除账户", isPresented: $deletionViewModel.showFinalConfirmation) {
            Button("永久删除账户", role: .destructive) {
                Task { await appState.deleteCurrentAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账户将被软删除，所有登录令牌会失效。删除成功后手机号可以重新注册。此操作不可撤销。")
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
            .environmentObject(SpeechService())
    }
}
#endif
