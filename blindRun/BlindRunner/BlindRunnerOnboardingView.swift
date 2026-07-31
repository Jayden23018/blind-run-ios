import SwiftUI

// MARK: - Onboarding Step

/// 盲人跑者引导流的步骤，枚举顺序就是「第一个未完成的环节」的判定顺序。
///
/// 实名认证自 2026-07-30 起是**下单硬门槛**（后端 403 `IDENTITY_NOT_VERIFIED`），
/// 已计入 `AppState.isBlindBookingReady`。但 `identityPrompt` 这一步仍可「稍后再说」：
/// 跳过只是放行进首页去看历史订单和设置，**不等于可以下单**——
/// 真正的拦截发生在 `BlindBookingGate.identityVerification`。
/// 跳过后仍能通过「设置 → 实名认证」随时回到实名页，不会变成死路。
enum BlindOnboardingStep: Equatable {
    /// 基础资料（昵称）未填。
    case basicProfile
    /// 紧急联系人缺失，或没有恰好一位主联系人。
    case emergencyContacts
    /// 其余步骤已完成，只剩实名认证提示（可跳过，但跳过后无法下单）。
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
                        .accessibilityHint("进入设置页面，可以查看资料、实名认证或退出登录")
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
            EmergencyContactsView()
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
        return "\(status.displayName)。\(status.guidanceMessage)可以现在去实名认证；也可以选择稍后再说先进入首页，但在完成实名认证之前无法预约跑步。"
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
                    BlindIdentityVerificationView()
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
                    speechService.speak("已跳过实名认证。完成实名认证之前无法预约跑步，可以随时在设置里的实名认证页面完成。")
                    onSkipIdentityPrompt()
                }
                .font(AppFonts.primaryButton())
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .cornerRadius(12)
                .accessibilityLabel("稍后再说")
                .accessibilityHint("跳过实名认证并进入首页；完成实名认证之前无法预约跑步，可稍后在设置里补做")

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

#if DEBUG
#Preview {
    BlindRunnerOnboardingView(step: .identityPrompt, onSkipIdentityPrompt: {})
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
