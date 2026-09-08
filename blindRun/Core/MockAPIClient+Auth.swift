//
//  MockAPIClient+Auth.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 认证与角色 分段。行为零改动，只改文件位置。
//

import Foundation

extension MockAPIClient {

    // MARK: - Auth Handlers

    func handleSendCode(body: (any Encodable & Sendable)?) throws -> SendCodeResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(SendCodeRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        guard AppState.isValidMainlandPhone(request.phone) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "手机号格式不正确"))
        }
        return SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: nil
        )
    }

    func handleVerifyCode(body: (any Encodable & Sendable)?) throws -> LoginResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(VerifyCodeRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        guard request.code == AppConstants.Auth.demoVerificationCode else {
            throw APIError.serverError(ErrorResponse(
                code: "INVALID_VERIFICATION_CODE", message: "验证码错误"))
        }
        mockToken = "mock_jwt_token_\(UUID().uuidString)"
        isAccountDeleted = false // 软删除后的手机号可重新注册
        return LoginResponse(
            token: mockToken!,
            userId: mockUserId,
            role: mockRole?.rawValue
        )
    }

    func handleGetVolunteerRegistrationStatus() -> VolunteerRegistrationStatus {
        let status = volunteerProfile?.verificationStatus?.lowercased()
        let step1Completed = volunteerProfile?.name?.trimmed.isEmpty == false
        let registrationStep = volunteerRegistrationStepCode ?? {
            if status == "approved" {
                return "STEP_4_COMPLETED"
            }
            return step1Completed ? "STEP_3_FACE_VERIFY" : "STEP_1_BASIC_INFO"
        }()
        let idStatus: String
        if step1Completed || status == "approved" || registrationStep == "STEP_3_FACE_VERIFY" || registrationStep.hasPrefix("STEP_4") {
            idStatus = "APPROVED"
        } else {
            idStatus = "NONE"
        }
        // DECLINED 优先级最高：它是终态选择，不该被「有没有 certifyId」这类过程量盖掉。
        let faceStatus: String
        if volunteerFaceVerifyDeclined {
            faceStatus = "DECLINED"
        } else if registrationStep.hasPrefix("STEP_4") {
            faceStatus = "APPROVED"
        } else {
            faceStatus = activeCloudAuthCertifyId == nil ? "NONE" : "PENDING"
        }
        // ⚠️ 走替代路径的人**注册流程走完了但仍不能接单**（后端 api_spec.yaml:1025-1027）：
        // 还要 POST /api/volunteer/verification 传材料 + 管理员人工审核。
        // 所以 DECLINED 只进 registrationCompleted，不进 canAcceptOrders —— 两者在这里必须分开。
        let canAcceptOrders = registrationStep == "STEP_4_COMPLETED" && !volunteerFaceVerifyDeclined
        // 与后端 VolunteerRegistrationService.isRegistrationCompleted 同口径：
        // STEP_3_FACE_VERIFY 只有在活体 APPROVED（或依法拒绝）时才算走完
        // （该步骤位在「正在做活体」时也是它）。
        let registrationCompleted = registrationStep.hasPrefix("STEP_4")
            || (registrationStep == "STEP_3_FACE_VERIFY" && (faceStatus == "APPROVED" || faceStatus == "DECLINED"))
        return VolunteerRegistrationStatus(
            currentStep: nil,
            registrationStep: registrationStep,
            registrationCompleted: registrationCompleted,
            canAcceptOrders: canAcceptOrders,
            stepDetails: VolunteerRegistrationStepDetails(
                idVerifyStatus: idStatus,
                faceVerifyStatus: faceStatus,
                idVerifyRejectionReason: nil,
                faceVerifyRejectionReason: nil
            ),
            step1Completed: step1Completed,
            step2Completed: idStatus == "APPROVED",
            step3Completed: registrationStep.hasPrefix("STEP_4"),
            overallStatus: status?.uppercased() ?? "NOT_SUBMITTED",
            idVerifyStatus: idStatus,
            faceVerifyStatus: faceStatus
        )
    }

    func handleSubmitVolunteerRegistrationBasicInfo(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(BasicInfoRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let idCardNumberRegex = #"^\d{17}[\dXx]$"#
        guard !request.name.trimmed.isEmpty,
              AppState.isValidMainlandPhone(request.phone),
              !request.idCardName.trimmed.isEmpty,
              request.idCardNumber.trimmed.range(of: idCardNumberRegex, options: .regularExpression) != nil else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请填写姓名、手机号和有效身份证信息"))
        }
        if let volunteerRegistrationStepCode,
           volunteerRegistrationStepCode != "STEP_1_BASIC_INFO" {
            throw APIError.serverError(
                ErrorResponse(
                    code: "REGISTRATION_STEP_INVALID",
                    message: "当前步骤不允许提交基本信息，当前步骤：\(volunteerRegistrationStepCode)"
                )
            )
        }
        volunteerProfile = VolunteerProfileResponse(
            name: request.name.trimmed,
            verificationStatus: volunteerProfile?.verificationStatus ?? "in_progress",
            adminReviewStatus: volunteerProfile?.adminReviewStatus,
            registrationStep: "STEP_3_FACE_VERIFY",
            canAcceptOrders: false,
            isAvailable: volunteerProfile?.isAvailable ?? false,
            availableTimeSlots: volunteerProfile?.availableTimeSlots,
            acceptsGuideDog: volunteerProfile?.acceptsGuideDog,
            paceRange: volunteerProfile?.paceRange
        )
        volunteerRegistrationStepCode = "STEP_3_FACE_VERIFY"
        // 重填基本信息 = 重新跑二要素，之前那次拒绝随之作废（被 ID_INFO_INVALID 弹回来的人走的就是这条）。
        volunteerFaceVerifyDeclined = false
        return EmptyResponse()
    }

    func handleInitFaceVerify(body: (any Encodable & Sendable)?) throws -> FaceVerifyInitResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(FaceVerifyInitRequest.self, from: data),
              !request.metaInfo.trimmed.isEmpty else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "缺少活体认证设备信息"))
        }
        guard volunteerRegistrationStepCode == "STEP_3_FACE_VERIFY" else {
            throw APIError.serverError(ErrorResponse(code: "REGISTRATION_STEP_INVALID", message: "当前步骤不允许发起活体认证"))
        }
        // 「先拒绝、后来又想做人脸」是后端明确允许的（api_spec.yaml:1040），
        // 所以这里要把拒绝态清掉，否则状态回读还是 DECLINED，界面永远回不到活体那条路。
        volunteerFaceVerifyDeclined = false
        activeCloudAuthCertifyId = "mock-certify-id"
        return FaceVerifyInitResponse(
            certifyId: "mock-certify-id",
            status: "PENDING",
            message: "活体认证已发起"
        )
    }

    func handleFaceVerifyResult(body: (any Encodable & Sendable)?) throws -> FaceVerifyResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(FaceVerifyResultRequest.self, from: data),
              request.certifyId == activeCloudAuthCertifyId else {
            throw APIError.serverError(ErrorResponse(code: "REGISTRATION_STEP_INVALID", message: "活体认证流水无效"))
        }
        activeCloudAuthCertifyId = nil
        let usesLegacyTrainingStatus = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_LEGACY_TRAINING_STATUS"] == "1"
        let completedStepCode = usesLegacyTrainingStatus ? "STEP_4_TRAINING" : "STEP_4_COMPLETED"
        volunteerRegistrationStepCode = completedStepCode
        volunteerProfile = VolunteerProfileResponse(
            name: volunteerProfile?.name ?? "测试志愿者",
            verificationStatus: "approved",
            adminReviewStatus: volunteerProfile?.adminReviewStatus,
            registrationStep: completedStepCode,
            canAcceptOrders: !usesLegacyTrainingStatus,
            isAvailable: volunteerProfile?.isAvailable ?? false,
            wantsDispatch: volunteerProfile?.wantsDispatch,
            availableTimeSlots: volunteerProfile?.availableTimeSlots,
            acceptsGuideDog: volunteerProfile?.acceptsGuideDog,
            paceRange: volunteerProfile?.paceRange
        )
        return FaceVerifyResponse(passed: true, status: "APPROVED", message: "活体认证通过")
    }

    /// 拒绝人脸，转「身份证二要素核验 + 人工审核」。
    ///
    /// 后端三道守卫是「步骤位 → 二要素 → 已过活体」
    /// （`VolunteerRegistrationService.declineFaceVerify:229`），这里**故意把「已过活体」提到最前**。
    ///
    /// 理由是两边的步骤位模型不同，不是抄漏了：后端活体通过后 `registrationStep` **仍是**
    /// `STEP_3_FACE_VERIFY`（见 `VolunteerRegistrationStatus.isRegistrationComplete` 那条注释），
    /// 所以它能一路走到第三道拿到「活体认证已通过」；而 Mock 的 `handleFaceVerifyResult`
    /// 把步骤位推进到了 `STEP_4_*`，照抄顺序的话第一道就会把这些人拦成「当前步骤不允许」，
    /// 第三道成为死代码 —— 两个 409 子情形在 Mock 下就只剩一种，而客户端要按它们分文案。
    func handleDeclineFaceVerify() throws -> FaceVerifyDeclineResponse {
        if volunteerRegistrationStepCode?.hasPrefix("STEP_4") == true {
            throw APIError.serverError(
                ErrorResponse(code: "REGISTRATION_STEP_INVALID", message: "活体认证已通过，无需使用替代认证方式")
            )
        }

        guard volunteerRegistrationStepCode == "STEP_3_FACE_VERIFY" else {
            throw APIError.serverError(
                ErrorResponse(code: "REGISTRATION_STEP_INVALID", message: "当前步骤不允许选择替代认证方式")
            )
        }

        // 后端这一道比 initFaceVerify 严：那边只拦 REJECTED，这边必须 APPROVED ——
        // 活体拿掉后二要素是仅剩的自动化核验。回退到 STEP_1 是因为那是跑二要素的唯一入口。
        guard volunteerProfile?.name?.trimmed.isEmpty == false else {
            volunteerRegistrationStepCode = "STEP_1_BASIC_INFO"
            throw APIError.serverError(
                ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息未通过核验，请重新提交基本信息")
            )
        }

        // 幂等：已经是 DECLINED 时重复调不报错（后端同）。
        volunteerFaceVerifyDeclined = true
        // certifyId 必须清掉，否则一条迟到的轮询能把 DECLINED 覆盖回 APPROVED（后端同因）。
        activeCloudAuthCertifyId = nil
        return FaceVerifyDeclineResponse(
            message: "已为你改用身份证二要素核验加人工审核。请上传能证明本人身份的材料，等待管理员审核。"
        )
    }

    func handleGetMe() throws -> CurrentUserResponse {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        return CurrentUserResponse(userId: mockUserId, phone: nil, role: mockRole?.rawValue)
    }

    func handleLogout() throws -> LogoutResponse {
        if ProcessInfo.processInfo.environment["AIDRUN_MOCK_LOGOUT_FAILURE"] == "1" {
            throw APIError.networkError(URLError(.notConnectedToInternet))
        }
        mockToken = nil
        mockRole = nil
        return LogoutResponse(success: true, message: "已退出登录")
    }

    func handleDeleteAccount() throws -> DeleteAccountResponse {
        let blocking: Set<RunOrderStatus> = [
            .pendingMatch, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .rematching
        ]
        guard !orders.contains(where: { blocking.contains($0.status) }) else {
            throw APIError.serverError(ErrorResponse(
                code: "ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED",
                message: "当前存在进行中的服务，请处理完成后再删除账户。"
            ))
        }
        isAccountDeleted = true
        mockToken = nil
        mockRole = nil
        blindProfile = nil
        volunteerProfile = nil
        emergencyContacts = []
        return DeleteAccountResponse(
            success: true,
            message: "账户已删除",
            phoneReusable: true,
            allTokensInvalidated: true
        )
    }

    // MARK: - Role Handler

    func handleSetRole(body: (any Encodable & Sendable)?) throws -> SetRoleResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(SetRoleRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        mockRole = request.role
        let newToken = "mock_jwt_\(request.role.rawValue)_\(UUID().uuidString)"
        mockToken = newToken
        return SetRoleResponse(success: true, role: request.role.rawValue, token: newToken)
    }
}
