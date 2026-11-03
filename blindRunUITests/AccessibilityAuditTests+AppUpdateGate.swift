import XCTest

/// 强制更新页（#526）整页过审计。页面行为的用例在 `AppUpdateGateUITests.swift`。
extension AccessibilityAuditTests {

    @MainActor
    func testAppUpdateRequiredGatePassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome(extraEnvironment: ["AIDRUN_MOCK_APP_MIN_VERSION": "99.0"])
        let update = app.buttons["appUpdateRequiredUpdateButton"]
        XCTAssertTrue(update.waitForExistence(timeout: 20), "强制更新页没出来")
        waitUntilSettled(update)
        attachScreenshot(app, name: "app-update-required")
        try audit(app)
    }
}
