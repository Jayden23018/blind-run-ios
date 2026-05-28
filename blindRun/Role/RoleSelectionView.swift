import Combine
import SwiftUI

// MARK: - Role Selection ViewModel

/// 角色选择页 ViewModel，管理角色切换 API 调用和活跃订单拦截处理。
/// 依赖 AppState 通过 ``configure(with:)`` 在 View.onAppear 中注入。
@MainActor
final class RoleSelectionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showBlockedAlert: Bool = false

    // MARK: - Dependencies

    private weak var appState: AppState?
    private var speechService: SpeechService?

    // MARK: - Init

    init() {}

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    // MARK: - Actions

    /// 选择角色并调用后端 API 切换
    func selectRole(_ role: UserRole) {
        guard let appState = appState else {
            errorMessage = "应用未初始化，请重启"
            return
        }

        Task { await performRoleSwitch(role: role, appState: appState) }
    }

    // MARK: - Private

    private func performRoleSwitch(role: UserRole, appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let request = SetRoleRequest(role: role)
            let response: SetRoleResponse = try await appState.apiClient.request(
                method: .post,
                path: "/api/user/role",
                query: nil,
                body: request,
                requiresAuth: true
            )
            appState.handleRoleSwitchSuccess(response: response, requestedRole: role)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            handleSwitchError(error)
        } catch {
            isLoading = false
            errorMessage = "网络错误，请重试"
            speechService?.speakError("网络错误，请重试")
        }
    }

    private func handleSwitchError(_ error: APIError) {
        switch error {
        case .serverError(let response):
            if response.errorCode == .activeOrderRoleSwitchBlocked {
                errorMessage = response.message
                showBlockedAlert = true
            } else {
                errorMessage = response.message
            }
        case .networkError:
            errorMessage = "网络错误，请重试"
        case .unauthorized:
            errorMessage = "登录已过期，请重新登录。"
        case .decodingError, .invalidURL, .unknown:
            errorMessage = "角色设置失败，请重试。"
        }
        if let message = errorMessage {
            speechService?.speakError(message)
        }
    }
}

// MARK: - Role Selection View

/// 角色选择页：两个大卡片供用户选择盲人跑者或志愿者身份。
/// 遵循 MVVM：纯渲染 View，所有业务逻辑在 RoleSelectionViewModel 中。
struct RoleSelectionView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = RoleSelectionViewModel()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: geometry.safeAreaInsets.top + 60)

                    HighContrastText("请选择您的角色", style: .title)

                    Spacer()
                        .frame(height: 20)

                    // 盲人跑者卡片
                    roleCard(
                        role: .blind,
                        icon: "figure.run",
                        title: "我是盲人跑者",
                        subtitle: "预约志愿者陪我跑步",
                        backgroundColor: Color.orange.opacity(0.15)
                    )

                    // 志愿者卡片
                    roleCard(
                        role: .volunteer,
                        icon: "figure.and.child.holdinghands",
                        title: "我是志愿者",
                        subtitle: "陪伴盲人跑者完成跑步",
                        backgroundColor: Color.blue.opacity(0.15)
                    )

                    // Loading
                    if viewModel.isLoading {
                        ProgressView("正在设置角色...")
                            .padding()
                            .accessibilityLabel("正在设置角色，请稍候")
                    }

                    // 错误消息
                    if let error = viewModel.errorMessage, !viewModel.showBlockedAlert {
                        Text(error)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .accessibilityLabel(error)
                    }

                    Spacer()

                    // 底部说明
                    Text("一个手机号可同时拥有两个身份，后续可在设置中切换")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // 环境切换入口
                    #if DEBUG
                    environmentSwitcher
                    #endif
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppColors.background)
        .onAppear {
            viewModel.configure(with: appState, speechService: speechService)
            // TTS 播报警示语
            speechService.speak("请选择您的角色。我是盲人跑者，预约志愿者陪我跑步。我是志愿者，陪伴盲人跑者完成跑步。")
        }
        .alert("无法切换角色", isPresented: $viewModel.showBlockedAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "存在进行中的订单，无法切换角色。")
        }
    }

    // MARK: - Role Card

    private func roleCard(
        role: UserRole,
        icon: String,
        title: String,
        subtitle: String,
        backgroundColor: Color
    ) -> some View {
        Button {
            viewModel.selectRole(role)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundColor(AppColors.textPrimary)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(backgroundColor)
            .cornerRadius(16)
        }
        .disabled(viewModel.isLoading)
        .accessibilityLabel(role == .blind
            ? "我是盲人跑者，预约志愿者陪我跑步"
            : "我是志愿者，陪伴盲人跑者完成跑步")
        .accessibilityHint(role == .blind
            ? "点击后进入盲人跑者模式"
            : "点击后进入志愿者模式")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Environment Switcher

    #if DEBUG
    private var environmentSwitcher: some View {
        Button {
            let allEnvs = APIEnvironment.allCases
            guard let currentIndex = allEnvs.firstIndex(of: appState.currentEnvironment) else { return }
            let nextIndex = (currentIndex + 1) % allEnvs.count
            appState.currentEnvironment = allEnvs[nextIndex]
        } label: {
            Text("API 环境: \(appState.currentEnvironment.displayName)")
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .accessibilityLabel("API 环境切换")
        .accessibilityHint("当前环境：\(appState.currentEnvironment.displayName)")
    }
    #endif
}

#if DEBUG
#Preview {
    RoleSelectionView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
