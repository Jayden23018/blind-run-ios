import XCTest

extension AccessibilityAuditTests {
    /// 未完成培训时滑块滑不开、不说接单中，点按去接单前进度页（#658）。
    @MainActor
    func testBlockedSliderSaysWhyAndOpensReadinessProgress() {
        let app = launchVolunteerHome(
            available: true,
            extraEnvironment: ["AIDRUN_MOCK_VOLUNTEER_TRAINING_COMPLETED": "0"]
        )

        let entry = app.buttons["查看接单前进度"]
        XCTAssertTrue(entry.waitForExistence(timeout: 25), "被培训挡住时滑块应当通往进度页")
        XCTAssertFalse(app.buttons["进入接单"].exists, "接不到单时不能说进入接单")

        entry.tap()
        let title = app.descendants(matching: .any)["volunteerReadinessTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "点按后没有进入接单前进度页")
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerReadinessStep.training"].firstMatch.exists,
            "进度页要列出培训这一步"
        )
    }
}
