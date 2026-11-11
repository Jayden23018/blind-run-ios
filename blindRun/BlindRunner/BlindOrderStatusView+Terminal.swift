import SwiftUI

// MARK: - 终态页（已取消 / 暂无志愿者）

extension RunOrderStatus {
    /// 这一态走订单页 v7 终态页（深色头 + 竖线停在中断那一步 + 返回首页，#946），而不是改版前那条只读列表。
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
    /// 已取消 / 暂无陪跑员的终态页。导航栏与底栏要和页面一起判，同一个谓词。
    /// 放在这个文件而不是 `BlindOrderStatusView.swift` 里：那个文件已超长，行数棘轮不许再变大。
    var usesTerminalPage: Bool {
        BlindOrderPageFallback.resolve(viewModel.order?.status) == .terminal
    }

    /// 订单还没拿到（进页面那一瞬间，或第一次拉取失败）。用 v7 外壳，不再闪改版前那页（#946）。
    var usesLoadingShell: Bool {
        BlindOrderPageFallback.resolve(viewModel.order?.status) == .loadingShell
    }

    /// 自带 v7 顶栏的几种页面：藏系统导航栏。只剩 `.unknown` 的只读退路还用系统导航栏。
    var usesV7Chrome: Bool {
        usesStagePage || usesTrackingMapPage || usesTerminalPage || usesLoadingShell
    }

    /// 骨架、终态页或加载外壳：不挂旧的「问一句」底栏 `standardRepeatStatusArea`。
    var usesFlowChrome: Bool {
        usesFlowSkeleton || usesTerminalPage || usesLoadingShell
    }

    /// 已取消 / 暂无陪跑员（#946，稿 `docs/ui/mockups/blind-order-terminal-v7-20261111/`）：
    /// 与 ①–④ 同一个外壳，竖线停在中断那一步，底部只有「返回首页」。
    ///
    /// 🔴 右上角求助胶囊**留着**（负责人 11-11 定），走云端还是本地拨号由 `sosMode` 判 —— 终态不是
    /// `IN_PROGRESS`，所以只会是本地拨号（`AGENTS.md` §6）。
    /// 🔴 **不自动离开页面**：取消成功必须让人听到、看到，并自己决定何时返回首页。
    /// 🔴 没有说明卡（负责人原话「这种没必要的说明把它给去掉」）。
    ///
    /// 改版前那页上的东西一件没删：失败提示、举报结果行、Mock 调试区在 footer（`stageFooter`），
    /// 举报 / 不再匹配在顶栏「···」，预约信息与状态变更记录是竖线下面的两行折叠。
    @ViewBuilder
    func terminalContent(_ order: OrderDetailResponse) -> some View {
        if let presentation = BlindOrderTerminalPresentation.make(order: order, logs: viewModel.statusLogs) {
            BlindOrderStageScaffold(
                topBar: stageTopBar(menu: counterpartMenuItems, onRepeatStatus: { viewModel.repeatStatus() }),
                eyebrow: presentation.eyebrow,
                title: presentation.title,
                headerAccessibilityLabel: presentation.headerAccessibilityLabel,
                headerFocused: $statusHeaderFocused,
                place: presentation.place,
                when: presentation.when,
                timeline: presentation.timeline,
                card: { EmptyView() },
                footer: {
                    VStack(spacing: 16) {
                        terminalDisclosures(order)
                        stageFooter(order)
                    }
                },
                bottom: {
                    BlindOrderStageButton(
                        title: BlindOrderTerminalCopy.backHome,
                        style: .solid,
                        accessibilityHint: BlindOrderTerminalCopy.backHomeHint
                    ) {
                        dismiss()
                    }
                    .accessibilityIdentifier("blindOrderFlowPrimaryButton")
                }
            )
            // 竖线停在哪一步要读状态变更记录（订单本身没有这个字段）。只有已取消要等它；
            // 拿到之前不画竖线，不猜。
            .task(id: order.orderId) {
                guard order.status == .cancelled else { return }
                await viewModel.loadStatusLogs()
            }
        }
    }

    /// 进页面时订单还没拿到：同一个深色头外壳 + 转圈；第一次拉取失败时同一位置显示原因（#946）。
    /// 顶栏同 ①–④，只是没有「···」（订单是什么状态还不知道）。
    /// 读屏念「正在获取订单状态」；`errorMessage` 已由 `speakError` 念过，这里只负责看得见。
    @ViewBuilder
    var loadingShellContent: some View {
        VStack(spacing: 0) {
            // 同 ①–④ 的顶栏：返回、「重复当前状态」、求助（订单未知时 `sosMode` 只会是本地拨号）。
            stageTopBar(menu: [], onRepeatStatus: { viewModel.repeatStatus() })
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage = viewModel.errorMessage, !viewModel.isLoading {
                    Text(errorMessage)
                        .flowFont(FlowV2Fonts.callout())
                        .foregroundColor(BlindOrderV7Palette.headerEyebrow)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blindOrderFlowErrorMessage")
                } else {
                    ProgressView()
                        .tint(BlindOrderV7Palette.headerTitle)
                        .accessibilityHidden(true)
                    Text("正在获取订单状态")
                        .flowFont((30, .bold, .title))
                        .foregroundColor(BlindOrderV7Palette.headerTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .background(BlindOrderV7Palette.headerGradient.ignoresSafeArea())
        // 系统导航栏藏掉之后，读屏「两指 Z」不再自动返回（同 `BlindOrderStageScaffold`）。
        .accessibilityAction(.escape) { dismiss() }
    }

    /// 竖线下面那两行折叠。内容沿用改版前那两块（`orderInfoRows` / `statusLogContent`），只换外壳。
    private func terminalDisclosures(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 0) {
            terminalSeparator
            terminalDisclosure(
                title: "预约信息",
                hint: "展开后可以听到预约时间、出发地点等已确认的信息",
                isExpanded: nil
            ) {
                orderInfoRows(order)
            }
            terminalSeparator
            terminalDisclosure(
                title: "状态变更记录",
                hint: "展开后可以听到此订单每一次状态变化和发生时间",
                isExpanded: $showStatusLogs
            ) {
                statusLogContent
            }
            .accessibilityIdentifier("blindOrderStatusLogsDisclosure")
            terminalSeparator
        }
    }

    private var terminalSeparator: some View {
        Rectangle()
            .fill(AppColors.Flow.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

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
            .frame(minHeight: AppTouchTarget.blindPrimary)
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
        .accessibilityHint(hint)
    }
}
