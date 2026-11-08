//
//  MockAPIClient+VoiceIntent.swift
//  blindRun
//
//  确认轮的表态判定（Mock）。从 MockAPIClient+Voice.swift 搬出，并改成逐字镜像后端正则（#899）。
//

import Foundation

extension MockAPIClient {

    /// 确认轮的表态判定。**逐字镜像**后端 `VoiceSlotParser.parseUserIntent`：同一串正则、同一判定顺序。
    ///
    /// 理由与整个 Mock 一致：**Mock 不许比线上松也不许比线上紧**。
    /// 客户端的本地直通表要求是后端正则的子集，Mock 若比后端松，那条子集关系在开发期就验不出来。
    ///
    /// 🔒 `scripts/validate-voice-intent-words.mjs` 逐字比对下面每条正则的源串、大小写开关，
    /// 以及本函数里的判定顺序与匹配方式，和后端 `VoiceSlotParser.java` 有一处不同就红（CI `specs` job）。
    /// 后端改了正则就照抄过来，别在这里另写一套。
    ///
    /// 后端还有一路大模型识别，Mock 没有 —— 所以方言与长句在 Mock 里会落到 `nil`，
    /// 与「模型不可用」时的线上行为一致，不是漏实现。
    static func mockVoiceUserIntent(in transcript: String, missingIsEmpty: Bool) -> VoiceUserIntent? {
        let text = transcript.trimmed
        guard !text.isEmpty else { return nil }
        // 判定顺序 = 后端顺序，别调换（脚本会查）：
        // ① CANCEL 先判 ——「算了不下了」里也有个「了」。
        // ② REPEAT 必须在 RESTART **之后** ——「重新说一遍」两条都命中，而它是 RESTART。
        // ③ NOT_CONFIRM 必须在 CONFIRM 之前 ——「不对」含「对」，不先挡就会被判成确认→直接下单。
        // ④ QUESTION 挡问句 ——「可以了吗」是在问，不是在答。
        if mockVoiceIntentCancel.found(in: text) { return .cancel }
        if mockVoiceIntentRestart.found(in: text) { return .restart }
        if mockVoiceIntentRepeat.found(in: text) { return .repeatBack }
        if mockVoiceIntentNotConfirm.found(in: text) { return nil }
        if mockVoiceQuestion.found(in: text) { return nil }
        let spoken = mockVoiceNotSpoken.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        guard mockVoiceIntentConfirm.matchesWhole(spoken) else { return nil }
        // ⚠️ `CONFIRM` 只在 `missing` 为空时出现：槽位没齐就无从确认，那时用户说「对」
        // 多半是没听清追问。`CANCEL`/`RESTART`/`REPEAT` 不受此限 —— 被卡住的人最需要那几个出口。
        return missingIsEmpty ? .confirm : nil
    }

    /// 只说了「不对」这类否定、既没点名也没给值。
    static func mockVoiceIsPlainNegation(_ transcript: String) -> Bool {
        mockVoiceIntentNotConfirm.found(in: transcript)
    }

    // 以下正则逐字抄自后端 `VoiceSlotParser.java` 的同名常量（`INTENT_*`、`QUESTION`、`NOT_SPOKEN`）。
    // 后端用 `Matcher.find()`（子串命中），所以这里用 `found(in:)`；CONFIRM 用 `matches()`（整句），这里用 `matchesWhole`。
    // 光秃秃的「取消」只在整句就是它时才算数：「把导盲犬取消」是改一项，判成 CANCEL 会让整单凭空消失。
    private static let mockVoiceIntentCancel = mockVoiceRegex(
        #"算了|不下单|不下了|不订了|不跑了|别下单|别下了|不要了|取消订单|取消下单|放弃"#
            + #"|^\s*取消[吧了]?\s*$"#
    )
    private static let mockVoiceIntentRestart = mockVoiceRegex(
        #"重说|重新说|重新来|重新开始|重来|从头再来|从头说"#
    )
    /// ⚠️ 「再说一遍 / 再说一次」在**这一组**，不在 RESTART —— 中文里那是「你把刚才那句重复一次」，
    /// 盲人没听清读回时最自然的请求。判成重来会把他刚说完的一整句清空。
    private static let mockVoiceIntentRepeat = mockVoiceRegex(
        #"再说一遍|再说一次|再念一遍|再念一次|再读一遍|再播一遍|重复一遍|重复一下|重复一次"#
            + #"|没听清|没听见|没听到|刚才说啥|刚才说什么|你说啥|说的啥|再讲一遍"#
    )
    /// 否定/不满 —— 命中返回 nil（=没有表态），交给 `correctionTarget` / `correctionUnclear` 那条路。
    private static let mockVoiceIntentNotConfirm = mockVoiceRegex(
        #"不对|不太对|不是|不行|不可以|不好|先不|错了|有问题|等一下|等等"#
    )
    /// 裸「对」算确认，裸「好」**不算**（要带后缀）。两者刻意不对称 ——「好」是中文最强的话语标记
    /// （「好，那我们…」），旁人对话里出现时多半不是在回答问题；而读回句以「对吗？」结尾，「对」是它唯一的自然答句。
    private static let mockVoiceIntentConfirm = mockVoiceRegex(
        #"(?:对(?:的|了|吧|呀|啊)?|是的|好(?:的|了|吧|呀|啊)|可以了?|没问题|就这样|就这么(?:办|定)?"#
            + #"|这样就?(?:可以|行)了?|确认(?:下单|预约|提交)?|直接下单|下单吧|开始吧|行吧|行了|可行|OK)+"#
            + #"[了吧啊呀哦嘛啦]?"#,
        caseInsensitive: true
    )
    private static let mockVoiceQuestion = mockVoiceRegex(
        #"[吗？?]"#
    )
    private static let mockVoiceNotSpoken = mockVoiceRegex(
        #"[\s\p{P}\p{S}]+"#
    )

    /// 源串是逐字抄来的常量，编译失败只可能是抄错了 —— 开发期就该崩出来。
    private static func mockVoiceRegex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }
}

private extension NSRegularExpression {
    /// Java `Matcher.find()`：任一子串命中。
    func found(in text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Java `Matcher.matches()`：整串命中。包一层 `^(?:…)$` 而不是比较首个匹配的范围 ——
    /// 交替分支会先停在较短的那一支（「对」先于「对的」），首个匹配短于整串不代表整串匹配不上。
    func matchesWhole(_ text: String) -> Bool {
        guard let whole = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: options) else { return false }
        return whole.found(in: text)
    }
}
