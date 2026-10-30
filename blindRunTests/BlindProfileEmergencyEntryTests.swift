import XCTest
@testable import blindRun

/// #605：「我的」的紧急入口按模式分流。云端求助只能去订单页，本地拨号绝不碰订单页。
@MainActor
final class BlindProfileEmergencyEntryTests: XCTestCase {
    func testLocalCallStaysOnTheCurrentPageForBothEntries() {
        for mode in [BlindHomeSOSMode.localCall, .localCallSessionExpired] {
            XCTAssertNil(mode.orderSafetyRequestForGesture, "\(mode)")
            XCTAssertNil(mode.orderSafetyRequestForRow, "\(mode)")
        }
    }

    func testCloudModeGestureGoesStraightToTheLockedConfirmation() {
        XCTAssertEqual(BlindHomeSOSMode.cloudTrigger.orderSafetyRequestForGesture, .confirmEmergency)
    }

    func testCloudModeRowOpensTheSafetyHubInsteadOfSending() {
        XCTAssertEqual(BlindHomeSOSMode.cloudTrigger.orderSafetyRequestForRow, .safetyHub)
        XCTAssertEqual(BlindHomeSOSMode.cloudTrigger.profileRowTitle, EmergencySafetyCopy.hubTitle)
    }

    func testLocalCallRowNeverPretendsToSendHelp() {
        for mode in [BlindHomeSOSMode.localCall, .localCallSessionExpired] {
            XCTAssertEqual(mode.profileRowTitle, EmergencySafetyCopy.homeCallTitle)
            XCTAssertFalse(mode.profileRowTitle.contains("求助"), "\(mode)")
            XCTAssertTrue(mode.profileRowAccessibilityHint.contains("不会代你发送求助"), "\(mode)")
        }
    }
}
