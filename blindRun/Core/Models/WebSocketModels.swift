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

    init(
        lat: Double,
        lng: Double,
        hAcc: Double? = nil,
        speed: Double? = nil,
        alt: Double? = nil,
        steps: Int? = nil,
        cadence: Int? = nil
    ) {
        self.type = WSMessageType.locationUpdate.rawValue
        self.lat = lat
        self.lng = lng
        self.hAcc = hAcc
        self.speed = speed
        self.alt = alt
        self.steps = steps
        self.cadence = cadence
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

    /// 这一单要不要先通电话磨合。**决定 `/respond` 发哪个 `action`**（见 `dispatchRespondAction`）。
    ///
    /// ⚠️ **契约把它标成「必填」，这里却是 optional —— 是刻意的，不要改成非可选。**
    /// 非可选意味着缺这个键时 `WSNewOrder` 整条解不出来，而
    /// `WebSocketService.decodeTextMessage` 对解不出的**消息**是丢弃：志愿者连派单弹窗都看不到，
    /// 静默退出派单池，而盲人正在等这一轮。缺失时落回的 `INTERESTED` 后端在
    /// `app.intro-call.enabled` 开与关两种情况下都放行（`DispatchService.introCallEnabled`
    /// 的注释：关掉只是不再**强制**），所以降级路径本身是通的 —— 代价只是熟人多打一通电话，
    /// 正是这个字段上线前的既有行为。
    /// 缺失不是静默的：`WebSocketService` 会把 `failedField: "requiresIntroCall"` 记进派单诊断，
    /// 那条诊断渲染在志愿者首页（`VolunteerHomeView` 的「派单诊断：…」）。
    ///
    /// 🚨 **不许在客户端自己推算这个值**（例如拿 `plannedStart - now` 跟 20 分钟比）：
    /// 判断的另一半「这两人磨合成功过没有」客户端根本拿不到，窗口长度又是后端配置
    /// （`app.intro-call.window-minutes`）。自己算必然与后端守卫漂移，
    /// 而漂移的表现是「界面说能直接接、后端回 409」。
    /// 后端已把这个判断收成一份（`DispatchService.introCallWindowFits`），三个消费者共用。
    let requiresIntroCall: Bool?

    /// 配速区间与本次计划里程。契约里从 2026-08-09 就在 `NEW_ORDER` 上
    /// （`websocket-protocol.md` 的 NEW_ORDER 字段表），客户端此前没解码。
    ///
    /// 接进来的理由：设计交付文档 v3 §5 的「邀请」屏要显示「跑多远 / 配速」——
    /// 那是志愿者判断「我跟不跟得下来」的两个量，而定性档位（`pacePreference`）答不了。
    /// 三项**接单前可见**的判据与 `pacePreference` / `hasGuideDog` 一致：取值空间封闭
    /// （数值区间可以逐个判定给陌生人看行不行），自由文本才一律推迟到接单后（`AGENTS.md` §8）。
    ///
    /// ⚠️ 用户没填时后端**整个键不出现**（不发 `null`），所以缺值 = 那一行不渲染，
    /// 不是显示「未填写」。三项声明成 `var` 只为让 memberwise init 自动给 nil 默认值 ——
    /// 用例里的构造点因此不必各加三行，同 `OrderDetailResponse.volunteerId` 那条。
    var paceMinSecondsPerKm: Int?
    var paceMaxSecondsPerKm: Int?
    var plannedDistanceMeters: Int?

    /// 邀请卡跑者行那几项（后端 #306，2026-09-18 起两个入口都有）。前四项档案缺失时**整键不出现**，
    /// 缺 = 那一项不渲染，**不脑补默认值**（把「不知道」显示成「全盲」同样是错的）。
    /// 全部接成 `String?`：开放枚举，认不出的取值由展示层兜底，不许整条派单解不出来。
    var visionLevel: String?
    var tetherPreference: String?
    var chatPreference: String?
    var routePreference: String?
    /// 你和这位盲人一起跑完过几单。契约里**必填、0 也下发**；可选只为缺键时不崩 ——
    /// 缺键 = 什么都不显示，`0` = 「第一次一起跑」，两者在卡片上说的话不同。
    var completedTogetherCount: Int?
    /// 预计时长（#357，2026-09-25 起在推送里）。与 `AvailableOrderResponse` 同名同值。
    var expectedDurationMinutes: Int?

    /// 收到这条派单时该发的 `action`。「发哪个」只在这里判一次。
    ///
    /// `false` 的三种成因（通话功能整体关闭 / 这两人已磨合成功过 / 距开跑已不够聊一轮）
    /// 客户端**不需要也无法区分**，所以界面上不解释原因，只把主按钮换成「接单」。
    var dispatchRespondAction: OrderRespondAction {
        (requiresIntroCall ?? true) ? .interested : .accept
    }
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
    case unknown(String)
}
