import XCTest

/// 盲人端个人资料重做（#750，定稿 `docs/ui/mockups/blind-profile-edit-20261105/`）：
/// 查看页、选择页、文字编辑页，各在亮 / 暗 / 最大字号下截图并整页审计。盲人端要测最大字号。
private let blindProfileVariants: [(name: String, environment: [String: String], arguments: [String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], []),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"], []),
    ("ax5-light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
]

private let guideNoteSample = "我习惯你在我左边，转弯前提前说一声"

extension AccessibilityAuditTests {

    /// 账户页进来的查看页：组标题按「陪跑员什么时候看得到」写、没有底部「保存」、每行 64pt；
    /// 改「给陪跑员的话」走编辑页，存上后回到查看页那一行显示原文；改引导方式走选择页，当场保存。
    @MainActor
    func testBlindProfileOverviewChoiceAndEditPagesPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in blindProfileVariants {
            let app = launchBlindHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            openProfileOverview(app, variant: variant.name)
            try checkGuideNoteEditPage(app, variant: variant.name)
            try checkProfileOverview(app, variant: variant.name)
            try checkTetherChoicePage(app, variant: variant.name)
            app.terminate()
        }
    }

    // MARK: - 分步检查

    @MainActor
    private func openProfileOverview(_ app: XCUIApplication, variant: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "\(variant)：标签栏没起来")
        tabBar.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 10), "\(variant)：没进到「我的」")
        app.openBlindAccountPage()
        let entry = app.buttons["个人资料"].firstMatch
        XCTAssertTrue(scrollUntilVisible(entry, in: app), "\(variant)：账户页没有「个人资料」")
        entry.tap()
        XCTAssertTrue(app.navigationBars["个人资料"].waitForExistence(timeout: 10), "\(variant)：没进到个人资料")
    }

    @available(iOS 17.0, *)
    @MainActor
    private func checkGuideNoteEditPage(_ app: XCUIApplication, variant: String) throws {
        let row = app.descendants(matching: .any)["blindProfileGuideNoteRow"].firstMatch
        XCTAssertTrue(scrollUntilVisible(row, in: app), "\(variant)：查看页没有「给陪跑员的话」")
        XCTAssertEqual(row.value as? String, "未填写", "\(variant)：种子档案没写这段，应念「未填写」")
        row.tap()
        XCTAssertTrue(app.navigationBars["给陪跑员的话"].waitForExistence(timeout: 8), "\(variant)：没进编辑页")
        let field = app.descendants(matching: .any)["blindProfileTextEditField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(variant)：编辑页没有输入框")
        field.tap()
        field.typeText(guideNoteSample)
        // 剩余字数跟着草稿走：17 个字 ⇒ 还能写 63 个字（定稿上的那句）。
        let footnote = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "最多 80 个字，还能写 63 个字")).firstMatch
        XCTAssertTrue(footnote.waitForExistence(timeout: 5), "\(variant)：剩余字数没跟着输入变")
        let save = app.buttons["blindProfileTextEditSave"].firstMatch
        XCTAssertGreaterThanOrEqual(save.frame.height, 63.5, "\(variant)：「保存」不足 64pt：\(save.frame)")
        // 截图前收起键盘：键盘不是本页的东西，盖住一半也审不到底部按钮。
        app.navigationBars["给陪跑员的话"].tap()
        attachScreenshot(app, name: "blind-profile-edit-\(variant)")
        try audit(app)

        save.tap()
        XCTAssertTrue(app.navigationBars["个人资料"].waitForExistence(timeout: 10), "\(variant)：存上之后没回到查看页")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, guideNoteSample, "\(variant)：查看页那一行没显示刚存的原文")
    }

    @available(iOS 17.0, *)
    @MainActor
    private func checkProfileOverview(_ app: XCUIApplication, variant: String) throws {
        for _ in 0..<6 { app.swipeDown() }
        XCTAssertFalse(app.buttons["保存，保存资料"].firstMatch.exists, "\(variant)：查看页不该有底部「保存」")
        let nickname = app.descendants(matching: .any)["blindProfileNicknameRow"].firstMatch
        XCTAssertTrue(nickname.waitForExistence(timeout: 5), "\(variant)：查看页没有「昵称」")
        XCTAssertEqual(nickname.value as? String, "测试盲人")
        XCTAssertGreaterThanOrEqual(nickname.frame.height, 63.5, "\(variant)：昵称行不足 64pt：\(nickname.frame)")
        for title in ["派单时，陪跑员就会看到", "接单后，陪跑员才看到"] {
            XCTAssertTrue(scrollUntilVisible(app.staticTexts[title].firstMatch, in: app), "\(variant)：没有组标题「\(title)」")
        }
        for _ in 0..<6 { app.swipeDown() }
        attachScreenshot(app, name: "blind-profile-overview-\(variant)")
        try audit(app)

        let contactsRow = app.descendants(matching: .any)["blindProfileEmergencyContactsRow"].firstMatch
        XCTAssertTrue(scrollUntilVisible(contactsRow, in: app), "\(variant)：查看页没有紧急联系人那一行")
        XCTAssertEqual(contactsRow.label, "管理紧急联系人")
        XCTAssertEqual(contactsRow.value as? String, "1 位，主联系人是张三", "\(variant)：紧急联系人摘要不对")
        XCTAssertGreaterThanOrEqual(contactsRow.frame.height, 63.5, "\(variant)：紧急联系人行不足 64pt")
        attachScreenshot(app, name: "blind-profile-overview-bottom-\(variant)")
        try audit(app)
        for _ in 0..<6 { app.swipeDown() }
    }

    @available(iOS 17.0, *)
    @MainActor
    private func checkTetherChoicePage(_ app: XCUIApplication, variant: String) throws {
        let tetherRow = app.descendants(matching: .any)["blindProfileTetherPreferencePicker"].firstMatch
        XCTAssertTrue(scrollUntilVisible(tetherRow, in: app), "\(variant)：查看页没有「希望怎么被引导」")
        tetherRow.tap()
        XCTAssertTrue(app.navigationBars["希望怎么被引导"].waitForExistence(timeout: 8), "\(variant)：没进选择页")
        for title in ["还没决定", "牵引绳", "搀扶", "仅语言引导"] {
            let choice = app.buttons[title].firstMatch
            XCTAssertTrue(scrollUntilVisible(choice, in: app), "\(variant)：选择页没有「\(title)」")
            XCTAssertGreaterThanOrEqual(choice.frame.height, 63.5, "\(variant)：「\(title)」不足 64pt：\(choice.frame)")
        }
        for _ in 0..<4 { app.swipeDown() }
        app.buttons["牵引绳"].firstMatch.tap() // 种子档案已是牵引绳：只念「现在就是」，不发请求
        XCTAssertFalse(
            app.descendants(matching: .any)["blindProfileSavedNotice"].firstMatch.waitForExistence(timeout: 2),
            "\(variant)：点已选中的那项不该保存"
        )
        let armHold = app.buttons["搀扶"].firstMatch
        armHold.tap()
        let saved = app.descendants(matching: .any)["blindProfileSavedNotice"].firstMatch
        XCTAssertTrue(scrollUntilVisible(saved, in: app), "\(variant)：选完没出「已保存」")
        XCTAssertEqual(saved.label, "已保存：搀扶")
        XCTAssertTrue(armHold.isSelected, "\(variant)：对勾没移到「搀扶」")
        attachScreenshot(app, name: "blind-profile-choice-\(variant)")
        try audit(app)
    }

    /// 滚到元素出现在窗口里（`List` / `ScrollView` 不渲染屏外的行，断言前先滚）。最多上划 8 次。
    @MainActor
    @discardableResult
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch.frame
        for _ in 0..<8 {
            if element.exists, window.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
                return true
            }
            app.swipeUp()
        }
        return element.exists && window.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
    }
}
