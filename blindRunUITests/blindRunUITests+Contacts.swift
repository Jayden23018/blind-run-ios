import XCTest

// 紧急联系人页的操作步骤。主类已超长，新的辅助方法放这里。
extension blindRunUITests {
    func addContact(_ app: XCUIApplication, name: String, phone: String, relationship: String) {
        // 「从通讯录添加」弹的是进程外的系统选择器，用例驱动不了，所以走「手动输入」（#746）。
        let addButton = app.buttons["手动输入新增紧急联系人"].firstMatch
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

        // 新增页只剩姓名、手机号（#807），「添加」贴在底部：先收键盘，免得按钮被键盘挡住。
        let dismissKeyboard = app.buttons["收起键盘"].firstMatch
        if dismissKeyboard.exists { dismissKeyboard.tap() }
        let formAddButton = app.descendants(matching: .any)["emergencyContactFormSave"].firstMatch
        XCTAssertTrue(formAddButton.waitForExistence(timeout: 5), "新增页底部没有「添加」")
        tapWhenHittableOrByCoordinate(formAddButton, app: app)
        XCTAssertTrue(
            waitForElementToDisappear(app.navigationBars["新增紧急联系人"], timeout: 15),
            "添加成功后新增页应自动退回列表"
        )

        // 关系不在新增页（#807），添加后到编辑页补。
        guard !relationship.isEmpty else { return }
        openContactEditor(app, named: name)
        chooseContactRelationship(app, relationship)
        let save = app.descendants(matching: .any)["emergencyContactFormSave"].firstMatch
        tapWhenHittableOrByCoordinate(save, app: app)
        XCTAssertTrue(
            waitForElementToDisappear(app.navigationBars["编辑紧急联系人"], timeout: 15),
            "保存成功后编辑页应自动退回列表"
        )
    }

    /// 关系改成选择页（#746）：点「关系」行，在列表里点预设，选完自动退回表单。
    func chooseContactRelationship(_ app: XCUIApplication, _ relationship: String) {
        // 手机号框还有焦点时，键盘上方那一栏正好盖在「关系」行上，点下去落在键盘区（#746 第一轮真机）。
        let dismissKeyboard = app.buttons["收起键盘"].firstMatch
        if dismissKeyboard.exists { dismissKeyboard.tap() }
        let relationshipRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "与联系人的关系，")
        ).firstMatch
        XCTAssertTrue(relationshipRow.waitForExistence(timeout: 5), "表单里没有「关系」行")
        tapWhenHittableOrByCoordinate(relationshipRow, app: app)
        XCTAssertTrue(app.navigationBars["关系"].waitForExistence(timeout: 8), "没进关系选择页")
        let preset = app.buttons[relationship].firstMatch
        scrollUntilExists(preset, app: app)
        tapWhenHittableOrByCoordinate(preset, app: app)
        XCTAssertTrue(
            app.buttons["与联系人的关系，\(relationship)"].firstMatch.waitForExistence(timeout: 8),
            "选完关系应回到表单，并显示「\(relationship)」"
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
