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
/// 并发只用 async/await：`.task` + 一个 `Task`，没有 `AnyCancellable`（AGENTS.md 硬约束）。
struct VolunteerPointsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var balance: Int64 = 0
    @State private var transactions: [PointTransactionResponse] = []
    @State private var nextPage = 0
    @State private var hasMore = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var hasLoadedOnce = false

    private static let pageSize = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if hasLoadedOnce {
                    IncentiveHeroCard(
                        value: "\(balance)",
                        caption: VolunteerPointsCopy.balanceCaption,
                        spokenLabel: VolunteerPointsCopy.balanceAccessibilityLabel(balance)
                    )
                    .accessibilityIdentifier("volunteerPointsBalance")

                    complianceCard
                    ledgerSection
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载积分")
                } else {
                    IncentiveFailureSection(
                        message: errorMessage ?? VolunteerPointsCopy.loadFailure,
                        retryTitle: VolunteerPointsCopy.retry,
                        identifier: "volunteerPointsRetryButton"
                    ) {
                        Task { await load(reset: true) }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(VolunteerPointsCopy.navigationTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerPointsView")
        .task {
            guard !hasLoadedOnce else { return }
            await load(reset: true)
        }
    }

    /// 两条合规文案。刻意放在余额**正下方**而不是页脚 —— 页脚的东西读屏用户要划到最后才听到，
    /// 而「这些分不能换钱」正是看到余额那一刻就该知道的事。
    private var complianceCard: some View {
        IncentiveCard {
            Text(VolunteerPointsCopy.disclaimer)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(VolunteerPointsCopy.separateFromServiceHours)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("volunteerPointsDisclaimer")
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(VolunteerPointsCopy.ledgerSectionTitle)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if transactions.isEmpty {
                Text(VolunteerPointsCopy.empty)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("volunteerPointsEmpty")
            } else {
                // 按天分节。分组只改视觉分节，不改顺序也不合并条目。
                ForEach(Array(PointTransactionGrouping.group(transactions).enumerated()), id: \.offset) { _, day in
                    IncentiveCard(title: day.title) {
                        ForEach(Array(day.transactions.enumerated()), id: \.offset) { index, transaction in
                            if index > 0 {
                                Divider()
                            }
                            row(transaction)
                        }
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
                    .accessibilityIdentifier("volunteerPointsLoadMoreButton")
                }
            }
        }
    }

    /// 一行流水。
    ///
    /// 🔴 `delta == 0` 的行**不过滤、不弱化**：它是「我这单怎么没加分」的唯一答案。
    /// 视觉上靠图标 + 语义色区分（颜色不是唯一指示，WCAG 1.4.1），
    /// 而 `note` 用主文本色渲染 —— 它是这一行真正要读的内容，不是脚注。
    private func row(_ transaction: PointTransactionResponse) -> some View {
        AdaptiveHStack(spacing: 12) {
            Image(systemName: symbolName(for: transaction.kind))
                .font(.body.weight(.semibold))
                .foregroundColor(color(for: transaction.kind))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note?.nilIfBlank ?? transaction.reasonText)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if transaction.note?.nilIfBlank != nil {
                    Text(transaction.reasonText)
                        .font(AppFonts.caption())
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
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transaction.accessibilityLabel)
    }

    private func symbolName(for kind: PointTransactionResponse.Kind) -> String {
        switch kind {
        case .credited: return "plus.circle"
        case .noChange: return "exclamationmark.circle"
        case .deducted: return "minus.circle"
        }
    }

    private func color(for kind: PointTransactionResponse.Kind) -> Color {
        switch kind {
        case .credited: return AppColors.success
        case .noChange: return AppColors.warning
        case .deducted: return AppColors.destructive
        }
    }

    private func load(reset: Bool) async {
        if reset {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        let page = reset ? 0 : nextPage
        do {
            let response: VolunteerPointsResponse = try await appState.apiClient.get(
                "/api/volunteer/points",
                query: ["page": "\(page)", "size": "\(Self.pageSize)"]
            )
            balance = response.resolvedBalance
            if reset {
                transactions = response.resolvedTransactions
            } else {
                transactions += response.resolvedTransactions
            }
            nextPage = page + 1
            hasMore = response.hasMorePages
            errorMessage = nil
            hasLoadedOnce = true
        } catch let error as APIError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = VolunteerPointsCopy.loadFailure
        }
    }
}
