import Foundation

// MARK: - Order Status

enum BlindRunnerOrderRoute: String, Sendable {
    case tracking
    case inService
    case completion
    case terminal
}

enum RunOrderStatus: String, Codable, CaseIterable, Sendable {
    case pendingMatch = "PENDING_MATCH"
    case pendingAccept = "PENDING_ACCEPT"
    case inProgress = "IN_PROGRESS"
    case driverEnRoute = "DRIVER_EN_ROUTE"
    case driverArrived = "DRIVER_ARRIVED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case rematching = "REMATCHING"
    case noVolunteer = "NO_VOLUNTEER"
    /// 后端新增状态时的兜底。**不是后端会发的值**，只在解码遇到不认识的字符串时产生。
    case unknown = "UNKNOWN"

    /// 兜底解码：合成的 `decodeIfPresent` 只对「字段缺失/为 null」宽容，
    /// 对「值存在但不认识」会抛 `dataCorrupted`，把**整条**响应带崩
    /// （`OrderDetailResponse` / `OrderResponse` / `OrderTrackResponse` /
    /// `VolunteerLocationData` / `VolunteerDispatchSummary*` 全部走这个枚举）。
    /// 后端往订单状态机里加一个值就够让订单主干页面整页空白，所以在枚举层一次兜住，
    /// 而不是逐个字段改成 `String` + 映射。与 `BlindVerifyStatus`、
    /// `VolunteerDispatchNotAvailableReason` 是同一套写法。
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = RunOrderStatus(rawValue: rawValue) ?? .unknown
    }

    /// 刻意排除 `.unknown`：它不是一个真实状态，不该出现在状态机遍历（`canReach`）或任何选项列表里。
    static var allCases: [RunOrderStatus] {
        [
            .pendingMatch,
            .pendingAccept,
            .inProgress,
            .driverEnRoute,
            .driverArrived,
            .completed,
            .cancelled,
            .rematching,
            .noVolunteer
        ]
    }

    var displayName: String {
        switch self {
        case .pendingMatch: return "系统派单中"
        case .pendingAccept: return "待出发"
        case .inProgress: return "进行中"
        case .driverEnRoute: return "志愿者出发中"
        case .driverArrived: return "志愿者已到达"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        case .rematching: return "重新匹配中"
        case .noVolunteer: return "暂无志愿者"
        case .unknown: return "状态未知"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .noVolunteer:
            return true
        default:
            return false
        }
    }

    /// Whether blind runner should keep polling for updates
    var shouldPoll: Bool {
        switch self {
        case .pendingMatch, .pendingAccept, .inProgress, .driverEnRoute, .driverArrived, .rematching:
            return true
        case .completed, .cancelled, .noVolunteer:
            return false
        // 继续轮询：`.unknown` 表示「我不认识后端给的状态」，不表示订单结束。
        // 停轮询会把页面永久钉死在未知态；继续轮询则会在状态推进到本客户端认识的值时自愈。
        // 代价是后端若新增的是**终态**，会一直轮询到用户离开页面 —— 相较之下这个代价更小。
        case .unknown:
            return true
        }
    }

    /// Blind-runner cancellation states. Volunteer cancellation is role-scoped below.
    var canCancel: Bool {
        canBlindRunnerCancel
    }

    var canBlindRunnerCancel: Bool {
        switch self {
        case .pendingMatch, .pendingAccept, .rematching:
            return true
        default:
            return false
        }
    }

    var canVolunteerCancel: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        default:
            return false
        }
    }

    func canCancel(as role: UserRole) -> Bool {
        switch role {
        case .blind:
            return canBlindRunnerCancel
        case .volunteer:
            return canVolunteerCancel
        case .unset:
            return false
        }
    }

    /// Whether the blind runner may trigger the in-run SOS. Enabled in `IN_PROGRESS` only:
    /// that is the one state where the live escort session is guaranteed to be holding a fresh
    /// real coordinate, and the one the backend's participant check accepts for this role.
    var canBlindRunnerTriggerEmergency: Bool {
        self == .inProgress
    }

    /// Whether the escorting volunteer may raise the SOS on the blind runner's behalf.
    ///
    /// Held at `false` until 2026-07-31 because `EmergencyService.triggerEmergency` keyed the event
    /// on the *triggering* user: a volunteer-initiated SOS pushed the alert back to the volunteer who
    /// pressed it, never reached the blind runner, and escalated to the *volunteer's* emergency
    /// contacts. The backend now resolves `victimId` from the order participant, tags the source with
    /// `TriggerType.VOLUNTEER_BUTTON`, and pushes `EMERGENCY_TRIGGERED_BY_VOLUNTEER` to the blind
    /// runner (handoff.md 2026-07-31). Same `IN_PROGRESS`-only gate as the blind runner's own entry.
    var canVolunteerTriggerEmergency: Bool {
        self == .inProgress
    }

    func canTriggerEmergency(as role: UserRole) -> Bool {
        switch role {
        case .blind:
            return canBlindRunnerTriggerEmergency
        case .volunteer:
            return canVolunteerTriggerEmergency
        case .unset:
            return false
        }
    }

    var blindRunnerRoute: BlindRunnerOrderRoute {
        switch self {
        case .pendingMatch, .pendingAccept, .driverEnRoute, .driverArrived, .rematching:
            return .tracking
        case .inProgress:
            return .inService
        case .completed:
            return .completion
        case .cancelled, .noVolunteer:
            return .terminal
        // 落到只读的跟踪页：那是唯一不提供取消/开始/结束等破坏性操作的落点。
        case .unknown:
            return .tracking
        }
    }

    var canFinishService: Bool {
        self == .inProgress
    }

    var canStartService: Bool {
        self == .driverArrived
    }

    var isArrivedWaitingForServiceStart: Bool {
        self == .driverArrived
    }

    var arrivedWaitingCopy: String {
        "志愿者已到达约定地点，请等待志愿者开始服务。服务开始前不能结束订单。"
    }

    var startServiceBlockedMessage: String {
        switch self {
        case .inProgress:
            return "服务已开始，不能重复开始。"
        case .completed:
            return "服务已完成，不能开始服务。"
        case .cancelled, .noVolunteer:
            return "订单已结束，不能开始服务。"
        default:
            return "当前订单状态尚未到达约定地点，不能开始服务。"
        }
    }

    var finishBlockedMessage: String {
        switch self {
        case .driverArrived:
            return arrivedWaitingCopy
        case .completed:
            return "服务已完成，不能重复结束。"
        case .cancelled, .noVolunteer:
            return "订单已结束，不能结束服务。"
        default:
            return "当前订单状态尚未进入服务中，不能结束服务。"
        }
    }

}

