import Foundation

// MARK: - Registration Status

struct VolunteerRegistrationStatus: Decodable, Sendable {
    let currentStep: Int?
    let currentStepCode: String?
    let registrationStep: String?
    /// 注册流程走完没有。后端 2026-07-31 从 `canAcceptOrders` 里拆出来的新字段，
    /// 客户端据此决定「还要不要留在注册引导流程里」。旧服务端不返回，故可空。
    let registrationCompleted: Bool?
    /// 现在能不能接单（后端 = `VolunteerProfile.verified`，即管理员资质审核结果）。
    /// ⚠️ 不是「注册完成度」——走完注册但没过审的账号这里是 false。
    let canAcceptOrders: Bool?
    let stepDetails: VolunteerRegistrationStepDetails?
    let step1Completed: Bool?
    let step2Completed: Bool?
    let step3Completed: Bool?
    let overallStatus: String? // "PENDING", "IN_PROGRESS", "COMPLETED", "REJECTED"
    let idVerifyStatus: String?
    let faceVerifyStatus: String?

    init(
        currentStep: Int? = nil,
        currentStepCode: String? = nil,
        registrationStep: String? = nil,
        registrationCompleted: Bool? = nil,
        canAcceptOrders: Bool? = nil,
        stepDetails: VolunteerRegistrationStepDetails? = nil,
        step1Completed: Bool? = nil,
        step2Completed: Bool? = nil,
        step3Completed: Bool? = nil,
        overallStatus: String? = nil,
        idVerifyStatus: String? = nil,
        faceVerifyStatus: String? = nil
    ) {
        self.currentStep = currentStep
        self.currentStepCode = currentStepCode
        self.registrationStep = registrationStep
        self.registrationCompleted = registrationCompleted
        self.canAcceptOrders = canAcceptOrders
        self.stepDetails = stepDetails
        self.step1Completed = step1Completed
        self.step2Completed = step2Completed
        self.step3Completed = step3Completed
        self.overallStatus = overallStatus
        self.idVerifyStatus = idVerifyStatus
        self.faceVerifyStatus = faceVerifyStatus
    }

    private enum CodingKeys: String, CodingKey {
        case currentStep
        case registrationStep
        case registrationCompleted
        case canAcceptOrders
        case stepDetails
        case step1Completed
        case step2Completed
        case step3Completed
        case overallStatus
        case idVerifyStatus
        case faceVerifyStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let numericStep = try? container.decodeIfPresent(Int.self, forKey: .currentStep) {
            currentStep = numericStep
            currentStepCode = nil
        } else {
            currentStep = nil
            currentStepCode = try container.decodeIfPresent(String.self, forKey: .currentStep)
        }
        registrationStep = try container.decodeIfPresent(String.self, forKey: .registrationStep)
        registrationCompleted = try container.decodeIfPresent(Bool.self, forKey: .registrationCompleted)
        canAcceptOrders = try container.decodeIfPresent(Bool.self, forKey: .canAcceptOrders)
        stepDetails = try container.decodeIfPresent(VolunteerRegistrationStepDetails.self, forKey: .stepDetails)
        step1Completed = try container.decodeIfPresent(Bool.self, forKey: .step1Completed)
        step2Completed = try container.decodeIfPresent(Bool.self, forKey: .step2Completed)
        step3Completed = try container.decodeIfPresent(Bool.self, forKey: .step3Completed)
        overallStatus = try container.decodeIfPresent(String.self, forKey: .overallStatus)
        idVerifyStatus = try container.decodeIfPresent(String.self, forKey: .idVerifyStatus) ?? stepDetails?.idVerifyStatus
        faceVerifyStatus = try container.decodeIfPresent(String.self, forKey: .faceVerifyStatus) ?? stepDetails?.faceVerifyStatus
    }

    /// 注册流程是否真的走完（决定要不要放用户离开注册引导流程）。
    ///
    /// ⚠️ 不能用 `canAcceptOrders` 判断：后端 2026-07-31 起它等于「资质审核通过」，
    /// 走完注册但没过审的账号是 false。拿它当完成度会把人锁死在注册流程里，
    /// 而证书上传入口在注册流程之外 —— 他永远够不到那一步，`verified` 永远翻不了真。
    ///
    /// ⚠️ 也不能只看 `registrationStep`：`STEP_3_FACE_VERIFY` 既表示「正在做活体」
    /// 也表示「活体已通过」（后端 step1 二要素一过就置这个值，活体通过后仍是它），
    /// 只看步骤位会把没做活体的人判成已完成，而资质审核硬性要求活体 APPROVED，他永远审不过。
    var isRegistrationComplete: Bool {
        // 新服务端权威：后端已经把「步骤位 + 活体结果」合并算好了
        if let registrationCompleted { return registrationCompleted }

        // 旧服务端没有该字段，客户端自己按同一口径推
        let stepCode = (registrationStep ?? currentStepCode)?.uppercased()
        switch stepCode {
        case "STEP_4_COMPLETED", "STEP_4_TRAINING":
            return true                                   // 老培训流程存量：走到这一步必然已过活体
        case "STEP_3_FACE_VERIFY":
            // `DECLINED` 与 `APPROVED` 在「注册流程走完没有」这个问题上是**同一个答案**：
            // 后端 decline 成功后 `registrationCompleted=true`（api_spec.yaml:1025）。
            // 走到这条兜底分支的只有不返回该字段的旧服务端，而旧服务端也发不出 DECLINED ——
            // 这一项是防御性的：漏了它的表现是拒绝人脸的人被永久锁在注册引导里，
            // 而证书上传入口在注册流程之外，他永远够不到（同本属性上面那条注释说的坑）。
            return resolvedFaceVerifyStatus == "APPROVED" || hasDeclinedFaceVerification
        default:
            return false
        }
    }

