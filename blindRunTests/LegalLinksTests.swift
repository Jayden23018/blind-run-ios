import XCTest
@testable import blindRun

/// `GET /api/misc/legal-links` 的分支覆盖。
///
/// 核心保证（App Store 审核 5.1.1 / 5.1.2）：无论后端返回什么，
/// 隐私政策 / 用户协议入口都必须落到一个有内容的页面。
final class LegalLinksTests: XCTestCase {

    // MARK: - Fallback Branch

    func testBothURLsNilRoutesToBuiltInFallback() {
        // 当前生产的真实状态：后端配置未注入，两个字段都是 null。
        let links = LegalLinksResponse(privacyPolicyUrl: nil, userAgreementUrl: nil)

        XCTAssertEqual(LegalDocumentKind.privacyPolicy.destination(in: links), .builtInFallback)
        XCTAssertEqual(LegalDocumentKind.userAgreement.destination(in: links), .builtInFallback)
    }

    func testMissingResponseRoutesToBuiltInFallback() {
        // links 为 nil 表示尚未加载完成或请求失败。
        for kind in LegalDocumentKind.allCases {
            XCTAssertEqual(kind.destination(in: nil), .builtInFallback)
        }
    }

    func testOneNullOneValidRoutesEachBranchIndependently() {
        let links = LegalLinksResponse(
            privacyPolicyUrl: nil,
            userAgreementUrl: "https://aidrun.example.com/terms"
        )

        XCTAssertEqual(LegalDocumentKind.privacyPolicy.destination(in: links), .builtInFallback)
        XCTAssertEqual(
            LegalDocumentKind.userAgreement.destination(in: links),
            .remote(URL(string: "https://aidrun.example.com/terms")!)
        )
    }

    func testUnusableURLStringsRouteToBuiltInFallback() {
        // 后端配置是外部输入，不可信。这些都必须挡掉而不是打开。
        let unusable = [
            "",
            "   ",
            "\n",
            "null",
            "NULL",
            "/privacy",                       // 相对路径
            "aidrun://privacy",               // 自定义 scheme
            "javascript:alert(1)",            // 脚本
            "file:///etc/passwd",             // 本地文件
            "https://",                       // 无 host
            "http://"
        ]

        for raw in unusable {
            let links = LegalLinksResponse(privacyPolicyUrl: raw, userAgreementUrl: raw)
            XCTAssertEqual(
                LegalDocumentKind.privacyPolicy.destination(in: links),
                .builtInFallback,
                "应回退到内置文案：\(raw)"
            )
        }
    }

    // MARK: - Remote Branch

    func testValidURLsRouteToRemote() {
        let links = LegalLinksResponse(
            privacyPolicyUrl: "https://aidrun.example.com/privacy",
            userAgreementUrl: "http://aidrun.example.com/terms"
        )

        XCTAssertEqual(
            LegalDocumentKind.privacyPolicy.destination(in: links),
            .remote(URL(string: "https://aidrun.example.com/privacy")!)
        )
        // http 也接受：后端当前整体走 http://47.114.113.171。
        XCTAssertEqual(
            LegalDocumentKind.userAgreement.destination(in: links),
            .remote(URL(string: "http://aidrun.example.com/terms")!)
        )
    }

    func testSurroundingWhitespaceIsTrimmedBeforeOpening() {
        let links = LegalLinksResponse(
            privacyPolicyUrl: "  https://aidrun.example.com/privacy\n",
            userAgreementUrl: nil
        )

        XCTAssertEqual(
            LegalDocumentKind.privacyPolicy.destination(in: links).remoteURL,
            URL(string: "https://aidrun.example.com/privacy")
        )
    }

    // MARK: - Decoding

