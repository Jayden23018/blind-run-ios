import Foundation

// MARK: - Mock API Client

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        // 模拟网络延迟
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // 序列化请求体数据，供 Mock 路由使用
        var bodyData: Data? = nil
        if let body = body {
            bodyData = try JSONEncoder().encode(body)
        }

        let jsonData = try MockAPIStore.shared.response(for: path, method: method, bodyData: bodyData)
        return try JSONDecoder().decode(T.self, from: jsonData)
    }
}

// MARK: - Mock API Store

@MainActor
private final class MockAPIStore {
    static let shared = MockAPIStore()

    private struct Snapshot: Codable {
        let user: UserDto
        let blindRunnerProfile: BlindRunnerProfileDto?
        let volunteerProfile: VolunteerProfileDto?
        let orders: [RunOrderDto]

        init(user: UserDto, blindRunnerProfile: BlindRunnerProfileDto?, volunteerProfile: VolunteerProfileDto?, orders: [RunOrderDto]) {
            self.user = user
            self.blindRunnerProfile = blindRunnerProfile
            self.volunteerProfile = volunteerProfile
            self.orders = orders
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            user = try container.decode(UserDto.self, forKey: .user)
            blindRunnerProfile = try container.decodeIfPresent(BlindRunnerProfileDto.self, forKey: .blindRunnerProfile)
            volunteerProfile = try container.decodeIfPresent(VolunteerProfileDto.self, forKey: .volunteerProfile)
            orders = try container.decodeIfPresent([RunOrderDto].self, forKey: .orders) ?? []
        }
    }

    private enum Persistence {
        static let snapshotKey = "com.aidrun.mvp.mockAPIStore.snapshot"
    }

    private var user = UserDto(
        id: "00000000-0000-0000-0000-000000000001",
        phoneNumber: "13800138000",
        nickname: "测试用户",
        roles: [.blindRunner, .volunteer],
        activeRole: nil,
        createdAt: "2024-01-01T00:00:00Z",
        updatedAt: "2024-01-01T00:00:00Z"
    )

    private var blindRunnerProfile: BlindRunnerProfileDto?
    private var volunteerProfile: VolunteerProfileDto?
    private var orders: [RunOrderDto] = []

    private init() {
        restore()
    }

