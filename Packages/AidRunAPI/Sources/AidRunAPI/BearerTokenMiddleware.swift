import Foundation
import HTTPTypes
import OpenAPIRuntime

/// 给每个出站请求带上 `Authorization: Bearer <jwt>`。
///
/// 为什么要手写：swift-openapi-generator 完全不处理 OpenAPI 的 `security` /
/// `securitySchemes`（apple/swift-openapi-generator#37，2023 年开至今）。
/// 实测生成的 16,162 行里 `Authorization` 出现 0 次。`Client.init` 自带
/// `middlewares:` 参数，是官方留的插入点。
public struct BearerTokenMiddleware: ClientMiddleware {
    /// 每次请求现取，而不是构造时取一次 —— token 会因登录、续期、登出而变，
    /// 快照下来会让 Client 一直用着过期的那个。
    private let tokenProvider: @Sendable () -> String?

    public init(tokenProvider: @escaping @Sendable () -> String?) {
        self.tokenProvider = tokenProvider
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // ponytail: 有 token 就带，没有就不带。不维护「哪些端点免鉴权」的白名单 ——
        // 那份名单会和契约反向漂移，而漂移正是这次引入生成器要消灭的东西。
        // 已知上限：登录后再调 send-code 这类公开端点也会带上 token。后端忽略它。
        // 若某天后端对公开端点上的陈旧 token 返 401，再按 operationID 加豁免。
        guard let token = tokenProvider(), !token.isEmpty else {
            return try await next(request, body, baseURL)
        }
        var request = request
        request.headerFields[.authorization] = "Bearer \(token)"
        return try await next(request, body, baseURL)
    }
}
