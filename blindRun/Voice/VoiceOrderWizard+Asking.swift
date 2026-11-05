import Foundation

extension VoiceOrderWizard {
    // MARK: Asking

    func askCurrentStep() {
        guard isRunning, let field = step.speechField else { return }
        let prompt: String
        if step == .confirm, let bookingViewModel {
            prompt = confirmPrompt(for: bookingViewModel)
            readBackStartPlaceID = bookingViewModel.resolvedStartPlace?.id
        } else {
            prompt = step.prompt
        }
        speak(prompt)
        listen(for: field)
    }

    /// 读回整单。先念用户原话，再念最终要下的单，最后给出两条出路。
    ///
    /// 三段缺一不可：没有原话，用户分不清是自己说错还是系统听错；没有整单，用户不知道默认值补了什么；
    /// 没有出路，看不见屏幕的人不会自己发现还能说「改时间」。
    private func confirmPrompt(for bookingViewModel: BlindBookingViewModel) -> String {
        var parts: [String] = []
        if let pendingNotice, !pendingNotice.isEmpty {
            parts.append(pendingNotice)
        }
        if let lastUtterance, !lastUtterance.isEmpty {
            parts.append("我听到你说：\(lastUtterance)。")
        }
        parts.append("这次的预约是：")
        parts.append(bookingViewModel.startPointSummary + bookingViewModel.consumeStartPointPrivacySpeech()) // #660 F-14
        // 紧跟起点。终点为 nil 时是空串，一个字都不会念。
        parts.append(bookingViewModel.endPointSummary)
        // 时间这一项**只在真的抽到时才念具体时刻**。
        //
        // 以前无条件念 `appointmentSummary`，而 `appointmentTime` 的初值是 `Date()` ——
        // 抽不出时间时，读回会念出一个用户从没说过的具体时刻，后面再补一句「需至少在 30 分钟后」。
        // 对听不见屏幕的人，那就是「它念了一张我没说过的单」（2026-08-06 用户原话：
        // 「他也没有经过我的同意」）。没说就说没说，不许编。
        // 结束时刻**只在真的抽到开始时间的那一支念**。
        //
        // 另一支里 `appointmentTime` 还是 `Date()` 初值，由它推出来的结束时刻同样是编的 ——
        // 在「预约时间还没说。」后面接一句「预计 X 结束」，正是上面那段注释在防的事，
        // 而且更糟：用户会以为系统听到了时间、只是没念出来。
        parts.append(
            didCaptureStartTime
                ? bookingViewModel.appointmentSummary + bookingViewModel.plannedEndSummary
                : "预约时间还没说。"
        )
        parts.append(bookingViewModel.optionalNeedsSpeechSummary)
        parts.append(confirmOutro)
        return parts.joined()
    }

    /// 读回结尾那句出路。缺关键槽位时**不能**教用户说「确认」——
    /// 教了他会说，说了不生效，那是比不教更糟的体验。
    private var confirmOutro: String {
        if let blocked = missingRequiredSlotMessage {
            return blocked
        }
        return Step.confirmOutroText
    }

    /// 关键槽位缺失时的说明。**开始时间和出发地点是关键的**；时长在产品上就是选填，
    /// 读回念「没有填写选填跑步需求」本来就是诚实的，没有编造。
    ///
    /// 起点以前不算关键槽位，理由是「缺失时有正当默认（当前位置）」。这个假设在定位被拒、
    /// 精确位置关闭、定位还没回来时不成立：`resolvedStartPlace` 为 nil，读回却照样教「说确认」，
    /// 用户照做后语音面板消失、落到表单，只听到「请选择出发地点。」（#558 走查卡死 2）。
    /// 判据用 `resolvedStartPlace` 而不是自己判定位状态 —— 提交时 `makeCreateOrderRequest` 认的就是它。
    ///
    /// 没有 view model 时不拦：那时什么都提交不了（`submitConfirmedBooking` 第一行就 `guard` 掉）。
    var missingRequiredSlotMessage: String? {
        // 2026-08-10：先教「直接说时间」。跨轮修正之后补一个槽位不再需要把整句重说一遍，
        // 而对听不见屏幕的人，少说一整句就是少一次出错的机会。「重说」仍然留着当第二条出路。
        guard didCaptureStartTime else { return Self.missingStartTimeMessage }
        if let bookingViewModel, bookingViewModel.resolvedStartPlace == nil {
            return Self.missingStartPointMessage
        }
        return nil
    }

    func listen(for field: SpeechInputField) {
        guard let speechInputService else { return }
        partialTranscript = ""
        Task { [weak self] in
            await self?.waitForSpeechToSettle()
            guard let self, self.isRunning, self.step.speechField == field else { return }
            speechInputService.startRecognition(
                field: field,
                // 实时文本只写屏，不播报：边说边念会盖住用户自己的声音，识别也会跟着跑偏。
                onTextChanged: { [weak self] text in
                    self?.partialTranscript = text
                },
                // 录音起止的可听提示由 `SpeechInputService` 统一发出，向导转交给 TTS 通道，
                // 免得两边各播一次。
                onAnnouncement: { [weak self] message in
                    self?.speechService?.announce(message)
                },
                onCompletion: { [weak self] completion in
                    self?.handle(completion)
                }
            )
        }
    }