// MARK: - Pace & Route Preferences

/// 偏好枚举既进（`OrderDetailResponse` / `BlindProfileResponse` / `VolunteerProfileResponse`）
/// 又出（`CreateOrderRequest` / 资料更新请求）。它们是**跨端共享的词表**：安卓或后台
/// 新增一个取值，iOS 这边即使自己的选择器里没有，也会在读订单详情时撞上。
/// 所以未知取值一律落 `.unknown`，且 `.unknown` **编码成 null** —— 决不把一个后端不认识的
/// 字符串再发回去，也不占用「无偏好」这个有明确语义的真实取值。
enum PacePreference: String, Codable, CaseIterable, Sendable {
    case walkRun = "WALK_RUN"
    case easy = "EASY"
    case moderate = "MODERATE"
    case fast = "FAST"
    case noPreference = "NO_PREFERENCE"
    case unknown = "UNKNOWN"

    /// 刻意排除 `.unknown`：它不是用户能选的偏好，不该出现在任何选择器里。
    static var allCases: [PacePreference] {
        [.walkRun, .easy, .moderate, .fast, .noPreference]
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = PacePreference(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if self == .unknown {
            try container.encodeNil()
        } else {
            try container.encode(rawValue)
        }
    }

    /// 绑定到选择器时用：未知取值回落到「无偏好」，否则 SwiftUI 找不到匹配 tag 会渲染空白选项，
    /// VoiceOver 也就什么都读不出来。
    var selectable: PacePreference { self == .unknown ? .noPreference : self }

    var displayName: String {
        switch self {
        case .walkRun: return "走跑结合"
        case .easy: return "轻松"
        case .moderate: return "中等"
        case .fast: return "快速"
        case .noPreference: return "无偏好"
        case .unknown: return "无偏好"
        }
    }
}

/// 兜底策略同 `PacePreference`，原因也同：`OrderDetailResponse.routePreference` 在订单主干上。
enum RoutePreference: String, Codable, CaseIterable, Sendable {
    case parkTrail = "PARK_TRAIL"
    case street = "STREET"
    case track = "TRACK"
    case noPreference = "NO_PREFERENCE"
    case unknown = "UNKNOWN"

