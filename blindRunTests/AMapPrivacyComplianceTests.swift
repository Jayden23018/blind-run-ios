import AMapFoundationKit
import XCTest
@testable import blindRun

/// 高德两项扩展功能（安全保障、数据用于统计分析）必须关着（#355）。
/// iOS 基础库里两者**默认 YES**（`AMapServices.h`：「默认为YES。since 1.8.7」），
/// 删掉 `AMapManager.disableOptionalExtensions` 里那两行这条就红 —— 而隐私政策写着「两项都没有开启」。
final class AMapPrivacyComplianceTests: XCTestCase {

    func testAMapOptionalSecurityAndAnalysisFeaturesAreOff() throws {
        // 测试宿主的 `blindRunApp.init` 已调过 `AMapManager.configure()`。
        try XCTSkipUnless(AMapManager.isConfigured, "高德 key 未配置，SDK 不会被初始化")
        XCTAssertFalse(AMapServices.shared().securityAgree, "「安全保障」没问过用户，不许开")
        XCTAssertFalse(AMapServices.shared().analysisAgree, "「数据用于统计分析」用途含优化广告投放，与「不做广告」冲突")
    }

    /// #408：向高德声明「用户已同意」要等用户真同意之后。此前 `App.init` 无条件声明，
    /// 首装用户还停在同意页时高德那边已是「已同意」。声明本身（`updatePrivacyAgree`）读不回来，
    /// 所以断的是它的触发条件 `isPrivacyAgreed`：没点同意之前恒为假，按下同意才翻面。
    @MainActor
    func testAMapPrivacyAgreementWaitsForTheUserToAcceptTheLaunchConsent() {
        AMapManager.resetPrivacyAgreementForTesting()
        addTeardownBlock { AMapManager.resetPrivacyAgreementForTesting() }

        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        XCTAssertFalse(appState.didAcceptPrivacyConsent, "前提：全新安装还没同意")
        XCTAssertFalse(AMapManager.isPrivacyAgreed, "还停在同意页就不能向高德声明已同意")

        // 冷启动时同意记录为「未同意」，同步进来也不能翻面。
        AMapManager.setUserAcceptedPrivacy(false)
        XCTAssertFalse(AMapManager.isPrivacyAgreed)

        appState.acceptPrivacyConsent()
        XCTAssertTrue(AMapManager.isPrivacyAgreed, "用户按下「同意」后要补发声明")
    }
}
