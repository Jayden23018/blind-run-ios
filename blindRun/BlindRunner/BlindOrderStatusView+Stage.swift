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
                makeTopBar: { menu, onRepeat in stageTopBar(menu: menu + counterpartMenuItems, onRepeatStatus: onRepeat) },
                headerFocused: $statusHeaderFocused,
                footer: { stageFooter(order) }
            )
        } else if BlindOrderStage.resolve(order.status) == .matching {
            // ①「已等 N 分钟」每分钟刷新（#926）。轮询也会重画，这里兜住轮询停了的时候。
            // 派单进度原位写在当前步那一行（#949），不弹浮层。
            DispatchWideningReader(coordinator: appState.realtimeCoordinator, orderID: order.orderId) { widened in
                TimelineView(.everyMinute) { context in
                    if let presentation = BlindOrderStagePresentation.make(
                        order: order,
                        canKeepWaiting: viewModel.canShowKeepWaiting,
                        dispatchWidened: widened,
                        now: context.date
                    ) {
                        stageScaffold(presentation, order: order)
                    }
                }
            }
        } else if let presentation = BlindOrderStagePresentation.make(
            order: order,
            canKeepWaiting: viewModel.canShowKeepWaiting
        ) {
            stageScaffold(presentation, order: order)
        }
    }

    /// 找到陪跑员那一刻的前 0.3 秒（#926）：照换之前那一单画旧 ①，当前点打勾、卡片淡出。
    ///
    /// 不接受点按：这一刻订单已经变了，旧屏上的「取消匹配」会作用在新状态上。
    @ViewBuilder
    func matchFoundContent(_ transition: BlindMatchFoundTransition) -> some View {
        if let presentation = BlindOrderStagePresentation.make(
            order: transition.previousOrder,
            canKeepWaiting: viewModel.canShowKeepWaiting
        ) {
            stageScaffold(presentation.markingMatchFound(), order: transition.previousOrder)
                .allowsHitTesting(false)
        }
    }

    /// 找到陪跑员那一刻的时序（#926，稿 C 帧）。震动与播报不在这里：`apply` 换状态时已经各做了一次
    /// （`speakStatusChange` = 现有状态句 + `RunOrderStatus.haptic`），这里再念一句会把那句切断。
    ///
    /// 被取消（换了新过渡、页面关了）时 `Task.sleep` 立刻返回，整段快进到定格，不会卡在旧 ① 上。
    func playMatchFound() async {
        guard let id = viewModel.matchFound?.id else { return }
        let reduce = reduceMotion
        if !reduce {
            try? await Task.sleep(nanoseconds: Self.nanoseconds(BlindMatchFoundTiming.checkPhase))
        }
        // 只是淡入淡出（两支都是 `.transition(.opacity)`），本身就是减弱动态效果时的降级形态。
        withAnimation(.easeInOut(duration: BlindMatchFoundTiming.crossfade)) { // guard:allow motion-not-gated
            viewModel.revealMatchFound(id)
        }
        let rest = reduce ? BlindMatchFoundTiming.crossfade : BlindMatchFoundTiming.total - BlindMatchFoundTiming.checkPhase
        try? await Task.sleep(nanoseconds: Self.nanoseconds(rest))
        viewModel.finishMatchFound(id)
        // 定格之后读屏焦点才挪到新标题（稿「停在 v7 ②，读屏焦点移到标题」）。
        if viewModel.matchFound == nil { statusHeaderFocused = true }
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(seconds * 1_000_000_000)
    }

    private func stageScaffold(_ presentation: BlindOrderStagePresentation, order: OrderDetailResponse) -> some View {
        BlindOrderStageScaffold(
            topBar: stageTopBar(
                menu: presentation.menu.map { stageMenuItem($0, order: order) } + counterpartMenuItems,
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
        case .reportCounterpart, .blockCounterpart:
            // 不由 `BlindOrderStagePresentation` 给（要看运行时的对方 id），统一从 `counterpartMenuItems` 拼。
            return counterpartMenuItem(kind)
        }
    }

    // MARK: 举报 / 不再匹配此人（2026-11-11 起收进「···」，见 `CounterpartSafetyMenu`）

    /// 举报谁。②③ 通话期 `order.volunteer` 恒为 null，对方 id 从通话数据里取；其余走订单页判定
    /// （跑步中不给，`CounterpartSafetyGate.orderPageTarget`）。跑完那一幕只留绿色卡（#831），也不给。
    var counterpartSafetyTarget: CounterpartSafetyTarget? {
        guard let order = viewModel.order, order.status != .completed else { return nil }
        if BlindOrderStage.resolve(order.status) == .introCall {
            return CounterpartSafetyGate.target(userId: viewModel.introCallCounterpartUserId, orderId: order.orderId)
        }
        return CounterpartSafetyGate.orderPageTarget(order)
    }

    /// 通话期确认框说的是「这一轮换人」，其余是普通的不再匹配（文案在 `UserSafetyCopy.BlockContext`）。
    var counterpartSafetyBlockContext: UserSafetyCopy.BlockContext {
        viewModel.order.flatMap { BlindOrderStage.resolve($0.status) } == .introCall ? .introCall : .standard
    }

    /// 顶栏「···」末尾那两项。没有对方时为空；已不再匹配后只剩「举报」。
    var counterpartMenuItems: [BlindOrderMenuItem] {
        guard counterpartSafetyTarget != nil else { return [] }
        return counterpartSafety.didBlock
            ? [counterpartMenuItem(.reportCounterpart)]
            : [counterpartMenuItem(.reportCounterpart), counterpartMenuItem(.blockCounterpart)]
    }

    private func counterpartMenuItem(_ kind: BlindOrderMenuItem.Kind) -> BlindOrderMenuItem {
        if kind == .blockCounterpart {
            return BlindOrderMenuItem(kind: kind, title: UserSafetyCopy.blockTitle, isDestructive: true) {
                counterpartSafety.showsBlockConfirm = true
            }
        }
        return BlindOrderMenuItem(kind: .reportCounterpart, title: UserSafetyCopy.reportTitle) {
            counterpartSafety.showsReport = true
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

    /// 竖线下面：刚才那一下的结果（含「不再匹配」的结果一行）、调试按钮。正常时大多为空。
    @ViewBuilder
    func stageFooter(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 16) {
            flowFooter(order)
            CounterpartBlockOutcome(viewModel: counterpartSafety)
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
