import SwiftUI

extension BlindBookingView {
    // MARK: - 语音态

    /// 启动向导，并把表单同步到向导实际停留的那一页。
    ///
    /// 同步这一步**不能只靠** `.onChange(of: voiceWizard.step)`：`step` 的初值就是 `.freeform`，
    /// `start()` 里的 `step = .freeform` 是同值赋值，而 SwiftUI 的 `onChange` 只在新旧值不等时触发。
    /// 少了这里，`currentStep` 停在初值 `.startPoint`，用户按「改用表单」退出语音时屏幕落在
    /// 「确认出发地点」那一步，而向导刚念完的是整单 —— 听到的和摸到的是两回事。
    ///
    /// `start()` 返回 false 表示被前置门槛挡住（资料 / 紧急联系人 / 定位），它自己已经播报过
    /// 原因。这时 `currentStep` 保持第 1 步是对的：用户要去补前置项，不是来复核整单的。
    func startVoiceWizard() {
        // 语音下单会把转写文字交给第三方大模型：账号没同意就先问，**不启动向导、不开麦克风**。
        // 这里是用户看得见的那一道；`ConsentGatedVoiceOrderService` 是兜底，保证同意之前一个 `/parse` 都不会发。
        guard appState.hasVoiceOrderConsent else {
            showsVoiceConsent = true
            return
        }
        // 复位零输入那一步。**没有这行会露出一个可以直接下单的按钮**：
        // 用户点了「不用填，直接下单」（`isZeroInputConfirming = true`）之后改点「用语音重新说一次」，
        // 这一轮语音再失败时页面切回表单态，而 `@State` 还留着上一轮的 true ——
        // `zeroInputBookingSection` 直接渲染第二步那个真提交的按钮，
        // 而用户这一轮既没点过 offer、也没听到「确认就再点一次」那句整单播报。
        // 两步确认的全部理由就是那句播报，没听到就等于一步提交。
        isZeroInputConfirming = false
        // 主动要一次新坐标 —— **这是 N48 根因的正面修法**，放宽新鲜度门只是它的兜底。
        //
        // 这一页要的（`requestsLocationUpdates(.blindBooking)`）是**持续**定位，而非陪跑模式下 `distanceFilter = 10`
        // 意味着站着不动 Core Location 就不推新样本；语音下单恰恰是站着说完一整句。
        // `requestLocation()` 绕过 distanceFilter 直接要一次新 fix，而用户接下来要说 10~20 秒 ——
        // 新坐标早在解析请求发出前就到了，**零延迟代价**。
        //
        // 同一个模式 `EmergencyCoordinator.freshEmergencyCoordinate` 已经在用（`:117-131`），
        // 那边还额外轮询等 5 秒；这里不等，因为拿不到也有 300 秒兜底，而求助没有兜底可言。
        locationService.requestOneTimeLocation()
        if voiceWizard.start() {
            viewModel.currentStep = .review
        }
    }

    /// 语音下单的单独同意小弹窗。文案全部取自 `PrivacyConsentPurpose`（被单测钉住的合规文本，不在 View 里另写）。
    ///
    /// 同意 → 记录后直接启动向导，用户不用再点一次。
    /// 拒绝 → 关掉同意页，下单页此刻停在手动表单上（向导没跑，`showsVoiceStage` 为 false）；
    /// 当场念出反馈，因为对看不见屏幕的人，页面悄悄换回表单等于「点了没反应」。
    /// 不劝返、不重试：拒绝是一个完整的答案。
    var voiceConsentScreen: some View {
        ConsentDisclosureView(
            purpose: .voiceOrderThirdPartyLLM,
            onAgree: {
                appState.recordVoiceOrderConsent()
                declinedVoiceConsentThisVisit = false
                showsVoiceConsent = false
                // 先掐掉还没念完的告知朗读：向导起步要等当前播报落定才开麦，不掐就白等那段长文本。
                speechService.stop()
                startVoiceWizard()
            },
            onDecline: {
                declinedVoiceConsentThisVisit = true
                showsVoiceConsent = false
                speechService.stop()
                speechService.speak(PrivacyConsentPurpose.voiceOrderThirdPartyLLM.declinedFeedback)
            }
        )
        // 系统模态不会把背后的下单页移出读屏树（真机实测），要自己藏，见 `PresenterAccessibilityHider`。
        .background(PresenterAccessibilityHider())
        .task {
            speechService.speak(text: PrivacyConsentPurpose.voiceOrderThirdPartyLLM.popupSpokenScript)
        }
    }

