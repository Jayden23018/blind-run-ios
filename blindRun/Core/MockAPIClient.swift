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
    /// 实名状态独立于资料本体保存：`AIDRUN_MOCK_BLIND_VERIFY_STATUS` 控制初始值，
    /// `AIDRUN_MOCK_BLIND_VERIFY_RESULT` 控制提交实名后的结果（均只接受 NOT_VERIFIED/VERIFIED/FAILED）。
    private var blindVerifyStatus: String = BlindVerifyStatus.verified.rawValue
    private var volunteerProfile: VolunteerProfileResponse?
    /// 资质证书审核状态，取值与后端 `VerificationStatus` 完全一致（NONE/PENDING/APPROVED/REJECTED）。
    /// `AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS` 可覆盖初始值，用于驱动四态 UI。
    private var volunteerVerificationStatus: VolunteerCertificateStatus = .approved
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
        #if DEBUG
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_HANG_HOME_REQUESTS"] == "1",
           path == "/api/orders/mine" || path == "/api/volunteer/dispatch-summary" {
            await Self.suspendForeverIgnoringCancellation()
            throw CancellationError()
        }
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_HANG_TRANSITION_CONFIRMATION"] == "1",
           method == .get,
           path.matches(of: try! Regex("/api/orders/\\d+$")).count > 0 {
            await Self.suspendForeverIgnoringCancellation()
            throw CancellationError()
        }
        #endif

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

    #if DEBUG
    /// Deterministic UI-test fault injection for clients that never complete
    /// and do not cooperate with task cancellation.
    nonisolated private static func suspendForeverIgnoringCancellation() async {
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
    }
    #endif

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        try await Task.sleep(nanoseconds: 300_000_000)

        if path == "/api/volunteer/verification" {
            let result = try handleSubmitVerification(files: files)
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

        throw APIError.unknown(statusCode: 404)
    }

    /// 逐条对齐后端 `VolunteerController.submitVerification` + `VolunteerService.submitVerification`：
    /// - 前三条校验在 Controller 内联返回 `{success:false,code:400,message}`，**没有 errorCode**
    ///   （`VolunteerController.java:68/73/77`）。
    /// - APPROVED 重传抛 `IllegalArgumentException`（`VolunteerService.java:314`），
    ///   经 `GlobalExceptionHandler:136` 变成 `ApiResponse.error(400, ErrorCode.BAD_REQUEST, message)`，
    ///   所以这一条**带 errorCode `BAD_REQUEST`**，与前三条形状不同。
    /// - 成功后状态一律置 `PENDING`，`verified` 重置为 false。
    private func handleSubmitVerification(files: [MultipartFile]) throws -> VolunteerVerificationStatusResponse {
        guard let file = files.first(where: { $0.fieldName == "file" }), !file.data.isEmpty else {
            throw APIError.serverError(ErrorResponse(code: "400", message: "资质证件文件不能为空"))
        }
        guard file.mimeType.hasPrefix("image/") || file.mimeType == "application/pdf" else {
            throw APIError.serverError(ErrorResponse(code: "400", message: "文件格式仅支持图片或PDF"))
        }
        guard file.data.count <= 5 * 1024 * 1024 else {
            throw APIError.serverError(ErrorResponse(code: "400", message: "文件大小不能超过5MB"))
        }
        guard volunteerVerificationStatus != .approved else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "资质证书已审核通过，无需重新上传"))
        }

        volunteerVerificationStatus = .pending
        applyVolunteerVerificationStatusToProfile()
        return VolunteerVerificationStatusResponse(success: true, status: volunteerVerificationStatus.rawValue)
    }

    /// 后端 `GET /api/volunteer/profile` 的 `verificationStatus` 与
    /// `GET /api/volunteer/verification/status` 同源（都读 `profile.getVerificationStatus().name()`），
    /// Mock 必须保持两者一致。
    private func applyVolunteerVerificationStatusToProfile() {
        let existing = volunteerProfile
        volunteerProfile = VolunteerProfileResponse(
            name: existing?.name ?? "测试志愿者",
            verificationStatus: volunteerVerificationStatus.rawValue,
            adminReviewStatus: existing?.adminReviewStatus,
            registrationStep: volunteerRegistrationStepCode,
            canAcceptOrders: volunteerVerificationStatus == .approved,
            isAvailable: existing?.isAvailable ?? false,
            wantsDispatch: existing?.wantsDispatch,
            availableTimeSlots: existing?.availableTimeSlots,
            acceptsGuideDog: existing?.acceptsGuideDog,
            paceRange: existing?.paceRange
        )
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
        // 注意：紧急联系人的 DELETE 也挂在 /api/users/ 下，必须先放行再兜底拒绝。
        if path.hasPrefix("/api/users/") && method == .delete && extractEmergencyContactId(from: path) == nil {
            throw APIError.serverError(ErrorResponse(code: "SECURITY_FORBIDDEN", message: "只能删除当前账户。"))
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
        if path == "/api/blind/verify-identity" && method == .post {
            return try handleVerifyIdentity(body: body)
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
        if path == "/api/volunteer/verification/status" && method == .get {
            // 后端只返回 {"status": "..."}，不带信封。
            return VolunteerVerificationStatusResponse(status: volunteerVerificationStatus.rawValue)
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
        if let contactId = extractSetPrimaryContactId(from: path), method == .put {
            return try handleSetPrimaryEmergencyContact(contactId: contactId)
        }
        if let contactId = extractEmergencyContactId(from: path), method == .put {
            return try handleUpdateEmergencyContact(contactId: contactId, body: body)
        }
        if let contactId = extractEmergencyContactId(from: path), method == .delete {
            return try handleDeleteEmergencyContact(contactId: contactId)
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
            if path.hasSuffix("/track") && method == .get {
                return try handleGetOrderTrack(orderId: orderId)
            }
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

        // Legal links (App Store 5.1.1 / 5.1.2)。后端 permitAll，Mock 同样不要求 token。
        // 默认返回非 null URL 以覆盖外链分支；设 AIDRUN_MOCK_LEGAL_LINKS_NULL=1
        // 可模拟后端未配置 URL（当前生产的真实状态），用于验证内置回退文案分支。
        if path == "/api/misc/legal-links" && method == .get {
            if ProcessInfo.processInfo.environment["AIDRUN_MOCK_LEGAL_LINKS_NULL"] == "1" {
                return LegalLinksResponse(privacyPolicyUrl: nil, userAgreementUrl: nil)
            }
            return LegalLinksResponse(
                privacyPolicyUrl: "https://example.com/aidrun/privacy",
                userAgreementUrl: "https://example.com/aidrun/terms"
            )
        }

        throw APIError.invalidURL
    }

    private func handleGetOrderTrack(orderId: Int64) throws -> OrderTrackResponse {
        guard let order = orders.first(where: { $0.orderId == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        guard order.status == .completed,
              let startLatitude = order.startLatitude,
              let startLongitude = order.startLongitude else {
            return OrderTrackResponse(
                status: order.status,
                volunteerTrack: [],
                volunteerStats: TrackStats(distanceMeters: 0, durationSeconds: 0, avgPaceSecPerKm: nil),
                blindTrack: [],
                blindStats: TrackStats(distanceMeters: 0, durationSeconds: 0, avgPaceSecPerKm: nil)
            )
        }
        let points = [
            TrackPoint(lat: startLatitude, lng: startLongitude, recordedAt: "2026-07-21T08:00:00Z"),
            TrackPoint(lat: startLatitude + 0.003, lng: startLongitude + 0.002, recordedAt: "2026-07-21T08:12:00Z"),
            TrackPoint(lat: startLatitude + 0.006, lng: startLongitude + 0.004, recordedAt: "2026-07-21T08:24:00Z")
        ]
        return OrderTrackResponse(
            status: order.status,
            volunteerTrack: points,
            volunteerStats: TrackStats(distanceMeters: 820, durationSeconds: 1_440, avgPaceSecPerKm: 1_756),
            blindTrack: points,
            blindStats: TrackStats(distanceMeters: 820, durationSeconds: 1_440, avgPaceSecPerKm: 1_756)
        )
    }

    // MARK: - Auth Handlers

    private func handleSendCode(body: (any Encodable & Sendable)?) throws -> SendCodeResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(SendCodeRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        guard AppState.isValidMainlandPhone(request.phone) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "手机号格式不正确"))
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

    private func handleInitFaceVerify(body: (any Encodable & Sendable)?) throws -> FaceVerifyInitResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
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

    private func handleFaceVerifyResult(body: (any Encodable & Sendable)?) throws -> FaceVerifyResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
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
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        mockRole = request.role
        let newToken = "mock_jwt_\(request.role.rawValue)_\(UUID().uuidString)"
        mockToken = newToken
        return SetRoleResponse(success: true, role: request.role.rawValue, token: newToken)
    }

    // MARK: - Profile Handlers

    /// 实名状态是 Mock 里的独立字段：资料更新不会覆盖它，提交实名后重新 GET 才拿到权威值。
    private func handleGetBlindProfile() -> BlindProfileResponse {
        return BlindProfileResponse(
            name: blindProfile?.name,
            runningPace: blindProfile?.runningPace,
            specialNeeds: blindProfile?.specialNeeds,
            verifyStatus: blindVerifyStatus,
            visionLevel: blindProfile?.visionLevel,
            hasGuideDog: blindProfile?.hasGuideDog,
            tetherPreference: blindProfile?.tetherPreference,
            chatPreference: blindProfile?.chatPreference,
            defaultPace: blindProfile?.defaultPace
        )
    }

    /// `POST /api/blind/verify-identity`：后端响应是无类型 object，这里同样返回空对象。
    /// Mock **不保存身份证号**，只落一个状态位。
    private func handleVerifyIdentity(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(BlindVerifyRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let idCardName = request.idCardName.trimmed
        guard idCardName.count >= 2, idCardName.count <= 50 else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "姓名需为 2 到 50 个字符"))
        }
        guard request.idCardNumber.trimmed.range(of: #"^\d{17}[\dXx]$"#, options: .regularExpression) != nil else {
            throw APIError.serverError(ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息核验未通过"))
        }
        blindVerifyStatus = Self.environmentVerifyStatus(
            key: "AIDRUN_MOCK_BLIND_VERIFY_RESULT",
            default: BlindVerifyStatus.verified.rawValue
        )
        return EmptyResponse()
    }

    /// 只接受三个合法状态，避免 UI 测试写错环境变量后拿到无声失败。
    private static func environmentVerifyStatus(key: String, default defaultValue: String) -> String {
        guard let raw = ProcessInfo.processInfo.environment[key]?.uppercased(),
              BlindVerifyStatus(rawValue: raw) != nil,
              raw != BlindVerifyStatus.unknown.rawValue else {
            return defaultValue
        }
        return raw
    }

    private func handleUpdateBlindProfile(body: (any Encodable & Sendable)?) throws -> BlindProfileResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(BlindProfileUpdateRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        blindProfile = BlindProfileResponse(
            name: request.name ?? blindProfile?.name,
            runningPace: request.runningPace ?? blindProfile?.runningPace,
            specialNeeds: request.specialNeeds ?? blindProfile?.specialNeeds,
            verifyStatus: blindVerifyStatus,
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
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
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
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
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
        // 与后端 VolunteerService.getDispatchSummary 逐条对齐：只有三个独立条件，
        // 在途订单**不**产生 notAvailableReason（后端在派单入口另行过滤）。
        // Mock 不得造后端没有的原因值，否则某些分支永远跑不到（曾因此漏掉 NOT_VERIFIED 解码 bug）。
        // Mock 只在开启接单时上报位置，因此 isOnline 与 wantsDispatch 同源。
        let isOnline = wantsDispatch
        let reasons: [VolunteerDispatchNotAvailableReason] = {
            var values: [VolunteerDispatchNotAvailableReason] = []
            if !wantsDispatch {
                values.append(.dispatchDisabled)
            }
            if !handleGetVolunteerRegistrationStatus().isRegistrationComplete {
                values.append(.notVerified)
            }
            if !isOnline {
                values.append(.offline)
            }
            return values
        }()
        return VolunteerDispatchSummaryResponse(
            canDispatch: reasons.isEmpty,
            notAvailableReasons: reasons,
            wantsDispatch: wantsDispatch,
            isOnline: isOnline,
            lastLat: isOnline ? 39.9042 : nil,
            lastLng: isOnline ? 116.4074 : nil,
            lastLocationAt: isOnline ? ISO8601DateFormatter().string(from: Date()) : nil,
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
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "请求格式错误"))
        }
        // 后端 EmergencyContactService.addContact：count >= 5 时抛 CONTACT_LIMIT_EXCEEDED（400）。
        guard emergencyContacts.count < EmergencyContactRules.maxCount else {
            throw APIError.serverError(ErrorResponse(
                code: "CONTACT_LIMIT_EXCEEDED",
                message: "最多添加 \(EmergencyContactRules.maxCount) 个紧急联系人"
            ))
        }
        try validateContactFields(request, requireAllFields: true)

        // 第一个联系人必定是主联系人；显式要求主联系人时旧的自动取消。
        let shouldBePrimary = (request.isPrimary ?? false) || emergencyContacts.isEmpty
        let contact = EmergencyContactResponse(
            id: nextContactId,
            name: request.name?.trimmed,
            phone: request.phone?.trimmed,
            relationship: request.relationship?.trimmed.nilIfBlank,
            isPrimary: shouldBePrimary
        )
        nextContactId += 1
        emergencyContacts.append(contact)
        if shouldBePrimary {
            applyPrimaryContact(id: contact.id)
        }
        return try storedEmergencyContact(id: contact.id)
    }

    private func handleUpdateEmergencyContact(
        contactId: Int64,
        body: (any Encodable & Sendable)?
    ) throws -> EmergencyContactResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyContactRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "请求格式错误"))
        }
        guard let index = emergencyContacts.firstIndex(where: { $0.id == contactId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        try validateContactFields(request, requireAllFields: false)

        // PATCH 语义：请求里为 nil 的字段保留旧值（后端 EmergencyContactService.updateContact 逐字段判空）。
        let existingContact = emergencyContacts[index]
        emergencyContacts[index] = EmergencyContactResponse(
            id: existingContact.id,
            name: request.name?.trimmed ?? existingContact.name,
            phone: request.phone?.trimmed ?? existingContact.phone,
            relationship: request.relationship?.trimmed.nilIfBlank ?? existingContact.relationship,
            isPrimary: request.isPrimary ?? existingContact.isPrimary
        )

        // 设成主联系人时旧的自动取消。
        // 唯一的主联系人被显式置 false 时，后端**不报错**，而是把列表里的下一个补成主联系人
        // （EmergencyContactService.updateContact 末尾的补偿分支，与 deleteContact 一致）。
        // Mock 不得在这里造一个后端从不返回的 400，否则客户端会为不存在的失败分支写死逻辑。
        if request.isPrimary == true {
            applyPrimaryContact(id: contactId)
        } else if request.isPrimary == false, existingContact.isPrimary == true {
            promoteFirstContact(excluding: contactId)
        }

        return try storedEmergencyContact(id: contactId)
    }

    /// `PUT .../{contactId}/set-primary`：后端返回 `{"success": true}`，不返回列表，客户端必须重新 GET。
    private func handleSetPrimaryEmergencyContact(contactId: Int64) throws -> EmptyResponse {
        guard emergencyContacts.contains(where: { $0.id == contactId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        applyPrimaryContact(id: contactId)
        return EmptyResponse()
    }

    private func handleDeleteEmergencyContact(contactId: Int64) throws -> EmptyResponse {
        guard let index = emergencyContacts.firstIndex(where: { $0.id == contactId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        // 后端 EmergencyContactService.deleteContact：count <= 1 时抛 CONTACT_MINIMUM_REQUIRED（400）。
        guard emergencyContacts.count > EmergencyContactRules.minCount else {
            throw APIError.serverError(ErrorResponse(
                code: "CONTACT_MINIMUM_REQUIRED",
                message: "至少保留 \(EmergencyContactRules.minCount) 个紧急联系人"
            ))
        }
        let removed = emergencyContacts.remove(at: index)
        // 删掉的是主联系人时顺延给列表第一个，保证"恰好一个主联系人"不变量不被 Mock 自己破坏。
        if removed.isPrimary == true {
            promoteFirstContact(excluding: removed.id)
        }
        return EmptyResponse()
    }

    /// 原子设置主联系人：目标置 true，其余一律置 false。
    private func applyPrimaryContact(id: Int64) {
        emergencyContacts = emergencyContacts.map { contact in
            EmergencyContactResponse(
                id: contact.id,
                name: contact.name,
                phone: contact.phone,
                relationship: contact.relationship,
                isPrimary: contact.id == id
            )
        }
    }

    /// 后端在"主联系人被删除/被取消"后把列表里的下一个补成主联系人；没有其他联系人时保持 0 个主联系人。
    private func promoteFirstContact(excluding contactId: Int64) {
        guard let next = emergencyContacts.first(where: { $0.id != contactId }) else { return }
        applyPrimaryContact(id: next.id)
    }

    private func storedEmergencyContact(id: Int64) throws -> EmergencyContactResponse {
        guard let contact = emergencyContacts.first(where: { $0.id == id }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        return contact
    }

    /// 字段长度按后端 `EmergencyContactRequest` 约束校验；创建时姓名和手机号必填。
    private func validateContactFields(_ request: EmergencyContactRequest, requireAllFields: Bool) throws {
        let name = request.name?.trimmed
        let phone = request.phone?.trimmed ?? ""
        // 后端 addContact 对空姓名/空手机号分别抛 CONTACT_FIELD_REQUIRED（400），姓名先判。
        if requireAllFields {
            if name?.isEmpty != false {
                throw APIError.serverError(
                    ErrorResponse(code: "CONTACT_FIELD_REQUIRED", message: "联系人姓名不能为空"))
            }
            if phone.isEmpty {
                throw APIError.serverError(
                    ErrorResponse(code: "CONTACT_FIELD_REQUIRED", message: "联系人电话不能为空"))
            }
        }
        if let name, name.count > EmergencyContactRules.maxNameLength {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人姓名过长"))
        }
        // 后端对联系人 phone 只有 @Size(max=20)，没有格式校验（见 demo/.../EmergencyContactRequest.java）。
        // Mock 不再做格式拦截，否则会掩盖"乱填的号码能存进去"这个真实缺口；格式校验的责任在客户端表单。
        if phone.count > EmergencyContactRules.maxPhoneLength {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人手机号过长"))
        }
        if let relationship = request.relationship?.trimmed,
           relationship.count > EmergencyContactRules.maxRelationshipLength {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人关系过长"))
        }
    }

    // MARK: - Order Handlers

    private func handleCreateOrder(body: (any Encodable & Sendable)?) throws -> OrderResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(CreateOrderRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
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
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
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
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
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
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
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
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
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
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许该操作"))
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
                code: "ORDER_STATUS_NOT_ALLOWED", message: "当前订单状态不允许取消"))
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
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
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
                orderId: orders.first(where: { [.pendingAccept, .driverEnRoute, .driverArrived].contains($0.status) })?.orderId,
                status: orders.first(where: { [.pendingAccept, .driverEnRoute, .driverArrived].contains($0.status) })?.status,
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

    private func extractSetPrimaryContactId(from path: String) -> Int64? {
        let components = path.split(separator: "/")
        // path like /api/users/1/emergency-contacts/100/set-primary
        guard components.count == 6,
              components[0] == "api",
              components[1] == "users",
              components[3] == "emergency-contacts",
              components[5] == "set-primary" else {
            return nil
        }
        return Int64(components[4])
    }

    // MARK: - Seed Data

    private func seedDemoData() {
        blindVerifyStatus = Self.environmentVerifyStatus(
            key: "AIDRUN_MOCK_BLIND_VERIFY_STATUS",
            default: BlindVerifyStatus.verified.rawValue
        )
        blindProfile = BlindProfileResponse(
            name: "测试盲人",
            runningPace: "MODERATE",
            specialNeeds: nil,
            verifyStatus: blindVerifyStatus,
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

        // Mock 只允许后端真实存在的四个取值，未知覆盖值一律忽略。
        if let override = ProcessInfo.processInfo.environment["AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS"],
           case let parsed = VolunteerCertificateStatus.parse(override),
           parsed != .unknown {
            volunteerVerificationStatus = parsed
        }
        if volunteerProfile != nil {
            applyVolunteerVerificationStatusToProfile()
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
