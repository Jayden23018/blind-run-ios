import SwiftUI

/// 志愿者服务成就页。**取代了此前的「积分商城」占位页**（那一页的理由与历史见
/// `VolunteerAchievementsViewModel` 顶部）。
///
/// 2026-11-04 照健康 · 步数详情重做（#697，稿子 `docs/ui/mockups/volunteer-secondary-pages-20261104/`）：
/// 陪伴时长大数字 + 近 6 个月柱状图 → 提要卡 → 累计里程 / 评分两张半宽卡（评分卡进评分页）
/// → 国标星级圆环 → 徽章块 → 关于。
///
/// 页面上的**每个数字都来自后端真有的字段**：`GET /api/volunteer/achievements` 与逐月的
/// `GET /api/orders/mine/run-records?month=`（`monthSummary.serviceMin`）。
///
/// 🔴 **国标星级与平台徽章分两块，不合并。** 平台最高的时长徽章是 50 小时，
/// 而国标一星要 100 小时（GB/T 40143—2021），理由见 `VolunteerStarLevel`。
///
/// 🔴 **不要挂标签栏**：2026-09-17 志愿者端加标签栏后，这一页的末行被盖掉半行、审计判对比度不足
/// （`testVolunteerAchievementsPassesAccessibilityAudit`），唯一的解法是二级页不要那条栏。
///
/// 并发只用 async/await：一个 `.task`，没有 `AnyCancellable`（AGENTS.md 硬约束）。
struct VolunteerServiceRecognitionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerAchievementsViewModel()
    @StateObject private var trend = VolunteerServiceTrendLoader()
    /// 无障碍字号档下两张半宽卡上下排（不用竖向 `ViewThatFits`，记忆里两处审计误报）。
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                if let achievements = viewModel.achievements {
                    content(achievements)
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载服务成就")
                } else {
                    errorSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 内层 `.infinity` 保留左对齐，外层把这条左对齐的列收进可读宽度并居中。
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle(VolunteerAchievementsCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerServiceRecognitionView")
        .task {
            viewModel.configure(appState: appState)
            // 两路互不依赖：成就是主体，月度是附加（拉不到只是不画图）。
            async let main: Void = viewModel.load()
            async let months: Void = trend.load(service: appState.runRecord)
            _ = await (main, months)
        }
    }

    @ViewBuilder
    private func content(_ achievements: VolunteerAchievementsResponse) -> some View {
        VolunteerServiceDurationCard(achievements: achievements, months: trend.months)

        if let months = trend.months {
            VolunteerServiceHighlightCard(months: months)
        }

        halfCards(achievements)

        VolunteerStarRingCard(level: achievements.resolvedStarLevel)

        badgeHeader(achievements)
        NavigationLink {
            VolunteerBadgeWallView(achievements: achievements)
        } label: {
            VolunteerBadgeSummaryCard(achievements: achievements)
        }
        .buttonStyle(.plain)
        .accessibilityHint(VolunteerSecondaryPagesCopy.badgeShowAllHint)

        VolunteerSecondarySectionTitle(title: VolunteerSecondaryPagesCopy.aboutTitle)
        VolunteerSecondaryCard {
            Text(VolunteerSecondaryPagesCopy.aboutText)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("volunteerAchievementsDisclaimer")
    }

    @ViewBuilder
    private func halfCards(_ achievements: VolunteerAchievementsResponse) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                mileageCard(achievements)
                ratingCard(achievements)
            }
        } else {
            HStack(alignment: .top, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                mileageCard(achievements)
                ratingCard(achievements)
            }
            // ScrollView 给的是不定高度，不固定的话两张卡各取自己的理想高度、底边一高一低。
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mileageCard(_ achievements: VolunteerAchievementsResponse) -> some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VolunteerSecondaryCardHeader(
                    title: VolunteerSecondaryPagesCopy.mileageTitle,
                    symbol: .route,
                    tint: VolunteerSecondaryTint.blue
                )
                VolunteerValueText(parts: [(
                    VolunteerSecondaryPagesCopy.kilometres(achievements.totalDistanceMeters),
                    VolunteerSecondaryPagesCopy.mileageUnit
                )])
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerSecondaryPagesCopy.mileageSpoken(achievements.totalDistanceMeters))
        .accessibilityIdentifier("volunteerAchievementsMileage")
    }

    /// 评分卡能点，进评分页（新页）。首页那张评分卡可点要等 #696 合并后另开小 PR。
    private func ratingCard(_ achievements: VolunteerAchievementsResponse) -> some View {
        NavigationLink {
            VolunteerRatingsView(achievements: achievements)
        } label: {
            VolunteerSecondaryCard {
                VStack(alignment: .leading, spacing: 10) {
                    VolunteerSecondaryCardHeader(
                        title: VolunteerSecondaryPagesCopy.ratingTitle,
                        symbol: .system("star.fill"),
                        tint: VolunteerSecondaryTint.rating,
                        showsChevron: true
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        VolunteerValueText(parts: [(VolunteerSecondaryPagesCopy.ratingValue(achievements.avgRating), "")])
                        Text(VolunteerSecondaryPagesCopy.ratingCaption(
                            average: achievements.avgRating,
                            total: achievements.totalRatings
                        ))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VolunteerSecondaryPagesCopy.ratingSpoken(
            average: achievements.avgRating,
            total: achievements.totalRatings
        ))
        .accessibilityHint(VolunteerSecondaryPagesCopy.ratingCardHint)
        .accessibilityIdentifier("volunteerAchievementsRatingCard")
    }

    /// 「徽章」+「全部显示」。全部显示**任何时候都能进**（改版前只在解锁 5 枚以上才出现，
    /// 于是解锁 ≤ 4 枚的人永远看不到没获得的那些）。
    private func badgeHeader(_ achievements: VolunteerAchievementsResponse) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VolunteerSecondarySectionTitle(title: VolunteerSecondaryPagesCopy.badgeSectionTitle)
            Spacer(minLength: 8)
            NavigationLink {
                VolunteerBadgeWallView(achievements: achievements)
            } label: {
                Text(VolunteerSecondaryPagesCopy.badgeShowAll)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.primary)
                    .frame(minHeight: 44)
            }
            .accessibilityHint(VolunteerSecondaryPagesCopy.badgeShowAllHint)
            .accessibilityIdentifier("volunteerBadgeWallLink")
        }
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.errorMessage ?? "服务成就加载失败。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button("重新加载") {
                Task { await viewModel.load() }
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityIdentifier("volunteerAchievementsRetryButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 徽章块

/// 成就页上的徽章块：顶上「下一枚」进度，下面已获得的几枚 + 「已获得 2 枚 / 共 7 枚」。
/// 整块一个焦点，点进徽章页。
private struct VolunteerBadgeSummaryCard: View {
    let achievements: VolunteerAchievementsResponse
    @ScaledMetric(relativeTo: .body) private var medalSize: CGFloat = 44

    private var items: [VolunteerBadgeItem] { VolunteerBadgeBoard.items(achievements) }
    private var earned: [VolunteerBadgeItem] { items.filter { $0.state.isEarned } }
    private var nextItem: VolunteerBadgeItem? {
        guard let code = achievements.nextBadge?.code else { return nil }
        return items.first { $0.id == code }
    }

    var body: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 14) {
                if let next = achievements.nextBadge {
                    nextRow(next)
                }
                if earned.isEmpty {
                    Text(VolunteerSecondaryPagesCopy.badgeEmpty)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 10) {
                        ForEach(earned.prefix(VolunteerBadgeWall.previewLimit)) { item in
                            VolunteerBadgeMedal(item: item, size: medalSize)
                        }
                        Text(VolunteerBadgeBoard.countText(items))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("volunteerNextBadgeSection")
    }

    private func nextRow(_ next: VolunteerNextBadgeDto) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let nextItem {
                VolunteerBadgeMedal(item: nextItem, size: medalSize)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(VolunteerSecondaryPagesCopy.nextBadgeCaption)
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                Text(nextTitle(next))
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = next.progressFraction {
                    VolunteerSecondaryProgressBar(fraction: fraction, tint: VolunteerSecondaryTint.blue)
                }
            }
        }
    }

    /// 「陪跑 10 次 · 7 / 10」。
    private func nextTitle(_ next: VolunteerNextBadgeDto) -> String {
        let name = VolunteerBadgeBoard.nextName(next)
        if case .inProgress(_, let short, _) = nextItem?.state {
            return "\(name) · \(short)"
        }
        return name
    }

    private var spoken: String {
        var parts = [VolunteerSecondaryPagesCopy.badgeSectionTitle]
        if let next = achievements.nextBadge {
            parts.append("\(VolunteerSecondaryPagesCopy.nextBadgeCaption)，\(VolunteerBadgeBoard.nextName(next))")
            if case .inProgress(_, _, let detail) = nextItem?.state { parts.append(detail) }
        }
        parts.append(earned.isEmpty ? VolunteerSecondaryPagesCopy.badgeEmpty : VolunteerBadgeBoard.countText(items))
        return parts.joined(separator: "，")
    }
}
