import SwiftUI

// 展示口径与文案在 `VolunteerProfileFirstScreen.swift`（同一目录）。
//
// 设计稿：`docs/ui/mockups/volunteer-profile-first-screen-20260914/01-final-screen.html`
// 结构依据：`docs/research/volunteer-profile-first-screen-20260914.md` §2
// （紧凑身份行 → 一个 3× 于其他数字的主指标 → 3 列同质统计 → 一排徽章加「全部 ›」→ 紧凑活动流）

/// 志愿者端的第一屏：**「我是谁、我做过什么」**。
///
/// 🚩 **主操作不在这一屏的内容里**，它在底部那条滑动 CTA 上
/// （`VolunteerAvailabilitySlider`，由 `VolunteerHomeView` 挂在 `safeAreaInset` 上）。
/// Strava 的 Record 是独立 tab，Be My Eyes 的「Call a volunteer」是一枚巨大的独立按钮 ——
/// 个人页不承担主操作是这几个参考里唯一一致的结构（调研 §2.6）。
///
/// 🔴 **但「需要你处理」的事必须留在这一屏。** 跨天预约的临期确认带着一个 60 分钟到期的动作，
/// 而 `docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二 的结论是
/// 「入口一律独立于『当前进行中』那个位，确认按钮直接摆在预约卡上，不进溢出菜单不进二级页」。
/// 所以作业区排在影响力区**之前** —— 读屏顺序播报，排序就是优先级，
/// 让人先听完 24 次陪跑和 7 枚勋章才听到「你有一张单要确认」是反的。
struct VolunteerProfileFirstScreen: View {
    @EnvironmentObject var appState: AppState
    /// 读「定位摘要」那一行（`dispatchSection` 末尾），以及下拉刷新、「重新定位」与
    /// 「重新加载派单状态」时强制取一次点。
    /// 请求权限与开始更新在 `VolunteerHomeView.onAppear`，不在这一层。
    @EnvironmentObject var locationService: LocationService
    @ObservedObject var viewModel: VolunteerHomeViewModel

    /// 成就 / 固定搭档 / 火花三条只读端点。**刻意不并进 `VolunteerHomeViewModel`** ——
    /// 那份带着一条 10 秒轮询，而 `totalServiceMinutes` 要扫全部已完成订单
    /// （理由逐字在 `VolunteerHomeIncentiveViewModel` 顶部）。
    @StateObject var incentive = VolunteerHomeIncentiveViewModel()

    let onReload: @MainActor () async -> Void

