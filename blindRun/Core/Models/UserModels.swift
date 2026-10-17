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

/// 验证码登录与 `POST /api/auth/refresh` 共用的响应（契约同一个 `LoginResponse`）。
///
/// `refreshToken` / `expiresIn` 契约标必有（后端 #642），这里仍按可选解：缺了就只是不续期，
/// 回到接续期之前的行为，而不是整条登录解码失败（`AGENTS.md` 枚举 / 解码降级那条）。
struct LoginResponse: Codable, Sendable {
    let token: String
    let userId: Int64
    let role: String?
    /// 只用来调 `POST /api/auth/refresh`，存 Keychain（`RefreshCredentialStore`）。
    /// **不进 `Authorization` 头、不进任何 URL、不打日志。**
    let refreshToken: String?
    /// `token` 的有效期（秒，从签发起算）。不是常量：后端等 iOS 接完续期就会改短。
    let expiresIn: Int64?

    init(token: String, userId: Int64, role: String?, refreshToken: String? = nil, expiresIn: Int64? = nil) {
        self.token = token
        self.userId = userId
        self.role = role
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
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

    /// 邀请人的邀请码，**可选**（SPEC-E 第 4 步）。
    ///
    /// 🚩 **为什么挂在这一步而不是 `POST /api/auth/verify-code`**：后者是登录与注册合一的入口，
    /// 老用户每次登录都会经过它 —— 挂在那里等于给任何老用户开一个「随时补填邀请码」的入口，
    /// 那就是刷分入口。设角色天然只能成功一次（角色已设定时返 409 `ROLE_ALREADY_SET`，
    /// 且角色不可修改），于是「老用户不能补填」由已有的数据库状态保证。
    ///
    /// ⚠️ **填错不会让本请求失败**：码不存在、填了自己的、或已被别人邀请过，
    /// 一律照常设角色成功、只是不建立邀请关系。
    /// ⇒ **不要根据这个请求的成功与否判断邀请码有没有生效**，
    /// 本轮也没有「我的邀请人是谁」这个端点可以回查。
    ///
    /// 合成的 `Encodable` 对 Optional 走 `encodeIfPresent`，所以 `nil` 时这个键根本不出现 ——
    /// 与老客户端的请求体逐字节一致。
    let inviteCode: String?

    init(role: UserRole, inviteCode: String? = nil) {
        self.role = role
        self.inviteCode = inviteCode
    }
}

/// `POST /api/auth/refresh` 的请求体。refresh token 只出现在这里（契约：不进头、不进 URL）。
struct RefreshTokenRequest: Codable, Sendable {
    let refreshToken: String
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
