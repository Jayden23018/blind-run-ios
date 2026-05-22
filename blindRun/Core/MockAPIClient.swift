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

    private init() {
        restore()
    }

    func response(for path: String, method: HTTPMethod, bodyData: Data?) throws -> Data {
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

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Persistence.snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        user = snapshot.user
        blindRunnerProfile = snapshot.blindRunnerProfile
        volunteerProfile = snapshot.volunteerProfile
    }

    private func persist() {
        let snapshot = Snapshot(
            user: user,
            blindRunnerProfile: blindRunnerProfile,
            volunteerProfile: volunteerProfile
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Persistence.snapshotKey)
    }
}
