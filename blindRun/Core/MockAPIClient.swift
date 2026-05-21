import Foundation

// MARK: - Mock API Client

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {

    func request<T: Decodable & Sendable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        // 模拟网络延迟
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        let jsonData = try mockResponse(for: path, method: method)
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    // MARK: - Mock Data Routing

    private func mockResponse(for path: String, method: HTTPMethod) throws -> Data {
        // 基础 Mock 路由，后续 PR 逐步补充完整数据
        if path.contains("/auth/login") {
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
