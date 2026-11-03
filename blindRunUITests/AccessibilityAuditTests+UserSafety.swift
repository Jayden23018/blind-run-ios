import XCTest

/// 举报与拉黑（#524）：入口真的渲染出来、64pt、走得通，并且整页过审计。
extension AccessibilityAuditTests {

    /// 订单页 → 举报 → 不再匹配此人 → 「我的」→ 已拉黑的人 → 解除，一条路走完。
    @MainActor
    func testBlindReportAndBlockFlowPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "SCHEDULED_CONFIRMED")
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        if card.waitForExistence(timeout: 15) { card.tap() }

        let report = revealButton(app, "counterpartReportButton")
        XCTAssertGreaterThanOrEqual(report.frame.height, 63.5, "举报按钮可点高度不足 64pt：\(report.frame)")
        attachScreenshot(app, name: "blind-order-safety-actions")
        report.tap()

        XCTAssertTrue(app.descendants(matching: .any)["userReportSubmit"].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "blind-report-form")
        try audit(app)

        let submit = revealButton(app, "userReportSubmit")
        submit.tap()
        let problem = app.descendants(matching: .any)["userReportError"].firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "没选原因时要在屏幕上说")

        let reason = app.buttons["骚扰"].firstMatch
        for _ in 0..<4 where !reason.isHittable { app.swipeDown() }
        reason.tap()
        XCTAssertTrue(reason.isSelected, "读屏要能听出选中了哪一项")
        revealButton(app, "userReportSubmit").tap()

        let submitted = app.descendants(matching: .any)["userReportSubmitted"].firstMatch
        XCTAssertTrue(submitted.waitForExistence(timeout: 10), "提交成功要留在屏幕上")
        XCTAssertTrue(submitted.label.contains("工单号"), "没有工单号：\(submitted.label)")
        attachScreenshot(app, name: "blind-report-submitted")
        app.buttons["userReportDone"].firstMatch.tap()

        let block = revealButton(app, "counterpartBlockButton")
        XCTAssertGreaterThanOrEqual(block.frame.height, 63.5)
        block.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "不再匹配必须二次确认")
        attachScreenshot(app, name: "blind-block-confirm")
        alert.buttons["取消"].tap()
        XCTAssertTrue(block.waitForExistence(timeout: 5), "取消后入口还在")

        block.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["不再匹配"].tap()
        let done = app.descendants(matching: .any)["counterpartBlockSucceeded"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "结果要留在屏幕上")
        XCTAssertFalse(app.buttons["counterpartBlockButton"].exists, "已拉黑后这一页不再显示入口")

        // 订单页没有标签栏，退回首页才有。
        app.navigationBars.buttons.firstMatch.tap()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        tabBar.buttons["我的"].tap()
        let entry = revealButton(app, "blockedUsersSettingsEntry", maxDrags: 24)
        XCTAssertGreaterThanOrEqual(entry.frame.height, 63.5, "设置入口可点高度不足 64pt：\(entry.frame)")
        XCTAssertTrue(app.buttons["supportTicketSettingsEntry"].exists, "账号停用提示指向的「上报问题」要在这里")
        attachScreenshot(app, name: "blind-settings-safety-rows")
        entry.tap()

        let unblock = app.buttons["blockedUserUnblockButton"].firstMatch
        XCTAssertTrue(unblock.waitForExistence(timeout: 10), "刚拉黑的人要出现在列表里")
        XCTAssertGreaterThanOrEqual(unblock.frame.height, 63.5)
        XCTAssertFalse(unblock.label.contains("*"), "读屏不念掩码星号：\(unblock.label)")
        attachScreenshot(app, name: "blind-blocked-list")
        try audit(app)

        unblock.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "解除也要二次确认")
        alert.buttons["确认解除"].tap()
        let empty = app.descendants(matching: .any)["blockedUsersEmpty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "解除后列表要空")
        attachScreenshot(app, name: "blind-blocked-list-empty")
    }

    /// 跑步中这一屏只留求助（`CounterpartSafetyGate.orderPageTarget`）。
    @MainActor
    func testBlindRunningPageHasNoReportOrBlockEntry() throws {
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "IN_PROGRESS")
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        if card.waitForExistence(timeout: 10) { card.tap() }
        let hub = app.descendants(matching: .any)["blindOrderFlowSafetyHubButton"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 15), "没到跑步中页")
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(app.buttons["counterpartReportButton"].exists)
        XCTAssertFalse(app.buttons["counterpartBlockButton"].exists)
    }

    @MainActor
    func testVolunteerOrderPageOffersReportAndBlock() throws {
        let app = launchVolunteerHome(seedOrderStatus: "SCHEDULED_CONFIRMED")
        let page = app.descendants(matching: .any)["volunteerOrderFlowStatusCard"].firstMatch
        if !page.waitForExistence(timeout: 15) {
            let current = app.staticTexts["当前订单"].firstMatch
            if current.waitForExistence(timeout: 5) { current.tap() }
        }
        let report = revealButton(app, "counterpartReportButton")
        XCTAssertGreaterThanOrEqual(report.frame.height, 63.5)
        XCTAssertTrue(app.buttons["counterpartBlockButton"].exists)
        attachScreenshot(app, name: "volunteer-order-safety-actions")
        // 不在这里整页审计：这一页原有元素的审计红灯记在 issue 里，本用例只守新加的两枚按钮。
    }

    /// 记录详情：留言旁的举报带着这条留言，页底有两枚入口。
    @MainActor
    func testRunnerRecordDetailOffersMessageReport() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome(emptyOrders: false, extraEnvironment: Self.recordsSeed)
        _ = openRunnerRunRecordDetail(app)
        let report = revealButton(app, "messageReportButton", maxDrags: 12)
        XCTAssertGreaterThanOrEqual(report.frame.height, 63.5)
        attachScreenshot(app, name: "runner-record-message-report")
        try audit(app)
        report.tap()
        let quoted = app.descendants(matching: .any)["userReportQuotedMessage"].firstMatch
        XCTAssertTrue(quoted.waitForExistence(timeout: 10), "举报留言要显示原文")
        attachScreenshot(app, name: "runner-report-quoted-message")
        revealButton(app, "userReportClose").tap()
        XCTAssertGreaterThanOrEqual(revealButton(app, "counterpartBlockButton", maxDrags: 12).frame.height, 63.5)
    }

    /// 拖到按钮露出且不压在底栏后面。每次拖四分之一屏，免得把它拖过头。
    @discardableResult
    @MainActor
    private func revealButton(_ app: XCUIApplication, _ identifier: String, maxDrags: Int = 10) -> XCUIElement {
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
