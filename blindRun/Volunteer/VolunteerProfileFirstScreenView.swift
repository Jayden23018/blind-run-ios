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
    @EnvironmentObject private var appState: AppState
    /// 只用来读「定位摘要」那一行（`dispatchSection` 末尾）。
    /// 请求权限与开始更新在 `VolunteerHomeView.onAppear`，不在这一层。
    @EnvironmentObject private var locationService: LocationService
    @ObservedObject var viewModel: VolunteerHomeViewModel

    /// 成就 / 固定搭档 / 火花三条只读端点。**刻意不并进 `VolunteerHomeViewModel`** ——
    /// 那份带着一条 10 秒轮询，而 `totalServiceMinutes` 要扫全部已完成订单
    /// （理由逐字在 `VolunteerHomeIncentiveViewModel` 顶部）。
    @StateObject private var incentive = VolunteerHomeIncentiveViewModel()

    let onReload: () async -> Void

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

    // MARK: - 作业区

    /// 「需要你处理」。**全部条件渲染**，一件没有时整块不出现，首屏就等于设计稿。
    @ViewBuilder
    private var todoSection: some View {
        let hasTodo = viewModel.activeOrder != nil
            || !viewModel.scheduledOrders.isEmpty
            || viewModel.scheduledOrdersMessage != nil
            || viewModel.acceptBlockMessage != nil
            || needsCertificateEntry
            || needsTrainingEntry
            || viewModel.locationDispatchWarning != nil
            || viewModel.displayedErrorMessage != nil

        if hasTodo {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(VolunteerProfileCopy.todoSectionTitle)

                if let activeOrder = viewModel.activeOrder {
                    NavigationLink {
                        VolunteerInServiceView(orderId: activeOrder.orderId, initialOrder: activeOrder)
                    } label: {
                        VolunteerCurrentOrderCard(order: activeOrder)
                    }
                    .buttonStyle(.plain)
                    // 姓名去掉掩码星号 —— 只念不显示，见 `String.unmaskedForSpeech`。
                    .accessibilityLabel("当前订单：\(activeOrder.status.displayName)，盲人 \(activeOrder.blindName?.unmaskedForSpeech ?? "")，地点 \(activeOrder.startAddress ?? "")")
                    .accessibilityHint("点击进入当前订单")
                    .accessibilityIdentifier("volunteerHomeCurrentOrderCard")
                }

                VolunteerScheduledOrdersSection(
                    orders: viewModel.scheduledOrders,
                    submittingOrderID: viewModel.submittingScheduledOrderID,
                    message: viewModel.scheduledOrdersMessage,
                    onConfirm: { orderID in
                        Task { await viewModel.confirmScheduledDeparture(orderID: orderID) }
                    },
                    onRelease: { orderID in
                        Task { await viewModel.releaseScheduledOrder(orderID: orderID) }
                    }
                )

                // 「为什么接不到单」和「去哪解决」必须在同一处 —— 所以资质入口跟着提示走，
                // 不留一行没有去处的说明（同下面 `trainingEntry` 与「重新定位」那两条判据）。
                if let acceptBlockMessage = viewModel.acceptBlockMessage {
                    Text(acceptBlockMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(acceptBlockMessage)
                }

                if needsCertificateEntry {
                    VolunteerCertificateUploadEntryLink()
                }

                if needsTrainingEntry {
                    trainingEntry
                }

                if let warning = viewModel.locationDispatchWarning {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(warning, systemImage: "location.slash.fill")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(warning)
                            .accessibilityHint("请检查定位权限，并等待设备获取当前位置")
                            .accessibilityIdentifier("volunteerDispatchLocationWarning")

                        // 「为什么接不到单」和「去哪解决」必须在同一处 —— 同 `trainingEntry`
                        // 与资质入口那条判据。原文只有上面那行字：它告诉人出了什么事，
                        // 却没有任何能促成一次取点的动作，而站着不动时 Core Location
                        // 本来就不推新样本（`distanceFilter` 10 米）。
                        Button("重新定位") {
                            locationService.requestOneTimeLocation()
                            Task { await onReload() }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("立即重新获取一次当前位置，并刷新派单状态")
                        .accessibilityIdentifier("volunteerDispatchRelocateButton")
                    }
                }

                if let errorMessage = viewModel.displayedErrorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(errorMessage)
                        Button("重试加载") {
                            Task { await onReload() }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("重新加载派单和当前订单状态")
                    }
                }
            }
        }
    }

    /// 判据全在 `VolunteerProfileTodoGate`（纯函数，有验红用例），这里只做转发。
    private var needsCertificateEntry: Bool {
        VolunteerProfileTodoGate.needsCertificateEntry(
            summary: viewModel.dispatchSummary,
            apiRejectedAsUnapproved: viewModel.needsCertificateUpload
        )
    }

    private var needsTrainingEntry: Bool {
        VolunteerProfileTodoGate.needsTrainingEntry(summary: viewModel.dispatchSummary)
    }

    /// 必修培训入口。**整张卡可点**，不是「一行说明 + 旁边一个小链接」。
    ///
    /// 用户原话：「必须在派单工作台点进去再点击一个贼小的去培训，一点都不显眼」。
    /// 所以三件事同时成立才算修好：① 在首屏、不在任何二级页；② 原因本身就是入口，
    /// 不需要先读懂一句话再去找按钮；③ 点一下直达培训页，中间没有别的页。
    ///
    /// 🚩 **`NavigationLink` 而不是 `.sheet`**（旧实现是 sheet）。两条理由：
    /// 这一屏确定在 `NavigationStack` 里（`VolunteerHomeView.body`），旧注释说的
    /// 「首页不保证处在 NavigationStack 里」已经不成立；而 sheet 会盖住刻意挂在
    /// `NavigationStack` **外面**的派单弹窗（AGENTS §5：模态最高优先级），push 不会。
    private var trainingEntry: some View {
        NavigationLink {
            VolunteerTrainingView()
        } label: {
            HStack(spacing: 12) {
                // 图标只是装饰：档位与原因全在文字里，不靠颜色也不靠图标传达（WCAG 1.4.1）。
                Image(systemName: "graduationcap.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText)
                        .font(AppFonts.body().weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(VolunteerProfileCopy.trainingEntryDetail)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 不写死高度，只给下限：文字自己跟 Dynamic Type 长，卡片跟着长。
            // 64 在这里不是触达下限（志愿者端走 Apple 的 44pt），而是「显眼」的量化形式 ——
            // 用户那句「一个贼小的去培训」说的就是这个维度。
            // 不加 `guard:allow small-touch-target`：那条规则既排除了 /blindRun/Volunteer/，
            // 判据又是 `< 64`，双重不触发，多余的标注只会稀释它在别处的信号。
            .frame(minHeight: 64)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        // ⛔ **不加** `.accessibilityElement(children: .combine)`。打在 `NavigationLink` 自身上
        // 会新建一个合成元素，link/button trait 有丢失风险，而这是必修培训唯一的显眼入口。
        // 同屏两个同形状的兄弟节点（当前订单卡、最近陪跑行）也都只有
        // `buttonStyle(.plain)` + `accessibilityLabel`，这里保持一致。
        .accessibilityLabel(
            "\(VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText)。"
                + VolunteerProfileCopy.trainingEntryDetail
        )
        .accessibilityHint(VolunteerProfileCopy.trainingEntryHint)
        .accessibilityIdentifier("volunteerHomeTrainingEntry")
    }

    // MARK: - 影响力区

    /// 主指标 + 3 列统计 + 火花 + 国标星级。
    ///
    /// 四态**必有其一**（内容 / 加载中 / 失败+重试 / 空），一个都没有就是
    /// 「`.task` 没触发」那个缺陷复发了。identifier 沿用改版前那四个，
    /// 回归用例 `testVolunteerHomeShowsTheIncentiveCard` 断的就是它们。
    @ViewBuilder
    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(VolunteerProfileCopy.impactSectionTitle)

            // 🔴 **判据是 `summary.achievements` 非空，不是 `summary` 非空。**
            //
            // `summary` 只要三条请求里**成功了任意一条**就会被赋值（收藏 / 成就 / 火花各自独立容错），
            // 所以「成就那条失败、收藏那条成功」时 `summary != nil` 而 `achievements == nil`。
            // 按 `summary` 判的话：第一个分支恒中 ⇒ 下面的失败 + 重试**永远走不到**，
            // 而 `totalCompleted` 为 nil 会被 `resolve` 当成 0 ⇒ 屏幕上出现
            // 「还没有完成的陪跑」+ 星级和 3 列统计一起消失 ——
            // **跑过 200 次的老志愿者和真新人逐字不可区分，且没有任何出错信号。**
            //
            // 这一屏把 `achievements` 变成了主指标的**唯一**来源（改版前那张卡的 `hero`
            // 还能退到 `favoritedByCount`），所以这个风险面是本次改版新造出来的。
            if let achievements = incentive.summary?.achievements, let summary = incentive.summary {
                impactContent(summary, achievements: achievements)
            } else if incentive.loadFailed {
                impactPlaceholder(
                    VolunteerHomeIncentiveCopy.loadFailure,
                    identifier: "volunteerHomeIncentiveFailure"
                )
                Button(VolunteerHomeIncentiveCopy.retry) {
                    Task { await incentive.load() }
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                .frame(minHeight: 44)  // guard:allow small-touch-target
                .accessibilityIdentifier("volunteerHomeIncentiveRetryButton")
            } else {
                impactPlaceholder(
                    VolunteerHomeIncentiveCopy.loading,
                    identifier: "volunteerHomeIncentiveLoading"
                )
            }
        }
    }

    /// `achievements` 作为**非可选**参数传进来，不是在这里现拆 —— 拆包失败时
    /// `resolve(totalCompleted: nil)` 会安静地落进 `.newcomer`，那正是上面那段注释说的缺陷。
    /// 让类型系统保证「走到这里就是真的读到了成就数据」。
    @ViewBuilder
    private func impactContent(
        _ summary: VolunteerHomeIncentiveSummary,
        achievements: VolunteerAchievementsResponse
    ) -> some View {
        let headline = VolunteerProfileHeadline.resolve(totalCompleted: achievements.totalCompleted)

        VStack(alignment: .leading, spacing: 14) {
            hero(headline)

            if headline.showsImpactSections {
                statsRow(summary, achievements: achievements)
            }

            if let streak = summary.streak {
                StreakStrip(
                    // 只念不显示，所以去掉掩码星号（见 `StreakStrip.partnerName`）。
                    partnerName: summary.streakPartnerName?.unmaskedForSpeech.nilIfBlank
                        ?? PartnerStreakCopy.unknownBlindName,
                    streak: streak
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("volunteerHomeIncentiveCard")

        if headline.showsImpactSections {
            starCard(achievements.resolvedStarLevel)
        }
    }

    /// 主指标。🔴 走 `AppFonts.largeTitle()` 而不是设计稿上那个 60pt 固定磅值 ——
    /// 一屏上最大的那个数字恰恰是低视力用户最需要放大的东西，固定磅值不跟 Dynamic Type 走。
    /// 本仓库为这条栽过一次（成就页头部原本写死 48pt）。
    @ViewBuilder
    private func hero(_ headline: VolunteerProfileHeadline) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch headline {
            case .newcomer:
                Text(VolunteerProfileCopy.newcomerHeadline)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(VolunteerProfileCopy.newcomerDetail)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .completed(let count):
                // 数字与量词同一行、量词小一号：主次靠**字号差**拉开，不靠卡片边框
                // （调研 §2.1，Nike Run Club 的 `20.6` + `5'14"` 是同一形态）。
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(count)")
                        .font(AppFonts.largeTitle())
                        .foregroundColor(AppColors.textPrimary)
                    Text(VolunteerProfileCopy.heroUnit)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 主数字和它的说明是同一件事的两种说法，分开念会让读屏用户听两遍同一个数。
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerProfileCopy.heroSpoken(headline))
    }

    /// 3 列统计。**数值在上、小标签在下** —— 中文跑步产品（悦跑圈）是这个方向，
    /// 与 Strava 的标签在上正好相反，中文语境按中文的来（调研 §1.5 C1）。
    private func statsRow(
        _ summary: VolunteerHomeIncentiveSummary,
        achievements: VolunteerAchievementsResponse
    ) -> some View {
        let stats = VolunteerProfileStats.row(
            achievements: achievements,
            favoritedByCount: summary.favoritedByCount
        )
        return HStack(alignment: .top, spacing: 8) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(stat.value)
                            .font(AppFonts.title())
                            .foregroundColor(AppColors.textPrimary)
                        if let unit = stat.unit {
                            Text(unit)
                                .font(AppFonts.caption().weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }
                    Text(stat.caption)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(stat.spoken)
            }
        }
        .padding(.top, 13)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.textSecondary.opacity(0.18))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// 国标星级。门槛由 GB/T 40143—2021 定、不由我们定、也不随用户表现漂移 ——
    /// 这正是它能替代「本月 N/M 次」那种 Moving Target 的原因（调研 §4.2）。
    /// 文案整段复用成就页那一套，不新写第二份。
    private func starCard(_ level: VolunteerStarLevelDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    VolunteerAchievementsCopy.starTitle(current: max(0, level.current ?? 0)),
                    systemImage: "star.fill"
                )
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                Spacer(minLength: 8)
            }

            // 进度条对 VoiceOver 是空的，所以下面那行文字不是装饰 —— 它是这一栏
            // 唯一能被读出来的进度信息。两者顺序不能倒，也不能只留进度条。
            ProgressView(value: starProgress(level))
                .tint(AppColors.warning)
                .accessibilityHidden(true)

            Text(VolunteerAchievementsCopy.starProgressText(level))
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerAchievementsCopy.starAccessibilityLabel(level))
        .accessibilityIdentifier("volunteerProfileStarCard")
    }

    private func starProgress(_ level: VolunteerStarLevelDto) -> Double {
        guard let nextTarget = level.nextTarget, nextTarget > 0 else { return 1 }
        return min(1, Double(max(0, level.currentHours ?? 0)) / Double(nextTarget))
    }

    private func impactPlaceholder(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
            .accessibilityLabel("\(VolunteerProfileCopy.impactSectionTitle)。\(text)")
            .accessibilityIdentifier(identifier)
    }

    // MARK: - 徽章

    /// 一排 + 「全部 N 枚 ›」。徽章铺满首屏会变成一片图标噪音，前几枚的意义随之被稀释
    /// （Strava Overview 的 Trophies 行 + `View more`，调研 §1.2 S8）。
    @ViewBuilder
    private var badgesSection: some View {
        // 🔴 同 `impactSection`：读不到成就数据时**整块不画**，不要拿 `?? []` 顶上。
        // 空数组会渲染成「完成第一次陪跑就会解锁第一枚徽章。」—— 对一个已经解锁 7 枚的人
        // 那是一句假话，而失败信号已经由上面的影响力区给过了，这里再画一遍只会互相矛盾。
        if let achievements = incentive.summary?.achievements {
            let unlocked = achievements.unlockedBadges
            let cells = VolunteerProfileBadgeRow.cells(
                unlocked: unlocked,
                next: achievements.nextBadge
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    sectionLabel(VolunteerProfileCopy.badgesSectionTitle)
                    Spacer(minLength: 8)
                    // 🚩 这个链接必须在任何 `.combine` 的**外面**才点得到
                    // （同作业区那张培训卡为什么不套 `.combine` 的那条判据）。
                    NavigationLink {
                        VolunteerServiceRecognitionView()
                    } label: {
                        linkLabel(VolunteerProfileBadgeRow.allLinkTitle(unlockedCount: unlocked.count))
                    }
                    .accessibilityLabel(VolunteerHomeIncentiveCopy.achievementsLinkTitle)
                    .accessibilityHint(VolunteerProfileCopy.badgesLinkHint)
                    .accessibilityIdentifier("volunteerHomeIncentiveAchievementsLink")
                }

                if cells.isEmpty {
                    Text(VolunteerProfileCopy.badgesEmpty)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .top, spacing: 11) {
                        ForEach(cells) { cell in
                            badgeCell(cell)
                        }
                        // 不足四格时补空位，让每格宽度稳定 —— 否则两枚徽章会被拉成半屏宽。
                        if cells.count < VolunteerProfileBadgeRow.cellCount {
                            ForEach(cells.count..<VolunteerProfileBadgeRow.cellCount, id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func badgeCell(_ cell: VolunteerProfileBadgeRow.Cell) -> some View {
        switch cell {
        case .unlocked(let badge):
            badgeCellBody(
                symbol: badge.symbolName,
                caption: badge.displayName,
                isLocked: false,
                spoken: VolunteerAchievementsCopy.badgeAccessibilityLabel(badge)
            )

        case .next(let next):
            badgeCellBody(
                // 🔴 不写死一个图标。图标是这一栏**区分档位的非颜色手段**（WCAG 1.4.1），
                // 写死等于把它废掉 —— 无论下一枚是「陪跑 10 次」还是「高分好评」都画成同一个。
                // 查的是同一张 `code → SF Symbol` 表，未知 code 落 `rosette`。
                symbol: VolunteerBadgeSymbol.name(for: next.code),
                caption: VolunteerProfileBadgeRow.nextBadgeCaption(next),
                isLocked: true,
                spoken: VolunteerAchievementsCopy.nextBadgeAccessibilityLabel(next)
            )
        }
    }

    /// 图标 + 名称共同区分徽章，**颜色不是唯一指示**（WCAG 1.4.1）；
    /// 未解锁那一格用虚线圈，形状差异不依赖色觉。
    private func badgeCellBody(
        symbol: String,
        caption: String,
        isLocked: Bool,
        spoken: String
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if isLocked {
                    Circle()
                        .strokeBorder(
                            AppColors.textSecondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                } else {
                    Circle().fill(AppColors.secondaryBackground)
                }
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundColor(isLocked ? AppColors.textSecondary : AppColors.primary)
            }
            .frame(width: 48, height: 48)

            Text(caption)
                .font(AppFonts.caption())
                .foregroundColor(isLocked ? AppColors.textSecondary : AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    // MARK: - 最近陪跑

    /// 日期 + 一行主语 + 一行副信息，行高压得很紧，靠分隔线不靠卡片（调研 §2.5）。
    ///
    /// 数据用**已经在手的** `dispatchSummary.recentOrders`，不新开一条请求 ——
    /// 「全部 ›」进 `RunRecordHistoryView(role: .volunteer)`，那一页自己拉月度记录与 `GET /api/orders/mine`。
    @ViewBuilder
    private var recentSection: some View {
        let orders = viewModel.dispatchSummary?.recentOrders ?? []

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(VolunteerProfileCopy.recentSectionTitle)
                Spacer(minLength: 8)
                NavigationLink {
                    RunRecordHistoryView(role: .volunteer)
                } label: {
                    linkLabel(VolunteerProfileCopy.recentLinkTitle)
                }
                .accessibilityLabel("我的陪跑记录")
                .accessibilityHint(VolunteerProfileCopy.recentLinkHint)
                .accessibilityIdentifier("volunteerProfileRecentAllLink")
            }

            if orders.isEmpty {
                Text(VolunteerProfileCopy.recentEmpty)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(orders.prefix(3).enumerated()), id: \.element.id) { index, order in
                        NavigationLink {
                            VolunteerOrderDetailView(orderId: order.orderId)
                        } label: {
                            recentRow(order, showsDivider: index < min(orders.count, 3) - 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("点击查看订单详情")
                    }
                }
            }
        }
    }

    /// 🔴 **这一行不显示 `pointsText`，而改版前那张卡显示。这是必须的，不是漏了。**
    ///
    /// 积分与志愿服务时长**刻意分两屏**（中央网信办 2026-06-19 通知第 2 条，理由逐字在
    /// `VolunteerPoints.swift` 顶部与 `VolunteerHomeIncentiveSummary` 的注释里）。
    /// 改版前的首页**不显示累计时长**（时长只在成就页），所以那张卡上有积分是安全的；
    /// 而这一屏的 3 列统计第一格就是「陪伴时长 186 小时」——
    /// 再把积分放进同屏，两个数就会挨在一起，那正是两屏分法要防的事。
    ///
    /// 顺带一提 `pointsDelta` 后端至今没发过（恒 nil），所以删掉它在**今天**没有可见差异 ——
    /// 但别因此把它当无关紧要的顺手改动加回来：后端哪天真发了，加回来就是违规。
    private func recentRow(
        _ order: VolunteerDispatchSummaryRecentOrder,
        showsDivider: Bool
    ) -> some View {
        let date = VolunteerProfileRecentDate.parts(from: order.completedAt ?? order.plannedStartTime)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let date {
                    VStack(spacing: 2) {
                        Text(date.day)
                            .font(AppFonts.body().weight(.bold))
                            .foregroundColor(AppColors.textPrimary)
                        Text(date.month)
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(width: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(VolunteerProfileCopy.recentRowTitle(blindName: order.blindName))
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(order.startAddress?.nilIfBlank ?? "地点待同步") · \(order.status.displayName)")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)

            if showsDivider {
                Rectangle()
                    .fill(AppColors.textSecondary.opacity(0.14))
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                date.map { "\($0.month)\($0.day)日" },
                // 上面那行 `Text` 用原样（带星号），这一份是念出来的，去掉星号。
                VolunteerProfileCopy.recentRowTitle(blindName: order.blindName?.unmaskedForSpeech),
                "地点：\(order.startAddress ?? "")",
                "状态：\(order.status.displayName)"
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
    }

    // MARK: - 派单状态

    /// 派单摘要 + 定位摘要。**这一块刻意在最底部、刻意没有分区标题。**
    ///
    /// 它是调研 §1 三档分类里的第三档「普通信息卡片」（关注时可见），不该占中段。
    /// 真正可操作的那几条原因 —— 资质、培训、定位权限 —— 都在顶部的作业区里，
    /// 而当前状态文字在底部那条常驻 CTA 上也有一份，所以沉底不埋信息。
    ///
    /// > 2026-09-15 由二级页「派单工作台」整块搬过来（那一页已删）。摆在这个位置是为了
    /// > 将来「等待派单」页出来时搬走的代价最小：删 `body` 里的一行 +
    /// > 把 `VolunteerDispatchSummaryCard` 整个 struct 挪过去，上下两块不用动。
    @ViewBuilder
    private var dispatchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = viewModel.dispatchSummary {
                VolunteerDispatchSummaryCard(summary: summary)
            } else if viewModel.isLoading {
                EmptyStateView(
                    title: "派单状态待同步",
                    message: "正在后台同步；上面的记录、成就和设置仍可使用。"
                )
            } else {
                EmptyStateView(
                    title: "派单状态待同步",
                    message: locationService.isAuthorized ? "请重新加载。" : "开启定位后才能接收系统派单。"
                )
                // 🔴 **文案不许写成「下拉可以重新加载」**：下拉是手势，对读屏用户和手部不便的人
                // 不是一条可执行的指令，而这一刻屏幕上除此之外没有任何控件。
                // identifier 沿用随工作台删掉的那枚工具栏刷新按钮，守卫会顺带把用例钉住。
                Button("重新加载派单状态") {
                    locationService.requestOneTimeLocation()
                    Task { await onReload() }
                }
                .buttonStyle(.bordered)
                .accessibilityHint("重新获取当前位置并加载派单状态")
                .accessibilityIdentifier("volunteerHomeRefreshButton")
            }

            Text(locationSummaryText)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(locationSummaryText)

            #if DEBUG
            if let diagnostic = appState.realtimeCoordinator.dispatchDiagnostic {
                Text("派单诊断：\(diagnostic.debugSummary)")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .accessibilityLabel("派单诊断，\(diagnostic.debugSummary)")
                    .accessibilityIdentifier("volunteerDispatchDiagnostic")
            }
            DebugTestingPanel()
                .environmentObject(appState)
            #endif
        }
    }

    private var locationSummaryText: String {
        if locationService.isAuthorized {
            return "\(locationService.readableCurrentLocationSummary)\(viewModel.dispatchSummary?.coverageText ?? "派单覆盖范围待同步")"
        }
        return "需要开启定位权限才能接收系统派单"
    }

    // MARK: - 共用零件

    /// 分区标题：小号灰字 —— 中文运动 App 的通行写法（调研 §1.5 C2）。
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.caption().weight(.semibold))
            .foregroundColor(AppColors.textSecondary)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func linkLabel(_ text: String) -> some View {
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
