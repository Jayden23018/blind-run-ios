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

    /// 开着接单却被培训挡住时，停止接单要有一条**看得见**的路（#694 复核 A 级）。
    ///
    /// v3 去掉了向左滑停止，常规停止入口在接单页，而这一态进不了接单页（胶囊点进去是进度页）。
    /// 断「按钮在 + 点了真的停」：把那枚按钮删掉或改成不调 `setAvailability(false)`，这条都会红。
    @MainActor
    func testSwitchedOnButBlockedVolunteerCanStillStopFromHome() {
        let app = launchVolunteerHome(
            available: true,
            extraEnvironment: ["AIDRUN_MOCK_VOLUNTEER_TRAINING_COMPLETED": "0"]
        )
        let stop = app.buttons["volunteerHomeStopAvailabilityButton"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 25), "开着却被挡住时首页底部没有「停止接单」")
        stop.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: stop)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(app.alerts.count, 0, "停止接单不得弹任何挽留对话框")
    }
}
