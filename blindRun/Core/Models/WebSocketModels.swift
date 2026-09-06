import Foundation

// MARK: - WebSocket Message Type

nonisolated enum WSMessageType: String, Codable, Sendable {
    // Client -> Server
    case locationUpdate = "LOCATION_UPDATE"
    case ping = "PING"

    // Server -> Client (Blind)
    case volunteerLocationUpdate = "VOLUNTEER_LOCATION_UPDATE"
    case blindLocationUpdate = "BLIND_LOCATION_UPDATE"
    case appNotification = "APP_NOTIFICATION"
    case orderStatusChanged = "ORDER_STATUS_CHANGED"
    case emergencyResolvedByVolunteer = "EMERGENCY_RESOLVED_BY_VOLUNTEER"
    // `EMERGENCY_CONTACT_NOTIFIED` 刻意不在这里：它不是顶层类型，而是 `APP_NOTIFICATION` 的一个
    // `eventType`（`websocket-protocol.md:182,248` 明确「v1 那个带 eventId 的顶层类型是设计稿、
    // 从未实现」）。处理入口是 `AppRealtimeCoordinator.emergencyKind(forEventType:)`。
    case pong = "PONG"

    // Server -> Client (Volunteer)
    case newOrder = "NEW_ORDER"
    case emergencyVolunteerAlert = "EMERGENCY_VOLUNTEER_ALERT"
}

// MARK: - Outgoing Messages (Client -> Server)

nonisolated struct WSLocationUpdateMessage: Codable, Sendable {
    let type: String
    let lat: Double
    let lng: Double

    init(lat: Double, lng: Double) {
        self.type = WSMessageType.locationUpdate.rawValue
        self.lat = lat
        self.lng = lng
    }
}

nonisolated struct WSPingMessage: Codable, Sendable {
    let type: String

    init() {
        self.type = WSMessageType.ping.rawValue
    }
}

// MARK: - Incoming Messages (Server -> Client)

/// Generic envelope to peek at message type before full decode
nonisolated struct WSMessageEnvelope: Codable, Sendable {
    let type: String
}

/// Volunteer real-time location (sent to blind user)
nonisolated struct WSVolunteerLocationUpdate: Codable, Sendable {
    let type: String
    let orderId: Int64
    let lat: Double
    let lng: Double
    let timestamp: Int64
}

/// Blind-runner real-time location (sent to the associated volunteer).
nonisolated struct WSBlindLocationUpdate: Codable, Sendable {
    let type: String
    let orderId: Int64
    let lat: Double
    let lng: Double
    let timestamp: Int64
}

/// Generic notification from backend templates
nonisolated struct WSAppNotification: Decodable, Sendable {
    let type: String
    let eventId: Int64?
    let messageId: String?
    let eventType: String
    let title: String?
    let body: String
    let ttsText: String?
    let priority: String?
    let timestamp: String?

    init(
        type: String,
        eventId: Int64?,
        messageId: String? = nil,
        eventType: String,
        title: String?,
        body: String,
        ttsText: String?,
        priority: String?,
        timestamp: String?
    ) {
        self.type = type
        self.eventId = eventId
        self.messageId = messageId
        self.eventType = eventType
        self.title = title
        self.body = body
        self.ttsText = ttsText
        self.priority = priority
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case type, eventId, messageId, eventType, title, body, ttsText, priority, timestamp
    }

    init(from decoder: Decoder) throws {
        let envelope = try decoder.container(keyedBy: CodingKeys.self)
        type = try envelope.decode(String.self, forKey: .type)
        eventId = try envelope.decodeIfPresent(Int64.self, forKey: .eventId)
        messageId = try envelope.decodeIfPresent(String.self, forKey: .messageId)
        eventType = try envelope.decode(String.self, forKey: .eventType)
        title = try envelope.decodeIfPresent(String.self, forKey: .title)
        body = try envelope.decode(String.self, forKey: .body)
        ttsText = try envelope.decodeIfPresent(String.self, forKey: .ttsText)
        priority = try envelope.decodeIfPresent(String.self, forKey: .priority)
        timestamp = try envelope.decodeIfPresent(String.self, forKey: .timestamp)
    }
}

/// `/api/notifications/since` 重连补读返回的遗漏通知。
/// 后端 `sentAt` 是 `LocalDateTime`（ISO-8601 无时区，按 Asia/Shanghai 解释），
/// 与前端回传的 `after` 参数格式一致。
nonisolated struct MissedNotificationResponse: Codable, Sendable {
    let id: Int64
    let eventType: String?
    let body: String
    let ttsText: String?
    let priority: String?
    let sentAt: String?
    let orderId: Int64?
}

