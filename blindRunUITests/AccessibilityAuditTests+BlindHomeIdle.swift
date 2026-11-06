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
        XCTAssertTrue(waitForBookingScreen(app), "约跑页没起来")

        // 约跑页（#806）进来默认是「当前位置」，点「常用地点」才用首页设的默认地点。
        // 按标签找：根视图的 identifier 盖掉了子元素的（#814）。
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "常用地点")).firstMatch.tap()
        // 断约跑页上那句「家附近操场 · 见面点电话里再定」，不会被首页那行「从家附近操场出发」误判通过。
        let place = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "家附近操场 · ")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 10), "约跑页选「常用地点」后没用上首页设的默认地点")
        keepScreenshot(app, "idle-booking-with-default")
    }

    /// #807：「添加常用地点」不再进约跑表单，进一页「使用当前定位 + 搜索 + 最近跑过的地点」。
    func testBlindHomeAddFavoriteOpensItsOwnPage() {
        let app = launchReturningRunner(favorite: true)
        let row = element(app, "blindHomeStartPlaceRow")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let add = element(app, "blindHomeAddFavoritePlace")
        XCTAssertTrue(add.waitForExistence(timeout: 10))

        add.tap()

        XCTAssertTrue(app.navigationBars["添加常用地点"].waitForExistence(timeout: 10), "没进添加常用地点页")
        XCTAssertTrue(element(app, "blindFavoritePlaceUseCurrentLocation").waitForExistence(timeout: 5), "没有「使用当前定位」")
        XCTAssertFalse(element(app, "blindRunnerHomeStartBookingButton").exists)
        keepScreenshot(app, "favorite-place-add")

        // 用当前定位：不添加任何地点，直接回首页。
        element(app, "blindFavoritePlaceUseCurrentLocation").tap()
        XCTAssertTrue(element(app, "blindHomeStartPlaceRow").waitForExistence(timeout: 10), "选完没回首页")
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
