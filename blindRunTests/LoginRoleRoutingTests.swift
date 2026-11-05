import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class LoginRoleRoutingTests: XCTestCase, BlindRunTestSupport {
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

    /// 新账号什么都没填（没昵称、没紧急联系人），甚至后端还没有档案（404），登录后都直接进首页（#781）。
    /// 改动前这三种都落在 `.blindProfile`（「完善信息」页）—— 那正是负责人说的「卡住他们」。
    func testNewBlindAccountWithNothingFilledInGoesStraightHome() async {
        for profile in [RootHydrationAPIClient.Profile.empty, .notFound] {
            let persistence = AppStatePersistenceFactory.makeIsolatedTest()
            defer { persistence.reset() }
            let client = RootHydrationAPIClient(profile: profile)
            let appState = AppState(apiClient: client, persistence: persistence)
            appState.currentEnvironment = .mock
            appState.handleLoginSuccess(response: LoginResponse(token: "token-new", userId: 1, role: "BLIND"))
            let router = ContentRootRouter()

            router.synchronize(with: appState)

            let didRoute = await waitUntil { router.route == .blindHome }
            XCTAssertTrue(didRoute, "\(profile)：没填资料也要进首页，实际停在 \(router.route)")
            XCTAssertFalse(appState.isBlindBookingReady, "前提：这个账号确实还不能下单")
        }
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

    private final class RootHydrationAPIClient: APIClientProtocol, @unchecked Sendable {
        /// 档案的三种样子：填齐了 / 新账号空档案（没昵称、没联系人）/ 后端没有档案（404）。
        enum Profile { case filled, empty, notFound }

        private let firstRequestDelay: TimeInterval
        private let profile: Profile
        private var profileRequestCount = 0
        private(set) var cancellationCount = 0

        init(firstRequestDelay: TimeInterval = 0, profile: Profile = .filled) {
            self.firstRequestDelay = firstRequestDelay
            self.profile = profile
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
                return try JSONDecoder().decode(T.self, from: try await profileData())
            }

            if path.contains("/emergency-contacts") {
                return try JSONDecoder().decode(T.self, from: try await contactsData(path: path))
            }

            throw APIError.invalidURL
        }

        private func profileData() async throws -> Data {
            switch profile {
            case .filled: break
            case .empty: return Data("{}".utf8)
            case .notFound: throw APIError.unknown(statusCode: 404)
            }
            profileRequestCount += 1
            let account = profileRequestCount
            if account == 1 { try await delayFirstRequestIfNeeded() }
            // 资料齐全的账号；资料不全的账号见 `Profile.empty`（#781 起同样进首页）。
            return Data("{\"name\":\"账号\(account)\",\"verifyStatus\":\"VERIFIED\"}".utf8)
        }

        private func contactsData(path: String) async throws -> Data {
            guard profile == .filled else { return Data("[]".utf8) }
            let account = path.contains("/users/2/") ? 2 : 1
            if account == 1 { try await delayFirstRequestIfNeeded() }
            return Data("[{\"id\":\(account),\"name\":\"联系人\",\"phone\":\"13800138000\",\"isPrimary\":true}]".utf8)
        }

        private func delayFirstRequestIfNeeded() async throws {
            guard firstRequestDelay > 0 else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(firstRequestDelay * 1_000_000_000))
            } catch {
                cancellationCount += 1
                throw error
            }
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
