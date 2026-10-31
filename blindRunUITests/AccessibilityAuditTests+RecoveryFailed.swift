import XCTest

/// 启动恢复失败页（`rootRoute.recoveryFailed`）：「退出登录」先确认再退（#561），整页过审计。
///
/// 走 Mock 接缝 `AIDRUN_MOCK_RESTORE_SESSION_FAILURE`：`/api/auth/me` 抛断网错误，会话校验停在 `.validationFailed`。
/// 此前这一页没有任何用例，按下「退出登录」直接退出也没人发现。
extension AccessibilityAuditTests {

    @MainActor
    func testRecoveryFailedLogoutAsksForConfirmationAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        // 默认那一下点在顶部（这一页那里只有图标），顺带触发系统权限弹窗的 interruption monitor。
        let app = launchBlindHome(extraEnvironment: ["AIDRUN_MOCK_RESTORE_SESSION_FAILURE": "1"])
        let page = app.descendants(matching: .any)["rootRoute.recoveryFailed"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 20), "启动恢复失败页没出来")
        waitUntilSettled(page)
        attachScreenshot(app, name: "recovery-failed")
        try audit(app)

        let logout = app.buttons["recoveryFailedLogoutButton"]
        let alert = app.alerts["确认退出"]
        let loginRoute = app.descendants(matching: .any)["rootRoute.unauthenticated"].firstMatch
        XCTAssertTrue(logout.waitForExistence(timeout: 5), "恢复失败页没有「退出登录」")
        logout.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "按下「退出登录」没有先弹确认")
        XCTAssertFalse(loginRoute.exists, "还没确认就退到了登录页")

        alert.buttons["取消"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5), "取消后没有留在恢复失败页")
        XCTAssertFalse(loginRoute.exists, "点了取消仍被退出")

        logout.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "第二次按「退出登录」没有弹确认")
        alert.buttons["确认退出"].tap()
        XCTAssertTrue(loginRoute.waitForExistence(timeout: 15), "确认退出后没有回到登录页")
    }
}