/// `/api/notifications/since` 的一页。
///
/// **`hasMore` 挂在信封顶层、与 `data` 平级**（契约 `api_spec.yaml:3363`，2026-08-29 新增，
/// 且只有这一个端点会返回它），所以这里解的是信封根对象而不是 `data` 里的东西。
/// `APIPayloadDecoder` 先试 `APIEnvelopeResponse<T>`，而 `data` 是数组、解不出本类型，
/// 于是退回裸解根对象，正好读到这两个键 —— 与 `EmergencyActiveEnvelope` 同一条路。
/// `notifications` 故意**非可选**：既是那条退路的保证（缺 `data` 就整条解不出、走
/// `decodingError` 留下诊断），也免得畸形响应被静默降级成「一条通知都没有」。
nonisolated struct MissedNotificationPage: Codable, Sendable {
    let notifications: [MissedNotificationResponse]
    /// 缺失当 false：后端加这个字段之前的部署不返回它，此时退回单页行为 ——
    /// 漏补读比整页解不出要好。
    let hasMore: Bool?

    private enum CodingKeys: String, CodingKey {
        case notifications = "data"
        case hasMore
    }
}

/// Order status change notification
nonisolated struct WSOrderStatusChanged: Codable, Sendable {
    let type: String
    let messageId: String?
    let orderId: Int64
    let fromStatus: String?
    let toStatus: String
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?

    init(
        type: String,
        messageId: String? = nil,
        orderId: Int64,
        fromStatus: String?,
        toStatus: String,
        message: String?,
        ttsText: String?,
        priority: String?,
        timestamp: String?
    ) {
        self.type = type
        self.messageId = messageId
        self.orderId = orderId
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.message = message
        self.ttsText = ttsText
        self.priority = priority
        self.timestamp = timestamp
    }
}

/// Emergency resolved by volunteer (sent to blind user)
nonisolated struct WSEmergencyResolved: Codable, Sendable {
    let type: String
    let eventId: Int64
    let message: String?
    let ttsText: String?
    let priority: String?
    let timestamp: String?
}

/// Heartbeat response
nonisolated struct WSPong: Codable, Sendable {
    let type: String
    let timestamp: Int64?
}

/// New order dispatch (sent to volunteer)
///
/// ⚠️ **刻意不解 `specialNotes`。** 后端的 `NEW_ORDER` 载荷现在仍带这个字段
/// （`websocket-protocol.md:359,376`），这里不声明它 —— `JSONDecoder` 忽略多余的键，
/// 于是那段文本进不了 App 的任何一个类型，也就没有任何视图能把它渲染出来。
///
/// 理由是 `AGENTS.md §8`「接单前隐藏盲人**敏感健康信息**」。派单是串行的，一单会依次推给
/// 多个候选志愿者，而这个弹窗紧挨着「接单 / 拒绝」按钮 —— 也就是接单前。`specialNotes` 是
/// 自由文本，取值空间开放、敏感度无法预判；语音下单落地后它装的就是用户原话
/// （「我有低血糖，如果我说头晕请马上停下来」），等于广播给所有最终拒单的人。
///
/// 只删渲染那几行不够：字段还在类型上，下一个人加回去没有任何东西拦着。删字段才是根因修法，
/// 编译器从此替我们守着。接单后的完整备注走 `OrderDetailResponse.specialNotes`，那条路不变。
///
/// 回归用例 `AppRealtimeCoordinatorTests.testNewOrderCarryingSpecialNotesDecodesButNeverReachesTheClient`
/// （已验红：把字段加回来，该用例立刻失败）。
/// 对照：`pacePreference` / `hasGuideDog` 留着 —— 取值空间封闭（枚举 / 布尔），且它们是志愿者
/// 判断「我接不接得下来」的依据，藏起来只会让人盲接、接了再取消，成本落回盲人身上。
nonisolated struct WSNewOrder: Codable, Sendable {
    let type: String
    let timestamp: String?
    let orderId: Int64
    let startAddress: String?
    let startLatitude: Double?
    let startLongitude: Double?
    let distanceKm: Double?
    let plannedStart: String?
    let plannedEnd: String?
    let dispatchTimeoutSeconds: Int?
    let priority: String?
    let pacePreference: String?
    let hasGuideDog: Bool?
}

/// Emergency alert for volunteer
nonisolated struct WSEmergencyVolunteerAlert: Codable, Sendable {
    let type: String
    let eventId: Int64
    let orderId: Int64
    let userId: Int64?
    let message: String?
    let ttsText: String?
    let priority: String?
    let gpsLat: Double?
    let gpsLng: Double?
    let timestamp: String?
}

// MARK: - Parsed WebSocket Event

/// High-level event enum for consumers to switch on
nonisolated enum WSIncomingEvent: Sendable {
    case volunteerLocation(WSVolunteerLocationUpdate)
    case blindLocation(WSBlindLocationUpdate)
    case notification(WSAppNotification)
    case orderStatusChanged(WSOrderStatusChanged)
    case emergencyResolved(WSEmergencyResolved)
    case pong(WSPong)
    case newOrder(WSNewOrder)
    case emergencyAlert(WSEmergencyVolunteerAlert)
    case unknown(String)
}
