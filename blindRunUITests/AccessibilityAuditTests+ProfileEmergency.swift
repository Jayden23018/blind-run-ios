import XCTest

// #605：「我的」不再有常驻红条，二级页的底部按钮不再被盖住。#711 起列表里那一行紧急入口也删了，只剩全屏手势。
extension AccessibilityAuditTests {
    private func emergencyCallButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "紧急呼叫")).firstMatch
    }

    /// 回归：「保存」曾被红条盖住 56pt，点它落到紧急呼叫上（真机 frame y 715–779 对 723–787）。
    /// `isHittable` 不判遮挡，所以断言打在 frame 与点击结果上。
    /// #750 起账户页进来的资料页是查看页，「保存」在改文字的编辑页底部，量那一枚。
    @MainActor
    func testProfileSaveButtonIsNotCoveredByAnEmergencyBar() throws {
        let app = launchBlindHome()
        app.tabBars.firstMatch.buttons["我的"].tap(); app.openBlindAccountPage() // 个人资料在账户页（#711）
        let profileLink = app.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileLink.waitForExistence(timeout: 10))
        profileLink.tap()
        let nicknameRow = app.descendants(matching: .any)["blindProfileNicknameRow"].firstMatch
        XCTAssertTrue(nicknameRow.waitForExistence(timeout: 10), "查看页没有「昵称」")
        nicknameRow.tap()

        let save = app.buttons["blindProfileTextEditSave"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "编辑页没有「保存」")
        let sos = emergencyCallButton(app)
        if sos.exists {
            XCTAssertTrue(
                save.frame.intersection(sos.frame).isNull,
                "「保存」\(save.frame) 被紧急呼叫 \(sos.frame) 盖住"
            )
        }
        // #711 起资料页从账户页进入，标签栏跟着藏起来；藏了就判「保存」整个在屏内。
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : app.windows.firstMatch.frame.maxY
        XCTAssertLessThanOrEqual(save.frame.maxY, bottom, "「保存」压在标签栏上或伸出屏幕")

        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(
            app.sheets.firstMatch.waitForExistence(timeout: 2),
            "点「保存」弹出了拨号单，触点落在了紧急呼叫上"
        )
    }

    /// #603：「删除账户」曾整行藏在红条后面。审核指南 5.1.1(v) 要求账号删除入口能被找到。
    @MainActor
    func testDeleteAccountIsVisibleAboveTheTabBarAtTheBottomOfProfile() throws {
        let app = launchBlindHome()
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["blindAccountCardEntry"].firstMatch.waitForExistence(timeout: 10), "「我的」没有加载出来")
        // #711 起删除账户在账户页（「我的」→ 头像卡）。账户页藏标签栏，所以要验的是栏真的藏了、按钮整行露在屏幕里。
        app.openBlindAccountPage()
        app.swipeUp()
        app.swipeUp()
        let delete = app.buttons["删除账户"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "账户页没有删除账户")
        sleep(1)
        XCTAssertFalse(tabBar.exists, "账户页的标签栏没藏起来")
        XCTAssertTrue(delete.isHittable, "「删除账户」\(delete.frame) 点不到")
        XCTAssertLessThanOrEqual(delete.frame.maxY, app.windows.firstMatch.frame.maxY, "「删除账户」\(delete.frame) 伸出屏幕")
        let sos = emergencyCallButton(app)
        if sos.exists {
            XCTAssertTrue(delete.frame.intersection(sos.frame).isNull, "「删除账户」被紧急呼叫盖住")
        }
    }

    /// 负责人 2026-11-05（#711）：「盲人的“我的”界面不需要一个常驻的求助按钮」，整行删掉。
    /// 不陪跑、陪跑中两种状态下「我的」都不能再出现这一行；求助走 Magic Tap 和订单页（下面两条手势用例守着）。
    @MainActor
    func testProfileTabHasNoEmergencyRowWithOrWithoutARun() throws {
        let idle = launchBlindHome()
        idle.tabBars.firstMatch.buttons["我的"].tap()
        XCTAssertTrue(idle.buttons["blindAccountCardEntry"].firstMatch.waitForExistence(timeout: 10), "「我的」没有加载出来")
        XCTAssertFalse(idle.descendants(matching: .any)["blindProfileEmergencyRow"].firstMatch.exists, "不陪跑时「我的」还有紧急入口")
        XCTAssertFalse(emergencyCallButton(idle).exists, "不陪跑时「我的」还有「紧急呼叫」")
        idle.terminate()

        let running = launchToProfileDuringRun()
        XCTAssertTrue(running.buttons["blindAccountCardEntry"].firstMatch.waitForExistence(timeout: 10), "陪跑中「我的」没有加载出来")
        XCTAssertFalse(running.descendants(matching: .any)["blindProfileEmergencyRow"].firstMatch.exists, "陪跑中「我的」还有紧急入口")
        XCTAssertFalse(
            running.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "求助与安全")).firstMatch.exists,
            "陪跑中「我的」还有「求助与安全」"
        )
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

    /// 订单页藏标签栏，这是陪跑中读屏用户最常见的位置。请求要穿过已在栈里的订单页，不走推入那条路。
    @MainActor
    func testSOSGestureOnTheOrderPageReachesTheLockedConfirmation() throws {
        let app = launchToHomeDuringRun(extraEnvironment: ["AIDRUN_UI_TEST_SOS_GESTURE_ON_RESUME": "1"])
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "首页没有订单卡")
        card.tap()
        // v7 起订单页藏了系统导航栏（#917 / #918），用自带顶栏的返回键认订单页。
        let orderPage = app.buttons["blindOrderTopBarBackButton"].firstMatch
        XCTAssertTrue(orderPage.waitForExistence(timeout: 10), "没有进到订单页")

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(orderPage.waitForExistence(timeout: 10), "回到前台后不在订单页")
        let confirmation = app.alerts.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "是否确认进入求助状态")
        ).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 8), "停在订单页做手势后没有弹出二次确认")
    }

    @MainActor
    private func launchToProfileDuringRun(extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = launchToHomeDuringRun(extraEnvironment: extraEnvironment)
        app.tabBars.firstMatch.buttons["我的"].tap()
        return app
    }

    @MainActor
    private func launchToHomeDuringRun(extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "IN_PROGRESS", extraEnvironment: extraEnvironment)
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        if !app.tabBars.firstMatch.waitForExistence(timeout: 5), !card.exists {
            let back = app.buttons["返回"].firstMatch
            if back.waitForExistence(timeout: 10) { back.tap() }
        }
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15), "回不到带标签栏的页面")
        return app
    }
}
