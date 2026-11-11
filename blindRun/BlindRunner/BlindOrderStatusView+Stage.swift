import SwiftUI

// MARK: - 订单页 v7 ①–④ 接线（#917）
//
// 版式在 `BlindOrderStageView.swift`，内容在 `BlindOrderStage.swift`（①④）与 `BlindIntroCallView`（②③）。
// 这里只把按钮、菜单项、求助胶囊接到订单页已有的动作上 —— **一个新动作都不造**。

extension BlindOrderStatusView {
    /// 这一刻是不是 v7 ①–④ 那几屏。导航栏、工具栏的分流都读它。
    var usesStagePage: Bool {
        viewModel.order.flatMap { BlindOrderStage.resolve($0.status) } != nil
    }

    @ViewBuilder
    func stageContent(_ order: OrderDetailResponse) -> some View {
        if BlindOrderStage.resolve(order.status) == .introCall {
            BlindIntroCallView(
                viewModel: viewModel,
                order: order,
                makeTopBar: { menu, onRepeat in stageTopBar(menu: menu, onRepeatStatus: onRepeat) },
                headerFocused: $statusHeaderFocused,
                footer: { stageFooter(order) }
            )
        } else if let presentation = BlindOrderStagePresentation.make(
            order: order,
            canKeepWaiting: viewModel.canShowKeepWaiting
        ) {
            BlindOrderStageScaffold(
                topBar: stageTopBar(
                    menu: presentation.menu.map { stageMenuItem($0, order: order) },
                    onRepeatStatus: { viewModel.repeatStatus() }
                ),
                eyebrow: presentation.eyebrow,
                title: presentation.title,
                headerAccessibilityLabel: presentation.headerAccessibilityLabel,
                headerFocused: $statusHeaderFocused,
                place: presentation.place,
                when: presentation.when,
                timeline: presentation.timeline,
                card: { stageCard(presentation) },
                footer: { stageFooter(order) },
                bottom: {
                    ForEach(Array(presentation.bottom.enumerated()), id: \.offset) { _, action in
                        stageButton(action, order: order)
                    }
                }
            )
        }
    }

    /// 顶栏。返回 = 离开订单页；求助 = 求助与安全中心（走云端还是本地拨号由 `sosMode` 判，
    /// ①–④ 都不是 `IN_PROGRESS`，所以只会是本地拨号 —— 判定只在 `BlindHomeSOSMode.resolve` 一处）。
    func stageTopBar(menu: [BlindOrderMenuItem], onRepeatStatus: @escaping () -> Void) -> BlindOrderTopBar {
        BlindOrderTopBar(
            surface: .onDark,
            onBack: { dismiss() },
            onRepeatStatus: onRepeatStatus,
            menu: menu,
            sosMode: sosMode,
            onHelp: { showSafetyHub = true }
        )
    }

    private func stageMenuItem(_ kind: BlindOrderMenuItem.Kind, order: OrderDetailResponse) -> BlindOrderMenuItem {
        switch kind {
        case .cancelBooking:
            return BlindOrderMenuItem(kind: kind, title: BlindOrderStageCopy.cancelBooking, isDestructive: true) {
                showCancelConfirmation = true
            }
        case .shareRunPlan:
            // 与求助中心那一格是同一个动作（`toggleLiveShare`）：起分享先过明示同意。
            return BlindOrderMenuItem(
                kind: kind,
                title: shareViewModel.isLiveSharing ? RunPlanLiveShareCopy.stopButtonTitle : RunPlanLiveShareCopy.buttonTitle,
                action: toggleLiveShare
            )
        case .runnerMessage:
            return BlindOrderMenuItem(kind: kind, title: BlindOrderStageCopy.runnerMessage) {
                showRunnerMessage = true
            }
        case .changeVolunteer:
            // 只在 ②③ 出现，那两屏的菜单由 `BlindIntroCallView` 自己拼（确认框挂在它身上）。
            return BlindOrderMenuItem(kind: kind, title: IntroCallCopy.declineButtonTitle) {}
        }
    }

    @ViewBuilder
    private func stageCard(_ presentation: BlindOrderStagePresentation) -> some View {
        BlindOrderStepCard(lead: presentation.cardLead, body: presentation.cardBody) {
            if let volunteer = presentation.volunteer {
                BlindOrderPersonRow(
                    initial: volunteer.initial,
                    label: volunteer.label,
                    line: volunteer.line,
                    spoken: volunteer.spoken
                )
                .accessibilityIdentifier("blindOrderStageVolunteerRow")
            }
        }
    }

    /// 竖线下面：刚才那一下的结果、举报 / 不再匹配、调试按钮。正常时大多为空。
    @ViewBuilder
    func stageFooter(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 16) {
            flowFooter(order)
            OrderCounterpartSafetySection(order: order)
            debugMockControls(order)
        }
    }

    @ViewBuilder
    private func stageButton(_ action: BlindOrderStageBottomAction, order: OrderDetailResponse) -> some View {
        switch action {
        case .keepWaiting:
            BlindOrderStageButton(
                title: KeepWaitingCopy.buttonTitle,
                style: .solid,
                isEnabled: !viewModel.isPerformingAction,
                accessibilityHint: KeepWaitingCopy.accessibilityHint
            ) {
                Task { await viewModel.keepWaiting() }
            }
            .accessibilityIdentifier("blindOrderStatusKeepWaitingButton")
        case .cancelMatching:
            // 只是弹既有的取消确认（里面还挂着「匹配规则说明」链接）。identifier 沿用旧的「最后一行」。
            BlindOrderStageButton(
                title: BlindOrderStageCopy.cancelMatching,
                style: .outline,
                accessibilityHint: "双击后会先确认一次"
            ) {
                showCancelConfirmation = true
            }
            .accessibilityIdentifier("blindOrderFlowLastRowButton")
        case .callVolunteer(let title):
            // 刻意不念号码：VoiceOver 外放等于把号码广播给周围的人（同 `primaryActionHint`）。
            BlindOrderStageButton(
                title: title,
                systemImage: "phone.fill",
                style: .solid,
                accessibilityHint: "系统会先弹出拨号确认，确认后才会拨出"
            ) {
                dialVolunteer(order)
            }
            .accessibilityIdentifier("blindOrderFlowPrimaryButton")
        }
    }
}
