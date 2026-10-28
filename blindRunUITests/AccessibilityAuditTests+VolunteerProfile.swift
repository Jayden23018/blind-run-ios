import XCTest

/// 志愿者「我的」首屏（`VolunteerProfileFirstScreen`）的常驻审计（#515）。
///
/// 这一屏此前**没有任何审计用例**：`testVolunteerHomeShowsTheIncentiveCard` 只断影响力区存在，不调 `audit`。
/// #508 拆文件时临时跑过一次，亮色默认 / 最大字号报 7 条对比度。亮 / 暗 × 默认 / 最大字号四遍，每遍截图。
extension AccessibilityAuditTests {

    @MainActor
    func testVolunteerProfileFirstScreenPassesAuditInLightDarkAndLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in Self.appearanceVariants {
            let app = launchVolunteerHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            let card = app.descendants(matching: .any)["volunteerHomeIncentiveCard"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 25), "\(variant.name)：「我的」首屏影响力区没出来")
            waitUntilSettled(card)
            attachScreenshot(app, name: "volunteer-profile-first-screen-\(variant.name)")
            try audit(app)
            app.terminate()
        }
    }
}
