import SwiftUI

// 盲人端账户页：「我的」点头像卡进来（#711，定稿 `docs/ui/mockups/blind-profile-20261105/`）。
//
// 和陪跑员账户页同一套版式（`VolunteerAccountView`），只少「资质审核」一行。
// 退出登录与两步删除的二次确认原样从改版前的「我的」搬过来，文案一字不改。
// 用 push 而不是 sheet：退出 / 删除进行中的进度遮罩挂在根视图上，sheet 会盖在遮罩上面，
// 遮罩期间背景就退不出无障碍树（`testSessionLifecycleOverlayHidesTheScreenBehindItDuringAccountDeletion` 守着）。

enum BlindAccountCopy {
    static let navigationTitle = "账户"
    static let roleLine = "视障跑者"
    static let profileTitle = "个人资料"
    static let privacyGroupTitle = "隐私"
    static let logout = "退出登录"
    static let deleteAccount = "删除账户"
    static let deletionFootnote = "删除账户会永久停用，需要再次确认。"
}

struct BlindAccountView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var deletionViewModel = AccountDeletionViewModel()
    @State private var showLogoutConfirm = false
    @State private var showDeletionInitialConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProfileAccountHeader(
                    name: appState.blindProfile?.name?.nilIfBlank ?? BlindSettingsCopy.unnamed,
                    roleLine: BlindAccountCopy.roleLine
                )
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
        .navigationTitle(BlindAccountCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮的栏会盖住最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindAccountView")
        .logoutConfirmation(isPresented: $showLogoutConfirm)
        .accountDeletionFlow(
            viewModel: deletionViewModel,
            isShowingInitialConfirmation: $showDeletionInitialConfirmation,
            role: .blind
        )
    }

    // MARK: 个人

    private var personalGroup: some View {
        GroupedCard {
            NavigationLink {
                BlindRunnerProfileView()
            } label: {
                SettingsRowLabel(title: BlindAccountCopy.profileTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(BlindAccountCopy.profileTitle)
            .accessibilityHint("编辑盲人跑者资料和紧急联系人")
        }
    }

    // MARK: 隐私

    private var privacyGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BlindAccountCopy.privacyGroupTitle)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding(.leading, GroupedCardMetrics.rowHorizontalPadding)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            GroupedCard {
                // 三项单独同意（语音大模型 / 视力与导盲犬 / 陪跑位置）的撤回放在一处（#393）。
                NavigationLink {
                    PrivacyAuthorizationView()
                } label: {
                    SettingsRowLabel(title: PrivacyAuthorizationCopy.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PrivacyAuthorizationCopy.title)
                .accessibilityHint("查看并撤回语音下单、视力状况和陪跑位置共享这三项同意")
                .accessibilityIdentifier("blindPrivacyAuthorizationSettingsEntry")

                GroupedCardDivider()

                NavigationLink {
                    BlockedUsersView()
                } label: {
                    SettingsRowLabel(title: UserSafetyCopy.blockedListTitle)
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
            GroupedCard {
                Button {
                    showLogoutConfirm = true
                } label: {
                    SettingsRowLabel(
                        title: BlindAccountCopy.logout,
                        titleColor: AppColors.destructive,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BlindAccountCopy.logout)
                .accessibilityHint("退出后需要重新登录，需要二次确认")

                GroupedCardDivider()

                Button {
                    showDeletionInitialConfirmation = true
                } label: {
                    SettingsRowLabel(
                        title: BlindAccountCopy.deleteAccount,
                        titleColor: AppColors.destructive,
                        showsChevron: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.accountDeletionState == .inProgress)
                .accessibilityLabel(BlindAccountCopy.deleteAccount)
                .accessibilityHint("永久停用当前账户，需要再次确认")
            }
            GroupedCardFootnote(text: BlindAccountCopy.deletionFootnote)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindAccountView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
