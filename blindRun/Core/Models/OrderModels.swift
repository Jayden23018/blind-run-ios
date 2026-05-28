import Foundation

// MARK: - Order Status

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

    var displayName: String {
        switch self {
        case .pendingMatch: return "匹配中"
        case .pendingAccept: return "待确认"
        case .inProgress: return "进行中"
        case .driverEnRoute: return "志愿者出发中"
        case .driverArrived: return "志愿者已到达"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        case .rematching: return "重新匹配中"
        case .noVolunteer: return "暂无志愿者"
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
        }
    }

    /// Whether the order can be cancelled by user
    var canCancel: Bool {
        switch self {
        case .pendingMatch, .pendingAccept, .inProgress:
            return true
        default:
            return false
        }
    }

    /// Whether the emergency trigger is available
    var canTriggerEmergency: Bool {
        switch self {
        case .inProgress, .driverEnRoute, .driverArrived:
            return true
        default:
            return false
        }
    }
}

// MARK: - Pace & Route Preferences

enum PacePreference: String, Codable, CaseIterable, Sendable {
    case walkRun = "WALK_RUN"
    case easy = "EASY"
    case moderate = "MODERATE"
    case fast = "FAST"
    case noPreference = "NO_PREFERENCE"

    var displayName: String {
        switch self {
        case .walkRun: return "走跑结合"
        case .easy: return "轻松"
        case .moderate: return "中等"
        case .fast: return "快速"
        case .noPreference: return "无偏好"
        }
    }
}

enum RoutePreference: String, Codable, CaseIterable, Sendable {
    case parkTrail = "PARK_TRAIL"
    case street = "STREET"
    case track = "TRACK"
    case noPreference = "NO_PREFERENCE"

    var displayName: String {
        switch self {
        case .parkTrail: return "公园步道"
        case .street: return "街道"
        case .track: return "跑道"
        case .noPreference: return "无偏好"
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
}

// MARK: - Paginated Order Response

struct PagedOrderResponse: Codable, Sendable {
    let content: [OrderDetailResponse]
    let totalElements: Int64
    let totalPages: Int
    let number: Int
    let size: Int
    let first: Bool
    let last: Bool
    let empty: Bool
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
    let id: Int64
    let status: RunOrderStatus
    let message: String?
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

// MARK: - Location Source

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
    let lat: Double?
    let lng: Double?
    let updatedAt: String?
}
