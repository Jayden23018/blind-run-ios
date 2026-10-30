import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长（同 `PrivacyAuthorizationUITests`）。
///
/// 守 #603：求助条占自己的高度，「我的」这一栈的内容不钻到它后面。
extension blindRunUITests {
    /// 「删除账户」是设置页最后一行，审核指南 5.1.1(v) 要求用户能找到。
    /// `tap()` 过不算数：藏在求助条后面时 XCUITest 照样点得中，人眼却看不见，所以断位置。
    @MainActor
    func testProfileTabLastRowScrollsClearOfTheSOSBar() throws {
        let app = launchProfileTab()
        openSettings(app)
        let deleteButton = app.buttons["删除账户"].firstMatch
        XCTAssertTrue(scrollUntilExists(deleteButton, app: app), "设置页滚到底也没有「删除账户」")
        app.swipeUp()
        app.swipeUp()

        let barTop = sosBarTop(app)
        XCTAssertTrue(deleteButton.isHittable, "滚到底后「删除账户」点不到")
        XCTAssertLessThanOrEqual(deleteButton.frame.maxY, barTop, "滚到底后「删除账户」仍有一截在求助条后面")
    }

    /// 根页和推出来的每一页共用同一个判据：滚动容器的底边不越过求助条顶边。
    /// 判容器而不判末行：末行随页面内容变，容器伸到条底下才是所有页共同的根因。
    @MainActor
    func testEveryPageInTheProfileTabStopsAboveTheSOSBar() throws {
        let app = launchProfileTab()
        openSettings(app)
        assertScrollContentStopsAboveSOSBar(app, page: "设置")

        for row in ["个人资料", "我的固定搭档", "我的邀请码", "隐私与授权", "实名认证", "使用帮助", "关于"] {
            tapNavigationRow(app, labelBeginsWith: row)
            // 等设置页离开界面树再量：push 动画途中 `collectionViews.firstMatch` 还是设置页那个列表。
            let settingsRow = app.buttons["blindInviteCodeSettingsEntry"]
            XCTAssertTrue(settingsRow.waitForNonExistence(timeout: 5), "「\(row)」页没有推出来")
            assertScrollContentStopsAboveSOSBar(app, page: row)
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5), "「\(row)」页没有返回按钮")
            back.tap()
            XCTAssertTrue(settingsRow.waitForExistence(timeout: 5), "从「\(row)」页回不到设置页")
        }
    }

    private func launchProfileTab() -> XCUIApplication {
        launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
    }

    private func sosBarTop(_ app: XCUIApplication) -> CGFloat {
        let bar = app.descendants(matching: .any)["blindTabBottomSOSBar"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "「我的」页没有常驻求助条")
        return bar.frame.minY
    }

    private func assertScrollContentStopsAboveSOSBar(_ app: XCUIApplication, page: String) {
        let barTop = sosBarTop(app)
        let scrollContent = [app.collectionViews.firstMatch, app.tables.firstMatch, app.scrollViews.firstMatch]
            .first { $0.waitForExistence(timeout: 2) }
        guard let scrollContent else {
            return XCTFail("「\(page)」页没有滚动容器")
        }
        XCTAssertLessThanOrEqual(scrollContent.frame.maxY, barTop, "「\(page)」页的内容钻到了求助条后面")
    }
}
