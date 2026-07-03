import Foundation

// MARK: - Volunteer Dispatch Summary

struct DispatchStatusRequest: Codable, Sendable {
    let wantsDispatch: Bool
}

enum VolunteerDispatchNotAvailableReason: String, Codable, CaseIterable, Sendable {
    case dispatchDisabled = "DISPATCH_DISABLED"
    case registrationIncomplete = "REGISTRATION_INCOMPLETE"
    case offline = "OFFLINE"
    case outsideServiceTime = "OUTSIDE_SERVICE_TIME"
    case noLocation = "NO_LOCATION"
    case activeOrder = "ACTIVE_ORDER"
    case notApproved = "NOT_APPROVED"

    var displayText: String {
        switch self {
        case .dispatchDisabled:
            return "已关闭接单"
        case .registrationIncomplete:
            return "注册资料未完成"
        case .offline:
            return "当前未在线"
        case .outsideServiceTime:
            return "不在可服务时间"
        case .noLocation:
            return "缺少最近定位"
        case .activeOrder:
            return "已有当前订单"
        case .notApproved:
            return "志愿者资格未通过"
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
            return canDispatch == true ? "已上线，等待系统派单" : "暂不可接收系统派单"
        }
        return reasons.map(\.displayText).joined(separator: "、")
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
