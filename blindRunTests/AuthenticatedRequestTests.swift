import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class AuthenticatedRequestTests: XCTestCase, BlindRunTestSupport {
    func testURLSessionRateLimitPrefersRetryAfterHeader() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthLifecycleURLProtocol.self]
        AuthLifecycleURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "7"]
            )!
            let data = #"{"code":"RATE_LIMITED","message":"注册过于频繁","retryAfterSeconds":99}"#.data(using: .utf8)!
            return (response, data)
        }
        let client = URLSessionAPIClient(baseURL: URL(string: "http://example.test")!, session: URLSession(configuration: configuration), tokenProvider: { nil })

        do {
            let _: EmptyResponse = try await client.post("/registration", requiresAuth: false)
            XCTFail("Expected rate limit")
        } catch APIError.rateLimited(let info) {
            XCTAssertEqual(info.retryAfterSeconds, 7)
            XCTAssertEqual(info.message, "注册过于频繁")
        }
        AuthLifecycleURLProtocol.handler = nil
    }

    /// `requiresAuth` 却拿不到 Token 时，**一个请求都不许发出去**，且抛的必须是
    /// `.missingCredentials` 而不是 `.unauthorized`。
    ///
    /// 这条守的是 2026-08-16 那次排查里最贵的一段。旧写法是「没 Token 就静默不带头发出去」，
    /// 于是：服务端理所当然回 401 → 客户端把它当成会话被撤销 → `expireSession()`
    /// → 清掉 Token → 弹「登录状态已失效」。本地状态错误伪装成服务端拒绝，
    /// 且清 Token 顺手把现场抹了 —— 抓包看到 401、服务端日志看到「没带 Authorization 头」，
    /// 两边互相指向对方。
    ///
    /// 空串一并覆盖：那是 Keychain 读失败的常见返回值，发出去是个空的 `Bearer `，
    /// 与没带头同样 401 却更难看出来。
    ///
    /// **stub 的 handler 刻意留空**：一旦真的发出请求，它会抛 `badServerResponse`，
    /// 客户端拿到的就是 `.networkError`。所以「catch 到 `.missingCredentials`」
    /// 本身就证明了请求没出门，不需要再数调用次数。
    func testMissingTokenThrowsMissingCredentialsWithoutSendingRequest() async {
        for token in [nil, ""] as [String?] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AuthLifecycleURLProtocol.self]
            AuthLifecycleURLProtocol.handler = nil
            let client = URLSessionAPIClient(
                baseURL: URL(string: "http://example.test")!,
                session: URLSession(configuration: configuration),
                tokenProvider: { token }
            )

            do {
                let _: EmptyResponse = try await client.get("/api/volunteer/profile")
                XCTFail("token=\(String(describing: token)) 时不该发出请求")
            } catch APIError.missingCredentials {
                // 期望路径
            } catch {
                XCTFail("token=\(String(describing: token)) 期望 .missingCredentials，实际拿到 \(error)")
            }
        }
    }

    /// 反向门：有 Token 时照常带头。
    /// 没有这条，上面那道 `guard` 写成「永远拦」也是绿的，而那样全 App 都发不出鉴权请求。
    func testPresentTokenIsStillSentAsBearerHeader() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthLifecycleURLProtocol.self]
        AuthLifecycleURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer real-token")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }
        let client = URLSessionAPIClient(
            baseURL: URL(string: "http://example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { "real-token" }
        )

        let _: EmptyResponse = try await client.get("/api/volunteer/profile")
        AuthLifecycleURLProtocol.handler = nil
    }

    func testNetworkDiagnosticsSanitizeIdentifiersAndSecrets() async throws {
        await NetworkDiagnosticRecorder.shared.resetForTesting()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthLifecycleURLProtocol.self]
        AuthLifecycleURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }
        let secret = "secret-jwt-13800138000"
        let client = URLSessionAPIClient(
            baseURL: URL(string: "http://example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { secret }
        )

        let _: EmptyResponse = try await client.get("/api/orders/123/track")
        let events = await NetworkDiagnosticRecorder.shared.snapshot()
        let event = try XCTUnwrap(events.last)

        XCTAssertEqual(event.endpointCategory, "/api/orders/{id}/track")
        XCTAssertEqual(event.statusCode, 200)
        XCTAssertFalse(String(describing: event).contains(secret))
        XCTAssertFalse(String(describing: event).contains("13800138000"))
        AuthLifecycleURLProtocol.handler = nil
    }

    func testRegistrationRateLimitDisablesSubmitForAuthoritativeCountdown() async {
        let client = AuthLifecycleAPIClient(registrationRateLimitSeconds: 2)
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.name = "测试志愿者"
        viewModel.phone = "13800138000"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.registrationRetryAfterSeconds, 2)
        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        let expired = expectation(description: "authoritative registration cooldown expires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { expired.fulfill() }
        await fulfillment(of: [expired], timeout: 3)
        XCTAssertNil(viewModel.registrationRetryAfterSeconds)
        XCTAssertTrue(viewModel.canSubmitBasicInfo)
    }

    func testAuthenticatedUnauthorizedErrorExpiresSession() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .blind

        let didExpire = appState.handleAuthenticatedAPIError(.unauthorized)

        XCTAssertTrue(didExpire)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testAuthenticatedNonUnauthorizedErrorDoesNotExpireSession() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "valid-token"
        appState.userId = 12
        appState.activeRole = .blind

        let didExpire = appState.handleAuthenticatedAPIError(.networkError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))

        XCTAssertFalse(didExpire)
        XCTAssertEqual(appState.accessToken, "valid-token")
        XCTAssertEqual(appState.userId, 12)
        XCTAssertEqual(appState.activeRole, .blind)
        XCTAssertNil(appState.consumeSessionExpirationMessage())
    }

    func testRoleSelectionUnauthorizedExpiresSessionAndReturnsToLogin() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        let viewModel = RoleSelectionViewModel(apiClient: FailingAPIClient(error: APIError.unauthorized))
        viewModel.configure(with: appState, speechService: SpeechService())

        viewModel.selectRole(.volunteer)

        let didExpire = await waitUntil {
            appState.accessToken == nil &&
            appState.activeRole == nil &&
            appState.userId == nil &&
            !viewModel.isLoading
        }

        XCTAssertTrue(didExpire)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showBlockedAlert)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    /// 🚨 **`lastSpokenText` 那条断言是这条用例的重点，不是顺手加的。**
    ///
    /// 会话过期时整个 App 被换成登录页，而下单 / 接单 / 语音确认三个调用点在
    /// `handleAuthenticatedAPIError` 返回 true 之后都只是 `return nil`。
    /// 光有 `errorMessage` 只修好了看得见屏幕的那一半 —— 对盲人，
    /// 一次真实的会话过期与「点了没反应」完全无从分辨。
    func testLoginViewModelShowsAndSpeaksAndConsumesSessionExpirationMessage() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.expireSession()
        let speechService = SpeechService()
        let viewModel = LoginViewModel()

        viewModel.configure(with: appState, speechService: speechService)

        XCTAssertEqual(viewModel.errorMessage, "登录已过期，请重新登录。")
        XCTAssertEqual(speechService.lastSpokenText, "登录已过期，请重新登录。")
        XCTAssertNil(appState.consumeSessionExpirationMessage())

        viewModel.sanitizePhoneInput("138")

        XCTAssertNil(viewModel.errorMessage)
    }

    /// 第二次 `onAppear` 不能再播一遍 —— 消息已经被 consume 掉了。
    /// 这条守的是「加一句播报」不许顺带引入重复播报：读屏用户听同一句话两遍
    /// 会以为发生了两次会话过期。
    ///
    /// ⚠️ 第二次用**另一个** `SpeechService` 实例来验，不是 `stop()` 之后复用同一个 ——
    /// `stop()` 只停合成器，`lastSpokenText` 是不清的（`SpeechService.swift:150-154`），
    /// 复用会让这条断言恒假地通过（读到的是第一次那句）。
    func testSessionExpirationIsSpokenOnceEvenIfConfigureRunsAgain() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.expireSession()
        let firstAppearance = SpeechService()
        let viewModel = LoginViewModel()

        viewModel.configure(with: appState, speechService: firstAppearance)
        XCTAssertEqual(firstAppearance.lastSpokenText, "登录已过期，请重新登录。")

        // 先把 `errorMessage` 清掉（用户开始输手机号就会清），否则第二次 configure
        // 会被 `errorMessage == nil` 那道 guard 挡在 consume 之前，
        // 这条用例就变成在验 guard 而不是在验 consume。
        viewModel.sanitizePhoneInput("138")
        XCTAssertNil(viewModel.errorMessage)

        let secondAppearance = SpeechService()
        viewModel.configure(with: appState, speechService: secondAppearance)

        XCTAssertNil(
            secondAppearance.lastSpokenText,
            "第二次 configure 又播了一遍 —— sessionExpirationMessage 应该已经被 consume 掉"
        )
    }
}

private final class AuthLifecycleURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override nonisolated func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override nonisolated func stopLoading() {}
}
