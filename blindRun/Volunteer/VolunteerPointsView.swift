import SwiftUI

// MARK: - 志愿者积分页

/// `GET /api/volunteer/points`（SPEC-E 第 1 步）。
///
/// 🔴 **为什么它是独立一屏，而不是塞进「服务成就」页的一个 section**：
/// 积分与「志愿服务时长」必须是两个数、两处文案，一次都不能混
/// （中央网信办 2026-06-19 通知第 2 条点名整治「宣传可以获得志愿服务时长」）。
/// 放同一屏最容易混，所以在**信息架构层**就隔开 —— 比靠文案自律可靠。
/// 两屏之间用一句话互相指路（`separateFromServiceHours`）。
///
/// 版式是负责人 2026-11-04 批准的定稿（#700，`docs/ui/mockups/volunteer-account-pages-20261104/`）：
/// 余额卡 →「最新记录」一张卡 → 页脚合规文案。
///
/// 并发只用 async/await：`.task` + 一个 `Task`，没有 `AnyCancellable`（AGENTS.md 硬约束）。
struct VolunteerPointsView: View {
    @EnvironmentObject private var appState: AppState

    /// 首屏一次加载的状态（#865）。翻页不改它的档位：翻页途中、翻页失败都保持 `.loaded`。
    @State private var pageState: AsyncLoadState<VolunteerPointsPage> = .idle
    /// 「查看更早的记录」的按钮忙碌态，不是页面加载态。
    @State private var isLoadingMore = false

    private static let pageSize = 20

