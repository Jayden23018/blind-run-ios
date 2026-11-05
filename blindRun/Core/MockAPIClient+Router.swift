import CoreLocation
import Foundation

extension MockAPIClient {
    // MARK: - Router
    func routeRequest(
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
        // 拉黑的 DELETE 也挂在 /api/users/ 下，同样要放在下面的兜底拒绝之前。
        if let result = routeUserBlock(method: method, path: path) {
            return result
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
        // 线上培训（后端迁移 0043）。见 MockAPIClient+Training.swift
        if path == "/api/volunteer/training/courses" && method == .get {
            return handleGetTrainingCourses()
        }
        if let courseId = extractTrainingCourseId(from: path, suffix: nil), method == .get {
            return try handleGetTrainingCourseDetail(courseId: courseId)
        }
        if let courseId = extractTrainingCourseId(from: path, suffix: "progress"), method == .post {
            return try handleReportTrainingProgress(courseId: courseId, body: body)
        }
        if let courseId = extractTrainingCourseId(from: path, suffix: "quiz"), method == .post {
            return try handleSubmitTrainingQuiz(courseId: courseId, body: body)
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
        if path == "/api/volunteer/registration/step3/face-verify/decline" && method == .post {
            return try handleDeclineFaceVerify()
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
            // `AIDRUN_MOCK_CREATE_ORDER_REJECT=<码>`：演后端用开放范围码拒单（#667，`AccessibilityAuditTests+LaunchScope`）。
            try Self.throwMockLaunchScopeRejectionIfRequested()
            return try handleCreateOrder(body: body)
        }
        if path == "/api/orders/mine" && method == .get {
            return handleGetMyOrders(query: query)
        }
        if path == "/api/orders/mine/run-records" && method == .get {
            return try handleGetMyRunRecords(query: query)
        }
        // 排在下面 `extractOrderId` 那一族之前只是照这一节的写法；`Int64("active")` 是 nil，
        // 顺序其实无所谓。
        if path == "/api/orders/active" && method == .get {
            return handleGetActiveOrder()
        }
        // `/api/orders/available` 恒返**空数组**。
        //
        // App 从 2026-09-18 起真的会打它（邀请卡拿视力 / 引导方式 / 跑多久），所以不能再不路由
        // —— 不路由会走到下面的 `unsupported`，表现成每收一条邀请就记一笔假的网络错误。
        //
        // 🚩 **刻意不在这里编几条可接订单。** Mock 造得出来的只有「附近订单池」那条链路，
        // 而 App 此刻用它的方式是「按 orderId 匹配正在等我回复的那一单」——
        // 派单是客户端种子注入的，mock 这边根本没有对应的 id，编出来的条目只会替真实形状遮丑。
        // 邀请卡跑者行在 UI 测试里的可达性由 `uiTestSeedInvite` 直接塞 supplement 保证，
        // 匹配逻辑本身由 `VolunteerInviteState.merge` 的单测验。
        if path == "/api/orders/available" && method == .get {
            return [AvailableOrderResponse]()
        }

        // Order actions
        if let orderId = extractOrderId(from: path) {
            if path.hasSuffix("/track") && method == .get {
                return try handleGetOrderTrack(orderId: orderId)
            }
            // Mock 进程里没有真实设备坐标，也不许编一个：一律走「定位不到」那一支（`AGENTS.md` §3）。
            if path.hasSuffix("/location/address") && method == .get {
                return OrderLocationAddressResponse(degraded: true)
            }
            if path.hasSuffix("/run-record/messages") && method == .post {
                return try handlePostRunRecordMessage(orderId: orderId, body: body)
            }
            if path.hasSuffix("/run-record") && method == .get {
                return try handleGetRunRecord(orderId: orderId)
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
            if path.hasSuffix("/intro-call/plan") && method == .put {
                return try handleSubmitIntroCallPlan(orderId: orderId, body: body)
            }
            if path.hasSuffix("/intro-call") && method == .get {
                return try handleGetIntroCall(orderId: orderId)
            }
            // ⚠️ 必须排在 `/en-route` 之前吗？不必 —— 两条后缀不相交。但它们是**不同的动作**，
            // 别因为都通向出发流程就合并（后端契约逐字点了这一条：合并会让位置互推提前几小时打开）。
            if path.hasSuffix("/confirm-departure") && method == .post {
                return try handleConfirmDeparture(orderId: orderId)
            }
            if path.hasSuffix("/quick-message") && method == .post {
                return try handleQuickMessage(orderId: orderId)
            }
            if path.hasSuffix("/ring-runner") && method == .post {
                return try handleRingRunner(orderId: orderId)
            }
            if path.hasSuffix("/end-waiting") && method == .post {
                return try handleEndWaiting(orderId: orderId)
            }
            if path.hasSuffix("/pause") && method == .post {
                return try handleSetRunPaused(orderId: orderId, paused: true)
            }
            if path.hasSuffix("/resume") && method == .post {
                return try handleSetRunPaused(orderId: orderId, paused: false)
            }
            if path.hasSuffix("/runner-message") && method == .put {
                return try handleRunnerMessage(orderId: orderId, body: body)
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

        // 事后工单。Mock 只回「收到了」——后端也只回一个客户端用不上的工单对象，
        // 而这一屏唯一要的事实就是「提交成没成」。
        if path == "/api/support/tickets" && method == .post {
            return EmptyResponse()
        }
        if path == "/api/support/tickets" && method == .get {
            return Self.mockSupportTickets
        }
        if path == "/api/reports" && method == .post {
            return Self.mockReportTicket
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

        // 需登录、无参数的只读端点（功能开关 / 待回复邀请 / 规则参数），见 `MockAPIClient+AuthenticatedReads.swift`。
        if method == .get, let response = try handleAuthenticatedRead(path: path) {
            return response
        }

        // 陪跑员锁屏卡的推送 token。Mock 只收下不做事 —— 进程内没有 APNs 可推。
        if path == "/api/devices/live-activity-token" && method == .post {
            guard mockToken != nil else { throw APIError.unauthorized }
            return EmptyResponse()
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
}
