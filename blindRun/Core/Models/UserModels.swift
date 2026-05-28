import Foundation

// MARK: - User Role

enum UserRole: String, Codable, CaseIterable, Sendable {
    case blind = "BLIND"
    case volunteer = "VOLUNTEER"
    case unset = "UNSET"

    var displayName: String {
        switch self {
        case .blind:
            return "视障跑者"
        case .volunteer:
            return "志愿者"
        case .unset:
            return "未设置"
        }
    }
}

// MARK: - Auth Requests

struct SendCodeRequest: Codable, Sendable {
    let phone: String
}

struct VerifyCodeRequest: Codable, Sendable {
    let phone: String
    let code: String
}

// MARK: - Auth Response

struct LoginResponse: Codable, Sendable {
    let token: String
    let userId: Int64
    let role: String?
}

// MARK: - Role Switch

struct SetRoleRequest: Codable, Sendable {
    let role: UserRole
}

/// Response from POST /api/user/role - contains new token
struct SetRoleResponse: Codable, Sendable {
    let success: Bool?
    let role: String?
    let token: String?
}

// MARK: - Generic API Success Response

struct ApiSuccessResponse: Codable, Sendable {
    let success: Bool?
    let message: String?
}