    static var allCases: [RoutePreference] {
        [.parkTrail, .street, .track, .noPreference]
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = RoutePreference(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if self == .unknown {
            try container.encodeNil()
        } else {
            try container.encode(rawValue)
        }
    }

    var selectable: RoutePreference { self == .unknown ? .noPreference : self }

    var displayName: String {
        switch self {
        case .parkTrail: return "公园步道"
        case .street: return "街道"
        case .track: return "跑道"
        case .noPreference: return "无偏好"
        case .unknown: return "无偏好"
        }
    }
}

// MARK: - Order Detail Response

struct OrderDetailResponse: Codable, Identifiable, Sendable {
    let orderId: Int64
    let status: RunOrderStatus
    let startAddress: String?
    let startLatitude: Double?
    let startLongitude: Double?
    let plannedStart: String?
    let plannedEnd: String?
    let blindName: String?
    let blindPhone: String?
    let volunteerPhone: String?
    let acceptedAt: String?
    let createdAt: String?
    let expectedDurationMinutes: Int?
    let pacePreference: PacePreference?
    let routePreference: RoutePreference?
    let routeNotes: String?
    let hasGuideDogThisRun: Bool?
    let specialNotes: String?
    let visionLevel: String?
    let tetherPreference: String?
    let chatPreference: String?

    var id: Int64 { orderId }

    func replacingStatus(with status: RunOrderStatus) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: startAddress,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
            blindName: blindName,
            blindPhone: blindPhone,
            volunteerPhone: volunteerPhone,
            acceptedAt: acceptedAt,
            createdAt: createdAt,
            expectedDurationMinutes: expectedDurationMinutes,
            pacePreference: pacePreference,
            routePreference: routePreference,
            routeNotes: routeNotes,
            hasGuideDogThisRun: hasGuideDogThisRun,
            specialNotes: specialNotes,
            visionLevel: visionLevel,
            tetherPreference: tetherPreference,
            chatPreference: chatPreference
        )
    }
}

// MARK: - Paginated Order Response

/// `GET /api/orders/mine` 的分页响应。契约里是 `PageOrderDetailResponse`（对象），
/// 这是本类型**唯一**的来源。
///
/// ⚠️ 解码**故意不留兜底**，这条是有事故背书的：这里曾有一个「宽容解码器」，
/// 依次试对象 / 裸数组 / 最后返空页，任何失败都不抛。
/// 结果是 `GET /api/orders/available`（真实形状是 `AvailableOrderResponse` 裸数组，
/// 元素没有 `status`，而 `OrderDetailResponse.status` 非可选）被解成**空列表且零报错**，
/// 从 2026-05-24 一直没人发现 —— 屏幕上是「暂无可用订单」，看起来完全正常。
///
/// 所以：`content` 缺失、元素缺必填字段、根节点不是对象，一律抛，让用户看见「加载失败」。
/// 这与「未知枚举值不许整条崩」不矛盾 —— 那条由 `RunOrderStatus.unknown` 一族承担，
/// 管的是**认识不了的取值**；这里管的是**根本没给的字段**，两者的安全方向相反。
/// 回归用例在 `OrderEnumLeniencyDecodingTests`。
struct PagedOrderResponse: Codable, Sendable {
    let content: [OrderDetailResponse]
    let totalElements: Int64?
    let totalPages: Int?
    let number: Int?
    let size: Int?
    let first: Bool?
    let last: Bool?
    let empty: Bool?

