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

struct SendCodeResponse: Codable, Sendable {
    let success: Bool?
    let message: String?
    let code: String?
    let verificationCode: String?
    let smsCode: String?

    private enum CodingKeys: String, CodingKey {
        case success, message, code, verificationCode, smsCode
    }

    init(
        success: Bool?,
        message: String?,
        code: String?,
        verificationCode: String?,
        smsCode: String?
    ) {
        self.success = success
        self.message = message
        self.code = code
        self.verificationCode = verificationCode
        self.smsCode = smsCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        code = Self.decodeVerificationCodeString(from: container, forKey: .code)
        verificationCode = Self.decodeVerificationCodeString(from: container, forKey: .verificationCode)
        smsCode = Self.decodeVerificationCodeString(from: container, forKey: .smsCode)
    }

    var resolvedVerificationCode: String? {
        [verificationCode, smsCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { Self.isSixDigitVerificationCode($0) }
    }

    private static func decodeVerificationCodeString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key),
           value > 0 {
            return String(value)
        }
        return nil
    }

    private static func isSixDigitVerificationCode(_ value: String) -> Bool {
        value.range(of: #"^\d{6}$"#, options: .regularExpression) != nil
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
