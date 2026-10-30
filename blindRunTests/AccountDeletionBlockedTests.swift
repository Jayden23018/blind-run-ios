import XCTest
@testable import blindRun

/// 删除账户被后端 409 拦下时的弹窗（后端 #844 / #847）。
///
/// 两种 409 都是「现在删不了，等条件变了再来」：有进行中的订单
/// （`ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED`），或有未结束的紧急求助
/// （`ACTIVE_EMERGENCY_ACCOUNT_DELETION_BLOCKED`）。立刻重试只会再被拒一次，
/// 所以弹窗不给「重试」。网络断开、5xx 这类失败重试有意义，保留「重试」。
///
/// 每条用例都把**后端真实响应体**喂给 `URLSessionAPIClient`：后端的 `code` 是整数 409，
/// 业务码在 `errorCode` 里，这条解码路径（`APIErrorEnvelope`）正是要守的东西。
@MainActor
final class AccountDeletionBlockedTests: XCTestCase {

    private static let emergencyBlockedBody = #"""
    {"success":false,"code":409,"errorCode":"ACTIVE_EMERGENCY_ACCOUNT_DELETION_BLOCKED","message":"你有未结束的紧急求助，请等待客服处理完毕后再注销","data":null}
    """#

    private static let orderBlockedBody = #"""
    {"success":false,"code":409,"errorCode":"ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED","message":"你有进行中的订单，无法注销","data":null}
    """#

    override func tearDown() {
        DeletionStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testActiveEmergencyBlockShowsLocalCopyWithoutRetry() async throws {
        let appState = try await appStateAfterDeleting(respondingWith: 409, body: Self.emergencyBlockedBody)

        let alert = try XCTUnwrap(appState.accountDeletionState.accountDeletionFailureAlert)
        XCTAssertEqual(alert.title, "暂时不能删除账户")
        XCTAssertEqual(alert.message, "当前有未结束的紧急求助，请等待客服处理完毕后再删除账户。")
        XCTAssertFalse(alert.offersRetry, "立刻重试只会再被拒一次")
        XCTAssertNotNil(appState.accessToken, "删除没成功就不能把人踢出登录态")
    }

    func testActiveOrderBlockAlsoDropsRetry() async throws {
        let appState = try await appStateAfterDeleting(respondingWith: 409, body: Self.orderBlockedBody)

        let alert = try XCTUnwrap(appState.accountDeletionState.accountDeletionFailureAlert)
        XCTAssertEqual(alert.title, "暂时不能删除账户")
        XCTAssertEqual(alert.message, ErrorCode.activeOrderAccountDeletionBlocked.localizedMessage)
        XCTAssertFalse(alert.offersRetry)
    }

    /// 两种拦截的正文不能撞：一个要用户去处理订单，一个要用户等客服。
    func testTwoBlockReasonsSayDifferentThings() throws {
        let emergency = try XCTUnwrap(
            ErrorCode(rawValue: "ACTIVE_EMERGENCY_ACCOUNT_DELETION_BLOCKED"),
            "rawValue 要逐字对上后端码，否则落到未知兜底"
        )
        XCTAssertNotEqual(emergency.localizedMessage, ErrorCode.activeOrderAccountDeletionBlocked.localizedMessage)
    }

    /// 后端 `errorCode` 是开放枚举。老版本 App 遇到不认识的码时，整条响应仍要解得出来，
    /// 并念后端 `message`；它不是已知的拦截，所以仍按普通失败给「重试」。
    func testUnknownErrorCodeStillDecodesAndShowsServerMessage() async throws {
        let body = #"{"success":false,"code":409,"errorCode":"SOME_FUTURE_CODE","message":"后端新加的原因"}"#
        let appState = try await appStateAfterDeleting(respondingWith: 409, body: body)

        let alert = try XCTUnwrap(appState.accountDeletionState.accountDeletionFailureAlert)
        XCTAssertEqual(alert.title, AccountDeletionFailureAlert.failedTitle)
        XCTAssertEqual(alert.message, "后端新加的原因")
        XCTAssertTrue(alert.offersRetry)
    }

    func testServerErrorKeepsRetry() async throws {
        let body = #"{"success":false,"code":500,"errorCode":"INTERNAL_ERROR","message":"x"}"#
        let appState = try await appStateAfterDeleting(respondingWith: 500, body: body)

        let alert = try XCTUnwrap(appState.accountDeletionState.accountDeletionFailureAlert)
        XCTAssertEqual(alert.title, AccountDeletionFailureAlert.failedTitle)
        XCTAssertTrue(alert.offersRetry, "5xx 重试有意义")
    }

    func testDismissClearsTheBlockedAlert() async throws {
        let appState = try await appStateAfterDeleting(respondingWith: 409, body: Self.emergencyBlockedBody)
        XCTAssertNotNil(appState.accountDeletionState.accountDeletionFailureAlert)

        appState.dismissAccountDeletionFailure()

        XCTAssertNil(appState.accountDeletionState.accountDeletionFailureAlert)
        XCTAssertEqual(appState.accountDeletionState, .idle)
    }

    // MARK: - Helpers

    /// 走真实 `URLSessionAPIClient` 拿到删除失败的错误，再交给 `AppState.deleteCurrentAccount`。
    private func appStateAfterDeleting(respondingWith status: Int, body: String) async throws -> AppState {
        let error = try await deletionError(status: status, body: body)

        let fake = FakeAuthService()
        fake.deleteAccountResult = .failure(error)
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        addTeardownBlock { persistence.reset() }
        let appState = AppState(auth: fake, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.handleLoginSuccess(response: LoginResponse(token: "t", userId: 7, role: "BLIND"))

        await appState.deleteCurrentAccount()
        return appState
    }

    private func deletionError(status: Int, body: String) async throws -> Error {
        DeletionStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeletionStubURLProtocol.self]
        let client = URLSessionAPIClient(
            baseURL: URL(string: "http://example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { "t" }
        )
        do {
            let _: DeleteAccountResponse = try await client.delete("/api/users/7")
        } catch {
            return error
        }
        XCTFail("删除应当失败")
        return APIError.invalidURL
    }
}

private final class DeletionStubURLProtocol: URLProtocol, @unchecked Sendable {
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
