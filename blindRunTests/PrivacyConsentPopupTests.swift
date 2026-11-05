import XCTest
@testable import blindRun

/// 单独同意的小弹窗与表单勾选框文案（#769）。从 `PrivacyConsentTests` 分出来：那个文件已到 400 行上限。
final class PrivacyConsentPopupTests: XCTestCase {
    /// 志愿者实名勾选框旁的协议页必须原样带出 `disclosures`，一条不少、一个字不改（#769）——
    /// 勾选框只是把告知挪到了点开协议名之后，不是替代。
    func testCheckboxDocumentCarriesEveryDisclosureVerbatim() {
        let document = PrivacyConsentPurpose.volunteerIdentity.checkboxDocument
        XCTAssertEqual(document.sections.flatMap(\.bullets), PrivacyConsentPurpose.volunteerIdentity.disclosures)
        XCTAssertEqual(document.title, "身份信息与人脸核验授权")
    }

    /// 小弹窗的自动播报只念标题 + 摘要（#769）；没有摘要的目的退回全文，不能念成空的。
    func testPopupSpokenScriptUsesSummaryWhenPresent() {
        let location = PrivacyConsentPurpose.blindLocationTrack
        XCTAssertEqual(location.popupSpokenScript, "\(location.title) \(location.popupSummary ?? "")")
        XCTAssertNotEqual(location.popupSpokenScript, location.spokenScript)
        XCTAssertNil(PrivacyConsentPurpose.volunteerIdentity.popupSummary)
        XCTAssertEqual(PrivacyConsentPurpose.volunteerIdentity.popupSpokenScript, PrivacyConsentPurpose.volunteerIdentity.spokenScript)
    }
}
