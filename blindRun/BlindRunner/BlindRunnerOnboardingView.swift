import SwiftUI

// MARK: - Onboarding Step

/// 盲人跑者引导流的步骤，枚举顺序就是「第一个未完成的环节」的判定顺序。
///
/// 2026-11-05 起视障跑者不再实名认证（#767），引导只剩资料和紧急联系人两步。
enum BlindOnboardingStep: Equatable {
    /// 基础资料（昵称）未填。
    case basicProfile
    /// 紧急联系人缺失，或没有恰好一位主联系人。
    case emergencyContacts

    /// 返回第一个未完成的环节；全部完成时返回 nil，表示可以进主页。
    static func first(
        isBasicProfileComplete: Bool,
        hasValidEmergencyContacts: Bool
    ) -> BlindOnboardingStep? {
        if !isBasicProfileComplete { return .basicProfile }
        if !hasValidEmergencyContacts { return .emergencyContacts }
        return nil
    }
}

// MARK: - Onboarding View

/// 引导流容器：把当前步骤放进一个 `NavigationStack`，并始终保留右上角设置入口（内含退出登录）。
struct BlindRunnerOnboardingView: View {
    let step: BlindOnboardingStep

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
                        .accessibilityHint("进入设置页面，可以查看资料或退出登录")
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
        }
    }
}

#if DEBUG
#Preview {
    BlindRunnerOnboardingView(step: .basicProfile)
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
