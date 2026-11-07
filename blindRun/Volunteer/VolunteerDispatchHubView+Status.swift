import SwiftUI

// 接单页最上面的状态卡与分区标题。主体与排序在 `VolunteerDispatchHubView.swift`。
// 拆出来是为了不让主文件超过 SwiftLint 的长度上限（陪跑员首页 v3，#694）。

extension VolunteerDispatchHubView {
    // MARK: 状态卡

    /// 最上面那张：此刻在不在接单、派单状态与覆盖范围、定位摘要。
    ///
    /// 🚩 改版前首页底部的派单状态框（`dispatchSection`）整块搬到这里（#694）——
    /// 首页不再出现任何接单状态文字。identifier 沿用：`volunteerDispatchHubAcceptingPill`
    /// （十几条用例拿它判「进了接单页」）、`volunteerDispatchSummaryCard`、`volunteerHomeRefreshButton`。
    var statusCard: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 8) {
                statusHeadline

                if let summary = viewModel.dispatchSummary {
                    VolunteerDispatchSummaryCard(summary: summary)
                } else {
                    Text(viewModel.isLoading
                        ? VolunteerDispatchHubCopy.statusLoadingMessage
                        : VolunteerDispatchHubCopy.statusPendingTitle)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !viewModel.isLoading {
                        // 🔴 **文案不许写成「下拉可以重新加载」**：下拉是手势，对读屏用户和手部不便的人
                        // 不是一条可执行的指令。
                        Button(VolunteerDispatchHubCopy.reloadTitle) {
                            locationService.requestOneTimeLocation()
                            Task { await onReload() }
                        }
                        .buttonStyle(OutlineSecondaryButtonStyle())
                        .accessibilityHint("重新获取当前位置并加载派单状态")
                        .accessibilityIdentifier("volunteerHomeRefreshButton")
                    }
                }

                Text(locationSummaryText)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusHeadline: some View {
        let accepting = viewModel.availabilityStatus.isAccepting
        let color = accepting ? AppColors.Flow.acceptingText : AppColors.textPrimary
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(viewModel.availabilityStatus.hubPillTitle)
                .font(AppFonts.title())
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        // 附上 view model 那半句（「正在等待系统派单」/「不在空闲时间内」）才说得完整。
        .accessibilityLabel("\(viewModel.availabilityStatus.hubPillTitle)，\(viewModel.statusText)")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("volunteerDispatchHubAcceptingPill")
    }

    private var locationSummaryText: String {
        if locationService.isAuthorized {
            return locationService.readableCurrentLocationSummary
        }
        return "需要开启定位权限才能接收系统派单"
    }

    #if DEBUG
    @ViewBuilder
    var debugSection: some View {
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
    }
    #endif

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.title())
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
            .padding(.top, 10)
    }
}
