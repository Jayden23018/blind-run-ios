import XCTest

/// 盲人端个人资料核对清单（#812，定稿 `docs/ui/mockups/blind-profile-checklist-20261106/`）：
/// 清单页、一题一屏的弹层（单选、多选、补充说明），各在亮 / 暗 / 最大字号下截图并整页审计。盲人端要测最大字号。
private let blindProfileVariants: [(name: String, environment: [String: String], arguments: [String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], []),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"], []),
    ("ax5-light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
]

private let supplementSample = "我习惯陪跑员在我左侧"

extension AccessibilityAuditTests {

    /// 账户页进来的清单页：分「未设置 / 已设置」两组、没有底部「保存」、卡片与昵称入口 64pt；
    /// 「途中提示」走三题弹层，存上后卡片念「已保存」；「陪跑方式」预选现有答案，改一项后整张卡保存。
    @MainActor
    func testBlindProfileOverviewChoiceAndEditPagesPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in blindProfileVariants {
            let app = launchBlindHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            openProfileOverview(app, variant: variant.name)
            try checkGuideNoteFlow(app, variant: variant.name)
            try checkProfileOverview(app, variant: variant.name)
            try checkEscortFlow(app, variant: variant.name)
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

    /// 「途中提示」三题：单选没选时「继续」不可用；多选可不选；补充说明的剩余字数把已选说法算进去。
    @available(iOS 17.0, *)
    @MainActor
    private func checkGuideNoteFlow(_ app: XCUIApplication, variant: String) throws {
        let card = app.descendants(matching: .any)["blindProfileCard_guideNote"].firstMatch
        XCTAssertTrue(scrollUntilVisible(card, in: app), "\(variant)：清单页没有「途中提示」")
        XCTAssertEqual(card.value as? String, "尚未设置", "\(variant)：种子档案没写这段，应念「尚未设置」")
        XCTAssertGreaterThanOrEqual(card.frame.height, 63.5, "\(variant)：卡片不足 64pt：\(card.frame)")
        card.tap()

        let title = app.descendants(matching: .any)["blindProfileFlowQuestionTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), "\(variant)：没弹出第 1 题")
        XCTAssertEqual(title.label, "第 1 题，共 3 题，路况播报")
        let advance = app.buttons["blindProfileFlowContinue"].firstMatch
        XCTAssertFalse(advance.isEnabled, "\(variant)：没选时「继续」应不可用")
        XCTAssertGreaterThanOrEqual(advance.frame.height, 63.5, "\(variant)：「继续」不足 64pt：\(advance.frame)")
        attachScreenshot(app, name: "blind-profile-single-\(variant)")
        try audit(app)

        app.buttons["blindProfileOption_guideDetail_0"].firstMatch.tap()
        advance.tap()
        let firstCue = app.buttons["blindProfileOption_guideCues_0"].firstMatch
        XCTAssertTrue(firstCue.waitForExistence(timeout: 5), "\(variant)：没进第 2 题")
        XCTAssertTrue(advance.isEnabled, "\(variant)：多选题一项不选也应能继续")
        firstCue.tap()
        XCTAssertTrue(firstCue.isSelected, "\(variant)：勾选后读屏没有「已选中」")
        attachScreenshot(app, name: "blind-profile-multi-\(variant)")
        try audit(app)
        advance.tap()

        // 按读屏标签找，不按控件类型：多行输入框在 XCUI 里可能是 textField 也可能是 textView，
        // 而换屏动画没结束时先判类型会选错。
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "补充说明，选填")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(variant)：没进补充说明")
        field.tap()
        field.typeText(supplementSample)
        // 「仅播报必要路况；转弯前提前提示；我习惯陪跑员在我左侧」26 个字 ⇒ 剩余 54 字。
        let remaining = app.descendants(matching: .any)["blindProfileFlowRemaining"].firstMatch
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        XCTAssertEqual(remaining.label, "含已选内容，剩余 54 字。", "\(variant)：剩余字数没把已选说法算进去")
        // 截图前收起键盘：键盘不是本页的东西，盖住一半也审不到底部按钮。
        title.tap()
        attachScreenshot(app, name: "blind-profile-supplement-\(variant)")
        try audit(app)

        advance.tap()
        XCTAssertTrue(waitUntilGone(title, timeout: 10), "\(variant)：点「完成」后弹层没关")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "已保存：途中提示", "\(variant)：卡片没念「已保存」")
    }

    @available(iOS 17.0, *)
    @MainActor
    private func checkProfileOverview(_ app: XCUIApplication, variant: String) throws {
        for _ in 0..<6 { app.swipeDown() }
        XCTAssertFalse(app.buttons["保存，保存资料"].firstMatch.exists, "\(variant)：清单页不该有底部「保存」")
        let nickname = app.descendants(matching: .any)["blindProfileNicknameRow"].firstMatch
        XCTAssertTrue(nickname.waitForExistence(timeout: 5), "\(variant)：清单页没有「修改昵称」")
        XCTAssertEqual(nickname.value as? String, "测试盲人")
        XCTAssertGreaterThanOrEqual(nickname.frame.height, 63.5, "\(variant)：「修改昵称」不足 64pt：\(nickname.frame)")
        for title in ["未设置", "已设置"] {
            XCTAssertTrue(scrollUntilVisible(app.staticTexts[title].firstMatch, in: app), "\(variant)：没有组标题「\(title)」")
        }
        for _ in 0..<6 { app.swipeDown() }
        attachScreenshot(app, name: "blind-profile-overview-\(variant)")
        try audit(app)

        let contactsCard = app.descendants(matching: .any)["blindProfileCard_emergencyContacts"].firstMatch
        XCTAssertTrue(scrollUntilVisible(contactsCard, in: app), "\(variant)：清单页没有紧急联系人卡")
        XCTAssertEqual(contactsCard.label, "管理紧急联系人")
        XCTAssertEqual(contactsCard.value as? String, "1 位，主要联系人：张三", "\(variant)：紧急联系人摘要不对")
        XCTAssertGreaterThanOrEqual(contactsCard.frame.height, 63.5, "\(variant)：紧急联系人卡不足 64pt")
        attachScreenshot(app, name: "blind-profile-overview-bottom-\(variant)")
        try audit(app)
        for _ in 0..<6 { app.swipeDown() }
    }

    /// 「陪跑方式」：种子档案是牵引绳，打开就预选好；改成「搀扶」再走完两题，卡片念「已保存：搀扶，…」。
    @available(iOS 17.0, *)
    @MainActor
    private func checkEscortFlow(_ app: XCUIApplication, variant: String) throws {
        let card = app.descendants(matching: .any)["blindProfileCard_escort"].firstMatch
        XCTAssertTrue(scrollUntilVisible(card, in: app), "\(variant)：清单页没有「陪跑方式」")
        card.tap()
        let rope = app.buttons["blindProfileOption_tether_0"].firstMatch
        XCTAssertTrue(rope.waitForExistence(timeout: 8), "\(variant)：没弹出「引导方式」")
        XCTAssertTrue(rope.isSelected, "\(variant)：现有答案（牵引绳）没预选")
        for offset in 0..<4 {
            let option = app.buttons["blindProfileOption_tether_\(offset)"].firstMatch
            XCTAssertTrue(scrollUntilVisible(option, in: app), "\(variant)：没有第 \(offset) 项")
            XCTAssertGreaterThanOrEqual(option.frame.height, 63.5, "\(variant)：第 \(offset) 项不足 64pt：\(option.frame)")
        }
        let armHold = app.buttons["blindProfileOption_tether_1"].firstMatch
        armHold.tap()
        XCTAssertTrue(armHold.isSelected, "\(variant)：对勾没移到「搀扶」")
        XCTAssertFalse(rope.isSelected, "\(variant)：旧选项还标着已选")
        attachScreenshot(app, name: "blind-profile-choice-\(variant)")
        try audit(app)

        let advance = app.buttons["blindProfileFlowContinue"].firstMatch
        advance.tap()
        XCTAssertTrue(app.buttons["blindProfileFlowBack"].firstMatch.waitForExistence(timeout: 5), "\(variant)：第 2 题没有返回钮")
        advance.tap()
        XCTAssertTrue(waitUntilGone(advance, timeout: 10), "\(variant)：点「完成」后弹层没关")
        XCTAssertTrue(
            (card.value as? String ?? "").hasPrefix("已保存：搀扶"),
            "\(variant)：卡片没念「已保存：搀扶」：\(String(describing: card.value))"
        )
    }

    /// 等元素消失（弹层关掉）。`blindRunUITests` 那份同名工具不在这个类上。
    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
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
