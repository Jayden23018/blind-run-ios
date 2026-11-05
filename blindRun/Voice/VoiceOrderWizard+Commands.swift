import Foundation

extension VoiceOrderWizard {
    // MARK: Command recognition

    /// 「确认」的肯定词。**整串匹配，不做包含匹配。**
    ///
    /// 两个方向的错误代价不对称：把「确认」误判成「非确认」只是让用户多说一轮；把「改时间」误判成
    /// 「确认」会产生一张用户没打算下的订单并触发真实派单。所以这里只认明确的肯定表达。
    ///
    /// 不做包含匹配的直接理由：「不确认」「先别确认」「确认一下时间」都含有「确认」，
    /// 而意思分别是否定、否定、要求复核。
    ///
    /// 刻意不收「嗯」：它做犹豫填充词的次数不比做肯定少，而这里的误判方向是会真下单的那一边。
    ///
    /// **2026-08-05 收窄：单音节高频应答词全部移出。**
    /// 2018 年 Portland 那起 Alexa 事故是这条规则的完整证据链 —— Amazon 官方复盘里，
    /// 助手问 "[名字], right?"，背景对话中的一句 **"right"** 满足了确认，把一段私人录音发了出去。
    /// 中文的「好」「行」「对」「是」与 "right" 完全同构，而陪跑场景还多一个加重因素：
    /// **志愿者可能就站在旁边说话**，这几个字正是中文日常应答里频率最高的。
    ///
    /// 移出的词：好 / 好的 / 行 / 可以 / 对 / 是 / 没错 / 同意 / 确定 / 提交 / 下单。
    /// 前九个是单双音节应答词；「提交」「下单」是名词性动词，会在「我要下单」「帮我提交一下」
    /// 这类叙述里命中。
    ///
    /// 保留「确认」是因为读回的出路那句念的就是「说『确认』就下单」（见 `confirmPrompt`）——
    /// **白名单必须和系统教用户说的话一致**，否则用户照着念却不生效。改任一边都要改另一边。
    ///
    /// 代价是方言与长句表达更容易被判为「非确认」，用户多说一轮。这正是可接受的失败方向。
    ///
    /// **2026-08-10 删掉「开始约跑」**：本地直通表必须是后端确定性兜底
    /// （`VoiceSlotParser.INTENT_CONFIRM`）的子集，而后端那条正则里没有任何模式能命中它
    /// （最接近的是「开始吧」）。它也从来没被 `confirmPrompt` 教给用户，删掉零损失。
    private static let affirmatives: Set<String> = [
        "确认", "确认下单", "确认预约", "确认提交",
        "没问题", "就这样", "就这么办"
    ]

    /// 「重说」的触发词。**这一组用包含匹配，不用整串匹配** —— 与 `affirmatives` 刻意相反。
    ///
    /// 两组的失败方向不对称，所以匹配严格程度也该不一样：
    /// - 把「不是确认的话」误判成确认 → 产生一张用户没打算下的真实订单。必须整串、必须严。
    /// - 把「不是重说的话」误判成重说 → 用户多说一句话。可以松。
    ///
    /// 整串匹配在这一组上已经被真机证伪：用户说「改地点」被识别成同音的「该地点」，整串不中，
    /// 人就卡在读回那一轮出不来。包含匹配对同音字仍然无能为力，所以词表里把
    /// **「重」「从」两种常见误识都收进来**，并且不依赖单个字。
    ///
    /// 🔴 **2026-08-10 把「再说一次」移出本组**，它现在归 `repeatWords`。
    /// 逐词对撞后端 `VoiceSlotParser` 时查出这是一处**方向相反**的判定分歧：本地判「重说」会把
    /// 用户刚说完的一整句清空，后端 `INTENT_REPEAT` 判的是「你把刚才那句再念一遍」。
    /// 后端 `INTENT_RESTART` 的注释写得很直白 ——「刻意不收『再说一遍』」，因为判错的代价不对称。
    /// 这一条现在由 `scripts/validate-voice-intent-words.mjs` 钉住，再漂就红。
    private static let restartWords: [String] = [
        "重说", "重新说", "从新说", "重新讲", "重来", "重新来", "从头说", "从头再说", "从头来",
        "重新预约", "重新说一遍", "重新来过"
    ]

