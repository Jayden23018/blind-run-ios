import Foundation

// MARK: - Mock API Client

/// 本地模拟 API Client，支持离线开发和 Demo 演示。
/// 模拟 300ms 网络延迟，内部维护状态，支持完整订单流程。
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {

    // MARK: - Internal State

    private var mockToken: String? = nil
    private var mockUserId: Int64 = 1
    private var mockRole: UserRole? = nil
    private var isAccountDeleted = false

    private var blindProfile: BlindProfileResponse?
    private var volunteerProfile: VolunteerProfileResponse?
    private var volunteerRegistrationStepCode: String?
    private var activeCloudAuthCertifyId: String?
    private var emergencyContacts: [EmergencyContactResponse] = []

    private var orders: [OrderDetailResponse] = []
    private var nextOrderId: Int64 = 100
    private var nextContactId: Int64 = 100

    // MARK: - Init

    init() {
        seedDemoData()
    }

    func syncRoleFromAppState(_ role: UserRole?) {
        mockRole = role
    }

    func syncSessionFromAppState(token: String?, role: UserRole?) {
        mockToken = token
        mockRole = role
    }

    // MARK: - APIClientProtocol

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000)

        let result: Any = try routeRequest(method: method, path: path, query: query, body: body)

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        guard let typed = result as? T else {
            throw APIError.decodingError(
                NSError(domain: "MockAPIClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Type mismatch: expected \(T.self)"])
            )
        }
        return typed
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        try await Task.sleep(nanoseconds: 300_000_000)

        if path == "/api/volunteer/verification" {
            volunteerProfile = VolunteerProfileResponse(
                name: volunteerProfile?.name ?? "测试志愿者",
                verificationStatus: "pending",
                adminReviewStatus: volunteerProfile?.adminReviewStatus ?? "pending",
                registrationStep: volunteerRegistrationStepCode,
                canAcceptOrders: false,
                isAvailable: volunteerProfile?.isAvailable ?? false,
                availableTimeSlots: volunteerProfile?.availableTimeSlots,
                acceptsGuideDog: volunteerProfile?.acceptsGuideDog,
                paceRange: volunteerProfile?.paceRange
            )
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            if T.self == ApiSuccessResponse.self {
                return ApiSuccessResponse(success: true, message: "认证资料已提交") as! T
            }
        }

        throw APIError.unknown(statusCode: 404)
    }

    // MARK: - Router

    private func routeRequest(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?
    ) throws -> Any {
        if ProcessInfo.processInfo.environment["AIDRUN_MOCK_GENERAL_RATE_LIMIT"] == "1",
           path != "/api/auth/send-code" {
            throw APIError.rateLimited(RateLimitInfo(
                message: "操作过于频繁。",
                bucket: .general,
                retryAfterSeconds: 30
            ))
        }
        // Auth endpoints
        if path == "/api/auth/send-code" && method == .post {
            if ProcessInfo.processInfo.environment["AIDRUN_MOCK_AUTH_RATE_LIMIT"] == "1" {
                throw APIError.rateLimited(RateLimitInfo(
                    message: "验证码发送过于频繁。",
                    bucket: .auth,
                    retryAfterSeconds: 60
                ))
            }
            return try handleSendCode(body: body)
        }
        if path == "/api/auth/verify-code" && method == .post {
            return try handleVerifyCode(body: body)
        }
        if path == "/api/auth/me" && method == .get {
            return try handleGetMe()
        }
        if path == "/api/auth/logout" && method == .post {
            return try handleLogout()
        }
        if path == "/api/users/\(mockUserId)" && method == .delete {
            return try handleDeleteAccount()
        }
        if path.hasPrefix("/api/users/") && method == .delete {
            throw APIError.serverError(ErrorResponse(code: "FORBIDDEN", message: "只能删除当前账户。"))
        }

        // Role
        if path == "/api/user/role" && method == .post {
            return try handleSetRole(body: body)
        }

        // Blind profile
        if path == "/api/blind/profile" && method == .get {
            return handleGetBlindProfile()
        }
        if path == "/api/blind/profile" && method == .put {
            return try handleUpdateBlindProfile(body: body)
        }
        // Volunteer profile
        if path == "/api/volunteer/profile" && method == .get {
            return handleGetVolunteerProfile()
        }
        if path == "/api/volunteer/profile" && method == .put {
            return try handleUpdateVolunteerProfile(body: body)
        }
        if path == "/api/volunteer/dispatch-status" && method == .put {
            return try handleUpdateDispatchStatus(body: body)
        }
        if path == "/api/volunteer/dispatch-summary" && method == .get {
            return handleGetVolunteerDispatchSummary()
        }
        if path == "/api/volunteer/registration/status" && method == .get {
            return handleGetVolunteerRegistrationStatus()
        }
        if path == "/api/volunteer/registration/step1" && method == .post {
            return try handleSubmitVolunteerRegistrationBasicInfo(body: body)
        }
        if path == "/api/volunteer/registration/step3/face-verify/init" && method == .post {
            return try handleInitFaceVerify(body: body)
        }
        if path == "/api/volunteer/registration/step3/face-verify/result" && method == .post {
            return try handleFaceVerifyResult(body: body)
        }
        // Emergency contacts
        if path.hasPrefix("/api/users/") && path.hasSuffix("/emergency-contacts") && method == .get {
            return emergencyContacts
        }
        if path.hasPrefix("/api/users/") && path.hasSuffix("/emergency-contacts") && method == .post {
            return try handleAddEmergencyContact(body: body)
        }
        if let contactId = extractEmergencyContactId(from: path), method == .put {
            return try handleUpdateEmergencyContact(contactId: contactId, body: body)
        }

        // Orders
        if path == "/api/orders" && method == .post {
            return try handleCreateOrder(body: body)
        }
        if path == "/api/orders/mine" && method == .get {
            return handleGetMyOrders(query: query)
        }
        if path == "/api/orders/available" && method == .get {
            return handleGetAvailableOrders()
        }

        // Order actions
        if let orderId = extractOrderId(from: path) {
            if path.hasSuffix("/respond") && method == .post {
                return try handleRespondOrder(orderId: orderId, body: body)
            }
            if path.hasSuffix("/en-route") && method == .post {
                return try handleEnRoute(orderId: orderId)
            }
            if path.hasSuffix("/arrived") && method == .post {
                return try handleArrived(orderId: orderId)
            }
            if path.hasSuffix("/start-service") && method == .post {
                return try handleStartService(orderId: orderId)
            }
            if path.hasSuffix("/finish") && method == .post {
                return try handleFinish(orderId: orderId)
            }
            if path.hasSuffix("/cancel") && method == .post {
                return try handleCancel(orderId: orderId)
            }
            if path.hasSuffix("/review") && method == .post {
                return handleReview()
            }

            // Order detail
            if method == .get && path.matches(of: try! Regex("/api/orders/\\d+$")).count > 0 {
                return try handleGetOrder(orderId: orderId)
            }
        }

        // Emergency trigger
        if path == "/api/emergency/trigger" && method == .post {
            return try handleEmergencyTrigger(body: body)
        }

        // Location
        if path == "/api/blind/location" && method == .post {
            return ApiSuccessResponse(success: true, message: "位置已更新")
        }
        if path == "/api/blind/volunteer-location" && method == .get {
            return handleGetVolunteerLocation()
        }

        throw APIError.invalidURL
    }

    // MARK: - Auth Handlers

    private func handleSendCode(body: (any Encodable & Sendable)?) throws -> SendCodeResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(SendCodeRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        guard AppState.isValidMainlandPhone(request.phone) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "手机号格式不正确"))
        }
        return SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: nil,
            verificationCode: nil,
            smsCode: nil
        )
    }

    private func handleVerifyCode(body: (any Encodable & Sendable)?) throws -> LoginResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(VerifyCodeRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
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

    private func handleGetVolunteerRegistrationStatus() -> VolunteerRegistrationStatus {
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
        return VolunteerRegistrationStatus(
            currentStep: nil,
            registrationStep: registrationStep,
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

    private func handleSubmitVolunteerRegistrationBasicInfo(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(BasicInfoRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        let idCardNumberRegex = #"^\d{17}[\dXx]$"#
        guard !request.name.trimmed.isEmpty,
              AppState.isValidMainlandPhone(request.phone),
              !request.idCardName.trimmed.isEmpty,
              request.idCardNumber.trimmed.range(of: idCardNumberRegex, options: .regularExpression) != nil else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请填写姓名、手机号和有效身份证信息"))
        }
        if let volunteerRegistrationStepCode,
           volunteerRegistrationStepCode != "STEP_1_BASIC_INFO" {
            throw APIError.serverError(
                ErrorResponse(
                    code: "INVALID_REGISTRATION_STEP",
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

    private func handleInitFaceVerify(body: (any Encodable & Sendable)?) throws -> FaceVerifyInitResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(FaceVerifyInitRequest.self, from: data),
              !request.metaInfo.trimmed.isEmpty else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "缺少活体认证设备信息"))
        }
        guard volunteerRegistrationStepCode == "STEP_3_FACE_VERIFY" else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_REGISTRATION_STEP", message: "当前步骤不允许发起活体认证"))
        }
        activeCloudAuthCertifyId = "mock-certify-id"
        return FaceVerifyInitResponse(
            certifyId: "mock-certify-id",
            status: "PENDING",
            message: "活体认证已发起"
        )
    }

    private func handleFaceVerifyResult(body: (any Encodable & Sendable)?) throws -> FaceVerifyResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(FaceVerifyResultRequest.self, from: data),
              request.certifyId == activeCloudAuthCertifyId else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "活体认证流水无效"))
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

    private func handleGetMe() throws -> CurrentUserResponse {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        return CurrentUserResponse(userId: mockUserId, phone: nil, role: mockRole?.rawValue)
    }

    private func handleLogout() throws -> LogoutResponse {
        if ProcessInfo.processInfo.environment["AIDRUN_MOCK_LOGOUT_FAILURE"] == "1" {
            throw APIError.networkError(URLError(.notConnectedToInternet))
        }
        mockToken = nil
        mockRole = nil
        return LogoutResponse(success: true, message: "已退出登录")
    }

    private func handleDeleteAccount() throws -> DeleteAccountResponse {
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

    private func handleSetRole(body: (any Encodable & Sendable)?) throws -> SetRoleResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(SetRoleRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        mockRole = request.role
        let newToken = "mock_jwt_\(request.role.rawValue)_\(UUID().uuidString)"
        mockToken = newToken
        return SetRoleResponse(success: true, role: request.role.rawValue, token: newToken)
    }

    // MARK: - Profile Handlers

    private func handleGetBlindProfile() -> BlindProfileResponse {
        return blindProfile ?? BlindProfileResponse(
            name: nil, runningPace: nil, specialNeeds: nil,
            verifyStatus: "NOT_VERIFIED", visionLevel: nil,
            hasGuideDog: nil, tetherPreference: nil,
            chatPreference: nil, defaultPace: nil
        )
    }

    private func handleUpdateBlindProfile(body: (any Encodable & Sendable)?) throws -> BlindProfileResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(BlindProfileUpdateRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        blindProfile = BlindProfileResponse(
            name: request.name ?? blindProfile?.name,
            runningPace: request.runningPace ?? blindProfile?.runningPace,
            specialNeeds: request.specialNeeds ?? blindProfile?.specialNeeds,
            verifyStatus: blindProfile?.verifyStatus ?? "NOT_VERIFIED",
            visionLevel: request.visionLevel ?? blindProfile?.visionLevel,
            hasGuideDog: request.hasGuideDog ?? blindProfile?.hasGuideDog,
            tetherPreference: request.tetherPreference ?? blindProfile?.tetherPreference,
            chatPreference: request.chatPreference ?? blindProfile?.chatPreference,
            defaultPace: request.defaultPace ?? blindProfile?.defaultPace
        )
        return blindProfile!
    }

    private func handleGetVolunteerProfile() -> VolunteerProfileResponse {
        return volunteerProfile ?? VolunteerProfileResponse(
            name: nil,
            verificationStatus: nil,
            adminReviewStatus: nil,
            registrationStep: volunteerRegistrationStepCode,
            canAcceptOrders: volunteerRegistrationStepCode == "STEP_4_COMPLETED",
            isAvailable: nil,
            availableTimeSlots: nil,
            acceptsGuideDog: nil,
            paceRange: nil
        )
    }

    private func handleUpdateVolunteerProfile(body: (any Encodable & Sendable)?) throws -> VolunteerProfileResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(VolunteerProfileUpdateRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        volunteerProfile = VolunteerProfileResponse(
            name: request.name ?? volunteerProfile?.name,
            verificationStatus: "approved",
            adminReviewStatus: volunteerProfile?.adminReviewStatus ?? "approved",
            registrationStep: volunteerRegistrationStepCode ?? "STEP_4_COMPLETED",
            canAcceptOrders: volunteerRegistrationStepCode == nil || volunteerRegistrationStepCode == "STEP_4_COMPLETED",
            isAvailable: request.isAvailable ?? volunteerProfile?.isAvailable,
            wantsDispatch: request.wantsDispatch ?? volunteerProfile?.wantsDispatch,
            availableTimeSlots: request.availableTimeSlots ?? volunteerProfile?.availableTimeSlots,
            acceptsGuideDog: request.acceptsGuideDog ?? volunteerProfile?.acceptsGuideDog,
            paceRange: request.paceRange ?? volunteerProfile?.paceRange
        )
        return volunteerProfile!
    }

    private func handleUpdateDispatchStatus(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(DispatchStatusRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        let existing = handleGetVolunteerProfile()
        volunteerProfile = VolunteerProfileResponse(
            name: existing.name,
            verificationStatus: existing.verificationStatus,
            adminReviewStatus: existing.adminReviewStatus,
            registrationStep: existing.registrationStep,
            canAcceptOrders: existing.canAcceptOrders,
            isAvailable: request.wantsDispatch,
            wantsDispatch: request.wantsDispatch,
            availableTimeSlots: existing.availableTimeSlots,
            acceptsGuideDog: existing.acceptsGuideDog,
            paceRange: existing.paceRange
        )
        return EmptyResponse()
    }

    private func handleGetVolunteerDispatchSummary() -> VolunteerDispatchSummaryResponse {
        let profile = handleGetVolunteerProfile()
        let wantsDispatch = profile.isAvailable ?? profile.wantsDispatch ?? false
        let activeOrders = orders
            .filter { $0.status.isActiveForVolunteer }
            .sorted { ($0.acceptedAt ?? $0.createdAt ?? "") > ($1.acceptedAt ?? $1.createdAt ?? "") }
            .map {
                VolunteerDispatchSummaryActiveOrder(
                    orderId: $0.orderId,
                    status: $0.status,
                    plannedStartTime: $0.plannedStart,
                    plannedEndTime: $0.plannedEnd,
                    startAddress: $0.startAddress,
                    startLatitude: $0.startLatitude,
                    startLongitude: $0.startLongitude,
                    blindName: $0.blindName,
                    blindPhoneMasked: $0.blindPhone?.maskedPhone,
                    acceptedAt: $0.acceptedAt
                )
            }
        let recentOrders = orders
            .filter { $0.status == .completed || $0.status == .cancelled || $0.status.isActiveForVolunteer }
            .sorted { ($0.createdAt ?? $0.plannedStart ?? "") > ($1.createdAt ?? $1.plannedStart ?? "") }
            .prefix(5)
            .map {
                VolunteerDispatchSummaryRecentOrder(
                    orderId: $0.orderId,
                    status: $0.status,
                    plannedStartTime: $0.plannedStart,
                    completedAt: $0.status == .completed ? $0.plannedEnd : nil,
                    startAddress: $0.startAddress,
                    blindName: $0.blindName,
                    rating: $0.status == .completed ? 5 : nil,
                    pointsDelta: $0.status == .completed ? 100 : nil
                )
            }
        let totalCompleted = orders.filter { $0.status == .completed }.count
        let totalAccepted = orders.filter { $0.status != .pendingMatch }.count
        let reasons: [VolunteerDispatchNotAvailableReason] = {
            var values: [VolunteerDispatchNotAvailableReason] = []
            if !wantsDispatch {
                values.append(.dispatchDisabled)
            }
            if !handleGetVolunteerRegistrationStatus().isRegistrationComplete {
                values.append(.registrationIncomplete)
            }
            if !activeOrders.isEmpty {
                values.append(.activeOrder)
            }
            return values
        }()
        return VolunteerDispatchSummaryResponse(
            canDispatch: reasons.isEmpty,
            notAvailableReasons: reasons,
            wantsDispatch: wantsDispatch,
            isOnline: wantsDispatch,
            lastLat: 39.9042,
            lastLng: 116.4074,
            lastLocationAt: ISO8601DateFormatter().string(from: Date()),
            coverageRadiusKm: 10,
            isWithinServiceTime: true,
            availableTimeSlots: profile.availableTimeSlots,
            avgRating: totalCompleted > 0 ? 5.0 : nil,
            totalRatings: totalCompleted,
            totalDispatched: max(totalAccepted + 2, 2),
            totalAccepted: totalAccepted,
            totalDeclined: 1,
            totalTimeout: 1,
            totalCompleted: totalCompleted,
            totalCancelled: orders.filter { $0.status == .cancelled }.count,
            acceptanceRate: 0.7,
            pointsBalance: nil,
            activeOrders: activeOrders,
            recentOrders: Array(recentOrders)
        )
    }

    // MARK: - Emergency Contact Handlers

    private func handleAddEmergencyContact(body: (any Encodable & Sendable)?) throws -> EmergencyContactResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyContactRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        let contact = EmergencyContactResponse(
            id: nextContactId,
            name: request.name,
            phone: request.phone,
            relationship: request.relationship,
            isPrimary: request.isPrimary ?? emergencyContacts.isEmpty
        )
        nextContactId += 1
        emergencyContacts.append(contact)
        return contact
    }

    private func handleUpdateEmergencyContact(
        contactId: Int64,
        body: (any Encodable & Sendable)?
    ) throws -> EmergencyContactResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyContactRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        guard let index = emergencyContacts.firstIndex(where: { $0.id == contactId }) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "紧急联系人不存在"))
        }

        let existingContact = emergencyContacts[index]
        let updatedContact = EmergencyContactResponse(
            id: existingContact.id,
            name: request.name ?? existingContact.name,
            phone: request.phone ?? existingContact.phone,
            relationship: request.relationship ?? existingContact.relationship,
            isPrimary: request.isPrimary ?? existingContact.isPrimary
        )

        if updatedContact.isPrimary == true {
            emergencyContacts = emergencyContacts.map { contact in
                guard contact.id != updatedContact.id else { return updatedContact }
                return EmergencyContactResponse(
                    id: contact.id,
                    name: contact.name,
                    phone: contact.phone,
                    relationship: contact.relationship,
                    isPrimary: false
                )
            }
        } else {
            emergencyContacts[index] = updatedContact
        }

        return updatedContact
    }

    // MARK: - Order Handlers

    private func handleCreateOrder(body: (any Encodable & Sendable)?) throws -> OrderResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(CreateOrderRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }

        // Validate profile completeness
        guard blindProfile?.name != nil, !emergencyContacts.isEmpty else {
            throw APIError.serverError(ErrorResponse(
                code: "PROFILE_INCOMPLETE", message: "请先完善盲人资料和紧急联系人"))
        }

        // Validate appointment time (30 min ahead)
        if let date = ISO8601DateFormatter().date(from: request.plannedStartTime)
            ?? DateFormatter.aidRunBackendLocalDateTime.date(from: request.plannedStartTime) {
            let leadTime = date.timeIntervalSince(Date())
            if leadTime < Double(AppConstants.Timing.minimumBookingLeadMinutes) * 60 {
                throw APIError.serverError(ErrorResponse(
                    code: "APPOINTMENT_TOO_SOON", message: "预约时间至少需要在 30 分钟后"))
            }
        }

        let orderId = nextOrderId
        nextOrderId += 1

        let order = OrderDetailResponse(
            orderId: orderId,
            status: .pendingMatch,
            startAddress: request.startAddress,
            startLatitude: request.startLatitude,
            startLongitude: request.startLongitude,
            plannedStart: request.plannedStartTime,
            plannedEnd: request.plannedEndTime,
            blindName: blindProfile?.name,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expectedDurationMinutes: request.expectedDurationMinutes,
            pacePreference: request.pacePreference,
            routePreference: request.routePreference,
            routeNotes: request.routeNotes,
            hasGuideDogThisRun: request.hasGuideDogThisRun,
            specialNotes: request.specialNotes,
            visionLevel: blindProfile?.visionLevel,
            tetherPreference: blindProfile?.tetherPreference,
            chatPreference: blindProfile?.chatPreference
        )
        orders.append(order)

        return OrderResponse(id: orderId, status: .pendingMatch, message: "订单已创建", success: true)
    }

    private func handleGetMyOrders(query: [String: String]?) -> PagedOrderResponse {
        var filtered = orders
        if let status = query?["status"], let s = RunOrderStatus(rawValue: status) {
            filtered = filtered.filter { $0.status == s }
        }
        return PagedOrderResponse(
            content: filtered.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
            totalElements: Int64(filtered.count),
            totalPages: 1,
            number: 0,
            size: 100,
            first: true,
            last: true,
            empty: filtered.isEmpty
        )
    }

    private func handleGetAvailableOrders() -> PagedOrderResponse {
        let filtered = orders.filter { $0.status == .pendingMatch }
        return PagedOrderResponse(
            content: filtered.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") },
            totalElements: Int64(filtered.count),
            totalPages: 1,
            number: 0,
            size: 100,
            first: true,
            last: true,
            empty: filtered.isEmpty
        )
    }

    private func handleGetOrder(orderId: Int64) throws -> OrderDetailResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        return order
    }

    private func handleRespondOrder(orderId: Int64, body: (any Encodable & Sendable)?) throws -> OrderResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(OrderRespondRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        switch request.action {
        case .accept:
            return try handleAcceptOrder(orderId: orderId)
        case .decline:
            return try handleDeclineOrder(orderId: orderId)
        }
    }

    private func handleAcceptOrder(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .pendingMatch else {
            throw APIError.serverError(ErrorResponse(
                code: "ORDER_ALREADY_ACCEPTED", message: "订单已被其他志愿者接单"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .pendingAccept, volunteerPhone: "13800000002")
        return actionResponse(for: orders[index], message: "接单成功")
    }

    private func handleDeclineOrder(orderId: Int64) throws -> OrderResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        return actionResponse(for: order, message: "已拒绝本次派单")
    }

    private func handleEnRoute(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .pendingAccept else {
            throw APIError.serverError(ErrorResponse(
                code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .driverEnRoute)
        return actionResponse(for: orders[index], message: "已出发")
    }

    private func handleArrived(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .driverEnRoute else {
            throw APIError.serverError(ErrorResponse(
                code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .driverArrived)
        return actionResponse(for: orders[index], message: "已到达")
    }

    private func handleFinish(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status.canFinishService else {
            throw APIError.serverError(ErrorResponse(
                code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .completed)
        return actionResponse(for: orders[index], message: "服务已完成")
    }

    private func handleStartService(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard orders[index].status == .driverArrived else {
            throw APIError.serverError(ErrorResponse(
                code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许该操作"))
        }
        orders[index] = updateOrderStatus(orders[index], to: .inProgress)
        return actionResponse(for: orders[index], message: "服务已开始")
    }

    private func handleCancel(orderId: Int64) throws -> OrderResponse {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard let role = mockRole, orders[index].status.canCancel(as: role) else {
            throw APIError.serverError(ErrorResponse(
                code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许取消"))
        }
        let nextStatus: RunOrderStatus = role == .volunteer ? .rematching : .cancelled
        orders[index] = updateOrderStatus(orders[index], to: nextStatus)
        let message = role == .volunteer ? "志愿者已取消，订单重新匹配中" : "订单已取消"
        return actionResponse(for: orders[index], message: message)
    }

    private func actionResponse(for order: OrderDetailResponse, message: String) -> OrderResponse {
        OrderResponse(id: order.orderId, status: order.status, message: message, success: true)
    }

    private func handleReview() -> ApiSuccessResponse {
        return ApiSuccessResponse(success: true, message: nil)
    }

    // MARK: - Emergency Handler

    private func handleEmergencyTrigger(body: (any Encodable & Sendable)?) throws -> ApiSuccessResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyTriggerRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "请求格式错误"))
        }
        // In mock, we just acknowledge the emergency
        guard orders.first(where: { $0.orderId == request.orderId }) != nil else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        return ApiSuccessResponse(success: true, message: "求助已发送")
    }

    // MARK: - Location Handler

    private func handleGetVolunteerLocation() -> VolunteerLocationResponse {
        return VolunteerLocationResponse(
            success: true,
            code: 200,
            message: nil,
            data: VolunteerLocationData(
                lat: AppConstants.Defaults.demoLatitude + 0.002,
                lng: AppConstants.Defaults.demoLongitude + 0.001,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
        )
    }

    // MARK: - Helpers

    private func updateOrderStatus(
        _ order: OrderDetailResponse,
        to newStatus: RunOrderStatus,
        volunteerPhone: String? = nil
    ) -> OrderDetailResponse {
        return OrderDetailResponse(
            orderId: order.orderId,
            status: newStatus,
            startAddress: order.startAddress,
            startLatitude: order.startLatitude,
            startLongitude: order.startLongitude,
            plannedStart: order.plannedStart,
            plannedEnd: order.plannedEnd,
            blindName: order.blindName,
            blindPhone: order.blindPhone,
            volunteerPhone: volunteerPhone ?? order.volunteerPhone,
            acceptedAt: newStatus == .pendingAccept ? ISO8601DateFormatter().string(from: Date()) : order.acceptedAt,
            createdAt: order.createdAt,
            expectedDurationMinutes: order.expectedDurationMinutes,
            pacePreference: order.pacePreference,
            routePreference: order.routePreference,
            routeNotes: order.routeNotes,
            hasGuideDogThisRun: order.hasGuideDogThisRun,
            specialNotes: order.specialNotes,
            visionLevel: order.visionLevel,
            tetherPreference: order.tetherPreference,
            chatPreference: order.chatPreference
        )
    }

    private func extractOrderId(from path: String) -> Int64? {
        let components = path.split(separator: "/")
        // path like /api/orders/123 or /api/orders/123/respond
        guard components.count >= 3, components[1] == "orders" else { return nil }
        return Int64(components[2])
    }

    private func extractEmergencyContactId(from path: String) -> Int64? {
        let components = path.split(separator: "/")
        // path like /api/users/1/emergency-contacts/100
        guard components.count == 5,
              components[0] == "api",
              components[1] == "users",
              components[3] == "emergency-contacts" else {
            return nil
        }
        return Int64(components[4])
    }

    // MARK: - Seed Data

    private func seedDemoData() {
        blindProfile = BlindProfileResponse(
            name: "测试盲人",
            runningPace: "MODERATE",
            specialNeeds: nil,
            verifyStatus: "VERIFIED",
            visionLevel: "TOTAL_BLIND",
            hasGuideDog: false,
            tetherPreference: "TETHER_ROPE",
            chatPreference: "PREFER_CHAT",
            defaultPace: .moderate
        )

        let uiTestVolunteerAvailable = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] == "1"
        let uiTestActiveVolunteerOrder = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_ACTIVE_ORDER"] == "1"
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_UNREGISTERED_VOLUNTEER"] == "1" {
            volunteerProfile = nil
            volunteerRegistrationStepCode = nil
        } else {
            volunteerProfile = VolunteerProfileResponse(
                name: "测试志愿者",
                verificationStatus: "approved",
                adminReviewStatus: "approved",
                isAvailable: uiTestVolunteerAvailable,
                availableTimeSlots: [
                    VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "09:00:00", endTime: "12:00:00"),
                    VolunteerAvailableTimeSlot(dayOfWeek: "SUNDAY", startTime: "09:00:00", endTime: "12:00:00")
                ],
                acceptsGuideDog: true,
                paceRange: .moderate
            )
        }

        emergencyContacts = [
            EmergencyContactResponse(id: 1, name: "张三", phone: "13900139001", relationship: "家人", isPrimary: true)
        ]

        // Seed some demo orders
        let futureDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
        let futureEnd = Calendar.current.date(byAdding: .hour, value: 3, to: Date())!
        let formatter = ISO8601DateFormatter()
        let activeAcceptedAt = formatter.string(from: Date().addingTimeInterval(-600))

        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] == "1" {
            orders = []
            nextOrderId = 10
            return
        }

        orders = [
            OrderDetailResponse(
                orderId: 1,
                status: uiTestActiveVolunteerOrder ? .pendingAccept : .pendingMatch,
                startAddress: "朝阳公园南门",
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                plannedStart: formatter.string(from: futureDate),
                plannedEnd: formatter.string(from: futureEnd),
                blindName: "李明",
                blindPhone: "13800001001",
                volunteerPhone: uiTestActiveVolunteerOrder ? "13800000002" : nil,
                acceptedAt: uiTestActiveVolunteerOrder ? activeAcceptedAt : nil,
                createdAt: formatter.string(from: Date()),
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: "沿湖边跑道",
                hasGuideDogThisRun: false,
                specialNotes: nil,
                visionLevel: "TOTAL_BLIND",
                tetherPreference: "TETHER_ROPE",
                chatPreference: "PREFER_CHAT"
            ),
            OrderDetailResponse(
                orderId: 2,
                status: .completed,
                startAddress: "奥林匹克森林公园",
                startLatitude: 40.0150,
                startLongitude: 116.3847,
                plannedStart: formatter.string(from: Date().addingTimeInterval(-86400)),
                plannedEnd: formatter.string(from: Date().addingTimeInterval(-82800)),
                blindName: "王芳",
                blindPhone: "13800001002",
                volunteerPhone: "13800000002",
                acceptedAt: formatter.string(from: Date().addingTimeInterval(-86000)),
                createdAt: formatter.string(from: Date().addingTimeInterval(-90000)),
                expectedDurationMinutes: 45,
                pacePreference: .easy,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil,
                visionLevel: "TOTAL_BLIND",
                tetherPreference: "TETHER_ROPE",
                chatPreference: "NO_PREFERENCE"
            )
        ]
        nextOrderId = 10
    }
}

// MARK: - AnyEncodable Helper

/// Helper to bridge `any Encodable` to concrete Encodable for JSONEncoder
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: (any Encodable & Sendable)?) {
        self._encode = { encoder in
            if let value = wrapped {
                try value.encode(to: encoder)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

private extension String {
    var maskedPhone: String {
        guard count >= 7 else { return self }
        return "\(prefix(3))****\(suffix(4))"
    }
}
