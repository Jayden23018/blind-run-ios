import SwiftUI

// 盲人端「我的」：底部标签的根页，也是引导页 push 进来的「设置」页。
// 定稿：`docs/ui/mockups/blind-profile-20261105/`（负责人 2026-11-05：「和陪跑员完全一致」，按 v1 做，#711）。
//
// 与陪跑员「我的」同一套版式与组件（`Shared/SettingsTileComponents.swift`）：头像卡 → 账户页；常用入口做成两列方块；其余留在列表。
// 和陪跑员版只差两处：方块四个；列表行一律 64pt。
// 没有紧急呼叫行：负责人 2026-11-05「盲人的“我的”界面不需要一个常驻的求助按钮」，整行删掉（#711）。
// 求助走标签栏容器上的 Magic Tap（`BlindRunnerTabView`）和订单页的「求助与安全」。
// 现有入口一个不少，`accessibilityIdentifier` 原样保留：UI 用例按它找入口。

enum BlindSettingsCopy {
    static let tabTitle = "我的"
    /// 从引导页 push 进来时仍叫「设置」，那条路的用户是来改设置的。
    static let onboardingTitle = "设置"
    static let accountCardSubtitle = "个人资料与账户"
    static let categoriesTitle = "类别"
    static let unnamed = "未填写"
}

// MARK: - 方块

/// 「类别」里的四个方块。顺序就是屏幕上的顺序（两列时左右左右）。
enum BlindSettingsTile: CaseIterable, Identifiable {
    case partners, invite, help, support

    var id: Self { self }

    var title: String {
        switch self {
        case .partners: return "固定搭档"
        case .invite: return "邀请好友"
        case .help: return "使用帮助"
        case .support: return SupportTicketCopy.title
        }
    }

    var systemImage: String {
        switch self {
        case .partners: return "person.2.fill"
        case .invite: return "gift.fill"
        case .help: return "questionmark.circle.fill"
        case .support: return "bubble.left.fill"
        }
    }

    /// 方块底色（纯色，压白字，亮暗两档同值）。必须过 4.5:1（`BlindSettingsTileTests`）。
    /// 取陪跑员版已在真机审计里过过的色值：固定搭档、邀请好友同名同色；使用帮助用陪跑培训的绿，联系客服用资质证书的蓝。
    var rgb: UInt32 {
        switch self {
        case .partners: return VolunteerSettingsTile.partners.rgb
        case .invite: return VolunteerSettingsTile.invite.rgb
        case .help: return VolunteerSettingsTile.training.rgb
        case .support: return VolunteerSettingsTile.certificate.rgb
        }
    }

    var identifier: String {
        switch self {
        case .partners: return "blindFavoriteVolunteersSettingsEntry"
        case .invite: return "blindInviteCodeSettingsEntry"
        case .help: return "blindRunnerSettingsHelpLink"
        case .support: return "supportTicketSettingsEntry"
        }
    }

    var hint: String {
        switch self {
        case .partners: return "查看你的固定搭档，以及你们连续一起跑步的周数"
        case .invite: return "查看你的邀请码和已经邀请的人数"
        // 首次进首页会自动播一遍，这里是它**唯一**的重听入口 ——
        // 没有这条，漏听的人就永远拿不回来了（引导正是最容易漏听的那一段）。
        case .help: return "重新播报怎么约跑、怎么求助、怎么重听当前状态"
        case .support: return SupportTicketCopy.settingsHint
        }
    }
}

// MARK: - 页面

struct BlindRunnerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @State private var showsSupportTicket = false

    /// 底部「我的」标签的根页为 true：标题叫「我的」。本月汇总已移到首页，同一句不放两处。
    var isTabRoot = false

    var body: some View {
        ScrollView {
            // 声明顺序就是读屏顺序：我的 → 头像卡 → 类别 → 方块 → 列表。
            VStack(alignment: .leading, spacing: 16) {
                accountCard
                SettingsTileGrid(title: BlindSettingsCopy.categoriesTitle, items: BlindSettingsTile.allCases) { tile in
                    tileEntry(tile)
                }
                listGroup
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        // 导航栏底色用页面同色，但**不强制常显**（不写 `.toolbarBackground(.visible)`）：
        // iOS 27 真机上常显的实底会把顶部的大标题「我的」整个盖住（2026-11-05 截图，#711；陪跑员版同写法同问题）。
        // 上推后系统自己换成带底色的栏，标题对比度由审计用例守着。
        .toolbarBackground(AppColors.Flow.page, for: .navigationBar)
        .navigationTitle(isTabRoot ? BlindSettingsCopy.tabTitle : BlindSettingsCopy.onboardingTitle)
        .sheet(isPresented: $showsSupportTicket) {
            SupportTicketView(
                orderID: nil,
                category: .account,
                appState: appState,
                speak: { speechService.speak($0) },
                speakError: { speechService.speakError($0) }
            )
        }
    }

    private var displayName: String {
        appState.blindProfile?.name?.nilIfBlank ?? BlindSettingsCopy.unnamed
    }

    // MARK: 头像卡

    private var accountCard: some View {
        NavigationLink {
            BlindAccountView()
        } label: {
            ProfileAccountCardLabel(name: displayName, subtitle: BlindSettingsCopy.accountCardSubtitle)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName)，\(BlindSettingsCopy.accountCardSubtitle)")
        .accessibilityHint("打开账户页：个人资料、隐私、退出登录和删除账户")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("blindAccountCardEntry")
    }

    // MARK: 类别方块

    @ViewBuilder
    private func tileEntry(_ tile: BlindSettingsTile) -> some View {
        let label = SettingsTileLabel(title: tile.title, systemImage: tile.systemImage, rgb: tile.rgb)
        Group {
            switch tile {
            // 联系客服是写字页，弹出来；和改版前一样不带订单。
            case .support:
                Button { showsSupportTicket = true } label: { label }
            case .partners:
                NavigationLink { BlindFavoriteVolunteersView() } label: { label }
            case .invite:
                NavigationLink { InviteCodeView() } label: { label }
            case .help:
                NavigationLink { BlindRunnerHelpView(isFirstRun: false) } label: { label }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.title)
        .accessibilityHint(tile.hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(tile.identifier)
    }

    // MARK: 列表

    private var listGroup: some View {
        GroupedCard {
            // 提交之后唯一能看到回复的地方（`SUPPORT_TICKET_REPLIED` 推送错过了就只剩这里）。
            NavigationLink {
                MySupportTicketsView()
            } label: {
                SettingsRowLabel(title: SupportTicketCopy.myTicketsTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SupportTicketCopy.myTicketsTitle)
            .accessibilityHint(SupportTicketCopy.myTicketsHint)
            .accessibilityIdentifier("mySupportTicketsSettingsEntry")

            GroupedCardDivider()
            // #521：通知开没开，拒绝过时给去系统设置的入口。
            NotificationPermissionRow()
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            GroupedCardDivider()

            NavigationLink {
                AboutAidRunView()
            } label: {
                SettingsRowLabel(title: "关于")
            }
            .buttonStyle(.plain)

            #if DEBUG
            if AppBuildChannel.current.allowsEnvironmentSwitcher {
                GroupedCardDivider()
                Picker("API 环境", selection: $appState.currentEnvironment) {
                    ForEach(AppState.debugTestEnvironments, id: \.self) { environment in
                        Text(environment.displayName).tag(environment)
                    }
                }
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                .accessibilityLabel("API 环境，\(appState.currentEnvironment.displayName)")
            }
            #endif
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindRunnerSettingsView(isTabRoot: true)
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
