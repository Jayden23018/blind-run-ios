import XCTest
@testable import blindRun

/// 启动恢复失败页的「重试恢复」（#573）。
///
/// 修之前按钮只调 `synchronize`：会话校验失败（断网）时它按现有状态重选页面、不发请求，
/// 网络恢复后点了也原样不动。下面两条用 `/api/auth/me` 的调用次数区分两种实现 ——
/// 旧实现重试后次数仍是 1、状态仍是 `.validationFailed`。
@MainActor
final class RecoveryRetryTests: XCTestCase {

    func testRetryAfterSessionValidationFailureValidatesAgainAndSucceeds() async {
        let (appState, client, persistence) = Self.makeStoredSession(failingMeCalls: 1)
        defer { persistence.reset() }
        let router = ContentRootRouter()
        await appState.restoreSession()
        router.synchronize(with: appState)
        guard case .recoveryFailed = router.route else { return XCTFail("前提：先落到恢复失败页，实际 \(router.route)") }

        await router.retryRecovery(with: appState)

        XCTAssertEqual(client.meCalls, 2, "重试要重新校验会话")
        XCTAssertEqual(appState.sessionRestorationState, .authenticated)
        XCTAssertEqual(router.failedRecoveryRetries, 0, "成功了不该触发失败重念")
    }

    /// 又失败时：仍在恢复失败页，且重试次数加一 —— 失败页靠它把原因再念一遍，不能静默。
    func testRetryThatFailsAgainStaysOnTheFailurePageAndBumpsTheAnnouncement() async {
        let (appState, client, persistence) = Self.makeStoredSession(failingMeCalls: 2)
        defer { persistence.reset() }
        let router = ContentRootRouter()
        await appState.restoreSession()

        await router.retryRecovery(with: appState)
        router.synchronize(with: appState)

        XCTAssertEqual(client.meCalls, 2)
        guard case .validationFailed = appState.sessionRestorationState else {
            return XCTFail("应仍是校验失败，实际 \(appState.sessionRestorationState)")
        }
        guard case .recoveryFailed = router.route else { return XCTFail("应仍在恢复失败页，实际 \(router.route)") }
        XCTAssertEqual(router.failedRecoveryRetries, 1)
    }

    // MARK: - 场景

    private static func makeStoredSession(
        failingMeCalls: Int
    ) -> (AppState, FlakyMeAPIClient, UserDefaultsAppStatePersistence) {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        persistence.set("stored-token", forKey: AppConstants.UserDefaultsKeys.accessToken)
        persistence.set(Int64(77), forKey: AppConstants.UserDefaultsKeys.userId)
        persistence.set(UserRole.blind.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole)
        let client = FlakyMeAPIClient(failingMeCalls: failingMeCalls)
        return (AppState(apiClient: client, persistence: persistence), client, persistence)
    }

    /// `/api/auth/me` 前 N 次断网、之后成功；其余端点一律失败（会话恢复成功后的副作用请求不影响断言）。
    final class FlakyMeAPIClient: APIClientProtocol, @unchecked Sendable {
        private let failingMeCalls: Int
        private(set) var meCalls = 0

        init(failingMeCalls: Int) { self.failingMeCalls = failingMeCalls }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .get, path == "/api/auth/me" else { throw APIError.invalidURL }
            meCalls += 1
            if meCalls <= failingMeCalls { throw APIError.networkError(URLError(.notConnectedToInternet)) }
            guard let response = CurrentUserResponse(userId: 77, phone: nil, role: "BLIND") as? T else {
                throw APIError.invalidURL
            }
            return response
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }
}