    /// 「把刚才那段再念给我听」。**注意与 `restartWords` 的语义分界**：
    /// 这一组是「你再念一遍」，那一组是「我再说一遍」。
    ///
    /// 「再说一遍 / 再说一次」中文里两种意思都有。**2026-08-10 从「重说」改判到本组**，
    /// 依据是后端 `VoiceSlotParser.INTENT_REPEAT` 把它们收进了重播，而 `INTENT_RESTART`
    /// 注释里明说「刻意不收」。判反的代价不对称：当成重说会把用户刚说完的一整句清空，
    /// 当成重播最坏只是多念一遍 —— 而这一句正是盲人没听清读回时最自然的说法。
    ///
    /// 长句形式（「再给我念一遍呗」「你刚才说啥来着」）不进本表，交给后端 —— 本地整串表
    /// 接不住方言与长句，那正是第 2 档存在的理由。
    private static let repeatWords: Set<String> = [
        "重复", "重复一遍", "再念一遍", "没听清", "再念一次", "你再说一遍",
        "再说一遍", "再说一次"
    ]

    /// 「放弃这一单」。**整串匹配，不做包含** —— 与 `affirmatives` 同口径。
    ///
    /// 「把导盲犬取消」是改一项，不是取消整单；包含匹配会让用户的整单凭空消失
    /// （后端 `VoiceSlotParser.INTENT_CANCEL` 的注释专门讲过，光秃秃的「取消」只在整句就是它时才算）。
    /// 带订单级宾语的长句（「算了，今天不跑了」）本地不接，交后端 `userIntent == CANCEL`。
    ///
    /// ⚠️ **这里写口语原样，查表时两边都过 `normalizedCommand`**：句尾的「了」「吧」会被剥掉，
    /// 「算了」归一化后是「算」。直接拿归一化后的串去对原样词表，「算了」「不下了」「不要了」
    /// 一个都命中不了。原样写在这里是因为 `scripts/validate-voice-intent-words.mjs` 要拿它逐词
    /// 对撞后端的 `INTENT_CANCEL`，本地不得认后端不判成 CANCEL 的词。
    private static let cancelWords: Set<String> = [
        "算了", "不下单", "不下了", "不订了", "不跑了", "不要了", "取消", "取消吧", "放弃"
    ]
    private static let normalizedCancelWords = Set(cancelWords.map(normalizedCommand))

    static func isCancel(_ transcript: String) -> Bool {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return false }
        return normalizedCancelWords.contains(normalized)
    }

    /// 句尾语气词不改变语义，剥掉可以显著提高召回而不牺牲安全性（「确认吧」「好的呀」）。
    /// 句首不剥：那会让「不确认」这类否定的判定变得脆弱，而多问一轮是可接受的失败方向。
    private static let trailingParticles: Set<Character> = ["吧", "啊", "呀", "了", "哦", "喔", "嘛", "呗", "咯", "啦"]

    /// ponytail: 本地整串匹配只做**第 1 档直通**，判不出来不是终点 —— 交给
    /// `handleConfirmViaBackend` 的 `userIntent` / `correctionTarget`。原来那条「方言与长句会被判成
    /// 没听懂，用户多说一轮」的天花板已经由后端接住，本地表只保留零延迟与离线可用这两件事。
    static func normalizedCommand(_ transcript: String) -> String {
        var normalized = transcript.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
        while let last = normalized.last, trailingParticles.contains(last) {
            normalized.removeLast()
        }
        return normalized
    }

    static func isAffirmative(_ transcript: String) -> Bool {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return false }
        return affirmatives.contains(normalized)
    }

    /// 判定顺序有意义：**肯定词先判、且只认整串**，免得「重新确认一下」这种话里的「确认」被包含匹配吃掉。
    static func command(for transcript: String) -> Command {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return .unrecognized }
        if affirmatives.contains(normalized) { return .confirm }
        if repeatWords.contains(normalized) { return .repeatBack }
        if restartWords.contains(where: { normalized.contains($0) }) { return .restart }
        return .unrecognized
    }
}
