import Foundation
@testable import blindRun

/// 只记录并回放罐装值的 transport。**不含任何判定** —— 判定属于被测代码。
///
/// 领域 service 层各片的「端点映射」用例共用这一个：断言某个方法打的是不是那一条
/// method / path / query / requiresAuth。路径字面量本身由
/// `scripts/validate-spec-coverage.mjs` 对着后端契约撞，那个脚本看不出
/// `logout()` 打成了 `/api/auth/me`，这里管的就是那一半。
///
/// 与 `MockAPIClient` 的分工：Mock 演后端行为（幂等、门槛、错误码），
/// 这个只记流水账，一条业务判定都不许加。
final class RecordingTransport: APIClientProtocol, @unchecked Sendable {
    struct Recorded {
        let method: HTTPMethod
        let path: String
        let query: [String: String]?
        let requiresAuth: Bool
        let hasBody: Bool
    }

    var nextResponse: Any?
    private(set) var requests: [Recorded] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requests.append(
            Recorded(method: method, path: path, query: query, requiresAuth: requiresAuth, hasBody: body != nil)
        )
        guard let typed = nextResponse as? T else { throw APIError.unknown(statusCode: -1) }
        return typed
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.unknown(statusCode: -1)
    }
}
