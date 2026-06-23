import Foundation

// MARK: - Error Code

enum ErrorCode: String, Codable, Sendable {
    case invalidVerificationCode = "INVALID_VERIFICATION_CODE"
    case profileIncomplete = "PROFILE_INCOMPLETE"
    case locationPermissionRequired = "LOCATION_PERMISSION_REQUIRED"
    case orderNotFound = "ORDER_NOT_FOUND"
    case orderAlreadyAccepted = "ORDER_ALREADY_ACCEPTED"
    case invalidOrderStatus = "INVALID_ORDER_STATUS"
    case activeOrderRoleSwitchBlocked = "ACTIVE_ORDER_ROLE_SWITCH_BLOCKED"
    case volunteerNotAvailable = "VOLUNTEER_NOT_AVAILABLE"
    case volunteerNotApproved = "VOLUNTEER_NOT_APPROVED"
    case appointmentTooSoon = "APPOINTMENT_TOO_SOON"
    case validationFailed = "VALIDATION_FAILED"
    case unauthorized = "UNAUTHORIZED"

    var localizedMessage: String {
        switch self {
        case .invalidVerificationCode:
            return "验证码错误，请重新输入。"
        case .profileIncomplete:
            return "请先完善个人资料。"
        case .locationPermissionRequired:
            return "需要定位权限才能继续操作。"
        case .orderNotFound:
            return "订单不存在。"
        case .orderAlreadyAccepted:
            return "该订单已被其他志愿者接单。"
        case .invalidOrderStatus:
            return "当前订单状态不允许此操作。"
        case .activeOrderRoleSwitchBlocked:
            return "存在进行中的订单，无法切换角色。"
        case .volunteerNotAvailable:
            return "您当前未开启接单状态。"
        case .volunteerNotApproved:
            return "您的志愿者资格尚未通过审核。"
        case .appointmentTooSoon:
            return "预约时间需要至少30分钟之后。"
        case .validationFailed:
            return "提交内容不符合要求，请检查后重试。"
        case .unauthorized:
            return "登录已过期，请重新登录。"
        }
    }

    var ttsMessage: String {
        localizedMessage
    }
}

// MARK: - Error Response

struct ErrorResponse: Codable, Sendable {
    let code: String
    let message: String

    var errorCode: ErrorCode? {
        ErrorCode(rawValue: code)
    }
}

// MARK: - Cloud Backend Response Envelope

/// Generic response envelope for cloud backend business endpoints.
/// Format: {"success": bool, "code": int, "message": string, "data": T}
struct APIEnvelopeResponse<T: Decodable>: Decodable {
    let success: Bool?
    let code: Int?
    let message: String?
    let data: T?
}

/// Empty success payload for endpoints where the client only needs HTTP success.
struct EmptyResponse: Decodable, Sendable {
    init() {}
    init(from decoder: Decoder) throws {}
}

/// Flexible cloud error payload. The demo backend currently returns multiple
/// shapes, including `errorCode`, numeric/string `code`, `message`, and `error`.
struct APIErrorEnvelope: Decodable {
    let success: Bool?
    let code: String?
    let errorCode: String?
    let message: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case success, code, errorCode, message, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        if let stringCode = try? container.decodeIfPresent(String.self, forKey: .code) {
            code = stringCode
        } else if let intCode = try? container.decodeIfPresent(Int.self, forKey: .code) {
            code = String(intCode)
        } else {
            code = nil
        }
    }

    func resolvedErrorResponse(statusCode: Int) -> ErrorResponse? {
        guard let resolvedMessage = message ?? error else { return nil }
        return ErrorResponse(
            code: errorCode ?? code ?? "HTTP_\(statusCode)",
            message: resolvedMessage
        )
    }
}
