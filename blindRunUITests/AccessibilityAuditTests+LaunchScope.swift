import XCTest

/// #667：下单入口的开放范围告知。Mock 用 `AIDRUN_MOCK_LAUNCH_SCOPE` 演两种限制。
extension AccessibilityAuditTests {

    /// 暂不接受预约：点「预约」只看到后端那句告知和「返回首页」，表单不出现，语音向导不启动。
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
        for id in ["blindBookingVoiceOrderButton", "blindBookingFinishSpeakingSurface", "blindBookingStopVoiceButton"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].firstMatch.exists, "暂不接受预约时还出现了下单页的 \(id)")
        }
        attachScreenshot(app, name: "B-booking-closed")
        try audit(app)

        app.descendants(matching: .any)["blindBookingClosedBackHome"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "「返回首页」没有回到首页")
    }

    /// 只开放部分城市和时段：表单显示后端的开放城市句（语音进来再改用表单时停在复核步，那一步同样有）；
    /// 演示坐标（北京）在范围外，前面说一句「不在开放范围内」。
    @MainActor
    func testBlindBookingRestrictedShowsTheAreaHintBeforeSubmitting() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome(extraEnvironment: ["AIDRUN_MOCK_LAUNCH_SCOPE": "restricted"])
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "盲人首页没起来")
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "有限制但开放时，下单页应照常起来")
        let stopVoice = app.descendants(matching: .any)["blindBookingStopVoiceButton"].firstMatch
        if stopVoice.waitForExistence(timeout: 5) { stopVoice.tap() }

        let notice = app.descendants(matching: .any)["blindBookingLaunchAreaNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "提交前看不到开放城市提示")
        XCTAssertTrue(notice.label.contains("目前只开放深圳市、杭州市"), "提示不是后端那句：\(notice.label)")
        attachScreenshot(app, name: "B-booking-restricted")
        try audit(app)
    }
}
