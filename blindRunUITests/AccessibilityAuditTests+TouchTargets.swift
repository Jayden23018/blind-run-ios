import XCTest

/// 盲人端次级控件的 64pt 触达（#527）。
///
/// 静态审查扫出 19 处低于 64pt：选择器（菜单 Picker 约 34pt、分段控件约 32pt）、并排的文字按钮、
/// 写死 `height: 44 / 52` 的图标按钮。守卫 `small-touch-target` 拦新写的，这里量改过的那几页并跑审计。
/// 资料页与紧急联系人页此前**没有任何审计用例**。
extension AccessibilityAuditTests {

    @MainActor
    func testBlindProfileControlsAreTallEnoughAndPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        // #750 起资料页只有查看页：没有档案时也一样渲染，不再有「完善信息」标题和右上角退出图标。
        let app = launchBlindHome()
        openBlindProfile(app)

        let escort = app.descendants(matching: .any)["blindProfileCard_escort"].firstMatch
        XCTAssertTrue(swipeUntilHittable(escort, in: app), "资料页没有「陪跑方式」卡")
        assertBlindTouchTarget(escort, name: "陪跑方式")
        XCTAssertFalse((escort.value as? String ?? "").isEmpty, "读屏没念卡片状态")
        attachScreenshot(app, name: "blind-profile-tether")
        try audit(app)

        let contactsRow = navigationRow(app, labelBeginsWith: "管理紧急联系人")
        XCTAssertTrue(swipeUntilHittable(contactsRow, in: app), "资料页没有「管理紧急联系人」")
        contactsRow.tap()
        XCTAssertTrue(app.navigationBars["紧急联系人"].waitForExistence(timeout: 12), "没进紧急联系人页")

