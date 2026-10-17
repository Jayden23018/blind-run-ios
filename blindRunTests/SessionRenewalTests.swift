import XCTest
@testable import blindRun

/// #391：refresh token 续期（OpenSpec `renew-session-with-refresh-token`，契约 blind-run-backend#669）。
///
/// 三层各验各的：
/// - 续期器：覆盖两个 token、失效不重试、暂时故障保留会话并冷却、并发只续一次、登出期间的迟到结果不复活。
/// - `URLSessionAPIClient`：401 → 续期 → 用新 access **只**重试一次；续不了时抛的不是 `.unauthorized`。
/// - `AppState`：续期换 token 不重置会话、登录存 / 登出删 refresh。登出的重试与「无论成败都清」在
///   `AuthServiceTests.testLogoutServerFailureIsRetriedOnceThenSignsOut` 与 `testLogoutNetworkFailureStillSignsOutLocally`。
@MainActor
final class SessionRenewalTests: XCTestCase {

    override func tearDown() {
        RenewalStubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - 续期器

    func testRenewalOverwritesBothTokens() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh", expiresIn: 7200))

        let outcome = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")

        XCTAssertEqual(outcome.renewedToken, "new-access")
        XCTAssertEqual(harness.accessStore.read(), "new-access")
        XCTAssertEqual(harness.credential?.refreshToken, "new-refresh", "refresh token 必须一起覆盖")
        XCTAssertEqual(harness.credential?.expiresIn, 7200)
        XCTAssertEqual(harness.sentRefreshTokens, ["old-refresh"], "发出去的是旧 refresh，且只发一次")
        XCTAssertEqual(harness.renewedNotifications, ["new-access"], "持有内存副本的一方要被通知")
    }

    func testRejectedRefreshClearsItAndIsNeverRetried() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .failure(APIError.unauthorized)

        let first = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")
        let second = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")

