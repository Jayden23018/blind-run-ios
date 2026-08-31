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
    /// 接单前通话磨合（后端迁移 `0031`）。候选志愿者选了「有意向，想先聊聊」，订单**锁定给他**，
    /// 等盲人打过电话、双方各自表态；都说合适才转 `PENDING_ACCEPT`，任一方不合适或窗口超时
    /// （20 分钟）退回 `PENDING_MATCH` 换下一位，满 3 轮转 `NO_VOLUNTEER`。
    ///
    /// ⚠️ **这一态还没有志愿者接单**：后端 `order.volunteer` 恒为 null，候选人只存在于
    /// `dispatchCurrentVolunteerId`（`IntroCallService.markInterested`）。两个直接后果：
    /// - 志愿者调 `GET /api/orders/{id}` 会被 `OrderQueryService.getOrder` 判 403 —— 他这一刻
    ///   拿不到 `OrderDetailResponse`，志愿者侧通话页只能吃派单载荷 + `IntroCallView`。
    /// - `volunteerPhone` 也不会有值，所以本状态下的拨号一律走通话专用接口，
    ///   不走 `offersVolunteerCall` 那条双向下发号码的老路径。
    case pendingIntroCall = "PENDING_INTRO_CALL"
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
            .pendingIntroCall,
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
        case .pendingIntroCall: return "等待通话确认"
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
        case .pendingMatch, .pendingIntroCall, .pendingAccept, .inProgress, .driverEnRoute, .driverArrived, .rematching:
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
        // `.pendingIntroCall` 在列是后端明写的（`OrderLifecycleService.cancelOrder` 的盲人分支
        // 逐字写着「通话磨合期盲人随时可以放弃这一单」）：聊到一半发现今天不想跑了是正常的，
        // 漏掉会把人困在通话态直到窗口超时。
        case .pendingMatch, .pendingIntroCall, .pendingAccept, .rematching:
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
        // `.pendingIntroCall` 归跟踪侧：通话还在接单**之前**，不是服务中。
        case .pendingMatch, .pendingIntroCall, .pendingAccept, .driverEnRoute, .driverArrived, .rematching:
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
    /// 终点文字描述。`nil` = **用户未指定终点**，不是「原路返回起点」——
    /// 两者混淆会让志愿者去确认一个盲人从没说过的地点，所以 nil 时任何 UI 都不许提终点
    /// （后端 `api_spec.yaml:3535` 与 `websocket-protocol.md:429` 同一条口径）。
    let endAddress: String?
    /// 允许「有地址、无坐标」：用户说了地名但高德查不到时后端就是这么返回的。
    /// **起点没有这个宽容度**（起点无坐标就下不了单），别把两边的规则抄成一份。
    let endLatitude: Double?
    let endLongitude: Double?
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
            // 终点三项必须原样带过去。漏掉不会报错，只会让终点在每一次状态轮询后
            // 静默消失 —— 志愿者详情页上一秒有「结束地点」下一秒没有，而没人会去查
            // 一个「本来就可能为空」的字段。回归用例
            // `blindRunTests.testReplacingStatusKeepsTheEndLocation`。
            endAddress: endAddress,
            endLatitude: endLatitude,
            endLongitude: endLongitude,
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

/// 终点三元组打成一个值，**不许拆成三个平铺属性**。
///
/// 拆开的后果有先例：后端 `VoiceOrderService.Slots.fillFrom()` 的教训注释说的就是这个 ——
/// 地址三元组分别赋值会拼出「新地址 + 旧坐标」，读回念的是新地点、实际派到旧坐标，
/// 而盲人完全听不出来。打包成一个值之后，要换就整个换。
///
/// `latitude` / `longitude` 要么同在要么同缺：只带半个后端返 400「终点经纬度必须同时提供」。
/// 这个不变式由 `init` 守着，构造完就不可能坏。
struct BookingEndPlace: Equatable, Sendable {
    /// 完整地址。**下单与展示都用它**，一个字都不能少 —— 志愿者要靠门牌号找到人。
    let address: String
    /// 朗读形态（后端 `endAddressShort`），只有 POI 名。`nil` = 后端没给，念完整地址。
    ///
    /// **单独存一份而不是替换 `address`**：契约明确两者分工不同 ——
    /// 念的是名字（听得出对不对），下单带的是门牌号（走得到）。合并成一个字段就得二选一。
    private let shortAddress: String?
    let latitude: Double?
    let longitude: Double?

    /// 读回念这个。没有朗读形态时退回完整地址：念长一点总好过不念。
    var spokenAddress: String { shortAddress?.nilIfBlank ?? address }

