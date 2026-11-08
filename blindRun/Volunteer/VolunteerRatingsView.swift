import SwiftUI

/// 评分页（#697 新页，照健康 · 睡眠评分：一个分数 + 一句话说怎么算）。
///
/// 只显示陪跑员看得到的东西：`avgRating` / `totalRatings`（成就页传进来）与
/// `GET /api/volunteer/dispatch-summary` 里每单的 `rating`。
///
/// 🔴 **不画**：评分分布、评价标签、评语原文。评语对陪跑员永久扣留（`commentWithheld`），
/// 契约里也没有分布与标签 —— 画出来就是编的。
struct VolunteerRatingsView: View {
    let achievements: VolunteerAchievementsResponse

    @EnvironmentObject private var appState: AppState
    /// 「最近的评价」那一节的加载状态（#865）。平均分与高分徽章来自上一页带进来的成就，不在这里。
    @State private var recentState: AsyncLoadState<[VolunteerDispatchSummaryRecentOrder]> = .idle

    static let recentLoadFailure = "最近的评价加载失败，请稍后重试。"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                VolunteerRatingAverageCard(average: achievements.avgRating, total: achievements.totalRatings)
                highRatedCard
                VolunteerSecondarySectionTitle(title: VolunteerSecondaryPagesCopy.recentTitle)
                recentSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle(VolunteerSecondaryPagesCopy.ratingsNavigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerRatingsView")
        .task {
            guard recentState.value == nil else { return }
            await loadRecent()
        }
    }

    private var highRatedCard: some View {
        let item = VolunteerBadgeBoard.items(achievements).first { $0.id == VolunteerBadgeCatalog.highRatedCode }
        let status = VolunteerSecondaryPagesCopy.highRatedStatus(achievements)
        return VolunteerSecondaryCard {
            HStack(spacing: 14) {
                if let item {
                    VolunteerBadgeMedal(item: item, size: 52)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(VolunteerSecondaryPagesCopy.highRatedTitle)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(VolunteerSecondaryPagesCopy.highRatedTitle)，\(status)")
        .accessibilityIdentifier("volunteerRatingsHighRated")
    }

    private var recentSection: some View {
        RemoteContent(
            recentState,
            loadingLabel: "正在加载最近的评价",
            failureIdentifier: "volunteerRatingsRetryButton",
            retryTitle: "重新加载",
            retry: { Task { await loadRecent() } }
        ) { recentOrders in
            recentList(recentOrders.filter { $0.status == .completed })
        }
    }

    @ViewBuilder
    private func recentList(_ orders: [VolunteerDispatchSummaryRecentOrder]) -> some View {
        if orders.isEmpty {
            VolunteerSecondaryFootnote(text: VolunteerSecondaryPagesCopy.recentEmpty)
        } else {
            VolunteerSecondaryCard(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12)) {
                VStack(spacing: 0) {
                    ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                        NavigationLink {
                            VolunteerRunRecordView(orderId: order.orderId)
                        } label: {
                            VolunteerRatingRow(order: order)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(VolunteerSecondaryPagesCopy.recentRowSpoken(
                            date: VolunteerSecondaryPagesCopy.recentDate(order),
                            blindName: order.blindName,
                            address: order.startAddress,
                            level: VolunteerRatingLevel(rating: order.rating)
                        ))
                        .accessibilityHint(VolunteerSecondaryPagesCopy.recentRowHint)
                        .accessibilityIdentifier("volunteerRatingRow.\(order.orderId)")
                        if index < orders.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            VolunteerSecondaryFootnote(text: VolunteerSecondaryPagesCopy.recentFootnote)
        }
    }

    private func loadRecent() async {
        recentState = .loading(requestID: UUID())
        do {
            recentState = .loaded(try await appState.orders.dispatchSummary().recentOrders ?? [])
        } catch {
            recentState = .failed(message: Self.recentLoadFailure)
        }
    }
}

// MARK: - 平均分卡

private struct VolunteerRatingAverageCard: View {
    let average: Double?
    let total: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VolunteerSecondaryCardHeader(
                    title: VolunteerSecondaryPagesCopy.averageTitle,
                    symbol: .system("star.fill"),
                    tint: VolunteerSecondaryTint.rating,
                    meta: average == nil ? nil : VolunteerSecondaryPagesCopy.ratingCaption(average: average, total: total)
                )
                // 大字号下分数和五颗星上下排：并排时星星宽度不变，会把分数挤没（AX5 实测）。
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        score
                        if let average { stars(average) }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        score
                        Spacer(minLength: 8)
                        if let average { stars(average) }
                    }
                }
                Text(average == nil ? "还没有收到评价。\(VolunteerSecondaryPagesCopy.ratingRule)" : VolunteerSecondaryPagesCopy.ratingRule)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerSecondaryPagesCopy.ratingsSpoken(average: average, total: total))
        .accessibilityIdentifier("volunteerRatingsAverage")
    }

    private var score: some View {
        VolunteerValueText(
            parts: [(VolunteerSecondaryPagesCopy.ratingValue(average), VolunteerSecondaryPagesCopy.ratingScale)],
            size: .hero
        )
        .layoutPriority(1)
    }

    /// 五颗星，按平均分四舍五入点亮。纯视觉，分数由上面的数字和读屏那句说。
    private func stars(_ average: Double) -> some View {
        let lit = Int(average.rounded())
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < lit ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundColor(VolunteerSecondaryTint.rating)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 最近的评价一行

/// 日期、「和李* · 地点」、右边等宽的档位标签（很好 / 一般 / 无评分）。
///
/// 标签等宽对齐（负责人 2026-11-04 要求）：每个标签都按最长那档的宽度占位，
/// 不用固定磅值 —— 大字号下固定宽度会截字。
private struct VolunteerRatingRow: View {
    let order: VolunteerDispatchSummaryRecentOrder

    private var level: VolunteerRatingLevel { VolunteerRatingLevel(rating: order.rating) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let date = VolunteerSecondaryPagesCopy.recentDate(order) {
                    Text(date)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                }
                Text(VolunteerSecondaryPagesCopy.recentRowDetail(blindName: order.blindName, address: order.startAddress))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VolunteerRatingTag(level: level)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// 档位标签。三档用同一个宽度：把最长的那个字串叠在底下当隐形尺子，可见的那个居中。
struct VolunteerRatingTag: View {
    let level: VolunteerRatingLevel

    private var colors: (fill: Color, ink: Color) {
        switch level {
        case .good: return (AppColors.Flow.acceptingBackground, AppColors.Flow.acceptingText)
        case .ok: return (AppColors.Flow.warmCard, AppColors.Flow.warmCardTitle)
        case .none, .score: return (AppColors.Flow.surfaceSubtle, AppColors.textSecondary)
        }
    }

    var body: some View {
        ZStack {
            // 隐形尺子：三档里最宽的是「无评分」。
            Text(VolunteerRatingLevel.none.label).hidden()
            Text(level.label)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(colors.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(colors.fill))
        .accessibilityHidden(true)
    }
}
