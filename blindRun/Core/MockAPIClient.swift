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

        let jsonData = try mockResponse(for: path, method: method, bodyData: bodyData)
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    // MARK: - Mock Data Routing

    private func mockResponse(for path: String, method: HTTPMethod, bodyData: Data?) throws -> Data {
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
            }
            return try encode(AuthResponse(
                accessToken: "mock_jwt_token_for_testing",
                tokenType: "Bearer",
                user: UserDto(
                    id: "00000000-0000-0000-0000-000000000001",
                    phoneNumber: "13800138000",
                    nickname: "测试用户",
                    roles: [.blindRunner, .volunteer],
                    activeRole: nil,
                    createdAt: "2024-01-01T00:00:00Z",
                    updatedAt: "2024-01-01T00:00:00Z"
                )
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
            return try encode(UserDto(
                id: "00000000-0000-0000-0000-000000000001",
                phoneNumber: "13800138000",
                nickname: "测试用户",
                roles: [.blindRunner, .volunteer],
                activeRole: targetRole,
                createdAt: "2024-01-01T00:00:00Z",
                updatedAt: "2024-01-01T00:00:00Z"
            ))
        }

        // GET /api/users/me
        if path.contains("/users/me") {
            return try encode(UserMeResponse(
                user: UserDto(
                    id: "00000000-0000-0000-0000-000000000001",
                    phoneNumber: "13800138000",
                    nickname: "测试用户",
                    roles: [.blindRunner, .volunteer],
                    activeRole: .blindRunner,
                    createdAt: "2024-01-01T00:00:00Z",
                    updatedAt: "2024-01-01T00:00:00Z"
                ),
                blindRunnerProfile: nil,
                volunteerProfile: nil
            ))
        }

        // 未匹配的路径返回空 JSON 对象
        return "{}".data(using: .utf8)!
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}
