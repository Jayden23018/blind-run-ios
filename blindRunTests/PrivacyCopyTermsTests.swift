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

    private var legalTexts: [String] {
        LegalDocumentKind.allCases.flatMap { kind in
            LegalFallbackCopy.document(for: kind).sections.flatMap { [$0.heading] + $0.bullets }
        }
    }

    func testNoPrivacyOrLegalTextSaysThisSingleOrder() {
        let purposes = PrivacyConsentPurpose.allCases.flatMap {
            [$0.title, $0.launchSummary ?? ""] + $0.disclosures + [$0.declinedFeedback, $0.escortDeclinedFeedback ?? ""]
        }
        for text in legalTexts + purposes + authorizationCopy {
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

    /// 内置政策同时有身份句和服务句，不能整体禁词，这里只钉住 #558 改过的服务句。
    func testLegalServiceLinesCallTheEscortRunnerNotVolunteer() {
        let legal = legalTexts.joined(separator: "\n")
        for phrase in ["匹配附近的志愿者", "已接单的志愿者", "志愿者看不到", "志愿者需要开启定位"] {
            XCTAssertFalse(legal.contains(phrase), phrase)
        }
        XCTAssertTrue(legal.contains("已接单的陪跑员"), "没有查到内置政策的正文")
    }
}