    /// TTS 还在播时开录音，麦克风会先录到系统自己的声音，识别必然跑偏。
    private func waitForSpeechToSettle() async {
        guard let speechService else { return }
        let deadline = speechSettleDeadline
            ?? Date().addingTimeInterval(Self.settleTimeout(forCharacterCount: 0))
        while speechService.isSpeaking && Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    // MARK: Recognition results

    func handle(_ completion: SpeechInputCompletion) {
        guard isRunning, completion.field == step.speechField else { return }
        let transcript = completion.recognizedText.trimmed
        partialTranscript = ""

        guard completion.reason.shouldTriggerSearchWithRecognizedText, !transcript.isEmpty else {
            // ~~整句这一轮什么都没听到：不重问，直接读回默认整单。用户可能就是想「什么都不说，
            // 按默认下单」，重问只会挡着他。~~ **2026-08-06 真机手测推翻这条。**
            //
            // 实际发生的是：用户没听到起音提示（提示音走响铃通道、被静音拨杆关掉，见
            // `RecordingCue`），根本不知道麦克风开了，于是沉默着等提示；8 秒后系统判定
            // 「他想用默认值」，念了一整单他从没说过的预约 —— 时间是 30 分钟后、时长是默认档。
            // 用户的原话是「他也没有经过我的同意」。
            //
            // 「沉默 = 同意默认值」这个假设本身就不成立，对看不见屏幕的人尤其不成立：
            // 沉默的原因绝大多数是**没听见、没听懂、还在想**，而不是「我接受你的默认值」。
            // 而这条路径的下一步就是读回 + 说「确认」成单，把一次没听清放大成一张真实订单。
            //
            // 现在整句轮和别的轮一样重问，共用 `maximumReasksPerSlot`（两次重问后结束：
            // 没听清停在语音面板，识别起不来交回表单，见 `reask`）。
            // 这也与调研 §6.6 一致：识别为空一律重问、上限 3 次，那一节本来就没有给整句开口子。
            //
            // 注意这**不影响**「说了话但抽不出槽位」那条路径 —— 那时 transcript 非空，
            // 走 `parseFreeform` 用默认值补齐并读回，是对的：用户确实说了，他能在读回里听出来。
            lastEmptyCompletionWasStartFailure = completion.reason == .error
            reask(with: silenceReaskMessage(for: completion.reason))
            return
        }

        lastEmptyCompletionWasStartFailure = false
        parseTask?.cancel()
        parseTask = Task { [weak self] in
            await self?.submitTranscript(transcript)
        }
    }

    /// 什么都没听到时说的那句话。
    ///
    /// 整句那一轮**带上例句**：调研 §6.6 引 Google 的错误处理规范 ——「例子比解释有效」，
    /// 而听不见屏幕的人在这里缺的正是「我到底该说什么」，不是「再说一次」这个指令。
    /// 其余轮次的提问本身就短且带例子（见 `Step.prompt`），重复一遍反而拖长。
    private func silenceReaskMessage(for reason: SpeechInputStopReason) -> String {
        if reason == .error {
            return "语音识别启动失败，我再问一次。"
        }
        if step == .freeform {
            return "没有听到你说话。请说你想从哪儿出发、什么时候跑、跑多久，比如：明天早上八点从人民广场出发跑一个小时。"
        }
        return "没有听到你说话，我再问一次。"
    }

    /// 把一段转录文本交给当前这一轮的处理逻辑。
    ///
    /// 与录音解耦是有意的：麦克风那一段由 `SpeechInputService` 自己的用例覆盖，向导这边真正要锁的是
    /// 「整句抽取落到哪些字段」「非确认绝不提交」「三次降级」，这些不需要真的说话就能验。
    func submitTranscript(_ transcript: String) async {
        // 三轮共用的出口：整句轮说「算了」不该被当成下单内容发去 `/parse`，消歧轮不该被当成地名。
        // 本地整串判定，零延迟、不依赖网络 —— 想退出的人不该等一次往返。
        if Self.isCancel(transcript) {
            endSession(.cancelled)
            return
        }
        switch step {
        case .freeform:
            await parseFreeform(transcript)
        case .disambiguateStart(let candidates, _):
            // 完全本地判定，一个字节都不发 —— 「第二个」不是地名，把它发回 `/parse`
            // 会被模型圈成起点 span，高德查不到又按后端口径保留下来，
            // 于是把刚挑好的地址冲掉（后端 `api_spec.yaml` 的 `candidates` 字段写死了这一条）。
            chooseCandidate(from: candidates, saying: transcript)
        case .confirm:
            await handleConfirmCommand(transcript)
        }
    }
}