    /// 手写 init 只为一件事：上面三个属性要给同目录的 `VolunteerProfileFirstScreenView+*.swift`
    /// 用，不能再是 `private`（#508 拆文件），而不再 `private` 之后合成的 memberwise init
    /// 会把它们也收成参数。写出来让对外的初始化方式与拆分前一样只有 `viewModel` / `onReload`，
    /// `incentive` 只由 `@StateObject` 的初始值创建，外面传不进来。
    init(viewModel: VolunteerHomeViewModel, onReload: @escaping @MainActor () async -> Void) {
        self.viewModel = viewModel
        self.onReload = onReload
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityRow
                todoSection
                impactSection
                badgesSection
                recentSection
                dispatchSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
            // 内层 `.infinity` 保留左对齐，外层把这条左对齐的列收进可读宽度并居中（iPad）。
            .readableContentColumn()
        }
        .background(AppColors.background)
        .accessibilityIdentifier("volunteerProfileFirstScreen")
        // 手动刷新。它接替的是随「派单工作台」一起删掉的那枚工具栏刷新按钮 ——
        // 这一屏的导航栏是隐藏的（`navigationBarHidden(true)`），按钮无处可放，
        // 而删了不补就等于志愿者只能等那条 10 秒轮询。
        //
        // 🚩 **不只是重拉摘要，同时强制取一次定位**：非陪跑模式 `distanceFilter` 是 10 米
        // （`LocationService.swift`），站着不动 Core Location 就不推新样本，而没有位置上报
        // 就收不到派单。这一下取点原先由地图上那枚「回到当前位置」承担，地图删了之后
        // 志愿者端一个 `requestOneTimeLocation()` 的调用点都不剩了。
        .refreshable {
            locationService.requestOneTimeLocation()
            await onReload()
        }
        // 🔴 **这个 `.task` 挂在一棵永远非空的子树上。**
        //
        // 身份行无条件渲染，所以 `ScrollView` 的内容永远不为空。写成
        // `if let summary { … }` 再把 `.task` 挂上去的话，条件不成立时整棵子树解析成空，
        // **`.task` 不会触发** ⇒ 永远不加载 ⇒ 永远渲染空，自己把自己锁死。
        // 这正是 commit `a3cee29`（PR #134）修的那个缺陷，而这一屏全是条件卡片，
        // 是它最可能复发的地方。回归钉子 `testVolunteerHomeShowsTheIncentiveCard`。
        .task {
            incentive.configure(appState: appState)
            await incentive.loadIfNeeded()
        }
        // 跑完一单 / 收到评价后影响力区补拉一次（#335）。挂在同一棵永远非空的子树上，理由同上。
        .task(id: VolunteerHomeIncentiveViewModel.RefreshKey(viewModel.dispatchSummary)) {
            incentive.configure(appState: appState)
            await incentive.summaryVersionChanged(VolunteerHomeIncentiveViewModel.RefreshKey(viewModel.dispatchSummary))
        }
    }

    // MARK: - 身份行

    /// 紧凑身份行，**不做居中大头像**（调研 §2.3）——身份占一行就够，
    /// 省下的高度全给影响力。HelpUnity 那种「大头像 + 一行小字时长 + 随即塌成设置列表」
    /// 是本轮唯一的反面参考。
    private var identityRow: some View {
        HStack(spacing: 13) {
            // 后端 `VolunteerProfileResponse` 没有头像字段，所以这里是一个**符号**而不是
            // 一张编出来的图。对读屏隐藏：它不承载任何信息。
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(AppColors.textSecondary.opacity(0.45))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(VolunteerProfileCopy.roleSubtitle(starLevel: starLevel?.current))
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            NavigationLink {
                VolunteerSettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.medium))
                    .foregroundColor(AppColors.textSecondary)
                    // 44pt 是系统触达下限。志愿者端不受盲人端 64pt 线约束
                    // （`guard.mjs` 的 `small-touch-target` 显式排除 /blindRun/Volunteer/）。
                    .frame(width: 44, height: 44)  // guard:allow small-touch-target
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(VolunteerProfileCopy.settingsTitle)
            .accessibilityHint(VolunteerProfileCopy.settingsHint)
            .accessibilityIdentifier("volunteerProfileSettingsEntry")
        }
        // 容器上只放 identifier + `children: .contain`：不配 `.contain` 的话，
        // 容器的 identifier 会向下盖掉每个子元素自己的 id（齿轮入口就会找不到）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerProfileIdentityRow")
    }

    private var displayName: String {
        viewModel.nickname.nilIfBlank ?? VolunteerProfileCopy.roleTitle
    }

    private var starLevel: VolunteerStarLevelDto? {
        incentive.summary?.achievements?.resolvedStarLevel
    }

    // MARK: - 共用零件

    /// 分区标题：小号灰字 —— 中文运动 App 的通行写法（调研 §1.5 C2）。
    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.caption().weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
    }

    func linkLabel(_ text: String) -> some View {
        HStack(spacing: 3) {
            Text(text)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
        }
        .font(AppFonts.caption().weight(.semibold))
        .foregroundColor(AppColors.primary)
        // 44pt 是系统触达下限。志愿者端不受盲人端 64pt 线约束
        // （`guard.mjs` 的 `small-touch-target` 显式排除 /blindRun/Volunteer/）。
        .frame(minHeight: 44)  // guard:allow small-touch-target
        .contentShape(Rectangle())
    }
}
