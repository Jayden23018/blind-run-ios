import XCTest
@testable import blindRun

/// 隐私与法律文本的称呼口径（#558）：一律写「此订单」；服务场景叫「陪跑员」，「志愿者」只留在注册和身份场景。
final class PrivacyCopyTermsTests: XCTestCase {

    private let authorizationCopy = [
        PrivacyAuthorizationCopy.visionPurpose,
        PrivacyAuthorizationCopy.locationPurpose,
        PrivacyAuthorizationCopy.locationBlockedDuringEscort,
        VolunteerPrivacyCopy.locationPurpose
    ]

    func testNoPrivacyOrLegalTextSaysThisSingleOrder() {
        let legal = LegalDocumentKind.allCases.flatMap { LegalFallbackCopy.document(for: $0).sections.flatMap(\.bullets) }
        let purposes = PrivacyConsentPurpose.allCases.flatMap {
            [$0.title] + $0.disclosures + [$0.declinedFeedback, $0.escortDeclinedFeedback ?? ""]
        }
        for text in legal + purposes + authorizationCopy {
            XCTAssertFalse(text.contains("这一单"), text)
        }
    }

    /// 下面这些文本只讲订单和服务。身份场景的「志愿者」（实名、资质、角色定义）在 `appLaunch`、内置政策和用户协议里，不查。
    func testServiceTextsCallTheEscortRunnerNotVolunteer() {
        let purposes: [PrivacyConsentPurpose] = [.blindIdentity, .blindVisionProfile, .blindLocationTrack, .volunteerLocationTrack]
        let serviceTexts = purposes.flatMap { $0.disclosures + [$0.declinedFeedback, $0.escortDeclinedFeedback ?? ""] }
        for text in serviceTexts + authorizationCopy {
            XCTAssertFalse(text.contains("志愿者"), text)
        }
    }
}
