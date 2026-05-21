import Foundation

// MARK: - User Role

enum UserRole: String, Codable, CaseIterable, Sendable {
    case blindRunner = "blind_runner"
    case volunteer = "volunteer"

    var displayName: String {
        switch self {
        case .blindRunner:
            return "视障跑者"
        case .volunteer:
            return "志愿者"
        }
    }
}

// MARK: - User DTO

struct UserDto: Codable, Identifiable, Sendable {
    let id: String
    let phoneNumber: String
    let nickname: String?
    let roles: [UserRole]
    let activeRole: UserRole?
    let createdAt: String?
    let updatedAt: String?
}

struct UserMeResponse: Codable, Sendable {
    let user: UserDto
    let blindRunnerProfile: BlindRunnerProfileDto?
    let volunteerProfile: VolunteerProfileDto?
}

// MARK: - Auth

struct PhoneLoginRequest: Codable, Sendable {
    let phoneNumber: String
    let verificationCode: String
}

struct AuthResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let user: UserDto
}

struct SwitchRoleRequest: Codable, Sendable {
    let activeRole: UserRole
}
