import SwiftUI

// MARK: - 隐私与授权 · 第二层（#754）

/// 一项同意的详情页：「当前」状态行、用途卡、红字撤回行、组下说明。撤回结果留在撤回行下面。
///
/// 撤回成功后撤回行消失，结果那句就留在它原来的位置；陪跑中被拦、保存失败时撤回行还在，结果在它下面。
struct PrivacyConsentDetailPage: View {
    let title: String
    let statusValue: String
    /// 「当前」那组下面的补充说明（没有同意时怎么办、撤回没完成、资料没加载）。
    let statusHint: String?
    let purpose: String
    let revoke: PrivacyRevokeAction?
    let notice: PrivacyRevokeNotice?
    let revokeFootnote: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    GroupedCard {
                        SettingsRowLabel(
                            title: PrivacyAuthorizationCopy.currentStatusTitle,
                            value: statusValue,
                            showsChevron: false
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(PrivacyAuthorizationCopy.currentStatusTitle)：\(statusValue)")
                        .accessibilityIdentifier("privacyConsentCurrentStatus")
                    }
                    if let statusHint {
                        GroupedCardFootnote(text: statusHint)
                    }
                }

                GroupedCard {
                    Text(purpose)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(GroupedCardMetrics.rowHorizontalPadding)
                }

                if let revoke {
                    VStack(alignment: .leading, spacing: 8) {
                        GroupedCard {
                            PrivacyRevokeRowButton(action: revoke)
                        }
                        if let notice {
                            PrivacyRevokeNoticeLabel(notice: notice)
                        }
                        GroupedCardFootnote(text: revokeFootnote)
                    }
                } else if let notice {
                    PrivacyRevokeNoticeLabel(notice: notice)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
    }
}

// MARK: - 语音下单

struct PrivacyVoiceConsentDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @State private var notice: PrivacyRevokeNotice?
    /// 同意状态是现读的计算属性，撤回后自增一次让本页重读。
    @State private var refreshTick = 0

    var body: some View {
        let _ = refreshTick
        let granted = appState.hasVoiceOrderConsent
        PrivacyConsentDetailPage(
            title: PrivacyAuthorizationCopy.voiceTitle,
            statusValue: granted ? PrivacyAuthorizationCopy.grantedValue : PrivacyAuthorizationCopy.notGrantedValue,
            // 撤回成功后结果那句已说清下次怎么办，组下不再重复同一句。
            statusHint: granted || notice != nil ? nil : PrivacyAuthorizationCopy.voiceNotGrantedHint,
            purpose: PrivacyAuthorizationCopy.voicePurpose,
            revoke: granted ? PrivacyRevokeAction(
                title: PrivacyAuthorizationCopy.voiceRevokeButtonTitle,
                label: PrivacyAuthorizationCopy.voiceRevokeLabel,
                identifier: "privacyRevokeVoiceOrderConsent",
                perform: revoke
            ) : nil,
            notice: notice,
            revokeFootnote: PrivacyAuthorizationCopy.voiceRevokeFootnote
        )
    }

    private func revoke() {
        appState.revokeVoiceOrderConsent()
        // 屏幕上留一句、读屏念一次。只播不显的话，低视力用户与明眼家属看不到发生了什么。
        notice = PrivacyRevokeNotice(text: PrivacyAuthorizationCopy.voiceRevoked, isSuccess: true)
        refreshTick += 1
        speechService.speak(PrivacyAuthorizationCopy.voiceRevoked)
    }
}

// MARK: - 视力状况和导盲犬

/// 视力那项复用资料页的撤回（整表单保存，两项发 `NOT_SPECIFIED`，保存成功才删同意记录）。
/// 成功那句与失败那句都由 view model 朗读，这里只负责留在屏幕上。
struct PrivacyVisionConsentDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @ObservedObject var profileViewModel: BlindRunnerProfileViewModel

    var body: some View {
        let row = VisionRevokeRow.resolve(
            hasConsent: profileViewModel.hasVisionConsent,
            withdrawalPending: profileViewModel.isVisionConsentWithdrawalPending,
            profileLoaded: appState.blindProfile != nil
        )
        PrivacyConsentDetailPage(
            title: PrivacyAuthorizationCopy.visionTitle,
            statusValue: row.value,
            statusHint: row.hint,
            purpose: PrivacyAuthorizationCopy.visionPurpose,
            revoke: row.offersRevoke ? PrivacyRevokeAction(
                title: PrivacyAuthorizationCopy.visionRevokeButtonTitle,
                label: PrivacyAuthorizationCopy.visionRevokeLabel,
                identifier: "privacyRevokeVisionConsent",
                isDisabled: profileViewModel.isLoading,
                // 撤回没存上时重试同一次保存（`withdrawVisionConsent` 在已收起时什么都不做）。
                perform: row == .withdrawalPending ? { profileViewModel.submit() } : { profileViewModel.withdrawVisionConsent() }
            ) : nil,
            notice: notice(for: row),
            revokeFootnote: PrivacyAuthorizationCopy.visionRevokeFootnote
        )
        .onAppear {
            // 资料没加载时这一页没有撤回行，原因占撤回行的位置，进页念一次（点了没反应对盲人就是事故）。
            guard row == .profileNotLoaded else { return }
            speechService.speak(PrivacyAuthorizationCopy.visionProfileNotLoaded)
        }
    }

    private func notice(for row: VisionRevokeRow) -> PrivacyRevokeNotice? {
        if row == .profileNotLoaded {
            return PrivacyRevokeNotice(text: PrivacyAuthorizationCopy.visionProfileNotLoaded, isSuccess: false)
        }
        if let succeeded = profileViewModel.visionConsentWithdrawnNotice {
            return PrivacyRevokeNotice(text: succeeded, isSuccess: true)
        }
        return profileViewModel.errorMessage.map { PrivacyRevokeNotice(text: $0, isSuccess: false) }
    }
}

// MARK: - 陪跑时的位置共享

struct PrivacyLocationConsentDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @State private var notice: PrivacyRevokeNotice?
    @State private var refreshTick = 0

    var body: some View {
        let _ = refreshTick
        let granted = appState.hasLocationTrackConsent(.blindLocationTrack)
        PrivacyConsentDetailPage(
            title: PrivacyAuthorizationCopy.locationTitle,
            statusValue: granted ? PrivacyAuthorizationCopy.grantedValue : PrivacyAuthorizationCopy.notGrantedValue,
            statusHint: granted || notice != nil ? nil : PrivacyAuthorizationCopy.locationNotGrantedHint,
            purpose: PrivacyAuthorizationCopy.locationPurpose,
            revoke: granted ? PrivacyRevokeAction(
                title: PrivacyAuthorizationCopy.locationRevokeButtonTitle,
                label: PrivacyAuthorizationCopy.locationRevokeLabel,
                identifier: "privacyRevokeLocationTrackConsent",
                perform: revoke
            ) : nil,
            notice: notice,
            revokeFootnote: PrivacyAuthorizationCopy.locationRevokeFootnote
        )
    }

    /// 陪跑会话进行中 `revokeLocationTrackConsent` 返回 false、同意保留，说明原因与系统设置这条出路。
    private func revoke() {
        let revoked = appState.revokeLocationTrackConsent(.blindLocationTrack)
        let result = revoked
            ? PrivacyRevokeNotice(text: PrivacyAuthorizationCopy.locationRevoked, isSuccess: true)
            : PrivacyRevokeNotice(text: PrivacyAuthorizationCopy.locationBlockedDuringEscort, isSuccess: false)
        notice = result
        refreshTick += 1
        speechService.speak(result.text)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PrivacyVoiceConsentDetailView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
