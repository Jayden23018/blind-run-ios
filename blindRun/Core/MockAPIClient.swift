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
    /// 志愿者是否已依《人脸识别技术应用安全管理办法》第十条拒绝人脸、转「二要素 + 人工审核」。
    /// 缺了它 Mock 下走完 decline 状态一点不变，替代路径整条在开发期和 UI 测试里都验不了。
    var volunteerFaceVerifyDeclined = false
    /// 线上培训进度：courseId → 进度（后端迁移 `0043`）。
    ///
    /// 🚩 **初始为空 = 一门课都没学**，这是刻意的默认：Mock 环境下第一次进志愿者首页
    /// 就应该看到 `TRAINING_INCOMPLETE`，否则「未完成培训 → 接不到单 → 去培训」
    /// 这条主路径在开发期和 UI 测试里一次都走不到。
    /// 想演「已完成」的用例自己先调 `completeAllRequiredTrainingForTesting()`。
    var trainingProgress: [Int64: MockTrainingProgress] = [:]
    var emergencyContacts: [EmergencyContactResponse] = []

    var orders: [OrderDetailResponse] = []
    /// 通话磨合期两侧各自的表态。**按角色分开存**：后端的 `IntroCallPair` 也是两列
    /// （`blindDecision` / `volunteerDecision`），而 `IntroCallView.myDecision` 只回自己那一列 ——
    /// 存成一个值会让「只有一方表了态」这条最要紧的中间态在 Mock 里根本演不出来。
    var introCallDecisions: [Int64: [UserRole: IntroCallDecision]] = [:]
    /// 这一轮见面安排单的最新一版（#755）。本轮没约成 / 约成都清掉 —— 后端也是随本轮删除、约成后写进订单。
    var introCallPlans: [Int64: IntroCallPlanView] = [:]
    /// 这一轮 `PUT /plan` 的提交次数，**被拒的也算**（契约原话）。
    var introCallPlanSubmissionCounts: [Int64: Int] = [:]
    /// 镜像后端开关 `app.intro-call.plan-required`，缺省 `false` 与后端一致。
    /// 新版客户端两种状态下都必须走得通（陪跑员一律 `PUT /plan`、盲人一律带 `planVersion`），
    /// 所以用例要能把它拨到 `true` 验一遍：关着时老路也通，会把「新客户端漏发 planVersion」藏起来。
    var introCallPlanRequired = false
    var emergencyEventSequence: Int64 = 9000
    /// 当前未终态的紧急事件，`GET /api/emergency/active` 的回放源。撤销后置 nil。
    var activeEmergencyEvent: EmergencyEventResponse?
    /// 倒计时到点后这条事件该变成什么（有没有主紧急联系人决定），见 `handleEmergencyTrigger`。
    var mockFiredEmergencyStatus: EmergencyEventStatus = .pending
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

    /// 我拉黑的人，`GET /api/users/blocked` 的回放源，最近的在前。
    var blockedUsers: [BlockedUserResponse] = []

    /// 跑后留言，`GET /api/orders/{id}/run-record` 的 `messages` 回放源。
    var runRecordMessages: [Int64: [RunRecordMessageResponse]] = [:]

    /// 跑步数据页的样例（#710）：按订单号存公里、陪伴分钟。没有条目的单照旧按 1.04 公里。
    /// 只由 `seedRunDataForUITestIfRequested` 写入。
    var runRecordSamples: [Int64: MockRunRecordSample] = [:]

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

    /// Mock 订单接单之后那位志愿者是谁 —— `OrderDetailResponse.volunteerId` / `volunteerName` 的取值。
    ///
    /// **刻意选一个初始未收藏、但在 `blindFavoriteSeeds` 里的 id**：订单详情页的
    /// 「把他设为固定搭档」按钮只在未收藏时出现，而 Mock 的收藏门槛是「这个 id 在不在种子表里」。
    /// 用 9001–9003（初始已收藏）会让那个按钮在开发期永远不出现，
    /// 用一个不在种子表里的 id 则会让它必然报 `FAVORITE_VOLUNTEER_NOT_ELIGIBLE` ——
    /// 两种都会让新入口的主路径一次都走不到。
    ///
    /// 常量放这里而不放 `MockIncentiveSeed`：那个 enum 是 `private`，
    /// 而 `updateOrderStatus` 在本文件，跨不过去。种子表反过来引用它，单一来源。
    static let mockOrderVolunteerId: Int64 = 9005
    /// 掩码姓名，与后端口径一致（全名一律不下发）。
    static let mockOrderVolunteerName = "陈*"

    /// 这位志愿者累计完成过多少单。首页深蓝卡与订单页陪跑员行的「陪跑 N 次」用它。
    ///
    /// 取 32 是为了和设计稿 `design-reference/order-flow/` 的截图对得上 ——
    /// 截图对照时 Mock 与参考图显示同一个数，差异就只剩排版本身。
    static let mockOrderVolunteerCompletedRuns = 32

    /// 这一态后端会不会下发 `volunteerId` / `volunteerName`。
    ///
    /// 契约：`PENDING_MATCH` / `PENDING_INTRO_CALL` / `REMATCHING` / `NO_VOLUNTEER` / `CANCELLED`
    /// 期 `order.volunteer` 恒为 null，其余状态有值。
    ///
    /// 🚨 **判据不能借 `offersVolunteerCall`**（种子订单填 `volunteerPhone` 用的就是它）：
    /// 号码只在需要当面汇合的四态下发，`COMPLETED` 时为 null，而 `volunteerId` 在 `COMPLETED`
    /// **仍然有值** —— 订单详情的收藏入口正是开在已完成订单上的。借错的直接症状是
    /// 那个按钮在唯一该出现的地方不出现，且没有任何报错。
    /// （同一类坑的归档：记忆 `same-name-predicate-different-sets-across-ends`。）
    ///
    /// 穷举 switch 而不是集合字面量：后端加状态时编译器在这里逼一次决策。
    static func mockHasAcceptedVolunteer(_ status: RunOrderStatus) -> Bool {
        switch status {
        case .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .completed:
            return true
        case .pendingMatch, .pendingIntroCall, .rematching, .noVolunteer, .cancelled, .unknown:
            return false
        }
    }

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
    var registeredApnsTokens: Set<String> = []
    /// `/api/notifications/since` 的补读语料。Mock 不主动产生离线通知，默认为空。
    var missedNotifications: [MissedNotificationResponse] = []

    // MARK: - Init

    init() {
        seedDemoData()
        seedHomeHistoryForUITestIfRequested()
        seedRunDataForUITestIfRequested()
        // Mock 默认未完成培训，而未完成培训滑不开开关。测开关本身的 UI 用例用它声明前提。
        if ProcessInfo.processInfo.environment["AIDRUN_MOCK_VOLUNTEER_TRAINING_COMPLETED"] == "1" {
            completeAllRequiredTrainingForTesting()
        }
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
        // 与真实入口同一道安排单闸门：开关打开时，代打的「合适」也不许绕过安排单成单。
        if decision == .accept,
           (try? checkIntroCallPlanGate(orderId: orderId, role: role, planVersion: introCallPlans[orderId]?.version)) == nil {
            return
        }
        var decisions = introCallDecisions[orderId] ?? [:]
        decisions[role] = decision
        introCallDecisions[orderId] = decisions
        if decision == .decline {
            orders[index] = updateOrderStatus(orders[index], to: .pendingMatch)
            endIntroCallRound(orderId: orderId)
        } else if decisions[.blind] == .accept, decisions[.volunteer] == .accept {
            orders[index] = updateOrderStatus(
                orders[index],
                to: .pendingAccept,
                volunteerPhone: "13800000002",
                meetupPlan: introCallPlans[orderId]
            )
            endIntroCallRound(orderId: orderId)
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

    #if DEBUG
    private static var orderDetailRequestCountForUITest = 0
    #endif

    // MARK: - APIClientProtocol

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        #if DEBUG
        // ⚠️ 盲人首页 2026-08-31 起走 `/api/orders/active`（不再是 `/api/orders/mine`，
        // 那条现在只剩历史页在用）。两条都留着：漏掉 active 这一条，
        // 「首页请求挂住」这组 UI 测试就会静默变成「首页正常加载」，用例照样绿。
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_HANG_HOME_REQUESTS"] == "1",
           path == "/api/orders/active" || path == "/api/orders/mine"
            || path == "/api/volunteer/dispatch-summary" {
            await Self.suspendForeverIgnoringCancellation()
            throw CancellationError()
        }
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_HANG_TRANSITION_CONFIRMATION"] == "1",
           method == .get,
           path.matches(of: try! Regex("/api/orders/\\d+$")).count > 0 {
            await Self.suspendForeverIgnoringCancellation()
            throw CancellationError()
        }
        // 跑到一半凭证过期（#376）：订单详情第一次照常返回（订单页要靠它渲染出求助入口），之后一律 401。
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_UNAUTHORIZED_AFTER_FIRST_ORDER_DETAIL"] == "1",
           method == .get,
           path.matches(of: try! Regex("/api/orders/\\d+$")).count > 0 {
            Self.orderDetailRequestCountForUITest += 1
            if Self.orderDetailRequestCountForUITest > 1 { throw APIError.unauthorized }
        }
        // 让退出登录 / 删除账户在 `.inProgress` 停够几秒，UI 测试才断得到进度遮罩那一刻的无障碍树。
        // 限时而不是永久挂起：退出登录配 `AIDRUN_MOCK_LOGOUT_FAILURE` 就能走到「失败 → 照样清本地 → 登录页」（#391），
        // 同一条用例顺带验遮罩收起后新挂上的登录页在树里。
        if path == "/api/auth/logout" || (method == .delete && path.hasPrefix("/api/users/")),
           let seconds = Double(ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SLOW_SESSION_END_SECONDS"] ?? "") {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
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
    func applyVolunteerVerificationStatusToProfile() {
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
}
