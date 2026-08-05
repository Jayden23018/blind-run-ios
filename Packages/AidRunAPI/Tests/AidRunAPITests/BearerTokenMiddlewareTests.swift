import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest

@testable import AidRunAPI

/// 中间件是唯一手写的鉴权路径 —— 生成器不碰 `security`。它坏了的表现是
/// 所有需要登录的接口静默 401，对盲人端就是「点了没反应」。所以它必须有测试。
final class BearerTokenMiddlewareTests: XCTestCase {
    /// 跑一次 intercept，把中间件交给下游的那个请求捞出来。
    private func capturedRequest(
        tokenProvider: @escaping @Sendable () -> String?,
        incoming: HTTPRequest = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/auth/me")
    ) async throws -> HTTPRequest {
        let middleware = BearerTokenMiddleware(tokenProvider: tokenProvider)
        let box = CapturedRequestBox()
        _ = try await middleware.intercept(
            incoming,
            body: nil,
            baseURL: URL(string: "http://47.114.113.171")!,
            operationID: "getCurrentUser",
            next: { request, _, _ in
                await box.store(request)
                return (HTTPResponse(status: .ok), nil)
            }
        )
        return await box.value!
    }

    func testAttachesBearerHeaderWhenTokenAvailable() async throws {
        let request = try await capturedRequest(tokenProvider: { "jwt-abc" })
        XCTAssertEqual(request.headerFields[.authorization], "Bearer jwt-abc")
    }

    func testOmitsHeaderWhenNoToken() async throws {
        let request = try await capturedRequest(tokenProvider: { nil })
        XCTAssertNil(request.headerFields[.authorization])
    }

    /// 空串是 Keychain 读失败时的常见返回。发 `Bearer ` 会让后端回 401，
    /// 而不是走「未登录」分支 —— 两者在 UI 上是不同文案。
    func testTreatsEmptyTokenAsNoToken() async throws {
        let request = try await capturedRequest(tokenProvider: { "" })
        XCTAssertNil(request.headerFields[.authorization])
    }

    /// token 是每次请求现取的，不是构造时快照。续期后必须立刻生效。
    func testReadsTokenOnEveryRequest() async throws {
        let counter = TokenCounter()
        let provider: @Sendable () -> String? = { counter.next() }

        let first = try await capturedRequest(tokenProvider: provider)
        let second = try await capturedRequest(tokenProvider: provider)

        XCTAssertEqual(first.headerFields[.authorization], "Bearer token-1")
        XCTAssertEqual(second.headerFields[.authorization], "Bearer token-2")
    }

    /// 中间件只加自己的头，不动路径、方法和已有的头。
    func testLeavesRestOfRequestUntouched() async throws {
        var incoming = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/api/orders")
        incoming.headerFields[.contentType] = "application/json"

        let request = try await capturedRequest(tokenProvider: { "jwt-abc" }, incoming: incoming)

        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/orders")
        XCTAssertEqual(request.headerFields[.contentType], "application/json")
    }
}

private actor CapturedRequestBox {
    var value: HTTPRequest?
    func store(_ request: HTTPRequest) { value = request }
}

private final class TokenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return "token-\(count)"
    }
}
