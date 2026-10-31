import SwiftUI

// 志愿者「我的」首屏底部的派单状态。主体与排序在 `VolunteerProfileFirstScreenView.swift`。

extension VolunteerProfileFirstScreen {
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
    var dispatchSection: some View {
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
                .buttonStyle(OutlineSecondaryButtonStyle())
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
}
