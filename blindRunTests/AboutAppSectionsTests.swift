import XCTest
@testable import blindRun

final class AboutAppSectionsTests: XCTestCase {
    func testVersionLineUsesBundleVersion() {
        XCTAssertEqual(AppIdentity.versionLine(info: ["CFBundleShortVersionString": "1.2"]), "版本 1.2")
    }

    func testVersionLineFallsBackWhenBundleVersionIsMissingOrBlank() {
        XCTAssertEqual(AppIdentity.versionLine(info: nil), "版本未知")
        XCTAssertEqual(AppIdentity.versionLine(info: ["CFBundleShortVersionString": "  "]), "版本未知")
    }

    func testRealBundleProvidesVersion() {
        XCTAssertNotEqual(AppIdentity.versionLine(), "版本未知")
    }

    func testFilingNumberKeepsTheAppSuffix() {
        XCTAssertEqual(AppFilingDisclosure.appFilingNumber, "粤ICP备20047259号-4A")
    }

    func testFilingQueryURLIsTheMIITSite() {
        XCTAssertEqual(AppFilingDisclosure.filingQueryURL.absoluteString, "https://beian.miit.gov.cn/")
    }
}
