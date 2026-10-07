import Combine
import SwiftUI

// MARK: - Blind Runner Settings View

struct BlindRunnerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var deletionViewModel = AccountDeletionViewModel()
    @State private var showLogoutConfirm = false
    @State private var showDeletionInitialConfirmation = false
    /// 本月汇总，与「记录」tab 同一个 view model、同一句文案（不另写一份）。
    @StateObject private var monthSummary = RunRecordHistoryViewModel(role: .runner)

    /// 底部「我的」标签的根页为 true：标题叫「我的」、顶上有本月汇总卡。
    /// 从别处 push 进来（引导页）时仍是「设置」，那条路的用户是来改设置的。
    var isTabRoot = false

    var body: some View {
        List {
            if isTabRoot, (monthSummary.history?.monthSummary.runs ?? 0) > 0, let summary = monthSummary.summaryText() {
                // 「我的」页此前是一张纯设置列表（2026-10-05 截图评审：吸引力 2/10）。
                // 只放跑者自己的一句成绩，不放排名、不放与他人比较（design-direction §1）。
                // 本月 0 次时**不显示**：页面最顶上一句「10月还没有跑步记录」是在泼冷水，
                // 而这一页不是记录页，没有「约一次」的出口可以接住它（design-direction §8 第 5 条）。
                Section {
                    Text(summary)
                        .font(AppFonts.title())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                        .accessibilityLabel(monthSummary.summaryText(spoken: true) ?? summary)
                        .accessibilityIdentifier("blindProfileMonthSummary")
                }
            }

            Section {
                settingsRow("昵称", value: appState.blindProfile?.name ?? "未填写")
                settingsRow("当前角色", value: "视障跑者")
            }

            Section {
                // 🗑「我的历史订单」这条入口已删除：2026-09-16 起它是底部标签栏的「记录」tab
                // （`BlindRunnerTabView`），一个顶级 tab 加一条列表行等于同一个页面两条路。
                // 对靠位置记忆操作的读屏用户，两条路比一条路更难记 —— 而 tab 那条永远在。
                //
                // 原注释「入口放设置而不是首页，因为首页刚做过减法」已作废：那次减法减掉的是
                // 280pt 主按钮那一版的首页，而现在首页是「问候 + 订单卡 + 预约块」三块，
                // 历史订单也不在首页上，它在自己的 tab 里。

                NavigationLink("个人资料") {
                    BlindRunnerProfileView()
                }
                .accessibilityLabel("个人资料")
                .accessibilityHint("编辑盲人跑者资料和紧急联系人")

                // SPEC-E 的两个入口。同样放设置而不是首页，理由与上面「我的历史订单」那条一样。
                NavigationLink("我的固定搭档") {
                    BlindFavoriteVolunteersView()
                }
                .accessibilityLabel("我的固定搭档")
                .accessibilityHint("查看你的固定搭档，以及你们连续一起跑步的周数")
                .accessibilityIdentifier("blindFavoriteVolunteersSettingsEntry")

                NavigationLink("我的邀请码") {
                    InviteCodeView()
                }
                .accessibilityLabel("我的邀请码")
                .accessibilityHint("查看你的邀请码和已经邀请的人数")
                .accessibilityIdentifier("blindInviteCodeSettingsEntry")

                // 实名是下单硬门槛（后端 403 IDENTITY_NOT_VERIFIED），引导流里「稍后再说」跳过后
                // 必须还有一条随时能走回实名页的路，否则未实名用户会被永久挡在预约之外。
                NavigationLink("实名认证") {
                    BlindIdentityVerificationView()
                }
                .accessibilityLabel("实名认证，当前状态\(appState.blindIdentityStatus.displayName)")
                .accessibilityHint("提交姓名和身份证号完成实名认证，完成后才能预约跑步")

                #if DEBUG
                if AppBuildChannel.current.allowsEnvironmentSwitcher {
                    Picker("API 环境", selection: $appState.currentEnvironment) {
                        ForEach(AppState.debugTestEnvironments, id: \.self) { environment in
                            Text(environment.displayName).tag(environment)
                        }
                    }
                    .accessibilityLabel("API 环境，\(appState.currentEnvironment.displayName)")
                }
                #endif

                // 首次进首页会自动播一遍，这里是它**唯一**的重听入口 ——
                // 没有这条，漏听的人就永远拿不回来了（引导正是最容易漏听的那一段）。
                NavigationLink("使用帮助") {
                    BlindRunnerHelpView(isFirstRun: false)
                }
                .accessibilityLabel("使用帮助")
                .accessibilityHint("重新播报怎么约跑、怎么求助、怎么重听当前状态")
                .accessibilityIdentifier("blindRunnerSettingsHelpLink")

                NavigationLink("关于") {
                    AboutAidRunView()
                }
            }

            Section {
                Button("退出登录", role: .destructive) {
                    showLogoutConfirm = true
                }
                .accessibilityLabel("退出登录")
                .accessibilityHint("退出后需要重新登录，需要二次确认")

                Button("删除账户", role: .destructive) {
                    showDeletionInitialConfirmation = true
                }
                .disabled(appState.accountDeletionState == .inProgress)
                .accessibilityLabel("删除账户")
                .accessibilityHint("永久停用当前账户，需要再次确认")
            }

        }
        .navigationTitle(isTabRoot ? "我的" : "设置")
        .task {
            guard isTabRoot else { return }
            // 不传 `speechService`：每次切到「我的」都念一遍本月汇总是噪音，记录页才需要那句播报。
            monthSummary.configure(with: appState, speechService: nil)
            await monthSummary.load()
        }
        .alert("无法删除账户", isPresented: $deletionViewModel.isShowingPreflightBlock) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deletionViewModel.preflightMessage ?? "")
        }
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("确认退出", role: .destructive) {
                Task { await appState.logout() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后将清除当前登录状态，返回登录页。")
        }
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
            Text(AccountDeletionViewModel.finalConfirmationMessage(for: .blind))
        }
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindRunnerSettingsView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
