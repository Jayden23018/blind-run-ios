import XCTest
@testable import blindRun

/// 认证·会话片的 service 层。两组用例分工不同，缺一组都留下一个洞：
///
/// - **端点组**：`AuthService` 有没有把每个方法映到正确的 method / path / requiresAuth。
///   路径字面量本身由 `scripts/validate-spec-coverage.mjs` 对着后端契约撞，这里只管
///   「这个方法打的是不是那一条」—— 那个脚本看不出 `logout()` 打成了 `/api/auth/me`。
/// - **失败传播组**：错误有没有**穿过** service 层到达渲染点。
///   本仓库的历史缺陷是「失败时屏幕上什么都不多」，所以断言打在
///   `logoutState` / `accountDeletionState` 这些会被 UI 读到的状态上，而不是打在「抛没抛」上。
final class AuthServiceTests: XCTestCase {

    // MARK: - 端点映射

    func testSendVerificationCodeIsUnauthenticatedPost() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = SendCodeResponse(success: true, message: "已发送", code: nil)

        _ = try await AuthService(transport: transport).sendVerificationCode(phone: "13800138000")

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.path, "/api/auth/send-code")
        XCTAssertFalse(sent.requiresAuth, "还没登录，带鉴权会 401")
    }

    func testLegalLinksStaysUnauthenticated() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = LegalLinksResponse(privacyPolicyUrl: nil, userAgreementUrl: nil)

        _ = try await AuthService(transport: transport).legalLinks()

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.path, "/api/misc/legal-links")
        XCTAssertFalse(
            sent.requiresAuth,
            "后端 permitAll，App Store 审核员是未登录状态（5.1.1 / 5.1.2）"
        )
    }

    func testDeleteAccountInterpolatesUserIdIntoOneLiteralPath() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = DeleteAccountResponse(
            success: true, message: nil, phoneReusable: true, allTokensInvalidated: true
        )

        _ = try await AuthService(transport: transport).deleteAccount(userId: 42)

        XCTAssertEqual(transport.requests.first?.method, .delete)
        XCTAssertEqual(transport.requests.first?.path, "/api/users/42")
    }

    /// `DELETE` **带 body**。这一条是 `send(_:body:)` 存在的理由：
    /// `APIClientProtocol.delete(_:)` 便捷式没有 body 参数，用它会把 token 丢掉、
    /// 后端删不到这台设备的绑定，旧账号的求助推送继续念给下一个人听。
    func testUnregisterDeviceTokenIsDeleteWithBody() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = EmptyResponse()

        try await AuthService(transport: transport).unregisterDeviceToken("abc123")

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.method, .delete)
        XCTAssertEqual(sent.path, "/api/devices/apns")
        XCTAssertTrue(sent.hasBody, "token 在 body 里，丢了后端就不知道删哪一条")
    }

    func testMissedNotificationsPassesCursorAsQuery() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = MissedNotificationPage(notifications: [], hasMore: false)

        _ = try await AuthService(transport: transport).missedNotifications(after: "2026-09-02T10:00:00")

        XCTAssertEqual(transport.requests.first?.path, "/api/notifications/since")
        XCTAssertEqual(transport.requests.first?.query, ["after": "2026-09-02T10:00:00"])
    }

    // MARK: - 失败必须穿过 service 层

    /// 登出失败**不能**被当成登出成功。吞掉的话用户以为退了、token 其实还活着。
    @MainActor
    func testLogoutFailureSurfacesRevocationFailedInsteadOfSigningOut() async {
        let fake = FakeAuthService()
        fake.logoutResult = .failure(APIError.unknown(statusCode: 500))
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(auth: fake, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.handleLoginSuccess(response: LoginResponse(token: "t", userId: 7, role: "BLIND"))

        await appState.logout()

        XCTAssertEqual(fake.calls, ["logout()"])
        guard case .revocationFailed = appState.logoutState else {
            return XCTFail("服务端撤销失败必须让用户看得到，实际：\(appState.logoutState)")
        }
        XCTAssertEqual(appState.accessToken, "t", "没确认撤销就清本地 token，等于把现场毁掉")
    }

    /// 注销失败同理：屏幕上必须**多**出一条失败文案，而不是只是没跳转。
    @MainActor
    func testAccountDeletionFailureSurfacesMessage() async {
        let fake = FakeAuthService()
        fake.deleteAccountResult = .failure(
            APIError.serverError(ErrorResponse(code: "ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED", message: "有进行中的服务"))
        )
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(auth: fake, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.handleLoginSuccess(response: LoginResponse(token: "t", userId: 7, role: "BLIND"))

        await appState.deleteCurrentAccount()

        XCTAssertEqual(fake.lastUserId, 7)
        guard case .revocationFailed(let message) = appState.accountDeletionState else {
            return XCTFail("注销失败必须有可见文案，实际：\(appState.accountDeletionState)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotNil(appState.accessToken, "删除没成功就不能把人踢出登录态")
    }

    /// 会话恢复走的是 `auth.currentUser()`，不是别的端点。
    @MainActor
    func testRestoreSessionGoesThroughAuthService() async {
        let fake = FakeAuthService()
        fake.currentUserResult = .success(CurrentUserResponse(userId: 7, phone: nil, role: "BLIND"))
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = InMemoryTokenStore()
        store.save("stored-token")
        let appState = AppState(auth: fake, persistence: persistence, tokenStore: store)

        await appState.restoreSession()

        XCTAssertEqual(fake.calls, ["currentUser()"])
        XCTAssertEqual(appState.sessionRestorationState, .authenticated)
        XCTAssertEqual(appState.activeRole, .blind)
    }
}

// MARK: - Test Doubles
//
// `RecordingTransport` 已搬到 `blindRunTests/RecordingTransport.swift`，激励片起各片共用一份。
