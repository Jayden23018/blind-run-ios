import XCTest

/// 版本更新弹窗（#526）。判定的主在单测 `AppUpdatePolicyTests` / `AppUpdateGateTests`，这里守的是接线。
/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
extension blindRunUITests {
    /// Mock 的版本开关不往 `launchApp` 加参数（那个函数已超长），带上开关重启一次。
    private func relaunch(
        _ app: XCUIApplication,
        minVersion: String? = nil,
        latestVersion: String? = nil,
        environment: [String: String] = [:]
    ) {
        app.terminate()
        app.launchEnvironment["AIDRUN_MOCK_APP_MIN_VERSION"] = minVersion
        app.launchEnvironment["AIDRUN_MOCK_APP_LATEST_VERSION"] = latestVersion
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
    }

    /// 只有一个按钮。按下后离开 App，回来仍低于最低版本就再弹。
    @MainActor
    func testRequiredUpdateAlertHasOneButtonAndReturnsAfterComingBack() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "update-gate-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
        relaunch(app, minVersion: "99.0")

        let alert = app.alerts["版本过低"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "版本过低且不在陪跑中时必须弹窗")
        XCTAssertEqual(alert.buttons.count, 1)
        let update = alert.buttons["去更新"]
        XCTAssertTrue(update.exists)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "app-update-required-alert"
        shot.lifetime = .keepAlways
        add(shot)

        update.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        app.activate()
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "回到 App 仍低于最低版本，必须再弹")
    }

    /// 陪跑中不弹，这一单离开同行三态后马上弹。
    /// 走现成的「陪跑员失联」接缝：启动 N 秒后订单从 `DRIVER_EN_ROUTE` 转 `REMATCHING`。
    @MainActor
    func testUpdateAlertWaitsForTheEscortToEnd() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "update-gate-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            seedOrderStatus: "DRIVER_EN_ROUTE"
        )
        relaunch(app, minVersion: "99.0", environment: ["AIDRUN_UI_TEST_VOLUNTEER_LOST_AFTER_SECONDS": "10"])

        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 8))
        let alert = app.alerts["版本过低"].firstMatch
        XCTAssertFalse(alert.waitForExistence(timeout: 5), "陪跑进行中不能弹")
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "陪跑结束后要弹，不用等回到前台")
    }

    @MainActor
    func testOptionalUpdateAlertDoesNotComeBackAfterLater() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "update-gate-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
        relaunch(app, latestVersion: "99.0")

        let alert = app.alerts["有新版本"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.buttons["去更新"].exists)
        alert.buttons["稍后"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))

        relaunch(app, latestVersion: "99.0")
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 8))
        XCTAssertFalse(alert.waitForExistence(timeout: 4), "同一版本点过「稍后」后不再提示")
    }
}