    /// 志愿者依《人脸识别技术应用安全管理办法》第十条拒绝了人脸，改走
    /// 「身份证二要素核验 + 人工审核」。**这不是失败态**：此时注册流程算走完
    /// （`registrationCompleted=true`），但 `canAcceptOrders` 仍为 false ——
    /// 还要上传能证明本人身份的材料等人工审核。
    ///
    /// 全仓判这件事**只经过这一个属性**。散着写 `== "DECLINED"` 的后果是漏一处就把
    /// 依法拒绝的人当成认证失败，而那正是后端契约里用整段文字禁止的显示方式。
    var hasDeclinedFaceVerification: Bool {
        resolvedFaceVerifyStatus == "DECLINED"
    }

    /// 活体已经通过。用于区分 `REGISTRATION_STEP_INVALID` 的两个子情形
    /// （「已完成认证」还是「步骤位对不上」）—— 后端给这两种情况发的是同一个错误码。
    var isFaceVerificationApproved: Bool {
        resolvedFaceVerifyStatus == "APPROVED"
    }

    private var resolvedFaceVerifyStatus: String? {
        (faceVerifyStatus ?? stepDetails?.faceVerifyStatus)?.uppercased()
    }
}

struct VolunteerRegistrationStepDetails: Codable, Sendable {
    let idVerifyStatus: String?
    let faceVerifyStatus: String?
    let idVerifyRejectionReason: String?
    let faceVerifyRejectionReason: String?

    init(
        idVerifyStatus: String? = nil,
        faceVerifyStatus: String? = nil,
        idVerifyRejectionReason: String? = nil,
        faceVerifyRejectionReason: String? = nil
    ) {
        self.idVerifyStatus = idVerifyStatus
        self.faceVerifyStatus = faceVerifyStatus
        self.idVerifyRejectionReason = idVerifyRejectionReason
        self.faceVerifyRejectionReason = faceVerifyRejectionReason
    }
}

// MARK: - Step 1: Basic Info

struct BasicInfoRequest: Codable, Sendable {
    let name: String
    let phone: String
    let idCardName: String
    let idCardNumber: String
    let runningExperience: String?
    let hasGuidedBefore: Bool?
    let emergencyExperience: String?
}

// MARK: - Step 3: Face Verify

struct FaceVerifyInitRequest: Codable, Sendable {
    let metaInfo: String
}

struct FaceVerifyInitResponse: Codable, Sendable {
    let certifyId: String?
    let status: String?
    let message: String?

    var isPending: Bool {
        status?.uppercased() == "PENDING"
    }

    var isError: Bool {
        status?.uppercased() == "ERROR"
    }
}

struct FaceVerifyResultRequest: Codable, Sendable {
    let certifyId: String
}

// MARK: - Step 3: Decline Face Verify（替代认证路径）

/// `POST /step3/face-verify/decline` 的 200 响应体是 `ApiResponse<String>`，
/// `data` 是一句可直接朗读的提示文案。
///
/// 🚨 **不能直接把返回类型写成 `String`。** `APIPayloadDecoder.decodePayload` 是
/// 「信封优先、裸解兜底」：`data` 为 null 或不是字符串时 `envelope.data` 是 nil，
/// 于是退回拿**整个信封对象**去解 `String` —— 必然抛 `decodingError`。
/// 那会把一次**已经成功的 200** 报成失败，而这个端点是幂等的：用户看到「失败」会反复点，
/// 每一次其实都成功了。文案缺失是可以降级的（本地兜底一句），一次成功的拒绝被吞掉不行。
struct FaceVerifyDeclineResponse: Decodable, Sendable {
    let message: String?

    init(message: String?) {
        self.message = message
    }

    init(from decoder: Decoder) throws {
        // 只接受「就是一个字符串」这一种形状，其余一律给 nil，**绝不抛**。
        message = try? decoder.singleValueContainer().decode(String.self)
    }
}

struct FaceVerifyResponse: Codable, Sendable {
    let passed: Bool?
    let status: String?
    let message: String?

    var isPassed: Bool {
        if passed == true {
            return true
        }
        let normalizedStatus = status?.uppercased()
        return normalizedStatus == "APPROVED" || normalizedStatus == "PASSED"
    }

    var isPending: Bool {
        status?.uppercased() == "PENDING"
    }

    var isRejected: Bool {
        status?.uppercased() == "REJECTED"
    }

    var isError: Bool {
        status?.uppercased() == "ERROR"
    }
}
