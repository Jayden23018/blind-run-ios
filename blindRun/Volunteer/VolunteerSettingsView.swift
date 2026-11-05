import SwiftUI

// 陪跑员「我的」：底部标签的根页，也是首页头像进来的「设置」页。
// 定稿：`docs/ui/mockups/volunteer-settings-20261104/`（负责人 2026-11-04 批准，#700）。
//
// 照健康 App「浏览」的版式：头像卡 → 账户页；常用入口做成两列彩色方块；其余留在列表。
// 只学版式，图标和颜色用自己的（审核 5.2.5）。
// 现有入口一个不少，`accessibilityIdentifier` 原样保留：UI 用例按它找入口。

enum VolunteerSettingsCopy {
    static let tabTitle = "我的"
    /// 从首页头像进来时仍叫「设置」，免得点「设置」进了一页叫「我的」的。
    static let gearTitle = "设置"
    static let accountCardSubtitle = "个人资料、实名与账户"
    static let categoriesTitle = "类别"
    static let unnamed = "未填写"
    static let achievementsTitle = "服务成就"
}

// MARK: - 方块

/// 「类别」里的六个方块。顺序就是屏幕上的顺序（两列时左右左右）。
enum VolunteerSettingsTile: CaseIterable, Identifiable {
    case training, schedule, certificate, partners, points, invite

    var id: Self { self }

    var title: String {
        switch self {
        case .training: return "陪跑培训"
        case .schedule: return "空闲时间"
        case .certificate: return "资质证书"
        case .partners: return "固定搭档"
        case .points: return "我的积分"
        case .invite: return "邀请好友"
        }
    }

    var systemImage: String {
        switch self {
        case .training: return "graduationcap.fill"
        case .schedule: return "calendar"
        case .certificate: return "person.text.rectangle.fill"
        case .partners: return "person.2.fill"
        case .points: return "star.fill"
        case .invite: return "gift.fill"
        }
    }

    /// 方块底色（纯色，压白字，亮暗两档同值）。必须过 4.5:1（`VolunteerSettingsTileTests`）。
    /// 不用稿子的上浅下深渐变：渐变底在真机无障碍审计里六块全判对比度不足（2026-11-05，#700），
    /// 纯色底同样压白字的资质证书卡则能过。取渐变里深的那一端。
    var rgb: UInt32 {
        switch self {
        case .training: return 0x1A6B33
        case .schedule: return 0xA8231A
        case .certificate: return 0x0A4FA6
        case .partners: return 0xB23A0B
        case .points: return 0x8A5500
        case .invite: return 0x075960
        }
    }

    var identifier: String {
        switch self {
        case .training: return "volunteerTrainingSettingsEntry"
        case .schedule: return "volunteerScheduleSettingsEntry"
        case .certificate: return "volunteerCertificateSettingsEntry"
        case .partners: return "volunteerPartnersSettingsEntry"
        case .points: return "volunteerPointsSettingsEntry"
        case .invite: return "volunteerInviteCodeSettingsEntry"
        }
    }

    /// 资质证书的提示随审核状态变，在视图里给。
    var hint: String? {
        switch self {
        case .training: return "学习必修与选修课程，完成必修后才能接单"
        // 空闲时间是匹配前提：空闲时间以外后端不发邀请，「我为什么收不到单」的第一个答案就在这里。
        case .schedule: return "设置你每周哪些时间有空，这些时间之外不会给你发邀请"
        case .certificate: return nil
        case .partners: return "查看哪些跑者把你设为固定搭档，以及你们连续一起跑步的周数"
        // 🔴 积分刻意不放进「服务成就」：积分与志愿服务时长必须是两个数、两处文案（中央网信办 2026-06-19 通知第 2 条）。
        case .points: return "查看积分余额和每一笔的加分原因"
        case .invite: return "查看你的邀请码和已经邀请的人数"
        }
    }
}

// MARK: - 页面

struct VolunteerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var achievements = VolunteerAchievementsViewModel()

    /// 底部「我的」标签的根页为 true：标题叫「我的」、列表第一行是服务成就。
    var isTabRoot = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                accountCard
                categories
                listGroup
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        // 导航栏给页面同色的实底：上推后饱和色的方块滚到半透明栏下面，标题「我的」压在模糊的红绿上，
        // 真机审计判对比度不足（2026-11-05，#700）。实底下标题永远压在页面底色上；在顶部时与页面同色，看不出栏。
        .toolbarBackground(AppColors.Flow.page, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle(isTabRoot ? VolunteerSettingsCopy.tabTitle : VolunteerSettingsCopy.gearTitle)
        .task {
            guard isTabRoot else { return }
            achievements.configure(appState: appState)
            await achievements.load()
        }
    }

    private var displayName: String {
        appState.volunteerProfile?.name?.nilIfBlank ?? VolunteerSettingsCopy.unnamed
    }

    // MARK: 头像卡

    private var accountCard: some View {
        NavigationLink {
            VolunteerAccountView()
        } label: {
            ProfileAccountCardLabel(name: displayName, subtitle: VolunteerSettingsCopy.accountCardSubtitle)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName)，\(VolunteerSettingsCopy.accountCardSubtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("volunteerAccountCardEntry")
    }

    // MARK: 类别方块

    private var categories: some View {
        SettingsTileGrid(title: VolunteerSettingsCopy.categoriesTitle, items: VolunteerSettingsTile.allCases) { tile in
            tileLink(tile)
        }
    }

    private func tileLink(_ tile: VolunteerSettingsTile) -> some View {
        NavigationLink {
            destination(for: tile)
        } label: {
            SettingsTileLabel(title: tile.title, systemImage: tile.systemImage, rgb: tile.rgb)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile == .certificate ? certificateState.displayName : "")
        .accessibilityHint(tile == .certificate ? certificateState.guidanceMessage : (tile.hint ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(tile.identifier)
    }

    @ViewBuilder
    private func destination(for tile: VolunteerSettingsTile) -> some View {
        switch tile {
        // 培训的另一个入口在接单前进度页（#706）；这里是常驻的，复习和选修只能从这里进。
        case .training: VolunteerTrainingView()
        case .schedule: VolunteerAvailabilityScheduleView()
        case .certificate: VolunteerCertificateUploadView()
        case .partners: VolunteerPartnersView()
        case .points: VolunteerPointsView()
        case .invite: InviteCodeView()
        }
    }

    /// 资料里的 `verificationStatus` 是后端 `VerificationStatus` 的四个取值之一；
    /// 尚未拉取到时按「状态未知」展示，不假装已提交或已通过。
    private var certificateState: VolunteerCertificateDisplayState {
        VolunteerCertificateDisplayState.from(
            status: VolunteerCertificateStatus.parse(appState.volunteerProfile?.verificationStatus),
            statusLoadFailed: false
        )
    }

    // MARK: 列表

    private var listGroup: some View {
        GroupedCard {
            if isTabRoot, let response = achievements.achievements {
                VolunteerSettingsAchievementsRow(response: response)
                GroupedCardDivider()
            }
            VolunteerSupportSettingsRows()
            GroupedCardDivider()
            // #521：通知开没开，拒绝过时给去系统设置的入口。
            NotificationPermissionRow()
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: GroupedCardMetrics.rowMinHeight, alignment: .leading)
            GroupedCardDivider()
            VolunteerHelpSettingsLink() // #656：第一次打开订单页会自动弹一次，这里是随时回看的入口
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
        VolunteerSettingsView(isTabRoot: true)
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
