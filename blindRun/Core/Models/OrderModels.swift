import Foundation

// MARK: - Order Status

enum RunOrderStatus: String, Codable, CaseIterable, Sendable {
    case matching
    case accepted
    case arrived
    case inProgress = "in_progress"
    case completed
    case cancelled
    case emergency

    var displayName: String {
        switch self {
        case .matching: return "匹配中"
        case .accepted: return "已接单"
        case .arrived: return "已到达"
        case .inProgress: return "服务中"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        case .emergency: return "求助中"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .emergency:
            return true
        default:
            return false
        }
    }
}

// MARK: - Cancellation

enum CancelledBy: String, Codable, Sendable {
    case blindRunner = "blind_runner"
    case volunteer = "volunteer"
}

enum ManualCancellationReason: String, Codable, CaseIterable, Sendable {
    case timeConflict = "time_conflict"
    case wrongLocation = "wrong_location"
    case temporaryIssue = "temporary_issue"
    case cannotContact = "cannot_contact"
    case other

    var displayName: String {
        switch self {
        case .timeConflict: return "时间不合适"
        case .wrongLocation: return "地点填写错误"
        case .temporaryIssue: return "临时有事"
        case .cannotContact: return "联系不上对方"
        case .other: return "其他"
        }
    }
}

enum CancellationReason: String, Codable, Sendable {
    case timeConflict = "time_conflict"
    case wrongLocation = "wrong_location"
    case temporaryIssue = "temporary_issue"
    case cannotContact = "cannot_contact"
    case other
    case noVolunteerAvailable = "no_volunteer_available"
}

// MARK: - Location

enum LocationSource: String, Codable, Sendable {
    case deviceLocation = "device_location"
    case manual
    case demoDefault = "demo_default"
}

struct LocationPoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let addressText: String?
    let source: LocationSource
}

// MARK: - Order DTO

struct RunOrderDto: Codable, Identifiable, Sendable {
    let id: String
    let blindRunnerUserId: String
    let blindRunnerNickname: String
    let blindRunnerPhone: String?
    let volunteerUserId: String?
    let volunteerNickname: String?
    let status: RunOrderStatus
    let startLocation: LocationPoint
    let destinationText: String?
    let appointmentTime: String
    let estimatedDurationMinutes: Int?
    let estimatedDistanceKm: Double?
    let pacePreference: String?
    let preferSameGender: Bool?
    let remark: String?
    let cancellation: CancellationDto?
    let emergencyEvent: EmergencyEventDto?
    let serviceSummary: ServiceSummaryDto?
    let rating: RatingDto?
    let createdAt: String?
    let updatedAt: String?
    let acceptedAt: String?
    let arrivedAt: String?
    let startedAt: String?
    let completedAt: String?
    let cancelledAt: String?
    let emergencyAt: String?
}

// MARK: - Request/Response DTOs

struct CreateOrderRequest: Codable, Sendable {
    let startLocation: LocationPoint
    let destinationText: String?
    let appointmentTime: String
    let estimatedDurationMinutes: Int?
    let estimatedDistanceKm: Double?
    let pacePreference: String?
    let preferSameGender: Bool?
    let remark: String?
}

struct AvailableOrderDto: Codable, Identifiable, Sendable {
    let id: String
    let blindRunnerNickname: String
    let startLocation: LocationPoint
    let destinationText: String?
    let appointmentTime: String
    let estimatedDurationMinutes: Int?
    let estimatedDistanceKm: Double?
    let pacePreference: String?
    let preferSameGender: Bool?
    let remark: String?
    let blindRunnerPhone: String?
}

struct CancelOrderRequest: Codable, Sendable {
    let cancelledBy: CancelledBy
    let cancelledReason: ManualCancellationReason
    let otherReasonText: String?
}

struct CompleteOrderRequest: Codable, Sendable {
    let summaryText: String?
}

struct RatingRequest: Codable, Sendable {
    let stars: Int
    let comment: String?
}

struct CancellationDto: Codable, Sendable {
    let id: String
    let orderId: String
    let cancelledBy: CancelledBy?
    let cancelledReason: CancellationReason
    let otherReasonText: String?
    let createdAt: String?
}

struct EmergencyEventDto: Codable, Sendable {
    let id: String
    let orderId: String
    let triggeredByRole: UserRole
    let previousStatus: RunOrderStatus
    let note: String?
    let createdAt: String?
}

struct ServiceSummaryDto: Codable, Sendable {
    let id: String
    let orderId: String
    let volunteerUserId: String
    let summaryText: String?
    let createdAt: String?
}

struct RatingDto: Codable, Sendable {
    let id: String
    let orderId: String
    let blindRunnerUserId: String
    let volunteerUserId: String
    let stars: Int
    let comment: String?
    let createdAt: String?
}
