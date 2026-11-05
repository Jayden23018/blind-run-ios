import SwiftUI

// MARK: - 陪跑员「连续陪跑」跑步数据页

/// 首页「连续陪跑」卡点进来（负责人 2026-11-05 批准 v1，#710；定稿
/// `docs/ui/mockups/volunteer-run-data-20261105/run-data-final.png`）。
///
/// 照健康 App 卡片详情页的结构：先结论（和谁连续几周、本周记上没有），再图（陪跑日历、里程、陪伴时长），
/// 再提要（一句话 + 一个小图），最后个人纪录和固定搭档入口。只学版式，图标与颜色用自己的。
///
/// 🔴 只用现有契约（负责人定：这次不请后端加每次时长 / 配速），所以**没有**配速趋势与每周时长。
struct VolunteerRunDataView: View {
    let streak: VolunteerRunDataStreak
    let achievements: VolunteerAchievementsResponse
    let favoritedByCount: Int

    @EnvironmentObject private var appState: AppState
    @StateObject var model = VolunteerRunDataModel()
    @State var range: VolunteerRunDataSummary.MileageRange = .halfYear
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                streakCard
                switch model.phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityLabel(VolunteerRunDataCopy.loading)
                        .accessibilityIdentifier("volunteerRunData.loading")
                case .failed:
                    IncentiveFailureSection(
                        message: VolunteerRunDataCopy.allFailed,
                        retryTitle: VolunteerRunDataCopy.retry,
                        identifier: "volunteerRunData.retry"
                    ) {
                        Task { await model.retry(appState: appState) }
                    }
                case .loaded:
                    loadedContent
                }
                partnersLink
                VolunteerSecondaryFootnote(text: VolunteerRunDataCopy.ruleFootnote)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle(VolunteerRunDataCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页不挂标签栏（同固定搭档页、服务成就页）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerRunDataView")
        .task { await model.loadIfNeeded(appState: appState) }
    }

    var summary: VolunteerRunDataSummary { model.summary }
    var calendar: Calendar { model.calendar }

    @ViewBuilder
    private var loadedContent: some View {
        if !model.failedMonths.isEmpty {
            partialFailure
        }
        if summary.hasAnyRun {
            calendarCard
            VolunteerSecondarySectionTitle(title: VolunteerRunDataCopy.mileageSection)
            VolunteerRunDataRangePicker(selection: $range)
            mileageCard
            durationCard
            highlights
            if !summary.partners.isEmpty {
                partnersCard
            }
            recordsSection
        } else if model.pendingCount == 0, model.failedMonths.isEmpty {
            VolunteerSecondaryCard {
                Text(VolunteerRunDataCopy.empty)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("volunteerRunData.empty")
        }
    }

    private var partialFailure: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(VolunteerRunDataCopy.partialFailure(model.failedMonths.count))
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("volunteerRunData.partialFailure")
            Button(VolunteerRunDataCopy.retry) {
                Task { await model.retry(appState: appState) }
            }
            .buttonStyle(TextButtonStyle())
            .accessibilityIdentifier("volunteerRunData.retry")
        }
    }

    // MARK: 固定搭档入口

    private var partnersLink: some View {
        NavigationLink {
            VolunteerPartnersView()
        } label: {
            VolunteerSecondaryCard(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 14)) {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(AppColors.VolunteerHome.streakOrange)
                        .accessibilityHidden(true)
                    Text(VolunteerRunDataCopy.partnersLinkTitle)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer(minLength: 8)
                    Text(VolunteerRunDataCopy.partnersLinkValue(favoritedByCount))
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("\(VolunteerRunDataCopy.partnersLinkTitle)，\(VolunteerRunDataCopy.partnersLinkValue(favoritedByCount))")
        .accessibilityHint(VolunteerRunDataCopy.partnersLinkHint)
        .accessibilityIdentifier("volunteerRunData.partnersLink")
    }

}
