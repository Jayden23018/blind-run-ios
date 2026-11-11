import XCTest
@testable import blindRun

/// #813：约跑页点「开始找陪跑员」前，出发点能不能用当前位置。
/// 规格 `blind-precise-location-gate`「精确位置关闭时下单不用当前位置作出发点」。
final class BookingStartGateTests: XCTestCase {

    func testPreciseLocationOffWithCurrentLocationAsksForTemporaryPreciseLocation() {
        let gate = BookingStartGate.evaluate(usesCurrentLocation: true, isDenied: false, isPreciseLocationOff: true)
        XCTAssertEqual(gate, .askPreciseLocation)
    }

    func testDeniedPermissionNeverAsksForPreciseLocation() {
        // 权限被拒时系统不会再弹框：直接给提示。精确位置标志在被拒时也可能为真，被拒要优先。
        let gate = BookingStartGate.evaluate(usesCurrentLocation: true, isDenied: true, isPreciseLocationOff: true)
        XCTAssertEqual(gate, .blockedByDeniedLocation)
    }

    func testFavoritePlaceIsNeverBlockedWhateverTheLocationState() {
        for denied in [false, true] {
            for off in [false, true] {
                let gate = BookingStartGate.evaluate(usesCurrentLocation: false, isDenied: denied, isPreciseLocationOff: off)
                XCTAssertEqual(gate, .proceed, "denied=\(denied) preciseOff=\(off)")
            }
        }
    }

    func testPreciseLocationOnProceeds() {
        let gate = BookingStartGate.evaluate(usesCurrentLocation: true, isDenied: false, isPreciseLocationOff: false)
        XCTAssertEqual(gate, .proceed)
    }

    func testAlertsExplainTheReasonAndTheEmergencyCost() {
        for isDenied in [false, true] {
            let alert = BookingStartGateAlert.make(isDenied: isDenied)
            XCTAssertTrue(alert.message.contains("不能从当前位置出发"), "isDenied=\(isDenied)")
            XCTAssertTrue(alert.message.contains("紧急求助"), "isDenied=\(isDenied)")
            XCTAssertFalse(alert.message.contains("请选择出发地点"), "不能退回只说「请选择出发地点」")
        }
        XCTAssertTrue(BookingStartGateAlert.make(isDenied: false).message.contains("精确位置"))
        XCTAssertTrue(BookingStartGateAlert.make(isDenied: true).message.contains("打开定位"))
    }

    func testEntrySpeechReplacesCurrentLocationOnlyWhenLocationIsUnusable() {
        XCTAssertNil(BookingStartGateCopy.entrySpoken(isDenied: false, isPreciseLocationOff: false))
        let preciseOff = BookingStartGateCopy.entrySpoken(isDenied: false, isPreciseLocationOff: true)
        XCTAssertEqual(preciseOff?.contains("精确位置已关闭"), true)
        XCTAssertEqual(preciseOff?.contains("从当前位置出发"), false)
        XCTAssertEqual(BookingStartGateCopy.entrySpoken(isDenied: true, isPreciseLocationOff: false)?.contains("定位权限没开"), true)
    }

    func testDetailNoteOnlyWhenLocationIsUnusable() {
        XCTAssertNil(BookingStartGateCopy.detail(isDenied: false, isPreciseLocationOff: false))
        XCTAssertEqual(BookingStartGateCopy.detail(isDenied: false, isPreciseLocationOff: true)?.contains("精确位置已关闭"), true)
        XCTAssertEqual(BookingStartGateCopy.detail(isDenied: true, isPreciseLocationOff: true)?.contains("定位权限没开"), true)
    }
}
