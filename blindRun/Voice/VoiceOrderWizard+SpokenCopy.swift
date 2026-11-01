import Foundation

/// 向导念给用户的几句固定文案（读回前的提示、缺关键槽位时的结尾）。
/// 从 `VoiceOrderWizard.swift` 挪出来：那个文件超了 SwiftLint 行数上限，只许变短（#558）。
extension VoiceOrderWizard {
    static let missingStartTimeMessage =
        "还没听到你说预约时间，现在不能下单。直接说时间就行，比如「明天早上八点」；要整句重说就说「重说」。"
    /// 说一个地点会走确认轮的后端解析，地名落进 `current` 后读回重念（`handleConfirmViaBackend` 末尾）。
    static let missingStartPointMessage =
        "出发地点还没有确定，现在不能下单。请直接说出发地点，比如「从人民广场出发」。"

    /// 说得超过后端的大模型字数线时，读回前先说的那一句。
    ///
    /// **不做客户端截断**（`design.md` D4）：截断是无声的信息丢失，而丢的必然是句子后半段 ——
    /// 「我有低血糖，如果我说头晕请马上停下来扶我坐到路边」里要执行的那半句正好在后半段。
    /// 静默取整已经被判过一次「对听不见屏幕的人等于篡改」，这是同一类问题的更严重版本。
    ///
    /// 措辞的两条约束，与 `startAddressUnresolvedNotice` 同源：
    /// **说清楚是「太长没记全」而不是「没听见」**（我们听见了），
    /// 以及**给出唯一的出路**（说短一点重说）。不列举具体丢了哪几项 ——
    /// 读回紧接着就会把记下的念一遍，用户自己听得出缺什么，而读回本来就要 15~25 秒。
    static func longUtteranceNotice(forCharacterCount count: Int) -> String? {
        guard count > ParseVoiceOrderRequest.modelFallbackCharacterLimit else { return nil }
        return "这句话超过 \(ParseVoiceOrderRequest.modelFallbackCharacterLimit) 个字，"
            + "我只能按关键词记，终点和备注可能没记下。缺了就说「重说」，讲短一点。"
    }

    /// 听见了地名却没查到时，读回前先说的那一句。
    ///
    /// 措辞的两条约束：**说清楚「没找到」而不是「没听到」**（我们听到了，是查不到），
    /// 以及**说清楚起点现在是什么**（不说的话用户得从后面那句 `startPointSummary` 里自己推）。
    static let startAddressUnresolvedNotice =
        "没找到你说的那个地点，出发地先按当前位置来，要改就说「重说」。"
    /// 当前位置也用不了（定位被拒、精确位置关闭、还没定到）时不许说「先按当前位置来」：
    /// 读回紧接着会说「出发地点还没有确定」，两句自相矛盾（#558）。
    /// 用户选过地点（含首页设的默认地点）时起点不是当前位置，不能说「按当前位置来」。
    static func unresolvedStartNotice(hasFallback: Bool, isChosenPlace: Bool = false) -> String {
        guard hasFallback else { return "没找到你说的那个地点。" }
        return isChosenPlace ? "没找到你说的那个地点，出发地先按你选的地点来，要改就说「重说」。" : startAddressUnresolvedNotice
    }

    /// 整句解析失败时先说的那句话。
    ///
    /// 措辞上的三条约束：
    /// - **不说「网络」**。404、超时、鉴权过期表现相同，客户端分不出来，断言原因就是编。
    /// - **不说「没听到」**。ASR 是成功的，紧接着的「我听到你说：⋯⋯」会念出原话，说没听到自相矛盾。
    ///   失败的是把原话转成预约内容这一步。
    /// - **不给指令**。读回结尾那句「要改就说『改地点』⋯⋯」已经把出路说全了，再说一遍只是把
    ///   本就 15~25 秒的读回拖得更长。
    static let parseFailureNotice = "这次没能把你说的话转成预约内容，下面念的是默认值。"

    /// 「这个接口在服务端根本不存在」——**重说多少遍都不会变好**，与「没听懂」必须分开。
    ///
    /// 上面 `parseFailureNotice` 那三条措辞约束（不说网络、不说没听到、不给指令）针对的是
    /// **偶发**失败。端点未部署不是偶发，它是常态，而对它说「下面念的是默认值」等于邀请用户
    /// 再试一次 —— 试一万次也一样。所以这一路单独播、并且直接交回表单。
    static let parseUnavailableNotice = "语音下单暂时用不了，"

    /// 确认轮网络失败时说的那句话。
    ///
    /// 三条约束与 `parseFailureNotice` 同源（不说网络、不说没听到、不编原因），
    /// 但**必须把本地还能用的那两条出路念出来** —— 网络断着的时候它们是仅存的通路。
    static let confirmRoundNetworkFailureNotice =
        "这次没能听明白你想改什么。说「确认」就按刚才念的下单，说「重说」重新说一遍。"

    static let cancelledReason = "已取消这次语音下单"
    /// 文案取自后端 #502 的提议，负责人 2026-10-05 确认。**不提表单**：用户是想退出，不是想填表。
    static let cancelledMessage = "\(cancelledReason)。"
    static let notUnderstoodMessage = "暂时没听清，你可以稍后再试，或者让身边的人帮忙。"
}
