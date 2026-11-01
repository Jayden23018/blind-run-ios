import XCTest

// 盲人首页没有订单时：预约卡占满剩余高度，下方按用户状态放内容。
// OpenSpec `redesign-blind-home-idle-state`。
@MainActor
extension AccessibilityAuditTests {
    private func launchReturningRunner(period: String = "this", favorite: Bool = false) -> XCUIApplication {
        var environment = ["AIDRUN_UI_TEST_SEED_HOME_HISTORY": period]
        if favorite { environment["AIDRUN_UI_TEST_SEED_HOME_FAVORITE"] = "1" }
        return launchBlindHome(emptyOrders: false, extraEnvironment: environment)
    }

    private func keepScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func testBlindHomeNewRunnerCardFillsTheScreen() {
        let app = launchBlindHome()
        let card = element(app, "blindRunnerHomeStartBookingButton")
        XCTAssertTrue(card.waitForExistence(timeout: 20))

        XCTAssertGreaterThan(card.frame.height / app.windows.firstMatch.frame.height, 0.65)
        XCTAssertFalse(element(app, "blindHomeRunSummary").exists)
        XCTAssertFalse(element(app, "blindHomeStartPlaceRow").exists)
        keepScreenshot(app, "idle-new-runner")
    }

    func testBlindHomeUnverifiedRunnerGetsIdentityEntry() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome(extraEnvironment: ["AIDRUN_MOCK_BLIND_VERIFY_STATUS": "NOT_VERIFIED"])
        let later = app.buttons["稍后再说"]
        XCTAssertTrue(later.waitForExistence(timeout: 20))
        later.tap()
        let row = element(app, "blindHomeVerifyIdentityRow")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        keepScreenshot(app, "idle-unverified")
        try audit(app)

        row.tap()

        XCTAssertTrue(app.navigationBars["实名认证"].waitForExistence(timeout: 10))
    }

    func testBlindHomeReturningRunnerSeesRunsAndStartRow() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchReturningRunner()
        let summary = element(app, "blindHomeRunSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        XCTAssertTrue(summary.label.contains("跑了 3 次"), summary.label)
        XCTAssertEqual(element(app, "blindHomeStartPlaceRow").label, "用当前定位出发")
        keepScreenshot(app, "idle-returning")
        try audit(app)

        summary.tap()

        XCTAssertTrue(app.staticTexts["跑步记录"].waitForExistence(timeout: 10))
    }

    func testBlindHomeFallsBackToLastMonth() throws {
        let app = launchReturningRunner(period: "last")
        let summary = element(app, "blindHomeRunSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        let lastMonth = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -1, to: Date()))
        let month = Calendar.current.component(.month, from: lastMonth)

        XCTAssertTrue(summary.label.contains("\(month)月跑了"), summary.label)
    }

    func testBlindHomeDefaultStartPlaceCarriesIntoBooking() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchReturningRunner(favorite: true)
        let row = element(app, "blindHomeStartPlaceRow")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let favorite = app.buttons["家附近操场"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        keepScreenshot(app, "idle-start-place-page")
        try audit(app)

        favorite.tap()
        XCTAssertTrue(favorite.waitForNonExistence(timeout: 10))
        XCTAssertEqual(element(app, "blindHomeStartPlaceRow").label, "从家附近操场出发")
        keepScreenshot(app, "idle-default-favorite")

        element(app, "blindRunnerHomeStartBookingButton").tap()
        XCTAssertTrue(waitForBookingScreen(app), "下单页没起来")
        let stopVoice = element(app, "blindBookingStopVoiceButton")
        if stopVoice.waitForExistence(timeout: 5) { stopVoice.tap() }

        let place = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "家附近操场")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 10), "预约页没有带上默认出发地点")
        keepScreenshot(app, "idle-booking-with-default")
    }

    func testBlindHomeAddFavoriteOpensBookingForm() {
        let app = launchReturningRunner(favorite: true)
        let row = element(app, "blindHomeStartPlaceRow")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let add = element(app, "blindHomeAddFavoritePlace")
        XCTAssertTrue(add.waitForExistence(timeout: 10))

        add.tap()

        XCTAssertTrue(waitForBookingScreen(app), "添加常用地点没有进预约表单")
    }

    func testBlindHomeIdleRowsReachableAtLargestText() {
        let app = launchBlindHome(
            emptyOrders: false,
            extraEnvironment: ["AIDRUN_UI_TEST_SEED_HOME_HISTORY": "this"],
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        XCTAssertTrue(element(app, "blindRunnerHomeStartBookingButton").waitForExistence(timeout: 20))
        keepScreenshot(app, "idle-ax5-top")
        let row = element(app, "blindHomeStartPlaceRow")
        for _ in 0..<4 where !(row.exists && row.isHittable) {
            element(app, "blindRunnerHomeScrollView").swipeUp()
        }

        XCTAssertTrue(row.isHittable, "最大字号下出发地点行滚不出来")
        keepScreenshot(app, "idle-ax5-bottom")
    }
}