        XCTAssertTrue(first.isInvalid)
        XCTAssertTrue(second.isInvalid)
        XCTAssertNil(harness.credential, "REFRESH_TOKEN_INVALID 之后本地 refresh 要删掉")
        XCTAssertEqual(harness.sentRefreshTokens.count, 1, "结果不会变，别重试")
        XCTAssertEqual(harness.accessStore.read(), "old-access", "续期器不碰 access：清会话是调用方（暂缓 / 登出）的事")
    }

    func testServerOutageKeepsTheSessionAndCoolsDown() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .failure(APIError.unknown(statusCode: 503))

        let first = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")
        harness.clock += 5
        let duringCooldown = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")

        XCTAssertTrue(first.isUnavailable)
        XCTAssertTrue(duringCooldown.isUnavailable)
        XCTAssertEqual(harness.sentRefreshTokens.count, 1, "冷却期内的轮询不再发续期，否则自己把续期打成 429")
        XCTAssertEqual(harness.credential?.refreshToken, "old-refresh", "5xx 不是登录失效，refresh 要留着")
        XCTAssertEqual(harness.accessStore.read(), "old-access")

        harness.clock += SessionTokenRefresher.unavailableCooldown
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh"))
        let afterCooldown = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")

        XCTAssertEqual(afterCooldown.renewedToken, "new-access", "冷却过后要再试")
        XCTAssertEqual(harness.sentRefreshTokens.count, 2)
    }

    func testConcurrentUnauthorizedRequestsRenewOnce() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh"))
        harness.exchangeDelayNanoseconds = 50_000_000
        let refresher: SessionTokenRefresher = harness.refresher

        async let a = refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")
        async let b = refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")
        async let c = refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")
        let outcomes = await [a, b, c]

        XCTAssertEqual(harness.sentRefreshTokens.count, 1, "三个 401 只发一次续期")
        XCTAssertEqual(outcomes.map { $0.renewedToken }, ["new-access", "new-access", "new-access"])
    }

    func testAccessAlreadyRenewedElsewhereIsReusedWithoutAnotherRenewal() async {
        let harness = RefresherHarness(access: "fresh-access", refresh: "fresh-refresh")

        let outcome = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "stale-access")

        XCTAssertEqual(outcome.renewedToken, "fresh-access")
        XCTAssertTrue(harness.sentRefreshTokens.isEmpty, "Keychain 里已经是别人换好的新 token，不再续")
    }

    /// 续期在路上时用户登出：迟到的结果不能把凭据写回 Keychain。
    func testSignOutDuringRenewalDiscardsTheLateResult() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh"))
        harness.exchangeDelayNanoseconds = 50_000_000
        let refresher: SessionTokenRefresher = harness.refresher

        async let outcome = refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")
        try? await Task.sleep(nanoseconds: 10_000_000)
        refresher.clearCredential()
        harness.accessStore.delete()
        let result = await outcome

        XCTAssertTrue(result.isSessionChanged, "那一次登录已经结束，结果作废")
        XCTAssertNil(harness.accessStore.read(), "登出后不许复活 access")
        XCTAssertNil(harness.credential, "登出后不许复活 refresh")
        XCTAssertTrue(harness.renewedNotifications.isEmpty)
    }

    /// code review A：A 登出、B 登录后，A 的迟到 401 不许拿 B 的 token 重发（身份串用），也不许按 401 把 B 踢掉。
    func testUnauthorizedFromAPreviousLoginIsNotReplayedWithTheNewSessionsToken() async {
        let harness = RefresherHarness(access: "access-A", refresh: "refresh-A")
        let epochOfRequestA = harness.refresher.sessionEpoch
        harness.refresher.storeCredential(from: Self.renewal(access: "access-B", refresh: "refresh-B"))
        harness.accessStore.save("access-B")

        let outcome = await harness.refresher.renewAfterUnauthorized(
            rejectedAccessToken: "access-A",
            requestEpoch: epochOfRequestA
        )

        XCTAssertTrue(outcome.isSessionChanged)
        XCTAssertTrue(harness.sentRefreshTokens.isEmpty)
        XCTAssertTrue(harness.renewedNotifications.isEmpty)
    }

    /// code review A：上一次登录在途的续期，新会话的 401 不许去等它（它可能回 `.invalid` 把新会话踢掉）。
    func testNewLoginDoesNotWaitForThePreviousLoginsRenewal() async {
        let harness = RefresherHarness(access: "access-A", refresh: "refresh-A")
        harness.exchangeResult = .success(Self.renewal(access: "access-A2", refresh: "refresh-A2"))
        harness.exchangeDelayNanoseconds = 50_000_000
        let refresher: SessionTokenRefresher = harness.refresher

        async let old = refresher.renewAfterUnauthorized(rejectedAccessToken: "access-A", requestEpoch: refresher.sessionEpoch)
        try? await Task.sleep(nanoseconds: 10_000_000)
        refresher.storeCredential(from: Self.renewal(access: "access-B", refresh: "refresh-B"))
        harness.accessStore.save("access-B")
        harness.exchangeResult = .success(Self.renewal(access: "access-B2", refresh: "refresh-B2"))
        let fresh = await refresher.renewAfterUnauthorized(rejectedAccessToken: "access-B", requestEpoch: refresher.sessionEpoch)
        let stale = await old

        XCTAssertEqual(harness.sentRefreshTokens, ["refresh-A", "refresh-B"], "新会话自己续一次，不等旧的")
        XCTAssertEqual(fresh.renewedToken, "access-B2")
        XCTAssertTrue(stale.isSessionChanged)
        XCTAssertEqual(harness.credential?.refreshToken, "refresh-B2", "旧会话的迟到结果不许覆盖新会话的凭据")
    }

    func testNonPositiveExpiresInDoesNotMakeRenewalPermanentlyDue() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh", expiresIn: 3600)
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh", expiresIn: 0))

        _ = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")

        XCTAssertEqual(harness.credential?.refreshToken, "new-refresh")
        XCTAssertEqual(harness.credential?.expiresIn, 3600, "0 秒不收，否则之后每条请求都触发续期")
    }

    func testProactiveRenewalWaitsForHalfOfTheLifetime() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh", expiresIn: 100)
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh"))

        harness.clock += 49
        let early = await harness.refresher.renewIfDue()
        XCTAssertNil(early)
        XCTAssertTrue(harness.sentRefreshTokens.isEmpty, "不到一半不续")

        harness.clock += 2
        let due = await harness.refresher.renewIfDue()
        XCTAssertEqual(due?.renewedToken, "new-access")
        XCTAssertEqual(harness.sentRefreshTokens, ["old-refresh"])
    }

    /// 主动续期得到「失效」只删 refresh、不清 access：契约说最后续出的 access 还能用到它自己过期。
    func testProactiveRejectionLeavesTheStillValidAccessInPlace() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh", expiresIn: 100)
        harness.exchangeResult = .failure(APIError.unauthorized)
        harness.clock += 60

        await harness.refresher.renewIfDue()

        XCTAssertNil(harness.credential)
        XCTAssertEqual(harness.accessStore.read(), "old-access")
    }

    func testOnlyRejectionAndBadRequestMeanTheSessionEnded() {
        XCTAssertTrue(SessionTokenRefresher.meansSessionEnded(.unauthorized))
        XCTAssertTrue(SessionTokenRefresher.meansSessionEnded(.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "x"))))
        XCTAssertTrue(SessionTokenRefresher.meansSessionEnded(.unknown(statusCode: 400)))
        XCTAssertTrue(SessionTokenRefresher.meansSessionEnded(.serverError(ErrorResponse(code: "BAD_REQUEST", message: "x"))))
        XCTAssertTrue(SessionTokenRefresher.meansSessionEnded(.serverError(ErrorResponse(code: "HTTP_400", message: "x"))))

        XCTAssertFalse(SessionTokenRefresher.meansSessionEnded(.unknown(statusCode: 503)))
        XCTAssertFalse(SessionTokenRefresher.meansSessionEnded(.serverError(ErrorResponse(code: "INTERNAL_ERROR", message: "x"))))
        XCTAssertFalse(SessionTokenRefresher.meansSessionEnded(.rateLimited(RateLimitInfo(message: "x", retryAfterSeconds: 30))))
        XCTAssertFalse(SessionTokenRefresher.meansSessionEnded(.networkError(URLError(.timedOut))))
        XCTAssertFalse(SessionTokenRefresher.meansSessionEnded(.decodingError(URLError(.cannotParseResponse))))
    }

    func testRateLimitedRenewalWaitsForRetryAfter() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .failure(APIError.rateLimited(RateLimitInfo(message: "慢点", retryAfterSeconds: 40)))

        _ = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")
        harness.clock += 20
        _ = await harness.refresher.renewAfterUnauthorized(rejectedAccessToken: "old-access")

        XCTAssertEqual(harness.sentRefreshTokens.count, 1, "Retry-After 40 秒内不再发")
    }

    // MARK: - URLSessionAPIClient

    func testUnauthorizedRequestRenewsAndRetriesOnceWithTheNewToken() async throws {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh"))
        RenewalStubURLProtocol.responder = { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access"
                ? (200, #"{"success":true,"data":{"success":true}}"#)
                : (401, "")
        }
        let client = Self.client(harness: harness)

        let response: ApiSuccessResponse = try await client.get("/api/orders/42")

        XCTAssertEqual(response.success, true)
        XCTAssertEqual(
            RenewalStubURLProtocol.authorizationHeaders,
            ["Bearer old-access", "Bearer new-access"],
            "先用旧的被拒，续期后用新的重试一次"
        )
        XCTAssertEqual(harness.sentRefreshTokens, ["old-refresh"])
        XCTAssertFalse(
            RenewalStubURLProtocol.recordedURLs.contains { $0.contains("refresh") },
            "refresh token 不进任何 URL"
        )
    }

    func testSecondUnauthorizedAfterRenewalIsNotRetriedAgain() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh"))
        RenewalStubURLProtocol.responder = { _ in (401, "") }
        let client = Self.client(harness: harness)

        do {
            let _: ApiSuccessResponse = try await client.get("/api/orders/42")
            XCTFail("续期后还是 401 应当抛出")
        } catch APIError.unauthorized {
        } catch {
            XCTFail("应当是 .unauthorized，实际 \(error)")
        }
        XCTAssertEqual(RenewalStubURLProtocol.authorizationHeaders.count, 2, "只重试一次")
        XCTAssertEqual(harness.sentRefreshTokens.count, 1, "不续第二次")
    }

    /// 续期端点 503 时，原请求抛的**不能**是 `.unauthorized` —— 那会让调用方在跑道上把人踢回登录页。
    func testRenewalOutageSurfacesTheTransientErrorInsteadOfUnauthorized() async {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .failure(APIError.unknown(statusCode: 503))
        RenewalStubURLProtocol.responder = { _ in (401, "") }
        let client = Self.client(harness: harness)

        do {
            let _: ApiSuccessResponse = try await client.get("/api/orders/42")
            XCTFail("应当抛出")
        } catch APIError.unknown(let statusCode) {
            XCTAssertEqual(statusCode, 503)
        } catch {
            XCTFail("应当抛续期那条 503，实际 \(error)")
        }
        XCTAssertEqual(RenewalStubURLProtocol.authorizationHeaders.count, 1, "没续上就不重试")
    }

    func testUploadAlsoRenewsOnUnauthorized() async throws {
        let harness = RefresherHarness(access: "old-access", refresh: "old-refresh")
        harness.exchangeResult = .success(Self.renewal(access: "new-access", refresh: "new-refresh"))
        RenewalStubURLProtocol.responder = { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access"
                ? (200, #"{"success":true,"data":{"success":true}}"#)
                : (401, "")
        }
        let client = Self.client(harness: harness)

        let _: ApiSuccessResponse = try await client.upload(
            "/api/volunteer/certificates",
            files: [MultipartFile(fieldName: "file", fileName: "a.jpg", mimeType: "image/jpeg", data: Data([1]))]
        )

        XCTAssertEqual(RenewalStubURLProtocol.authorizationHeaders, ["Bearer old-access", "Bearer new-access"])
    }

    func testRefreshEndpointIsUnauthenticatedAndCarriesTheTokenInTheBody() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = Self.renewal(access: "a", refresh: "r")

        _ = try await AuthService(transport: transport).refreshSession(refreshToken: "r-old")

        XCTAssertEqual(transport.requests.first?.path, "/api/auth/refresh")
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requests.first?.requiresAuth, false, "access 过期时正要调它，不能要求登录")
        XCTAssertEqual((transport.requests.first?.body as? RefreshTokenRequest)?.refreshToken, "r-old")
    }

    func testLoginResponseDecodesRefreshFieldsAndToleratesTheirAbsence() throws {
        let full = try JSONDecoder().decode(
            LoginResponse.self,
            from: Data(#"{"token":"a","userId":7,"role":"BLIND","refreshToken":"r","expiresIn":7200}"#.utf8)
        )
        XCTAssertEqual(full.refreshToken, "r")
        XCTAssertEqual(full.expiresIn, 7200)

        let legacy = try JSONDecoder().decode(LoginResponse.self, from: Data(#"{"token":"a","userId":7,"role":"BLIND"}"#.utf8))
        XCTAssertNil(legacy.refreshToken, "缺键只是不续期，不是整条登录解码失败")
    }

    // MARK: - AppState

    func testLoginStoresTheRefreshCredentialAndSignOutClearsIt() {
        let refreshStore = InMemoryTokenStore()
        let appState = makeAppState(refreshStore: refreshStore)

        appState.handleLoginSuccess(response: Self.renewal(access: "access-9f3c", refresh: "refresh-71ab", expiresIn: 7200))
        XCTAssertEqual(RefreshCredentialStore(storage: refreshStore).read()?.refreshToken, "refresh-71ab")
        XCTAssertFalse(refreshStore.read()?.contains("access-9f3c") ?? true, "access 不和 refresh 存在同一条里")

        appState.clearSession()
        XCTAssertNil(refreshStore.read(), "登出要连 refresh 一起删")
    }

    /// 🔴 换 token 的 `didSet` 会断实时通道、重置陪跑会话与求助协调器 —— 续期绝不能走那条路。
    func testRenewedAccessTokenDoesNotResetTheRunningSession() {
        let tokenStore = InMemoryTokenStore()
        let appState = makeAppState(tokenStore: tokenStore)
        appState.handleLoginSuccess(response: Self.renewal(access: "old-access", refresh: "r"))
        appState.liveEscortCoordinator.updateOwnedOrder(orderID: 42, status: .inProgress)
        let generation = appState.sessionGeneration

        appState.applyRenewedAccessToken("new-access")

        XCTAssertEqual(appState.accessToken, "new-access")
        XCTAssertEqual(tokenStore.read(), "new-access", "新 token 要落 Keychain，锁屏卡读的是那里")
        XCTAssertEqual(appState.sessionGeneration, generation, "会话代号不变 = 根路由不重跑、资料加载不作废")
        XCTAssertEqual(appState.liveEscortCoordinator.activeOrderID, 42, "陪跑会话不能被重置")
        XCTAssertEqual(appState.liveEscortCoordinator.activeStatus, .inProgress)

        appState.handleLoginSuccess(response: Self.renewal(access: "other-login", refresh: "r2"))
        XCTAssertNotEqual(appState.sessionGeneration, generation, "真换了一次登录，代号要变")
    }

    func testLateRenewalAfterSignOutDoesNotRevive() {
        let appState = makeAppState()
        appState.handleLoginSuccess(response: Self.renewal(access: "a", refresh: "r"))
        appState.clearSession()

        appState.applyRenewedAccessToken("late")

        XCTAssertNil(appState.accessToken)
    }

    func testWebSocketReconnectUsesTheRenewedToken() {
        let service = WebSocketService()
        service.connect(baseURL: URL(string: "https://127.0.0.1:9")!, token: "old-access", role: .blind)
        defer { service.disconnect() }

        service.updateAccessTokenForReconnect("new-access")

        XCTAssertEqual(service.accessTokenForTesting, "new-access")
    }

    // MARK: - 陪跑员跑步中求助面板（#437）

    func testHelpPanelCloudRowsSayLoginExpiredInsteadOfAskingForARetry() {
        let expired = VolunteerRunHelpPanel.supportRowSubtitle(state: .failed, isSessionExpired: true)
        XCTAssertEqual(expired, VolunteerRunCopy.cloudRowSessionExpiredSubtitle)
        XCTAssertFalse(expired.contains("重试"), "登录过期时不能叫人重试一个必然 401 的请求")
        XCTAssertEqual(
            VolunteerRunHelpPanel.cloudRowSubtitle(normal: VolunteerRunCopy.pauseRowSubtitle, isSessionExpired: true),
            VolunteerRunCopy.cloudRowSessionExpiredSubtitle
        )

        XCTAssertEqual(VolunteerRunHelpPanel.supportRowSubtitle(state: .failed, isSessionExpired: false), VolunteerRunCopy.supportFailed)
        XCTAssertEqual(VolunteerRunHelpPanel.supportRowSubtitle(state: .idle, isSessionExpired: false), VolunteerRunCopy.supportRowSubtitle)
        XCTAssertEqual(
            VolunteerRunHelpPanel.supportRowSubtitle(state: .submitted, isSessionExpired: true),
            VolunteerRunCopy.supportSubmitted,
            "已经提交成功的就照实说"
        )
    }

    // MARK: - Helpers

    static func renewal(access: String, refresh: String, expiresIn: Int64 = 3600) -> LoginResponse {
        LoginResponse(token: access, userId: 7, role: "BLIND", refreshToken: refresh, expiresIn: expiresIn)
    }

    static func client(harness: RefresherHarness) -> URLSessionAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RenewalStubURLProtocol.self]
        let accessStore = harness.accessStore
        return URLSessionAPIClient(
            baseURL: URL(string: "https://renewal.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { accessStore.read() },
            sessionRenewer: harness.refresher
        )
    }

    func makeAppState(
        tokenStore: InMemoryTokenStore? = nil,
        refreshStore: InMemoryTokenStore? = nil
    ) -> AppState {
        let tokenStore = tokenStore ?? InMemoryTokenStore()
        let refreshStore = refreshStore ?? InMemoryTokenStore()
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        addTeardownBlock { persistence.reset() }
        return AppState(persistence: persistence, tokenStore: tokenStore, refreshTokenStore: refreshStore)
    }
}

// MARK: - 续期器桩

@MainActor
final class RefresherHarness {
    let accessStore: InMemoryTokenStore
    let credentialStorage: InMemoryTokenStore
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var exchangeResult: Result<LoginResponse, Error> = .failure(URLError(.badServerResponse))
    var exchangeDelayNanoseconds: UInt64 = 0
    private(set) var sentRefreshTokens: [String] = []
    private(set) var renewedNotifications: [String] = []
    private(set) var refresher: SessionTokenRefresher!

    init(access: String, refresh: String, expiresIn: TimeInterval = 3600) {
        accessStore = InMemoryTokenStore(token: access)
        credentialStorage = InMemoryTokenStore()
        let store = RefreshCredentialStore(storage: credentialStorage)
        store.save(RefreshCredential(refreshToken: refresh, issuedAt: clock, expiresIn: expiresIn))
        refresher = SessionTokenRefresher(accessStore: accessStore, credentialStore: store, now: { [unowned self] in self.clock })
        refresher.exchange = { [unowned self] refreshToken in
            self.sentRefreshTokens.append(refreshToken)
            if self.exchangeDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.exchangeDelayNanoseconds)
            }
            return try self.exchangeResult.get()
        }
        refresher.onAccessTokenRenewed = { [unowned self] token in
            self.renewedNotifications.append(token)
        }
    }

    var credential: RefreshCredential? { RefreshCredentialStore(storage: credentialStorage).read() }
}

extension SessionRenewalOutcome {
    var renewedToken: String? {
        if case .renewed(let token) = self { return token }
        return nil
    }

    var isInvalid: Bool {
        if case .invalid = self { return true }
        return false
    }

    var isSessionChanged: Bool {
        if case .sessionChanged = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

// MARK: - HTTP 桩

private final class RenewalStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responder: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) private static var _requests: [URLRequest] = []

    nonisolated static var responder: ((URLRequest) -> (Int, String))? {
        get { lock.withLock { _responder } }
        set { lock.withLock { _responder = newValue } }
    }

    nonisolated static var authorizationHeaders: [String] {
        lock.withLock { _requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") } }
    }

    nonisolated static var recordedURLs: [String] {
        lock.withLock { _requests.compactMap { $0.url?.absoluteString } }
    }

    nonisolated static func reset() {
        lock.withLock {
            _responder = nil
            _requests = []
        }
    }

    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override nonisolated func startLoading() {
        let request = self.request
        Self.lock.withLock { Self._requests.append(request) }
        guard let responder = Self.responder, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = responder(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override nonisolated func stopLoading() {}
}
