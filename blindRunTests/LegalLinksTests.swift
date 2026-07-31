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
}