    private enum CodingKeys: String, CodingKey {
        case content, totalElements, totalPages, number, size, first, last, empty
    }

    init(content: [OrderDetailResponse], totalElements: Int64?, totalPages: Int?, number: Int?, size: Int?, first: Bool?, last: Bool?, empty: Bool?) {
        self.content = content
        self.totalElements = totalElements
        self.totalPages = totalPages
        self.number = number
        self.size = size
        self.first = first
        self.last = last
        self.empty = empty
    }
}

// MARK: - Order Create

struct CreateOrderRequest: Codable, Sendable {
    let startLatitude: Double
    let startLongitude: Double
    let startAddress: String
    let plannedStartTime: String
    let plannedEndTime: String
    let expectedDurationMinutes: Int?
    let pacePreference: PacePreference?
    let routePreference: RoutePreference?
    let routeNotes: String?
    let hasGuideDogThisRun: Bool?
    let specialNotes: String?
}

struct OrderResponse: Codable, Sendable {
    let id: Int64?
    let status: RunOrderStatus?
    let message: String?
    let success: Bool?
}

// MARK: - Order Respond

/// 不做未知值兜底：只出现在 `OrderRespondRequest`（**只出不进**），
/// 客户端自己产生取值，后端新增值不会经由解码打到这里。
enum OrderRespondAction: String, Codable, Sendable {
    case accept = "ACCEPT"
    case decline = "DECLINE"
}

struct OrderRespondRequest: Codable, Sendable {
    let action: OrderRespondAction
}

// MARK: - Order Review

struct CreateReviewRequest: Codable, Sendable {
    let rating: Int
    let comment: String?
}

// MARK: - Emergency

struct EmergencyTriggerRequest: Codable, Sendable {
    let orderId: Int64
    let gpsLat: Double?
    let gpsLng: Double?
}

/// Structured success body of `POST /api/emergency/trigger`.
/// Shape taken from `demo/.../controller/EmergencyController.java:34-38`, which returns a bare
/// `Map` rather than the usual `ApiResponse` envelope — `URLSessionAPIClient` decodes it directly.
/// `api_spec.yaml:1024-1030` only declares `type: object`, so the controller is the contract.
struct EmergencyTriggerResponse: Codable, Sendable, Equatable {
    let success: Bool
    let eventId: Int64
    let status: String

    var eventStatus: EmergencyEventStatus {
        EmergencyEventStatus(rawValue: status) ?? .unknown
    }
}

/// Mirrors backend `entity/EmergencyStatus.java`. `unknown` absorbs values added server-side later:
/// a status this client cannot name must never be presented as a rescue guarantee.
enum EmergencyEventStatus: String, Codable, Sendable, CaseIterable {
    case pending = "PENDING"
    case volunteerNotified = "VOLUNTEER_NOTIFIED"
    case volunteerConfirmed = "VOLUNTEER_CONFIRMED"
    case csHandling = "CS_HANDLING"
    case contactNotified = "CONTACT_NOTIFIED"
    case resolved = "RESOLVED"
    case falseAlarm = "FALSE_ALARM"
    case unknown = "UNKNOWN"

    var isTerminal: Bool {
        self == .resolved || self == .falseAlarm
    }
}

/// `GET /api/emergency/active` —— **拿事件 id 和实时状态的唯一权威来源**。
///
/// WS 的 `EMERGENCY_*` 都走 `APP_NOTIFICATION` 信封、不带 `eventId`（`api_spec.yaml:1174-1176`），
/// 而 `POST /api/emergency/trigger` 的 `status` 只是触发那一刻的快照，之后的推进不回写。
/// 所以冷启动、重连、以及「我到底还有没有一条没结束的求助」都只能问这个端点。
/// `data` 为 `null` 表示当前没有未终态事件。原始坐标此处一律为 null，只给 `hasGpsLocation`。
struct EmergencyEventResponse: Codable, Sendable, Equatable {
    let id: Int64
    let orderId: Int64?
    /// 受助者（盲人）ID。⚠️ 不是触发者 —— 志愿者代触发时这里仍是盲人。
    let userId: Int64?
    /// **故意是 `String` 而不是 `EmergencyEventStatus`**，与 `EmergencyTriggerResponse.status` 同因：
    /// 可选枚举只对「字段缺失/为 null」宽容，对「值存在但不认识」会直接抛 `dataCorrupted`，
    /// 整个响应连带解不出。这里是 SOS 恢复的唯一通道，后端加一个状态值就让它静默失效
    /// （`refreshActiveEvent` 的 catch 会把异常吞掉），表现是「有进行中的求助但界面说没有」。
    /// 已用 `/tmp` 下的独立解码探针复现过这条崩法，不是假想。
    let status: String?
    let triggerType: String?
    let hasGpsLocation: Bool?

