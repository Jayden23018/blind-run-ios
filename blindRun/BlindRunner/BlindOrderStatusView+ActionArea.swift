import SwiftUI

extension BlindOrderStatusView {
    /// 求助区块**不在这里** —— `IN_PROGRESS` 时它在骨架底部那两个固定版位里
    /// （`BlindOrderFlowView.bottomActions` 的「求助与安全」）。
    ///
    /// 2026-08-19 搬走：这个 section 排在滚动内容第 7 位，`IN_PROGRESS` 时上面压着状态卡、
    /// 140pt 的「打电话给志愿者」、行程分享、180pt 装饰地图 —— 内容顶到求助按钮约 700pt，
    /// 而底部常驻条吃掉约 164pt 后视口只剩约 550pt，**服务进行中的求助按钮在首屏之外，要下滑**。
    /// 而且它的位置还不稳定：拿不到志愿者位置时地图退化成一行文字，求助又回到首屏。
    /// 这直接违反 `docs/research/blind-voice-booking-ia-20260805.md` §4「求助（`IN_PROGRESS` 时）
    /// 必须在首屏两次滑动内可达」。
    ///
    /// 求助搬走之后这里剩下的两个都是**这一态的状态机动作**：等待中的「取消订单」、
    /// 终态的「返回首页」。所以同日把整段从第 8 位提到主动作紧后面 —— 一个页面上
    /// 「此刻能对这一单做的事」应该连在一起，中间不隔着分享和地图。
    /// `IN_PROGRESS` 时这一段是空的（`canBlindRunnerCancel` 为假，`AGENTS.md` §5
    /// 明确禁止服务中展示取消），所以那一态的布局不受这次移动影响。
    func actionSection(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 14) {
            if viewModel.canShowCancel {
                Button("取消订单") {
                    showCancelConfirmation = true
                }
                .buttonStyle(TextButtonStyle(tint: AppColors.destructive, alignment: .center))
                .accessibilityLabel("取消订单")
                .accessibilityHint("需要确认后取消")
            }

            if order.status.isTerminal && order.status != .completed {
                PrimaryButton("返回首页") {
                    dismiss()
                }
                .accessibilityLabel("返回首页")
                .accessibilityHint("点击后返回盲人首页")
            }
        }
    }

    @ViewBuilder
    func debugMockControls(_ order: OrderDetailResponse) -> some View {
        #if DEBUG
        if appState.currentEnvironment == .mock {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mock 状态测试")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                if order.status == .pendingMatch {
                    Button("模拟志愿者接单") {
                        Task {
                            await viewModel.runMockCounterpartSteps(
                                [.respond(.accept)],
                                orderId: order.orderId
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者接单")

                    // 真实链路里陌生人**不能**直接接单（后端 409 `INTRO_CALL_REQUIRED`），
                    // 走的是这一条。留着上面那个是因为熟人路径与「后端把开关关掉」都还走它。
                    Button("模拟志愿者想先聊聊") {
                        Task {
                            await viewModel.runMockCounterpartSteps(
                                [.respond(.interested)],
                                orderId: order.orderId
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者想先聊聊")
                }

                // 通话磨合期只有盲人这一侧能在 Mock 里操作，陪跑员那半边由这个按钮代打 ——
                // 否则盲人端 B3「确认见面安排」在单设备上永远走不到（#434）。
                // 陪跑员的「合适」自 #755 起就是提交安排单，所以代打的是这件事，不再是 `ACCEPT`。
                if order.status == .pendingIntroCall {
                    Button("模拟陪跑员提交见面安排") {
                        _ = try? (appState.sessionUnawareAPIClient as? MockAPIClient)?.simulateIntroCallPlanSubmissionForTesting(
                            orderId: order.orderId,
                            plan: MockAPIClient.demoIntroCallPlan(for: order)
                        )
                        viewModel.startPolling(orderId: order.orderId)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟陪跑员提交见面安排")
                }

                // 跨天预约单：先让志愿者「确认出发」把它推到 `PENDING_ACCEPT`，
                // 之后就接回既有的那几个按钮。分开一个按钮而不是并进下面那条链，
                // 是因为这一步本身就是要验的东西 —— 合进去就跳过了它。
                if order.status == .scheduledConfirmed {
                    Button("模拟志愿者确认出发") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.confirmDeparture], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者确认出发")
                }

                if order.status == .driverEnRoute || order.status == .pendingAccept {
                    Button("模拟志愿者到达") {
                        Task {
                            // 真实状态机是 PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED，不能跳级，
                            // 所以 `PENDING_ACCEPT` 要先补一步 en-route。被 Mock 拒掉时
                            // `runMockCounterpartSteps` 会把原因写进 `errorMessage`，不再静默。
                            let steps: [BlindOrderStatusViewModel.MockCounterpartStep] =
                                order.status == .pendingAccept ? [.enRoute, .arrived] : [.arrived]
                            await viewModel.runMockCounterpartSteps(steps, orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者到达")
                }

                if order.status == .driverArrived {
                    Button("模拟服务开始") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.startService], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务开始")
                }

                if order.status == .inProgress {
                    Button("模拟服务完成") {
                        Task {
                            await viewModel.runMockCounterpartSteps([.finish], orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务完成")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
        }
        #endif
    }

    /// **只读退路**（`.unknown` 与终态）那条常驻底栏：「问一句」+「重复当前状态」。
    ///
    /// 「问一句」排在前面是因为更省时间 —— 整段状态播报要 15~25 秒，而问一句只念被问的那一项。
    ///
    /// 🚩 这里**没有求助分支**，而且不该有。求助只在 `IN_PROGRESS` 开放
    /// （`canBlindRunnerTriggerEmergency` 恒等于 `status == .inProgress`），
    /// 而那一态 2026-09-16 起走骨架、由骨架自带的「求助与安全」版位承担 ——
    /// 这条底栏根本不会被挂上去（`usesFlowSkeleton` 为真时 `safeAreaInset` 里是空的）。
    /// 留着一条永远走不到的安全分支比删掉危险：它会继续被当成「这条路还在」，
    /// 而没有任何东西会说话。
    var standardRepeatStatusArea: some View {
        VStack(spacing: 12) {
            askQuestionButton
            PrimaryButton("重复当前状态") {
                viewModel.repeatStatus()
            }
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前订单状态")
        }
        // 与内容列同宽。都是具名按钮，收窄不影响读屏用户找得到。
        .readableContentColumn()
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // 这条常驻底栏压在滚动内容之上，**恒用实色**。
        //
        // 原来只在系统「降低透明度」打开时才实色，默认走 `.regularMaterial` ——
        // 于是滑过去的文字会从这几个按钮底下透上来，2026-09-07 真机报的「穿模」就是它。
        // 材质在短底栏上没问题，问题出在这一页：它压着一条很长的滚动列表，
        // 透上来的是**正文**，成了文字叠文字。
        //
        // 判据不是「好不好看」，是这一页服务谁：`VisionLevel.LOW_VISION` 的用户不开读屏，
        // 只有「看得见的那一屏」这一条通道，而叠影恰好打掉的就是那条通道
        // （对比度审计查不出来 —— 它查的是静态配色，不是两层内容叠在一起）。
        // 恒实色是原来那个条件的超集，「降低透明度」的用户拿到的东西没变。
        .background(AppColors.background)
        // 底栏与滚动内容之间的边界原本靠材质的模糊来暗示，改实色之后要自己画一条 ——
        // 底栏背景与页面背景是同一个颜色（`:1037`），不画就真的看不出哪里是边界。
        //
        // **不透明，不要 `.opacity(0.25)`**：那样在亮色下是 `#D6D6D7` 压白底 ≈ 1.4:1、
        // 暗色 ≈ 1.5:1，而 WCAG 1.4.11 对「用来识别控件边界」的非文本内容要求 3:1。
        // 这条线正是这次改动为低视力用户新增的**唯一**视觉边界，做成看不见的那一档
        // 等于白改；而且它不响应「增强对比度」，没有别的补偿。
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.textSecondary)
                .frame(height: 1)
                // 纯装饰：不参与命中测试，也不该在无障碍树里多出一个没有 label 的元素。
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 只读退路那条底栏上的「问一句」。
    ///
    /// 走骨架的那六幕不经过这里 —— 它们的「问一句」在求助中心弹层的第三格
    /// （`BlindActiveRunSafetyHubOption.askQuestion`）。两处按的是同一个
    /// `viewModel.askVoiceQuestion()`，且**都不是**纯 `accessibilityAction`：
    /// 那样只有开读屏的人够得着（记忆 `low-vision-visual-channel-unaudited`）。
    private var askQuestionButton: some View {
        Button("问一句") {
            viewModel.askVoiceQuestion()
        }
        .font(AppFonts.body().weight(.semibold))
        .foregroundColor(AppColors.primary)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        // 描边不是装饰。底栏改成实色之后这个按钮压的是 `AppColors.background`，
        // 而 `secondaryBackground` 与它是**同一族系统语义色**：亮色 `#F2F2F7` 压 `#FFFFFF`
        // ≈ 1.06:1，暗色 `#1C1C1E` 压 `#000000` ≈ 1.22:1 —— 按钮的形状实际上消失了，
        // 只剩文字能认出这里可以点。这个组合此前只有开了「降低透明度」的人会遇到，
        // 改成恒实色等于把它变成所有人的默认，所以必须补上边界。
        // 用 `primary`（就是文字色）而不是灰线：它同时给出 ≈7:1 的边界对比。
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.primary, lineWidth: 2)
        )
        .accessibilityLabel("问一句")
        .accessibilityHint("点击后开始录音，可以问陪跑员还有多远、几点开始，或者打电话给陪跑员")
        .accessibilityIdentifier("blindOrderStatusAskQuestionButton")
    }
}