    func response(for path: String, method: HTTPMethod, bodyData: Data?) throws -> Data {
        seedBlindRunnerProfileForUITestsIfNeeded()
        seedVolunteerProfileForUITestsIfNeeded()
        seedVolunteerDemoDataIfNeeded()

        // 基础 Mock 路由，后续 PR 逐步补充完整数据
        if path.contains("/auth/phone-login") {
            // 解码请求体校验验证码（Demo 固定验证码 123456）
            if let bodyData = bodyData,
               let loginReq = try? JSONDecoder().decode(PhoneLoginRequest.self, from: bodyData) {
                // 空验证码视为"获取验证码"语义，直接返回成功
                if !loginReq.verificationCode.isEmpty && loginReq.verificationCode != "123456" {
                    throw APIError.serverError(ErrorResponse(
                        code: "INVALID_VERIFICATION_CODE",
                        message: "验证码错误"
                    ))
                }
                if user.phoneNumber != loginReq.phoneNumber {
                    blindRunnerProfile = nil
                    volunteerProfile = nil
                }
                user = UserDto(
                    id: user.id,
                    phoneNumber: loginReq.phoneNumber,
                    nickname: user.nickname,
                    roles: user.roles,
                    activeRole: user.activeRole,
                    createdAt: user.createdAt,
                    updatedAt: user.updatedAt
                )
                persist()
            }
            return try encode(AuthResponse(
                accessToken: "mock_jwt_token_for_testing",
                tokenType: "Bearer",
                user: user
            ))
        }

        // 角色切换 Mock (PATCH /api/users/me/active-role)
        if path.contains("/users/me") && method == .patch {
            if hasActiveOrderForCurrentUser() {
                throw APIError.serverError(ErrorResponse(
                    code: "ACTIVE_ORDER_ROLE_SWITCH_BLOCKED",
                    message: "存在进行中的订单，无法切换角色"
                ))
            }
            // 从请求体中解码目标角色
            var targetRole = UserRole.blindRunner
            if let bodyData = bodyData {
                if let switchRequest = try? JSONDecoder().decode(SwitchRoleRequest.self, from: bodyData) {
                    targetRole = switchRequest.activeRole
                }
            }
            // 返回更新后的 UserDto（activeRole 设为目标角色）
            user = userWith(nickname: user.nickname, activeRole: targetRole)
            persist()
            return try encode(user)
        }

        // GET /api/users/me
        if path.contains("/users/me") {
            return try encode(UserMeResponse(
                user: user,
                blindRunnerProfile: blindRunnerProfile,
                volunteerProfile: volunteerProfile
            ))
        }

        // PUT /api/profiles/blind-runner
        if path.contains("/profiles/blind-runner") && method == .put {
            guard let bodyData,
                  let request = try? JSONDecoder().decode(BlindRunnerProfileUpsertRequest.self, from: bodyData) else {
                return "{}".data(using: .utf8)!
            }
            let profile = BlindRunnerProfileDto(
                id: blindRunnerProfile?.id ?? "10000000-0000-0000-0000-000000000001",
                userId: user.id,
                nickname: request.nickname,
                runningExperience: request.runningExperience,
                emergencyContact: request.emergencyContact,
                createdAt: blindRunnerProfile?.createdAt ?? "2024-01-01T00:00:00Z",
                updatedAt: "2024-01-01T00:00:00Z"
            )
            blindRunnerProfile = profile
            user = userWith(nickname: profile.nickname, activeRole: user.activeRole)
            persist()
            return try encode(profile)
        }

        // PUT /api/profiles/volunteer
        if path.contains("/profiles/volunteer") && method == .put {
            guard let bodyData,
                  let request = try? JSONDecoder().decode(VolunteerProfileUpsertRequest.self, from: bodyData) else {
                return "{}".data(using: .utf8)!
            }
            let existing = currentVolunteerProfile()
            let profile = VolunteerProfileDto(
                id: existing.id,
                userId: user.id,
                nickname: request.nickname,
                phoneNumber: user.phoneNumber,
                verificationStatus: existing.verificationStatus,
                adminReviewStatus: existing.adminReviewStatus,
                isAvailable: existing.isAvailable,
                pointsBalance: existing.pointsBalance,
                createdAt: existing.createdAt,
                updatedAt: "2024-01-01T00:00:00Z"
            )
            volunteerProfile = profile
            user = userWith(nickname: profile.nickname, activeRole: user.activeRole)
            persist()
            return try encode(profile)
        }

        // POST /api/volunteer/mock-verification/approve
        if path.contains("/volunteer/mock-verification/approve") && method == .post {
            guard let existing = volunteerProfile else {
                throw APIError.serverError(ErrorResponse(
                    code: "PROFILE_INCOMPLETE",
                    message: "请先完善志愿者资料"
                ))
            }
            let profile = VolunteerProfileDto(
                id: existing.id,
                userId: user.id,
                nickname: existing.nickname,
                phoneNumber: user.phoneNumber,
                verificationStatus: .approved,
                adminReviewStatus: .approved,
                isAvailable: existing.isAvailable,
                pointsBalance: existing.pointsBalance,
                createdAt: existing.createdAt,
                updatedAt: "2024-01-01T00:00:00Z"
            )
            volunteerProfile = profile
            persist()
            return try encode(profile)
        }

        // PATCH /api/volunteer/availability
        if path.contains("/volunteer/availability") && method == .patch {
            guard let bodyData,
                  let request = try? JSONDecoder().decode(AvailabilityRequest.self, from: bodyData) else {
                return "{}".data(using: .utf8)!
            }
            guard let existing = volunteerProfile else {
                throw APIError.serverError(ErrorResponse(
                    code: "PROFILE_INCOMPLETE",
                    message: "请先完善志愿者资料"
                ))
            }
            guard existing.verificationStatus == .approved,
                  existing.adminReviewStatus == .approved else {
                throw APIError.serverError(ErrorResponse(
                    code: "VOLUNTEER_NOT_APPROVED",
                    message: "志愿者认证未通过"
                ))
            }
            let profile = VolunteerProfileDto(
                id: existing.id,
                userId: user.id,
                nickname: existing.nickname,
                phoneNumber: user.phoneNumber,
                verificationStatus: existing.verificationStatus,
                adminReviewStatus: existing.adminReviewStatus,
                isAvailable: request.isAvailable,
                pointsBalance: existing.pointsBalance,
                createdAt: existing.createdAt,
                updatedAt: "2024-01-01T00:00:00Z"
            )
            volunteerProfile = profile
            persist()
            return try encode(profile)
        }

        // POST /api/orders
        if path == "/api/orders" && method == .post {
            guard let bodyData,
                  let request = try? JSONDecoder().decode(CreateOrderRequest.self, from: bodyData) else {
                return "{}".data(using: .utf8)!
            }
            guard blindRunnerProfile != nil else {
                throw APIError.serverError(ErrorResponse(
                    code: "PROFILE_INCOMPLETE",
                    message: "请先完善盲人资料和紧急联系人"
                ))
            }

            let now = Date()
            guard let appointmentDate = ISO8601DateFormatter.aidRunFormatter.date(from: request.appointmentTime) ?? ISO8601DateFormatter().date(from: request.appointmentTime),
                  appointmentDate.timeIntervalSince(now) >= TimeInterval(AppConstants.Timing.minimumBookingLeadMinutes * 60) else {
                throw APIError.serverError(ErrorResponse(
                    code: "APPOINTMENT_TOO_SOON",
                    message: "预约时间至少需要在 30 分钟后"
                ))
            }

            let timestamp = ISO8601DateFormatter.aidRunFormatter.string(from: now)
            let order = RunOrderDto(
                id: UUID().uuidString,
                blindRunnerUserId: user.id,
                blindRunnerNickname: blindRunnerProfile?.nickname ?? user.nickname ?? "盲人跑者",
                blindRunnerPhone: user.phoneNumber,
                volunteerUserId: nil,
                volunteerNickname: nil,
                status: .matching,
                startLocation: request.startLocation,
                destinationText: request.destinationText,
                appointmentTime: request.appointmentTime,
                estimatedDurationMinutes: request.estimatedDurationMinutes,
                estimatedDistanceKm: request.estimatedDistanceKm,
                pacePreference: request.pacePreference,
                preferSameGender: request.preferSameGender,
                remark: request.remark,
                cancellation: nil,
                emergencyEvent: nil,
                serviceSummary: nil,
                rating: nil,
                createdAt: timestamp,
                updatedAt: timestamp,
                acceptedAt: nil,
                arrivedAt: nil,
                startedAt: nil,
                completedAt: nil,
                cancelledAt: nil,
                emergencyAt: nil
            )
            orders.insert(order, at: 0)
            persist()
            return try encode(order)
        }

        // GET /api/orders/my
        if path == "/api/orders/my" && method == .get {
            return try encode(orders.filter(isCurrentUserOrder))
        }

        // GET /api/orders/available
        if path == "/api/orders/available" && method == .get {
            let available = orders
                .filter { $0.status == .matching }
                .map { availableOrder(from: $0) }
            return try encode(available)
        }

        // GET /api/orders/{orderId}
        if let orderId = orderId(from: path), method == .get {
            guard let order = orders.first(where: { $0.id == orderId }) else {
                throw APIError.serverError(ErrorResponse(
                    code: "ORDER_NOT_FOUND",
                    message: "订单不存在"
                ))
            }
            return try encode(orderForCurrentUser(order))
        }

        // Order transition endpoints
        if let orderId = orderId(from: path), method == .post {
            if path.hasSuffix("/accept") {
                try validateVolunteerCanAccept()
                return try encode(try updateOrder(orderId: orderId, expected: .matching, target: .accepted))
            }
            if path.hasSuffix("/arrive") {
                return try encode(try updateOrder(orderId: orderId, expected: .accepted, target: .arrived))
            }
            if path.hasSuffix("/confirm-start") {
                return try encode(try updateOrder(orderId: orderId, expected: .arrived, target: .inProgress))
            }
            if path.hasSuffix("/complete") {
                return try encode(try completeOrder(orderId: orderId, bodyData: bodyData))
            }
            if path.hasSuffix("/cancel") {
                guard let bodyData,
                      let request = try? JSONDecoder().decode(CancelOrderRequest.self, from: bodyData) else {
                    return "{}".data(using: .utf8)!
                }
                return try encode(try cancelOrder(orderId: orderId, request: request))
            }
            if path.hasSuffix("/emergency") {
                return try encode(try emergencyOrder(orderId: orderId))
            }
        }

        // 未匹配的路径返回空 JSON 对象
        return "{}".data(using: .utf8)!
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func currentVolunteerProfile() -> VolunteerProfileDto {
        if let volunteerProfile {
            return volunteerProfile
        }
        let profile = VolunteerProfileDto(
            id: "20000000-0000-0000-0000-000000000001",
            userId: user.id,
            nickname: user.nickname ?? "",
            phoneNumber: user.phoneNumber,
            verificationStatus: .notSubmitted,
            adminReviewStatus: .notSubmitted,
            isAvailable: false,
            pointsBalance: 0,
            createdAt: "2024-01-01T00:00:00Z",
            updatedAt: "2024-01-01T00:00:00Z"
        )
        volunteerProfile = profile
        persist()
        return profile
    }

    private func validateVolunteerCanAccept() throws {
        guard let profile = volunteerProfile,
              !profile.nickname.trimmed.isEmpty,
              AppState.isValidMainlandPhone(profile.phoneNumber) else {
            throw APIError.serverError(ErrorResponse(
                code: "PROFILE_INCOMPLETE",
                message: "请先完善志愿者资料"
            ))
        }
        guard profile.verificationStatus == .approved,
              profile.adminReviewStatus == .approved else {
            throw APIError.serverError(ErrorResponse(
                code: "VOLUNTEER_NOT_APPROVED",
                message: "请先完成志愿者认证"
            ))
        }
        guard profile.isAvailable else {
            throw APIError.serverError(ErrorResponse(
                code: "VOLUNTEER_NOT_AVAILABLE",
                message: "请先开启可服务状态"
            ))
        }
    }

    private func availableOrder(from order: RunOrderDto) -> AvailableOrderDto {
        AvailableOrderDto(
            id: order.id,
            blindRunnerNickname: order.blindRunnerNickname,
            startLocation: order.startLocation,
            destinationText: order.destinationText,
            appointmentTime: order.appointmentTime,
            estimatedDurationMinutes: order.estimatedDurationMinutes,
            estimatedDistanceKm: order.estimatedDistanceKm,
            pacePreference: order.pacePreference,
            preferSameGender: order.preferSameGender,
            remark: order.remark,
            blindRunnerPhone: nil
        )
    }

    private func orderForCurrentUser(_ order: RunOrderDto) -> RunOrderDto {
        if shouldShowBlindRunnerPhone(order) {
            return order
        }
        return copyOrder(
            order,
            status: order.status,
            blindRunnerPhone: .some(nil),
            updatedAt: order.updatedAt ?? order.createdAt ?? ISO8601DateFormatter.aidRunFormatter.string(from: Date())
        )
    }

    private func shouldShowBlindRunnerPhone(_ order: RunOrderDto) -> Bool {
        order.blindRunnerUserId == user.id || order.volunteerUserId == user.id
    }

    private func isCurrentUserOrder(_ order: RunOrderDto) -> Bool {
        order.blindRunnerUserId == user.id || order.volunteerUserId == user.id
    }

    private func hasActiveOrderForCurrentUser() -> Bool {
        orders.contains { order in
            isCurrentUserOrder(order) &&
            [.accepted, .arrived, .inProgress, .emergency].contains(order.status)
        }
    }

    private func orderId(from path: String) -> String? {
        let prefix = "/api/orders/"
        guard path.hasPrefix(prefix) else { return nil }
        let remainder = String(path.dropFirst(prefix.count))
        return remainder.split(separator: "/").first.map(String.init)
    }

    private func updateOrder(orderId: String, expected: RunOrderStatus, target: RunOrderStatus) throws -> RunOrderDto {
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        let current = orders[index]
        guard current.status == expected else {
            let code = target == .accepted ? "ORDER_ALREADY_ACCEPTED" : "INVALID_ORDER_STATUS"
            throw APIError.serverError(ErrorResponse(code: code, message: "当前订单状态不允许该操作"))
        }

        let now = ISO8601DateFormatter.aidRunFormatter.string(from: Date())
        let volunteerProfile = volunteerProfile
        let updated = copyOrder(
            current,
            status: target,
            volunteerUserId: target == .accepted ? (volunteerProfile?.userId ?? "20000000-0000-0000-0000-000000000001") : current.volunteerUserId,
            volunteerNickname: target == .accepted ? (volunteerProfile?.nickname.nilIfBlank ?? "测试志愿者") : current.volunteerNickname,
            updatedAt: now,
            acceptedAt: target == .accepted ? now : current.acceptedAt,
            arrivedAt: target == .arrived ? now : current.arrivedAt,
            startedAt: target == .inProgress ? now : current.startedAt,
            completedAt: target == .completed ? now : current.completedAt
        )
        orders[index] = updated
        persist()
        return updated
    }

    private func completeOrder(orderId: String, bodyData: Data?) throws -> RunOrderDto {
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        let current = orders[index]
        guard current.status == .inProgress else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许该操作"))
        }
        guard current.volunteerUserId == user.id else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_ORDER_STATUS", message: "只能由接单志愿者结束服务"))
        }