        // 联系人是整行按钮（#606），行与编辑页底部的「删除」都要够 64pt。
        let contactRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "张三，")).firstMatch
        XCTAssertTrue(swipeUntilHittable(contactRow, in: app), "列表没有张三这一行")
        assertBlindTouchTarget(contactRow, name: "联系人行")
        attachScreenshot(app, name: "blind-emergency-contacts")
        // 已知红灯 #756：列表分「主联系人 / 其他联系人」两组后，默认字号下「其他联系人」「手动输入」被误报改不了字号
        // （AX5 那条用例同一页不报、字确实放大）。按负责人口径不加白名单；判回归比点名的元素，别比条数。
        try audit(app)

        // 添加区两行（#746）也是盲人端入口，同样 64pt。
        for (identifier, name) in [
            ("emergencyContactAddFromContacts", "从通讯录添加"),
            ("emergencyContactAddManually", "手动输入"),
        ] {
            let addRow = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(swipeUntilHittable(addRow, in: app), "添加区没有「\(name)」")
            assertBlindTouchTarget(addRow, name: name)
        }

        swipeUntilHittable(contactRow, in: app)
        contactRow.tap()
        // 关系改成选择页（#746）：表单里那一行与选择页本身都要过审计。
        let relationshipRow = app.descendants(matching: .any)["emergencyContactRelationshipRow"].firstMatch
        XCTAssertTrue(swipeUntilHittable(relationshipRow, in: app), "编辑页没有「关系」行")
        assertBlindTouchTarget(relationshipRow, name: "关系")
        let deleteButton = app.buttons["删除张三"].firstMatch
        XCTAssertTrue(swipeUntilHittable(deleteButton, in: app), "编辑页没有删除按钮")
        assertBlindTouchTarget(deleteButton, name: "删除")
        attachScreenshot(app, name: "blind-emergency-contact-editor")
        try audit(app)

        swipeUntilHittable(relationshipRow, in: app)
        relationshipRow.tap()
        XCTAssertTrue(app.navigationBars["关系"].waitForExistence(timeout: 8), "没进关系选择页")
        let checked = app.buttons["家人"].firstMatch
        XCTAssertTrue(checked.waitForExistence(timeout: 5), "关系选择页没有「家人」")
        XCTAssertTrue(checked.isSelected, "张三存的关系是「家人」，选择页应把它标为已选")
        assertBlindTouchTarget(checked, name: "关系选项")
        attachScreenshot(app, name: "blind-emergency-contact-relationship")
        try audit(app)
    }

    /// 紧急联系人页在最大字号下（#746 改版后第一次有这一档的用例）：列表、手动新增表单、关系选择页都过审计。
    @MainActor
    func testEmergencyContactsPagesPassAuditAtLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome(
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        openBlindProfile(app)
        let contactsRow = navigationRow(app, labelBeginsWith: "管理紧急联系人")
        XCTAssertTrue(swipeUntilHittable(contactsRow, in: app), "资料页没有「管理紧急联系人」")
        contactsRow.tap()
        XCTAssertTrue(app.navigationBars["紧急联系人"].waitForExistence(timeout: 12), "没进紧急联系人页")
        attachScreenshot(app, name: "blind-emergency-contacts-ax5")
        try audit(app)

        let manual = app.descendants(matching: .any)["emergencyContactAddManually"].firstMatch
        XCTAssertTrue(swipeUntilHittable(manual, in: app), "添加区没有「手动输入」")
        manual.tap()
        XCTAssertTrue(app.navigationBars["新增紧急联系人"].waitForExistence(timeout: 8), "没进新增表单")
        attachScreenshot(app, name: "blind-emergency-contact-form-ax5")
        // 新增表单里原有的「设为主联系人」开关等控件是 #676 记下的已知红灯，同 `testManualEmergencyContactFormHasOnlyNameAndPhoneAndPassesAudit`。
        // #807 去掉了那个开关；没真机跑过前沿用原口径。
        try auditKnownRedPage(app)

        // #807：关系只在编辑页。退回列表，进张三的编辑页再点「关系」。
        app.navigationBars["新增紧急联系人"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["紧急联系人"].waitForExistence(timeout: 8), "没退回列表")
        let contactRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "张三，")).firstMatch
        XCTAssertTrue(swipeUntilHittable(contactRow, in: app), "列表没有张三这一行")
        contactRow.tap()
        XCTAssertTrue(app.navigationBars["编辑紧急联系人"].waitForExistence(timeout: 8), "没进编辑页")
        let relationshipRow = app.descendants(matching: .any)["emergencyContactRelationshipRow"].firstMatch
        XCTAssertTrue(swipeUntilHittable(relationshipRow, in: app), "编辑页没有「关系」行")
        relationshipRow.tap()
        XCTAssertTrue(app.navigationBars["关系"].waitForExistence(timeout: 8), "没进关系选择页")
        attachScreenshot(app, name: "blind-emergency-contact-relationship-ax5")
        try audit(app)
    }

    /// 下单表单第 3 步（需求）的三个选择器：原来菜单 Picker 约 34pt、分段控件约 32pt。
    @MainActor
    func testBookingPreferencePickersAreTallEnoughAndPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "下单页没起来")
        let stopVoice = app.descendants(matching: .any)["blindBookingStopVoiceButton"].firstMatch
        if stopVoice.exists { stopVoice.tap() }

        // 改用表单后落在最后一步「确认」，退一步就是「需求」。
        let pace = app.buttons["配速偏好，选填"].firstMatch
        let previous = app.buttons["上一步"].firstMatch
        var backs = 0
        while !pace.waitForExistence(timeout: 3) && previous.exists && backs < 3 {
            previous.tap()
            backs += 1
        }
        for label in ["预计时长，选填", "配速偏好，选填", "路线偏好，选填"] {
            let picker = app.buttons[label].firstMatch
            XCTAssertTrue(swipeUntilHittable(picker, in: app), "第 3 步没有「\(label)」（按了 \(backs) 次上一步）")
            assertBlindTouchTarget(picker, name: label)
        }
        attachScreenshot(app, name: "booking-preference-pickers")
        try audit(app)
    }

    // MARK: - 辅助

    /// 首页 →「我的」→ 头像卡（账户页，#711）→ 个人资料。
    @MainActor
    private func openBlindProfile(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "标签栏没起来")
        tabBar.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 10), "没有进到「我的」"); app.openBlindAccountPage()
        let row = navigationRow(app, labelBeginsWith: "个人资料")
        XCTAssertTrue(swipeUntilHittable(row, in: app), "设置页没有「个人资料」")
        row.tap()
    }

    /// 设置 / 资料页的导航行：有的渲染成按钮，有的渲染成单元格（同 `blindRunUITests.tapNavigationRow`）。
    private func navigationRow(_ app: XCUIApplication, labelBeginsWith prefix: String) -> XCUIElement {
        // 按钮与单元格合在一个查询里：行在屏幕外时两者都不存在，先选定一种再划会划错对象。
        let predicate = NSPredicate(
            format: "(elementType == %d OR elementType == %d) AND label BEGINSWITH %@",
            XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue, prefix
        )
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func assertBlindTouchTarget(_ element: XCUIElement, name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(
            element.frame.height + Self.layoutRoundingTolerance, Self.minimumBlindPrimaryButtonHeight,
            "「\(name)」可点高度只有 \(element.frame.height)pt，低于盲人端 64pt", file: file, line: line
        )
    }

    /// `List` 不渲染屏幕外的行：先划到元素出现，再划到可点（记忆 `ui-test-tap-lands-on-persistent-sos-bar`）。
    private func swipeUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            if element.exists, element.frame.minY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
            swipes += 1
        }
        return element.exists && element.isHittable
    }
}
