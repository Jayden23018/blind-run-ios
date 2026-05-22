import SwiftUI

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
                        role: .blindRunner,
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
        .accessibilityLabel(role == .blindRunner
            ? "我是盲人跑者，预约志愿者陪我跑步"
            : "我是志愿者，陪伴盲人跑者完成跑步")
        .accessibilityHint(role == .blindRunner
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
