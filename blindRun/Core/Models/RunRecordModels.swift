import Foundation

// 跑后运动记录。契约唯一源：`demo/docs/api_spec.yaml` 的 `RunRecordResponse` /
// `RunRecordHistoryResponse` / `RunRecordMessage*` / `Run*`（2026-09-24，迁移 0047）。
// 类型名与 schema 名逐字一致，好让 `ContractFixtureTests` 按文件名前缀找到它们。
//
// 三条解码规则（OpenSpec `add-post-run-record` → `post-run-record`）：
// 1. 响应里的枚举一律开放：标量字段遇到不认识的值落到 `.unknown`，整条照常解出来。
// 2. `events` / `messages` 里不认识的类型**整条跳过**（`@SkippingUndecodable`）——
//    后端 P1 会加 `VOICE` 留言，老客户端念不出来的东西不该出现，也不该让整页空白。
// 3. 没有数据是 `null` 不是 `0`：计算类数字一律 Optional，界面按 nil 隐藏（HANDOFF 6.4）。
//
// 日期保持后端原串（`2026-09-16T20:22:27.820218`，无时区、可能带小数秒），
// 与 `OrderTrackModels` 一致，由界面阶段用 `String.backendLocalDate` 解析。

/// 生成状态。含义见契约 `getRunRecord` 的说明。
nonisolated enum RunRecordStatus: String, Decodable, Sendable {
    case generating = "GENERATING"
    case ready = "READY"
    case failed = "FAILED"
    case insufficientTrack = "INSUFFICIENT_TRACK"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = RunRecordStatus(rawValue: rawValue) ?? .unknown
    }
}

/// `viewerRole` / `fromRole` / 列表 `role`。契约枚举里的 `UNSET` 在这几个位置上不会出现，
/// 与后端新加的值一样落到 `.unknown`。不复用 `UserRole`：它全 App 穷举 switch，
/// 给它加 `.unknown` 会波及登录与角色选择。
nonisolated enum RunRecordRole: String, Decodable, Sendable {
    case blind = "BLIND"
    case volunteer = "VOLUNTEER"
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = RunRecordRole(rawValue: rawValue) ?? .unknown
    }
}

/// 途中事件类型。**刻意没有 `.unknown`**：不认识的值让这一条解码失败，
/// 由外层 `@SkippingUndecodable` 跳过（契约原话「不认识的跳过」）。
nonisolated enum RunEventType: String, Decodable, Sendable {
    case arrived = "ARRIVED"
    case runStarted = "RUN_STARTED"
    case rest = "REST"
    case runEnded = "RUN_ENDED"
    case orderCompleted = "ORDER_COMPLETED"
}

/// 留言类型。本期只有 `TEXT`；同样没有 `.unknown`，理由同 `RunEventType`。
nonisolated enum RunRecordMessageType: String, Codable, Sendable {
    case text = "TEXT"
}

/// 解码时逐个元素尝试，失败的那一个跳过、其余保留。
///
/// 只用在契约明说「不认识的跳过」的数组上。别拿它包 `splits` 这种必须完整的数组 ——
/// 少一段分段比整页报错更难发现。
@propertyWrapper
nonisolated struct SkippingUndecodable<Element: Decodable & Sendable & Equatable>: Decodable, Sendable, Equatable {
    var wrappedValue: [Element]

    init(wrappedValue: [Element]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // 解码失败时容器下标不前进，必须吞掉这一个元素，否则死循环。
                _ = try container.decode(DiscardedElement.self)
            }
        }
        wrappedValue = elements
    }

    private nonisolated struct DiscardedElement: Decodable {}
}

// MARK: - 单条记录

nonisolated struct RunRecordResponse: Decodable, Sendable, Equatable {
    let orderId: Int64
    let status: RunRecordStatus
    let viewerRole: RunRecordRole
    let place: String?
    let blindName: String?
    let volunteerName: String?
    let runStartedAt: String?
    let runEndedAt: String?
    /// `GENERATING` / `FAILED` 时为 nil。
    let summary: RunSummary?
    let splits: [RunSplit]
    let fastestSplitIndex: Int?
    let paceSamples: [RunPaceSample]
    let stops: [RunStop]
    @SkippingUndecodable var events: [RunEvent]
    let sosTriggered: Bool
    let service: RunService
    /// 只给跑者本人；陪跑员恒为 nil（D6）。
    let comparison: RunComparison?
    @SkippingUndecodable var messages: [RunRecordMessageResponse]
    /// 轨迹不足、或超过 90 天留存期时为 nil。
    let track: RunTrack?
}

