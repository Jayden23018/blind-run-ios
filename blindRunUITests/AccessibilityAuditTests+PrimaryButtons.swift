import XCTest

/// 实心主按钮在亮 / 暗、默认 / 最大字号下的审计（#527）。
///
/// 起因：`.borderedProminent` 的白字压在环境 tint 上 —— 标签页外是没定义颜色的 `AccentColor`（系统蓝），
/// 标签页里是 `Flow.tabSelected`（暗色档纯白）。登录页「获取验证码」是自拼的 52pt 按钮，不可用态白字压
/// `systemGray4` 约 1.5:1。这一屏此前**没有任何审计用例**。
extension AccessibilityAuditTests {

    /// 亮 / 暗 × 默认 / 最大字号。整页审计的四种外观都从这里取。
    static let appearanceVariants: [(name: String, environment: [String: String], arguments: [String])] = [
        ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], []),
        ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"], []),
        ("ax5-light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"],
         ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
        ("ax5-dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"],
         ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
    ]

    /// 登录页两态：没填手机号（按钮不可用）与填好之后（可用）。按钮要 ≥64pt，两态都过审计。
    @MainActor
    func testLoginPassesAccessibilityAuditInLightDarkAndLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in Self.appearanceVariants {
            let app = launchLoggedOut(environment: variant.environment, arguments: variant.arguments)
            let phone = app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch
            XCTAssertTrue(phone.waitForExistence(timeout: 20), "\(variant.name)：登录页没起来")

            let request = app.buttons["获取验证码"].firstMatch
            scrollIntoView(request, in: app)
            XCTAssertFalse(request.isEnabled, "\(variant.name)：没填手机号时「获取验证码」应不可用")
            XCTAssertGreaterThanOrEqual(
                request.frame.height, Self.minimumBlindPrimaryButtonHeight,
                "\(variant.name)：「获取验证码」只有 \(request.frame.height)pt"
            )
            attachScreenshot(app, name: "login-request-disabled-\(variant.name)")
            try audit(app)

            phone.tap()
            phone.typeText("13800000001")
            let dismissKeyboard = app.buttons["收起键盘"].firstMatch
            if dismissKeyboard.waitForExistence(timeout: 2) { dismissKeyboard.tap() }
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "\(variant.name)：键盘没收起")
            scrollIntoView(request, in: app)
            XCTAssertTrue(request.isEnabled, "\(variant.name)：填好 11 位手机号后「获取验证码」应可用")
            attachScreenshot(app, name: "login-request-enabled-\(variant.name)")
            try audit(app)
            app.terminate()
        }
    }

    /// 下单页「精确位置关闭」那两枚按钮在暗色下的审计。它们原来是 `.borderedProminent`，
    /// 下单页在标签页里，暗色档 tint 是纯白 ⇒ 白底白字。
    @MainActor
    func testBookingLocationButtonsPassAccessibilityAuditInDarkMode() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome(extraEnvironment: [
            "AIDRUN_UI_TEST_PRECISE_LOCATION_OFF": "1",
            "AIDRUN_UI_TEST_COLOR_SCHEME": "dark",
        ])
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "下单页没起来")
        let stopVoice = app.descendants(matching: .any)["blindBookingStopVoiceButton"].firstMatch
        if stopVoice.exists { stopVoice.tap() }

        // 改用表单后落在最后一步，出发地点区块在第 1 步（同 `testBookingWithPreciseLocationOff…`）。
        let notice = app.descendants(matching: .any)["bookingLocationDegradationNotice"].firstMatch
        let previous = app.buttons["上一步"].firstMatch
        var backs = 0
        while !notice.waitForExistence(timeout: 3) && previous.exists && backs < 4 {
            previous.tap()
            backs += 1
        }
        let temporary = app.buttons["bookingRequestTemporaryPreciseLocationButton"].firstMatch
        XCTAssertTrue(temporary.waitForExistence(timeout: 10), "暗色下缺少「临时开启精确位置」")
        scrollIntoView(temporary, in: app)
        attachScreenshot(app, name: "booking-precise-location-off-dark")
        try audit(app)
    }

    // MARK: - 辅助

    @MainActor
    private func launchLoggedOut(environment: [String: String], arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        app.launchEnvironment["AIDRUN_UI_TEST_BLOCK_TEL_DIAL"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = "mock"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// 按元素在哪一侧决定往哪划，最多划 4 次。
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while element.exists && !element.isHittable && swipes < 4 {
            if element.frame.minY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
            swipes += 1
        }
    }
}
