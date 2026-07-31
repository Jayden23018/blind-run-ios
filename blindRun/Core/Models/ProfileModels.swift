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

/// `POST /api/blind/verify-identity` 的请求体。
/// 身份证号只在提交这一刻存在于 ViewModel 内存里，禁止写入 AppState、日志或任何持久化。
struct BlindVerifyRequest: Codable, Sendable {
    let idCardName: String
    let idCardNumber: String
}

/// `POST /api/blind/verify-identity` 的响应。后端 schema 是无类型 object，
/// 所以这里只解可选字段，**权威状态一律重新 `GET /api/blind/profile` 读 `verifyStatus`**。
struct BlindVerifySubmitResponse: Codable, Sendable {
    let success: Bool?
    let message: String?

    init(success: Bool? = nil, message: String? = nil) {
        self.success = success
        self.message = message
    }
}

/// `BlindProfileResponse.verifyStatus` 的三态。后端**没有 PENDING 态**。
/// 未知取值解码为 `.unknown` 而不是抛错，避免后端新增枚举值时整个资料接口解析失败。
enum BlindVerifyStatus: String, Codable, Sendable {
    case notVerified = "NOT_VERIFIED"
    case verified = "VERIFIED"
    case failed = "FAILED"
    /// 后端未返回该字段或返回了本客户端不认识的值。
    case unknown = "UNKNOWN"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BlindVerifyStatus.parse(raw)
    }

    static func parse(_ rawValue: String?) -> BlindVerifyStatus {
        guard let normalized = rawValue?.trimmed.uppercased(), !normalized.isEmpty else {
            return .unknown
        }
        return BlindVerifyStatus(rawValue: normalized) ?? .unknown
    }

    var isVerified: Bool { self == .verified }

    /// 实名只是软引导：未通过时提示，但不阻塞下单。
    var shouldPromptVerification: Bool { !isVerified }

    var displayName: String {
        switch self {
        case .notVerified: return "未实名认证"
        case .verified: return "已实名认证"
        case .failed: return "实名认证未通过"
        case .unknown: return "实名状态未知"
        }
    }

    /// 展示与 TTS 共用的下一步引导文案。
    var guidanceMessage: String {
        switch self {
        case .notVerified: return "尚未实名认证。完成实名认证可以提升接单成功率，也可以先直接预约。"
        case .verified: return "已完成实名认证。"
        case .failed: return "实名认证未通过，请核对姓名和身份证号后重新提交。"
        case .unknown: return "暂时无法获取实名状态，可稍后在设置中重试。"
        }
    }
}

extension BlindProfileResponse {
    /// 类型化的实名状态。**仅用于展示与引导，不参与下单门槛。**
    var identityStatus: BlindVerifyStatus {
        BlindVerifyStatus.parse(verifyStatus)
    }
}

/// 实名认证提交失败的稳定文案映射。
/// 只返回固定文案或客户端自己生成的描述，**绝不回显后端 message**，
/// 避免后端把提交的身份证号原样带回来后被展示或朗读出去。
enum BlindIdentityVerificationFailure {
    static let genericMessage = "实名认证提交失败，请稍后重试。"

    static func message(for error: APIError) -> String {
        switch error {
        case .serverError(let response):
            switch response.errorCode {
            case .idInfoInvalid:
                return "身份信息核验未通过，请核对姓名和身份证号后重试。"
            case .validationFailed, .badRequest:
                return "身份信息格式不正确，请检查后重试。"
            case .rateLimited, .tooManyRequests:
                return "提交过于频繁，请稍后重试。"
            case .userNotFound:
                return "账户信息异常，请重新登录后重试。"
            case .unauthorized:
                return "登录已过期，请重新登录。"
            default:
                return genericMessage
            }
        case .rateLimited:
            return "提交过于频繁，请稍后重试。"
        case .unauthorized:
            return "登录已过期，请重新登录。"
        case .networkError:
            return "网络连接失败，请检查网络后重试。"
        case .decodingError, .invalidURL, .unknown:
            return genericMessage
        }
    }
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
        let stepCode = registrationStep?.uppercased()
        return canAcceptOrders == true ||
            stepCode == "STEP_4_COMPLETED" ||
            stepCode == "STEP_4_TRAINING" ||
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

/// 联系人写请求。后端 `EmergencyContactRequest` 的 `name`/`phone` 都只有 `@Size`，没有
/// `@NotBlank`，`PUT` 是 PATCH 语义（传 null 保留旧值），所以这里保持可选。
/// 必填校验发生在 `POST` 的 Service 层（缺失时 400 `CONTACT_FIELD_REQUIRED`）。
///
/// TODO(集成批次2)：本地分支已把 `phone` 收紧为非可选（配合"后端 v1.5.0 起返回明文手机号、
/// 不再用掩码回填推断未修改"的改动），但那依赖紧急联系人视图与 `ProfileModule` 的重写，
/// 属于后续批次。收紧要和视图一起做，否则 `ProfileModule.emergencyContactPhoneForRequest`
/// 的掩码回填逻辑会被静默破坏。
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

/// 紧急联系人的契约约束（后端 `EmergencyContactRequest` 字段长度 + 1~5 条数量限制）。
enum EmergencyContactRules {
    static let minCount = 1
    static let maxCount = 5
    static let maxNameLength = 50
    static let maxPhoneLength = 20
    static let maxRelationshipLength = 20
}

extension EmergencyContactResponse {
    /// 展示用脱敏。后端自 v1.5.0 起返回**明文**手机号，脱敏只发生在展示层：
    /// 不要把脱敏值写回输入框，更不要用"值没变=没修改"来推断请求体。
    var maskedPhone: String? {
        EmergencyContactResponse.maskPhone(phone)
    }

    static func maskPhone(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let digits = rawValue.filter(\.isNumber)
        guard digits.count == 11 else { return rawValue }
        return "\(digits.prefix(3))****\(digits.suffix(4))"
    }

    /// 恰好一个主联系人时返回它；0 个或多个都返回 nil（不变量被破坏）。
    static func singlePrimary(in contacts: [EmergencyContactResponse]) -> EmergencyContactResponse? {
        let primaries = contacts.filter { $0.isPrimary == true }
        return primaries.count == 1 ? primaries[0] : nil
    }
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