nonisolated struct RunSummary: Decodable, Sendable, Equatable {
    let distanceM: Int?
    let movingSec: Int?
    let elapsedSec: Int?
    let restSec: Int?
    let avgPaceSecPerKm: Int?
    /// 下面三个是**请求者本人手机**的数据（D3），另一方的不下发。
    let steps: Int?
    let avgCadence: Int?
    let elevationGainM: Int?
}

nonisolated struct RunSplit: Decodable, Sendable, Equatable {
    let index: Int
    let distanceM: Int
    let durationSec: Int
    let paceSecPerKm: Int
    let avgCadence: Int?
}

nonisolated struct RunPaceSample: Decodable, Sendable, Equatable {
    let distanceM: Int
    let paceSecPerKm: Int
}

nonisolated struct RunStop: Decodable, Sendable, Equatable {
    let startedAt: String
    let durationSec: Int
    let atDistanceM: Int
    /// GCJ-02；超过 90 天留存期为 nil。
    let lat: Double?
    let lng: Double?
    /// 本期恒为 nil（逆地理编码是 P1）。
    let placeName: String?
}

/// 只有类型和时间，**文案由客户端生成**（后端不写中文句子）。
nonisolated struct RunEvent: Decodable, Sendable, Equatable {
    let type: RunEventType
    let at: String
    /// true = 由轨迹推算（REST、RUN_ENDED）。
    let inferred: Bool
    /// 仅 REST。
    let durationSec: Int?
    let lat: Double?
    let lng: Double?
}

/// 志愿服务时长（D4 口径：进入 IN_PROGRESS → 订单完成；D5：没有确认状态字段）。
nonisolated struct RunService: Decodable, Sendable, Equatable {
    let startedAt: String?
    let completedAt: String?
    /// 从未进入 IN_PROGRESS（超时自动完成）为 nil。
    let durationMin: Int?
    /// 这位陪跑员的累计服务分钟数（D6，两个角色都能看到）；陪跑员注销为 nil。
    let volunteerTotalServiceMinutes: Int64?
}

nonisolated struct RunComparison: Decodable, Sendable, Equatable {
    let previousOrderId: Int64
    let previousDistanceM: Int
    /// 本次 − 上次，可为负。
    let deltaDistanceM: Int
}

nonisolated struct RunTrack: Decodable, Sendable, Equatable {
    /// 恒为 `GCJ02`（D1），直接交给高德，不做二次转换。
    let coordSystem: String
    let startedAt: String
    let points: [RunTrackPoint]
}

nonisolated struct RunTrackPoint: Decodable, Sendable, Equatable {
    /// 距 `RunTrack.startedAt` 的秒数。
    let t: Double
    let lat: Double
    let lng: Double
    /// 到此点的累计米数（不含自动暂停段）。
    let d: Int
}

// MARK: - 留言

nonisolated struct RunRecordMessageRequest: Encodable, Sendable, Equatable {
    let type: RunRecordMessageType
    let text: String

    init(text: String) {
        self.type = .text
        self.text = text
    }
}

nonisolated struct RunRecordMessageResponse: Decodable, Sendable, Equatable {
    let id: Int64
    let fromRole: RunRecordRole
    let type: RunRecordMessageType
    let text: String?
    let createdAt: String
}

// MARK: - 月度列表

nonisolated struct RunRecordHistoryResponse: Decodable, Sendable, Equatable {
    let role: RunRecordRole
    /// `YYYY-MM`
    let month: String
    let monthSummary: RunMonthSummary
    let items: [RunHistoryItem]
}

nonisolated struct RunMonthSummary: Decodable, Sendable, Equatable {
    let runs: Int
    let distanceM: Int?
    /// 仅陪跑员。
    let serviceMin: Int64?
    let topPartner: RunTopPartner?
}

nonisolated struct RunTopPartner: Decodable, Sendable, Equatable {
    /// 脱敏；注销为 nil。
    let name: String?
    let runs: Int
}

nonisolated struct RunHistoryItem: Decodable, Sendable, Equatable {
    let orderId: Int64
    let finishedAt: String
    let place: String?
    /// 始终脱敏（`张*`）；对方注销为 nil。
    let partnerName: String?
    let distanceM: Int?
    /// 仅陪跑员，≤ 64 点，GCJ-02。
    let thumbnail: [RunLatLng]?
}

nonisolated struct RunLatLng: Decodable, Sendable, Equatable {
    let lat: Double
    let lng: Double
}
