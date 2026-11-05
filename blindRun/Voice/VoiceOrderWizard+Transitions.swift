import Foundation

extension VoiceOrderWizard {
    // MARK: Transitions

    func reask(with message: String) {
        reaskCount += 1
        guard reaskCount < Self.maximumReasksPerSlot else {
            if lastEmptyCompletionWasStartFailure {
                fallBack(reason: "语音输入当前不可用")
            } else {
                endSession(.notUnderstood)
            }
            return
        }
        speak(message)
        guard let field = step.speechField else { return }
        listen(for: field)
    }

    /// 播一句、再收一次音，**不计入重问上限**。
    ///
    /// 与 `reask` 的分界是「这一轮是不是没听清」：定点修改的定向追问里后端听懂了、用户也在正常
    /// 推进，把它记成没听清会让「连改三项」在第三项上被降级到表单。
    /// 计数没有因此消失 —— 用户若在追问后沉默，`handle` 那条空转录路径走的仍是 `reask`。
    func promptAndListen(_ message: String) {
        reaskCount = 0
        speak(message)
        guard let field = step.speechField else { return }
        listen(for: field)
    }

    /// 语音路径走不通时**必须**说清楚接下来去哪 —— 看不见屏幕的人没有别的方式发现语音已经停了。
    /// - Parameter joinsReasonDirectly: `reason` 自己已经带了标点、直接拼下一句。
    ///   默认 `false` 时补一个逗号（「连续两次没听到预约时间，已切回表单⋯⋯」）。
    func fallBack(reason: String, joinsReasonDirectly: Bool = false) {
        isRunning = false
        // 结束态之后再降级（例如在「语音下单已结束」上轻点重开、而这次识别起不来）：不清掉它，
        // 界面会停在语音面板，播报却说「已切回表单」—— 屏幕上根本没有表单。
        endedMessage = nil
        endedAfterFailure = false
        speechInputService?.stopRecognition()
        let message = joinsReasonDirectly
            ? "\(reason)已切回表单填写，你可以用屏幕上的输入框继续预约。"
            : "\(reason)，已切回表单填写，你可以用屏幕上的输入框继续预约。"
        fallbackMessage = message
        speak(message)
    }

    enum SessionEnding { case cancelled, notUnderstood }

    /// 结束语音会话、**停在语音面板**（后端 #502）。与 `fallBack` 的分界是「再说一次有没有可能成」：
    /// 取消和没听清都有，所以不送去表单；权限被拒和端点不存在没有，那两种仍走 `fallBack`。
    func endSession(_ ending: SessionEnding) {
        parseTask?.cancel()
        parseTask = nil
        isRunning = false
        isParsing = false
        speechInputService?.stopRecognition()
        fallbackMessage = nil
        let message = ending == .cancelled ? Self.cancelledMessage : Self.notUnderstoodMessage
        endedMessage = message
        endedAfterFailure = ending == .notUnderstood
        speak(message)
    }

    func speak(_ text: String) {
        lastSpokenPrompt = text
        // 上限在开口的那一刻按字数定下来。放在这里而不是 `waitForSpeechToSettle` 里，是因为那边
        // 只看得到「还在不在念」，看不到念的是什么。
        speechSettleDeadline = Date().addingTimeInterval(Self.settleTimeout(forCharacterCount: text.count))
        speechService?.speak(text)
    }

    /// 进入一次网络往返，并把这件事说出来。
    ///
    /// 不说的话，全盲用户在结束音之后听到的是长达 `parseTimeout`（12 秒）的绝对静默 —— 这正是
    /// AppleVis 对语音类 App「按下之后全程没有任何反馈」的那条抱怨，和我们用来论证要做
    /// `RecordingCue` 的是同一条依据，只守住起止两端等于只守了一半。
    ///
    /// 刻意**不走** `speak(_:)`：那会把 `lastSpokenPrompt` 顶掉，「重复一遍」就再也念不回刚才的提问。
    /// 也刻意不加触觉：`RecordingCue.end()` 的震动刚在几十毫秒前发生过，再震一次是噪声不是信息。
    /// 结果回来时 `askCurrentStep` 的播报会打断这一句 —— 被打断本身就是「好了」的信号。
    ///
    /// 本地判定那一路（肯定词、定点修改指令）**不经过这里**：它零延迟，没有需要填的静默。
    func enterParsing(saying notice: String) {
        isParsing = true
        speechService?.speak(notice)
    }
}
