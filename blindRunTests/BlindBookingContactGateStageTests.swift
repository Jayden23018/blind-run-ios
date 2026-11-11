import XCTest
@testable import blindRun

/// #805 约跑前的紧急联系人门页：什么时候拦、拦成哪一种。判据与下单门槛同源（`AppState.hasValidEmergencyContacts`）。
final class BlindBookingContactGateStageTests: XCTestCase {
    func testValidContactsSkipTheGate() {
        XCTAssertNil(BlindBookingContactGateStage.resolve(hasValidEmergencyContacts: true, contactCount: 1))
    }

    func testNoContactsShowsPickFromContactsStage() {
        XCTAssertEqual(
            BlindBookingContactGateStage.resolve(hasValidEmergencyContacts: false, contactCount: 0),
            .noContacts
        )
    }

    /// 有人但没有唯一主联系人时，添加新联系人补不齐门槛（新增的不是第一位，不会自动成主联系人），
    /// 所以必须走「去设主联系人」，不能再给通讯录按钮。
    func testContactsWithoutPrimaryShowsSetPrimaryStage() {
        XCTAssertEqual(
            BlindBookingContactGateStage.resolve(hasValidEmergencyContacts: false, contactCount: 2),
            .noPrimary(count: 2)
        )
    }

    /// 文案红线（AGENTS.md §6）：只说「会发」，不说已发出、已送达、已通知。
    func testExplanationNeverClaimsDelivery() {
        for stage in [BlindBookingContactGateStage.noContacts, .noPrimary(count: 2)] {
            for forbidden in ["已发出", "已送达", "已通知", "已收到短信"] {
                XCTAssertFalse(stage.spokenIntro.contains(forbidden), "\(stage) 说了「\(forbidden)」")
            }
        }
    }
}
