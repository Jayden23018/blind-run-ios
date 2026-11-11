import XCTest

/// 联系客服入口、我的工单、陪跑员使用帮助（#656，OpenSpec `add-support-entry-and-volunteer-help`）。
///
/// 入口行 64pt、整页过审计、关键文案真的渲染出来。截图用于交付时给负责人看。
extension AccessibilityAuditTests {

    /// 盲人端：「我的」→ 联系客服（写字页，不带订单）→ 我的工单（Mock 里一条已回复、一条刚收到）。
    @MainActor
    func testBlindSupportEntryAndMyTicketsPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))
        tabBar.buttons["我的"].tap()

        let contact = revealSupportRow(app, "supportTicketSettingsEntry")
        XCTAssertGreaterThanOrEqual(contact.frame.height, 63.5, "联系客服入口可点高度不足 64pt：\(contact.frame)")
        XCTAssertEqual(contact.label, "联系客服", "入口名要与文案里指向它的名字一致")
        let tickets = revealSupportRow(app, "mySupportTicketsSettingsEntry")
        XCTAssertGreaterThanOrEqual(tickets.frame.height, 63.5)
        attachScreenshot(app, name: "blind-settings-support-rows")

        contact.tap()
        let editor = app.descendants(matching: .any)["supportTicketEditor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "没打开工单页")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "120")).firstMatch.exists,
            "写字之前要先说清有危险直接拨 120"
        )
        attachScreenshot(app, name: "blind-support-ticket-page")
        try audit(app)
        // #755：「关闭」降成一行蓝字，可点区仍要整行 64pt。
        let close = app.buttons["supportTicketClose"].firstMatch
        XCTAssertGreaterThanOrEqual(close.frame.height, 63.5, "「关闭」可点高度不足 64pt：\(close.frame)")
        close.tap()

        revealSupportRow(app, "mySupportTicketsSettingsEntry").tap()
        let row = app.descendants(matching: .any)["mySupportTicketRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "我的工单里没有工单行")
        let replied = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "客服回复：")).firstMatch
        XCTAssertTrue(replied.exists, "已回复的那条要把客服回复读出来")
        XCTAssertTrue(row.label.hasPrefix("已回复") || row.label.hasPrefix("已收到"), "状态要在一张工单的最前面念：\(row.label)")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "我的工单是二级页，要藏标签栏")
        attachScreenshot(app, name: "blind-my-support-tickets")
        try audit(app)
    }

    /// 陪跑员端：设置页有联系客服、我的工单、使用帮助；帮助页整页过审计。
    @MainActor
    func testVolunteerSettingsOffersSupportAndHelp() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchVolunteerHome()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 25))
        tabBar.buttons["我的"].tap()

        let contact = revealSupportRow(app, "supportTicketSettingsEntry")
        XCTAssertGreaterThanOrEqual(contact.frame.height, 63.5, "联系客服入口可点高度不足 64pt：\(contact.frame)")
        XCTAssertTrue(app.buttons["mySupportTicketsSettingsEntry"].exists)
        attachScreenshot(app, name: "volunteer-settings-support-rows")

        let help = revealSupportRow(app, "volunteerSettingsHelpLink")
        attachScreenshot(app, name: "volunteer-settings-help-entry")
        help.tap()
        let page = app.descendants(matching: .any)["volunteerHelpScrollView"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "没打开使用帮助")
        XCTAssertFalse(app.buttons["volunteerHelpDoneButton"].exists, "从设置进来不该有「知道了」")
        attachScreenshot(app, name: "volunteer-help-page")
        try audit(app)
        app.navigationBars.buttons.firstMatch.tap()

        revealSupportRow(app, "mySupportTicketsSettingsEntry").tap()
        XCTAssertTrue(app.descendants(matching: .any)["mySupportTicketRow"].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "volunteer-my-support-tickets")
        try audit(app)
    }

    /// 第一次打开出发前的订单页，自动弹一次使用帮助；按「知道了」后收起且不再弹。
    @MainActor
    func testVolunteerFirstRunHelpOpensOnTheOrderPageAndClosesWithGotIt() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchVolunteerHome(
            seedOrderStatus: "SCHEDULED_CONFIRMED",
            extraEnvironment: ["AIDRUN_UI_TEST_FORCE_VOLUNTEER_FIRST_RUN_HELP": "1"]
        )
        let page = app.descendants(matching: .any)["volunteerOrderFlowStatusCard"].firstMatch
        if !page.waitForExistence(timeout: 15) {
            let current = app.staticTexts["当前订单"].firstMatch
            if current.waitForExistence(timeout: 5) { current.tap() }
        }
        let done = app.buttons["volunteerHelpDoneButton"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 20), "第一次进订单页没有弹出使用帮助")
        XCTAssertGreaterThanOrEqual(done.frame.height, 43.5)
        attachScreenshot(app, name: "volunteer-first-run-help")
        try audit(app)

        done.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: done)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(page.waitForExistence(timeout: 10), "收起后应回到订单页")
        // 不再弹：标志只在按下「知道了」时写，写了就不再来。
        XCTAssertFalse(app.buttons["volunteerHelpDoneButton"].waitForExistence(timeout: 4), "按过「知道了」又弹出来了")
    }

    /// 拖到入口露出且不压在底栏后面。名字不与同文件里别的 `revealButton` 重，那些是 private。
    @discardableResult
    @MainActor
    private func revealSupportRow(_ app: XCUIApplication, _ identifier: String, maxDrags: Int = 24) -> XCUIElement {
        let element = app.buttons[identifier].firstMatch
        _ = element.waitForExistence(timeout: 8)
        for _ in 0..<maxDrags {
            let bar = app.tabBars.firstMatch
            let bottom = bar.exists ? bar.frame.minY : app.frame.maxY - 112
            if element.exists, element.isHittable, element.frame.maxY < bottom { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(identifier) 没有露出来")
        return element
    }
}
