import Foundation

// MARK: - Blind Runner Profile

struct BlindProfileResponse: Codable, Sendable {
    let name: String?
    let runningPace: String?
    let specialNeeds: String?
    let verifyStatus: String?
    let visionLevel: String?
    let hasGuideDog: Bool?
    let tetherPreference: String?
    let chatPreference: String?
    let defaultPace: PacePreference?

    private enum CodingKeys: String, CodingKey {
        case name
        case runningPace
        case specialNeeds
        case verifyStatus
        case visionLevel
        case hasGuideDog
        case tetherPreference
        case chatPreference
        case defaultPace
    }
}

struct BlindProfileUpdateRequest: Codable, Sendable {
    let name: String?
    let runningPace: String?
    let specialNeeds: String?
    let visionLevel: String?
    let hasGuideDog: Bool?
    let tetherPreference: String?
    let chatPreference: String?
    let defaultPace: PacePreference?

    private enum CodingKeys: String, CodingKey {
        case name
        case runningPace
        case specialNeeds
        case visionLevel
        case hasGuideDog
        case tetherPreference
        case chatPreference
        case defaultPace
    }
}

// MARK: - Identity Verification

struct BlindVerifyRequest: Codable, Sendable {
    let idCardName: String
    let idCardNumber: String
}

// MARK: - Volunteer Profile

struct VolunteerProfileResponse: Codable, Sendable {
    let name: String?
    let verificationStatus: String?
    let isAvailable: Bool?
    let availableTimeSlots: [VolunteerAvailableTimeSlot]?
    let acceptsGuideDog: Bool?
    let paceRange: PacePreference?

    private enum CodingKeys: String, CodingKey {
        case name
        case verificationStatus
        case isAvailable
        case availableTimeSlots
        case acceptsGuideDog
        case paceRange
    }
}

struct VolunteerAvailableTimeSlot: Codable, Sendable {
    let dayOfWeek: String?
    let startTime: String?
    let endTime: String?
}

struct VolunteerProfileUpdateRequest: Codable, Sendable {
    let name: String?
    let isAvailable: Bool?
    let availableTimeSlots: [VolunteerAvailableTimeSlot]?
    let acceptsGuideDog: Bool?
    let paceRange: PacePreference?

    private enum CodingKeys: String, CodingKey {
        case name
        case isAvailable
        case availableTimeSlots
        case acceptsGuideDog
        case paceRange
    }

    init(
        name: String? = nil,
        isAvailable: Bool? = nil,
        availableTimeSlots: [VolunteerAvailableTimeSlot]? = nil,
        acceptsGuideDog: Bool? = nil,
        paceRange: PacePreference? = nil
    ) {
        self.name = name
        self.isAvailable = isAvailable
        self.availableTimeSlots = availableTimeSlots
        self.acceptsGuideDog = acceptsGuideDog
        self.paceRange = paceRange
    }
}

// MARK: - Emergency Contact

struct EmergencyContactRequest: Codable, Sendable {
    let name: String?
    let phone: String?
    let relationship: String?
    let isPrimary: Bool?
}

struct EmergencyContactResponse: Codable, Identifiable, Sendable {
    let id: Int64
    let name: String?
    let phone: String?
    let relationship: String?
    let isPrimary: Bool?
}

// MARK: - Vision Level

enum VisionLevel: String, Codable, CaseIterable, Sendable {
    case totalBlind = "TOTAL_BLIND"
    case lowVision = "LOW_VISION"

    var displayName: String {
        switch self {
        case .totalBlind: return "全盲"
        case .lowVision: return "低视力"
        }
    }
}

// MARK: - Tether Preference

enum TetherPreference: String, Codable, CaseIterable, Sendable {
    case tetherRope = "TETHER_ROPE"
    case armHold = "ARM_HOLD"
    case verbalOnly = "VERBAL_ONLY"

    var displayName: String {
        switch self {
        case .tetherRope: return "牵引绳"
        case .armHold: return "搀扶"
        case .verbalOnly: return "仅语言引导"
        }
    }
}

// MARK: - Chat Preference

enum ChatPreference: String, Codable, CaseIterable, Sendable {
    case preferChat = "PREFER_CHAT"
    case preferQuiet = "PREFER_QUIET"
    case noPreference = "NO_PREFERENCE"

    var displayName: String {
        switch self {
        case .preferChat: return "喜欢聊天"
        case .preferQuiet: return "偏好安静"
        case .noPreference: return "无偏好"
        }
    }
}
