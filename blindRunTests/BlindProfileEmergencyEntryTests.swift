import XCTest
@testable import blindRun

/// #605：全屏手势按模式分流。云端求助只能去订单页，本地拨号绝不碰订单页。
/// 「我的」列表那一行已删（负责人 2026-11-05，#711），只剩手势这一条通道。
@MainActor
final class BlindProfileEmergencyEntryTests: XCTestCase {
    func testLocalCallGestureStaysOnTheCurrentPage() {
        for mode in [BlindHomeSOSMode.localCall, .localCallSessionExpired] {
            XCTAssertNil(mode.orderSafetyRequestForGesture, "\(mode)")
        }
    }

    func testCloudModeGestureGoesStraightToTheLockedConfirmation() {
        XCTAssertEqual(BlindHomeSOSMode.cloudTrigger.orderSafetyRequestForGesture, .confirmEmergency)
    }
}