    /// UI 测试接缝：把向导按在运行态，**不碰麦克风**。
    ///
    /// 真机跑 UI 测试拿不到语音识别授权，`start()` 一定走 `isSpeechPathUnavailable` 直接降级到表单态 ——
    /// 于是「语音态里一个表单控件都不许出现」这条本次改动的核心约束**在自动化里根本走不到**。
    /// 少了这个接缝，唯一的验证方式是人肉开 VoiceOver 手测，而那正是这类回归会漏掉的地方。
    ///
    /// 它只置 `isRunning` / `step`（`startForTesting` 的全部作用），不伪造任何解析结果、
    /// 不改播报、不触碰下单路径。
    /// - Returns: 接缝是否生效。生效时调用方不要再走正常的启动分支。
    func holdVoiceStageForUITestingIfRequested() -> Bool {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_FORCE_VOICE_STAGE"] == "1" else {
            return false
        }
        voiceWizard.startForTesting(at: .freeform)
        viewModel.currentStep = .review
        return true
        #else
        return false
        #endif
    }

    /// 语音在跑时屏幕上的全部内容：一块状态区，读回轮再加一张整单。**没有表单。**
    ///
    /// 状态区要真的吃满内容区（`maxHeight: .infinity`），所以滚动容器外面量一次可用高度，
    /// 内容至少撑到那么高：装得下时与不滚动完全一样，装不下时才滚。
    ///
    /// 此前不套 `ScrollView`，理由是「语音态定长、不需要滚动」—— **iPhone 横屏下不成立**：
    /// 可用高度只剩约 400pt，底栏两枚 64pt 按钮之后塞不下状态区，溢出被上下对半分，
    /// 蓝卡顶进透明导航栏，黑字标题「创建预约」直接压在卡上（真机审计 Contrast，
    /// `testBlindBookingInLandscapePassesAccessibilityAudit`）。
    /// 不用 `ViewThatFits` 二选一：真机审计会把整页文字判成改不了字号（记忆 `viewthatfits-fails-dynamic-type-audit`）。
    var voiceStage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    voiceStatusBlock
                    voiceOrderRecap
                    // 没听清而结束时，失败后最省力的出路跟到语音面板上来（原本只在表单态出现）。
                    if isVoiceSessionEnded {
                        zeroInputBookingSection
                        // 直接下单被后端拒（夜间窗口、时段冲突……）时，原因原来只在表单态显示 ——
                        // 这条入口搬到语音面板上之后，不在这里显示就是「按了没反应」。
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(AppFonts.body())
                                .foregroundColor(AppColors.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel(errorMessage)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                // **这一态刻意不收 `readableContentColumn()`**：`voiceStatusBlock` 整块可点是它的核心交互
                // （「说完了」/「别念了」不需要先找按钮）。收到 700pt 会在 iPad 左右各留出 160pt
                // 点不到的边，而盲人是靠空间记忆盲点的 —— 那正是这一态要消除的成本。
                // 可读列宽治的是「长文本横扫串行」，这一屏只有一句话，不适用。
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    /// 整块内容区就是那一下：**在录音是「我说完了」，在播报是「别念了，我要说」。**
    ///
    /// 依据：AppleVis 上对 iMessage 语音消息的原话抱怨是「很难干净地停下来，只能到处滑动去找一个
    /// 很小很难定位的停止按钮」。盲人定位屏幕元素靠顺序滑动或空间记忆，让他在说完话之后再去
    /// 找一个按钮，等于把最该零成本的动作做成了最贵的。整块可点就没有「找」这一步。
    ///
    /// 覆盖范围从「录音中」放宽到「向导运行中」，是为了让长读回也能被打断 —— 读回整单在写死的
    /// 默认语速下要 15~25 秒，而读屏用户日常语速是它的两三倍。
    ///
    /// **它此前是 `body` 上的一层 `.overlay`，解析途中整块撤掉。** 撤掉的理由（`isParsing` 时
    /// `finishSpeakingOrSkipPrompt` 是空操作，宣告一个按不动的动作比没有更糟）现在由「不挂手势、
    /// 不加 `.isButton`」承担；而元素本身留下，否则解析那几秒屏幕上没有任何东西说「正在识别」。
    ///
    /// **逃生口不在它之下**：「改用表单」在 `safeAreaInset` 的底栏里（iPhone 横屏是右侧栏，
    /// 见 `placesVoiceControlsBeside`），那一块永远不被内容区盖住。
    ///
    /// VoiceOver 只给**一个**焦点：`label` 是现在能做什么，`value` 是系统刚念的那句话。
    /// 分成两个元素的话，用户要滑两下才能同时知道「什么状态」和「它说了什么」，
    /// 而这两件事在语音流程里从来是一起需要的。
    private var voiceStatusBlock: some View {
        VStack(spacing: 12) {
            voiceStageIcon

            Text(voiceStageHeadline)
                .font(AppFonts.largeTitle())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if let detail = voiceStageDetail {
                Text(detail)
                    .font(AppFonts.body())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 白底实心胶囊、正文字号：原来是 caption 字号的白色细描边，在整块蓝里几乎看不见，
            // 而它是看得见的用户唯一知道「这一整块能点」的线索（2026-10-05 真机截图评审，两方都点名）。
            // 字色取面板的蓝 —— 白底上的蓝与蓝底上的白是同一对颜色，对比度不变。
            if let tapHint = voiceStageTapHint {
                Text(tapHint)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.voiceStageSurface)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.white))
                    .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.voiceStageSurface)
        .cornerRadius(16)
        .contentShape(Rectangle())
        .onTapGesture {
            if isVoiceSessionEnded {
                // 直接下单正在提交时不重开：一张单在创建、麦克风又开了，两件事会互相打断。
                guard !viewModel.isSubmitting else { return }
                startVoiceWizard()
                return
            }
            guard !voiceWizard.isParsing else { return }
            voiceWizard.finishSpeakingOrSkipPrompt()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceStageAccessibilityLabel)
        .accessibilityValue(isRecording ? "" : (voiceWizard.lastSpokenPrompt ?? "")) // 录音中念出的示例句会被录进去（#558）
        .accessibilityHint(voiceStageAccessibilityHint)
        .accessibilityAddTraits(voiceWizard.isParsing ? [] : .isButton)
        .accessibilityIdentifier("blindBookingFinishSpeakingSurface")
    }

    /// 三态各自的图形。**整块是同一个蓝，三态不靠颜色区分** —— 户外强光下低视力用户
    /// 最先丢的就是色相差异，而这一屏三个状态里有两个（录音 / 识别）决定着「现在点它有没有用」。
    /// 区别落在这里的图形、大标题和下面那句提示上，三处冗余。
    @ViewBuilder
    private var voiceStageIcon: some View {
        if isRecording {
            recordingIndicator
        } else if voiceWizard.isParsing {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.6)
                .frame(height: 40)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)
                .accessibilityHidden(true)
        }
    }

    /// 「这块屏幕可以点」此前只写在 VoiceOver 的 label 里（「双击结束」）——
    /// **看得见的用户没有任何线索**，一整块纯色区域看不出是控件。这行字补的是那一半。
    ///
    /// 它刻意不进无障碍树：整块是 `children: .ignore`，读屏那条路径上这句话已经由
    /// `voiceStageAccessibilityLabel` 说过了，再念一遍是纯重复。
    ///
    /// 解析中返回 nil —— 那一刻 `onTapGesture` 被 `guard` 挡着，宣告一个按不动的动作
    /// 比什么都不说更糟。这与 `.accessibilityAddTraits(isParsing ? [] : .isButton)` 是同一条判据。
    private var voiceStageTapHint: String? {
        if voiceWizard.isParsing { return nil }
        if isVoiceSessionEnded { return "轻点重新开始说话" }
        return isRecording ? "说完轻点这里" : "轻点开始说话"
    }

    private var voiceStageHeadline: String {
        if isRecording { return "正在录音" }
        if voiceWizard.isParsing { return "正在识别" }
        if isVoiceSessionEnded { return "语音下单已结束" }
        if isAskingFreeform { return VoiceBookingCopy.freeformHeadline }
        return "请听提示后说话"
    }

    /// 第一步（自由说）且还没开口。这一刻屏幕上只放一个问题，不放说明。
    private var isAskingFreeform: Bool {
        voiceWizard.step == .freeform && voiceWizard.partialTranscript.isEmpty
    }

    /// 小字那一行。录音中优先显示实时识别文本 —— 它只写屏、不进无障碍树：
    /// 一边说一边念会盖住用户自己的声音，识别也会跟着跑偏（调研 2026-08-03）。
    ///
    /// 🔄 2026-10-07（`redesign-blind-runner-screens-a`）：**第一步不再把那段说明 + 示例摆在屏上**
    /// （「请说你想从哪儿出发……比如：……」）。它仍然被念出来，也仍在读屏的 `accessibilityValue` 里 ——
    /// WCAG 3.3.2 要的「给出输入示例」由听觉通道满足，屏幕只留问题本身。
    /// 后面几步（同名地点追问、读回确认）的那句话**就是系统在问你的问题**，照常显示。
    private var voiceStageDetail: String? {
        if !voiceWizard.partialTranscript.isEmpty {
            return "听到：\(voiceWizard.partialTranscript)"
        }
        if isAskingFreeform { return nil }
        return voiceWizard.lastSpokenPrompt
    }

    private var voiceStageAccessibilityLabel: String {
        if voiceWizard.isParsing { return "正在识别，请稍候" }
        if isVoiceSessionEnded { return "语音下单已结束，双击重新开始说话" }
        return isRecording ? "正在录音，说完后双击结束" : "双击跳过播报，直接开始说话"
    }

    private var voiceStageAccessibilityHint: String {
        if voiceWizard.isParsing { return "" }
        if isVoiceSessionEnded { return "" }
        return isRecording ? "" : "也可以听完播报，麦克风会自动打开" // 录音中不给 hint，同上（#558）
    }

    /// 读回轮把整单摆在屏幕上。**服务的是低视力用户和陪同的明眼人** —— 全盲用户靠读回听，
    /// 屏幕上这份是给看得见的人核对用的。
    ///
    /// 一行「一个名字 + 一个值」，不写「出发地点：」这种前缀：读屏合并后念出来长度翻倍，
    /// 而一张陪跑订单里出现的时间就是预约时间（`docs/research/blind-ui-visual-benchmark-20260808.md` §1 规则 4）。
    ///
    /// 时间只在**真的抽到**时才显示具体时刻。`appointmentTime` 的初值是 `Date()`，
    /// 无条件显示等于把一个用户从没说过的时刻摆成既成事实 —— 这是 2026-08-06 在读回文案上修过的
    /// 同一条红线（用户原话：「他也没有经过我的同意」），屏幕这一份不能把它退回去。
    @ViewBuilder
    private var voiceOrderRecap: some View {
        // 结束态不摆整单：用户刚说了「算了」或者没听清，屏幕上还留一张单会让人以为它还在。
        if voiceWizard.step == .confirm, voiceWizard.isRunning {
            VStack(spacing: 8) {
                recapRow("出发", viewModel.resolvedStartLocationDescription.nilIfBlank ?? "当前位置")
                // 紧跟「出发」，与读回同一个顺序 —— 起终点抽反了要能一眼/一耳看出来。
                // 没说终点就整行不渲染：nil 是「未指定」，摆一行「结束：无」是在回答用户没问的问题。
                if let endPlace = viewModel.endPlace {
                    recapRow("结束", endPlace.isUnresolved ? "\(endPlace.address)（未定位到）" : endPlace.address)
                }
                recapRow(
                    "时间",
                    voiceWizard.didCaptureStartTime
                        ? DateFormatter.aidRunDisplayDateTime.string(from: viewModel.appointmentTime)
                        : "还没说"
                )
                if let durationText = viewModel.resolvedDurationText {
                    recapRow("时长", durationText)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(AppColors.secondaryBackground)
            .cornerRadius(16)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("blindBookingVoiceOrderRecap")
        }
    }

    private func recapRow(_ name: String, _ value: String) -> some View {
        BookingRecapRow(name: name, value: value)
    }
}
