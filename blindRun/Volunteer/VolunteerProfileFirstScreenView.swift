import SwiftUI

// 展示口径与文案在 `VolunteerProfileFirstScreen.swift` 与 `VolunteerHomeSummaryCards.swift`（同一目录）。
//
// 设计稿：`docs/ui/mockups/volunteer-home-v3-20261104/home-v3.html`（负责人 2026-11-04 定稿，#694）。
// 上一版（2026-09-14）：`docs/ui/mockups/volunteer-profile-first-screen-20260914/01-final-screen.html`。

/// 志愿者端首页：**只回答「我做过什么」**。
///
/// v3 的分工（#694）：首页 = 陪伴时长、连续陪跑 / 评分、最近陪跑、徽章，全部是白色圆角卡片；
/// 接单的东西（派单状态、定位摘要、下一次陪跑、暂停）全部在接单页 `VolunteerDispatchHubView`。
/// 两页之间只有底部白色底座里那一枚胶囊（`VolunteerAvailabilitySlider`，由 `VolunteerHomeView`
/// 挂在 `safeAreaInset` 上）。
///
/// 🔴 **但「需要你处理」的事必须留在这一屏的最上方。** 跨天预约的临期确认带着一个 60 分钟到期的动作，
/// 而 `docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二 的结论是
/// 「入口一律独立于『当前进行中』那个位，确认按钮直接摆在预约卡上，不进溢出菜单不进二级页」（#463，v3 没动它）。
/// 读屏顺序播报，排序就是优先级：先听到「你有一张单要确认」，再听陪伴时长和徽章。
struct VolunteerProfileFirstScreen: View {
    @EnvironmentObject var appState: AppState
    /// 下拉刷新时强制取一次点（见 `.refreshable`）。请求权限与开始更新在 `VolunteerTabView`，不在这一层。
    @EnvironmentObject var locationService: LocationService
    @ObservedObject var viewModel: VolunteerHomeViewModel

    /// 成就 / 固定搭档 / 火花三条只读端点。**刻意不并进 `VolunteerHomeViewModel`** ——
    /// 那份带着一条 10 秒轮询，而 `totalServiceMinutes` 要扫全部已完成订单
    /// （理由逐字在 `VolunteerHomeIncentiveViewModel` 顶部）。
    @StateObject var incentive = VolunteerHomeIncentiveViewModel()
    /// 最近陪跑卡的跑后记录。不并进上面那份的理由相同。
    @StateObject var recentRun = VolunteerHomeRecentRunModel()
    /// 「置顶」放哪几张卡、什么顺序（只存在本机）。编辑页拿同一份。
    @StateObject var pinnedStore = VolunteerHomePinnedStore()

    /// 无障碍字号下半宽卡改上下排、卡内的左右排改上下排。
    /// 🔴 **不用竖向 `ViewThatFits`**：它会让整页文字审计判成「改不了字号」
    /// （记忆 `viewthatfits-fails-dynamic-type-audit`）。
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    /// 右上角头像这一行的边长。跟字号长（低视力用户放大字号时这枚入口也跟着变大），
    /// 也把大标题往下推 —— 不长的话 AX5 下测试构建那枚 Mock 横幅会压住「首页」一截（真机审计 2026-11-04）。
    @ScaledMetric(relativeTo: .title) var avatarSide: CGFloat = 44

    let onReload: @MainActor () async -> Void

