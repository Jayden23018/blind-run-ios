import Foundation

// MARK: - Voice Order (语音下单)

/// 语音下单的三个后端端点（`api_spec.yaml:773-826`，均需 JWT + `BLIND` 角色）。
///
/// 分工：**后端只收文本、不收音频、不存状态**。录音、ASR、TTS、以及「下一个字段问不问」的向导状态机
/// 全在客户端；后端提供无状态的解析原语。所以这里只有 DTO，状态机在 `VoiceOrderWizard`。
enum VoiceOrderEndpoint {
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
