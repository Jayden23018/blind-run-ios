import XCTest

extension blindRunUITests {
    // MARK: - 紧急联系人 helpers

    /// Mock 种子联系人（`MockAPIClient.seedDemoData`）：张三 / 13900139001 / 家人 / 主联系人。
    static let seededContactSummary = "共 1 位紧急联系人，最多 5 位。主联系人是张三。"

    func launchBlindContactsApp() -> XCUIApplication {
        launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
    }

    /// 首页 → 设置 → 个人资料 → 管理紧急联系人。
    ///
    /// 设置页没有「紧急联系人」直达行，管理页挂在个人资料页下面，所以是三跳。
    func openContacts(_ app: XCUIApplication) {
        openSettings(app)
        tapNavigationRow(app, labelBeginsWith: "个人资料")
        tapNavigationRow(app, labelBeginsWith: "管理紧急联系人")
        XCTAssertTrue(
            app.navigationBars["紧急联系人"].waitForExistence(timeout: 12),
            "应已进入紧急联系人管理页"
        )
    }

    func replaceText(in field: XCUIElement, with newValue: String, app: XCUIApplication) {
        tapWhenHittableOrByCoordinate(field, app: app)
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(newValue)
    }

    /// List 里的 `NavigationLink` 可能暴露成 button 也可能暴露成 cell，两种都试。
    func tapNavigationRow(_ app: XCUIApplication, labelBeginsWith prefix: String) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 10) {
            scrollElementIntoView(button, app: app)
            tapWhenHittableOrByCoordinate(button, app: app)
            return
        }
        let cell = app.cells.matching(predicate).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "未找到以「\(prefix)」开头的入口")
        scrollElementIntoView(cell, app: app)
        tapWhenHittableOrByCoordinate(cell, app: app)
    }

    /// 把控件滚进可见区。判据是"中心点落在可见区内"而不是 `isHittable`：
    /// 禁用态的按钮永远不 hittable，用 `isHittable` 会让上限用例白白滑满 maxSwipes 次。
    /// 在惰性渲染的列表里把元素**滚到渲染出来**。
    ///
    /// 与 `scrollElementIntoView` 的分工：那个第一行就是 `guard element.exists else { return }`，
    /// 只能处理「已在无障碍树里、但不在可视区」；而 SwiftUI 的 List 对屏幕外的行根本不渲染，
    /// 元素压根不在树里，`exists` 为 false，那个 helper 会直接放弃、`waitForExistence` 也永远等不到。
    /// 联系人列表随数量增长会把下方的「新增」入口顶出屏幕，必须先滚动才谈得上断言存在。
    @discardableResult
    func scrollUntilExists(_ element: XCUIElement, app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        if element.exists { return true }
        for _ in 0..<maxSwipes {
            scrollableSurface(app).swipeUp()
            if element.exists { return true }
        }
        return element.exists
    }

    func scrollableSurface(_ app: XCUIApplication) -> XCUIElement {
        for candidate in [
            app.collectionViews.firstMatch,
            app.tables.firstMatch,
            app.scrollViews.firstMatch
        ] where candidate.exists {
            return candidate
        }
        return app
    }

    func assertLogoutRequiresConfirmation(_ app: XCUIApplication) {
        let logoutButton = app.buttons["退出登录"].firstMatch
        // 退出登录在列表最后：`List` 不渲染屏幕外的行，不滚它连无障碍树里都没有。
        // 已经在屏上时 `scrollUntilExists` 第一行就返回，零开销。
        // 这里原本还跟一句 `waitForExistence(timeout: 10)`：上一行已断言存在，它只会白等约 1 秒。
        XCTAssertTrue(scrollUntilExists(logoutButton, app: app), "设置页滚到底也没有「退出登录」")
        XCTAssertTrue(scrollElementIntoView(logoutButton, app: app), "「退出登录」滚不出求助条")
        logoutButton.tap()
        let confirmAlert = app.alerts["确认退出"].firstMatch
        XCTAssertTrue(confirmAlert.exists || confirmAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["确认退出"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)
    }
}
