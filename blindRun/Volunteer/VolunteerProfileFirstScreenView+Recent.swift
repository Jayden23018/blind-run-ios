import SwiftUI

// 志愿者首页的最近陪跑卡。主体与排序在 `VolunteerProfileFirstScreenView.swift`，取值在 `VolunteerHomeSummaryCards.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 最近陪跑

    /// 一张卡：公里数 + 「和王* · 地点」+ 右侧路线缩略图（#694 v3）。
    ///
    /// 数据走 `GET /api/orders/mine/run-records`（「记录」标签页同一个接口），
    /// 不再用 `dispatchSummary.recentOrders`：那份没有公里数和路线。
    @ViewBuilder
    var recentSection: some View {
        sectionHeader(VolunteerProfileCopy.recentSectionTitle) {
            NavigationLink {
                RunRecordHistoryView(role: .volunteer)
            } label: {
                linkLabel(VolunteerProfileCopy.recentLinkTitle)
            }
            .accessibilityLabel("我的陪跑记录")
            .accessibilityHint(VolunteerProfileCopy.recentLinkHint)
            .accessibilityIdentifier("volunteerProfileRecentAllLink")
        }

        switch recentRun.state {
        case .loaded(let content?):
            NavigationLink {
                VolunteerRunRecordView(orderId: content.orderId)
            } label: {
                recentCard(content)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(content.spoken)
            .accessibilityHint(VolunteerProfileCopy.recentCardHint)
            .accessibilityIdentifier("volunteerProfileRecentRunCard")

        case .loaded(nil):
            recentMessage(
                // 跑过的人两个月没跑：不说「完成陪跑后会显示在这里」，那句是对新人说的。
                hasCompletedRuns ? VolunteerProfileCopy.recentNoneLately : VolunteerProfileCopy.recentEmpty,
                identifier: "volunteerProfileRecentEmpty"
            )

        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                recentMessage(VolunteerProfileCopy.recentLoadFailure, identifier: "volunteerProfileRecentFailure")
                Button(VolunteerProfileCopy.recentRetry) {
                    Task { await recentRun.load(appState: appState) }
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("volunteerProfileRecentRetryButton")
            }

        case .loading:
            recentMessage(VolunteerHomeIncentiveCopy.loading, identifier: "volunteerProfileRecentLoading")
        }
    }

    /// 成就数据说跑过至少一次。拿不到成就数据时按「没跑过」处理 —— 那只影响空态的措辞，两句都是真话。
    private var hasCompletedRuns: Bool {
        (incentive.summary?.achievements?.totalCompleted ?? 0) > 0
    }

    private func recentCard(_ content: VolunteerHomeRecentRunContent) -> some View {
        VolunteerHomeCard {
            VStack(alignment: .leading, spacing: 12) {
                VolunteerHomeCardHeader(
                    title: VolunteerProfileCopy.recentCardTitle,
                    symbol: "figure.run",
                    tint: AppColors.primary,
                    meta: content.dateText,
                    showsChevron: true
                )
                // 无障碍字号下路线图挪到文字下面：并排时它会把公里数挤成一列一个字。
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        recentTexts(content)
                        recentRoute(content.route)
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        recentTexts(content)
                        Spacer(minLength: 0)
                        recentRoute(content.route)
                    }
                }
            }
        }
    }

    private func recentTexts(_ content: VolunteerHomeRecentRunContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let distance = content.distanceText {
                (Text(distance).font(AppFonts.largeTitle())
                    + Text(" 公里").font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textSecondary))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = content.detailText {
                Text(detail)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 🔴 **画不出路线就什么都不画**（#694）：不画占位图标。`route` 为 nil 的判据在
    /// `VolunteerHomeRecentRunContent`（空、null、点全部重合）。记录页那一行的跑步图标是另一回事 ——
    /// 列表里每行左侧要对齐，这张卡没有这个约束。
    @ViewBuilder
    private func recentRoute(_ route: [RunLatLng]?) -> some View {
        if let route {
            RunRouteThumbnail(points: route)
                .frame(width: 92, height: 52)
                .accessibilityHidden(true)
        }
    }

    private func recentMessage(_ text: String, identifier: String) -> some View {
        VolunteerHomeCard {
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(VolunteerProfileCopy.recentSectionTitle)。\(text)")
        .accessibilityIdentifier(identifier)
    }
}
