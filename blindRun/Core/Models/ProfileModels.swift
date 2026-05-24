import Foundation

// MARK: - Emergency Contact

struct EmergencyContactDto: Codable, Sendable {
    let name: String
    let phoneNumber: String
}

// MARK: - Verification Status

enum VerificationStatus: String, Codable, Sendable {
    case notSubmitted = "not_submitted"
    case pending
    case approved
    case rejected
}

enum AdminReviewStatus: String, Codable, Sendable {
    case notSubmitted = "not_submitted"
    case pending
    case approved
    case rejected
}

// MARK: - Blind Runner Profile

struct BlindRunnerProfileDto: Codable, Identifiable, Sendable {
    let id: String
    let userId: String
    let nickname: String
    let runningExperience: String?
    let emergencyContact: EmergencyContactDto?
    let createdAt: String?
    let updatedAt: String?
}

struct BlindRunnerProfileUpsertRequest: Codable, Sendable {
    let nickname: String
    let runningExperience: String?
    let emergencyContact: EmergencyContactDto
}

// MARK: - Volunteer Profile

struct VolunteerProfileDto: Codable, Identifiable, Sendable {
    let id: String
    let userId: String
    let nickname: String
    let phoneNumber: String
    let verificationStatus: VerificationStatus
    let adminReviewStatus: AdminReviewStatus
    let isAvailable: Bool
    let pointsBalance: Int
    let createdAt: String?
    let updatedAt: String?
}

struct VolunteerProfileUpsertRequest: Codable, Sendable {
    let nickname: String
}

struct AvailabilityRequest: Codable, Sendable {
    let isAvailable: Bool
}

// MARK: - Volunteer Points

struct VolunteerPointsLedgerDto: Codable, Identifiable, Sendable {
    let id: String
    let orderId: String?
    let pointsDelta: Int
    let reason: String
    let createdAt: String?
}

struct VolunteerPointsResponse: Codable, Sendable {
    let pointsBalance: Int
    let ledger: [VolunteerPointsLedgerDto]
}

// MARK: - Shop

struct ShopItemDto: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let pointsRequired: Int
    let description: String
    let isPlaceholder: Bool
}
