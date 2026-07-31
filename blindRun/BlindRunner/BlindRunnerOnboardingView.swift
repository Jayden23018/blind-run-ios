import SwiftUI

// MARK: - Onboarding Step

/// 盲人跑者引导流的步骤，枚举顺序就是「第一个未完成的环节」的判定顺序。
///
/// 实名认证是**软引导**：`identityPrompt` 一步永远可以「稍后再说」直接放行，
/// 也绝不参与 `AppState.isBlindBookingReady`（后端 `OrderCreationService` 不看 `verifyStatus`）。
enum BlindOnboardingStep: Equatable {
    /// 基础资料（昵称）未填。
    case basicProfile
    /// 紧急联系人缺失，或没有恰好一位主联系人。
    case emergencyContacts
    /// 硬门槛已满足，只剩实名认证的可跳过提示。
    case identityPrompt

    /// 返回第一个未完成的环节；全部完成（或实名提示已被跳过）时返回 nil，表示可以进主页。
    static func first(
        isBasicProfileComplete: Bool,
        hasValidEmergencyContacts: Bool,
        shouldPromptIdentity: Bool,
        didDismissIdentityPrompt: Bool
    ) -> BlindOnboardingStep? {
        if !isBasicProfileComplete { return .basicProfile }
        if !hasValidEmergencyContacts { return .emergencyContacts }
        if shouldPromptIdentity && !didDismissIdentityPrompt { return .identityPrompt }
        return nil
    }
}

// MARK: - Onboarding View

/// 引导流容器：把当前步骤放进一个 `NavigationStack`，并始终保留右上角设置入口（内含退出登录）。
struct BlindRunnerOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    let step: BlindOnboardingStep
    /// 「稍后再说」：持久化跳过实名提示，直接进入主页。
    let onSkipIdentityPrompt: () -> Void

    var body: some View {
        NavigationStack {
            stepContent
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink {
                            BlindRunnerSettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                        }
                        .accessibilityLabel("设置")
                        .accessibilityHint("进入设置页面，可以查看资料、切换角色或退出登录")
                    }
                }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .basicProfile:
            BlindRunnerProfileView()
                .navigationTitle("完善信息")
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("blindOnboarding.basicProfile")
        case .emergencyContacts:
            // TODO(集成批次4)：换成独立的 `EmergencyContactsView`（多联系人 CRUD + 主联系人切换）。
            // 现阶段复用合并式资料表单：它以 `isPrimary: true` 写入唯一联系人，
            // 足以满足 `hasValidEmergencyContacts`，不会让用户卡在这一步。
            BlindRunnerProfileView()
                .navigationTitle("紧急联系人")
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("blindOnboarding.emergencyContacts")
        case .identityPrompt:
            identityPrompt
                .accessibilityIdentifier("blindOnboarding.identityPrompt")
        }
    }

    private var identityPromptSpeech: String {
        let status = appState.blindIdentityStatus
        return "\(status.displayName)。\(status.guidanceMessage)可以现在去实名认证，也可以选择稍后再说，直接开始预约。"
    }

    private var identityPrompt: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HighContrastText("实名认证", style: .title)
                    .accessibilityAddTraits(.isHeader)

                Text(identityPromptSpeech)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(identityPromptSpeech)

                NavigationLink {
                    BlindIdentityVerificationEntryPlaceholder()
                } label: {
                    Text("去实名认证")
                        .font(AppFonts.primaryButton())
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 64)
                        .foregroundColor(.white)
                        .background(AppColors.primary)
                        .cornerRadius(12)
                }
                .accessibilityLabel("去实名认证")
                .accessibilityHint("填写姓名和身份证号提交实名认证")

                Button("稍后再说") {
                    speechService.speak("已跳过实名认证，可以随时在设置中完成。")
                    onSkipIdentityPrompt()
                }
                .font(AppFonts.primaryButton())
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .cornerRadius(12)
                .accessibilityLabel("稍后再说")
                .accessibilityHint("跳过实名认证，直接进入首页开始预约")

                PrimaryButton("重复当前状态") {
                    speechService.speak(identityPromptSpeech)
                }
                .accessibilityLabel("重复当前状态")
                .accessibilityHint("再次朗读当前实名认证状态")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(AppColors.background)
        .navigationTitle("实名认证引导")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            speechService.speak(identityPromptSpeech)
        }
    }
}

// MARK: - Placeholder

/// TODO(集成批次4)：换成 `BlindIdentityVerificationView`（姓名 + 身份证号提交表单）。
/// 那个视图连同它的 ViewModel、测试属于批次 4，这里只保留一个诚实的占位页，
/// 避免把未集成的表单提前拖进来，也避免用户点进一个空白页。
private struct BlindIdentityVerificationEntryPlaceholder: View {
    @EnvironmentObject private var speechService: SpeechService

    private let message = "实名认证入口正在接入中，暂时无法在这里提交。可以先返回选择稍后再说，直接开始预约。"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HighContrastText("实名认证", style: .title)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message)

                PrimaryButton("重复朗读") {
                    speechService.speak(message)
                }
                .accessibilityLabel("重复朗读")
                .accessibilityHint("再次朗读当前页面说明")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(AppColors.background)
        .navigationTitle("实名认证")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("blindOnboarding.identityVerificationPlaceholder")
        .onAppear {
            speechService.speak(message)
        }
    }
}

#if DEBUG
#Preview {
    BlindRunnerOnboardingView(step: .identityPrompt, onSkipIdentityPrompt: {})
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
