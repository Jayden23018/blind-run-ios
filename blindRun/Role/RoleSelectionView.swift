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
    private let apiClientOverride: (any APIClientProtocol)?

    // MARK: - Init

    init(apiClient: (any APIClientProtocol)? = nil) {
        self.apiClientOverride = apiClient
    }

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
            let response: SetRoleResponse = try await activeAPIClient(appState: appState).request(
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
            if response.errorCode == .roleAlreadySet {
                errorMessage = response.message
                showBlockedAlert = true
            } else {
                errorMessage = response.message
            }
        case .networkError:
            errorMessage = "网络错误，请重试"
        case .rateLimited(let info):
            errorMessage = APIError.rateLimited(info).localizedMessage
        case .unauthorized:
            appState?.expireSession()
            errorMessage = nil
        case .missingCredentials:
            // 刻意不走 `expireSession()`：本地本来就没 Token，再清一次只会把现场抹掉。
            // 照原样把话说清楚，让人能看出这是客户端状态问题而不是"服务端把我踢了"。
            errorMessage = error.localizedMessage
        case .decodingError, .invalidURL, .unknown:
            errorMessage = "角色设置失败，请重试。"
        }
        if let message = errorMessage {
            speechService?.speakError(message)
        }
    }

    private func activeAPIClient(appState: AppState) -> any APIClientProtocol {
        apiClientOverride ?? appState.apiClient
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
                    Text("身份一经选定不可更改，请谨慎选择")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // 环境切换入口
                    #if DEBUG
                    if AppBuildChannel.current.allowsEnvironmentSwitcher {
                        environmentSwitcher
                    }
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
            // 身份不可逆，盲人用户只靠语音，这句警示必须进播报。
            speechService.speak("请选择您的角色。我是盲人跑者，预约志愿者陪我跑步。我是志愿者，陪伴盲人跑者完成跑步。身份一经选定不可更改，请谨慎选择。")
        }
        .alert("身份已设定", isPresented: $viewModel.showBlockedAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "身份已设定，不可修改。")
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
            let allEnvs = AppState.debugTestEnvironments
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
