import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class AuthSessionLifecycleTests: XCTestCase, BlindRunTestSupport {
    // `testMaintainedDocsDoNotUseForbiddenLowercaseOrderStatusVocabulary` 已删除：
    // 它读仓库里的 .md 文件，真机测试包沙盒读不到必然 XCTSkip，而真机是本仓唯一可用的
    // XCTest 通道，所以它一次都没跑过；同一份 forbiddenFragments 清单在
    // `scripts/validate-docs.mjs` 里有可运行的等价实现（AGENTS.md §13 的必跑命令），
    // 且那份的文档清单更新（不含 2026-07-28 已归档的 07-api-contract / websocket-protocol）。

    func testLoginResponseDecodesCorrectly() throws {
        let json = """
        {
          "token": "eyJhbGciOiJIUzI1NiJ9.test",
          "userId": 1,
          "role": "BLIND"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)

        XCTAssertEqual(response.token, "eyJhbGciOiJIUzI1NiJ9.test")
        XCTAssertEqual(response.userId, 1)
        XCTAssertEqual(response.role, "BLIND")
    }

    func testLoginRoleResolverTreatsUnsetAndMissingRoleAsRoleSelection() {
        XCTAssertNil(AppState.resolvedLoginRole(from: nil))
        XCTAssertNil(AppState.resolvedLoginRole(from: "UNSET"))
        XCTAssertNil(AppState.resolvedLoginRole(from: "UNKNOWN"))
        XCTAssertEqual(AppState.resolvedLoginRole(from: "BLIND"), .blind)
        XCTAssertEqual(AppState.resolvedLoginRole(from: "VOLUNTEER"), .volunteer)
    }

    func testLoginSuccessClearsStaleRoleWhenBackendReturnsNoRole() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.activeRole = .volunteer

        appState.handleLoginSuccess(
            response: LoginResponse(
                token: "token",
                userId: 12,
                role: nil
            )
        )

        XCTAssertEqual(appState.accessToken, "token")
        XCTAssertEqual(appState.userId, 12)
        XCTAssertNil(appState.activeRole)
    }

    func testLoginSuccessClearsUnsetRoleToAvoidBlankRootRoute() {
        let appState = AppState()
        appState.currentEnvironment = .mock

        appState.handleLoginSuccess(
            response: LoginResponse(
                token: "token",
                userId: 12,
                role: "UNSET"
            )
        )

        XCTAssertNil(appState.activeRole)
    }

    func testContentRootRouterCommitsOneBlindDestinationAfterAtomicHydration() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let client = RootHydrationAPIClient()
        let appState = AppState(apiClient: client, persistence: persistence)
        appState.currentEnvironment = .mock
        appState.handleLoginSuccess(response: LoginResponse(token: "token-1", userId: 1, role: "BLIND"))
        let router = ContentRootRouter()

        router.synchronize(with: appState)

        XCTAssertEqual(router.route, .restoringAccount)
        let didRoute = await waitUntil { router.route == .blindHome }
        XCTAssertTrue(didRoute)
        XCTAssertEqual(appState.blindProfile?.name, "账号1")
        XCTAssertEqual(appState.emergencyContacts.count, 1)
    }

    func testContentRootRouterCancelsOldAccountHydrationBeforeCommit() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let client = RootHydrationAPIClient(firstRequestDelay: 1)
        let appState = AppState(apiClient: client, persistence: persistence)
        appState.currentEnvironment = .mock
        let router = ContentRootRouter()

        appState.handleLoginSuccess(response: LoginResponse(token: "old-token", userId: 1, role: "BLIND"))
        router.synchronize(with: appState)
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.handleLoginSuccess(response: LoginResponse(token: "new-token", userId: 2, role: "BLIND"))
        router.synchronize(with: appState)

        let didRoute = await waitUntil { router.route == .blindHome }
        XCTAssertTrue(didRoute)
        XCTAssertEqual(appState.userId, 2)
        XCTAssertEqual(appState.blindProfile?.name, "账号2")
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
    }

    func testExpireSessionClearsStateAndProvidesOneTimeLoginMessage() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .volunteer
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())

        appState.expireSession()

        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertNil(appState.volunteerProfile)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
        XCTAssertNil(appState.consumeSessionExpirationMessage())
    }

    func testSessionRestoreHydratesSelectedRole() async {
        let persistence = prepareStoredSession(token: "selected-token", role: .blind, userId: 99)
        let client = AuthLifecycleAPIClient(meResult: .success(CurrentUserResponse(userId: 99, phone: nil, role: "BLIND")))
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .authenticated)
        XCTAssertEqual(appState.currentUser?.userId, 99)
        XCTAssertEqual(appState.activeRole, .blind)
        persistence.reset()
    }

    func testSessionRestoreKeepsRolelessSessionWithoutWebSocket() async {
        let persistence = prepareStoredSession(token: "roleless-token", role: nil, userId: 100)
        let client = AuthLifecycleAPIClient(meResult: .success(CurrentUserResponse(userId: 100, phone: nil, role: "UNSET")))
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .choosingRole)
        XCTAssertEqual(appState.userId, 100)
        XCTAssertNil(appState.activeRole)
        XCTAssertNil(appState.webSocketService)
        persistence.reset()
    }

    func testSessionRestoreRejectsMalformedRole() async {
        let persistence = prepareStoredSession(token: "malformed-role-token", role: .blind, userId: 102)
        let client = AuthLifecycleAPIClient(
            meResult: .success(CurrentUserResponse(userId: 102, phone: nil, role: "ADMIN"))
        )
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.currentUser)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录角色信息异常，请重新登录。")
        persistence.reset()
    }

    func testRevokedSessionRestoreClearsCredentialsAndMetadata() async {
        let persistence = prepareStoredSession(token: "revoked-token", role: .volunteer, userId: 101)
        persistence.set("event-101", forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata)
        let client = AuthLifecycleAPIClient(meResult: .failure(.unauthorized))
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(persistence.object(forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata))
        persistence.reset()
    }

    func testLogoutSuccessAndUnauthorizedBothCleanSession() async {
        for result in [
            Result<LogoutResponse, APIError>.success(LogoutResponse(success: true, message: nil)),
            .failure(.unauthorized)
        ] {
            let persistence = AppStatePersistenceFactory.makeIsolatedTest()
            defer { persistence.reset() }
            let client = AuthLifecycleAPIClient(logoutResult: result)
            let appState = AppState(apiClient: client, persistence: persistence)
            appState.handleLoginSuccess(response: LoginResponse(token: "token", userId: 7, role: "BLIND"))
            await appState.logout()
            XCTAssertFalse(appState.isLoggedIn)
            XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
        }
    }

    /// #391 起：服务端登出没成也照样清本地会话（契约 blind-run-backend#669「用户的意图是退出」）。
    /// 此前这里保留会话、等用户确认「仅退出本机」。断网不重试（`AppState.logoutIsWorthRetrying`）。
    func testLogoutNetworkFailureStillSignsOutLocally() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let client = AuthLifecycleAPIClient(logoutResult: .failure(.networkError(URLError(.notConnectedToInternet))))
        let appState = AppState(apiClient: client, persistence: persistence)
        appState.handleLoginSuccess(response: LoginResponse(token: "token", userId: 8, role: "VOLUNTEER"))

        await appState.logout()

        XCTAssertFalse(appState.isLoggedIn)
        XCTAssertEqual(appState.logoutState, .idle)
        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
    }

    func testLocalCleanupIsIdempotentAndClearsUserScopedMetadata() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)
        appState.handleLoginSuccess(response: LoginResponse(token: "token", userId: 9, role: "BLIND"))
        persistence.set("event-9", forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata)

        appState.clearSession()
        appState.clearSession()

        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.currentUser)
        XCTAssertNil(persistence.object(forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata))
    }

    func testAccountDeletionPreflightSpeaksActiveOrderBlock() async throws {
        let data = #"{"content":[{"orderId":77,"status":"IN_PROGRESS"}]}"#.data(using: .utf8)!
        let orders = try JSONDecoder().decode(PagedOrderResponse.self, from: data)
        let client = AuthLifecycleAPIClient(mineOrders: orders)
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let viewModel = AccountDeletionViewModel()

        await viewModel.preflight(appState: appState, speechService: speechService)

        let expected = "当前存在进行中的服务，请处理完成后再删除账户。"
        XCTAssertEqual(viewModel.preflightMessage, expected)
        XCTAssertEqual(speechService.lastSpokenText, expected)
        XCTAssertEqual(speechService.lastVoiceOverAnnouncement, expected)
        XCTAssertFalse(viewModel.showFinalConfirmation)
        // 拦截必须有一个**可见**的落点：两端设置页都拿这个开关驱动「无法删除账户」弹窗。
        // 只播不显曾经就是真实行为 —— 明眼志愿者与低视力用户按下去屏幕上什么都不变。
        XCTAssertTrue(viewModel.isShowingPreflightBlock)
    }

    /// 后端 `UserService.cascadeDeletePii` 刻意保留订单与评价（不存姓名手机号，留作纠纷复核审计）。
    /// PIPL 第 47 条下这件事必须让用户在按下「永久删除账户」之前知道 —— 而这句正是未来
    /// 「文案太长，精简一下」时最先被删掉的一句，所以钉在这里。
    func testAccountDeletionCopyStatesWhatIsDeletedAndWhatIsKept() {
        for role in [UserRole.blind, .volunteer, .unset] {
            let message = AccountDeletionViewModel.finalConfirmationMessage(for: role)
            XCTAssertTrue(message.contains("历史订单与评价会保留"), "\(role.rawValue) 文案没说清保留项")
            XCTAssertTrue(message.contains("手机号可以重新注册"), "\(role.rawValue) 文案没说手机号可重注册")
            XCTAssertTrue(message.contains("不可撤销"), "\(role.rawValue) 文案没说不可撤销")
        }

        // 两端各说各自真的会被删的那份：对盲人说「证件照」会让他怀疑自己填过什么。
        let blind = AccountDeletionViewModel.finalConfirmationMessage(for: .blind)
        XCTAssertTrue(blind.contains("紧急联系人"))
        XCTAssertFalse(blind.contains("资质证件照"))

        let volunteer = AccountDeletionViewModel.finalConfirmationMessage(for: .volunteer)
        XCTAssertTrue(volunteer.contains("资质证件照"))
        XCTAssertFalse(volunteer.contains("紧急联系人"))
    }

    private func prepareStoredSession(token: String, role: UserRole?, userId: Int64) -> UserDefaultsAppStatePersistence {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        persistence.set(token, forKey: AppConstants.UserDefaultsKeys.accessToken)
        persistence.set(userId, forKey: AppConstants.UserDefaultsKeys.userId)
        if let role { persistence.set(role.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole) }
        else { persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole) }
        return persistence
    }

    private final class RootHydrationAPIClient: APIClientProtocol, @unchecked Sendable {
        private let firstRequestDelay: TimeInterval
        private var profileRequestCount = 0
        private(set) var cancellationCount = 0

        init(firstRequestDelay: TimeInterval = 0) {
            self.firstRequestDelay = firstRequestDelay
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .get else { throw APIError.invalidURL }

            if path == "/api/blind/profile" {
                profileRequestCount += 1
                let account = profileRequestCount
                if account == 1, firstRequestDelay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(firstRequestDelay * 1_000_000_000))
                    } catch {
                        cancellationCount += 1
                        throw error
                    }
                }
                // 已实名：这两个用例断言的是「水合完成后只提交一个终点 .blindHome」，
                // 所以 fixture 必须是引导流全部走完的账号，否则会停在实名软提示那一步。
                let data = Data("{\"name\":\"账号\(account)\",\"verifyStatus\":\"VERIFIED\"}".utf8)
                return try JSONDecoder().decode(T.self, from: data)
            }

            if path.contains("/emergency-contacts") {
                let account = path.contains("/users/2/") ? 2 : 1
                if account == 1, firstRequestDelay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(firstRequestDelay * 1_000_000_000))
                    } catch {
                        cancellationCount += 1
                        throw error
                    }
                }
                let data = Data("[{\"id\":\(account),\"name\":\"联系人\",\"phone\":\"13800138000\",\"isPrimary\":true}]".utf8)
                return try JSONDecoder().decode(T.self, from: data)
            }

            throw APIError.invalidURL
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