    /// 半个坐标一律降级成「只有地名」，不是丢弃整个终点 ——
    /// 地名本身对志愿者仍有展示价值，而半个坐标没有任何意义。
    init(address: String, spokenAddress: String? = nil, latitude: Double?, longitude: Double?) {
        self.address = address
        self.shortAddress = spokenAddress
        if let latitude, let longitude {
            self.latitude = latitude
            self.longitude = longitude
        } else {
            self.latitude = nil
            self.longitude = nil
        }
    }

    /// 说了地名但高德查不到坐标。后端叫 `endAddressUnresolved`，
    /// 但判据在这边是**结构**而不是那个标志位 —— 同一事实有两个来源时只信结构。
    var isUnresolved: Bool { latitude == nil }
}

struct CreateOrderRequest: Codable, Sendable {
    let startLatitude: Double
    let startLongitude: Double
    let startAddress: String
    /// 终点三项全部可选，`nil` = 用户未指定。坐标只传一个会被后端 400 拦下 ——
    /// 构造请求时一律从 `BookingEndPlace` 取，别手拼三个字段。
    let endAddress: String?
    let endLatitude: Double?
    let endLongitude: Double?
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
    /// 「有意向，想先聊聊」—— 订单转 `PENDING_INTRO_CALL` 并锁给这位志愿者（后端迁移 `0031`）。
    ///
    /// ⚠️ **这不是接单**：后端 `order.volunteer` 仍是 null，聊崩了对志愿者也没有统计损失
    /// （`IntroCallService.markInterested` 的方法注释）。
    ///
    /// 🚨 陌生人直接发 `.accept` 会被后端 409 `INTRO_CALL_REQUIRED` 拦下
    /// （`DispatchService.java:264` 的守卫）。判据（这两人磨合成功过没有、时间够不够聊一轮）
    /// 全在后端，客户端一个都算不出来 —— 所以志愿者端一律先发 `.interested`。
    /// 详见 `VolunteerHomeViewModel.respondToDispatch` 上那段说明。
    case interested = "INTERESTED"
}

struct OrderRespondRequest: Codable, Sendable {
    let action: OrderRespondAction
}

// MARK: - Order Review

struct CreateReviewRequest: Codable, Sendable {
    let rating: Int
    let comment: String?
}

/// `GET /api/orders/{id}/reviews` 的 `data`（后端 `dto/ReviewResponse.java`）。
/// `comment` / `createdAt` 契约里显式可空；`rating` 上有 `@NotNull @Min(1) @Max(5)`，写入侧保证非空。
struct OrderReview: Decodable, Sendable, Equatable {
    let orderId: Int64?
    let rating: Int
    let comment: String?
    /// 后端 `LocalDateTime.toString()`，可能带小数秒。展示走 `String.displayDateTime`。
    let createdAt: String?
}

/// `GET /api/orders/{id}/reviews` 的整个响应体：裸 `Map`，只有一个 `data` 键，
/// **不走 `ApiResponse` 信封**（`ReviewController.java:41-48`）。
/// 尚未评价时是 200 + `data: null`，不是 404 —— 这是正常业务状态，不是错误。
struct OrderReviewEnvelope: Decodable, Sendable, Equatable {
    let data: OrderReview?

    private enum CodingKeys: String, CodingKey { case data }

    /// 自定义 `init(from:)` 会顶掉合成的逐成员初始化器，而 `MockAPIClient` 需要直接构造它。
    init(data: OrderReview?) {
        self.data = data
    }

    /// 合成的 `Decodable` 在这里是错的，理由是 `APIPayloadDecoder` 的「信封优先」：
    /// 它会先拿 `APIEnvelopeResponse<OrderReviewEnvelope>` 去解，把内层的
    /// `{orderId, rating, ...}` 当成本类型解 —— 合成版对缺失的 `data` 键宽容，
    /// 于是**解得出来、值是 nil**，一条真实评价被静默吞成「无评价」。
    /// 要求 `data` 键必须存在，就让那条错误路径解不出来、退回裸解，两种响应体都落到正确分支。
    /// （`EmergencyActiveEnvelope` 用非可选 `success` 达到同一目的，那边有 `success` 可用，这边没有。）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.data) else {
            throw DecodingError.keyNotFound(
                CodingKeys.data,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "缺少 data 键，不是 GET /api/orders/{id}/reviews 的响应体"
                )
            )
        }
        data = try container.decodeIfPresent(OrderReview.self, forKey: .data)
    }
}

// MARK: - Order Status Log

/// `GET /api/orders/{id}/status-logs` 的一条记录（后端 `dto/OrderStatusLogResponse.java`）。
/// 响应体是**裸数组**，按 `changedAt` **倒序**（最新在前，`OrderStatusLogRepository:16`），客户端不再排序。
///
/// 可空性取自实体的列定义而不是 spec（spec 没写 `required`）：
/// `toStatus` / `changedAt` 是 `nullable = false`，`fromStatus`（首条无前序状态）与 `remark` 可空。
/// 未取用 `changedBy` —— 它是原始 userId，对用户没有展示价值。
struct OrderStatusLog: Decodable, Sendable, Equatable, Identifiable {
    let id: Int64
    let fromStatus: RunOrderStatus?
    let toStatus: RunOrderStatus
    let changedAt: String
    let remark: String?

