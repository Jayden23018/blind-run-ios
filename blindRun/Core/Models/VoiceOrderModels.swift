import Foundation

// MARK: - Voice Order (语音下单)

/// 语音下单的三个后端端点（`api_spec.yaml`，均需 JWT + `BLIND` 角色）。
///
/// 分工：**后端只收文本、不收音频、不存状态**。录音、ASR、TTS、以及「下一个字段问不问」的向导状态机
/// 全在客户端；后端提供无状态的解析原语。所以这里只有 DTO，状态机在 `VoiceOrderWizard`。
enum VoiceOrderEndpoint {
    /// 整句一次抽三槽（起点 / 开始时间 / 时长）。请求体与 `resolveAddress` **完全一致**，故复用同一个类型。
    static let parseOrder = "/api/orders/voice/parse"
    static let resolveAddress = "/api/orders/voice/resolve-address"
    static let parseSlot = "/api/orders/voice/parse-slot"
}

struct ResolveAddressRequest: Codable, Sendable {
    /// 原始 ASR 转录文本，**不要做客户端清洗**：后端的正则与大模型兜底对「呃」「吧」这类语气词有容错，
    /// 前端去标点反而可能删掉断句信息（`语音下单交接说明.md` 第五节）。
    let transcript: String
    /// 当前位置（GCJ-02，可选，2026-08-01 后端新增）。
    ///
    /// 不传时后端走正向地理编码取 `geocodes[0]`，「人民广场」这类全国重名地点等于撞运气；传了则改走
    /// 周边搜索按距离取最近一个。语音路径没有候选列表可挑，消歧只能靠这两个数 —— **有定位就一定要带**。
    let latitude: Double?
    let longitude: Double?

    init(transcript: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.transcript = transcript
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// 起点解析结果。坐标已经是 **GCJ-02**，与全系统一致，可直接用于下单，不需要再转换。
struct ResolveAddressResponse: Codable, Sendable, Equatable {
    let address: String?
    let latitude: Double?
    let longitude: Double?
    /// `true` 表示「没听清」，是 **HTTP 200 的正常业务状态**，不是错误：播 `ttsText` 原地重问，
    /// 既不推进向导，也不弹错误 UI。
    let needReask: Bool?
    /// 后端渲染好的确认/追问文案，直接喂 TTS。
    let ttsText: String?

    var isUsable: Bool {
        needReask != true && latitude != nil && longitude != nil && address?.trimmed.isEmpty == false
    }
}

/// 不做未知值兜底：只出现在 `ParseSlotRequest`（**只出不进**），由客户端决定这一轮问哪个字段。
enum VoiceSlotField: String, Codable, Sendable {
    case startTime = "START_TIME"
    case duration = "DURATION"
}

/// `ParseVoiceOrderResponse.missing` 的元素。**刻意不复用 `VoiceSlotField`**：那个是请求侧、只出不进、
/// 且只有两个值（`ADDRESS` 传给 `parse-slot` 会返 400）；这个是响应侧、只进不出、多一个 `ADDRESS`。
/// 两个方向合并成一个枚举，迟早有人把 `ADDRESS` 发去 `parse-slot`。
///
/// 未知值退化成 `.unknown` 而不是抛 —— 后端往这个枚举加值时不该让整条响应解不出来（与
/// `RunOrderStatus` / `BlindVerifyStatus` 同一套写法）。
enum VoiceOrderMissingSlot: String, Codable, Sendable, Equatable {
    case address = "ADDRESS"
    case startTime = "START_TIME"
    case duration = "DURATION"
    /// 后端新增槽位时的兜底，不是后端会发的值。
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = VoiceOrderMissingSlot(rawValue: rawValue) ?? .unknown
    }
}

/// 整句解析结果：一句话同时抽起点、开始时间、时长。
///
/// **地点这一路是 2026-08-04 才有的**。此前只有 `resolve-address`，它把整个 transcript 原样喂高德正向
/// 地理编码，整句进去必然返「没听清地点」；`/parse` 改成先抽地名 span 再查，整句里说的起点才第一次可用。
///
/// 与 `ParseSlotResponse` 一样，`plannedStartTime` 是无时区 `yyyy-MM-ddTHH:mm:ss`（**可能带小数秒**，
/// 用 `String.backendLocalDate` 解），可直接透传给 `CreateOrderRequest`；坐标已是 GCJ-02。
///
/// `missing` / `needReask` / `ttsText` 在 spec 里标 required，这里**一律放宽成可选** —— 线上偶发缺字段
/// 应该退化成「当没听清处理」，而不是整条解码炸掉。语音是盲人唯一的下单通道，这里要比 spec 松一档。
struct ParseVoiceOrderResponse: Codable, Sendable, Equatable {
    let plannedStartTime: String?
    let durationMinutes: Int?
    let address: String?
    let latitude: Double?
    let longitude: Double?

    // MARK: 终点（可选槽位，2026-08-08 后端 SPEC B1 新增）

