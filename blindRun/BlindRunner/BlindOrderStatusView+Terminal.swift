import SwiftUI

// MARK: - 终态页（已取消 / 暂无志愿者）

extension RunOrderStatus {
    /// 这一态走订单页骨架的终态页（头卡 + 信息卡 + 底栏），而不是改版前那条只读列表（#818）。
    ///
    /// 穷举 switch 而不是集合字面量：后端加状态时编译器逼一次决策，同 `blindOrderFlowStep`。
    /// `.unknown` **不在内** —— 它是后端加状态时唯一的只读落点（`trackingContent`），不许改。
    /// `.completed` 走四步骨架的第四幕，不走这里。
    var usesBlindTerminalPage: Bool {
        switch self {
        case .cancelled, .noVolunteer:
            return true
        case .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .inProgress,
             .driverEnRoute, .driverArrived, .completed, .rematching, .unknown:
            return false
        }
    }
}

extension BlindOrderStatusView {
    /// 已取消 / 暂无志愿者的终态页。导航栏与底栏要和骨架一起判，同一个谓词。
    /// 放在这个文件而不是 `BlindOrderStatusView.swift` 里：那个文件已超长，行数棘轮不许再变大。
    var usesTerminalPage: Bool {
        viewModel.order?.status.usesBlindTerminalPage == true
    }

    /// 骨架或终态页：标题叫「陪跑订单」、右上角有「重复当前状态」、不挂旧的「问一句」底栏。
    var usesFlowChrome: Bool {
        usesFlowSkeleton || usesTerminalPage
    }

    /// 已取消 / 暂无志愿者。版式与订单页其他状态同一套：灰头卡、白色信息卡、底栏只有一个主按钮。
    ///
    /// 🔴 **没有「求助与安全」**：求助只在 `IN_PROGRESS` 开放（`AGENTS.md` §6）。
    /// 🔴 **没有「问一句」**：它在骨架态住在求助中心里，终态没有求助中心；「重复当前状态」仍在导航栏右侧。
    /// 🔴 **不自动离开页面**：取消成功必须让人听到、看到，并自己决定何时返回首页。
    ///
    /// 改版前那条列表上的东西一件没删：失败提示、Mock 调试区在 footer（对方安全入口 2026-11-11 起在导航栏「···」），
    /// 预约信息与状态变更记录是信息卡里的两行折叠。
    @ViewBuilder
    func terminalContent(_ order: OrderDetailResponse) -> some View {
        OrderFlowScaffold(
            bottom: OrderFlowBottomActions(
                owner: .blindRunner,
                primary: OrderFlowPrimaryAction(
                    title: "返回首页",
                    accessibilityHint: "点击后返回盲人首页",
                    action: { dismiss() }
                ),
                safetyHub: nil
            )
        ) {
            terminalHero(order)
            terminalInfoCard(order)
            VStack(spacing: 16) {
                flowFooter(order)
                CounterpartBlockOutcome(viewModel: counterpartSafety)
                debugMockControls(order)
            }
        }
    }

    private func terminalHero(_ order: OrderDetailResponse) -> some View {
        let status = order.status
        return FlowHeroCard(style: .tinted(AppColors.Flow.statePaused)) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: status == .noVolunteer ? "person.slash" : "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(AppColors.Flow.onHeroStrong)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.2)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(status.displayName)
                        .flowFont(FlowV2Fonts.title())
                        .foregroundColor(AppColors.Flow.onHeroStrong)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status.blindRunnerDescription)
                        .flowFont(FlowV2Fonts.callout())
                        .foregroundColor(AppColors.Flow.onHeroBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 正文合成一个读屏元素，念法写死，不交给 `.combine` 自己拼（同 `statusHeader`）。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(status.displayName)。\(status.blindRunnerDescription)")
            .accessibilityIdentifier("blindOrderFlowStatusCard")
            .accessibilityFocused($statusHeaderFocused)
        }
    }

    private func terminalInfoCard(_ order: OrderDetailResponse) -> some View {
        let timeText = order.blindRunnerShortStartText() ?? "待确认"
        let spokenTime = order.plannedStartForAnnouncement ?? timeText
        let placeText = order.startAddress?.nilIfBlank ?? "出发地点待确认"
        return FlowCard {
            VStack(spacing: 0) {
                FlowInfoRow(label: "时间", accessibilityLabel: "时间，\(spokenTime)") {
                    Text(timeText)
                        .flowFont(FlowFonts.rowValue(), monospacedDigit: true)
                        .foregroundColor(AppColors.Flow.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                FlowSeparator()
                FlowInfoRow(label: "集合地点", accessibilityLabel: "集合地点，\(placeText)") {
                    Text(placeText)
                        .flowFont(FlowFonts.rowValue())
                        .foregroundColor(AppColors.Flow.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.trailing)
                }
                FlowSeparator()
                terminalDisclosure(
                    title: "预约信息",
                    hint: "展开后可以听到预约时间、出发地点等已确认的信息",
                    isExpanded: nil
                ) {
                    orderInfoRows(order)
                }
                FlowSeparator()
                terminalDisclosure(
                    title: "状态变更记录",
                    hint: "展开后可以听到此订单每一次状态变化和发生时间",
                    isExpanded: $showStatusLogs
                ) {
                    statusLogContent
                }
                .accessibilityIdentifier("blindOrderStatusLogsDisclosure")
            }
        }
    }

    /// 信息卡里的折叠行。内容沿用改版前那两块（`orderInfoRows` / `statusLogContent`），只换外壳。
    @ViewBuilder
    private func terminalDisclosure<Content: View>(
        title: String,
        hint: String,
        isExpanded: Binding<Bool>?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let label = Text(title)
            .flowFont(FlowFonts.rowValue())
            .foregroundColor(AppColors.Flow.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: FlowMetrics.infoRowTappableMinHeight)
        // 先求值再进闭包：`content` 是非逃逸参数，`DisclosureGroup` 的内容闭包是逃逸的。
        let inner = content().padding(.bottom, 14)
        Group {
            if let isExpanded {
                DisclosureGroup(isExpanded: isExpanded) { inner } label: { label }
            } else {
                DisclosureGroup { inner } label: { label }
            }
        }
        .tint(AppColors.Flow.secondaryText)
        .padding(.horizontal, FlowMetrics.infoRowHorizontalPadding)
        .accessibilityHint(hint)
    }
}
