import AMapFoundationKit
import XCTest
@testable import blindRun

/// 高德两项扩展功能（安全保障、数据用于统计分析）必须关着（#355）。
/// iOS 基础库里两者**默认 YES**（`AMapServices.h`：「默认为YES。since 1.8.7」），
/// 删掉 `AMapManager.configurePrivacyCompliance` 里那两行这条就红 —— 而隐私政策写着「两项都没有开启」。
final class AMapPrivacyComplianceTests: XCTestCase {

    func testAMapOptionalSecurityAndAnalysisFeaturesAreOff() throws {
        // 测试宿主的 `blindRunApp.init` 已调过 `AMapManager.configure()`。
        try XCTSkipUnless(AMapManager.isConfigured, "高德 key 未配置，SDK 不会被初始化")
        XCTAssertFalse(AMapServices.shared().securityAgree, "「安全保障」没问过用户，不许开")
        XCTAssertFalse(AMapServices.shared().analysisAgree, "「数据用于统计分析」用途含优化广告投放，与「不做广告」冲突")
    }
}
