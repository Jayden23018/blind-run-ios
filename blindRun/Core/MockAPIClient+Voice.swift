//
//  MockAPIClient+Voice.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 语音下单 分段。行为零改动，只改文件位置。
//

import CoreLocation
import Foundation

extension MockAPIClient {

    // MARK: - Voice Order Handlers

    /// `POST /api/orders/voice/parse`。整句一次抽三槽，抽不出的进 `missing`。
    ///
    /// **抽不出不是错误**：和另外两个语音端点一样走 200 + `needReask`，Mock 把这一点做错，
    /// 向导就会在开发期被当成错误分支调通、上真机才发现走不通。
    /// 地点匹配沿用 `handleVoiceResolveAddress` 的同一份关键词表与带坐标排序 —— Mock 不许比线上松。
    func handleVoiceParseOrder(body: (any Encodable & Sendable)?) throws -> ParseVoiceOrderResponse {
        guard mockToken != nil else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(ParseVoiceOrderRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let transcript = request.transcript.trimmed
        let current = request.current
        // 既有的地点匹配helper按坐标就近排序，签名收 `ResolveAddressRequest`。
        // 两个请求体在坐标这两项上逐字相同，转一次比把签名改成协议便宜。
        let near = ResolveAddressRequest(
            transcript: transcript, latitude: request.latitude, longitude: request.longitude
        )

        // MARK: 本轮抽到了什么
        let place = Self.matchedVoicePlace(in: transcript, near: near)
        // 同名候选。**只在本轮真的抽到起点时才算** —— 起点从 `current` 继承来的那几轮不该
        // 重新弹一次消歧：用户上一轮已经挑过了，再问一遍是把他刚做的选择当没发生。
        let startCandidates = place == nil
            ? []
            : Self.matchedVoiceCandidates(in: transcript, near: request)
        let endPlace = Self.matchedVoiceEndPlace(in: transcript, near: near, startSpan: Self.mockVoiceAddressSpan(in: transcript))
        let startTime = Self.mockVoiceStartTime(in: transcript)
        let minutes = Self.mockVoiceMinutes(in: transcript).flatMap { (10...300).contains($0) ? $0 : nil }
        let guideDog = Self.mockVoiceGuideDog(in: transcript)
        let pace = Self.mockVoicePace(in: transcript)
        let notes = Self.mockVoiceSpecialNotes(in: transcript)

        // MARK: 与 `current` 合并 —— 本轮抽到的覆盖，没抽到的继承
        //
        // 口径抄后端 `frontend-guide.md`「本轮正则 > 本轮模型 > `current`」。
        // 起点三元组**整体覆盖或整体继承**，绝不拼出「新地址 + 旧坐标」—— 那会把人约到
        // 一个名字对、坐标错的地方，而读回只念名字，盲人一个字都听不出来。
        let mergedStartTime = startTime.map(Self.mockBackendLocalDateTime) ?? current?.plannedStartTime
        let mergedMinutes = minutes ?? current?.durationMinutes
        // 起点：本轮抽到就三项一起用本轮的，没抽到就三项一起继承。`matchedVoicePlace` 只会返回
        // 带坐标的结果，所以起点不存在「有地名没坐标」的半状态。
        // 平铺三项 = 候选第一项（契约：「我们的最佳猜测」，老客户端只读平铺字段也能下单）。
        // 有候选时用候选的 `readbackAddress`，否则用表里的完整地址 —— 前者才是后端
        // `readback(AddressCandidate)` 的形态，「挑第一个」和「挑第二个」必须拼出同一种串。
        let bestCandidate = startCandidates.first
        let mergedAddress = bestCandidate?.readbackAddress ?? place?.address ?? current?.address
        let mergedLatitude = bestCandidate?.latitude ?? place?.latitude ?? current?.latitude
        let mergedLongitude = bestCandidate?.longitude ?? place?.longitude ?? current?.longitude
        // 终点：本轮抽到地名但查不到坐标时**绝不能继承上一轮的坐标** —— 那会拼出
        // 「新地名 + 旧坐标」，名字对、位置错，而读回只念名字，盲人一个字都听不出来。
        let mergedEndAddress = endPlace?.address ?? current?.endAddress
        let mergedEndLatitude = endPlace?.place?.latitude ?? (endPlace == nil ? current?.endLatitude : nil)
        let mergedEndLongitude = endPlace?.place?.longitude ?? (endPlace == nil ? current?.endLongitude : nil)
        let mergedGuideDog = guideDog ?? current?.hasGuideDog
        let mergedPace = pace ?? current?.pacePreference
        // 备注与另外两个可选槽位同一口径：本轮抽到就覆盖，没抽到就继承 ——
        // 用户第二轮只说「时间改成九点」时，第一轮说的身体状况不该被擦掉。
        let mergedNotes = notes ?? current?.specialNotes

        // MARK: missing 按**合并后**的状态算
        //
        // ⚠️ 起点判据是**坐标**而不是地名（`api_spec.yaml` 的 `VoiceSlotSnapshot` 说明）：
        // 「有地址无坐标」下不了单，但那是靠 missing 拦，不是靠请求校验拦。
        var missing: [VoiceOrderMissingSlot] = []
        if mergedLatitude == nil { missing.append(.address) }
        if mergedStartTime == nil { missing.append(.startTime) }
        if mergedMinutes == nil { missing.append(.duration) }

        // MARK: 确认轮的表态与定点修改
        //
        // 两者都**只在带了 `current` 时可能非 null**（契约：没带 current 时恒为 null）。
        let intent = current == nil ? nil : Self.mockVoiceUserIntent(in: transcript, missingIsEmpty: missing.isEmpty)
        // 本轮抽到了任何新值就不是「点名没给值」。契约：给了新值 `correctionTarget` 与
        // `userIntent` 都为 null（「对，但时间改成九点」是修正不是确认）。
        let broughtNewValue = startTime != nil || minutes != nil || place != nil
            || endPlace != nil || guideDog != nil || pace != nil
        let correctionTarget: VoiceCorrectionTarget? = (current == nil || intent != nil || broughtNewValue)
            ? nil
            : Self.mockVoiceCorrectionTarget(in: transcript)
        // 只说了「不对」、既没表态也没点名也没给值。
        let correctionUnclear = current != nil && intent == nil && correctionTarget == nil
            && !broughtNewValue && Self.mockVoiceIsPlainNegation(transcript)

        // `needReask` 与 `missing` **双向解耦**（契约 2026-08-09）。这一行曾经写成
        // `!missing.isEmpty`，注释里挂着「接 `current` 时要一起改」—— 现在有三个反例：
        // `CANCEL` 时 missing 可能非空而不该再收音；`correctionTarget` / `correctionUnclear`
        // 时 missing 为空却必须再收一次。
        let needReask: Bool
        switch intent {
        case .confirm, .cancel:
            needReask = false
        case .restart, .repeatBack:
            needReask = true
        default:
            needReask = startCandidates.count >= 2
                || correctionTarget != nil || correctionUnclear || !missing.isEmpty
        }

        // 「说了地名、但我们没查到」。
        //
        // 判据是**抽到了 span 却没落成起点**，与后端同批那条改动对齐：带了坐标却一个候选都搜不到时
        // 不再回落全国范围的正向编码（那条路曾把深圳说的地名解析到海南），直接报 true 走追问。
        // 客户端据此在读回里说清楚，而不是静默落回「当前位置」—— 后者就是把人约到错误的起点。
        let addressUnresolved = mergedLatitude == nil
            && Self.mockVoiceAddressSpan(in: transcript) != nil

        return ParseVoiceOrderResponse(
            plannedStartTime: mergedStartTime,
            durationMinutes: mergedMinutes,
            address: mergedAddress,
            latitude: mergedLatitude,
            longitude: mergedLongitude,
            missing: missing,
            needReask: needReask,
            ttsText: Self.mockVoiceTtsText(
                intent: intent,
                candidates: startCandidates,
                correctionTarget: correctionTarget,
                correctionUnclear: correctionUnclear,
                missing: missing
            ),
            addressShort: Self.mockVoiceAddressShort(mergedAddress),
            endAddress: mergedEndAddress,
            endAddressShort: Self.mockVoiceAddressShort(mergedEndAddress),
            endLatitude: mergedEndLatitude,
            endLongitude: mergedEndLongitude,
            // 契约说它恒等于「有地名且没坐标」，且**按本次响应的最终状态算，不是按本轮抽到了什么**
            // （后端 N39 修正）—— 终点三元组会从 `current` 跨轮继承。这里照定义算，别另起一套。
            endAddressUnresolved: mergedEndAddress == nil ? nil : (mergedEndLatitude == nil),
            hasGuideDog: mergedGuideDog,
            pacePreference: mergedPace,
            // 备注只由大模型在必填槽位兜底那次顺带抽，正则不抽（语料 `_extra_slots_note`）。
            // 曾经因此恒为 nil，代价是「原文照录」这条规格在开发期永远走不到 ——
            // 现在由 `mockVoiceSpecialNotes` 按原话**取子串**产出，并复现超字数线时的降级。
            specialNotes: mergedNotes,
            userIntent: intent,
            correctionTarget: correctionTarget,
            correctionUnclear: correctionUnclear,
            // 没歧义时是**空数组不是 null**（契约明说），客户端按 `count >= 2` 判这一轮是不是消歧轮。
            candidates: startCandidates,
            addressUnresolved: addressUnresolved
        )
    }

    /// `addressShort` / `endAddressShort` 的 Mock 口径：取 POI 名，即第一个空格之前那一段。
    ///
    /// 镜像后端的两条规则（`api_spec.yaml:3026-3041`）：
    /// - 完整地址形如 `五角场市场监督管理所 国定路335号1号楼4层(...)` → `五角场市场监督管理所`
    /// - 正向地理编码回落给的 `上海市黄浦区人民广场` **不带 POI 名分隔**，此时**等于** `address`
    ///
    /// 与 `AddressCandidate.readbackAddress` 是同一条拼法的反向操作（那边 `name + " " + address`），
    /// 所以候选消歧挑定之后两条路得到的朗读形态一致。
    ///
    /// ponytail: 按空格切就够，不去猜门牌号的正则。后端真实实现更复杂，但 Mock 的职责是
    /// 让「读回念的是短名」这条链路在离线时走得到，不是复刻高德的地址格式。
    static func mockVoiceAddressShort(_ address: String?) -> String? {
        guard let address = address?.nilIfBlank else { return nil }
        guard let head = address.split(separator: " ", maxSplits: 1).first else { return address }
        return String(head)
    }

    /// 确认轮的表态判定。**逐字转写**后端 `VoiceSlotParser` 的五条正则与判定顺序
    /// （`demo/src/main/java/com/example/demo/util/VoiceSlotParser.java:187-308`）。
    ///
    /// 转写而不是自己写一套，理由与整个 Mock 一致：**Mock 不许比线上松也不许比线上紧**。
    /// 客户端的本地直通表要求是这份正则的子集，Mock 若比它松，那条子集关系在开发期就验不出来。
    /// 真正的对撞由 `scripts/validate-voice-intent-words.mjs` 直接读 Java 源码做，这里只保证
    /// 开发期跑通的分支和线上是同一批。
    ///
    /// 后端还有一路大模型识别，Mock 没有 —— 所以方言与长句在 Mock 里会落到 `nil`，
    /// 与「模型不可用」时的线上行为一致，不是漏实现。
    static func mockVoiceUserIntent(in transcript: String, missingIsEmpty: Bool) -> VoiceUserIntent? {
        let text = transcript.trimmed
        guard !text.isEmpty else { return nil }
        // 判定顺序有意义，别调换：
        // ① CANCEL 先判 ——「算了不下了」里也有个「了」。
        // ② REPEAT 必须在 RESTART **之后** ——「重新说一遍」两条都命中，而它是 RESTART。
        // ③ NOT_CONFIRM 必须在 CONFIRM 之前 ——「不对」含「对」，不先挡就会被判成确认→直接下单。
        if Self.mockVoiceIntentCancel.contains(where: text.contains)
            || Self.mockVoiceBareCancel.contains(Self.mockVoiceStripTrailingParticles(text)) {
            return .cancel
        }
        if Self.mockVoiceIntentRestart.contains(where: text.contains) { return .restart }
        if Self.mockVoiceIntentRepeat.contains(where: text.contains) { return .repeatBack }
        if Self.mockVoiceIntentNotConfirm.contains(where: text.contains) { return nil }
        guard Self.mockVoiceIntentConfirm.contains(where: text.contains)
                || Self.mockVoiceBareConfirm.contains(Self.mockVoiceStripTrailingParticles(text)) else {
            return nil
        }
        // ⚠️ `CONFIRM` 只在 `missing` 为空时出现：槽位没齐就无从确认，那时用户说「对」
        // 多半是没听清追问。`CANCEL`/`RESTART`/`REPEAT` 不受此限 —— 被卡住的人最需要那几个出口。
        return missingIsEmpty ? .confirm : nil
    }

    // 以下五组逐字对应后端的 `INTENT_*` 正则（`VoiceSlotParser.java:187-262`）。
    // 后端用 `Matcher.find()`（子串命中），所以这里也是 `contains`。
    private static let mockVoiceIntentCancel = [
        "算了", "不下单", "不下了", "不订了", "不跑了", "别下单", "别下了", "不要了",
        "取消订单", "取消下单", "放弃"
    ]
    /// 后端 `^\s*取消[吧了]?\s*$` —— 光秃秃的「取消」只在**整句就是它**时才算数：
    /// 「把导盲犬取消」是改一项，判成 CANCEL 会让用户的整单凭空消失。
    private static let mockVoiceBareCancel: Set<String> = ["取消", "取消吧", "取消了"]
    private static let mockVoiceIntentRestart = [
        "重新说", "重新来", "重新开始", "重来", "从头再来", "从头说"
    ]
    /// ⚠️ 「再说一遍 / 再说一次」在**这一组**，不在 RESTART —— 中文里那是「你把刚才那句重复一次」，
    /// 盲人没听清读回时最自然的请求。判成重来会把他刚说完的一整句清空。
    private static let mockVoiceIntentRepeat = [
        "再说一遍", "再说一次", "再念一遍", "再念一次", "再读一遍", "再播一遍",
        "重复一遍", "重复一下", "重复一次",
        "没听清", "没听见", "没听到", "刚才说啥", "刚才说什么", "你说啥", "说的啥", "再讲一遍"
    ]
    /// 否定/不满 —— 命中返回 nil（=没有表态），交给 `correctionTarget` / `correctionUnclear` 那条路。
    private static let mockVoiceIntentNotConfirm = [
        "不对", "不太对", "不是", "不行", "不可以", "不好", "先不", "错了", "有问题", "等一下", "等等"
    ]
    private static let mockVoiceIntentConfirm = [
        "没问题", "就这样", "就这么", "可以了", "下单吧", "直接下单", "开始吧",
        "确认", "是的", "对的", "行吧", "行了", "可行", "OK", "ok", "Ok"
    ]
    /// 后端的三条 `^…$` 锚定模式：裸「对」算确认，裸「好」**不算**（要带后缀），裸「可以」算。
    /// 两者刻意不对称 ——「好」是中文最强的话语标记（「好，那我们…」），旁人对话里出现时多半
    /// 不是在回答问题；而读回句以「对吗？」结尾，「对」是它唯一的自然答句。
    private static let mockVoiceBareConfirm: Set<String> = [
        "对", "对的", "对了", "对吧", "对呀", "对啊",
        "好的", "好了", "好吧", "好呀", "好啊",
        "可以"
    ]

    /// 后端那三条锚定模式允许的句尾语气词与标点。
    private static func mockVoiceStripTrailingParticles(_ text: String) -> String {
        var stripped = text
        while let last = stripped.last, "。！!？? ".contains(last) {
            stripped.removeLast()
        }
        return stripped
    }

    /// 用户点名要改哪一项、但没给新值。
    ///
    /// ⚠️ **这是刻意的粗近似**：线上这一路纯靠大模型（与终点抽取同一次调用），没有正则实现，
    /// 所以不存在可以逐字转写的后端源码。这里只覆盖最直白的说法，够开发期把
    /// 「播定向追问 → 再收一次音 → 新值覆盖」这条链路跑通即可。
    /// 模型不可用时线上恒为 null 并退回消歧问句 —— Mock 认不出来时的表现与那一档一致。
    static func mockVoiceCorrectionTarget(in transcript: String) -> VoiceCorrectionTarget? {
        // 必须先确认用户在说「改」这件事，否则「时间」两个字出现在任何句子里都会命中。
        let changeWords = ["改", "换", "错了", "不对"]
        guard changeWords.contains(where: transcript.contains) else { return nil }
        // 顺序有意义：终点的说法里含「地点」，起点那条放后面会被它吃掉。
        if ["终点", "结束地点", "跑到哪", "目的地"].contains(where: transcript.contains) { return .endAddress }
        if ["起点", "出发", "地点", "地方"].contains(where: transcript.contains) { return .startAddress }
        if ["时间", "几点", "点钟"].contains(where: transcript.contains) { return .startTime }
        if ["时长", "跑多久", "多长时间"].contains(where: transcript.contains) { return .duration }
        if ["导盲犬", "狗"].contains(where: transcript.contains) { return .guideDog }
        if ["配速", "快慢"].contains(where: transcript.contains) { return .pace }
        if ["备注", "说明"].contains(where: transcript.contains) { return .notes }
        return nil
    }

    /// 只说了「不对」这类否定、既没点名也没给值。
    static func mockVoiceIsPlainNegation(_ transcript: String) -> Bool {
        Self.mockVoiceIntentNotConfirm.contains(where: transcript.contains)
    }

    /// 五个分支的文案，优先级即契约里那一串（`api_spec.yaml` 的 `ttsText` 说明）。
    /// ⚠️ `CANCEL`/`RESTART` 排在 `missing` **之前**：用户被卡在追问里说「算了」，
    /// 再回他一句「没听清出发地点」就是把人锁死。
    private static func mockVoiceTtsText(
        intent: VoiceUserIntent?,
        candidates: [AddressCandidate],
        correctionTarget: VoiceCorrectionTarget?,
        correctionUnclear: Bool,
        missing: [VoiceOrderMissingSlot]
    ) -> String {
        switch intent {
        case .cancel: return "已取消"
        case .restart: return "好的，我们重新来"
        case .repeatBack: return "好的，我再念一遍"
        case .confirm: return "好的，这就为您下单"
        default: break
        }
        // ⚠️ **候选消歧排在 `missing` 追问之前**（契约 `api_spec.yaml` 明说）：候选是本轮算出来的，
        // 先追问时间的话，下一轮用户只说时间、抽不到地名，这批候选就永远消失、
        // 起点被静默取成第一条 —— 正是这批改动要消灭的那个失败。
        if candidates.count >= 2 {
            return mockCandidateTts(candidates)
        }
        if !missing.isEmpty {
            return "还差\(missing.count)项没听清，可以再说一次"
        }
        if let correctionTarget {
            return "好的，请说新的\(Self.mockVoiceCorrectionTargetName(correctionTarget))"
        }
        if correctionUnclear {
            return "您想改哪一项？出发地、开始时间，还是时长？"
        }
        return "好的，我记下了"
    }

    private static func mockVoiceCorrectionTargetName(_ target: VoiceCorrectionTarget) -> String {
        switch target {
        case .startAddress: return "出发地点"
        case .endAddress: return "结束地点"
        case .startTime: return "开始时间"
        case .duration: return "时长"
        case .guideDog: return "导盲犬安排"
        case .pace: return "配速偏好"
        case .notes: return "备注"
        case .unknown: return "内容"
        }
    }

    /// `POST /api/orders/voice/resolve-address`。`needReask` 是 **200 的正常业务状态**，
    /// 所以这里返回的是成功响应体而不是 `APIError` —— Mock 把这一点做错，向导就会在开发期被
    /// 当成错误分支调通、上真机才发现走不通。
    func handleVoiceResolveAddress(body: (any Encodable & Sendable)?) throws -> ResolveAddressResponse {
        guard mockToken != nil else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(ResolveAddressRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let transcript = request.transcript.trimmed
        guard let match = Self.matchedVoicePlace(in: transcript, near: request) else {
            return ResolveAddressResponse(
                address: nil,
                latitude: nil,
                longitude: nil,
                needReask: true,
                ttsText: "没听清地点，请再说一次出发地"
            )
        }
        return ResolveAddressResponse(
            address: match.address,
            latitude: match.latitude,
            longitude: match.longitude,
            needReask: false,
            ttsText: "您是说在\(match.address)出发吗？"
        )
    }

    /// `POST /api/orders/voice/parse-slot`。时长范围（10~300）与提前量（≥30 分钟）不满足时后端也走
    /// `needReask` 而不是错误码，Mock 同样如此。
    func handleVoiceParseSlot(body: (any Encodable & Sendable)?) throws -> ParseSlotResponse {
        guard mockToken != nil else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(ParseSlotRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let transcript = request.transcript.trimmed
        switch request.field {
        case .startTime:
            guard let startTime = Self.mockVoiceStartTime(in: transcript) else {
                return ParseSlotResponse(
                    plannedStartTime: nil,
                    durationMinutes: nil,
                    needReask: true,
                    ttsText: "没听清开始时间，请再说一次，比如“明天早上八点”"
                )
            }
            return ParseSlotResponse(
                plannedStartTime: Self.mockBackendLocalDateTime(startTime),
                durationMinutes: nil,
                needReask: false,
                // 读回念实际落点，不再恒说「明天」—— 说「今天八点半」却被念成明天，
                // 对听不见屏幕的人就是改了他的预约。
                ttsText: "好的，\(DateFormatter.aidRunDisplayDateTime.string(from: startTime))"
            )
        case .duration:
            guard let minutes = Self.mockVoiceMinutes(in: transcript), (10...300).contains(minutes) else {
                return ParseSlotResponse(
                    plannedStartTime: nil,
                    durationMinutes: nil,
                    needReask: true,
                    ttsText: "没听清时长，请再说一次，比如“一个小时”"
                )
            }
            return ParseSlotResponse(
                plannedStartTime: nil,
                durationMinutes: minutes,
                needReask: false,
                ttsText: "好的，大约\(minutes)分钟"
            )
        }
    }

    private struct MockVoicePlace {
        let keyword: String
        let address: String
        let latitude: Double
        let longitude: Double
        /// 候选播报用的 POI 名与行政区（后端 `AddressCandidate.name` / `.adname`）。
        ///
        /// **只有同名多点的条目需要填**：候选列表只在同一个关键词命中 ≥2 条时才产生，
        /// 而现有条目每个关键词只有一条，永远走不到那里。
        var poiName: String?
        var adname: String?

        init(
            keyword: String,
            address: String,
            latitude: Double,
            longitude: Double,
            poiName: String? = nil,
            adname: String? = nil
        ) {
            self.keyword = keyword
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
            self.poiName = poiName
            self.adname = adname
        }
    }

    /// 整句解析与单点解析共用同一份地点匹配 —— 两份会漂移，漂移了就等于 Mock 里两条语音路径行为不一致。
    ///
    /// 线上带坐标时走周边搜索、按距离取最近；Mock 语料太小分不出远近，这里只保留「有没有带坐标」
    /// 这一层行为差异：带了就按距离排序再匹配。真正的消歧在后端。
    private static func matchedVoicePlace(
        in transcript: String,
        near request: ResolveAddressRequest
    ) -> MockVoicePlace? {
        let candidates = request.latitude != nil && request.longitude != nil
            ? mockVoicePlaces.sorted { squaredDistance($0, request) < squaredDistance($1, request) }
            : mockVoicePlaces
        // 整句里先剥壳拿地名 span，拿不到再退回整句包含匹配（单点修改那一轮用户只说地名，没有壳）。
        let haystack = mockVoiceAddressSpan(in: transcript) ?? transcript
        return candidates.first { haystack.contains($0.keyword) }
    }

    /// 同名候选（后端 2026-08-10 新增，N48）。**只有同一个关键词命中 ≥2 条时才非空。**
    ///
    /// 先用 `matchedVoicePlace` 定下命中的是哪个关键词，再收同名的那几条 —— 不直接
    /// 「把所有命中的条目收起来」，是因为表里有个catch-all 条目 `("公园", "本市公园")`：
    /// 「中山公园」会同时命中它和 `中山公园`，那样每个带「公园」的地名都会凭空多出一轮消歧，
    /// 而线上根本没有这回事（后端是同一个 query 搜出多个同名 POI，不是模糊包含）。
    ///
    /// ⚠️ **带了坐标才有候选**：没有坐标就算不出 `distanceMeters`，而缺了距离的同名列表更难选
    /// —— 这一条与后端一致（`api_spec.yaml` 的 `candidates` 字段），别在 Mock 里放宽。
    /// 上限 3 也由后端定：纯听觉且要同时理解句子时人平均只记得住约 3 项。
    private static func matchedVoiceCandidates(
        in transcript: String,
        near request: ParseVoiceOrderRequest
    ) -> [AddressCandidate] {
        guard let latitude = request.latitude, let longitude = request.longitude else { return [] }
        let near = ResolveAddressRequest(
            transcript: request.transcript, latitude: latitude, longitude: longitude
        )
        guard let best = matchedVoicePlace(in: transcript, near: near) else { return [] }
        let sameName = mockVoicePlaces
            .filter { $0.keyword == best.keyword }
            .sorted { squaredDistance($0, near) < squaredDistance($1, near) }
        guard sameName.count >= 2 else { return [] }
        return sameName.prefix(3).map { place in
            AddressCandidate(
                name: place.poiName ?? place.keyword,
                address: place.address,
                adname: place.adname,
                // 高德常常不返回商圈名，Mock 一律不给 —— 播报会退回 adname，那条分支才是常见路径。
                business: nil,
                distanceMeters: Int(
                    (CLLocation(latitude: place.latitude, longitude: place.longitude)
                        .distance(from: CLLocation(latitude: latitude, longitude: longitude)))
                        .rounded()
                ),
                latitude: place.latitude,
                longitude: place.longitude
            )
        }
    }

    /// 候选列表的播报文案。**逐字照抄后端 `VoiceOrderService.buildCandidateTts`**
    /// （`demo/.../service/VoiceOrderService.java:159-181`）—— 这段话是教用户说什么的，
    /// Mock 里念得跟线上不一样，开发期练熟的说法上真机就不生效。
    private static func mockCandidateTts(_ candidates: [AddressCandidate]) -> String {
        var text = "找到\(candidates.count)个地点，请说第几个。"
        for (index, candidate) in candidates.enumerated() {
            text += "\(VoiceOrderWizard.ordinalWords[index])，\(candidate.name)"
            if let area = (candidate.business?.nilIfBlank ?? candidate.adname?.nilIfBlank) {
                text += "，\(area)"
            }
            if let distance = candidate.distanceMeters {
                text += "，距您\(mockDistanceText(distance))"
            }
            text += "。"
        }
        return text
    }

    /// 照抄后端 `formatDistance`：裸念「距您48000米」听不出量级，超 1 公里换单位。
    private static func mockDistanceText(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f公里", Double(meters) / 1000) : "\(meters)米"
    }

    /// 从整句里剥出地名 span。取值与语料里 `field: "ADDRESS"` 的 9 条一致。
    ///
    /// **只断言抽取，不断言地理编码**（语料 `_address_note`）：抽出「五角场」「我家楼下」而
    /// `mockVoicePlaces` 里查不到坐标，是线上「抽到 span 但正向编码失败」的同形场景，
    /// 结果就该是 `missing` 含 `ADDRESS`，而不是当成用户没说起点。
    static func mockVoiceAddressSpan(in transcript: String) -> String? {
        guard let match = transcript.firstMatch(of: addressSpanRegex),
              let span = match.output[1].substring.map(String.init)?.trimmed,
              !span.isEmpty else { return nil }
        // 壳抽出来的不一定是地名：「从明天早上八点开始跑」的壳内是时间片。
        // 送去正向地理编码要么返空、要么错命中，后者会让盲人确认到错地方 ——
        // 所以宁可误杀（多走一次兜底，结果仍对），也不漏杀。
        guard span.firstRange(of: timeLikeRegex) == nil else { return nil }
        return span
    }

    /// 逐字照抄后端 `VoiceSlotParser.ADDRESS_SPAN`（`demo/.../util/VoiceSlotParser.java:52`）。
    ///
    /// 此前这里是手列的 4 对壳（`从-出发` / `在-集合` / `在-跑步` / `到-那边`），
    /// 而后端是 4 个前缀 × 9 个后缀的叉积。手列必然漏：语料
    /// 「明天早上8:00从阳光棕榈园跑」的壳是 `从…跑`，四对里一对都不中，Mock 抽不出起点。
    /// 抄整条正则而不是补一对，是因为补一对下次还会漏 —— 叉积穷举不进人脑。
    ///
    /// 非贪婪 `{2,15}?` 与「span 内不含标点空格」都是后端的原样约束，别顺手放宽。
    private static let addressSpanRegex = try! Regex(
        "(?:从|在|去|到)([^，,。！？!?\\s]{2,15}?)(?:出发|集合|等我|见面|开始|跑|附近|那边|旁边)"
    )

    /// Mock 抽出来的终点：地名一定有，坐标查得到才有。
    private struct MockVoiceEndPlace {
        let address: String
        /// `nil` = 地名抽到了但 `mockVoicePlaces` 里查不到坐标，对应线上
        /// `endAddressUnresolved = true`。
        let place: MockVoicePlace?
    }

    /// 从整句里剥出**终点**地名。
    ///
    /// ponytail: 这是给 Demo / 开发期用的启发式，**不是契约的镜像**。线上终点只由大模型抽
    /// （`api_spec.yaml:2846`：「终点只由大模型定位，没有正则链路」），百炼不可用时后端的终点恒为
    /// null。Mock 没有模型，完全不抽的话终点这条链路在真机之前一次都走不到 —— 读回文案、
    /// 「未定位到」降级、志愿者详情那一行全部无从验证。上限：**它比线上的正则降级松，
    /// 但不比线上的完整行为松**；哪天后端给终点加了正则实现，这里要照抄那条正则，不是继续维护本函数。
    ///
    /// **只认 `跑到` 前缀，不认裸 `到`** —— 这条被语料钉死：
    /// 「明天早上8:00到五角场跑四十分钟」的期望是 **ADDRESS（起点）= 五角场**，
    /// 裸 `到` 会把同一段文字同时当成起点和终点，正是后端 2026-08-09 修掉的 N38。
    static func mockVoiceEndSpan(in transcript: String) -> String? {
        guard let match = transcript.firstMatch(of: endSpanRegex),
              let span = match.output[1].substring.map(String.init)?.trimmed,
              !span.isEmpty else { return nil }
        // 与起点同一条防线：壳内是时间片时（「跑到八点」）送去地理编码只会错命中。
        guard span.firstRange(of: timeLikeRegex) == nil else { return nil }
        return span
    }

    /// 终点 = 抽到的终点 span + （可选）坐标。
    ///
    /// - Parameter startSpan: 本句抽到的起点 span。**与终点相同就整个丢弃终点** ——
    ///   同一段文字不可能既是起点又是终点，后端遇到这种重叠也是两个都丢（N38）。
    ///   丢掉的是终点而不是起点：起点有默认值（当前位置）能兜住，终点没有。
    private static func matchedVoiceEndPlace(
        in transcript: String,
        near request: ResolveAddressRequest,
        startSpan: String?
    ) -> MockVoiceEndPlace? {
        guard let span = mockVoiceEndSpan(in: transcript) else { return nil }
        guard span != startSpan else { return nil }
        let candidates = request.latitude != nil && request.longitude != nil
            ? mockVoicePlaces.sorted { squaredDistance($0, request) < squaredDistance($1, request) }
            : mockVoicePlaces
        return MockVoiceEndPlace(address: span, place: candidates.first { span.contains($0.keyword) })
    }

    /// 终点壳。`跑到` 之后到标点或句尾为止 —— 与起点那条不同，终点没有「出发 / 集合 / 那边」
    /// 这类后缀词可依赖（「跑到五角场」后面直接就是逗号）。
    private static let endSpanRegex = try! Regex(
        "跑到([^，,。！？!?\\s]{2,15})(?:[，,。！？!?]|$)"
    )

    /// 逐字照抄后端 `VoiceSlotParser.TIME_LIKE`（`VoiceSlotParser.java:63`）。
    ///
    /// `\d{1,2}[:：][0-5]\d` 那一段是 2026-08-08 后端 PR #14 补的：只认「点」时，
    /// 「从8:00开始跑」的 span 抽出来是 `8:00`，判不出是时间就当地名送高德了。
    private static let timeLikeRegex = try! Regex(
        "[0-9零一二两三四五六七八九十半]\\s*(?:点|分|小时|分钟)|\\d{1,2}[:：][0-5]\\d"
            + "|明天|后天|今天|上午|下午|早上|晚上|中午"
    )

    /// 是否携带导盲犬。`nil` = 原话没提，与 `false`（本次明确不带）语义不同 ——
    /// 这个字段进派单硬过滤，两者混淆会让登记了导盲犬的用户被静默按「不带」派单。
    static func mockVoiceGuideDog(in transcript: String) -> Bool? {
        guard transcript.contains("导盲犬") else { return nil }
        // 🔴 **正反问句先判，命中就返回 nil。** 「带不带导盲犬改一下」是用户在**点名要改这一项**，
        // 不是在答。它同时长得像肯定和否定（「带不带导盲犬」里既有「不带导盲犬」也有「带…导盲犬」），
        // 所以**只挡一边没用**：后端 2026-08-09 实测给否定加前置守卫之后，肯定那条立刻从
        // 第二个「带」字重新匹配上，值从 false 翻成 true，一样是凭空造的（语料 `_guide_dog_question_note`）。
        //
        // 判错的后果不对称且不可见：档案里登记了导盲犬的用户被静默按「不带」派单，
        // 这个字段进派单硬过滤，候选池被无声缩放，盲人全程听不出来。
        // 语音的定点修改会**主动引导用户说出这类点名句**（`correctionTarget=GUIDE_DOG`），
        // 所以它不是边角情况。
        if transcript.firstRange(of: guideDogQuestionRegex) != nil { return nil }
        // 否定式必须先判，否则「不带导盲犬」会被「带导盲犬」吃掉。
        if transcript.contains("不带") || transcript.contains("没带") || transcript.contains("没有带") {
            return false
        }
        return true
    }

    /// 逐字照抄后端 `VoiceSlotParser.GUIDE_DOG_QUESTION`。
    private static let guideDogQuestionRegex = try! Regex(
        "(?:带不带|用不用|需不需要|要不要)[^，,。！？!?]{0,4}(?:导盲犬|狗)"
    )

    /// 配速偏好。`nil` = 原话没提，下单时不传即回落档案默认配速。
    static func mockVoicePace(in transcript: String) -> PacePreference? {
        if transcript.contains("走跑结合") { return .walkRun }
        if transcript.contains("慢一点") || transcript.contains("慢点") || transcript.contains("轻松") {
            return .easy
        }
        if transcript.contains("快一点") || transcript.contains("快点") { return .fast }
        if transcript.contains("中等") { return .moderate }
        return nil
    }

    /// 本次备注 —— **从原话里取子串，绝不重新组织语言**。
    ///
    /// 在此之前这个槽位在 Mock 里恒为 nil，于是「原文照录」（`design.md` D1）这条规格
    /// **在开发期永远验不到**：开发和 UI 测试都走 Mock，走不到自由文本分支就等于这条规格
    /// 从来没被执行过。而它是本变更里唯一关系到「志愿者会读到什么」的规格。
    ///
    /// 实现刻意只做子串截取而不做任何归纳：Mock 一旦自己编一句话出来，
    /// 「非 null 时保证是用户原话的子串」这条契约在 Mock 下就是假的，
    /// 而假的 Mock 比没有 Mock 更糟 —— 它让人以为验过了。
    static func mockVoiceSpecialNotes(in transcript: String) -> String? {
        // 超字数线时后端跳过大模型，而备注「只在触发大模型兜底那次顺带抽，正则不抽」
        // （`api_spec.yaml` 的 `specialNotes` 说明）。Mock 必须复现这个降级，
        // 否则开发期看到的是「说多长都有备注」，真机上却没有 —— 那正是
        // `VoiceOrderWizard.longUtteranceNotice` 要提醒用户的那件事。
        guard transcript.count <= ParseVoiceOrderRequest.modelFallbackCharacterLimit else { return nil }
        guard let marker = specialNotesMarkers
            .compactMap({ transcript.range(of: $0) })
            .min(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }

        // 从标记词一路取到句尾，**不在标点处切断**：条件从句（「如果我说头晕就…」）
        // 恰恰在后半段，切了等于把要执行的那半句丢掉。
        let notes = String(transcript[marker.lowerBound...]).trimmed
        guard !notes.isEmpty, notes.count <= 200 else { return nil }
        return notes
    }

    /// 备注从哪个词开始算。按后端语料里的真实说法挑的，**不求全**——
    /// Mock 的职责是让这条分支可达，不是复刻大模型。
    private static let specialNotesMarkers = [
        "我有", "我患", "如果我", "麻烦", "注意", "另外", "提醒"
    ]

    /// 格式与后端 `LocalDateTime` 一致（无时区）。
    static func mockBackendLocalDateTime(_ date: Date) -> String {
        DateFormatter.aidRunBackendLocalDateTime.string(from: date)
    }

    #if DEBUG
    /// 语音时间解析的「现在」。设了就取代 `Date()`。
    ///
    /// 存在的理由不是「方便测试」：黄金语料（`demo/docs/voice-golden-corpus.json`）的 START_TIME
    /// 期望值是**相对 `now = 2026-07-24T10:00:00` 的绝对时间戳**，不钉住基准就没法逐条对齐，
    /// 而「过去的钟点滚次日」这条规则恰恰只有在固定基准下才验得出来。
    /// 与 `RecordingCue.observerForTesting` 是同一种接缝。
    static var voiceClockForTesting: Date?
    #endif

    private static var voiceNow: Date {
        #if DEBUG
        return voiceClockForTesting ?? Date()
        #else
        return Date()
        #endif
    }

    /// 只用于排序，不需要真实距离，所以不做球面换算。
    private static func squaredDistance(_ place: MockVoicePlace, _ request: ResolveAddressRequest) -> Double {
        guard let latitude = request.latitude, let longitude = request.longitude else { return 0 }
        let dLat = place.latitude - latitude
        let dLng = place.longitude - longitude
        return dLat * dLat + dLng * dLng
    }

    /// GCJ-02，与真实接口同坐标系。
    /// 前三条逐字对齐后端黄金语料，**不得改动**（`VoiceOrderWizardTests` 锁着）。
    ///
    /// 其余是 2026-08-06 补的手测用地点：原来只有三个关键词，说别的一律抽不出，
    /// 真机手测时表现成「说了地点但读回还是默认起点」，会被误诊成客户端 bug。
    /// Mock 只是**测试设施**，比语料宽不影响正确性判定 —— 语料那几条仍然逐条断言。
    private static let mockVoicePlaces: [MockVoicePlace] = [
        MockVoicePlace(keyword: "人民广场", address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737),
        MockVoicePlace(keyword: "天安门", address: "北京市东城区天安门广场", latitude: 39.9087, longitude: 116.3975),
        MockVoicePlace(keyword: "奥林匹克", address: "北京市朝阳区奥林匹克森林公园", latitude: 40.0026, longitude: 116.3915),
        MockVoicePlace(keyword: "世纪公园", address: "上海市浦东新区世纪公园", latitude: 31.2200, longitude: 121.5540),
        MockVoicePlace(keyword: "中山公园", address: "上海市长宁区中山公园", latitude: 31.2230, longitude: 121.4200),
        MockVoicePlace(keyword: "徐家汇", address: "上海市徐汇区徐家汇", latitude: 31.1950, longitude: 121.4370),
        MockVoicePlace(keyword: "陆家嘴", address: "上海市浦东新区陆家嘴", latitude: 31.2400, longitude: 121.5000),
        MockVoicePlace(keyword: "静安寺", address: "上海市静安区静安寺", latitude: 31.2240, longitude: 121.4450),
        MockVoicePlace(keyword: "西湖", address: "浙江省杭州市西湖", latitude: 30.2450, longitude: 120.1490),
        MockVoicePlace(keyword: "颐和园", address: "北京市海淀区颐和园", latitude: 39.9999, longitude: 116.2755),
        MockVoicePlace(keyword: "朝阳公园", address: "北京市朝阳区朝阳公园", latitude: 39.9450, longitude: 116.4800),
        MockVoicePlace(keyword: "体育中心", address: "广东省深圳市福田区深圳体育中心", latitude: 22.5480, longitude: 114.0900),
        // 同名多点 —— **唯一一组会产生候选消歧轮的条目**（后端 2026-08-10，N48）。
        //
        // 存在的理由不是「方便测试」：不造这一组，开发期与 demo 环境**永远走不到消歧轮**，
        // 那段序号播报在真机手测之前没有任何人听过，而它正是这批改动的主体。
        //
        // 选「万象城」是因为它在语料和现有用例里 0 命中，加进来不会动任何既有断言；
        // 而它在现实中确实是全国同名（深圳 / 杭州 / 沈阳都有），与要修的失败同型。
        // ⚠️ **不要改用「阳光棕榈园」** —— 那个词被 `testAddressSpanIsExtractedEvenWhenTheMockCannotGeocodeIt`
        // 反过来钉着「表里没有它」，加进去会把那条 2026-08-06 手测留下的用例弄红。
        MockVoicePlace(
            keyword: "万象城", address: "深圳湾大道", latitude: 22.5290, longitude: 113.9430,
            poiName: "万象城", adname: "南山区"
        ),
        MockVoicePlace(
            keyword: "万象城", address: "富春路", latitude: 30.2560, longitude: 120.2100,
            poiName: "万象城", adname: "江干区"
        ),
        MockVoicePlace(
            keyword: "万象城", address: "青年大街", latitude: 41.7550, longitude: 123.4300,
            poiName: "万象城", adname: "和平区"
        ),
        MockVoicePlace(keyword: "公园", address: "本市公园", latitude: 31.2304, longitude: 121.4737)
    ]

    /// 开始时间解析。取值与 `demo/docs/voice-golden-corpus.json` 里 `field: "START_TIME"`、
    /// `source: "regex"` 的 10 条用例一致，`VoiceOrderWizardTests` 锁了这份对齐。
    ///
    /// 此前这里只认 5 个钟点、且落点恒定是「明天」，10 条语料只对得上 3 条 —— 于是开发期用 Mock 说
    /// 「今天八点半」会被念成明天，说「下午三点」「半小时后」则直接走重问，**而线上这三种都解得出**。
    /// Mock 比线上严和比线上松一样有害：一个让开发期以为功能没有，一个让上真机才发现走不通。
    static func mockVoiceStartTime(in transcript: String, now: Date? = nil) -> Date? {
        let now = now ?? voiceNow
        let calendar = Calendar.current

        // ⓪ 认不了的日期表达一律整句认输（语料 `_unsupported_date_note`）。
        //
        // 下面的日期词只认明天/后天/今天三个，碰上「8月10号」「下周三」它不会失败，
        // 而是**只取钟点、把日期当没说**，再套 ④ 的「已过就滚次日」—— 于是任何日期
        // 都被静默解析成今天或明天：「8月10号早上8点」→ 次日 08:00（差 1 天）。
        // 这个值能过提前量校验、读回念得很顺，而盲人无从判断这不是自己说的那天。
        if transcript.firstRange(of: unsupportedDateRegex) != nil { return nil }

        // ① 相对时间优先。「半小时后」不能被下面的钟点分支按「半」误读。
        if let offset = relativeMinutesOffset(in: transcript) {
            return calendar.date(byAdding: .minute, value: offset, to: now)
        }

        // ② 钟点。没有「N点」就不是时间表达（llm 那几条走这里返回 nil）。
        guard let clock = clockTime(in: transcript) else { return nil }

        // ③ 日期词。没说日期词时 dayOffset 为 nil —— 与「说了今天」不是一回事，见 ④。
        //
        // 「第二天」= 明天（产品 2026-08-09 拍板）。⓪ 那条黑名单专门把它放行到这里，
        // 这里再不认就等于「只取钟点、把日期当没说」，正是 ⓪ 要防的那个静默篡改。
        // 阿拉伯写法也要收：识别器把「第二天」渲染成「第2天」时，只认中文会静默丢掉日期。
        let dayOffset: Int? = transcript.contains("后天") ? 2
            : transcript.contains("明天") ? 1
            : transcript.contains("第二天") || transcript.contains("第2天") ? 1
            : transcript.contains("今天") ? 0
            : nil

        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: calendar.date(byAdding: .day, value: dayOffset ?? 0, to: now) ?? now
        )
        components.hour = clock.hour
        components.minute = clock.minute
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
        if transcript.contains("半小时后") || transcript.contains("半个小时后") { return 30 }
        if let minutes = chineseNumber(before: "分钟后", in: transcript) { return minutes }
        if let hours = chineseNumber(before: "个小时后", in: transcript)
            ?? chineseNumber(before: "小时后", in: transcript) {
            return hours * 60
        }
        return nil
    }

    /// 「八点半」「下午三点」「8:00」→ 24 小时制时分。时段词负责 12 小时制换算。
    private static func clockTime(in transcript: String) -> (hour: Int, minute: Int)? {
        guard var parsed = colonClockTime(in: transcript) ?? spokenClockTime(in: transcript) else {
            return nil
        }
        if parsed.hour < 12,
           transcript.contains("下午") || transcript.contains("晚上") || transcript.contains("傍晚") {
            parsed.hour += 12
        }
        return parsed
    }

    /// 冒号钟点：`8:00`、`8：00`、`18:30`。
    ///
    /// **这条起初在黄金语料里找不到依据，是照真机实况补的**（2026-08-06 手测「说了时间但识别不了
    /// 时间点」）：iOS 的 `SFSpeechRecognizer` 说中文时经常把「八点钟」渲染成 `8:00`，
    /// 句子里连「点」字都没有。后端 2026-08-08 的 PR #14 补齐同一条并进了语料，
    /// 现在两边同口径。
    ///
    /// 分钟写 `[0-5]\d` 而不是 `\d{2}` + 范围校验：非法分钟（`8:75`）直接不匹配，
    /// 与后端 `CLOCK_TIME` 逐字一致。
    private static func colonClockTime(in transcript: String) -> (hour: Int, minute: Int)? {
        for match in transcript.matches(of: colonClockRegex) {
            // ⚠️「跑1:30」是**时长**口语（识别器可能把「跑一个半小时」渲染成这样），不是 01:30 出发。
            // 不挡的话它会被当成钟点 → 01:30 已过 → 滚到次日 → 提前量校验放行 →
            // 读回念出一个用户从没说过的时刻。**静默篡改比抽不出更糟**：抽不出至少读回时听得出来。
            //
            // 跳过本次继续找，不是直接返 nil ——「跑1:30，明天早上8点出发」里真正的钟点在后面。
            if isDurationLeadIn(transcript, hourStart: match.range.lowerBound) { continue }
            let parts = transcript[match.range].split(whereSeparator: { $0 == ":" || $0 == "：" })
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
                  (0...24).contains(hour) else { continue }
            return (hour, minute)
        }
        return nil
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

    /// 逐字照抄后端 `VoiceSlotParser.UNSUPPORTED_DATE`（`VoiceSlotParser.java:56-60`）。
    ///
    /// 同时收中文与阿拉伯数字，且**在原文上判** —— 后端是在中文数字归一化之前匹配的，
    /// 归一化之后「下周三」就变成了「下周3」、词形没了。
    ///
    /// ponytail: 只让它认输，**不新增「认识 X月Y号」的解析分支**。日期表达是开放的
    /// （下下周二 / 这个月底 / 月底前），正则永远穷举不完，那是大模型该干的活。
    private static let unsupportedDateRegex = try! Regex(
        "[0-9零一二两三四五六七八九十]{1,3}\\s*月\\s*[0-9零一二两三四五六七八九十]{1,3}\\s*[号日]"
            + "|[下这本上]{1,2}\\s*个?\\s*(?:周|星期|礼拜)"
            + "|大[前后]天"
            + "|[下这本]\\s*个\\s*月"
            // 「第三天」以上 —— 相对哪一天的「第三天」没说清。**「第二天」是例外，它当明天解**
            // （产品 2026-08-09 拍板），所以用 `(?![二2]\s*天)` 把它放行给下面的日期词。
            + "|第(?![二2]\\s*天)[0-9零一二两三四五六七八九十]{1,3}\\s*天"
            // 「隔天」**刻意不当明天**：中文里它同样常指「每隔一天」（「隔天跑一次」），
            // 而这是个跑步 App，这个歧义是真的。宁可追问一次，不猜。
            + "|隔天"
    )

    /// 「N点」「N点半」。N 中文与阿拉伯数字都认。
    ///
    /// **扫描每一个「点」，不是只看第一个**：对齐后端 `while (clock.find())` 的「跳过本次继续找」。
    /// 只看第一个的话，「跑慢一点，明天早上八点出发」会停在被守卫拒掉的「慢一点」上，
    /// 而真正的钟点在后面。
    private static func spokenClockTime(in transcript: String) -> (hour: Int, minute: Int)? {
        var cursor = transcript.startIndex
        while let range = transcript.range(of: "点", range: cursor..<transcript.endIndex) {
            cursor = range.upperBound
            let head = String(transcript[transcript.startIndex..<range.lowerBound])
            guard let hour = trailingNumber(in: head, blockingDegreeLeadIn: true),
                  (1...24).contains(hour) else { continue }
            // 「N点半」只认紧跟在「点」后面的「半」，避免「八点跑半小时」被读成 08:30。
            // 两种写法都要查：识别输出「8点半」时，只查中文形式「八点半」会漏掉，
            // 半小时就被静默抹成整点 —— 对听不见屏幕的人，这是一次无声的篡改。
            let isHalfPast = transcript.contains("\(chineseDigits[hour] ?? "")点半")
                || transcript.contains("\(hour)点半")
            return (hour, isHalfPast ? 30 : 0)
        }
        return nil
    }

    /// 汉字数字 → 整数，只覆盖 Mock 语料需要的 1~59。找 `suffix` 前面那一段来解。
    private static func chineseNumber(before suffix: String, in transcript: String) -> Int? {
        guard let range = transcript.range(of: suffix) else { return nil }
        return trailingNumber(in: String(transcript[transcript.startIndex..<range.lowerBound]))
    }

    /// 从一段文字的**尾部**往前吃数字字符（最多 3 个，够「四十五」）并解成整数。
    ///
    /// - Parameter blockingDegreeLeadIn: 数字紧跟在程度副词后面时拒绝。
    ///   照抄后端 `VoiceSlotParser.isDegreeLeadIn`（`VoiceSlotParser.java:405`），**只在钟点上开**：
    ///   「慢一点」里的「一点」正好长得像「1 点」，认了就凭空造出一个凌晨 1 点 ——
    ///   而用户根本没提时间，这个时刻还能过提前量校验、被读回念得很顺。
    ///   只收「慢快早晚」四个字，刻意**不收「多少」**（会误杀「差不多1点」）。
    ///   时长那几个后缀（分钟后 / 小时后）不开，那里没有这个歧义。
    private static func trailingNumber(in head: String, blockingDegreeLeadIn: Bool = false) -> Int? {
        let digits = head.reversed().prefix(3).reversed().map(String.init)
        for start in 0..<digits.count {
            let candidate = digits[start...].joined()
            guard let value = chineseNumberValue(candidate) else { continue }
            // ⚠️「跑1.5小时」不许被读成 5 小时 = 300 分钟。而 300 正好是 `MAX_DURATION_MINUTES`，
            // 范围校验拦不住 —— 用户说 1.5 小时，读回却说 5 小时，是一次**静默篡改**。
            // 对齐后端 `VoiceSlotParser.HOUR_ONLY` 的 `(?<!\.)` 守卫（`VoiceSlotParser.java:94`）：
            // 只挡「抽错」，不新增「认小数时长」—— 落到追问是诚实的降级。
            if start > 0, digits[start - 1] == "." { continue }
            if blockingDegreeLeadIn, start > 0, "慢快早晚".contains(digits[start - 1]) { continue }
            return value
        }
        return nil
    }

    private static func chineseNumberValue(_ text: String) -> Int? {
        if let arabic = Int(text) { return arabic }
        let units = ["零": 0, "一": 1, "两": 2, "二": 2, "三": 3, "四": 4,
                     "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let single = units[text] { return single }
        guard text.contains("十") else { return nil }
        let parts = text.components(separatedBy: "十")
        guard parts.count == 2 else { return nil }
        let tens = parts[0].isEmpty ? 1 : (units[parts[0]] ?? -1)
        let ones = parts[1].isEmpty ? 0 : (units[parts[1]] ?? -1)
        guard tens >= 0, ones >= 0 else { return nil }
        return tens * 10 + ones
    }

    private static let chineseDigits: [Int: String] = [
        1: "一", 2: "两", 3: "三", 4: "四", 5: "五", 6: "六",
        7: "七", 8: "八", 9: "九", 10: "十", 11: "十一", 12: "十二"
    ]

    /// 取值与 `demo/docs/voice-golden-corpus.json` 里 `source: "regex"` 的 DURATION 用例一致。
    /// Mock 与真实解析器漂移会让开发期调通的向导在真机上走不通，`VoiceOrderWizardTests` 锁了这份对齐。
    /// 顺序有意义：「一个半小时」必须排在「半小时」「一小时」之前，否则会被前缀吃掉。
    static func mockVoiceMinutes(in transcript: String) -> Int? {
        if transcript.contains("一个半小时") { return 90 }
        if transcript.contains("一小时二十分钟") { return 80 }
        if transcript.contains("两小时") || transcript.contains("两个小时") { return 120 }
        if transcript.contains("半小时") { return 30 }
        if transcript.contains("一小时") || transcript.contains("一个小时") { return 60 }
        if transcript.contains("四十分钟") { return 40 }
        if transcript.contains("二十分钟") { return 20 }
        // 语料之外的兜底：**阿拉伯数字**。
        //
        // 上面那几条逐字对齐后端黄金语料，全是中文数字；而 iOS 的 `SFSpeechRecognizer` 实际
        // 输出的是「跑1个小时」「跑30分钟」这种阿拉伯数字形式。2026-08-06 真机手测因此出现
        // 「说了时长，读回还是默认值」—— 不是客户端 bug，是 Mock 比真实解析器窄。
        // 后端 `VoiceSlotParser` 先把中文数字归一成阿拉伯数字再跑正则，本来就两种都吃。
        if let hours = numberBefore(["个小时", "小时"], in: transcript) { return hours * 60 }
        if let minutes = numberBefore(["分钟"], in: transcript) { return minutes }
        return nil
    }

    /// 取某个后缀之前紧邻的数字，中文与阿拉伯数字都认。
    /// 顺序敏感：`["个小时", "小时"]` 里「个小时」必须排前面，否则「1个小时」会在「小时」处
    /// 往前吃到「个」而取不到数。
    private static func numberBefore(_ suffixes: [String], in transcript: String) -> Int? {
        for suffix in suffixes {
            if let value = chineseNumber(before: suffix, in: transcript), value > 0 {
                return value
            }
        }
        return nil
    }
}
