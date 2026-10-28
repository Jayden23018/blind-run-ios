import SwiftUI

// MARK: - 隐私与授权（#393）

/// 盲人端三项单独同意的撤回，放在同一处、同一种交互：说明这项同意管什么、当前状态、一个撤回按钮，
/// 结果留在页面上并朗读一次（PIPL 第十五条：同意要能撤回，撤回要和给出一样便捷）。
///
/// 撤回不加二次确认：随时可以重新同意，资料页 #352 那一项也是按下即生效（与安卓 #91 一致）。
enum PrivacyAuthorizationCopy {
    static let title = "隐私与授权"
    static let granted = "当前：已同意。"

    static let voiceTitle = "语音下单"
    static let voicePurpose = "用语音下单时，你说的话转成文字后会发给阿里云通义千问（第三方大模型），帮助理解你要去哪里、什么时候出发。"
    static let voiceNotGranted = "当前：没有同意。下次用语音下单前会先问你，也可以改用手动填写。"
    /// 三个按钮的可见标题各不相同：语音控制（「点按……」）按可见标题找按钮，三个都叫「撤回同意」就分不清。
    static let voiceRevokeButtonTitle = "撤回语音下单的同意"
    static let voiceRevokeLabel = "撤回语音下单的同意。撤回后不再把你说的话发给第三方大模型，下次用语音下单前会重新问你"
    static let voiceRevoked = "已撤回。语音下单不会再把你说的话发给第三方大模型；下次用语音下单前会重新问你，也可以改用手动填写。"

    static let visionTitle = "视力状况和导盲犬"
    static let visionPurpose = "这两项属于敏感个人信息，只用来让志愿者知道该怎么准备。"
    static let visionNotGranted = "当前：没有同意。想填可以到「个人资料」里点「填写视力状况」。"
    static let visionProfileNotLoaded = "资料还没加载出来，请先打开一次「个人资料」，再回来撤回。"
    static let visionWithdrawalPending = "当前：撤回还没完成，资料里的视力状况和导盲犬还在。"

    static let locationTitle = "陪跑时的位置共享"
    static let locationPurpose = "从志愿者出发来找你到跑步结束，持续获取你的位置，显示给这一单的志愿者；求助时附上当时的位置。"
    static let locationNotGranted = "当前：没有同意。下次预约陪跑、或已约好的陪跑出发前会先问你。"
    static let locationRevokeButtonTitle = "撤回位置共享的同意"
    static let locationRevokeLabel = "撤回陪跑时位置共享的同意。撤回后不再获取你的位置，求助也不附位置，下次预约陪跑或已约好的陪跑出发前会重新问你"
    static let locationRevoked = "已撤回。不再获取你的位置，求助也不会附上位置；下次预约陪跑、或已约好的陪跑出发前会重新问你。"
    static let locationBlockedDuringEscort =
        "正在陪跑，现在撤回会让对方立刻看不到你的位置，所以这一单跑完后再来撤回。现在就要停，可以在系统设置里关闭助盲跑的定位权限。"
}

/// 视力那一项此刻怎么显示（#393）。抽成纯函数只为可测：撤回保存失败后要能原地重试，而不是按钮消失、状态说错。
enum VisionRevokeRow: Equatable {
    /// 资料没加载：撤回会被表单校验挡下，先去个人资料。
    case profileNotLoaded
    /// 已同意：显示撤回按钮。
    case granted
    /// 撤回已按下、还没保存成功：说清没完成，按钮改为重试同一次保存。
    case withdrawalPending
    case notGranted

    static func resolve(hasConsent: Bool, withdrawalPending: Bool, profileLoaded: Bool) -> VisionRevokeRow {
        if withdrawalPending { return profileLoaded ? .withdrawalPending : .profileNotLoaded }
        guard hasConsent else { return .notGranted }
        return profileLoaded ? .granted : .profileNotLoaded
    }

    var status: String {
        switch self {
        case .profileNotLoaded: return PrivacyAuthorizationCopy.visionProfileNotLoaded
        case .granted: return PrivacyAuthorizationCopy.granted
        case .withdrawalPending: return PrivacyAuthorizationCopy.visionWithdrawalPending
        case .notGranted: return PrivacyAuthorizationCopy.visionNotGranted
        }
    }

    var offersRevoke: Bool { self == .granted || self == .withdrawalPending }
}

