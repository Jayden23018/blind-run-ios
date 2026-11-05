import Foundation

extension VoiceOrderWizard {
    // MARK: Freeform

    /// 一整句一次抽三个槽位（起点 / 开始时间 / 时长），抽不出的保留默认值。
    ///
    /// **这一轮不重问、不失败。** 抽出多少算多少，剩下的由读回环节交代清楚，让用户决定要不要改。
    /// 让整句这一轮也走「没听清就重问」，会把用户按在同一句话上反复喊——而他其实只要听一遍
    /// 结果就知道该改哪一项。
    ///
    /// 所以 `missing` / `needReask` / 后端 `ttsText` 三个字段在这一轮**一个都不消费**：
    /// `missing` 等价于「这几项保持默认值」，而后端的 `ttsText` 在 `missing` 非空时是**追问**文案，
    /// 播它就等于把人拉回重问。读回一律用 `confirmPrompt` 自己拼的整单（后端 2026-08-04 确认：
    /// 抽不出的槽位保留什么默认值只有客户端知道，后端拼不出整单）。
    func parseFreeform(_ transcript: String) async {
        enterParsing(saying: "正在识别，请稍候。")
        defer { isParsing = false }
        lastUtterance = transcript

        // 一次请求拿三个槽位。这一轮**吞掉所有错误**：整句抽不出或网络挂了都不该把用户打回表单，
        // 默认值仍然成单，让读回环节把实际内容念清楚，由用户决定改不改。
        //
        // 但**吞掉不等于不说**：原来这里是 `try?`，失败时一个槽位都不填，读回念的全是默认值，
        // 而用户听不出「语音没在工作」和「语音听懂了但你说的正好是默认值」的区别 ——
        // 没仔细听就下了一张时间地点全错的单。2026-08-06 查实 `/api/orders/voice/parse` 的 handler
        // 只在后端未部署分支上，生产恒 404，这条路径不是偶发而是常态。
        var parsed: ParseVoiceOrderResponse?
        var parseFailed = false
        parseIsUnavailable = false
        do {
            parsed = try await parseOrderResponse(transcript)
        } catch {
            if Self.isIdentityRejection(error) { return stopForIdentityRejection() }
            parseFailed = true
            parseIsUnavailable = Self.isEndpointMissing(error)
        }

        // 端点根本不存在：连一次读回都不做，直接交回表单。
        //
        // 读回在这里没有任何价值 —— 它必然念一整套默认值，而时间抽不到就不许确认，
        // 用户唯一能做的只有重说，重说还是 404。给他一次「听起来像是可以再试试」的读回，
        // 只是把死路包装得像活路。
        if parseIsUnavailable {
            fallBack(reason: Self.parseUnavailableNotice, joinsReasonDirectly: true)
            return
        }

        var notice: String? = parseFailed ? Self.parseFailureNotice : nil
        if let parsed {
            notice = apply(parsed, spokenIn: transcript) ?? notice
        }
        // 后端因**阻断项**缺失而给的追问语，作为 notice 带进读回。
        //
        // 🚩 **这不违反上面那条「整句这一轮不重问」** —— 我们仍然读回、仍然让用户决定改不改，
        // 只是把后端那句话说出来。加它的直接起因是夜间禁跑窗口（N134）：
        // 后端在 `[22:00, 05:00)` 时把 `startTime` 置 null、往 `missing` 里放 `START_TIME`
        // 并把 `ttsText` 换成夜间提示，然后**默认客户端会念它**（handoff 2026-09-05 原话
        // 「如果你们是按 needReask / missing 走的（应该是），这里什么都不用动」）。
        // 而这一轮本来一个字都不消费 ⇒ 用户听到的是「预约时间还没说」，
        // 对一个刚刚清清楚楚说了「晚上九点」的人，这句话是错的，而且他重说一遍还是同样结果。
        //
        // 🚩 **只取 `START_TIME` 一项，不取全部阻断项。**
        // `ADDRESS` 缺失在本客户端有**正当默认值**：起点回落当前位置，而且读回开头就会念
        // 「使用设备当前位置。」（见本文件 `confirmRoundSnapshot` 那段）。把后端那句
        // 「没听清出发地点」塞进去，紧接着读回却念出一个具体地点 —— 两句话自相矛盾，
        // 而对只能听的人，先听到的那句会被当成结论。
        //
        // `START_TIME` 没有这种默认值（`appointmentTime` 的初值是 `Date()`，
        // 而「用户没说过的时间不许当成已确认」是条红线），缺了就是真的缺 —— 后端那句追问
        // 是这一轮唯一能解释「为什么时间没进去」的东西，夜间禁跑那句正是走这条。
        //
        // 🚩 **判据是「排第一」，不是「含有」**（后端 #508）：`ttsText` 永远是 `missing` 里**第一个**
        // 阻断项的追问，而后端的顺序是起点在前。整句只说「明天早上」时 `missing = [ADDRESS, START_TIME]`，
        // `ttsText` 是起点追问 —— 用「含有」会把它念出来，正好撞上上一段要避免的自相矛盾。
        // 那一轮不念任何追问：读回结尾自己会说「预约时间还没说」，而确认轮的 `current` 带上设备位置后
        // 起点不再缺，后端到那时给的才是「明天早上几点？」。
        if let parsed,
           parsed.missing?.first == .startTime,
           let reask = parsed.ttsText?.nilIfBlank {
            notice = [reask, notice].compactMap { $0 }.joined()
        }

        // 说得太长时后端静默降级成纯正则，终点与备注**一定**抽不到（见
        // `ParseVoiceOrderRequest.modelFallbackCharacterLimit`）。排在最前面说：
        // 它解释的是后面那一整段读回为什么缺东西，放在后面等于让用户先困惑一遍。
        if let lengthNotice = Self.longUtteranceNotice(forCharacterCount: transcript.count) {
            notice = [lengthNotice, notice].compactMap { $0 }.joined()
        }

        // 起点撞了同名地点：**先让用户挑，再读回整单**。
        //
        // 排在读回之前不是顺序偏好：读回念的是「我们的最佳猜测」（候选第一条），
        // 用户听完多半就说「确认」，那批候选白算了，而如果第一条不是他要的那个，
        // 错地点已经被确认下单 —— 而他听到的读回念得很顺，无从分辨。
        if let parsed, let candidates = parsed.startCandidatesToDisambiguate {
            moveToDisambiguation(candidates, prompt: parsed.ttsText, notice: notice)
            return
        }

        moveToConfirm(notice: notice)
    }
}
