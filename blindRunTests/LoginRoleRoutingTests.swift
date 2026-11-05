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
