import Foundation

// MARK: - User Role

/// 不做未知值兜底：所有**入站**的角色字段（`LoginResponse.role` / `SetRoleResponse.role`）
/// 本来就接成 `String`，由 `roleResolution` 做 `rawValue` 映射并把不认识的值归到 `.invalid`；
/// 枚举本身只在 `SetRoleRequest` 这条只出不进的路径上被编码。
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

/// 后端 `AuthService.sendCode` 返回 void，响应体里**没有**验证码字段，
/// 客户端只需要业务信封的 success/message/code。
struct SendCodeResponse: Codable, Sendable {
    let success: Bool?
    let message: String?
    /// 业务码，后端信封里是数字（`ApiResponse.code`），历史上也出现过字符串形态。
    let code: String?

    private enum CodingKeys: String, CodingKey {
        case success, message, code
    }

    init(
        success: Bool?,
        message: String?,
        code: String?
    ) {
        self.success = success
        self.message = message
        self.code = code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        if let stringCode = try? container.decodeIfPresent(String.self, forKey: .code) {
            code = stringCode
        } else if let intCode = try? container.decodeIfPresent(Int.self, forKey: .code) {
            code = String(intCode)
        } else {
            code = nil
        }
    }
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

/// `GET /api/auth/me` 的当前会话用户。首次选角色前 role 可缺省、为 null 或 UNSET。
struct CurrentUserResponse: Codable, Sendable, Equatable {
    let userId: Int64
    let phone: String?
    let role: String?

    enum RoleResolution: Equatable {
        case unset
        case selected(UserRole)
        case invalid
    }

    var roleResolution: RoleResolution {
        guard let role else { return .unset }
        guard let value = UserRole(rawValue: role) else { return .invalid }
        return value == .unset ? .unset : .selected(value)
    }

    var resolvedRole: UserRole? {
        guard case .selected(let role) = roleResolution else { return nil }
        return role
    }
}

struct LogoutResponse: Codable, Sendable, Equatable {
    let success: Bool
    let message: String?
}

struct DeleteAccountResponse: Codable, Sendable, Equatable {
    let success: Bool
    let message: String?
    let phoneReusable: Bool
    let allTokensInvalidated: Bool
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
