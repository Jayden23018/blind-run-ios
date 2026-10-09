import XCTest
@testable import blindRun

/// 语音下单的第三方大模型同意（#374，审核指南 5.1.2(i)）。
///
/// 守的是一条出站约束：**账号没同意，`POST /api/orders/voice/parse` 一个字节都不能发**。
/// 断言打在传输层桩的请求计数上，而不是打在「抛了某个错」上 —— 错抛了而请求照发，才是真正的缺陷。
@MainActor
final class VoiceOrderConsentGateTests: XCTestCase {

    // MARK: - Gate

    /// 没同意：抛「未同意」，传输层一次都没被调用。
    func testParseIsNotSentUntilTheAccountHasConsented() async {
        let (appState, client, persistence) = makeSignedInAppState(userId: 7)
        defer { persistence.reset() }

        do {
            _ = try await appState.voiceOrder.parseOrder(Self.request)
            XCTFail("未同意时不该解析成功")
        } catch {
            XCTAssertEqual(error as? VoiceOrderConsentError, .notGranted)
        }
        XCTAssertEqual(client.paths, [], "未同意却发出了请求：\(client.paths)")
    }

    /// 同意之后正常发。这条守的是反方向：闸门写成「永远拒绝」时上一条仍然绿。
    func testParseIsSentOnceTheAccountHasConsented() async throws {
        let (appState, client, persistence) = makeSignedInAppState(userId: 7)
        defer { persistence.reset() }

        appState.recordVoiceOrderConsent()
        _ = try await appState.voiceOrder.parseOrder(Self.request)

        XCTAssertEqual(client.paths, [VoiceOrderEndpoint.parseOrder])
    }

    /// 同意按**账号**记：同一台手机换人用不是罕见场景。
    /// 参数选得能区分「按账号」与「按设备 / 按版本全局」两种实现 —— 账号 7 同意，账号 8 必须仍被拦。
    func testConsentDoesNotCarryOverToAnotherAccount() async throws {
        let (appState, client, persistence) = makeSignedInAppState(userId: 7)
        defer { persistence.reset() }
        appState.recordVoiceOrderConsent()
        _ = try await appState.voiceOrder.parseOrder(Self.request)
        XCTAssertEqual(client.paths.count, 1)

        appState.handleLoginSuccess(response: LoginResponse(token: "t8", userId: 8, role: "BLIND"))

        XCTAssertFalse(appState.hasVoiceOrderConsent)
        do {
            _ = try await appState.voiceOrder.parseOrder(Self.request)
            XCTFail("账号 8 没同意过，不该继承账号 7 的同意")
        } catch {
            XCTAssertEqual(error as? VoiceOrderConsentError, .notGranted)
        }
        XCTAssertEqual(client.paths.count, 1, "账号 8 的请求不该发出")
    }

    /// 首启告知的同意不等于这一项：那是「单独」同意的含义。
    func testLaunchConsentDoesNotCoverVoiceOrdering() {
        let (appState, _, persistence) = makeSignedInAppState(userId: 7)
        defer { persistence.reset() }

        appState.acceptPrivacyConsent()

        XCTAssertFalse(appState.hasVoiceOrderConsent)
    }

    /// 同意要落盘，冷启动后仍在；且存储键只含用途、版本、userId，
    /// 不含手机号或令牌（issue 明确要求）。
    func testConsentPersistsAndItsKeyCarriesNoPhoneOrToken() {
        let (appState, _, persistence) = makeSignedInAppState(userId: 7)
        defer { persistence.reset() }
        appState.recordVoiceOrderConsent()

        let key = PrivacyConsentStore.storageKey(purpose: .voiceOrderThirdPartyLLM, scope: .user("7"))
        XCTAssertEqual(key, "com.aidrun.mvp.privacyConsent.voiceOrderThirdPartyLLM.v1.user.7")
        XCTAssertEqual(persistence.object(forKey: key) as? Bool, true)

        let relaunched = AppState(apiClient: VoiceParseCountingClient(), persistence: persistence, tokenStore: InMemoryTokenStore())
        relaunched.handleLoginSuccess(response: LoginResponse(token: "t7", userId: 7, role: "BLIND"))
        XCTAssertTrue(relaunched.hasVoiceOrderConsent, "同意应当跨启动保留")
    }

    /// UI 用例默认跳过这道同意，专测同意页的那条用 `FORCE` 走真实路径。
    /// 写反的表现是**全部经「开始约跑」进下单页的 UI 用例被同意页挡住**；
    /// 写成无条件跳过的表现是真实安装不问就发 —— 两个方向都要钉。
    func testUITestLaunchSkipsTheVoiceConsentUnlessItIsTheOneUnderTest() {
        XCTAssertTrue(AppState.uiTestSkipsVoiceOrderConsent(environment: ["AIDRUN_UI_TEST_RESET_STATE": "1"]))
        XCTAssertFalse(AppState.uiTestSkipsVoiceOrderConsent(environment: [
            "AIDRUN_UI_TEST_RESET_STATE": "1",
            "AIDRUN_UI_TEST_FORCE_VOICE_ORDER_CONSENT": "1"
        ]))
        XCTAssertFalse(AppState.uiTestSkipsVoiceOrderConsent(environment: [:]), "真实安装没有这些环境变量，一律要同意")
    }

    // MARK: - Helpers

    private static let request = ParseVoiceOrderRequest(
        transcript: "明天早上七点从人民广场出发",
        latitude: nil,
        longitude: nil,
        current: nil
    )

    private func makeSignedInAppState(userId: Int64) -> (AppState, VoiceParseCountingClient, any AppStatePersistence) {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        let client = VoiceParseCountingClient()
        let appState = AppState(apiClient: client, persistence: persistence, tokenStore: InMemoryTokenStore())
        appState.handleLoginSuccess(response: LoginResponse(token: "t\(userId)", userId: userId, role: "BLIND"))
        return (appState, client, persistence)
    }
}

/// 只数请求。解析响应全是可选字段，`{}` 就能解出来。
private final class VoiceParseCountingClient: APIClientProtocol, @unchecked Sendable {
    private(set) var paths: [String] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)
        return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)
        return try JSONDecoder().decode(T.self, from: Data("{}".utf8))
    }
}
