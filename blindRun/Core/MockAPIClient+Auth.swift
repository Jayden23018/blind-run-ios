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
        let faceStatus = registrationStep.hasPrefix("STEP_4") ? "APPROVED" : activeCloudAuthCertifyId == nil ? "NONE" : "PENDING"
        let canAcceptOrders = registrationStep == "STEP_4_COMPLETED"
        // 与后端 VolunteerRegistrationService.isRegistrationCompleted 同口径：
        // STEP_3_FACE_VERIFY 只有在活体 APPROVED 时才算走完（该步骤位在「正在做活体」时也是它）。
        let registrationCompleted = registrationStep.hasPrefix("STEP_4")
            || (registrationStep == "STEP_3_FACE_VERIFY" && faceStatus == "APPROVED")
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
