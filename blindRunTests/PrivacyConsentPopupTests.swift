import CoreLocation
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
        let voice = PrivacyConsentPurpose.voiceOrderThirdPartyLLM
        XCTAssertEqual(voice.popupSpokenScript, "\(voice.title) \(voice.popupSummary ?? "")")
        XCTAssertNotEqual(voice.popupSpokenScript, voice.spokenScript)
        XCTAssertNil(PrivacyConsentPurpose.volunteerIdentity.popupSummary)
        XCTAssertEqual(PrivacyConsentPurpose.volunteerIdentity.popupSpokenScript, PrivacyConsentPurpose.volunteerIdentity.spokenScript)
    }

    /// 位置轨迹说明页（#776）：两个角色各三条用途，自动播报念标题、用途和那段说明；
    /// 系统定位框的回答直接就是同意 / 拒绝，还没回答时不算任何一种。
    func testLocationPreAlertCopyAndSystemAnswerMapping() {
        for purpose in [PrivacyConsentPurpose.blindLocationTrack, .volunteerLocationTrack] {
            XCTAssertEqual(purpose.preAlertUses.count, 3)
            XCTAssertTrue(purpose.preAlertSpokenScript.hasPrefix(purpose.preAlertTitle))
            XCTAssertTrue(purpose.preAlertSpokenScript.hasSuffix(purpose.preAlertFootnote))
            XCTAssertTrue(purpose.preAlertFootnote.contains("系统设置"))
        }
        XCTAssertFalse(PrivacyConsentPurpose.preAlertContinueTitle.contains("允许"), "HIG：说明页的按钮不用「允许」")
        XCTAssertEqual(LocationTrackPreAlertView.consentAnswer(to: .authorizedWhenInUse), true)
        XCTAssertEqual(LocationTrackPreAlertView.consentAnswer(to: .denied), false)
        XCTAssertEqual(LocationTrackPreAlertView.consentAnswer(to: .restricted), false)
        XCTAssertNil(LocationTrackPreAlertView.consentAnswer(to: .notDetermined))
    }
}
