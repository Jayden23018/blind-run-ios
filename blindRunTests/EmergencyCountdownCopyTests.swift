import XCTest
@testable import blindRun

/// 求助倒计时那一块第一句就让人自己拨 120，不再承诺「回拨」（#659，审计 F-3）。
///
/// 客服没有值班保证，用户等回电会晚拨 120。单独成文件：`EmergencySOSTests.swift` 已超 SwiftLint 行数基线。
///
/// **验红方式**：把「转给客服并回拨你」放回 `countdownPendingEffects`，第一条必须失败。
@MainActor
final class EmergencyCountdownCopyTests: XCTestCase {

    func testCountdownLeadsWithSelfDialingAndPromisesNoCallback() {
        let label = EmergencySafetyCopy.countdownPendingEffectsAccessibilityLabel
        XCTAssertTrue(label.hasPrefix(EmergencySafetyCopy.countdownSelfDialFirst), label)
        XCTAssertTrue(EmergencySafetyCopy.countdownSelfDialFirst.contains("拨打120"))
        for effect in EmergencySafetyCopy.countdownPendingEffects {
            XCTAssertFalse(effect.contains("回拨"), effect)
            XCTAssertFalse(effect.contains("客服"), "客服没有值班保证，倒计时里不提客服：\(effect)")
        }
    }

    /// 与 `EmergencySOSTests.testNoEmergencyCopyClaimsAnSMSWasDelivered` 同一张禁用词表：
    /// 那条扫了 `countdownPendingEffects`，没扫新加的第一句和整句读屏标签。
    func testCountdownCopyNeverClaimsDelivery() {
        let forbidden = ["联系人已收到短信", "已收到短信", "已通知家属", "已通知你的联系人", "短信已送达"]
        for copy in [EmergencySafetyCopy.countdownSelfDialFirst, EmergencySafetyCopy.countdownPendingEffectsAccessibilityLabel] {
            for claim in forbidden {
                XCTAssertFalse(copy.contains(claim), "“\(claim)” in “\(copy)”")
            }
        }
    }
}
