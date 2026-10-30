import XCTest

// #605：「我的」不再有常驻红条。紧急入口是设置列表里的一行，二级页的底部按钮不再被盖住。
extension AccessibilityAuditTests {
    private func emergencyCallButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "紧急呼叫")).firstMatch
    }

    /// 回归：「保存」曾被红条盖住 56pt，点它落到紧急呼叫上（真机 frame y 715–779 对 723–787）。
    /// `isHittable` 不判遮挡，所以断言打在 frame 与点击结果上。
    @MainActor
    func testProfileSaveButtonIsNotCoveredByAnEmergencyBar() throws {
        let app = launchBlindHome()
        app.tabBars.firstMatch.buttons["我的"].tap()
        let profileLink = app.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileLink.waitForExistence(timeout: 10))
        profileLink.tap()

        let save = app.buttons["保存，保存资料"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "资料页没有「保存」")
        let sos = emergencyCallButton(app)
        if sos.exists {
            XCTAssertTrue(
                save.frame.intersection(sos.frame).isNull,
                "「保存」\(save.frame) 被紧急呼叫 \(sos.frame) 盖住"
            )
        }
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        XCTAssertLessThanOrEqual(save.frame.maxY, tabBarTop, "「保存」压在标签栏上")

        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(
            app.sheets.firstMatch.waitForExistence(timeout: 2),
            "点「保存」弹出了拨号单，触点落在了紧急呼叫上"
        )
    }

    @MainActor
    func testProfileEmergencyRowDialsLocallyWhenThereIsNoRun() throws {
        let app = launchBlindHome()
        app.tabBars.firstMatch.buttons["我的"].tap()
        let row = app.descendants(matching: .any)["blindProfileEmergencyRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "「我的」没有紧急入口")
        XCTAssertTrue(row.label.hasPrefix("紧急呼叫"), "没有陪跑时不能叫求助：\(row.label)")
        row.tap()
        XCTAssertTrue(app.buttons["拨打110"].firstMatch.waitForExistence(timeout: 5), "没有弹本地拨号单")
    }

    /// 回到订单页才看得到云端求助的结果面，留在「我的」发求助时失败无人知晓。
    @MainActor
    func testProfileEmergencyRowOpensTheOrderSafetyHubDuringARun() throws {
        let app = launchToProfileDuringRun()
        let row = app.descendants(matching: .any)["blindProfileEmergencyRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "「我的」没有紧急入口")
        XCTAssertTrue(row.label.hasPrefix("求助与安全"), "陪跑中这一行不是求助与安全：\(row.label)")
        row.tap()
        let hub = app.descendants(matching: .any)["blindSafetyHub"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 8), "按入口后没有打开订单页的求助中心")
    }

    /// 手势从别的 tab 触发时，订单页要被推上来并弹出逐字锁定的二次确认，不能被推入动画吞掉。
    @MainActor
    func testSOSGestureFromAnotherTabReachesTheLockedConfirmation() throws {
        let app = launchToProfileDuringRun(extraEnvironment: ["AIDRUN_UI_TEST_SOS_GESTURE_ON_PROFILE": "1"])
        let confirmation = app.alerts.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "是否确认进入求助状态")
        ).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 8), "手势之后没有弹出二次确认")
    }

    @MainActor
    private func launchToProfileDuringRun(extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "IN_PROGRESS", extraEnvironment: extraEnvironment)
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        if !app.tabBars.firstMatch.waitForExistence(timeout: 5), !card.exists {
            let back = app.buttons["返回"].firstMatch
            if back.waitForExistence(timeout: 10) { back.tap() }
        }
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "回不到带标签栏的页面")
        tabBar.buttons["我的"].tap()
        return app
    }
}
