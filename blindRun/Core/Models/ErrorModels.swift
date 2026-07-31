import Foundation

// MARK: - Error Code

enum ErrorCode: String, Codable, Sendable {
    case invalidVerificationCode = "INVALID_VERIFICATION_CODE"
    case profileIncomplete = "PROFILE_INCOMPLETE"
    case locationPermissionRequired = "LOCATION_PERMISSION_REQUIRED"
    case orderNotFound = "ORDER_NOT_FOUND"
    case orderAlreadyAccepted = "ORDER_ALREADY_ACCEPTED"
    case invalidOrderStatus = "ORDER_STATUS_NOT_ALLOWED"
    case activeOrderRoleSwitchBlocked = "ROLE_ALREADY_SET"
    case volunteerNotAvailable = "VOLUNTEER_NOT_AVAILABLE"
    case volunteerNotApproved = "VOLUNTEER_NOT_VERIFIED"
    case appointmentTooSoon = "APPOINTMENT_TOO_SOON"
    case validationFailed = "VALIDATION_ERROR"
    case unauthorized = "UNAUTHORIZED"
    case rateLimited = "RATE_LIMITED"
    case activeOrderAccountDeletionBlocked = "ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED"
    case keepWaitingLimitReached = "KEEP_WAITING_LIMIT_REACHED"
    case orderDispatchMismatch = "ORDER_DISPATCH_MISMATCH"
    case orderConcurrentConflict = "ORDER_CONCURRENT_CONFLICT"
    case tooManyRequests = "TOO_MANY_REQUESTS"
    case notOrderParticipant = "NOT_ORDER_PARTICIPANT"
    case invalidTimestamp = "INVALID_TIMESTAMP"
    case phoneFormatInvalid = "PHONE_FORMAT_INVALID"
    case userNotFound = "USER_NOT_FOUND"
    case notFound = "NOT_FOUND"
    case badRequest = "BAD_REQUEST"
    case securityForbidden = "SECURITY_FORBIDDEN"
    case resourceNotFound = "RESOURCE_NOT_FOUND"
    case duplicateOrder = "DUPLICATE_ORDER"
    case registrationStepInvalid = "REGISTRATION_STEP_INVALID"
    case internalError = "INTERNAL_ERROR"
    case idInfoInvalid = "ID_INFO_INVALID"
    case volunteerNotRegistered = "VOLUNTEER_NOT_REGISTERED"
    case orderInProgress = "ORDER_IN_PROGRESS"
    case orderPermissionDenied = "ORDER_PERMISSION_DENIED"
    case smsSendLimitExceeded = "SMS_SEND_LIMIT_EXCEEDED"
    // 盲人下单前置门槛，后端 `ErrorCode.java`「盲人下单前置条件类（403）」小节（2026-07-30 新增）。
    // `OrderCreationService.createOrder` 的判定顺序是**先实名、后紧急联系人**，客户端门槛必须同序。
    case identityNotVerified = "IDENTITY_NOT_VERIFIED"
    // 取代此前复用的通用 `ORDER_PERMISSION_DENIED`：后者与「非订单参与者」等场景共用一个码，
    // 客户端无法程序化区分，只能猜 message。
    case emergencyContactRequired = "EMERGENCY_CONTACT_REQUIRED"
    // 紧急联系人专用码，后端 `ErrorCode.java` 「紧急联系人类（400）」小节的三个值。
    case contactLimitExceeded = "CONTACT_LIMIT_EXCEEDED"
    case contactMinimumRequired = "CONTACT_MINIMUM_REQUIRED"
    case contactFieldRequired = "CONTACT_FIELD_REQUIRED"

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
            // 后端 `DispatchService` 的接单守卫（403 VOLUNTEER_NOT_VERIFIED）唯一解法是上传资质证书等审核。
            // case 名与 rawValue 不一致是历史命名，不要改 rawValue。
            return "尚未通过资质认证，请先上传资质证书。"
        case .appointmentTooSoon:
            return "预约时间需要至少30分钟之后。"
        case .validationFailed:
            return "提交内容不符合要求，请检查后重试。"
        case .unauthorized:
            return "登录已过期，请重新登录。"
        case .rateLimited:
            return "操作过于频繁，请稍后重试。"
        case .activeOrderAccountDeletionBlocked:
            return "当前存在进行中的服务，请处理完成后再删除账户。"
        case .keepWaitingLimitReached:
            return "延长次数已达上限，无法继续等待。"
        case .orderDispatchMismatch:
            return "该订单未派送给您。"
        case .orderConcurrentConflict:
            return "操作冲突，请重试一次。"
        case .tooManyRequests:
            return "请求过于频繁，请稍后再试。"
        case .phoneFormatInvalid:
            return "手机号格式不正确。"
        case .userNotFound:
            return "用户不存在。"
        case .notFound:
            return "请求的资源不存在。"
        case .badRequest:
            return "请求参数有误。"
        case .securityForbidden:
            return "没有权限执行此操作。"
        case .resourceNotFound:
            return "请求的资源不存在。"
        case .duplicateOrder:
            return "存在重复订单。"
        case .registrationStepInvalid:
            return "注册步骤不正确，请重新开始。"
        case .internalError:
            return "服务器内部错误，请稍后重试。"
        case .idInfoInvalid:
            return "身份信息核验未通过，请检查后重试。"
        case .volunteerNotRegistered:
            return "志愿者注册流程尚未完成。"
        case .orderInProgress:
            return "订单进行中，当前操作受限。"
        case .orderPermissionDenied:
            return "没有权限操作此订单。"
        case .smsSendLimitExceeded:
            return "短信发送已达上限，请稍后重试。"
        case .identityNotVerified:
            return "还没有完成实名认证，暂时不能下单。请打开设置里的实名认证，填写姓名和身份证号后再预约。"
        case .emergencyContactRequired:
            return "还没有设置紧急联系人，暂时不能下单。请先添加至少 1 位紧急联系人，并把其中 1 位设为主联系人。"
        case .notOrderParticipant:
            return "您不是该订单的参与方。"
        case .invalidTimestamp:
            return "时间参数格式错误。"
        case .contactLimitExceeded:
            return "最多添加 5 个紧急联系人，请先删除一个再添加。"
        case .contactMinimumRequired:
            return "至少保留 1 个紧急联系人，请先添加新的再删除。"
        case .contactFieldRequired:
            return "请填写联系人姓名和手机号。"
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
    let rateLimitBucket: RateLimitBucket?
    let retryAfterSeconds: Int?

    init(
        code: String,
        message: String,
        rateLimitBucket: RateLimitBucket? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.rateLimitBucket = rateLimitBucket
        self.retryAfterSeconds = retryAfterSeconds
    }

    var errorCode: ErrorCode? {
        ErrorCode(rawValue: code)
    }
}

enum RateLimitBucket: String, Codable, Sendable {
    case auth = "AUTH"
    case registration = "REGISTRATION"
    case general = "GENERAL"
}

struct RateLimitInfo: Codable, Sendable, Equatable {
    let message: String
    let bucket: RateLimitBucket?
    let retryAfterSeconds: Int?
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
    let rateLimitBucket: RateLimitBucket?
    let retryAfterSeconds: Int?

    private enum CodingKeys: String, CodingKey {
        case success, code, errorCode, message, error, rateLimitBucket, retryAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        rateLimitBucket = try container.decodeIfPresent(RateLimitBucket.self, forKey: .rateLimitBucket)
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
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
            message: resolvedMessage,
            rateLimitBucket: rateLimitBucket,
            retryAfterSeconds: retryAfterSeconds
        )
    }
}
