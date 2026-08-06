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
    private var emergencyEventSequence: Int64 = 9000
    /// 当前未终态的紧急事件，`GET /api/emergency/active` 的回放源。撤销后置 nil。
    private var activeEmergencyEvent: EmergencyEventResponse?
    private var nextOrderId: Int64 = 100
    private var nextContactId: Int64 = 100

    /// 已上报的 APNs device token（幂等 upsert 的本地等价物）。
    private(set) var registeredApnsTokens: Set<String> = []
    /// `/api/notifications/since` 的补读语料。Mock 不主动产生离线通知，默认为空。
    var missedNotifications: [MissedNotificationResponse] = []

    // MARK: - Init

    init() {
        seedDemoData()
    }

    #if DEBUG
    /// 单测钩子。Mock 的初始实名状态与联系人只能由环境变量决定，而 `ProcessInfo.environment`
    /// 在进程启动后就固定了，单测无法逐条覆盖；播种的那 1 个联系人又受删除接口
    /// `CONTACT_MINIMUM_REQUIRED` 下限保护删不掉。下单前置的两条 403
    /// （`IDENTITY_NOT_VERIFIED` / `EMERGENCY_CONTACT_REQUIRED`）只能从这里到达。
    func overrideBookingPrerequisitesForTesting(
        verifyStatus: BlindVerifyStatus,
        emergencyContacts: [EmergencyContactResponse]
    ) {
        blindVerifyStatus = verifyStatus.rawValue
        self.emergencyContacts = emergencyContacts
    }
    #endif

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
                retryAfterSeconds: 30
            ))
        }
        // Auth endpoints
        if path == "/api/auth/send-code" && method == .post {
            if ProcessInfo.processInfo.environment["AIDRUN_MOCK_AUTH_RATE_LIMIT"] == "1" {
                throw APIError.rateLimited(RateLimitInfo(
                    message: "验证码发送过于频繁。",
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
        if path == "/api/volunteer/mock-verification/approve" && method == .post {
            return handleMockVerificationApprove()
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

        // 语音下单解析。真机上这两条接的是后端「正则优先、大模型兜底」，Mock 只认几条固定语料，
        // 其余一律 `needReask` —— 目的是让向导的重问/降级分支在开发期真的被走到。
        if path == VoiceOrderEndpoint.parseOrder && method == .post {
            return try handleVoiceParseOrder(body: body)
        }

        if path == VoiceOrderEndpoint.resolveAddress && method == .post {
            return try handleVoiceResolveAddress(body: body)
        }
        if path == VoiceOrderEndpoint.parseSlot && method == .post {
            return try handleVoiceParseSlot(body: body)
        }

        // Emergency trigger
        if path == "/api/emergency/trigger" && method == .post {
            return try handleEmergencyTrigger(body: body)
        }
        if path == "/api/emergency/active" && method == .get {
            return handleActiveEmergency()
        }
        if method == .put, path.hasSuffix("/cancel"), path.hasPrefix("/api/emergency/"),
           let eventId = Int64(path.dropFirst("/api/emergency/".count).dropLast("/cancel".count)) {
            return try handleCancelEmergency(eventId: eventId)
        }
        if method == .put, path.hasSuffix("/volunteer-response"), path.hasPrefix("/api/emergency/"),
           let eventId = Int64(
               path.dropFirst("/api/emergency/".count).dropLast("/volunteer-response".count)
           ) {
            return try handleVolunteerEmergencyResponse(eventId: eventId, action: query?["action"])
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

        // APNs device token 上报（幂等 upsert）。后端校验 32~128 位 hex。
        if path == "/api/devices/apns" && method == .post {
            return try handleRegisterApnsToken(body: body)
        }

        // 重连补读。后端要求 `after` 是 ISO-8601 字符串，传 epoch 会 400 INVALID_TIMESTAMP。
        if path == "/api/notifications/since" && method == .get {
            return try handleGetMissedNotifications(after: query?["after"])
        }

        throw APIError.invalidURL
    }

    /// `ApnsTokenRequest` 是只出不进的 Encodable，Mock 侧需要一个可解码的镜像来做校验。
    private struct ApnsTokenRequestProbe: Decodable {
        let deviceToken: String
        let platform: String?
    }

    private func handleRegisterApnsToken(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(ApnsTokenRequestProbe.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let isHex = request.deviceToken.count >= 32
            && request.deviceToken.count <= 128
            && request.deviceToken.allSatisfy(\.isHexDigit)
        guard isHex else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "deviceToken 格式不正确"))
        }
        registeredApnsTokens.insert(request.deviceToken)
        return EmptyResponse()
    }

    private func handleGetMissedNotifications(after: String?) throws -> [MissedNotificationResponse] {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        guard let after, !after.isEmpty, !after.allSatisfy(\.isNumber) else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_TIMESTAMP", message: "after 格式错误"))
        }
        // 后端窗口：sent_at > after，24h 内，最多 50 条，按时间正序。
        return missedNotifications
            .filter { ($0.sentAt ?? "") > after }
            .sorted { ($0.sentAt ?? "") < ($1.sentAt ?? "") }
            .prefix(50)
            .map { $0 }
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
            code: nil
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

    /// `POST /api/blind/verify-identity`：后端成功分支返回
    /// `data = {"message": "身份认证通过", "verifyStatus": "VERIFIED"}`（`BlindController.verifyIdentity`），
    /// Mock 只造这两个后端真会返回的字段。核验不通过时后端走 400 分支，这里对应抛 `ID_INFO_INVALID`。
    /// Mock **不保存身份证号**，只落一个状态位。
    private func handleVerifyIdentity(body: (any Encodable & Sendable)?) throws -> BlindVerifySubmitResponse {
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
        // 后端 200 分支的 message 是固定的「身份认证通过」；FAILED/NOT_VERIFIED 只出现在
        // UI 测试通过环境变量强制的场景里，此时不带那句成功文案。
        return BlindVerifySubmitResponse(
            message: blindVerifyStatus == BlindVerifyStatus.verified.rawValue ? "身份认证通过" : nil,
            verifyStatus: blindVerifyStatus
        )
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

    /// 「Demo 模拟认证」按钮专用，真实后端没有这个端点（入口只在 `.mock` 环境显示，
    /// 见 `VolunteerModule.shouldShowRealRegistration`）。行为对齐管理员审核通过后的志愿者：
    /// 资质 APPROVED、注册流程走完、可接单。
    private func handleMockVerificationApprove() -> VolunteerProfileResponse {
        volunteerVerificationStatus = .approved
        volunteerRegistrationStepCode = "STEP_4_COMPLETED"
        let existing = volunteerProfile
        volunteerProfile = VolunteerProfileResponse(
            name: existing?.name ?? "测试志愿者",
            verificationStatus: volunteerVerificationStatus.rawValue,
            adminReviewStatus: "approved",
            registrationStep: volunteerRegistrationStepCode,
            canAcceptOrders: true,
            isAvailable: existing?.isAvailable ?? false,
            wantsDispatch: existing?.wantsDispatch,
            availableTimeSlots: existing?.availableTimeSlots,
            acceptsGuideDog: existing?.acceptsGuideDog,
            paceRange: existing?.paceRange
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

    /// 校验顺序与后端 `EmergencyContactRequest` 严格一致：Bean Validation（`@Size` + `@Pattern`，
    /// 统一 400 `VALIDATION_ERROR`）先跑，`EmergencyContactService.addContact` 里手写的
    /// `CONTACT_FIELD_REQUIRED` 后跑。顺序反了会让 Mock 在「phone 传空串」时报错码与线上不一致。
    private func validateContactFields(_ request: EmergencyContactRequest, requireAllFields: Bool) throws {
        let name = request.name?.trimmed
        let phone = request.phone?.trimmed

        // —— Bean Validation 层 ——
        if let name, name.count > EmergencyContactRules.maxNameLength {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人姓名过长"))
        }
        if let phone {
            if phone.count > EmergencyContactRules.maxPhoneLength {
                throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人手机号过长"))
            }
            // 后端 2026-07-31 给 phone 加了 `@Pattern(^1[3-9]\d{9}$)`（与登录链路同款），
            // Mock 不能再比线上松 —— 松了就把「乱填的号码能存进去」这个安全缺口在开发期遮住。
            // `@Pattern` 对 null 放行、对空串不放行，所以这里只在 phone 非 nil 时判。
            if !AppState.isValidMainlandPhone(phone) {
                throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "手机号格式不正确"))
            }
        }
        if let relationship = request.relationship?.trimmed,
           relationship.count > EmergencyContactRules.maxRelationshipLength {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人关系过长"))
        }

        // —— 服务端手写校验层：后端对空姓名/缺手机号分别抛 CONTACT_FIELD_REQUIRED（400），姓名先判 ——
        guard requireAllFields else { return }
        if name?.isEmpty != false {
            throw APIError.serverError(
                ErrorResponse(code: "CONTACT_FIELD_REQUIRED", message: "联系人姓名不能为空"))
        }
        if phone?.isEmpty != false {
            throw APIError.serverError(
                ErrorResponse(code: "CONTACT_FIELD_REQUIRED", message: "联系人电话不能为空"))
        }
    }

    // MARK: - Order Handlers

    private func handleCreateOrder(body: (any Encodable & Sendable)?) throws -> OrderResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(CreateOrderRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }

        // 校验顺序与后端 `OrderCreationService.createOrder` 严格一致：
        // 提前量（422 APPOINTMENT_TOO_SOON）→ 实名（403 IDENTITY_NOT_VERIFIED）
        // → 紧急联系人（403 EMERGENCY_CONTACT_REQUIRED）。
        // 顺序错了会让 Mock 引导用户先补一个后端根本不会先拒的项。
        // 注意：后端**不校验** `BlindProfile.name`，Mock 也不能比后端严；
        // 之前那条 `PROFILE_INCOMPLETE` 是真实后端永不返回的死码，已删除。

        // Validate appointment time (30 min ahead)
        if let date = ISO8601DateFormatter().date(from: request.plannedStartTime)
            ?? request.plannedStartTime.backendLocalDate {
            let leadTime = date.timeIntervalSince(Date())
            if leadTime < Double(AppConstants.Timing.minimumBookingLeadMinutes) * 60 {
                throw APIError.serverError(ErrorResponse(
                    code: "APPOINTMENT_TOO_SOON", message: "预约时间至少需要在 30 分钟后"))
            }
        }

        guard BlindVerifyStatus.parse(blindVerifyStatus) == .verified else {
            throw APIError.serverError(ErrorResponse(
                code: "IDENTITY_NOT_VERIFIED", message: "请先完成实名认证再下单"))
        }

        guard !emergencyContacts.isEmpty else {
            throw APIError.serverError(ErrorResponse(
                code: "EMERGENCY_CONTACT_REQUIRED", message: "请先设置紧急联系人再下单"))
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

    // MARK: - Voice Order Handlers

    /// `POST /api/orders/voice/parse`。整句一次抽三槽，抽不出的进 `missing`。
    ///
    /// **抽不出不是错误**：和另外两个语音端点一样走 200 + `needReask`，Mock 把这一点做错，
    /// 向导就会在开发期被当成错误分支调通、上真机才发现走不通。
    /// 地点匹配沿用 `handleVoiceResolveAddress` 的同一份关键词表与带坐标排序 —— Mock 不许比线上松。
    private func handleVoiceParseOrder(body: (any Encodable & Sendable)?) throws -> ParseVoiceOrderResponse {
        guard mockToken != nil else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(ResolveAddressRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let transcript = request.transcript.trimmed

        let place = Self.matchedVoicePlace(in: transcript, near: request)
        let startTime = Self.mockVoiceStartTime(in: transcript)
        let minutes = Self.mockVoiceMinutes(in: transcript).flatMap { (10...300).contains($0) ? $0 : nil }

        var missing: [VoiceOrderMissingSlot] = []
        if place == nil { missing.append(.address) }
        if startTime == nil { missing.append(.startTime) }
        if minutes == nil { missing.append(.duration) }

        return ParseVoiceOrderResponse(
            plannedStartTime: startTime.map(Self.mockBackendLocalDateTime),
            durationMinutes: minutes,
            address: place?.address,
            latitude: place?.latitude,
            longitude: place?.longitude,
            missing: missing,
            // 在接入请求侧的 `current`（一步修正）之前，后端的 `correctionUnclear` 场景不可达，
            // 此处等价推导成立。接 `current` 时这一行要一起改成独立字段 —— 那时
            // `missing` 为空但 `needReask=true` 会真的发生（契约 2026-08-04）。
            needReask: !missing.isEmpty,
            // `missing` 非空时后端给的是追问文案，非空即追问 —— 向导刻意不播它，这里照形状给出即可。
            ttsText: missing.isEmpty
                ? "好的，我记下了"
                : "还差\(missing.count)项没听清，可以再说一次",
            hasGuideDog: Self.mockVoiceGuideDog(in: transcript),
            pacePreference: Self.mockVoicePace(in: transcript),
            // 备注只由大模型在必填槽位兜底那次顺带抽，正则不抽（语料 `_extra_slots_note`），
            // 所以 Mock 这条规则路径恒 nil，不是漏实现。
            specialNotes: nil
        )
    }

    /// `POST /api/orders/voice/resolve-address`。`needReask` 是 **200 的正常业务状态**，
    /// 所以这里返回的是成功响应体而不是 `APIError` —— Mock 把这一点做错，向导就会在开发期被
    /// 当成错误分支调通、上真机才发现走不通。
    private func handleVoiceResolveAddress(body: (any Encodable & Sendable)?) throws -> ResolveAddressResponse {
        guard mockToken != nil else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(ResolveAddressRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let transcript = request.transcript.trimmed
        guard let match = Self.matchedVoicePlace(in: transcript, near: request) else {
            return ResolveAddressResponse(
                address: nil,
                latitude: nil,
                longitude: nil,
                needReask: true,
                ttsText: "没听清地点，请再说一次出发地"
            )
        }
        return ResolveAddressResponse(
            address: match.address,
            latitude: match.latitude,
            longitude: match.longitude,
            needReask: false,
            ttsText: "您是说在\(match.address)出发吗？"
        )
    }

    /// `POST /api/orders/voice/parse-slot`。时长范围（10~300）与提前量（≥30 分钟）不满足时后端也走
    /// `needReask` 而不是错误码，Mock 同样如此。
    private func handleVoiceParseSlot(body: (any Encodable & Sendable)?) throws -> ParseSlotResponse {
        guard mockToken != nil else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(ParseSlotRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let transcript = request.transcript.trimmed
        switch request.field {
        case .startTime:
            guard let startTime = Self.mockVoiceStartTime(in: transcript) else {
                return ParseSlotResponse(
                    plannedStartTime: nil,
                    durationMinutes: nil,
                    needReask: true,
                    ttsText: "没听清开始时间，请再说一次，比如“明天早上八点”"
                )
            }
            return ParseSlotResponse(
                plannedStartTime: Self.mockBackendLocalDateTime(startTime),
                durationMinutes: nil,
                needReask: false,
                // 读回念实际落点，不再恒说「明天」—— 说「今天八点半」却被念成明天，
                // 对听不见屏幕的人就是改了他的预约。
                ttsText: "好的，\(DateFormatter.aidRunDisplayDateTime.string(from: startTime))"
            )
        case .duration:
            guard let minutes = Self.mockVoiceMinutes(in: transcript), (10...300).contains(minutes) else {
                return ParseSlotResponse(
                    plannedStartTime: nil,
                    durationMinutes: nil,
                    needReask: true,
                    ttsText: "没听清时长，请再说一次，比如“一个小时”"
                )
            }
            return ParseSlotResponse(
                plannedStartTime: nil,
                durationMinutes: minutes,
                needReask: false,
                ttsText: "好的，大约\(minutes)分钟"
            )
        }
    }

    private struct MockVoicePlace {
        let keyword: String
        let address: String
        let latitude: Double
        let longitude: Double
    }

    /// 整句解析与单点解析共用同一份地点匹配 —— 两份会漂移，漂移了就等于 Mock 里两条语音路径行为不一致。
    ///
    /// 线上带坐标时走周边搜索、按距离取最近；Mock 语料太小分不出远近，这里只保留「有没有带坐标」
    /// 这一层行为差异：带了就按距离排序再匹配。真正的消歧在后端。
    private static func matchedVoicePlace(
        in transcript: String,
        near request: ResolveAddressRequest
    ) -> MockVoicePlace? {
        let candidates = request.latitude != nil && request.longitude != nil
            ? mockVoicePlaces.sorted { squaredDistance($0, request) < squaredDistance($1, request) }
            : mockVoicePlaces
        // 整句里先剥壳拿地名 span，拿不到再退回整句包含匹配（单点修改那一轮用户只说地名，没有壳）。
        let haystack = mockVoiceAddressSpan(in: transcript) ?? transcript
        return candidates.first { haystack.contains($0.keyword) }
    }

    /// 从整句里剥出地名 span。取值与语料里 `field: "ADDRESS"` 的 9 条一致。
    ///
    /// **只断言抽取，不断言地理编码**（语料 `_address_note`）：抽出「五角场」「我家楼下」而
    /// `mockVoicePlaces` 里查不到坐标，是线上「抽到 span 但正向编码失败」的同形场景，
    /// 结果就该是 `missing` 含 `ADDRESS`，而不是当成用户没说起点。
    static func mockVoiceAddressSpan(in transcript: String) -> String? {
        for (prefix, suffix) in addressSpanShells {
            guard let head = transcript.range(of: prefix),
                  let tail = transcript.range(of: suffix, range: head.upperBound..<transcript.endIndex)
            else { continue }
            let span = String(transcript[head.upperBound..<tail.lowerBound]).trimmed
            if !span.isEmpty { return span }
        }
        return nil
    }

    /// 顺序即优先级。壳必须成对出现，只有「从」没有「出发」不算 ——
    /// 「从明天早上八点开始跑」里的「从」后面跟的是时间，抽出来当地点就把人约到了不存在的起点。
    private static let addressSpanShells: [(prefix: String, suffix: String)] = [
        ("从", "出发"), ("在", "集合"), ("在", "跑步"), ("到", "那边")
    ]

    /// 是否携带导盲犬。`nil` = 原话没提，与 `false`（本次明确不带）语义不同 ——
    /// 这个字段进派单硬过滤，两者混淆会让登记了导盲犬的用户被静默按「不带」派单。
    static func mockVoiceGuideDog(in transcript: String) -> Bool? {
        guard transcript.contains("导盲犬") else { return nil }
        // 否定式必须先判，否则「不带导盲犬」会被「带导盲犬」吃掉。
        if transcript.contains("不带") || transcript.contains("没带") || transcript.contains("没有带") {
            return false
        }
        return true
    }

    /// 配速偏好。`nil` = 原话没提，下单时不传即回落档案默认配速。
    static func mockVoicePace(in transcript: String) -> PacePreference? {
        if transcript.contains("走跑结合") { return .walkRun }
        if transcript.contains("慢一点") || transcript.contains("慢点") || transcript.contains("轻松") {
            return .easy
        }
        if transcript.contains("快一点") || transcript.contains("快点") { return .fast }
        if transcript.contains("中等") { return .moderate }
        return nil
    }

    /// 格式与后端 `LocalDateTime` 一致（无时区）。
    static func mockBackendLocalDateTime(_ date: Date) -> String {
        DateFormatter.aidRunBackendLocalDateTime.string(from: date)
    }

    #if DEBUG
    /// 语音时间解析的「现在」。设了就取代 `Date()`。
    ///
    /// 存在的理由不是「方便测试」：黄金语料（`demo/docs/voice-golden-corpus.json`）的 START_TIME
    /// 期望值是**相对 `now = 2026-07-24T10:00:00` 的绝对时间戳**，不钉住基准就没法逐条对齐，
    /// 而「过去的钟点滚次日」这条规则恰恰只有在固定基准下才验得出来。
    /// 与 `RecordingCue.observerForTesting` 是同一种接缝。
    static var voiceClockForTesting: Date?
    #endif

    private static var voiceNow: Date {
        #if DEBUG
        return voiceClockForTesting ?? Date()
        #else
        return Date()
        #endif
    }

    /// 只用于排序，不需要真实距离，所以不做球面换算。
    private static func squaredDistance(_ place: MockVoicePlace, _ request: ResolveAddressRequest) -> Double {
        guard let latitude = request.latitude, let longitude = request.longitude else { return 0 }
        let dLat = place.latitude - latitude
        let dLng = place.longitude - longitude
        return dLat * dLat + dLng * dLng
    }

    /// GCJ-02，与真实接口同坐标系。
    /// 前三条逐字对齐后端黄金语料，**不得改动**（`VoiceOrderWizardTests` 锁着）。
    ///
    /// 其余是 2026-08-06 补的手测用地点：原来只有三个关键词，说别的一律抽不出，
    /// 真机手测时表现成「说了地点但读回还是默认起点」，会被误诊成客户端 bug。
    /// Mock 只是**测试设施**，比语料宽不影响正确性判定 —— 语料那几条仍然逐条断言。
    private static let mockVoicePlaces: [MockVoicePlace] = [
        MockVoicePlace(keyword: "人民广场", address: "上海市黄浦区人民广场", latitude: 31.2304, longitude: 121.4737),
        MockVoicePlace(keyword: "天安门", address: "北京市东城区天安门广场", latitude: 39.9087, longitude: 116.3975),
        MockVoicePlace(keyword: "奥林匹克", address: "北京市朝阳区奥林匹克森林公园", latitude: 40.0026, longitude: 116.3915),
        MockVoicePlace(keyword: "世纪公园", address: "上海市浦东新区世纪公园", latitude: 31.2200, longitude: 121.5540),
        MockVoicePlace(keyword: "中山公园", address: "上海市长宁区中山公园", latitude: 31.2230, longitude: 121.4200),
        MockVoicePlace(keyword: "徐家汇", address: "上海市徐汇区徐家汇", latitude: 31.1950, longitude: 121.4370),
        MockVoicePlace(keyword: "陆家嘴", address: "上海市浦东新区陆家嘴", latitude: 31.2400, longitude: 121.5000),
        MockVoicePlace(keyword: "静安寺", address: "上海市静安区静安寺", latitude: 31.2240, longitude: 121.4450),
        MockVoicePlace(keyword: "西湖", address: "浙江省杭州市西湖", latitude: 30.2450, longitude: 120.1490),
        MockVoicePlace(keyword: "颐和园", address: "北京市海淀区颐和园", latitude: 39.9999, longitude: 116.2755),
        MockVoicePlace(keyword: "朝阳公园", address: "北京市朝阳区朝阳公园", latitude: 39.9450, longitude: 116.4800),
        MockVoicePlace(keyword: "体育中心", address: "广东省深圳市福田区深圳体育中心", latitude: 22.5480, longitude: 114.0900),
        MockVoicePlace(keyword: "公园", address: "本市公园", latitude: 31.2304, longitude: 121.4737)
    ]

    /// 开始时间解析。取值与 `demo/docs/voice-golden-corpus.json` 里 `field: "START_TIME"`、
    /// `source: "regex"` 的 10 条用例一致，`VoiceOrderWizardTests` 锁了这份对齐。
    ///
    /// 此前这里只认 5 个钟点、且落点恒定是「明天」，10 条语料只对得上 3 条 —— 于是开发期用 Mock 说
    /// 「今天八点半」会被念成明天，说「下午三点」「半小时后」则直接走重问，**而线上这三种都解得出**。
    /// Mock 比线上严和比线上松一样有害：一个让开发期以为功能没有，一个让上真机才发现走不通。
    static func mockVoiceStartTime(in transcript: String, now: Date? = nil) -> Date? {
        let now = now ?? voiceNow
        let calendar = Calendar.current

        // ① 相对时间优先。「半小时后」不能被下面的钟点分支按「半」误读。
        if let offset = relativeMinutesOffset(in: transcript) {
            return calendar.date(byAdding: .minute, value: offset, to: now)
        }

        // ② 钟点。没有「N点」就不是时间表达（llm 那几条走这里返回 nil）。
        guard let clock = clockTime(in: transcript) else { return nil }

        // ③ 日期词。没说日期词时 dayOffset 为 nil —— 与「说了今天」不是一回事，见 ④。
        let dayOffset: Int? = transcript.contains("后天") ? 2
            : transcript.contains("明天") ? 1
            : transcript.contains("今天") ? 0
            : nil

        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: calendar.date(byAdding: .day, value: dayOffset ?? 0, to: now) ?? now
        )
        components.hour = clock.hour
        components.minute = clock.minute
        guard let candidate = calendar.date(from: components) else { return nil }

        // ④ 没带日期词的钟点若早于现在，自动滚次日（语料 `_past_time_note`）。
        // 不滚的话「八点半」会返回今天 08:30，被提前量校验判成「太近了」—— 而用户压根没打算约今天。
        // 显式说了「今天」则不滚：那是用户的明确选择，该让提前量校验去拒绝它。
        if dayOffset == nil, candidate <= now {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return candidate
    }

    /// 「半小时后」「四十分钟后」「两个小时后」→ 相对分钟数。没有「后」字就不是相对表达。
    private static func relativeMinutesOffset(in transcript: String) -> Int? {
        guard transcript.contains("后"), !transcript.contains("后天") else { return nil }
        if transcript.contains("半小时后") || transcript.contains("半个小时后") { return 30 }
        if let minutes = chineseNumber(before: "分钟后", in: transcript) { return minutes }
        if let hours = chineseNumber(before: "个小时后", in: transcript)
            ?? chineseNumber(before: "小时后", in: transcript) {
            return hours * 60
        }
        return nil
    }

    /// 「八点半」「下午三点」「8:00」→ 24 小时制时分。时段词负责 12 小时制换算。
    private static func clockTime(in transcript: String) -> (hour: Int, minute: Int)? {
        guard var parsed = colonClockTime(in: transcript) ?? spokenClockTime(in: transcript) else {
            return nil
        }
        if parsed.hour < 12,
           transcript.contains("下午") || transcript.contains("晚上") || transcript.contains("傍晚") {
            parsed.hour += 12
        }
        return parsed
    }

    /// 冒号钟点：`8:00`、`8：00`、`18:30`。
    ///
    /// **这条在黄金语料里找不到依据，是照真机实况补的。** 语料 13 条 START_TIME 全是
    /// 「明天早上八点」这种中文数字加「点」的写法，而 iOS 的 `SFSpeechRecognizer` 说中文时
    /// 经常把「八点钟」直接渲染成 `8:00` —— 句子里连「点」字都没有，原来那条规则一定抽不出。
    /// 2026-08-06 真机手测「说了时间但识别不了时间点」就是这一条（已提给后端，见 handoff）。
    private static func colonClockTime(in transcript: String) -> (hour: Int, minute: Int)? {
        guard let range = transcript.range(of: #"\d{1,2}[:：]\d{2}"#, options: .regularExpression) else {
            return nil
        }
        let parts = transcript[range].split(whereSeparator: { $0 == ":" || $0 == "：" })
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// 「N点」「N点半」。N 中文与阿拉伯数字都认。
    private static func spokenClockTime(in transcript: String) -> (hour: Int, minute: Int)? {
        guard let hour = chineseNumber(before: "点", in: transcript), (1...24).contains(hour) else {
            return nil
        }
        // 「N点半」只认紧跟在「点」后面的「半」，避免「八点跑半小时」被读成 08:30。
        // 两种写法都要查：识别输出「8点半」时，只查中文形式「八点半」会漏掉，
        // 半小时就被静默抹成整点 —— 对听不见屏幕的人，这是一次无声的篡改。
        let isHalfPast = transcript.contains("\(chineseDigits[hour] ?? "")点半")
            || transcript.contains("\(hour)点半")
        return (hour, isHalfPast ? 30 : 0)
    }

    /// 汉字数字 → 整数，只覆盖 Mock 语料需要的 1~59。找 `suffix` 前面那一段来解。
    private static func chineseNumber(before suffix: String, in transcript: String) -> Int? {
        guard let range = transcript.range(of: suffix) else { return nil }
        let head = String(transcript[transcript.startIndex..<range.lowerBound])
        // 从尾部往前吃数字字符，最多 3 个（「四十五」）。
        let digits = head.reversed().prefix(3).reversed().map(String.init)
        for start in 0..<digits.count {
            let candidate = digits[start...].joined()
            if let value = chineseNumberValue(candidate) { return value }
        }
        return nil
    }

    private static func chineseNumberValue(_ text: String) -> Int? {
        if let arabic = Int(text) { return arabic }
        let units = ["零": 0, "一": 1, "两": 2, "二": 2, "三": 3, "四": 4,
                     "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let single = units[text] { return single }
        guard text.contains("十") else { return nil }
        let parts = text.components(separatedBy: "十")
        guard parts.count == 2 else { return nil }
        let tens = parts[0].isEmpty ? 1 : (units[parts[0]] ?? -1)
        let ones = parts[1].isEmpty ? 0 : (units[parts[1]] ?? -1)
        guard tens >= 0, ones >= 0 else { return nil }
        return tens * 10 + ones
    }

    private static let chineseDigits: [Int: String] = [
        1: "一", 2: "两", 3: "三", 4: "四", 5: "五", 6: "六",
        7: "七", 8: "八", 9: "九", 10: "十", 11: "十一", 12: "十二"
    ]

    /// 取值与 `demo/docs/voice-golden-corpus.json` 里 `source: "regex"` 的 DURATION 用例一致。
    /// Mock 与真实解析器漂移会让开发期调通的向导在真机上走不通，`VoiceOrderWizardTests` 锁了这份对齐。
    /// 顺序有意义：「一个半小时」必须排在「半小时」「一小时」之前，否则会被前缀吃掉。
    static func mockVoiceMinutes(in transcript: String) -> Int? {
        if transcript.contains("一个半小时") { return 90 }
        if transcript.contains("一小时二十分钟") { return 80 }
        if transcript.contains("两小时") || transcript.contains("两个小时") { return 120 }
        if transcript.contains("半小时") { return 30 }
        if transcript.contains("一小时") || transcript.contains("一个小时") { return 60 }
        if transcript.contains("四十分钟") { return 40 }
        if transcript.contains("二十分钟") { return 20 }
        // 语料之外的兜底：**阿拉伯数字**。
        //
        // 上面那几条逐字对齐后端黄金语料，全是中文数字；而 iOS 的 `SFSpeechRecognizer` 实际
        // 输出的是「跑1个小时」「跑30分钟」这种阿拉伯数字形式。2026-08-06 真机手测因此出现
        // 「说了时长，读回还是默认值」—— 不是客户端 bug，是 Mock 比真实解析器窄。
        // 后端 `VoiceSlotParser` 先把中文数字归一成阿拉伯数字再跑正则，本来就两种都吃。
        if let hours = numberBefore(["个小时", "小时"], in: transcript) { return hours * 60 }
        if let minutes = numberBefore(["分钟"], in: transcript) { return minutes }
        return nil
    }

    /// 取某个后缀之前紧邻的数字，中文与阿拉伯数字都认。
    /// 顺序敏感：`["个小时", "小时"]` 里「个小时」必须排前面，否则「1个小时」会在「小时」处
    /// 往前吃到「个」而取不到数。
    private static func numberBefore(_ suffixes: [String], in transcript: String) -> Int? {
        for suffix in suffixes {
            if let value = chineseNumber(before: suffix, in: transcript), value > 0 {
                return value
            }
        }
        return nil
    }

    // MARK: - Emergency Handler

    /// Mirrors `EmergencyController.triggerEmergency` after the 2026-07-31 rewrite: escalation to the
    /// emergency contacts happens at trigger time (no 30s serial wait on the volunteer), so the
    /// receipt `status` collapses to **two** values — `CONTACT_NOTIFIED` when a primary contact
    /// exists, `PENDING` when none does. `VOLUNTEER_NOTIFIED` is no longer produced: notifying the
    /// volunteer is a parallel bypass that does not move `status`. The order status itself is
    /// deliberately left untouched — an emergency is a separate event, never an order state
    /// (`AGENTS.md` section 6).
    private func handleEmergencyTrigger(body: (any Encodable & Sendable)?) throws -> EmergencyTriggerResponse {
        guard let data = try? JSONEncoder().encode(AnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyTriggerRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        guard let order = orders.first(where: { $0.orderId == request.orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "订单不存在"))
        }
        guard order.status == .inProgress else {
            throw APIError.serverError(
                ErrorResponse(code: "NOT_ORDER_PARTICIPANT", message: "您无权操作此订单")
            )
        }
        emergencyEventSequence += 1
        let hasPrimaryContact = emergencyContacts.contains { $0.isPrimary == true }
        let status: EmergencyEventStatus = hasPrimaryContact ? .contactNotified : .pending
        activeEmergencyEvent = EmergencyEventResponse(
            id: emergencyEventSequence,
            orderId: order.orderId,
            userId: nil,
            status: status.rawValue,
            triggerType: "BUTTON",
            hasGpsLocation: request.gpsLat != nil && request.gpsLng != nil
        )
        return EmergencyTriggerResponse(
            success: true,
            eventId: emergencyEventSequence,
            status: status.rawValue
        )
    }

    /// `GET /api/emergency/active` —— 冷启动/重连恢复。没有未终态事件时 `data` 为 null。
    private func handleActiveEmergency() -> EmergencyActiveEnvelope {
        EmergencyActiveEnvelope(success: true, data: activeEmergencyEvent)
    }

    /// `PUT /api/emergency/{eventId}/cancel` —— 受助者本人撤销误触。
    private func handleCancelEmergency(eventId: Int64) throws -> EmergencyCancelResponse {
        guard let event = activeEmergencyEvent else {
            throw APIError.serverError(
                ErrorResponse(code: "EMERGENCY_ALREADY_CLOSED", message: "该求助已经结束")
            )
        }
        guard event.id == eventId else {
            throw APIError.serverError(
                ErrorResponse(code: "EMERGENCY_NOT_OWNER", message: "只能撤销自己的紧急求助")
            )
        }
        activeEmergencyEvent = nil
        return EmergencyCancelResponse(
            success: true,
            eventId: eventId,
            status: EmergencyEventStatus.falseAlarm.rawValue
        )
    }

    /// `PUT /api/emergency/{eventId}/volunteer-response` —— **只接受 `NEED_HELP`**。
    /// `FALSE_ALARM` 在线上是 403，Mock 必须同样拒绝，否则开发期会长出一个线上根本不存在的「误触」按钮。
    private func handleVolunteerEmergencyResponse(
        eventId: Int64,
        action: String?
    ) throws -> VolunteerEmergencyAcknowledgement {
        guard action == "NEED_HELP" else {
            throw APIError.serverError(
                ErrorResponse(
                    code: "EMERGENCY_VOLUNTEER_CANNOT_DISMISS",
                    message: "志愿者无权撤销求助，请确认对方是否需要帮助"
                )
            )
        }
        return VolunteerEmergencyAcknowledgement(success: true, eventId: eventId, action: action)
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
