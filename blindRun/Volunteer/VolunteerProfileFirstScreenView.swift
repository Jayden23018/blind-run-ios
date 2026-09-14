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
                workbenchRow
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
            || viewModel.needsCertificateUpload
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
                    .accessibilityLabel("当前订单：\(activeOrder.status.displayName)，盲人 \(activeOrder.blindName ?? "")，地点 \(activeOrder.startAddress ?? "")")
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
                // 不留一行没有去处的说明（`VolunteerDispatchSummaryCard.trainingEntry` 同一条判据）。
                if let acceptBlockMessage = viewModel.acceptBlockMessage {
                    Text(acceptBlockMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(acceptBlockMessage)
                }

                if viewModel.needsCertificateUpload {
                    VolunteerCertificateUploadEntryLink()
                }

                if let warning = viewModel.locationDispatchWarning {
                    Label(warning, systemImage: "location.slash.fill")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(warning)
                        .accessibilityHint("请检查定位权限，并等待设备获取当前位置")
                        .accessibilityIdentifier("volunteerDispatchLocationWarning")
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

            if let summary = incentive.summary {
                impactContent(summary)
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

    @ViewBuilder
    private func impactContent(_ summary: VolunteerHomeIncentiveSummary) -> some View {
        let headline = VolunteerProfileHeadline.resolve(
            totalCompleted: summary.achievements?.totalCompleted
        )

        VStack(alignment: .leading, spacing: 14) {
            hero(headline)

            if headline.showsImpactSections {
                statsRow(summary)
            }

            if let streak = summary.streak {
                StreakStrip(
                    partnerName: summary.streakPartnerName?.nilIfBlank
                        ?? PartnerStreakCopy.unknownBlindName,
                    streak: streak
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("volunteerHomeIncentiveCard")

        if headline.showsImpactSections, let level = summary.achievements?.resolvedStarLevel {
            starCard(level)
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
    private func statsRow(_ summary: VolunteerHomeIncentiveSummary) -> some View {
        let stats = VolunteerProfileStats.row(
            achievements: summary.achievements,
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
        let unlocked = incentive.summary?.achievements?.unlockedBadges ?? []
        let next = incentive.summary?.nextBadge
        let cells = VolunteerProfileBadgeRow.cells(unlocked: unlocked, next: next)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(VolunteerProfileCopy.badgesSectionTitle)
                Spacer(minLength: 8)
                // 🚩 这个链接必须在任何 `.combine` 的**外面**才点得到
                // （同 `VolunteerDispatchSummaryCard` 的「去培训」踩过的那个坑）。
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
                symbol: "moon.stars",
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
    /// 「全部 ›」进 `VolunteerServiceRecordsView`，那一页自己会拉完整的 `GET /api/orders/mine`。
    @ViewBuilder
    private var recentSection: some View {
        let orders = viewModel.dispatchSummary?.recentOrders ?? []

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(VolunteerProfileCopy.recentSectionTitle)
                Spacer(minLength: 8)
                NavigationLink {
                    VolunteerServiceRecordsView()
                } label: {
                    linkLabel(VolunteerProfileCopy.recentLinkTitle)
                }
                .accessibilityLabel("我的服务记录")
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
                VolunteerProfileCopy.recentRowTitle(blindName: order.blindName),
                "地点：\(order.startAddress ?? "")",
                "状态：\(order.status.displayName)"
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
    }

    // MARK: - 派单工作台入口

    /// 地图、覆盖范围、派单统计和必修培训都在这后面。
    ///
    /// 这一行**永远显示**（不跟 `dispatchSummary` 走）：派单摘要拉失败时正是最需要
    /// 让人点进去看一眼的时候，而那一页里有重试和「去培训」。
    private var workbenchRow: some View {
        NavigationLink {
            VolunteerDispatchWorkbenchView(viewModel: viewModel, onReload: onReload)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(viewModel.statusColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(VolunteerProfileCopy.workbenchTitle)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(viewModel.statusText)
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
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(VolunteerProfileCopy.workbenchTitle)，\(viewModel.statusText)")
        .accessibilityHint(VolunteerProfileCopy.workbenchHint)
        .accessibilityIdentifier("volunteerProfileWorkbenchEntry")
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
