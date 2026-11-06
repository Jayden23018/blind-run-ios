import SwiftUI

extension BlindBookingView {
    // MARK: - 表单态

    /// 语音停了之后的屏幕。顺序即「从最省到最费」：出了什么事 → 不用填就能下的单 →
    /// 再试一次语音 → 自己填。
    var formStage: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let fallbackMessage = voiceWizard.fallbackMessage {
                Text(fallbackMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(fallbackMessage)
            }

            // 缺紧急联系人时在这里补（#781；昵称 #789 起不再要求）。都齐了它不渲染任何东西。
            BlindBookingMissingSetupCard(appState: appState)

            zeroInputBookingSection

            // 外观走 `PrimaryButtonStyle`：原先 frame / 底色挂在 Button 外面，可点区只有字那么大（#295 走查 B5）。
            Button("用语音重新说一次") {
                startVoiceWizard()
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("用语音重新说一次")
            .accessibilityHint("重新开始语音下单")
            .accessibilityIdentifier("blindBookingVoiceOrderButton")

            header
            guidedStepHeader
            currentStepContent

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
                    .accessibilityHint("错误提示")
            }
        }
    }

    /// 零输入下单：不填任何东西，用当前位置和最早可约时间成单。
    ///
    /// 只在**语音自己放弃之后**出现：降级到表单（`fallbackMessage != nil`），或没听清而停在
    /// 语音面板（`endedAfterFailure`，#502）。用户主动按「改用表单」时
    /// `fallbackMessage` 是 nil，那是他明说要自己填，不该再塞一个大按钮进去。
    ///
    /// 依据：IA 调研 §6.6 —— 国内产品对「识别不可用」的主流答案不是重试识别，而是**绕过输入**
    /// （滴滴关怀版预存常用地址、一键叫车不输起终点）。我们没有常用地址，能给的等价物就是
    /// 当前位置 + 最早可约时间。注意**没有「现在就跑」**：30 分钟提前量是后端硬约束。
    ///
    /// `firstMissingGate == nil` 这一个条件已经把演示坐标挡住了 —— 正式通道里
    /// `resolvedStartPlace` 拿不到真实定位就是 nil（`allowsDemoFallbackAsStartPoint` 只对
    /// Mock 与 UI 测试放行），`.startPoint` 那道门槛因此为真。不需要在这里再判一次坐标。
    /// 这条路径现在能不能给。**第二步的状态不许活得比它久** —— 见 `startVoiceWizard()` 与
    /// `body` 里对它的 `onChange`：前提消失就必须回到第一步，否则用户会看到一个没听过整单播报的
    /// 提交按钮，而两步确认的全部理由就是那句播报。
    var isZeroInputOfferAvailable: Bool {
        (voiceWizard.fallbackMessage != nil || voiceWizard.endedAfterFailure) && viewModel.firstMissingGate == nil
    }

    @ViewBuilder
    var zeroInputBookingSection: some View {
        if isZeroInputOfferAvailable {
            VStack(spacing: 10) {
                if isZeroInputConfirming {
                    // 第二步的按钮标题**就是整单**。表单路径靠 `reviewSection` 把整单摆在屏幕上
                    // 满足 WCAG 3.3.4 的「可复核确认」，这条路径没有那一屏，复核内容只能由
                    // 按钮自己承担 —— 读屏念按钮时念到的就是要下的单。
                    PrimaryButton(viewModel.zeroInputSummary, isLoading: viewModel.isSubmitting) {
                        Task {
                            if let response = await viewModel.submitAnnouncingProgress() {
                                onOrderCreated(response)
                            }
                        }
                    }
                    .accessibilityLabel(viewModel.zeroInputSummary)
                    .accessibilityHint("点击后立即创建预约并开始派单")
                    .accessibilityIdentifier("blindBookingZeroInputConfirmButton")

                    // 误按第一步的出口。第二步是个占满宽度的大按钮，读屏用户滑过去就可能激活，
                    // 而它的后果是一张真实订单加一次真实派单。
                    Button {
                        isZeroInputConfirming = false
                        // 在语音面板上时下面没有表单，别指一个不存在的地方。
                        speechService.speak(showsVoiceStage
                            ? "已取消直接下单。可以轻点上方重新说，或者按「改用表单」自己填。"
                            : "已取消，你可以继续用下面的表单填写。")
                    } label: {
                        Text("手动填写").secondaryFillButtonLabel(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("手动填写")
                    .accessibilityHint(showsVoiceStage ? "放弃直接下单，留在语音页" : "放弃直接下单，回到表单")
                } else {
                    PrimaryButton("直接下单") {
                        isZeroInputConfirming = true
                        speechService.speak("\(viewModel.zeroInputSummary)。确认就再点一次。")
                    }
                    .accessibilityLabel("直接下单")
                    .accessibilityHint("用当前位置和最早可约时间创建预约，点击后会先念一遍要下的单")
                    .accessibilityIdentifier("blindBookingZeroInputOfferButton")
                }
            }
        }
    }

    var isRecording: Bool {
        voiceWizard.isRunning && speechInputService.isListening
    }

    /// 录音中的可见状态。动画只服务低视力用户与陪同的明眼人 —— 全盲用户靠的是起止提示音和震动
    /// （`RecordingCue`），所以这里的信息**不能**只存在于动画里；承载语义的静态文字是
    /// `voiceStageHeadline` 的「正在录音」，就在这个圆点正下方。
    ///
    /// 脉冲周期 1.2 秒（约 0.83 次/秒），远低于 WCAG 2.3.1 的每秒 3 次红线；
    /// 系统开启「减弱动态效果」时退化为静态圆点。
    ///
    /// 圆点此前是 `destructive` 红并自带一行「正在录音」。改蓝底之后两处都得动：红压在
    /// `voiceStageSurface` 上只有 1.4:1（红和蓝的相对亮度太接近，这不是「深一点就好」能救的），
    /// 而那行文字与紧挨着的大标题逐字重复 —— 灰底时代就是重复的，只是没人盯。
    /// 现在它只剩圆点，居中摆在 `voiceStageIcon` 的录音分支上。
    var recordingIndicator: some View {
        Circle()
            .fill(.white)
            .frame(width: 32, height: 32)
            .opacity(reduceMotion ? 1 : (isPulsing ? 1 : 0.35))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .frame(height: 40)
            .onAppear { isPulsing = true }
            .onDisappear { isPulsing = false }
            .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText("创建预约", style: .title)
                .accessibilityAddTraits(.isHeader)
            Text("按步骤确认出发地点、预约时间和选填需求，最后再提交。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("按步骤确认出发地点、预约时间和选填需求，最后再提交")
        }
    }

    private var guidedStepHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 语音路径不走这四步，进度条对它是假的。
            //
            // 向导实际是「整句 → 读回」两轮，而 `.freeform` 和 `.confirm` 都映射到 `.review`，
            // 所以用户刚说第一句话，进度条就已经显示「第 4 步 / 共 4 步」。这句还进了下面那个
            // `accessibilityLabel`，VoiceOver 会把这个错的数字念出来。语音在跑就不画它。
            if !voiceWizard.isRunning {
                // 读屏不读这一行：下面的进度点组合元素 label 里已经带了同一句（#295 走查 A1）。
                Text(viewModel.stepProgressText)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)

                HStack(spacing: 8) {
                    ForEach(BlindBookingGuidedStep.allCases) { step in
                        VStack(spacing: 6) {
                            // 走过 / 没走过此前**只有填充色**不同 —— 对红绿色觉障碍
                            // （常与低视力并发，而 `VisionLevel.LOW_VISION` 是本 App 的一等公民）
                            // 这排点是完全一样的六个圆。开启「不使用颜色区分」时改成
                            // 实心 / 空心：形状差异不依赖任何色觉。
                            StepProgressDot(
                                isReached: step.rawValue <= viewModel.currentStep.rawValue,
                                differentiateWithoutColor: differentiateWithoutColor
                            )
                            .accessibilityHidden(true)
                            Text(step.shortName)
                                .font(AppFonts.caption())
                                .foregroundColor(step == viewModel.currentStep ? AppColors.textPrimary : AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(viewModel.stepProgressText)，当前步骤：\(viewModel.currentStep.displayName)")
            }

            Text(viewModel.currentStep.displayName)
                .font(.title2.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedStepHeader, equals: viewModel.currentStep)

            Text(viewModel.currentStepSpeechSummary)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(viewModel.currentStepSpeechSummary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch viewModel.currentStep {
        case .startPoint:
            LaunchScopeStepNotice(text: viewModel.launchScopeAreaNotice, identifier: "blindBookingLaunchAreaNotice")
            LaunchScopeStepNotice(text: viewModel.startPointPrivacyNotice, identifier: "blindBookingStartPointPrivacyNotice")
            locationSection
        case .appointmentTime:
            LaunchScopeStepNotice(text: viewModel.launchScopeDutyHoursNotice, identifier: "blindBookingLaunchDutyHoursNotice")
            appointmentSection
        case .runningNeeds:
            optionalSection
        case .review:
            // 提交前最后一站：语音下单、零输入下单都停在这一步，两句都再说一次（#667）。
            LaunchScopeStepNotice(text: viewModel.launchScopeAreaNotice, identifier: "blindBookingLaunchAreaNotice")
            LaunchScopeStepNotice(text: viewModel.launchScopeDutyHoursNotice, identifier: "blindBookingLaunchDutyHoursNotice")
            LaunchScopeStepNotice(text: viewModel.startPointPrivacyNotice, identifier: "blindBookingStartPointPrivacyNotice")
            reviewSection
        }
    }
}
