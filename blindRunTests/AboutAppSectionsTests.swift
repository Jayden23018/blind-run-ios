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

    /// 「关于」页顶部的图标取不到时页面只是少一块，不报错 —— 换图标资源格式时会静默消失（#755）。
    func testRealBundleProvidesAppIcon() {
        XCTAssertNotNil(AppIdentity.iconImage(), "安装包里取不到 App 图标，「关于」页顶部会没有图标")
    }

    func testFilingNumberKeepsTheAppSuffix() {
        XCTAssertEqual(AppFilingDisclosure.appFilingNumber, "粤ICP备20047259号-4A")
    }

    func testFilingQueryURLIsTheMIITSite() {
        XCTAssertEqual(AppFilingDisclosure.filingQueryURL.absoluteString, "https://beian.miit.gov.cn/")
    }
}
