import Foundation

// MARK: - Volunteer Dispatch Summary

struct DispatchStatusRequest: Codable, Sendable {
    let wantsDispatch: Bool
}

/// `GET /api/volunteer/dispatch-summary` 的 `notAvailableReasons` 取值。
///
/// 后端权威定义见 `demo/src/main/java/com/example/demo/entity/DispatchBlockReason.java`，
/// **后端只有三个值**：`DISPATCH_DISABLED` / `NOT_VERIFIED` / `OFFLINE`
/// （引导优先级：先认证 → 再开接单开关 → 最后上线定位）。
///
/// 客户端刻意不再多定义后端不会下发的取值：Mock 曾造 `REGISTRATION_INCOMPLETE` /
/// `ACTIVE_ORDER`，导致 Mock 永远不会走 `NOT_VERIFIED` 分支，「整份首页数据被静默吞成
/// 全 nil」的解码 bug 因此活到了真机联调才暴露。新增取值必须先在后端枚举里存在。
///
/// 未知取值一律落到 `.unknown` 而不是解码抛错 —— 严格解码会让整份
/// `VolunteerDispatchSummaryResponse` 连同积分、覆盖范围、订单列表一起丢失。
enum VolunteerDispatchNotAvailableReason: String, Codable, CaseIterable, Sendable {
    // MARK: 后端权威取值（DispatchBlockReason）
    case dispatchDisabled = "DISPATCH_DISABLED"
    case notVerified = "NOT_VERIFIED"
    case offline = "OFFLINE"

    /// 后端新增原因时的兜底，避免整份响应解码失败。
    case unknown = "UNKNOWN"

    /// 刻意排除 `.unknown`：它不是一个真实原因，不应出现在任何遍历产生的选项里。
    static var allCases: [VolunteerDispatchNotAvailableReason] {
        [
            .dispatchDisabled,
            .notVerified,
            .offline
        ]
    }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = VolunteerDispatchNotAvailableReason(rawValue: rawValue) ?? .unknown
    }

    var displayText: String {
        switch self {
        case .dispatchDisabled:
            return "已关闭接单"
        case .notVerified:
            return "尚未通过资质认证"
        case .offline:
            return "当前未在线"
        case .unknown:
            return "暂时无法接单，请稍后重试或更新 App"
        }
    }
}

struct VolunteerDispatchSummaryResponse: Codable, Sendable {
    let canDispatch: Bool?
    let notAvailableReasons: [VolunteerDispatchNotAvailableReason]?
    let wantsDispatch: Bool?
    let isOnline: Bool?
    let lastLat: Double?
    let lastLng: Double?
    let lastLocationAt: String?
    let coverageRadiusKm: Double?
    let isWithinServiceTime: Bool?
    let availableTimeSlots: [VolunteerAvailableTimeSlot]?
    let avgRating: Double?
    let totalRatings: Int?
    let totalDispatched: Int?
    let totalAccepted: Int?
    let totalDeclined: Int?
    let totalTimeout: Int?
    let totalCompleted: Int?
    let totalCancelled: Int?
    let acceptanceRate: Double?
    let pointsBalance: Int?
    let activeOrders: [VolunteerDispatchSummaryActiveOrder]?
    let recentOrders: [VolunteerDispatchSummaryRecentOrder]?

    var resolvedPointsBalance: Int {
        pointsBalance ?? ((totalCompleted ?? 0) * 100)
    }

    var completedCount: Int {
        totalCompleted ?? 0
    }

    var reasonText: String {
        let reasons = notAvailableReasons ?? []
        guard !reasons.isEmpty else {
            return canDispatch == true ? "已上线，等待系统派单" : "服务端未返回不可接单原因"
        }
        // 全是未识别取值时不能拼出空串；混合时只展示能解释清楚的那些。
        let recognized = reasons.filter { $0 != .unknown }
        guard !recognized.isEmpty else {
            return VolunteerDispatchNotAvailableReason.unknown.displayText
        }
        return recognized.map(\.displayText).joined(separator: "、")
    }

    var dispatchStatusText: String {
        canDispatch == true ? "已上线，等待系统派单" : reasonText
    }

    var coverageText: String {
        guard let coverageRadiusKm else { return "覆盖范围待同步" }
        return "当前覆盖约 \(coverageRadiusKm.cleanDisplay) 公里"
    }

    var ratingText: String {
        guard let avgRating else { return "--" }
        return String(format: "%.1f", avgRating)
    }

    var acceptanceRateText: String {
        guard let acceptanceRate else { return "--" }
        return "\(Int((acceptanceRate * 100).rounded()))%"
    }
}

struct VolunteerDispatchSummaryActiveOrder: Codable, Identifiable, Sendable {
    let orderId: Int64
    let status: RunOrderStatus
    let plannedStartTime: String?
    let plannedEndTime: String?
    let startAddress: String?
    let startLatitude: Double?
    let startLongitude: Double?
    let blindName: String?
    let blindPhoneMasked: String?
    let acceptedAt: String?

    var id: Int64 { orderId }

    var orderDetail: OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: startAddress,
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            // 派单摘要契约里没有终点字段（`VolunteerDispatchSummary` 是接单前后共用的轻量摘要），
            // 这里不能编。要看终点走 `GET /api/orders/{id}` 的完整详情。
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStartTime,
            plannedEnd: plannedEndTime,
            blindName: blindName,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: acceptedAt,
            createdAt: nil,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}

struct VolunteerDispatchSummaryRecentOrder: Codable, Identifiable, Sendable {
    let orderId: Int64
    let status: RunOrderStatus
    let plannedStartTime: String?
    let completedAt: String?
    let startAddress: String?
    let blindName: String?
    let rating: Int?
    let pointsDelta: Int?

    var id: Int64 { orderId }

    var resolvedPointsDelta: Int? {
        if let pointsDelta { return pointsDelta }
        return status == .completed ? 100 : nil
    }

    var pointsText: String {
        guard let resolvedPointsDelta else { return "--" }
        return resolvedPointsDelta > 0 ? "+\(resolvedPointsDelta)" : "\(resolvedPointsDelta)"
    }
}

private extension Double {
    var cleanDisplay: String {
        if rounded() == self {
            return String(Int(self))
        }
        return String(format: "%.1f", self)
    }
}