    /// 解析出的终点地址；原话没说终点时 `nil`。
    ///
    /// **终点永远不进 `missing`，也不会触发追问**（`api_spec.yaml:2841`）—— 它是可选的，
    /// 一个可选字段不该把用户卡在追问循环里。所以 `VoiceOrderMissingSlot` 里没有 `END_ADDRESS`。
    ///
    /// ⚠️ 终点**只由大模型抽取，没有正则链路**：百炼不可用时本字段恒为 `nil`，
    /// 起点/时间/时长照常解析。这是后端明确接受的降级，**不能当契约**。
    let endAddress: String?
    /// ⚠️ 可能为 `nil` 而 `endAddress` 非 `nil`（说了地名、高德查不到坐标）。
    let endLatitude: Double?
    let endLongitude: Double?
    /// 后端声明它恒等于「`endAddress` 非 null 且 `endLatitude` 为 null」。
    ///
    /// **解它是为了漂移可见，判断一律用 `resolvedEndPlace` 自己算** ——
    /// 同一事实有两个来源时只信结构：这个字段 2026-08-09 刚因为算错被后端修过一次（N39），
    /// 而三元组本身当时是对的。
    let endAddressUnresolved: Bool?

    /// 还缺（或校验不通过）的槽位。**客户端把它当作「这几项保持默认值」**，不据此重问 ——
    /// 理由见 `VoiceOrderWizard.parseFreeform`。
    let missing: [VoiceOrderMissingSlot]?
    let needReask: Bool?
    /// `missing` 非空时这是**追问**文案，不是整单读回，所以整句轮不播它（后端 2026-08-04 确认：
    /// 抽不出的槽位保留什么默认值只有客户端知道，后端拼不出整单）。
    let ttsText: String?

    // MARK: 额外需求槽位（可选，2026-08-04 后端新增）
    //
    // 三者都是「抽不出不追问」的可选槽位：解析不出不会进 `missing`，也不会单独触发大模型兜底
    // （大多数人不提导盲犬，那样每单都要白付一次调用）。

    /// 本次是否携带导盲犬。
    ///
    /// ⚠️ **`nil` ≠ `false`，两者在下单时的处理完全不同**：
    /// - `nil` —— 原话没提。下单时**不要传** `hasGuideDogThisRun`，让后端回落
    ///   `BlindProfile.hasGuideDog` 档案默认值。
    /// - `false` —— 本次明确不带（「今天不带导盲犬」）。要原样传。
    ///
    /// 传错的后果不是文案问题：这个字段进派单的**硬过滤**（不接受导盲犬的志愿者被直接踢出候选池），
    /// 把 `nil` 当 `false` 传，会让档案里登记了导盲犬的用户被静默按「不带」派单。
    let hasGuideDog: Bool?

    /// 本次配速偏好；`nil` 表示原话没提，下单时不传即回落档案默认配速。
    let pacePreference: PacePreference?

    /// 本次备注；`nil` 表示原话没提。
    ///
    /// 非 nil 时后端保证是用户原话的子串 —— 备注原样展示给志愿者，模型编出来的「我行动不便」
    /// 会直接误导对方，所以改写过的备注在后端就被丢弃了。
    let specialNotes: String?

    /// 终点四项与三个额外槽位默认 `nil`（＝原话没提），让只关心三个必填槽位的调用点不必逐个写 `nil`。
    /// 解码走 `Codable` 合成路径，不受这里的默认值影响。
    init(
        plannedStartTime: String?,
        durationMinutes: Int?,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        missing: [VoiceOrderMissingSlot]?,
        needReask: Bool?,
        ttsText: String?,
        endAddress: String? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        endAddressUnresolved: Bool? = nil,
        hasGuideDog: Bool? = nil,
        pacePreference: PacePreference? = nil,
        specialNotes: String? = nil
    ) {
        self.plannedStartTime = plannedStartTime
        self.durationMinutes = durationMinutes
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.endAddress = endAddress
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.endAddressUnresolved = endAddressUnresolved
        self.missing = missing
        self.needReask = needReask
        self.ttsText = ttsText
        self.hasGuideDog = hasGuideDog
        self.pacePreference = pacePreference
        self.specialNotes = specialNotes
    }

    /// 起点三项要么全有要么当没抽到 —— 只有地址没有坐标下不了单，只有坐标没有地址读回时没法念。
    var resolvedStartPlace: (address: String, latitude: Double, longitude: Double)? {
        guard let address = address?.nilIfBlank, let latitude, let longitude else { return nil }
        return (address, latitude, longitude)
    }

    /// 终点：**规则比起点松一档**，有地名就算数、坐标可缺（`api_spec.yaml:3007-3019` 明确两边不同）。
    ///
    /// 反过来不行：只有坐标没有地名一律当没抽到 —— 那是客户端 bug，
    /// 而且读回时没有任何东西可念，盲人根本不知道被约到了哪。
    /// 半个坐标由 `BookingEndPlace.init` 降级成「只有地名」。
    var resolvedEndPlace: BookingEndPlace? {
        guard let address = endAddress?.nilIfBlank else { return nil }
        return BookingEndPlace(address: address, latitude: endLatitude, longitude: endLongitude)
    }
}

/// 一次只能解析一个字段 —— 这是接口层面的约束，不是产品选择。
struct ParseSlotRequest: Codable, Sendable {
    let transcript: String
    let field: VoiceSlotField
}

/// 时间/时长解析结果。
///
/// `plannedStartTime` 是 `yyyy-MM-ddTHH:mm:ss`（无时区），与 `CreateOrderRequest.plannedStartTime`
/// 同格式，**直接透传**，客户端不做二次格式化。提前量（≥30 分钟）和时长范围（10~300 分钟）由后端
/// 校验，不满足时同样返回 `needReask: true` + 提示文案，而不是错误分支。
struct ParseSlotResponse: Codable, Sendable, Equatable {
    let plannedStartTime: String?
    let durationMinutes: Int?
    let needReask: Bool?
    let ttsText: String?
}