    /// 这一条要念给用户听的话。
    ///
    /// 后端 12 处 `logStatusChange` 里有 11 处的 `remark` 就是可直接朗读的中文
    /// （「志愿者已出发」「服务完成」「匹配超时自动取消」…），且比 `toStatus.displayName` 更具体，
    /// 所以默认原样用。唯一的例外是取消那一条：它拼的是原始枚举
    /// （`OrderLifecycleService.java:260` 的 `"取消方=" + CancelledBy`），直接渲染会对盲人
    /// 念出「取消方=BLIND」。
    ///
    /// ponytail: 只翻译这一个已知前缀，后端再塞第二个机器串就会漏。上限已知，
    /// 升级路径是让后端把 `remark` 定成展示串或另给一个 reasonCode（已进 handoff 待确认）。
    var displayText: String {
        guard let remark = remark?.nilIfBlank else { return toStatus.displayName }
        guard remark.hasPrefix(Self.cancelledByPrefix) else { return remark }
        switch String(remark.dropFirst(Self.cancelledByPrefix.count)).trimmed {
        case "BLIND": return "你取消了订单"
        case "VOLUNTEER": return "志愿者取消了订单"
        case "SYSTEM": return "系统自动取消了订单"
        default: return toStatus.displayName
        }
    }

    private static let cancelledByPrefix = "取消方="
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

/// `GET /api/orders/active` 的信封（盲人端冷启动 / 断线重连恢复）。
///
/// 写法与理由与上面的 `EmergencyActiveEnvelope` **完全相同**，不是复制粘贴的巧合：
/// 两个端点是后端刻意做成一对的（形状一致），`success` 非可选同样是靠它逼内层解码失败，
/// 才能同时接住「没有活跃订单」的 `data: null` 和有订单时的 `data: {...}`。
///
/// 存在的理由：此前盲人冷启动走 `GET /api/orders/mine`（分页历史，默认 `size=10`）再由客户端
/// 挑出活跃那条。那条路能跑，但依赖两条**没写进契约**的性质 —— 盲人同时只能有一条活跃订单、
/// 而且它一定落在 `createdAt` 倒序的前 10 条里。这个端点把「哪些状态算活着」交回服务端，
/// 后端加状态时客户端不必跟。
/// 不跟 `EmergencyActiveEnvelope` 一样加 `Equatable`：`OrderDetailResponse` 本身不是 Equatable，
/// 而为了一个信封给那个 30 多字段的 DTO 加合成实现，代价远大于收益。
struct ActiveOrderEnvelope: Codable, Sendable {
    let success: Bool
    let data: OrderDetailResponse?
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

/// `GET /api/blind/volunteer-location` 的 `data`。五个键：
/// `lat` / `lng`（GCJ-02）、`orderId`、`status`、`updatedAt`（`api_spec.yaml:2352-2362`）。
///
/// 这个结构体上的两个字段都有过一次「看着在、实际从未生效」的历史，改动前先读注释：
/// `status` 曾因后端键名是 `orderStatus` 而恒为 nil，`updatedAt` 曾根本不存在。
/// 两个都在 2026-08-20（后端 `119c810`）对齐了。
struct VolunteerLocationData: Codable, Sendable {
    let orderId: Int64?
    /// 订单当前状态，与 `GET /api/orders/{id}` 同源，**同一时刻可能领先于**客户端上一次轮询到的值。
    ///
    /// 🔴 **不得用它否掉坐标** —— 契约原话「坐标是这个端点存在的唯一理由」。
    /// 2026-08-20 之前后端发的键叫 `orderStatus`，这个字段恒为 nil，那条比较从未真正执行过；
    /// 改名之后它会第一次生效，所以「保持原样」在那一刻等价于**新增一条会否掉坐标的分支**。
    let status: RunOrderStatus?
    /// 位置采样时刻，**epoch 毫秒**（与 WS `VOLUNTEER_LOCATION_UPDATE` 的 `timestamp` 同格式同来源）。
    ///
    /// ⚠️ 不是 ISO-8601 字符串。上一版这里是 `String?` + `ISO8601DateFormatter`，
    /// 而后端当时压根不发这个字段 —— 于是新鲜度闸恒 nil 恒 return，兜底 100% 静默失效。
    /// 拿它做判断必须**失败开放**（字段缺失就放行），理由见
    /// `BlindOrderStatusViewModel.volunteerFallbackCoordinate`。
    let updatedAt: Int64?
    let lat: Double?
    let lng: Double?

    var coordinateIsValid: Bool {
        guard let lat, let lng else { return false }
        return (-90...90).contains(lat) && (-180...180).contains(lng)
    }
}
