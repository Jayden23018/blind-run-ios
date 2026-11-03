import XCTest

/// 强制更新页（#526）。判定的主在单测 `AppUpdatePolicyTests`，这里守的是页面接线：
/// 盖得住、背后退出读屏树、紧急入口只拨号、订单进行中时不盖。
/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
extension blindRunUITests {
    /// Mock 的版本开关不往 `launchApp` 加参数（那个函数已超长），带上开关重启一次。
    private func relaunch(_ app: XCUIApplication, minVersion: String? = nil, latestVersion: String? = nil) {
        app.terminate()
        app.launchEnvironment["AIDRUN_MOCK_APP_MIN_VERSION"] = minVersion
        app.launchEnvironment["AIDRUN_MOCK_APP_LATEST_VERSION"] = latestVersion
        app.launch()
    }

    @MainActor
    func testAppUpdateGateCoversHomeAndOnlyOffersLocalDial() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "update-gate-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
        relaunch(app, minVersion: "99.0")

        let update = app.buttons["appUpdateRequiredUpdateButton"]
        XCTAssertTrue(update.waitForExistence(timeout: 8), "版本过低且没有订单时必须出现强制更新页")
        XCTAssertGreaterThanOrEqual(update.frame.height, 64)
        let call = app.buttons["appUpdateRequiredCallButton"]
        XCTAssertGreaterThanOrEqual(call.frame.height, 64)
        XCTAssertGreaterThanOrEqual(app.buttons["appUpdateRequiredRepeatButton"].frame.height, 64)

        // 系统模态与 overlay 都不会自动隔离：要断言 `.exists == false`（记忆 `hide-uikit-hosted-tree-from-accessibility`）。
        let homeTab = app.tabBars.buttons["首页"]
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: homeTab)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, "背后的标签栏必须退出读屏树")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "app-update-required-gate"
        shot.lifetime = .keepAlways
        add(shot)

        call.tap()
        let medical = app.buttons["拨打120"].firstMatch
        XCTAssertTrue(medical.waitForExistence(timeout: 5), "紧急呼叫要打开本地拨号单")
        XCTAssertTrue(app.buttons["拨打110"].firstMatch.exists)
    }

    /// 求助只在 `IN_PROGRESS` 走云端，订单页的入口不能被盖住。
    @MainActor
    func testAppUpdateGateStaysAwayDuringAnActiveRun() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "update-gate-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            seedOrderStatus: "IN_PROGRESS"
        )
        relaunch(app, minVersion: "99.0")

        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 8))
        // 等版本检查和订单查询都回来。
        let gate = app.buttons["appUpdateRequiredUpdateButton"]
        XCTAssertFalse(gate.waitForExistence(timeout: 4), "有进行中的订单时不能盖全屏")
    }

    @MainActor
    func testOptionalUpdatePromptDoesNotComeBackAfterClosing() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "update-gate-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
        relaunch(app, latestVersion: "99.0")

        let prompt = app.alerts["有新版本"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        prompt.buttons["以后再说"].tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 3))

        relaunch(app, latestVersion: "99.0")
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 8))
        XCTAssertFalse(prompt.waitForExistence(timeout: 4), "同一版本关闭后不再提示")
    }
}
