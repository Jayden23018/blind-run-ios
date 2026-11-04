import XCTest

/// 陪跑员四个二级页（固定搭档与搭档详情、服务成就、评分、徽章，#697）。
///
/// Mock 数据：固定搭档 李*（连续 3 周、最好 7 周）、王*（只有收藏）、赵*（只有连续记录）。
extension AccessibilityAuditTests {
    /// 列表上没有任何操作按钮；整行进详情，举报 / 不再匹配 / 退出都在详情页，退出仍二次确认。
    @MainActor
    func testVolunteerPartnersMoveActionsIntoThePartnerPage() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchVolunteerHome()
        openVolunteerPartners(app)

        let first = app.buttons["volunteerPartnerRow.0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15), "固定搭档列表没有行")
        XCTAssertTrue(first.label.hasPrefix("李"), "第一行念出来要以名字开头：\(first.label)")
        XCTAssertFalse(first.label.contains("*"), "名字的掩码星号不许念出来：\(first.label)")
        XCTAssertFalse(app.buttons["volunteerPartnerOptOutButton"].exists, "退出不该再出现在列表上")
        XCTAssertFalse(app.buttons["counterpartReportButton"].exists, "举报不该再出现在列表上")
        XCTAssertFalse(app.buttons["counterpartBlockButton"].exists, "不再匹配不该再出现在列表上")
        attachScreenshot(app, name: "volunteer-partners-list")
        try audit(app)

        first.tap()
        let streak = app.descendants(matching: .any)["volunteerPartnerStreakCard"].firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 10), "搭档详情页没有连续陪跑卡")
        XCTAssertTrue(streak.label.contains("还差 4 周追平"), "格子对读屏是空的，进度要在那句话里：\(streak.label)")
        XCTAssertTrue(revealSecondaryButton(app, "counterpartReportButton").exists)
        XCTAssertTrue(app.buttons["counterpartBlockButton"].exists)
        let optOut = revealSecondaryButton(app, "volunteerPartnerOptOutButton")
        attachScreenshot(app, name: "volunteer-partner-detail")
        try audit(app)

        optOut.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "退出要二次确认")
        alert.buttons["确认退出"].tap()
        let notice = app.descendants(matching: .any)["volunteerPartnerOptOutNotice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "退出后要回到列表并显示结果")
    }

    /// 服务成就页：月度柱状图有一句总结；评分卡进评分页；「全部显示」进徽章页，7 枚都在、能点开。
    @MainActor
    func testVolunteerAchievementsOpenRatingsAndTheFullBadgeWall() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchVolunteerHome()
        openVolunteerAchievements(app)

        let chart = app.descendants(matching: .any)["volunteerServiceChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 15), "月度柱状图没出来")
        XCTAssertTrue(chart.label.hasPrefix("近 6 个月"), "柱状图要有一句总结：\(chart.label)")

        revealSecondaryButton(app, "volunteerAchievementsRatingCard").tap()
        let average = app.descendants(matching: .any)["volunteerRatingsAverage"].firstMatch
        XCTAssertTrue(average.waitForExistence(timeout: 10), "评分卡没进评分页")
        XCTAssertTrue(average.label.contains("满分 5 分"), "平均分要念清楚满分：\(average.label)")
        attachScreenshot(app, name: "volunteer-ratings")
        try audit(app)
        app.navigationBars.buttons.firstMatch.tap()

        revealSecondaryButton(app, "volunteerBadgeWallLink").tap()
        let wall = app.descendants(matching: .any)["volunteerBadgeWallView"].firstMatch
        XCTAssertTrue(wall.waitForExistence(timeout: 10), "全部显示没进徽章页")
        attachScreenshot(app, name: "volunteer-badge-wall")
        try audit(app)
        // 7 枚都画出来，没获得的也在（改版前只列已解锁的）。
        XCTAssertTrue(revealSecondaryButton(app, "volunteerBadge.HIGH_RATED").exists)
        revealSecondaryButton(app, "volunteerBadge.FIRST_RUN").tap()
        let sheet = app.descendants(matching: .any)["volunteerBadgeDetailSheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "点奖章没有弹层")
        attachScreenshot(app, name: "volunteer-badge-detail")
        try audit(app)
        app.buttons["volunteerBadgeDetailClose"].tap()
    }

    /// 截图用：四页（含搭档详情与奖章弹层）在默认字号截一遍，和稿子对照。
    /// 陪跑员端只测默认字号（负责人 2026-11-05 定）：最大字号（AX5）只在盲人端测。
    @MainActor
    func testVolunteerSecondaryPagesScreenshots() throws {
        for (suffix, arguments) in [("default", [String]())] {
            let app = launchVolunteerHome(extraArguments: arguments)
            openVolunteerPartners(app)
            let row = app.buttons["volunteerPartnerRow.0"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            captureScrolling(app, "secondary-partners-\(suffix)")
            revealSecondaryButton(app, "volunteerPartnerRow.0").tap()
            XCTAssertTrue(app.descendants(matching: .any)["volunteerPartnerDetailView"].firstMatch.waitForExistence(timeout: 10))
            captureScrolling(app, "secondary-partner-detail-\(suffix)")
            app.terminate()

            let achievements = launchVolunteerHome(extraArguments: arguments)
            openVolunteerAchievements(achievements)
            captureScrolling(achievements, "secondary-achievements-\(suffix)")
            revealSecondaryButton(achievements, "volunteerAchievementsRatingCard").tap()
            XCTAssertTrue(achievements.descendants(matching: .any)["volunteerRatingsAverage"].firstMatch.waitForExistence(timeout: 10))
            captureScrolling(achievements, "secondary-ratings-\(suffix)")
            achievements.navigationBars.buttons.firstMatch.tap()
            revealSecondaryButton(achievements, "volunteerBadgeWallLink").tap()
            XCTAssertTrue(achievements.descendants(matching: .any)["volunteerBadgeWallView"].firstMatch.waitForExistence(timeout: 10))
            captureScrolling(achievements, "secondary-badges-\(suffix)")
            revealSecondaryButton(achievements, "volunteerBadge.HOURS_10").tap()
            XCTAssertTrue(achievements.descendants(matching: .any)["volunteerBadgeDetailSheet"].firstMatch.waitForExistence(timeout: 10))
            sleep(1)
            attachScreenshot(achievements, name: "secondary-badge-detail-\(suffix)")
            achievements.terminate()
        }
    }

    // MARK: - 辅助

    /// 陪跑员「我的」标签就是设置页，固定搭档是其中一行。
    @MainActor
    private func openVolunteerPartners(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 25))
        tabBar.buttons["我的"].tap()
        revealSecondaryButton(app, "volunteerPartnersSettingsEntry", maxDrags: 24).tap()
        XCTAssertTrue(app.descendants(matching: .any)["volunteerPartnersView"].firstMatch.waitForExistence(timeout: 15))
    }

    /// 首屏「查看服务成就」入口（同 `achievementsEntry`，那一份是 private）。
    @MainActor
    private func openVolunteerAchievements(_ app: XCUIApplication) {
        let entry = app.descendants(matching: .any)["查看服务成就"].firstMatch
        var drags = 0
        while !entry.waitForExistence(timeout: drags == 0 ? 20 : 1) && drags < 8 {
            app.swipeUp()
            drags += 1
        }
        XCTAssertTrue(entry.exists, "首屏没有服务成就入口")
        entry.tap()
        let star = app.descendants(matching: .any)["volunteerStarLevelSection"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 15), "服务成就页没加载出来")
    }

    /// 首屏截一张，再往下滑截三张（SwiftUI 不渲染屏外的行，首屏图看不到下半页）。
    @MainActor
    private func captureScrolling(_ app: XCUIApplication, _ name: String) {
        sleep(1)
        attachScreenshot(app, name: "\(name)-1")
        for index in 2...4 {
            app.swipeUp()
            sleep(1)
            attachScreenshot(app, name: "\(name)-\(index)")
        }
        // 滑回顶部，后面的 reveal 从头找。
        for _ in 0..<4 { app.swipeDown() }
    }

    /// 拖到元素露出且不压在底栏后面（同 `revealButton`，那一份是 private）。
    @discardableResult
    @MainActor
    private func revealSecondaryButton(_ app: XCUIApplication, _ identifier: String, maxDrags: Int = 12) -> XCUIElement {
        let element = app.buttons[identifier].firstMatch
        _ = element.waitForExistence(timeout: 8)
        for _ in 0..<maxDrags {
            let bar = app.tabBars.firstMatch
            let bottom = bar.exists ? bar.frame.minY : app.frame.maxY - 60
            if element.exists, element.isHittable, element.frame.maxY < bottom { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(identifier) 没有露出来")
        return element
    }
}
