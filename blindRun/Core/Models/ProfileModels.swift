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
        case name = "name"
        case runningPace
        case specialNeeds
        case verifyStatus
        case visionLevel
        case hasGuideDog
        case tetherPreference
        case chatPreference
        case defaultPace
    }

    init(
        name: String? = nil,
        runningPace: String? = nil,
        specialNeeds: String? = nil,
        verifyStatus: String? = nil,
        visionLevel: String? = nil,
        hasGuideDog: Bool? = nil,
        tetherPreference: String? = nil,
        chatPreference: String? = nil,
        defaultPace: PacePreference? = nil
    ) {
        self.name = name
        self.runningPace = runningPace
        self.specialNeeds = specialNeeds
        self.verifyStatus = verifyStatus
        self.visionLevel = visionLevel
        self.hasGuideDog = hasGuideDog
        self.tetherPreference = tetherPreference
        self.chatPreference = chatPreference
        self.defaultPace = defaultPace
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
        case name = "name"
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
    let adminReviewStatus: String?
    let registrationStep: String?
    let canAcceptOrders: Bool?
    let isAvailable: Bool?
    let wantsDispatch: Bool?
    let availableTimeSlots: [VolunteerAvailableTimeSlot]?
    let acceptsGuideDog: Bool?
    let paceRange: PacePreference?

    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case verificationStatus
        case adminReviewStatus
        case registrationStep
        case canAcceptOrders
        case isAvailable
        case wantsDispatch
        case availableTimeSlots
        case acceptsGuideDog
        case paceRange
    }

    init(
        name: String? = nil,
        verificationStatus: String? = nil,
        adminReviewStatus: String? = nil,
        registrationStep: String? = nil,
        canAcceptOrders: Bool? = nil,
        isAvailable: Bool? = nil,
        wantsDispatch: Bool? = nil,
        availableTimeSlots: [VolunteerAvailableTimeSlot]? = nil,
        acceptsGuideDog: Bool? = nil,
        paceRange: PacePreference? = nil
    ) {
        self.name = name
        self.verificationStatus = verificationStatus
        self.adminReviewStatus = adminReviewStatus
        self.registrationStep = registrationStep
        self.canAcceptOrders = canAcceptOrders
        self.isAvailable = isAvailable
        self.wantsDispatch = wantsDispatch
        self.availableTimeSlots = availableTimeSlots
        self.acceptsGuideDog = acceptsGuideDog
        self.paceRange = paceRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        verificationStatus = try container.decodeIfPresent(String.self, forKey: .verificationStatus)
        adminReviewStatus = try container.decodeIfPresent(String.self, forKey: .adminReviewStatus)
        registrationStep = try container.decodeIfPresent(String.self, forKey: .registrationStep)
        canAcceptOrders = try container.decodeIfPresent(Bool.self, forKey: .canAcceptOrders)
        wantsDispatch = try container.decodeIfPresent(Bool.self, forKey: .wantsDispatch)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? wantsDispatch
        availableTimeSlots = try container.decodeIfPresent([VolunteerAvailableTimeSlot].self, forKey: .availableTimeSlots)
        acceptsGuideDog = try container.decodeIfPresent(Bool.self, forKey: .acceptsGuideDog)
        paceRange = try container.decodeIfPresent(PacePreference.self, forKey: .paceRange)
    }
}

extension VolunteerProfileResponse {
    var isProfileCompleteForDispatch: Bool {
        guard let name, !name.trimmed.isEmpty else {
            return false
        }
        return true
    }

    var isCertificationApproved: Bool {
        verificationStatus?.lowercased() == "approved"
    }

    var isMainRegistrationCompleteWhenStatusUnavailable: Bool {
        canAcceptOrders == true ||
            registrationStep?.uppercased() == "STEP_4_COMPLETED" ||
            verificationStatus?.lowercased() == "approved"
    }

    var isAdminReviewApprovedWhenAvailable: Bool {
        guard let adminReviewStatus = adminReviewStatus?.trimmed, !adminReviewStatus.isEmpty else {
            return true
        }
        return adminReviewStatus.lowercased() == "approved"
    }

    var hasManualDispatchOptIn: Bool {
        wantsDispatch ?? isAvailable ?? false
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
    let wantsDispatch: Bool?
    let availableTimeSlots: [VolunteerAvailableTimeSlot]?
    let acceptsGuideDog: Bool?
    let paceRange: PacePreference?

    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case isAvailable
        case wantsDispatch
        case availableTimeSlots
        case acceptsGuideDog
        case paceRange
    }

    init(
        name: String? = nil,
        isAvailable: Bool? = nil,
        wantsDispatch: Bool? = nil,
        availableTimeSlots: [VolunteerAvailableTimeSlot]? = nil,
        acceptsGuideDog: Bool? = nil,
        paceRange: PacePreference? = nil
    ) {
        self.name = name
        self.isAvailable = isAvailable
        self.wantsDispatch = wantsDispatch ?? isAvailable
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
