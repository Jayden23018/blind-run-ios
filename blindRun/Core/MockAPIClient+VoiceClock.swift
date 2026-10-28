import Foundation

// Mock 语音解析的**开始时间**一族：日期词、时段词、钟点、相对时间、认不了的日期。
//
// 2026-10-28 从 `MockAPIClient+Voice.swift` 拆出（#528）：那个文件超了 SwiftLint 的 1000 行上限、只许变短，
// 而对齐后端 #864（#876）要加整段新逻辑。时长、地址、意图解析仍在原文件；两边共用的数字工具
// （`trailingNumeral`、`chineseNumber`、`chineseNumberValue`、`numeralCharacters`）也留在原文件。
extension MockAPIClient {

    /// 日期词表 —— **唯一来源**。`mockVoiceStartTime` 的日偏移、「明晚」的 +12、「挨着钟点的是不是日期词」、
    /// `timeLikeRegex` 的日期词，全部从它派生。
    ///
    /// 立这张表的理由是漂移：这几处原先各抄一份词表，后端 #472 加「明早/明晚」时只有解析处跟上了，
    /// `timeLikeRegex` 的注释写着「逐字照抄」却已经少了两个词 —— 「从明早出发」的 span 因此被当成地名。
    /// 加一个日期词（后端先加）只改这一处。
    static let voiceDateWords: [(form: String, dayOffset: Int, impliesEvening: Bool)] = [
        ("后天", 2, false),
        ("明天", 1, false), ("明早", 1, false), ("明晚", 1, true),
        // 「明早上 / 明晚上」整个是一个日期词（后端 `明[早晚]上?`）。判「挨着钟点的是什么」时要先认它，
        // 否则「早上」先被当成时段词剥掉，剩下一个「明」不是日期词，日期就丢了
        ("明早上", 1, false), ("明晚上", 1, true),
        ("第二天", 1, false), ("第2天", 1, false),
        ("今天", 0, false)
    ]

    /// 原话里有没有日期词（对应后端 `VoiceSlotParser.DATE_WORD`）。
    private static func mentionsVoiceDateWord(_ transcript: String) -> Bool {
        voiceDateWords.contains { transcript.contains($0.form) }
    }

    /// 开始时间解析。取值与 `demo/docs/voice-golden-corpus.json` 里 `field: "START_TIME"` 的用例一致，
    /// `VoiceOrderWizardTests` 锁了这份对齐。
    ///
    /// 此前这里只认 5 个钟点、且落点恒定是「明天」，10 条语料只对得上 3 条 —— 于是开发期用 Mock 说
    /// 「今天八点半」会被念成明天，说「下午三点」「半小时后」则直接走重问，**而线上这三种都解得出**。
    /// Mock 比线上严和比线上松一样有害：一个让开发期以为功能没有，一个让上真机才发现走不通。
    static func mockVoiceStartTime(in transcript: String, now: Date? = nil) -> Date? {
        let now = now ?? voiceNow
        let calendar = Calendar.current

        // ⓪ 认不了的日期表达一律整句认输（语料 `_unsupported_date_note`）。
        //
        // 下面的日期词只认明天/后天/今天这几个，碰上「8月10号」「下周三」它不会失败，
        // 而是**只取钟点、把日期当没说**，再套 ④ 的「已过就滚次日」—— 于是任何日期
        // 都被静默解析成今天或明天：「8月10号早上8点」→ 次日 08:00（差 1 天）。
        // 这个值能过提前量校验、读回念得很顺，而盲人无从判断这不是自己说的那天。
        if unsupportedDateRegex.firstMatch(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)) != nil { return nil }

        // ① 相对时间优先。「半小时后」不能被下面的钟点分支按「半」误读。
        if let offset = relativeMinutesOffset(in: transcript) {
            return calendar.date(byAdding: .minute, value: offset, to: now)
        }

        // ② 钟点。没有「N点」就不是时间表达（llm 那几条走这里返回 nil）。
        guard let picked = pickClock(in: transcript) else { return nil }

