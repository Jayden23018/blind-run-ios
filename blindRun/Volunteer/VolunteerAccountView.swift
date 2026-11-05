import SwiftUI

// 陪跑员账户页：「我的」点头像卡进来（#700，定稿 `docs/ui/mockups/volunteer-settings-20261104/`）。
//
// 照健康 App 头像进入的个人页：头像、名字、角色；只读信息和可点的行分组；退出 / 删除账户放最底。
// 用 push 而不是 sheet：退出 / 删除进行中的进度遮罩挂在根视图上，sheet 会盖在遮罩上面，
// 遮罩期间背景就退不出无障碍树（`blindRunUITests` 的遮罩用例守着）。

enum VolunteerAccountCopy {
    static let navigationTitle = "账户"
    static let roleLine = "当前角色：志愿者"
    static let profileTitle = "个人资料"
    static let identityTitle = "实名认证"
    static let certificateTitle = "资质审核"
    static let privacyGroupTitle = "隐私"
    static let logout = "退出登录"
    static let deleteAccount = "删除账户"
    static let deletionFootnote = "删除账户会永久停用，需要再次确认。"
}

struct VolunteerAccountView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var deletionViewModel = AccountDeletionViewModel()
    @State private var showLogoutConfirm = false
    @State private var showDeletionInitialConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                personalGroup
                privacyGroup
                sessionGroup
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(VolunteerAccountCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮的栏会盖住最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerAccountView")
        .alert("无法删除账户", isPresented: $deletionViewModel.isShowingPreflightBlock) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deletionViewModel.preflightMessage ?? "")
        }
        .logoutConfirmation(isPresented: $showLogoutConfirm)
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
            Text(AccountDeletionViewModel.finalConfirmationMessage(for: .volunteer))
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(spacing: 8) {
            VolunteerAvatarCircle(side: 96)
            Text(appState.volunteerProfile?.name?.nilIfBlank ?? VolunteerSettingsCopy.unnamed)
                .font(.title.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(VolunteerAccountCopy.roleLine)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: 个人

    private var personalGroup: some View {
        VolunteerAccountGroup {
            NavigationLink {
                VolunteerProfileView()
            } label: {
                VolunteerSettingsRowLabel(title: VolunteerAccountCopy.profileTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VolunteerAccountCopy.profileTitle)
            .accessibilityHint("查看姓名、手机号与实名状态")

            // 只读：没有新去处（资质证书方块已经进证书页），拿不到实名状态就不画这一行。
            if let identity = VolunteerAccountProfileContent.identityStatusText(
                appState.volunteerRegistrationStatus?.resolvedIdVerifyStatus
            ) {
                VolunteerAccountRowDivider()
                VolunteerAccountValueRow(title: VolunteerAccountCopy.identityTitle, value: identity)
                    .accessibilityIdentifier("volunteerAccountIdentityRow")
            }
            VolunteerAccountRowDivider()
            VolunteerAccountValueRow(title: VolunteerAccountCopy.certificateTitle, value: certificateState.displayName)
                .accessibilityIdentifier("volunteerAccountCertificateRow")
        }
    }

    /// 与「我的」上资质证书方块同一个判据：没拉到资料时按「状态未知」，不假装已提交或已通过。
    private var certificateState: VolunteerCertificateDisplayState {
        VolunteerCertificateDisplayState.from(
            status: VolunteerCertificateStatus.parse(appState.volunteerProfile?.verificationStatus),
            statusLoadFailed: false
        )
    }

    // MARK: 隐私

    private var privacyGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VolunteerAccountCopy.privacyGroupTitle)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding(.leading, VolunteerAccountMetrics.rowHorizontalPadding)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            VolunteerAccountGroup {
                // 位置共享同意的撤回（#530，与盲人端 #393 同一套交互）。
                NavigationLink {
                    VolunteerPrivacyAuthorizationView()
                } label: {
                    VolunteerSettingsRowLabel(title: PrivacyAuthorizationCopy.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PrivacyAuthorizationCopy.title)
                .accessibilityHint("查看并撤回接单和陪跑时位置共享的同意")
                .accessibilityIdentifier("volunteerPrivacyAuthorizationSettingsEntry")

                VolunteerAccountRowDivider()

                NavigationLink {
                    BlockedUsersView()
                } label: {
                    VolunteerSettingsRowLabel(title: UserSafetyCopy.blockedListTitle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(UserSafetyCopy.blockedListTitle)
                .accessibilityHint(UserSafetyCopy.blockedListHint)
                .accessibilityIdentifier("blockedUsersSettingsEntry")
            }
        }
    }

    // MARK: 退出与删除

    private var sessionGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            VolunteerAccountGroup {
                Button {
                    showLogoutConfirm = true
                } label: {
                    VolunteerSettingsRowLabel(
                        title: VolunteerAccountCopy.logout,
                        titleColor: AppColors.destructive,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VolunteerAccountCopy.logout)
                .accessibilityHint("退出后需要重新登录，需要二次确认")

                VolunteerAccountRowDivider()

                Button {
                    showDeletionInitialConfirmation = true
                } label: {
                    VolunteerSettingsRowLabel(
                        title: VolunteerAccountCopy.deleteAccount,
                        titleColor: AppColors.destructive,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.accountDeletionState == .inProgress)
                .accessibilityLabel(VolunteerAccountCopy.deleteAccount)
                .accessibilityHint("永久停用当前账户，需要再次确认")
            }
            VolunteerAccountFootnote(text: VolunteerAccountCopy.deletionFootnote)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VolunteerAccountView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
