import XCTest

/// #667：下单入口的开放范围告知。Mock 用 `AIDRUN_MOCK_LAUNCH_SCOPE` 演两种限制。
extension AccessibilityAuditTests {

    /// 暂不接受预约：点「预约」只看到后端那句告知和「返回首页」，约跑页不出现。
    @MainActor
    func testBlindBookingClosedShowsOnlyTheNoticeAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome(extraEnvironment: ["AIDRUN_MOCK_LAUNCH_SCOPE": "closed"])
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "盲人首页没起来")
        start.tap()

        let notice = app.descendants(matching: .any)["blindBookingClosedNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 20), "暂不接受预约时没有出现告知页")
        XCTAssertTrue(notice.label.contains("暂未开放"), "告知页没念后端那句：\(notice.label)")
        XCTAssertFalse(
            app.descendants(matching: .any)["matchFirstBookingPage"].firstMatch.exists,
            "暂不接受预约时还出现了约跑页"
        )
        attachScreenshot(app, name: "B-booking-closed")
        try audit(app)

        app.descendants(matching: .any)["blindBookingClosedBackHome"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "「返回首页」没有回到首页")
    }

    /// 起跑点不在开放范围：提交后屏幕上（也就是读屏能读到的）是后端那整句，仍停在约跑页。
    @MainActor
    func testBlindBookingOutsideOpenAreaShowsTheServerMessageOnTheBookingPage() throws {
        let message = "这个出发点不在开放范围内。目前只开放深圳市、杭州市，请换一个开放范围内的出发点"
        let app = launchBlindHome(extraEnvironment: ["AIDRUN_MOCK_CREATE_ORDER_REJECT": "ORDER_OUTSIDE_OPEN_AREA"])
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "盲人首页没起来")
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "约跑页没起来")

        // 按读屏标签前缀找：约跑页根视图的 identifier 会盖掉子元素的（记忆 accessibility-identifier-overwrites-children）。
        let submit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "开始找陪跑员")).firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "约跑页没有「开始找陪跑员」")
        XCTAssertTrue(submit.isEnabled, "提交按钮灰着：没有默认选中的时段")
        submit.tap()

        let error = app.staticTexts[message].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10), "读屏读不到后端那整句 message")
        XCTAssertTrue(waitForBookingScreen(app, timeout: 2), "被拒后离开了约跑页")
        attachScreenshot(app, name: "B-booking-outside-area-rejected")
    }
}