    var eventStatus: EmergencyEventStatus {
        status.flatMap(EmergencyEventStatus.init(rawValue:)) ?? .unknown
    }
}

/// `GET /api/emergency/active` 的信封。**`success` 故意是非可选的**：`URLSessionAPIClient` 先试信封
/// 再试裸解码，只有当内层 `data` 解不出这个类型时才会退回外层，而「没有进行中的事件」时 `data` 就是
/// `null` —— 用非可选字段把内层解码逼失败，是这里能同时接住 `data: null` 和 `data: {...}` 的原因。
struct EmergencyActiveEnvelope: Codable, Sendable, Equatable {
    let success: Bool
    let data: EmergencyEventResponse?
}

/// `PUT /api/emergency/{eventId}/cancel` 的裸响应体（`{success, eventId, status}`）。
/// 受助者本人撤销误触的唯一出口；志愿者没有撤销权（403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`）。
struct EmergencyCancelResponse: Codable, Sendable, Equatable {
    let success: Bool
    let eventId: Int64?
    let status: String?
}

/// `PUT /api/emergency/{eventId}/volunteer-response?action=NEED_HELP` 的裸响应体。
///
/// 只有 `NEED_HELP` 一个可用取值：`FALSE_ALARM` 恒 403，枚举值留在后端 schema 里只因它仍是
/// `VolunteerAction` 的合法值（`api_spec.yaml:302-310`）。这里**故意不定义 falseAlarm**，
/// 让「志愿者端不做误触按钮」这条约束在类型层面就无法违反。
struct VolunteerEmergencyAcknowledgement: Codable, Sendable, Equatable {
    let success: Bool
    let eventId: Int64?
    let action: String?
}

// MARK: - Location Source

/// 不做未知值兜底：唯一持有者 `LocationPoint` 不是 `Codable`，取值全由客户端自己产生，
/// 不经网络解码。（`Codable` 只是历史遗留标注。）
enum LocationSource: String, Codable, Sendable {
    case deviceLocation = "device_location"
    case manual = "manual"
    case demoDefault = "demo_default"
}

// MARK: - Location (Internal helper for map display)

struct LocationPoint: Sendable {
    let latitude: Double
    let longitude: Double
    let addressText: String?
    let source: LocationSource

    init(latitude: Double, longitude: Double, addressText: String?, source: LocationSource = .deviceLocation) {
        self.latitude = latitude
        self.longitude = longitude
        self.addressText = addressText
        self.source = source
    }

    var displayAddress: String {
        addressText ?? "(\(String(format: "%.4f", latitude)), \(String(format: "%.4f", longitude)))"
    }
}

// MARK: - Blind Location

struct BlindLocationRequest: Codable, Sendable {
    let latitude: Double
    let longitude: Double
}

// MARK: - Volunteer Location Response

struct VolunteerLocationResponse: Codable, Sendable {
    let success: Bool
    let code: Int?
    let message: String?
    let data: VolunteerLocationData?
}

struct VolunteerLocationData: Codable, Sendable {
    let orderId: Int64?
    let status: RunOrderStatus?
    let lat: Double?
    let lng: Double?
    let updatedAt: String?

    var coordinateIsValid: Bool {
        guard let lat, let lng else { return false }
        return (-90...90).contains(lat) && (-180...180).contains(lng)
    }
}
