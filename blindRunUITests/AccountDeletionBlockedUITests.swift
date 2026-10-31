import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
extension blindRunUITests {
    /// 后端 409 拦下删除（有未结束的紧急求助，#847）：弹「暂时不能删除账户」，只有「知道了」，
    /// 不给「重试」—— 立刻重试只会再被拒一次。文案内容的主在单测 `AccountDeletionBlockedTests`，
    /// 这里守的是视图有没有按 `offersRetry` 换按钮。
    @MainActor
    func testAuthLifecycleBlindDeletionBlockedByActiveEmergencyOffersNoRetry() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "blind-delete-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
        // Mock 的拦截开关只给这一条用：不往 `launchApp` 加参数（那个函数已超长），带上开关重启一次。
        app.terminate()
        app.launchEnvironment["AIDRUN_MOCK_DELETE_EMERGENCY_BLOCKED"] = "1"
        app.launch()

        openSettings(app)
        let deleteButton = app.buttons["删除账户"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        // 先滑到底，否则触点可能落在标签栏上。
        app.swipeUp()
        app.swipeUp()
        deleteButton.tap()

        XCTAssertTrue(app.alerts["确认删除账户"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["继续删除账户"].tap()
        XCTAssertTrue(app.alerts["最终确认删除账户"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["永久删除账户"].firstMatch.tap()

        let blocked = app.alerts["暂时不能删除账户"].firstMatch
        XCTAssertTrue(blocked.waitForExistence(timeout: 8), "被 409 拦下必须弹出拦截弹窗")
        XCTAssertTrue(blocked.buttons["知道了"].exists)
        XCTAssertFalse(blocked.buttons["重试"].exists, "立刻重试只会再被拒一次")
        XCTAssertFalse(app.alerts["删除账户失败"].exists)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "delete-account-blocked-by-active-emergency"
        shot.lifetime = .keepAlways
        add(shot)

        blocked.buttons["知道了"].tap()
        XCTAssertTrue(blocked.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["退出登录"].exists, "删除没成功就留在设置页、保持登录")
    }
}
