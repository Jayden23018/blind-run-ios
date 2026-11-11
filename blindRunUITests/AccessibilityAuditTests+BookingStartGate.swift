import XCTest

// 约跑页精确位置关闭（#813，OpenSpec `booking-precise-location-system-prompt`）。
// 真机此刻精确位置开着，系统不弹临时精确位置框（申请回调带错误），所以「再申请一次仍关着」那条路在这里等价于「被拒」：
// 点提交 → 应用自己的短提示。系统框本身只能在精确位置真的关掉的真机上看，这里测不到。
@MainActor
extension AccessibilityAuditTests {
    func testBookingWithPreciseLocationOffShowsTheReasonInsteadOfJustAskingForAPlace() {
        let app = launchBlindHome(extraEnvironment: ["AIDRUN_UI_TEST_PRECISE_LOCATION_OFF": "1"])
        let start = element(app, "blindRunnerHomeStartBookingButton")
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "约跑页没起来")

        XCTAssertTrue(
            element(app, "matchFirstStartDetail").label.contains("精确位置已关闭"),
            "出发点卡底没说精确位置已关闭"
        )

        let submit = element(app, "matchFirstSubmitButton")
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        submit.tap()

        let alert = app.alerts["没有精确位置"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "精确位置关闭时点提交，没有出现原因提示")
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "不能从当前位置出发")).firstMatch.exists)
        XCTAssertTrue(alert.buttons["选常用地点"].exists)
        XCTAssertTrue(alert.buttons["去设置"].exists)
        XCTAssertFalse(app.staticTexts["请选择出发地点。"].exists, "不应退回只说「请选择出发地点」")
    }
}
