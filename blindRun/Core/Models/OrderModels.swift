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

    /// Whether the emergency trigger is available
    var canTriggerEmergency: Bool {
        showsEmergencyPlaceholder
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

    var showsEmergencyPlaceholder: Bool {
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
    let totalElements: Int64?
    let totalPages: Int?
    let number: Int?
    let size: Int?
    let first: Bool?
    let last: Bool?
    let empty: Bool?

    /// Flexible decoder: handles both paged response and direct array from backend
    init(from decoder: Decoder) throws {
        // First try decoding as a paged response object
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.content = (try? container.decode([OrderDetailResponse].self, forKey: .content)) ?? []
            self.totalElements = try? container.decode(Int64.self, forKey: .totalElements)
            self.totalPages = try? container.decode(Int.self, forKey: .totalPages)
            self.number = try? container.decode(Int.self, forKey: .number)
            self.size = try? container.decode(Int.self, forKey: .size)
            self.first = try? container.decode(Bool.self, forKey: .first)
            self.last = try? container.decode(Bool.self, forKey: .last)
            self.empty = try? container.decode(Bool.self, forKey: .empty)
        } else if let array = try? decoder.singleValueContainer().decode([OrderDetailResponse].self) {
            // Fallback: backend returns a plain array
            self.content = array
            self.totalElements = Int64(array.count)
            self.totalPages = 1
            self.number = 0
            self.size = array.count
            self.first = true
            self.last = true
            self.empty = array.isEmpty
        } else {
            // Last resort: empty response
            self.content = []
            self.totalElements = 0
            self.totalPages = 0
            self.number = 0
            self.size = 0
            self.first = true
            self.last = true
            self.empty = true
        }
    }

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
