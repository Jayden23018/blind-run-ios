import CoreLocation
import Foundation

// MARK: - Mock API Client

/// 本地模拟 API Client，支持离线开发和 Demo 演示。
/// 模拟 300ms 网络延迟，内部维护状态，支持完整订单流程。
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {

    // MARK: - Internal State

    var mockToken: String? = nil
    var mockUserId: Int64 = 1
    var mockRole: UserRole? = nil
    var isAccountDeleted = false

    var blindProfile: BlindProfileResponse?
    /// 实名状态独立于资料本体保存：`AIDRUN_MOCK_BLIND_VERIFY_STATUS` 控制初始值，
    /// `AIDRUN_MOCK_BLIND_VERIFY_RESULT` 控制提交实名后的结果（均只接受 NOT_VERIFIED/VERIFIED/FAILED）。
    var blindVerifyStatus: String = BlindVerifyStatus.verified.rawValue
    var volunteerProfile: VolunteerProfileResponse?
    /// 资质证书审核状态，取值与后端 `VerificationStatus` 完全一致（NONE/PENDING/APPROVED/REJECTED）。
    /// `AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS` 可覆盖初始值，用于驱动四态 UI。
    var volunteerVerificationStatus: VolunteerCertificateStatus = .approved
    var volunteerRegistrationStepCode: String?
    var activeCloudAuthCertifyId: String?
    var emergencyContacts: [EmergencyContactResponse] = []

    var orders: [OrderDetailResponse] = []
    /// 通话磨合期两侧各自的表态。**按角色分开存**：后端的 `IntroCallPair` 也是两列
    /// （`blindDecision` / `volunteerDecision`），而 `IntroCallView.myDecision` 只回自己那一列 ——
    /// 存成一个值会让「只有一方表了态」这条最要紧的中间态在 Mock 里根本演不出来。
    var introCallDecisions: [Int64: [UserRole: IntroCallDecision]] = [:]
    private var emergencyEventSequence: Int64 = 9000
    /// 当前未终态的紧急事件，`GET /api/emergency/active` 的回放源。撤销后置 nil。
    private var activeEmergencyEvent: EmergencyEventResponse?
    var nextOrderId: Int64 = 100
    var nextContactId: Int64 = 100

    /// 每单已用掉的「继续等待」延长次数。
    ///
    /// 上限刻意设成 2 而不是后端默认的 10：这一档存在的唯一理由是让
    /// `KEEP_WAITING_LIMIT_REACHED` 那条分支在开发期离线走得到，点 10 次没人会点。
    /// 计数**不**随订单状态改变而清零 —— 后端的 `matchNotifyCount` 也是累计值。
    var keepWaitingCounts: [Int64: Int] = [:]
    static let mockKeepWaitingLimit = 2

    /// 已提交的评价，`GET /api/orders/{id}/reviews` 的回放源。没有键就是「尚未评价」，
    /// 对应后端的 200 + `data: null`。
    var orderReviews: [Int64: OrderReview] = [:]

    /// 志愿者已单方面退出的固定搭档（`DELETE /api/volunteer/favorites/{blindUserId}`）。
    ///
    /// 只记 userId、不删行 —— 与后端一致：退出是**打标记不是删行**，
    /// 那条记录仍然出现在两侧列表里，只是带上退出标记。
    var volunteerOptedOutPartnerIds: Set<Int64> = []

    /// 盲人当前收藏了哪几位志愿者（`PUT` / `DELETE /api/blind/favorite-volunteers/{volunteerId}`）。
    ///
    /// 与上面那个**刻意不同**：盲人侧取消收藏是真的删行（后端 `removeFavoriteVolunteer`），
    /// 志愿者侧退出是打标记。两条路的语义不一样，Mock 里也别写成一样。
    var blindFavoritedVolunteerIds: Set<Int64> = [9001, 9002, 9003]

    /// 后端默认 `app.favorite-volunteer.max-per-user=10`。
    static let mockFavoriteVolunteerLimit = 10

    /// 状态变更记录，`GET /api/orders/{id}/status-logs` 的回放源。
    /// **新的插在最前面**，与后端 `findByOrderIdOrderByChangedAtDesc` 同序。
    /// 种子订单刻意不带记录：它们的状态是直接摆出来的、没有经过状态机，
    /// 编一份假的转移史只会让「空列表」这条分支在开发期永远走不到。
    /// 想看有内容的样子，用页面底部的 Mock 状态测试按钮推一遍流程即可。
    var orderStatusLogs: [Int64: [OrderStatusLog]] = [:]
    var nextStatusLogId: Int64 = 5000

    /// 已生成的行程分享链接，按订单号存 —— `POST /api/orders/{id}/share` 的幂等性载体。
    /// 重复调返回同一条，`DELETE` 移除。
    var shareLinks: [Int64: ShareLinkResponse] = [:]

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

    /// 替志愿者那一侧表态。
    ///
    /// 存在理由：通话磨合要**两个人**才走得完，而 Mock 只有一个 `mockRole`。
    /// 没有它，「双方都说合适 ⇒ 成单」这条主路径在单设备上永远凑不齐，
    /// `PENDING_INTRO_CALL → PENDING_ACCEPT` 在开发期一次都跑不到。
    func simulateIntroCallDecisionForTesting(
        orderId: Int64,
        role: UserRole,
        decision: IntroCallDecision
    ) {
        guard let index = orders.firstIndex(where: { $0.orderId == orderId }),
              orders[index].status == .pendingIntroCall else { return }
        var decisions = introCallDecisions[orderId] ?? [:]
        decisions[role] = decision
        introCallDecisions[orderId] = decisions
        if decision == .decline {
            orders[index] = updateOrderStatus(orders[index], to: .pendingMatch)
            introCallDecisions[orderId] = nil
        } else if decisions[.blind] == .accept, decisions[.volunteer] == .accept {
            orders[index] = updateOrderStatus(
                orders[index],
                to: .pendingAccept,
                volunteerPhone: "13800000002"
            )
            introCallDecisions[orderId] = nil
        }
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
        if path == "/api/volunteer/achievements" && method == .get {
            return handleGetVolunteerAchievements()
        }
        // SPEC-E 激励体系
        if path == "/api/volunteer/points" && method == .get {
            return handleGetVolunteerPoints(query: query)
        }
        if path == "/api/blind/partners/streaks" && method == .get {
            return handleGetPartnerStreaks(asBlind: true)
        }
        if path == "/api/volunteer/partners/streaks" && method == .get {
            return handleGetPartnerStreaks(asBlind: false)
        }
        if path == "/api/blind/favorite-volunteers" && method == .get {
            return handleGetBlindFavoriteVolunteers()
        }
        if path.hasPrefix("/api/blind/favorite-volunteers/"),
           let volunteerId = Int64(path.replacingOccurrences(of: "/api/blind/favorite-volunteers/", with: "")) {
            if method == .put {
                return try handleAddBlindFavoriteVolunteer(volunteerId: volunteerId)
            }
            if method == .delete {
                return handleRemoveBlindFavoriteVolunteer(volunteerId: volunteerId)
            }
        }
        if path == "/api/volunteer/favorites" && method == .get {
            return handleGetVolunteerFavoritedBy()
        }
        if method == .delete,
           path.hasPrefix("/api/volunteer/favorites/"),
           let blindUserId = Int64(path.replacingOccurrences(of: "/api/volunteer/favorites/", with: "")) {
            return handleVolunteerOptOutOfFavorite(blindUserId: blindUserId)
        }
        if path == "/api/users/me/invite-code" && method == .get {
            return handleGetInviteCode()
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
        // 刻意没有 `/api/orders/available`：公开订单池那条链路已删除，App 不再请求它。
        // Mock 里保着一条 App 走不到的路由，只会在真实形状漂移时替它遮丑
        // —— 这条路径的真实响应是 `AvailableOrderResponse` 裸数组，与 `PagedOrderResponse` 不是一回事。

        // Order actions
        if let orderId = extractOrderId(from: path) {
            if path.hasSuffix("/track") && method == .get {
                return try handleGetOrderTrack(orderId: orderId)
            }
            if path.hasSuffix("/respond") && method == .post {
                return try handleRespondOrder(orderId: orderId, body: body)
            }
            // ⚠️ 三条 `intro-call/*` 必须排在 `intro-call` 之前 —— `hasSuffix("/intro-call")`
            // 对 `/intro-call/decision` 为 false，顺序其实无所谓，但把子路径放前面
            // 是这一族路由的既有写法（见下面 `/review` 与 `/reviews` 那段注释）。
            if path.hasSuffix("/intro-call/decision") && method == .post {
                return try handleIntroCallDecision(orderId: orderId, body: body)
            }
            if path.hasSuffix("/intro-call/unreachable") && method == .post {
                return try handleIntroCallUnreachable(orderId: orderId)
            }
            if path.hasSuffix("/intro-call/notify-incoming") && method == .post {
                return try handleIntroCallNotifyIncoming(orderId: orderId)
            }
            if path.hasSuffix("/intro-call") && method == .get {
                return try handleGetIntroCall(orderId: orderId)
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
            // ⚠️ `PUT`，不是 `POST` —— 契约里这两条都是 `put`（`api_spec.yaml:236` / `:256`），
            // 与同文件里其余走 POST 的状态流转端点不同族。
            if path.hasSuffix("/keep-waiting") && method == .put {
                return try handleKeepWaiting(orderId: orderId, requiredStatus: .pendingMatch)
            }
            if path.hasSuffix("/keep-rematching") && method == .put {
                return try handleKeepWaiting(orderId: orderId, requiredStatus: .rematching)
            }
            if path.hasSuffix("/review") && method == .post {
                return try handleReview(orderId: orderId, body: body)
            }
            // ⚠️ 读是 `/reviews`（复数），写是 `/review`（单数）—— 契约就是这么不对称的
            // （`ReviewController.java:41` vs `:30`）。这里能靠 `hasSuffix` 分开纯属巧合，
            // 换成 `contains("/review")` 之类的宽松匹配就会把读吞进写的分支。
            if path.hasSuffix("/reviews") && method == .get {
                return try handleGetReview(orderId: orderId)
            }
            if path.hasSuffix("/status-logs") && method == .get {
                return try handleGetStatusLogs(orderId: orderId)
            }
            // 同一条路径两个方法：`POST` 开分享、`DELETE` 停分享（`api_spec.yaml` 的
            // `createShareLink` / `revokeShareLink`）。分开两个 `if` 而不是 switch method，
            // 与本文件其余路由同形。
            if path.hasSuffix("/share") && method == .post {
                return try handleCreateShareLink(orderId: orderId)
            }
            if path.hasSuffix("/share") && method == .delete {
                return try handleRevokeShareLink(orderId: orderId)
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

        // 解绑本机 token（登出流程）。后端**幂等**：token 不存在、或属于别人时同样返 200 且不做事
        // —— 返 403 会把「这个 token 是不是别人的」变成可探测的答案（契约 `unregisterApnsToken`）。
        if path == "/api/devices/apns" && method == .delete {
            return try handleUnregisterApnsToken(body: body)
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
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
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

    /// 解绑。`401` 那条分支照抄真实后端的行为，正是它让「先 logout 再解绑」的错误顺序
    /// 在 Mock 上也现原形：logout 之后 `mockToken` 已清，这里就会抛 `unauthorized`。
    private func handleUnregisterApnsToken(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(ApnsTokenRequestProbe.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        // 幂等：不存在也返 200。
        registeredApnsTokens.remove(request.deviceToken)
        return EmptyResponse()
    }

    /// 后端每页上限 50，Mock 刻意压到 3。
    /// 照搬 50 等于把续读那条路藏起来：没人会为了开发期调试手工造 51 条离线通知，
    /// 于是 `hasMore = true` 在 Mock 上永远不出现，多页补读只能靠上线后出事才被发现。
    private static let mockCatchUpPageSize = 3

    private func handleGetMissedNotifications(after: String?) throws -> MissedNotificationPage {
        guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
        guard let after, !after.isEmpty, !after.allSatisfy(\.isNumber) else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_TIMESTAMP", message: "after 格式错误"))
        }
        // 后端窗口：sent_at > after，24h 内，按时间正序，每页有上限。
        let window = missedNotifications
            .filter { ($0.sentAt ?? "") > after }
            .sorted { ($0.sentAt ?? "") < ($1.sentAt ?? "") }
        let page = Array(window.prefix(Self.mockCatchUpPageSize))
        return MissedNotificationPage(notifications: page, hasMore: window.count > page.count)
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

    // MARK: - Emergency Handler

    /// Mirrors `EmergencyController.triggerEmergency` after the 2026-07-31 rewrite: escalation to the
    /// emergency contacts happens at trigger time (no 30s serial wait on the volunteer), so the
    /// receipt `status` collapses to **two** values — `CONTACT_NOTIFIED` when a primary contact
    /// exists, `PENDING` when none does. `VOLUNTEER_NOTIFIED` is no longer produced: notifying the
    /// volunteer is a parallel bypass that does not move `status`. The order status itself is
    /// deliberately left untouched — an emergency is a separate event, never an order state
    /// (`AGENTS.md` section 6).
    private func handleEmergencyTrigger(body: (any Encodable & Sendable)?) throws -> EmergencyTriggerResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
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

    /// ⚠️ **这里的三态是后端的，不是客户端的，两者不是同一个三态。** 别"顺手对齐"成后者。
    ///
    /// - 后端 `OrderStatus.sharesLiveLocation()`：`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`
    /// - 客户端 `RunOrderStatus.offersVolunteerDistanceToStart`：`PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`
    ///
    /// 交集只有中间两态。`PENDING_ACCEPT` 时客户端会调而后端返 404（位置 key 不存在）；
    /// `IN_PROGRESS` 时后端有数据而客户端根本不调（那一段的对方位置走 WebSocket
    /// `peerLocationPublisher`，没有 REST 兜底）。Mock 必须照**后端**来演，
    /// 否则这个不对称在开发期永远看不见 —— 上一次 Mock 自作主张（造了个后端不发的
    /// `updatedAt`）的代价是兜底对真实后端 100% 静默失效。
    private func handleGetVolunteerLocation() -> VolunteerLocationResponse {
        let sharing = orders.first {
            [.driverEnRoute, .driverArrived, .inProgress].contains($0.status)
        }
        return VolunteerLocationResponse(
            success: true,
            code: 200,
            message: nil,
            data: VolunteerLocationData(
                orderId: sharing?.orderId,
                status: sharing?.status,
                // epoch 毫秒，与 WS `VOLUNTEER_LOCATION_UPDATE` 的 `timestamp` 同格式（后端 119c810）。
                updatedAt: sharing.map { _ in Int64(Date().timeIntervalSince1970 * 1_000) },
                lat: AppConstants.Defaults.demoLatitude + 0.002,
                lng: AppConstants.Defaults.demoLongitude + 0.001
            )
        )
    }

    // MARK: - Helpers

    func updateOrderStatus(
        _ order: OrderDetailResponse,
        to newStatus: RunOrderStatus,
        volunteerPhone: String? = nil
    ) -> OrderDetailResponse {
        appendStatusLog(
            orderId: order.orderId,
            from: order.status,
            to: newStatus,
            remark: Self.mockStatusLogRemark(to: newStatus)
        )
        return OrderDetailResponse(
            orderId: order.orderId,
            status: newStatus,
            startAddress: order.startAddress,
            startLatitude: order.startLatitude,
            startLongitude: order.startLongitude,
            endAddress: order.endAddress,
            endLatitude: order.endLatitude,
            endLongitude: order.endLongitude,
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

    /// Mock 的 remark 逐字抄后端那 12 处 `logStatusChange` 的第五个参数，
    /// 让「remark 就是可朗读的中文」这条前端假设在开发期真的被验到。
    /// `CANCELLED` 刻意保留后端那个机器串（`"取消方=" + CancelledBy`）——
    /// `OrderStatusLog.displayText` 的翻译分支只有靠它才走得到。
    private static func mockStatusLogRemark(to newStatus: RunOrderStatus) -> String {
        switch newStatus {
        case .pendingMatch: return "创建订单"
        case .pendingIntroCall: return "志愿者表示有意向，进入通话磨合"
        case .pendingAccept: return "志愿者接单"
        case .driverEnRoute: return "志愿者已出发"
        case .driverArrived: return "志愿者已到达"
        case .inProgress: return "志愿者确认开始服务"
        case .completed: return "服务完成"
        case .cancelled: return "取消方=BLIND"
        case .rematching: return "志愿者取消，进入重新匹配，第1次"
        case .noVolunteer, .unknown: return ""
        }
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

        // 让 UI 用例把种子订单直接钉在某个状态上。没有它，要验 `IN_PROGRESS` 的页面就得在订单状态页
        // 最底部的 mock 面板上连点三次（模拟接单 → 模拟到达 → 模拟服务开始），每次都要先滚到底 ——
        // 慢，而且滚动 + 盲点 tap 正是 `snapshot timeout` 那类误触的温床。
        //
        // 与 `AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS` 同口径：只认真实存在的取值，
        // 未知值（含 `UNKNOWN` 这个纯解码兜底）一律忽略、退回原来的种子状态。
        let seededStatus: RunOrderStatus? = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SEED_ORDER_STATUS"]
            .flatMap(RunOrderStatus.init(rawValue:))
            .flatMap { RunOrderStatus.allCases.contains($0) ? $0 : nil }
        let activeOrderStatus = seededStatus ?? (uiTestActiveVolunteerOrder ? .pendingAccept : .pendingMatch)
        // 汇合之后的状态必须带上接单痕迹，否则页面会同时显示「进行中」和「还没有志愿者」。
        // `plannedStart` 同理要落到过去：一单已经跑起来的约在两小时后开始是自相矛盾的，
        // 而「预计结束时间」「已进行时长」都从这两个字段算。
        //
        // 判据借 `offersVolunteerCall` —— 它的语义就是「本单此刻有一个还在场的志愿者」
        // （`REMATCHING` 为 false，因为那个志愿者已经退出了），正是要不要填
        // `volunteerPhone` / `acceptedAt` 的同一个问题，不另起一套集合字面量。
        let isPastMatching = activeOrderStatus.offersVolunteerCall
        let startedAt = Calendar.current.date(byAdding: .minute, value: -20, to: Date())!
        let startedEnd = Calendar.current.date(byAdding: .minute, value: 40, to: Date())!

        orders = [
            OrderDetailResponse(
                orderId: 1,
                status: activeOrderStatus,
                startAddress: "朝阳公园南门",
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                // 种子订单**刻意不带终点**：UI 用例按现有行数与标签断言，凭空多一行会假失败。
                // 终点的展示路径由「语音下单 → 志愿者接单」这条真实路径覆盖，
                // 不靠种子数据摆样子。
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
                plannedStart: formatter.string(from: isPastMatching ? startedAt : futureDate),
                plannedEnd: formatter.string(from: isPastMatching ? startedEnd : futureEnd),
                blindName: "李明",
                blindPhone: "13800001001",
                volunteerPhone: isPastMatching ? "13800000002" : nil,
                acceptedAt: isPastMatching ? activeAcceptedAt : nil,
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
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
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

// MARK: - MockAnyEncodable Helper

/// Helper to bridge `any Encodable` to concrete Encodable for JSONEncoder.
/// 拆分成 `MockAPIClient+*.swift` 之后它必须是 internal，所以带上 `Mock` 前缀 ——
/// 这是 Mock 内部的编码桥，不是 App 词汇表里的类型。
struct MockAnyEncodable: Encodable {
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