struct PrivacyAuthorizationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    /// 视力那项复用资料页的撤回（整表单保存，两项发 `NOT_SPECIFIED`，保存成功才删同意记录），文案一字不差。
    @StateObject private var profileViewModel = BlindRunnerProfileViewModel()
    /// 撤回后同意记录变了，但 `hasVoiceOrderConsent` / `hasLocationTrackConsent` 是现读的计算属性，
    /// SwiftUI 收不到通知。撤回后自增一次让页面重读 —— 只读它、不拿它当 `.id`：换 id 会重建整页，读屏焦点跳回页首。
    @State private var refreshTick = 0
    @State private var voiceNotice: String?
    @State private var locationNotice: String?

    var body: some View {
        let _ = refreshTick
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                voiceSection
                visionSection
                locationSection
            }
            .padding(20)
        }
        .navigationTitle(PrivacyAuthorizationCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮胶囊会切掉页面最后一行（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            profileViewModel.configure(with: appState, speechService: speechService)
            profileViewModel.withdrawalRetryButtonTitle = VisionConsentWithdrawalCopy.buttonTitle
        }
    }

    // MARK: 三项

    private var voiceSection: some View {
        let granted = appState.hasVoiceOrderConsent
        return consentSection(
            title: PrivacyAuthorizationCopy.voiceTitle,
            purpose: PrivacyAuthorizationCopy.voicePurpose,
            status: granted ? PrivacyAuthorizationCopy.granted : PrivacyAuthorizationCopy.voiceNotGranted,
            revoke: granted ? RevokeAction(
                title: PrivacyAuthorizationCopy.voiceRevokeButtonTitle,
                label: PrivacyAuthorizationCopy.voiceRevokeLabel,
                identifier: "privacyRevokeVoiceOrderConsent",
                perform: revokeVoiceConsent
            ) : nil,
            notice: voiceNotice
        )
    }

    private var visionSection: some View {
        let row = VisionRevokeRow.resolve(
            hasConsent: profileViewModel.hasVisionConsent,
            withdrawalPending: profileViewModel.isVisionConsentWithdrawalPending,
            profileLoaded: appState.blindProfile != nil
        )
        return consentSection(
            title: PrivacyAuthorizationCopy.visionTitle,
            purpose: PrivacyAuthorizationCopy.visionPurpose,
            status: row.status,
            revoke: row.offersRevoke ? RevokeAction(
                title: VisionConsentWithdrawalCopy.buttonTitle,
                label: VisionConsentWithdrawalCopy.accessibilityLabel,
                identifier: "privacyRevokeVisionConsent",
                isDisabled: profileViewModel.isLoading,
                // 撤回没存上时重试同一次保存（`withdrawVisionConsent` 在已收起时什么都不做）。
                perform: row == .withdrawalPending ? { profileViewModel.submit() } : { profileViewModel.withdrawVisionConsent() }
            ) : nil,
            // 成功那句与失败那句都由 view model 朗读，这里只负责留在屏幕上。
            notice: profileViewModel.visionConsentWithdrawnNotice ?? profileViewModel.errorMessage
        )
    }

    private var locationSection: some View {
        let granted = appState.hasLocationTrackConsent(.blindLocationTrack)
        return consentSection(
            title: PrivacyAuthorizationCopy.locationTitle,
            purpose: PrivacyAuthorizationCopy.locationPurpose,
            status: granted ? PrivacyAuthorizationCopy.granted : PrivacyAuthorizationCopy.locationNotGranted,
            revoke: granted ? RevokeAction(
                title: PrivacyAuthorizationCopy.locationRevokeButtonTitle,
                label: PrivacyAuthorizationCopy.locationRevokeLabel,
                identifier: "privacyRevokeLocationTrackConsent",
                perform: revokeLocationConsent
            ) : nil,
            notice: locationNotice
        )
    }

    // MARK: 撤回

    private func revokeVoiceConsent() {
        appState.revokeVoiceOrderConsent()
        announce(PrivacyAuthorizationCopy.voiceRevoked) { voiceNotice = $0 }
    }

    private func revokeLocationConsent() {
        let revoked = appState.revokeLocationTrackConsent(.blindLocationTrack)
        announce(revoked ? PrivacyAuthorizationCopy.locationRevoked : PrivacyAuthorizationCopy.locationBlockedDuringEscort) {
            locationNotice = $0
        }
    }

    /// 屏幕上留一句、读屏念一次。只播不显的话，低视力用户与明眼家属看不到发生了什么。
    private func announce(_ text: String, store: (String) -> Void) {
        store(text)
        refreshTick += 1
        speechService.speak(text)
    }

    // MARK: 一项的版式

    private struct RevokeAction {
        let title: String
        let label: String
        let identifier: String
        var isDisabled = false
        let perform: () -> Void
    }

    private func consentSection(
        title: String,
        purpose: String,
        status: String,
        revoke: RevokeAction?,
        notice: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(purpose)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(status)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let revoke {
                // 64pt 写在标签内部：外挂在按钮外的 frame 撑不大可点区（记忆 button-frame-outside-label-does-not-grow-hit-area）。
                Button(action: revoke.perform) {
                    Text(revoke.title)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(12)
                }
                .disabled(revoke.isDisabled)
                .accessibilityLabel(revoke.label)
                .accessibilityIdentifier(revoke.identifier)
            }
            if let notice {
                Text(notice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