        // ③ 日期词只认**挨着钟点**的那个（后端 #864）。说了日期词、它却没挨着任何钟点 → 认输追问，不猜：
        // 「我明天要上班，所以下午5点跑吧」说的是今天，「明天早上我先去医院，下午3:00再跑」也定不下。
        // 以前这里按「原话里有没有日期词」算，两句都被读成明天。没说日期词时 dayOffset 为 nil ——
        // 与「说了今天」不是一回事，见 ④。
        //
        // 「第二天」= 明天（产品 2026-08-09 拍板）。⓪ 那条黑名单专门把它放行到这里，
        // 这里再不认就等于「只取钟点、把日期当没说」，正是 ⓪ 要防的那个静默篡改。
        if picked.prefix.date == nil, mentionsVoiceDateWord(transcript) { return nil }
        let dayOffset = picked.prefix.date?.dayOffset

        // 时段词同样只认挨着钟点的那个：「下午我先去医院，明天早上8点跑」是 08:00，不是 20:00。
        // 没有时段词时「明晚」自带晚上（后端 #472），哪些日期词自带由 `voiceDateWords` 的 `impliesEvening` 说了算。
        let period = picked.prefix.period ?? (picked.prefix.date?.impliesEvening == true ? .afternoon : nil)
        let hour = to24Hour(picked.clock.hour, period: period)
        // 后端 `hour > 23` 整句认输：「明天早上25:00」不硬凑成次日 1 点。
        guard hour <= 23 else { return nil }

        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: calendar.date(byAdding: .day, value: dayOffset ?? 0, to: now) ?? now
        )
        components.hour = hour
        components.minute = picked.clock.minute
        guard let candidate = calendar.date(from: components) else { return nil }

        // ④ 没带日期词的钟点若早于现在，自动滚次日（语料 `_past_time_note`）。
        // 不滚的话「八点半」会返回今天 08:30，被提前量校验判成「太近了」—— 而用户压根没打算约今天。
        // 显式说了「今天」则不滚：那是用户的明确选择，该让提前量校验去拒绝它。
        if dayOffset == nil, candidate <= now {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return candidate
    }

    /// 「半小时后」「四十分钟后」「两个小时后」→ 相对分钟数。没有「后」字就不是相对表达。
    private static func relativeMinutesOffset(in transcript: String) -> Int? {
        guard transcript.contains("后"), !transcript.contains("后天") else { return nil }
        if containsStandaloneHalfHour("后", in: transcript) { return 30 }
        if let minutes = chineseNumber(before: "分钟后", in: transcript) { return minutes }
        if let hours = chineseNumber(before: "个小时后", in: transcript)
            ?? chineseNumber(before: "小时后", in: transcript) {
            return hours * 60
        }
        return nil
    }

    /// 时段词表 —— **唯一来源**（与 `voiceDateWords` 同理）。`to24Hour` 的 12 → 24 小时换算、
    /// 「挨着钟点的是不是时段词」和 `timeLikeRegex` 的时段词都从它派生，加一个时段词只改这一处 ——
    /// 不然「凌晨」这类词会在判据与换算里各手抄一份，后端加词时只跟上一处（「明早/明晚」漏进 `timeLikeRegex` 就是这么漂的）。
    /// 「早晨 / 清晨 / 晌午 / 后晌 / 傍晚 / 傍黑（儿）」是后端 #864 补的。
    enum VoicePeriod { case morning, noon, afternoon, dawn }

    static let voicePeriodWords: [(form: String, period: VoicePeriod)] = [
        ("上午", .morning), ("早上", .morning), ("早晨", .morning), ("清晨", .morning),
        ("中午", .noon), ("晌午", .noon),
        ("下午", .afternoon), ("后晌", .afternoon), ("傍晚", .afternoon), ("傍黑儿", .afternoon), ("傍黑", .afternoon),
        ("晚上", .afternoon),
        ("凌晨", .dawn)
    ]

    /// 「中午」之后最晚到几点还算下午。对齐后端 `VoiceSlotParser.NOON_LAST_AFTERNOON_HOUR`。
    private static let noonLastAfternoonHour = 4

    /// 12 小时口语的钟点 → 24 小时制，由时段词决定。对应后端 `VoiceSlotParser.to24Hour`。
    /// 时段词只决定「几点」，不决定「哪天」。
    /// - 下午 / 晚上：`<12` 的 +12
    /// - 中午：一~四点 +12；十 / 十一 / 十二点照旧。不换的话「中午一点」读成凌晨 01:00，
    ///   值能过提前量校验、读回念得很顺的静默篡改
    /// - 凌晨：整体不变，**只有 12 点是 0 点**：凌晨十二点 = 次日零点，不是正午
    private static func to24Hour(_ hour: Int, period: VoicePeriod?) -> Int {
        switch period {
        case .afternoon: return hour < 12 ? hour + 12 : hour
        case .noon: return hour <= noonLastAfternoonHour ? hour + 12 : hour
        case .dawn: return hour == 12 ? 0 : hour
        case .morning, nil: return hour
        }
    }

    /// 句里的一个钟点：12 小时口语的时、分，以及数字在原话里的起点（判它前面挨着什么要用）。
    private struct VoiceClock {
        let hour: Int
        let minute: Int
        let hourStart: String.Index
    }

    /// 挨着钟点的日期词与时段词，对应后端 `CLOCK_TIME` 的 group(1) / group(2)。
    private struct VoiceClockPrefix {
        let date: (form: String, dayOffset: Int, impliesEvening: Bool)?
        let period: VoicePeriod?
    }

    /// 句里用哪个钟点 —— 对齐后端 `VoiceSlotParser.pickClock`（#864）：**挨着日期词的优先**，都没有就取第一个。
    /// 「我7:00下班，所以明天晚上8:00吧」约的是 20:00；以前取第一个，读回成 7:00。
    ///
    /// 程度副词守卫命中时跳过这一个、继续找（后端的 `continue`）：「跑慢一点，明天早上八点出发」里
    /// 真正的钟点在后半句，直接返 nil 会让整句抽不出时间。
    private static func pickClock(in transcript: String) -> (clock: VoiceClock, prefix: VoiceClockPrefix)? {
        let clocks = (colonClocks(in: transcript) + spokenClocks(in: transcript)).sorted { $0.hourStart < $1.hourStart }
        var firstUndated: (clock: VoiceClock, prefix: VoiceClockPrefix)?
        for clock in clocks {
            let prefix = clockPrefix(in: transcript, before: clock.hourStart)
            if prefix.date == nil, prefix.period == nil, isDegreeLeadIn(transcript, hourStart: clock.hourStart) { continue }
            if prefix.date != nil { return (clock, prefix) }
            if firstUndated == nil { firstUndated = (clock, prefix) }
        }
        return firstUndated
    }

    /// 日期词、时段词、钟点之间允许夹的东西（后端 `CLOCK_JOINER`，#864）：空白、「的」、逗号、
    /// 语气词「吧啊呀嗯呢呃」，以及「那个」（`droppingClockJoiners` 单独认）。
    /// 不收语气词的话，「明天吧，十一点」「明天早上呃8:00」的日期词挂不到钟点上，会被 ③ 判成认输追问。
    private static let clockJoinerCharacters: Set<Character> = [
        " ", "\t", "\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "的", "，", ",", "吧", "啊", "呀", "嗯", "呢", "呃"
    ]

    private static func droppingClockJoiners(_ text: Substring) -> Substring {
        var text = text
        while true {
            if let last = text.last, clockJoinerCharacters.contains(last) {
                text = text.dropLast()
            } else if text.hasSuffix("那个") {
                text = text.dropLast(2)
            } else {
                return text
            }
        }
    }

    /// 钟点数字前面挨着的日期词与时段词 —— 对齐后端 `(日期词)? 连接符 (时段词)? 连接符 数字`（#864）。
    /// 只认**挨着**的：句里别处的日期词、时段词不算。日期词先判，理由见 `voiceDateWords` 里的「明早上」。
    private static func clockPrefix(in transcript: String, before hourStart: String.Index) -> VoiceClockPrefix {
        let head = droppingClockJoiners(transcript[..<hourStart])
        if let date = voiceDateWords.first(where: { head.hasSuffix($0.form) }) {
            return VoiceClockPrefix(date: date, period: nil)
        }
        guard let period = voicePeriodWords.first(where: { head.hasSuffix($0.form) }) else {
            return VoiceClockPrefix(date: nil, period: nil)
        }
        let beforePeriod = droppingClockJoiners(head.dropLast(period.form.count))
        return VoiceClockPrefix(date: voiceDateWords.first { beforePeriod.hasSuffix($0.form) }, period: period.period)
    }

    /// 钟点数字紧跟在程度副词后面吗。照抄后端 `VoiceSlotParser.isDegreeLeadIn`（「慢快早晚好」）。
    ///
    /// 「慢一点」里的「一点」正好长得像「1 点」，认了就凭空造出一个凌晨 1 点 —— 而用户根本没提时间，
    /// 这个时刻还能过提前量校验、被读回念得很顺。刻意**不收「多少」**（会误杀「差不多1点」）。
    /// 只在钟点前**既没挨着日期词也没挨着时段词**时判（后端 #472 / #864）：「明晚八点」「傍晚6点」里
    /// 紧挨数字的「晚」属于它们。拒绝的是这**整个**钟点，不缩成更短的数再读，见 `trailingNumeral`。
    private static func isDegreeLeadIn(_ transcript: String, hourStart: String.Index) -> Bool {
        guard hourStart > transcript.startIndex else { return false }
        return "慢快早晚好".contains(transcript[transcript.index(before: hourStart)])
    }

    /// 冒号钟点：`8:00`、`8：00`、`18:30`。
    ///
    /// **这条起初在黄金语料里找不到依据，是照真机实况补的**（2026-08-06 手测「说了时间但识别不了
    /// 时间点」）：iOS 的 `SFSpeechRecognizer` 说中文时经常把「八点钟」渲染成 `8:00`，
    /// 句子里连「点」字都没有。后端 2026-08-08 的 PR #14 补齐同一条并进了语料，
    /// 现在两边同口径。
    ///
    /// 分钟写 `[0-5]\d` 而不是 `\d{2}` + 范围校验：非法分钟（`8:75`）直接不匹配，
    /// 与后端 `CLOCK_TIME` 逐字一致。小时不在这里拦，换算后大于 23 由 `mockVoiceStartTime` 整句认输（与后端同）。
    private static func colonClocks(in transcript: String) -> [VoiceClock] {
        transcript.matches(of: colonClockRegex).compactMap { match in
            // ⚠️「跑1:30」是**时长**口语（识别器可能把「跑一个半小时」渲染成这样），不是 01:30 出发。
            // 不挡的话它会被当成钟点 → 01:30 已过 → 滚到次日 → 提前量校验放行 →
            // 读回念出一个用户从没说过的时刻。**静默篡改比抽不出更糟**：抽不出至少读回时听得出来。
            //
            // 只跳过这一个 —— 「跑1:30，明天早上8点出发」里真正的钟点在后面。
            if isDurationLeadIn(transcript, hourStart: match.range.lowerBound) { return nil }
            let parts = transcript[match.range].split(whereSeparator: { $0 == ":" || $0 == "：" })
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
            return VoiceClock(hour: hour, minute: minute, hourStart: match.range.lowerBound)
        }
    }

    private static let colonClockRegex = try! Regex(#"\d{1,2}[:：][0-5]\d"#)

    /// 数字紧跟在时长引导词后面吗（「跑1:30」「跑步1:30」）。照抄后端
    /// `VoiceSlotParser.isDurationLeadIn`。
    ///
    /// **只在冒号钟点上判**：「跑8点」这种写法现实中不存在，加进来只会多一条没人走的分支。
    /// 用引导词而不是「小时数看着像时长」之类的启发式 —— 后者会把「跑到1:30」这类真钟点误杀。
    private static func isDurationLeadIn(_ transcript: String, hourStart: String.Index) -> Bool {
        guard hourStart > transcript.startIndex else { return false }
        return "跑步".contains(transcript[transcript.index(before: hourStart)])
    }

    /// 逐字照抄后端 `VoiceSlotParser.UNSUPPORTED_DATE`（`VoiceSlotParser.java:87-109`，2026-10-28 按后端 #876 同步），**在原文上判**
    /// （后端在中文数字归一化之前匹配，归一化后「下周三」变「下周3」）。用 `NSRegularExpression`（ICU）：反向后顾 `(?<!…)`
    /// 与占有量词 `\s*+` 它和 Java 一样认；Swift `Regex` 在 iOS 16 不支持反向后顾，`try!` 会在运行时崩。后端改了整段再抄一次。
    /// ponytail: 只让它认输，**不新增「认识 X月Y号」的解析分支**。日期表达是开放的
    /// （下下周二 / 这个月底 / 月底前），正则永远穷举不完，那是大模型该干的活。
    private static let unsupportedDateRegex = try! NSRegularExpression(
        pattern: "[0-9零一二两三四五六七八九十]{1,3}\\s*月\\s*[0-9零一二两三四五六七八九十]{1,3}\\s*[号日]"
            + "|[下这本上那]{1,2}\\s*+个?\\s*+(?:周|星期|礼拜)(?![围边])"
            + "|大[前后]天"
            + "|[下这本]\\s*个\\s*月"
            // 「第三天」以上相对哪天没说清；**「第二天」当明天解**（产品 2026-08-09 拍板），用 `(?![二2]\s*天)` 放行。
            + "|第(?![二2]\\s*天)[0-9零一二两三四五六七八九十]{1,3}\\s*天"
            + "|隔天"  // **刻意不当明天**：中文里也常指「每隔一天」（「隔天跑一次」），这个歧义是真的，宁可追问一次
            + "|(?<![每个几0-9零一二两三四五六七八九十])(?:周|星期|礼拜)[一二三四五六七日天末1-7]"  // 裸星期几、周末（不含「每周一次」）
            + "|[0-9零一二两三四五六七八九十几半]{1,3}\\s*(?:天|个?(?:周|星期|礼拜|月))\\s*[以之]?后"  // 三天后、一个月后
            + "|月[底初]"
            + "|(?<![然以之最])后儿"  // 方言「后儿」= 后天，「然后儿」不是
    )

    /// 「N点…」写法的钟点。N 中文与阿拉伯数字都认。
    ///
    /// **扫描每一个「点」，不是只看第一个**：对齐后端 `while (clock.find())` 的「跳过本次继续找」。
    /// 只看第一个的话，「跑慢一点，明天早上八点出发」会停在被守卫拒掉的「慢一点」上，
    /// 而真正的钟点在后面。
    private static func spokenClocks(in transcript: String) -> [VoiceClock] {
        var clocks: [VoiceClock] = []
        var cursor = transcript.startIndex
        while let range = transcript.range(of: "点", range: cursor..<transcript.endIndex) {
            cursor = range.upperBound
            guard let number = trailingNumeral(in: String(transcript[..<range.lowerBound])),
                  let minute = minuteAfterDot(transcript[range.upperBound...]) else { continue }
            clocks.append(VoiceClock(
                hour: number.value, minute: minute,
                hourStart: transcript.index(range.lowerBound, offsetBy: -number.length)
            ))
        }
        return clocks
    }

    /// 「点」后面的分钟。`nil` = 这个「点」整体不算钟点；没说分钟是 0。四选一，对齐后端 `CLOCK_TIME`：
    /// - 「半」= 30；「一刻 / 三刻」= 15 / 45（#472）。「两刻」「十一刻」这类不认的刻数**整体不匹配**
    ///   （后端 `(?!\d*刻)`），不是只取「N点」—— 此前「八点一刻」就是这样被静默读成 08:00。
    /// - 「N点M分」：M 是 0~59，且「分」后面不是「钟」（#864）—— 「八点四十分钟」是 8 点跑 40 分钟。
    /// - 「N点MM」不带「分」：必须是两位数，后面是句末、标点或 `bareMinuteFollowers` 才算（#864）——
    ///   「八点十号线」「八点二十路」「八点45号门」是 8:00。白名单而不是黑名单：后面接的东西列不完。
    /// - 都不是：整点。认不准就不认，落回整点。
    ///
    /// 「几位数」按后端归一化之后算：「四十」= `40` 两位，「五」「零五」= `5` 一位。
    private static func minuteAfterDot(_ afterDot: Substring) -> Int? {
        if afterDot.first == "半" { return 30 }
        let numeral = afterDot.prefix(while: { numeralCharacters.contains($0) }).prefix(3)
        let rest = afterDot.dropFirst(numeral.count)
        if rest.first == "刻" {
            switch numeral {
            case "一", "1": return 15
            case "三", "3": return 45
            default: return nil
            }
        }
        guard !numeral.isEmpty, let value = chineseNumberValue(String(numeral)), value <= 59 else { return 0 }
        let digitCount = numeral.allSatisfy(\.isASCII) ? numeral.count : String(value).count
        if rest.first == "分", rest.dropFirst().first != "钟", digitCount <= 2 { return value }
        if digitCount == 2, followsBareMinute(rest) { return value }
        return 0
    }

    /// 后端 `BARE_MINUTE_FOLLOWED_BY` 里除句末、空白、标点以外的那些词（#864 独立审查 A1）。
    private static let bareMinuteFollowers = [
        "出发", "开始", "跑", "集合", "见", "吧", "啊", "呀", "呢", "从", "在", "去", "到", "再",
        "左右", "前后", "的", "那", "我"
    ]

    private static func followsBareMinute(_ rest: Substring) -> Bool {
        guard let next = rest.first else { return true }
        return next.isPunctuation || " \t\n\r\u{0B}\u{0C}".contains(next) || bareMinuteFollowers.contains { rest.hasPrefix($0) }
    }
}
