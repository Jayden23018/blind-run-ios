import XCTest

// 紧急联系人页的操作步骤。主类已超长，新的辅助方法放这里。
extension blindRunUITests {
    func addContact(_ app: XCUIApplication, name: String, phone: String, relationship: String) {
        let addButton = app.buttons["新增紧急联系人"].firstMatch
        // 必须先滚：联系人到 4 个时列表已经把「新增」入口顶出屏幕，SwiftUI List 不渲染屏幕外的行，
        // 元素根本不在无障碍树里 —— 先断言存在会直接失败，而 scrollElementIntoView 又要求元素已存在。
        scrollUntilExists(addButton, app: app)
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        scrollElementIntoView(addButton, app: app)
        tapWhenHittableOrByCoordinate(addButton, app: app)
        XCTAssertTrue(app.navigationBars["新增紧急联系人"].waitForExistence(timeout: 8))

        let nameField = app.textFields["联系人姓名，必填"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        tapWhenHittableOrByCoordinate(nameField, app: app)
        nameField.typeText(name)

        let phoneField = app.textFields["联系人手机号，必填，11 位"].firstMatch
        tapWhenHittableOrByCoordinate(phoneField, app: app)
        phoneField.typeText(phone)

        let relationshipField = app.textFields["与联系人的关系，选填"].firstMatch
        tapWhenHittableOrByCoordinate(relationshipField, app: app)
        relationshipField.typeText(relationship)

        // 「保存」在导航栏，不会被键盘挡住，所以不需要先收键盘。
        tapWhenHittableOrByCoordinate(app.buttons["保存"].firstMatch, app: app)
        XCTAssertTrue(
            waitForElementToDisappear(app.navigationBars["新增紧急联系人"], timeout: 15),
            "保存成功后新增表单应自动关闭"
        )
    }

    /// 联系人行是整行按钮，读屏标签以姓名开头（#606）。
    func openContactEditor(_ app: XCUIApplication, named name: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name)，")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "列表里没有\(name)")
        scrollElementIntoView(row, app: app)
        tapWhenHittableOrByCoordinate(row, app: app)
        XCTAssertTrue(app.navigationBars["编辑紧急联系人"].waitForExistence(timeout: 8))
    }

    func deleteContact(_ app: XCUIApplication, named name: String) {
        openContactEditor(app, named: name)
        let deleteButton = app.buttons["删除\(name)"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 8))
        scrollElementIntoView(deleteButton, app: app)
        tapWhenHittableOrByCoordinate(deleteButton, app: app)

        let alert = app.alerts["确认删除联系人"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "删除是危险操作，必须二次确认")
        alert.buttons["确认删除"].tap()
        XCTAssertTrue(waitForElementToDisappear(alert, timeout: 8), "确认后弹窗应关闭")
    }

    /// 概览行在列表顶部，联系人多起来后会被滚出可见区、单元格被回收而查不到。
    /// 先直接等，等不到再往回滚一屏确认一次。
    func waitForContactSummary(_ app: XCUIApplication, _ expected: String) {
        let summary = app.staticTexts[expected].firstMatch
        if summary.waitForExistence(timeout: 12) { return }
        scrollableSurface(app).swipeDown()
        scrollableSurface(app).swipeDown()
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "紧急联系人概览应更新为「\(expected)」")
    }
}
