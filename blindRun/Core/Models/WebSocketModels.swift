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
    /// 出发中的预计到达。剩余分钟变化 ≥1 才推，不落通知日志 —— 重连后读订单详情的 `eta`。
    case orderEtaUpdated = "ORDER_ETA_UPDATED"
    /// 汇合距离档位变了才推，只推陪跑员。⚠️ 一侧先到时会先推一条 `UNKNOWN`。
    case meetDistanceBucket = "MEET_DISTANCE_BUCKET"
    /// 邀请被撤回（后端 #371，只走 WS）。按 `inviteId` 指认是哪一张。
    case inviteWithdrawn = "INVITE_WITHDRAWN"
}

// MARK: - Outgoing Messages (Client -> Server)

nonisolated struct WSLocationUpdateMessage: Codable, Sendable, Equatable {
    let type: String
    let lat: Double
    let lng: Double
    // 以下五个可选（`websocket-protocol.md` v1.2.0，DECISIONS D10）。合成编码对 Optional 走
    // `encodeIfPresent`，nil 时整个键不出现 —— 契约要求「拿不到就不传，别传 0」。
    /// 水平精度（米）。
    let hAcc: Double?
    /// 瞬时速度（m/s）。后端只存不算。
    let speed: Double?
    /// 气压计相对海拔（米）。
    let alt: Double?
    /// 本次跑步起的**累计**步数（后端 10 秒抽稀会丢中间的条，增量会丢步）。
    let steps: Int?
    /// 步/分钟（`CMPedometer.currentCadence` 是步/秒，已 ×60）。
    let cadence: Int?
    /// 跑者手机电量 0–1（V16，⚠️ 推定字段名，后端 BE-2 合并后核对）。只跑者带。
    let batteryLevel: Double?

    init(
        lat: Double,
        lng: Double,
        hAcc: Double? = nil,
        speed: Double? = nil,
        alt: Double? = nil,
        steps: Int? = nil,
        cadence: Int? = nil,
        batteryLevel: Double? = nil
    ) {
        self.type = WSMessageType.locationUpdate.rawValue
        self.lat = lat
        self.lng = lng
        self.hAcc = hAcc
        self.speed = speed
        self.alt = alt
        self.steps = steps
        self.cadence = cadence
        self.batteryLevel = batteryLevel
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
    /// 跑者定位精度（米）。盲人端没带时**整个键不出现**（2026-09-26 追加），汇合页方位扇形宽度据此画。
    var accuracyM: Double?
}

/// `ORDER_ETA_UPDATED`。`eta` 与订单详情的 `eta` 同形。
nonisolated struct WSOrderEtaUpdated: Decodable, Sendable {
    let orderId: Int64
    let eta: EtaView
}

/// `MEET_DISTANCE_BUCKET`。`distanceBucket` 是开放枚举，未知值按 `UNKNOWN`。
nonisolated struct WSMeetDistanceBucket: Decodable, Sendable {
    let orderId: Int64
    let meet: MeetView

    private enum CodingKeys: String, CodingKey { case orderId }

    init(from decoder: Decoder) throws {
        orderId = try decoder.container(keyedBy: CodingKeys.self).decode(Int64.self, forKey: .orderId)
        // `distanceBucket` / `farDistanceKm` 平铺在信封顶层，形状与 `MeetView` 一致。
        meet = try MeetView(from: decoder)
    }
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
    /// 部分事件的信封另带 `orderId`（2026-09-26 起的陪跑员订单页 v2 事件都有）。
    /// 旧事件没有这个键 —— 下面 `overriddenBody` 那段「契约盲区」的注释仍然成立，别拿它当普遍可用。
    let orderId: Int64?
    /// 只有 `RUNNER_RING` 带：响到这一刻为止（后端 `LocalDateTime`，无时区）。
    let until: String?

    init(
        type: String,
        eventId: Int64?,
        messageId: String? = nil,
        eventType: String,
        title: String?,
        body: String,
        ttsText: String?,
        priority: String?,
        timestamp: String?,
        orderId: Int64? = nil,
        until: String? = nil
    ) {
        self.orderId = orderId
        self.until = until
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
        case type, eventId, messageId, eventType, title, body, ttsText, priority, timestamp, orderId, until
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
        // `try?`：信封里这个键是附带信息，类型对不上时不该让整条通知（可能是求助）解不出来。
        orderId = (try? envelope.decodeIfPresent(Int64.self, forKey: .orderId)) ?? nil
        until = (try? envelope.decodeIfPresent(String.self, forKey: .until)) ?? nil
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
    /// 服务端算的两人距离（`websocket-protocol.md` EMERGENCY_VOLUNTEER_ALERT）。只拿来分档，不上屏。
    var distanceMeters: Double? = nil
    /// `NEARBY` / `CLOSE` / `FAR` / `UNKNOWN`，开放枚举，所以是 `String`。
    var distanceBand: String? = nil

    /// 能当兜底用的服务端距离。`UNKNOWN` 与不认识的档位一律当没有 ——
    /// 契约原话：UNKNOWN 时不要显示「0 米」或「就在附近」，整行不显示。
    var fallbackDistanceMeters: Double? {
        guard let distanceBand, ["NEARBY", "CLOSE", "FAR"].contains(distanceBand) else { return nil }
        return distanceMeters
    }
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
    case orderEtaUpdated(WSOrderEtaUpdated)
    case meetDistanceBucket(WSMeetDistanceBucket)
    case inviteWithdrawn(WSInviteWithdrawn)
    case unknown(String)
}