    private var balance: Int64 { pageState.value?.balance ?? 0 }
    private var transactions: [PointTransactionResponse] { pageState.value?.transactions ?? [] }
    private var hasMore: Bool { pageState.value?.hasMore ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteContent(
                    pageState,
                    loadingLabel: "正在加载积分",
                    failureIdentifier: "volunteerPointsRetryButton",
                    retryTitle: VolunteerPointsCopy.retry,
                    retry: { Task { await load(reset: true) } }
                ) { _ in
                    balanceCard
                    ledgerSection
                    complianceFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(VolunteerPointsCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        // 二级页藏标签栏：悬浮的栏会盖住页脚最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerPointsView")
        .task {
            guard pageState.value == nil else { return }
            await load(reset: true)
        }
    }

    /// 余额卡（定稿照 Apple Cash：大数字在上）。
    ///
    /// 大数字用 `.largeTitle`（34pt）而不是稿子的 52pt：没有默认档等于 52 的系统文字样式，
    /// 指定磅值的字真机审计判「改不了字号」（记忆 `scaledmetric-system-size-fails-dynamic-type-audit`）。
    private var balanceCard: some View {
        let summary = PointMonthlySummary.make(transactions: transactions, hasMorePages: hasMore)
        var spoken = VolunteerPointsCopy.balanceAccessibilityLabel(balance)
        if let summary { spoken += "。\(summary.spokenText)" }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .accessibilityHidden(true)
                Text(VolunteerPointsCopy.balanceCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppColors.Flow.replyUrgentText)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(balance)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                Text("分")
                    .font(.headline)
                    .foregroundColor(AppColors.textSecondary)
            }

            if let summary {
                Text(summary.text)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("volunteerPointsBalance")
    }

    /// 两条合规文案，原文放页脚（定稿：规则不占首屏，但这一页一定看得到）。
    ///
    /// 🔴 文案一个字不改（中央网信办 2026-06-19 通知）。读屏顺序上它在最后 ——
    /// 但余额卡上没有任何「能换钱」的暗示，所以先听到余额不会误导。
    private var complianceFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(VolunteerPointsCopy.disclaimer)
                .fixedSize(horizontal: false, vertical: true)
            Text(VolunteerPointsCopy.separateFromServiceHours)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundColor(AppColors.textSecondary)
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("volunteerPointsDisclaimer")
    }

    @ViewBuilder
    private var ledgerSection: some View {
        if transactions.isEmpty {
            VStack(spacing: 6) {
                Text(VolunteerPointsCopy.emptyTitle)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Text(VolunteerPointsCopy.emptyDetail)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(AppColors.Flow.surface)
            .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("volunteerPointsEmpty")
        } else {
            VolunteerSecondarySectionTitle(title: VolunteerPointsCopy.ledgerSectionTitle)

            // 后端按时间倒序，原样一行一条，不合并、不过滤。
            GroupedCard {
                ForEach(Array(transactions.enumerated()), id: \.offset) { index, transaction in
                    if index > 0 {
                        GroupedCardDivider(leadingInset: Self.rowDividerInset)
                    }
                    row(transaction)
                }
            }

            if hasMore {
                Button(isLoadingMore ? "正在加载…" : "查看更早的记录") {
                    Task { await load(reset: false) }
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                .disabled(isLoadingMore)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("volunteerPointsLoadMoreButton")
            }
        }
    }

    private static let rowIconWidth: CGFloat = 28
    private static let rowIconSpacing: CGFloat = 12
    /// 分隔线从文字起点开始：行内距 + 图标宽 + 图标到文字的间距。
    private static let rowDividerInset = GroupedCardMetrics.rowHorizontalPadding + rowIconWidth + rowIconSpacing

    /// 一行流水：左图标、中间原因与日期、右边加减分（定稿照健康「所有已记录的数据」）。
    ///
    /// 🔴 `delta == 0` 的行**不过滤、不弱化**：它是「我这单怎么没加分」的唯一答案。
    /// 视觉上靠图标 + 语义色区分（颜色不是唯一指示，WCAG 1.4.1），
    /// 有 `note` 时它是这一行的标题 —— 它是这一行真正要读的内容，不是脚注。
    private func row(_ transaction: PointTransactionResponse) -> some View {
        let note = transaction.note?.nilIfBlank
        let subtitle = [note == nil ? nil : transaction.reasonText, transaction.dayText()]
            .compactMap { $0 }
            .joined(separator: " · ")
        return AdaptiveHStack(spacing: Self.rowIconSpacing) {
            Image(systemName: symbolName(for: transaction.kind))
                .font(.title2)
                .foregroundColor(color(for: transaction.kind))
                .frame(width: Self.rowIconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(note ?? transaction.reasonText)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(transaction.deltaText)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(color(for: transaction.kind))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: GroupedCardMetrics.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transaction.accessibilityLabel)
    }

    private func symbolName(for kind: PointTransactionResponse.Kind) -> String {
        switch kind {
        case .credited: return "plus.circle.fill"
        case .noChange: return "exclamationmark.circle.fill"
        case .deducted: return "minus.circle.fill"
        }
    }

    private func color(for kind: PointTransactionResponse.Kind) -> Color {
        switch kind {
        case .credited: return AppColors.success
        case .noChange: return AppColors.warning
        case .deducted: return AppColors.destructive
        }
    }

    /// 翻页失败保留已显示的记录，只有首屏没读到才是 `.failed`（规则同 `RemoteContent` 顶部那条）。
    private func load(reset: Bool) async {
        let shown = pageState.value
        if reset {
            pageState = .loading(requestID: UUID())
        } else {
            isLoadingMore = true
        }
        defer { isLoadingMore = false }

        let page = reset ? 0 : (shown?.nextPage ?? 0)
        do {
            let response = try await appState.incentive.volunteerPoints(
                page: page,
                size: Self.pageSize
            )
            let earlier = reset ? [] : (shown?.transactions ?? [])
            pageState = .loaded(VolunteerPointsPage(
                balance: response.resolvedBalance,
                transactions: earlier + response.resolvedTransactions,
                nextPage: page + 1,
                hasMore: response.hasMorePages
            ))
        } catch {
            guard reset || shown == nil else { return }
            pageState = .failed(message: (error as? APIError)?.localizedMessage ?? VolunteerPointsCopy.loadFailure)
        }
    }
}

/// 积分页已经读到的内容：余额与已经翻到的那几页记录。
struct VolunteerPointsPage {
    let balance: Int64
    let transactions: [PointTransactionResponse]
    let nextPage: Int
    let hasMore: Bool
}