    func testDecodesNullFieldsFromBackendPayload() throws {
        // APIClient 已解包 {success, data} 外层信封，这里只解 data 内层。
        let json = Data(#"{"privacyPolicyUrl":null,"userAgreementUrl":null}"#.utf8)

        let decoded = try JSONDecoder().decode(LegalLinksResponse.self, from: json)

        XCTAssertNil(decoded.privacyPolicyUrl)
        XCTAssertNil(decoded.userAgreementUrl)
        XCTAssertEqual(LegalDocumentKind.privacyPolicy.destination(in: decoded), .builtInFallback)
    }

    func testDecodesPopulatedFieldsFromBackendPayload() throws {
        let json = Data(#"""
        {"privacyPolicyUrl":"https://aidrun.example.com/privacy","userAgreementUrl":"https://aidrun.example.com/terms"}
        """#.utf8)

        let decoded = try JSONDecoder().decode(LegalLinksResponse.self, from: json)

        XCTAssertTrue(LegalDocumentKind.privacyPolicy.destination(in: decoded).isRemote)
        XCTAssertTrue(LegalDocumentKind.userAgreement.destination(in: decoded).isRemote)
    }

    // MARK: - Fallback Copy

    func testFallbackCopyIsNeverEmptyForEitherDocument() {
        // 回退页是当前实际发布路径，绝不能是空白页。
        for kind in LegalDocumentKind.allCases {
            let document = LegalFallbackCopy.document(for: kind)

            XCTAssertEqual(document.title, kind.title)
            XCTAssertFalse(document.notice.isEmpty)
            XCTAssertFalse(document.sections.isEmpty, "\(kind.rawValue) 缺少正文分节")

            for section in document.sections {
                XCTAssertFalse(section.heading.isEmpty)
                XCTAssertFalse(section.bullets.isEmpty, "\(section.heading) 没有正文")
                for bullet in section.bullets {
                    XCTAssertFalse(bullet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Mock Client

    func testMockClientServesLegalLinksWithoutAuth() async throws {
        let client = MockAPIClient()

        let response: LegalLinksResponse = try await client.get(
            "/api/misc/legal-links",
            requiresAuth: false
        )

        XCTAssertTrue(LegalDocumentKind.privacyPolicy.destination(in: response).isRemote)
        XCTAssertTrue(LegalDocumentKind.userAgreement.destination(in: response).isRemote)
    }

    // MARK: - AppState 真的发起了这个请求

    /// 2026-08-04 `validate-spec-coverage.mjs` 首跑抓到：模型、回退文案、分支判定全都在，
    /// **但全仓没有任何一处发起 `GET /api/misc/legal-links`** —— 只有 Mock 路由了它。
    /// 也就是说 App 永久处在回退态，等运维注入生产 URL 后仍然不会显示外链。
    /// 上面那些用例全是纯函数级的，一条都抓不到这个，所以这里补真正的调用侧。
    @MainActor
    func testAppStateActuallyRequestsLegalLinks() async {
        let stub = LegalLinksAPIClientStub()
        stub.response = LegalLinksResponse(
            privacyPolicyUrl: "https://aidrun.example.com/privacy",
            userAgreementUrl: nil
        )
        let appState = AppState(apiClient: stub)

        XCTAssertNil(appState.legalLinks, "加载前应为 nil，入口走回退")
        await appState.loadLegalLinksIfNeeded()

        XCTAssertEqual(stub.requests.map(\.path), ["/api/misc/legal-links"])
        XCTAssertEqual(
            stub.requests.first?.requiresAuth, false,
            "必须免鉴权：审核员是未登录状态，带鉴权会 401，隐私政策就找不到了"
        )
        XCTAssertTrue(LegalDocumentKind.privacyPolicy.destination(in: appState.legalLinks).isRemote)
        XCTAssertEqual(LegalDocumentKind.userAgreement.destination(in: appState.legalLinks), .builtInFallback)
    }

    /// 只请求一次：这两个 URL 来自后端配置，一次会话里不会变。
    @MainActor
    func testLegalLinksAreRequestedOnlyOnce() async {
        let stub = LegalLinksAPIClientStub()
        stub.response = LegalLinksResponse(privacyPolicyUrl: nil, userAgreementUrl: nil)
        let appState = AppState(apiClient: stub)

        await appState.loadLegalLinksIfNeeded()
        await appState.loadLegalLinksIfNeeded()
        await appState.loadLegalLinksIfNeeded()

        XCTAssertEqual(stub.requests.count, 1)
    }

    /// 请求失败必须静默：入口在任何时刻都得可点且有内容。
    /// 这里冒一个错误弹窗，等于把审核员挡在隐私政策之外。
    @MainActor
    func testLegalLinksFailureLeavesEntriesOnTheFallbackPath() async {
        let stub = LegalLinksAPIClientStub()
        stub.error = .unknown(statusCode: 500)
        let appState = AppState(apiClient: stub)

        await appState.loadLegalLinksIfNeeded()

        XCTAssertNil(appState.legalLinks)
        for kind in LegalDocumentKind.allCases {
            XCTAssertEqual(kind.destination(in: appState.legalLinks), .builtInFallback)
        }
    }
}

// MARK: - Test Doubles

private final class LegalLinksAPIClientStub: APIClientProtocol, @unchecked Sendable {
    struct RecordedRequest {
        let path: String
        let requiresAuth: Bool
    }

    var response: LegalLinksResponse?
    var error: APIError?
    private(set) var requests: [RecordedRequest] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        requests.append(RecordedRequest(path: path, requiresAuth: requiresAuth))
        if let error { throw error }
        guard let typed = response as? T else { throw APIError.unknown(statusCode: -1) }
        return typed
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.unknown(statusCode: -1)
    }
}