        let request = bodyData.flatMap { try? JSONDecoder().decode(CompleteOrderRequest.self, from: $0) }
        let now = ISO8601DateFormatter.aidRunFormatter.string(from: Date())
        let summary = ServiceSummaryDto(
            id: UUID().uuidString,
            orderId: orderId,
            volunteerUserId: user.id,
            summaryText: request?.summaryText,
            createdAt: now
        )
        let updated = copyOrder(
            current,
            status: .completed,
            serviceSummary: summary,
            updatedAt: now,
            completedAt: now
        )
        orders[index] = updated

        if let existing = volunteerProfile {
            volunteerProfile = VolunteerProfileDto(
                id: existing.id,
                userId: existing.userId,
                nickname: existing.nickname,
                phoneNumber: existing.phoneNumber,
                verificationStatus: existing.verificationStatus,
                adminReviewStatus: existing.adminReviewStatus,
                isAvailable: existing.isAvailable,
                pointsBalance: existing.pointsBalance + 100,
                createdAt: existing.createdAt,
                updatedAt: now
            )
        }

        persist()
        return updated
    }

    private func cancelOrder(orderId: String, request: CancelOrderRequest) throws -> RunOrderDto {
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        let current = orders[index]
        guard current.status.canCancelBeforeStart else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许该操作"))
        }

        let now = ISO8601DateFormatter.aidRunFormatter.string(from: Date())
        let cancellation = CancellationDto(
            id: UUID().uuidString,
            orderId: orderId,
            cancelledBy: request.cancelledBy,
            cancelledReason: CancellationReason(rawValue: request.cancelledReason.rawValue) ?? .other,
            otherReasonText: request.otherReasonText,
            createdAt: now
        )
        let updated = copyOrder(
            current,
            status: .cancelled,
            cancellation: cancellation,
            updatedAt: now,
            cancelledAt: now
        )
        orders[index] = updated
        persist()
        return updated
    }

    private func emergencyOrder(orderId: String) throws -> RunOrderDto {
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else {
            throw APIError.serverError(ErrorResponse(code: "ORDER_NOT_FOUND", message: "订单不存在"))
        }
        let current = orders[index]
        guard current.status.canEnterEmergency else {
            throw APIError.serverError(ErrorResponse(code: "INVALID_ORDER_STATUS", message: "当前订单状态不允许该操作"))
        }

        let now = ISO8601DateFormatter.aidRunFormatter.string(from: Date())
        let emergencyEvent = EmergencyEventDto(
            id: UUID().uuidString,
            orderId: orderId,
            triggeredByRole: user.activeRole ?? .blindRunner,
            previousStatus: current.status,
            note: nil,
            createdAt: now
        )
        let updated = copyOrder(
            current,
            status: .emergency,
            emergencyEvent: emergencyEvent,
            updatedAt: now,
            emergencyAt: now
        )
        orders[index] = updated
        persist()
        return updated
    }

    private func copyOrder(
        _ order: RunOrderDto,
        status: RunOrderStatus,
        blindRunnerPhone: String?? = nil,
        volunteerUserId: String? = nil,
        volunteerNickname: String? = nil,
        cancellation: CancellationDto? = nil,
        emergencyEvent: EmergencyEventDto? = nil,
        serviceSummary: ServiceSummaryDto? = nil,
        updatedAt: String,
        acceptedAt: String? = nil,
        arrivedAt: String? = nil,
        startedAt: String? = nil,
        completedAt: String? = nil,
        cancelledAt: String? = nil,
        emergencyAt: String? = nil
    ) -> RunOrderDto {
        RunOrderDto(
            id: order.id,
            blindRunnerUserId: order.blindRunnerUserId,
            blindRunnerNickname: order.blindRunnerNickname,
            blindRunnerPhone: blindRunnerPhone ?? order.blindRunnerPhone,
            volunteerUserId: volunteerUserId ?? order.volunteerUserId,
            volunteerNickname: volunteerNickname ?? order.volunteerNickname,
            status: status,
            startLocation: order.startLocation,
            destinationText: order.destinationText,
            appointmentTime: order.appointmentTime,
            estimatedDurationMinutes: order.estimatedDurationMinutes,
            estimatedDistanceKm: order.estimatedDistanceKm,
            pacePreference: order.pacePreference,
            preferSameGender: order.preferSameGender,
            remark: order.remark,
            cancellation: cancellation ?? order.cancellation,
            emergencyEvent: emergencyEvent ?? order.emergencyEvent,
            serviceSummary: serviceSummary ?? order.serviceSummary,
            rating: order.rating,
            createdAt: order.createdAt,
            updatedAt: updatedAt,
            acceptedAt: acceptedAt ?? order.acceptedAt,
            arrivedAt: arrivedAt ?? order.arrivedAt,
            startedAt: startedAt ?? order.startedAt,
            completedAt: completedAt ?? order.completedAt,
            cancelledAt: cancelledAt ?? order.cancelledAt,
            emergencyAt: emergencyAt ?? order.emergencyAt
        )
    }

    private func userWith(nickname: String?, activeRole: UserRole?) -> UserDto {
        UserDto(
            id: user.id,
            phoneNumber: user.phoneNumber,
            nickname: nickname,
            roles: user.roles,
            activeRole: activeRole,
            createdAt: user.createdAt,
            updatedAt: "2024-01-01T00:00:00Z"
        )
    }

    private func seedVolunteerDemoDataIfNeeded() {
        guard orders.isEmpty else { return }

        let now = Date()
        let formatter = ISO8601DateFormatter.aidRunFormatter
        let createdAt = formatter.string(from: now.addingTimeInterval(-3_600))
        let appointmentOne = formatter.string(from: now.addingTimeInterval(7_200))
        let appointmentTwo = formatter.string(from: now.addingTimeInterval(10_800))
        let appointmentThree = formatter.string(from: now.addingTimeInterval(14_400))
        let completedAt = formatter.string(from: now.addingTimeInterval(-86_400))

        orders = [
            RunOrderDto(
                id: "30000000-0000-0000-0000-000000000001",
                blindRunnerUserId: "10000000-0000-0000-0000-000000000101",
                blindRunnerNickname: "李明",
                blindRunnerPhone: "13800001001",
                volunteerUserId: nil,
                volunteerNickname: nil,
                status: .matching,
                startLocation: LocationPoint(
                    latitude: AppConstants.Defaults.demoLatitude + 0.004,
                    longitude: AppConstants.Defaults.demoLongitude + 0.003,
                    addressText: "奥林匹克森林公园南门",
                    source: .demoDefault
                ),
                destinationText: "公园内环 3 公里",
                appointmentTime: appointmentOne,
                estimatedDurationMinutes: 35,
                estimatedDistanceKm: 3.0,
                pacePreference: "慢跑",
                preferSameGender: false,
                remark: "第一次体验，请提前到达。",
                cancellation: nil,
                emergencyEvent: nil,
                serviceSummary: nil,
                rating: nil,
                createdAt: createdAt,
                updatedAt: createdAt,
                acceptedAt: nil,
                arrivedAt: nil,
                startedAt: nil,
                completedAt: nil,
                cancelledAt: nil,
                emergencyAt: nil
            ),
            RunOrderDto(
                id: "30000000-0000-0000-0000-000000000002",
                blindRunnerUserId: "10000000-0000-0000-0000-000000000102",
                blindRunnerNickname: "王芳",
                blindRunnerPhone: "13800001002",
                volunteerUserId: nil,
                volunteerNickname: nil,
                status: .matching,
                startLocation: LocationPoint(
                    latitude: AppConstants.Defaults.demoLatitude + 0.012,
                    longitude: AppConstants.Defaults.demoLongitude + 0.006,
                    addressText: "朝阳公园西门",
                    source: .demoDefault
                ),
                destinationText: "湖边慢跑路线",
                appointmentTime: appointmentTwo,
                estimatedDurationMinutes: 45,
                estimatedDistanceKm: 4.0,
                pacePreference: "配速 8 分钟",
                preferSameGender: true,
                remark: nil,
                cancellation: nil,
                emergencyEvent: nil,
                serviceSummary: nil,
                rating: nil,
                createdAt: createdAt,
                updatedAt: createdAt,
                acceptedAt: nil,
                arrivedAt: nil,
                startedAt: nil,
                completedAt: nil,
                cancelledAt: nil,
                emergencyAt: nil
            ),
            RunOrderDto(
                id: "30000000-0000-0000-0000-000000000003",
                blindRunnerUserId: "10000000-0000-0000-0000-000000000103",
                blindRunnerNickname: "赵强",
                blindRunnerPhone: "13800001003",
                volunteerUserId: nil,
                volunteerNickname: nil,
                status: .matching,
                startLocation: LocationPoint(
                    latitude: AppConstants.Defaults.demoLatitude - 0.006,
                    longitude: AppConstants.Defaults.demoLongitude - 0.004,
                    addressText: "天坛公园东门",
                    source: .demoDefault
                ),
                destinationText: nil,
                appointmentTime: appointmentThree,
                estimatedDurationMinutes: nil,
                estimatedDistanceKm: nil,
                pacePreference: nil,
                preferSameGender: false,
                remark: "需要清楚报出路面变化。",
                cancellation: nil,
                emergencyEvent: nil,
                serviceSummary: nil,
                rating: nil,
                createdAt: createdAt,
                updatedAt: createdAt,
                acceptedAt: nil,
                arrivedAt: nil,
                startedAt: nil,
                completedAt: nil,
                cancelledAt: nil,
                emergencyAt: nil
            ),
            RunOrderDto(
                id: "30000000-0000-0000-0000-000000000004",
                blindRunnerUserId: "10000000-0000-0000-0000-000000000104",
                blindRunnerNickname: "陈晨",
                blindRunnerPhone: "13800001004",
                volunteerUserId: user.id,
                volunteerNickname: volunteerProfile?.nickname ?? "测试志愿者",
                status: .completed,
                startLocation: LocationPoint(
                    latitude: AppConstants.Defaults.demoLatitude + 0.002,
                    longitude: AppConstants.Defaults.demoLongitude - 0.002,
                    addressText: "什刹海健身步道",
                    source: .demoDefault
                ),
                destinationText: "湖边一圈",
                appointmentTime: formatter.string(from: now.addingTimeInterval(-90_000)),
                estimatedDurationMinutes: 30,
                estimatedDistanceKm: 2.5,
                pacePreference: "轻松跑",
                preferSameGender: nil,
                remark: nil,
                cancellation: nil,
                emergencyEvent: nil,
                serviceSummary: ServiceSummaryDto(
                    id: "40000000-0000-0000-0000-000000000001",
                    orderId: "30000000-0000-0000-0000-000000000004",
                    volunteerUserId: user.id,
                    summaryText: "顺利完成慢跑陪伴。",
                    createdAt: completedAt
                ),
                rating: nil,
                createdAt: formatter.string(from: now.addingTimeInterval(-172_800)),
                updatedAt: completedAt,
                acceptedAt: formatter.string(from: now.addingTimeInterval(-90_000)),
                arrivedAt: formatter.string(from: now.addingTimeInterval(-89_000)),
                startedAt: formatter.string(from: now.addingTimeInterval(-88_000)),
                completedAt: completedAt,
                cancelledAt: nil,
                emergencyAt: nil
            )
        ]
        persist()
    }

    private func seedBlindRunnerProfileForUITestsIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE"] == "1",
              blindRunnerProfile == nil else {
            return
        }
        let profile = BlindRunnerProfileDto(
            id: "10000000-0000-0000-0000-000000000099",
            userId: user.id,
            nickname: "UITestBlind",
            runningExperience: nil,
            emergencyContact: EmergencyContactDto(
                name: "UITestContact",
                phoneNumber: "13800001111"
            ),
            createdAt: "2024-01-01T00:00:00Z",
            updatedAt: "2024-01-01T00:00:00Z"
        )
        blindRunnerProfile = profile
        user = userWith(nickname: profile.nickname, activeRole: .blindRunner)
        persist()
        #endif
    }

    private func seedVolunteerProfileForUITestsIfNeeded() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_PROFILE"] == "1",
              volunteerProfile == nil else {
            return
        }
        let profile = VolunteerProfileDto(
            id: "20000000-0000-0000-0000-000000000099",
            userId: user.id,
            nickname: "UITestVolunteer",
            phoneNumber: user.phoneNumber,
            verificationStatus: .approved,
            adminReviewStatus: .approved,
            isAvailable: false,
            pointsBalance: 0,
            createdAt: "2024-01-01T00:00:00Z",
            updatedAt: "2024-01-01T00:00:00Z"
        )
        volunteerProfile = profile
        user = userWith(nickname: profile.nickname, activeRole: .volunteer)
        persist()
        #endif
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Persistence.snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        user = snapshot.user
        blindRunnerProfile = snapshot.blindRunnerProfile
        volunteerProfile = snapshot.volunteerProfile
        orders = snapshot.orders
    }

    private func persist() {
        let snapshot = Snapshot(
            user: user,
            blindRunnerProfile: blindRunnerProfile,
            volunteerProfile: volunteerProfile,
            orders: orders
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Persistence.snapshotKey)
    }
}