    /// 手写 init 只为一件事：上面几个属性要给同目录的 `VolunteerProfileFirstScreenView+*.swift`
    /// 用，不能再是 `private`（#508 拆文件），而不再 `private` 之后合成的 memberwise init
    /// 会把它们也收成参数。写出来让对外的初始化方式只有 `viewModel` / `onReload`。
    init(viewModel: VolunteerHomeViewModel, onReload: @escaping @MainActor () async -> Void) {
        self.viewModel = viewModel
        self.onReload = onReload
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                todoSection
                pinnedSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
            .padding(.bottom, 24)
            // 内层 `.infinity` 保留左对齐，外层把这条左对齐的列收进可读宽度并居中（iPad）。
            .readableContentColumn()
        }
        .background(alignment: .top) {
            VolunteerHomePageTint(top: AppColors.VolunteerHome.skyTop, middle: AppColors.VolunteerHome.skyMid)
        }
        .background(AppColors.Flow.page)
        .accessibilityIdentifier("volunteerProfileFirstScreen")
        .onAppear { pinnedStore.configure(persistence: appState.persistence) }
        // 手动刷新。这一屏的导航栏是隐藏的（`navigationBarHidden(true)`），没有工具栏按钮可放。
        //
        // 🚩 **不只是重拉摘要，同时强制取一次定位**：非陪跑模式 `distanceFilter` 是 10 米
        // （`LocationService.swift`），站着不动 Core Location 就不推新样本，而没有位置上报
        // 就收不到派单。
        .refreshable {
            locationService.requestOneTimeLocation()
            await onReload()
            await recentRun.load(appState: appState)
        }
        // 🔴 **这个 `.task` 挂在一棵永远非空的子树上。**
        //
        // 页头无条件渲染，所以 `ScrollView` 的内容永远不为空。写成
        // `if let summary { … }` 再把 `.task` 挂上去的话，条件不成立时整棵子树解析成空，
        // **`.task` 不会触发** ⇒ 永远不加载 ⇒ 永远渲染空，自己把自己锁死。
        // 这正是 commit `a3cee29`（PR #134）修的那个缺陷。回归钉子 `testVolunteerHomeShowsTheIncentiveCard`。
        .task {
            incentive.configure(appState: appState)
            await incentive.loadIfNeeded()
        }
        .task {
            await recentRun.loadIfNeeded(appState: appState)
        }
        // 跑完一单 / 收到评价后补拉一次（#335）。挂在同一棵永远非空的子树上，理由同上。
        .task(id: VolunteerHomeIncentiveViewModel.RefreshKey(viewModel.dispatchSummary)) {
            incentive.configure(appState: appState)
            await incentive.summaryVersionChanged(VolunteerHomeIncentiveViewModel.RefreshKey(viewModel.dispatchSummary))
        }
        // 最近陪跑只随完成次数变（收到评价不影响这张卡，不为它多拉跑后记录）。
        .task(id: viewModel.dispatchSummary?.totalCompleted) {
            await recentRun.completedCountChanged(viewModel.dispatchSummary?.totalCompleted, appState: appState)
        }
    }

    // MARK: - 页头

    /// 大标题「首页」+ 右上角头像（健康 App「摘要」的形状）。改版前的身份行（头像 + 昵称 + 角色）已删。
    ///
    /// 头像进设置 —— 与「我的」标签页是同一页（`VolunteerSettingsView`），也是改版前齿轮的去处。
    /// 后端 `VolunteerProfileResponse` 没有头像字段，所以这里是一个**符号**而不是一张编出来的图。
    ///
    /// identifier 沿用 `volunteerProfileIdentityRow`：十几条 UI 用例拿它判「首页渲染出来了」，
    /// 它在这一版指的是页头这一块。
    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                NavigationLink {
                    VolunteerSettingsView()
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: avatarSide * 0.78))
                        .foregroundColor(AppColors.textSecondary)
                        // 默认 44pt，是系统触达下限。志愿者端不受盲人端 64pt 线约束
                        // （`guard.mjs` 的 `small-touch-target` 显式排除 /blindRun/Volunteer/）。
                        .frame(width: avatarSide, height: avatarSide)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(VolunteerProfileCopy.settingsTitle)
                .accessibilityHint(VolunteerProfileCopy.settingsHint)
                .accessibilityIdentifier("volunteerProfileSettingsEntry")
            }

            Text(VolunteerProfileCopy.pageTitle)
                .font(AppFonts.largeTitle())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
        }
        .padding(.top, 4)
        // 容器上只放 identifier + `children: .contain`：不配 `.contain` 的话，
        // 容器的 identifier 会向下盖掉每个子元素自己的 id（头像入口就会找不到）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerProfileIdentityRow")
    }

    // MARK: - 共用零件

    /// 分区标题：加粗大字（健康 App 的分区标题），不再是 13pt 灰色小字（#694）。
    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.title())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 分区标题行：标题在左，蓝色文字链接在右。四周留白照样例（标题与上一张卡之间 14pt）。
    func sectionHeader<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            sectionLabel(title)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    /// 分区标题右侧的文字链接。样例里没有箭头：「全部记录」这几个字本身就说清了去处。
    func linkLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(AppColors.primary)
            .fixedSize(horizontal: false, vertical: true)
            // 44pt 是系统触达下限。志愿者端不受盲人端 64pt 线约束
            // （`guard.mjs` 的 `small-touch-target` 显式排除 /blindRun/Volunteer/）。
            .frame(minHeight: 44)  // guard:allow small-touch-target
            .contentShape(Rectangle())
    }
}

// MARK: - 卡片

/// 首页与接单页共用的白色圆角卡片（#694：两页「同一套卡片样式」）。
///
/// 不用 `FlowCard`：那一张带两层阴影，是订单页的样式；健康 App 摘要的卡片是平的，
/// 边界靠白卡压在浅灰底上（`Flow.surface` / `Flow.page`，暗色是 `#1C1C1E` 压纯黑）。
struct VolunteerHomeCard<Content: View>: View {
    /// 样例 `.card{border-radius:22px}`。
    static var cornerRadius: CGFloat { VolunteerHomeRadius.summaryCard }

    var padding = EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)
    var background: Color = AppColors.Flow.surface
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}

/// 卡片左上角的「图标 + 卡名」，右边可选一行灰字（日期）和箭头。
///
/// 🚩 **箭头只给真有去处的卡**（#694）：没有去处的卡画箭头，就是「点了没反应」。
struct VolunteerHomeCardHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    var meta: String?
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 图标只是装饰：卡名就在旁边，不靠颜色也不靠图标传达（WCAG 1.4.1）。
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if let meta {
                Text(meta)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(tint)
    }
}

/// 页面顶部那一抹颜色。纯装饰，不承载信息。
///
/// 照样例三段：`top` 在最上沿，`middle` 在 150pt，300pt 处回到页面底色
/// （`linear-gradient(180deg,#CFE3F7 0,#E7EEF6 150px,bg 300px)`）。
/// 首页传天蓝（`AppColors.VolunteerHome.skyTop / skyMid`），接单页传浅绿。
struct VolunteerHomePageTint: View {
    let top: Color
    var middle: Color?

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: top, location: 0),
                .init(color: middle ?? top.opacity(0.5), location: 0.5),
                .init(color: AppColors.Flow.page, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
            .frame(height: 300)
            .ignoresSafeArea(edges: .top)
            .accessibilityHidden(true)
    }
}
