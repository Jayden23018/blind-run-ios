import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
extension blindRunUITests {
    /// #542（#407 第 1 项）：陪跑员跑步中按云端求助，而本机「精确位置」关着 —— 先申请一次临时精确位置、等满上限，
    /// 仍关着就**不发**，自动弹出只列 120 / 110 的本地拨号，并在页面上写出「求助未发出」。
    ///
    /// 守的是单测够不着的那一段：弹窗开关在 view model 上（`offersLocalCallAfterUnsentSOS`），而它在页面上
    /// 真的弹得出来 —— 审查担心求助面板收起与拨号框同一拍出现时 iOS 会丢掉其中一个。
    /// `AIDRUN_UI_TEST_PRECISE_LOCATION_OFF` 只改判定；真机此刻精确位置是开着的，所以系统不会弹临时精确位置窗，
    /// 这条要等满 15 秒（`EmergencyCoordinator.preciseLocationAnswerTimeout`）。
    @MainActor
    func testVolunteerCloudSOSWithPreciseLocationOffFallsBackToLocalCall() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            seedOrderStatus: "IN_PROGRESS"
        )
        // 开关只给这一条用：不往 `launchApp` 加参数（那个函数已超长），带上开关重启一次。
        app.terminate()
        app.launchEnvironment["AIDRUN_UI_TEST_PRECISE_LOCATION_OFF"] = "1"
        app.launch()

        let stats = app.descendants(matching: .any)["volunteerRunningStatsCard"].firstMatch
        XCTAssertTrue(stats.waitForExistence(timeout: 25), "冷启动没有直接进跑步中页")
        app.buttons["volunteerServiceSOSButton"].firstMatch.tap()
        let panel = app.descendants(matching: .any)["volunteerRunHelpPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "跑步中「求助」没有打开求助面板")
        let emergency = app.descendants(matching: .any)["volunteerRunHelpEmergency"].firstMatch
        XCTAssertTrue(emergency.waitForExistence(timeout: 5), "求助面板里没有云端「紧急求助」")
        emergency.tap()
        let confirmation = app.alerts["一键求助"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "云端求助没有二次确认")
        confirmation.buttons["确认求助"].firstMatch.tap()

        let medical = app.buttons["拨打120"].firstMatch
        XCTAssertTrue(medical.waitForExistence(timeout: 30), "精确位置关着、求助没发出去，却没弹出本地拨号")
        XCTAssertTrue(app.buttons["拨打110"].firstMatch.exists, "拨号框缺 110")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "求助没有发出去")).firstMatch.exists,
            "拨号框第一句要说清求助没有发出去"
        )
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "App 不会代你发送求助")).firstMatch.exists,
            "拨号框必须说清 App 不会代你发送求助"
        )
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "volunteer-sos-unsent-local-call"
        shot.lifetime = .keepAlways
        add(shot)

        // 关拨号框的写法与 `testVolunteerRunHelpPanelOffersLocalCallAfterTheTokenExpiresMidRun` 相同：
        // iOS 26 起它在 iPhone 上可能是没有「取消」的浮层，点屏幕下方空白处关闭。
        let cancel = app.buttons["取消"].firstMatch
        if cancel.exists {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        }
        let dialogGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: medical)
        wait(for: [dialogGone], timeout: 5)
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "未发出")).firstMatch.waitForExistence(timeout: 5),
            "页面上没写出「求助未发出」—— 关掉拨号框之后原因就看不到了"
        )
    }
}
