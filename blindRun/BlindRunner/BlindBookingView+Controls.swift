import SwiftUI

extension BlindBookingView {
    var submitArea: some View {
        // 语音在跑的时候，「上一步 / 下一步」是不连贯的：表单的步骤正被向导驱动，用户按它等于和语音抢方向盘。
        // 换成语音自己的两个控件，同时解决另一件事 —— 底栏在 `safeAreaInset` 里，整屏点击区盖不到它，
        // 所以「改用表单」这个逃生口在录音和播报期间都点得到。位置固定不随内容滚动，也更利于空间记忆。
        Group {
            if showsVoiceStage {
                voiceControls
            } else {
                formControls
            }
        }
        // 与表单列同宽，两者左右对齐。语音态的两个控件同样收窄 —— 它们是**具名按钮**
        // （「重复一遍」/「改用表单」），靠 label 找得到，不依赖整屏可点。
        .readableContentColumn()
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // 侧栏：整条竖向铺满，按钮贴底 —— 与竖屏同一个拇指位。
        .frame(width: placesVoiceControlsBeside ? Self.besideVoiceControlsWidth : nil)
        .frame(maxHeight: placesVoiceControlsBeside ? .infinity : nil, alignment: .bottom)
        .background(.regularMaterial)
    }

    /// iPhone 横屏的语音态把底栏挪到右侧。可用高度约 400pt，底栏两枚 64pt 按钮占掉之后
    /// 语音卡片只剩约 140pt，而它的内容要约 250pt —— 放在底下，要么卡片顶进导航栏、
    /// 「改用表单」被挤出屏幕（修之前），要么说明文字静止在半透明底栏下面（只加滚动时）。
    /// 横屏缺的是高度不是宽度，所以挪到侧边：两枚按钮仍竖排、仍固定不随内容滚动。
    /// 表单态不挪 —— 那一态本来就是滚动表单，底栏压不住任何非滚动内容。
    var placesVoiceControlsBeside: Bool {
        showsVoiceStage && verticalSizeClass == .compact
    }

    /// 语音面板在不在屏幕上：向导在跑，或者刚以「取消 / 没听清」结束（后端 #502）。
    /// 后者**不送去表单** —— 全盲用户基本不可能用表单下单；表单只由「改用表单」显式进入。
    var showsVoiceStage: Bool {
        voiceWizard.isRunning || voiceWizard.endedMessage != nil
    }

    var isVoiceSessionEnded: Bool {
        !voiceWizard.isRunning && voiceWizard.endedMessage != nil
    }

    private static let besideVoiceControlsWidth: CGFloat = 240

    /// 竖排，不并排。两个理由：视觉上并排等于把每个按钮的宽度砍半
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1 规则 3，对标产品的次级操作一律整行铺满）；
    /// 读屏上横排两个元素的遍历顺序取决于框架布局而非视觉直觉，是本项目 UI 测试假失败的常见来源。
    ///
    /// 两个都是**蓝描边压在白底上**，与上方那块蓝色实心大屏拉开主次：那块是「点这里说话」，
    /// 这两条是「不想点那里的时候去哪」。同色同重量会让主操作失去优先级 ——
    /// 而这一屏最不该被找不到的恰恰是那块大屏。
    ///
    /// 「改用表单」此前是 `destructive` 红。改蓝是有意的：它不是危险操作，是**逃生口**
    /// （语音坏了，或者在地铁上不想说出自己在哪）。红色在本 App 里标的是求助与阻断，
    /// 用在这里是把警示色用薄了。两条按钮长得一样不构成问题 —— 读屏靠 label，
    /// 看得见的靠文字，而它们的后果都不可怕。
    private var voiceControls: some View {
        VStack(spacing: 10) {
            Button("重复一遍") {
                voiceWizard.repeatCurrentPrompt()
            }
            .buttonStyle(OutlineSecondaryButtonStyle())
            .accessibilityLabel("重复一遍")
            .accessibilityHint("再念一次刚才的提示")

            Button("改用表单") {
                voiceWizard.stop()
                speechService.speak("已停止语音下单，你可以继续用表单填写。")
            }
            .buttonStyle(OutlineSecondaryButtonStyle())
            .accessibilityLabel("改用表单")
            .accessibilityHint("停止语音，用屏幕上的输入框继续填写")
            .accessibilityIdentifier("blindBookingStopVoiceButton")
        }
    }

    private var formControls: some View {
        VStack(spacing: 10) {
            if let blockingReason = viewModel.blockingReasonForCurrentStep {
                Text(blockingReason)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(blockingReason)
            }

            HStack(spacing: 12) {
                if !viewModel.isFirstStep {
                    Button {
                        viewModel.moveToPreviousStep()
                    } label: {
                        Text("上一步").secondaryFillButtonLabel(minWidth: 96)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("上一步")
                    .accessibilityHint("返回上一个预约步骤")
                }

                PrimaryButton(viewModel.currentStep.nextActionTitle, isLoading: viewModel.isSubmitting) {
                    if viewModel.isReviewStep {
                        Task {
                            if let response = await viewModel.submitAnnouncingProgress() {
                                onOrderCreated(response)
                            }
                        }
                    } else {
                        viewModel.moveToNextStep()
                    }
                }
                // 不再额外压透明度：按钮样式在 `.disabled` 时已换成不可用配色（灰底灰字 5.3:1），
                // 再乘 0.45 会让低视力用户读不出这枚按钮是什么（#749 审查 B1）。
                .disabled(primaryActionDisabled)
                .accessibilityLabel(viewModel.currentStep.nextActionTitle)
                .accessibilityHint(primaryActionHint)
            }
            // 并排的一行：胶囊只变矮、不左右收进（#749 定稿 ②），否则最大字号下「提交预约」一行只剩一个字。
            .capsuleButtonsInRow()

            // 次按钮而不是第二块实心蓝：同一屏只留「下一步 / 提交预约」一个实心主按钮（#749，负责人 2026-11-05）。
            Button("重复当前状态") {
                viewModel.repeatCurrentStepStatus()
            }
            .buttonStyle(OutlineSecondaryButtonStyle())
            .accessibilityLabel("重复当前状态")
            .accessibilityHint("点击后重新播报当前预约步骤状态")
        }
    }

    private var primaryActionDisabled: Bool {
        viewModel.isReviewStep ? !viewModel.canSubmit : !viewModel.canAdvanceFromCurrentStep
    }

    private var primaryActionHint: String {
        if let blockingReason = viewModel.blockingReasonForCurrentStep {
            return blockingReason
        }
        return viewModel.isReviewStep ? "提交后系统将为你派单" : "进入下一步"
    }

    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}
