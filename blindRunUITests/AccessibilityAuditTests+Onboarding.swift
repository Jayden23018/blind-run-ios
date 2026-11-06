import XCTest

// #657：首启登录与建档的可听反馈与防误触（OpenSpec `add-onboarding-audible-feedback`）。
// 每条用例都在改过的那一页上跑一次审计，并留一张截图。
@MainActor
extension AccessibilityAuditTests {
    private func launchOnboarding(accessToken: String? = nil, extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        app.launchEnvironment["AIDRUN_UI_TEST_BLOCK_TEL_DIAL"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = "mock"
        app.launchEnvironment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"
        if let accessToken {
            app.launchEnvironment["AIDRUN_UI_TEST_ACCESS_TOKEN"] = accessToken
        }
        app.launchEnvironment.merge(extraEnvironment) { _, new in new }
        app.launch()
        return app
    }

    private func keepOnboardingScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func anyElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// 联系人表单、资料页这两处的**原有**控件还有审计红灯（#676，2026-11-04 首次整页审计报出）。
    /// 角色页与验证码区已修好，改回 `try audit(app)`；实名页 2026-11-05 已删（#767）；剩下两处没修完前不能去掉。
    /// 非严格：修好一处后不会因为「预期的失败没出现」而变红。
    /// 本轮新加的元素另有显式断言守着，不靠这一遍审计。
    /// 紧急联系人表单的另外两处审计（`AccessibilityAuditTests+TouchTargets.swift`）也用它，所以不是 private。
    @available(iOS 17.0, *)
    func auditKnownRedPage(_ app: XCUIApplication) throws {
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        try XCTExpectFailure("#676：这一页原有控件的审计红灯", options: options) {
            try audit(app)
        }
    }

    /// B-8：空验证码按「登录」要上屏（播报由单测钉），焦点要回到输入框（键盘重新弹出）。
    func testLoginEmptyCodeShowsWhyAndReturnsFocusToTheCodeField() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchOnboarding()
        let phone = app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch
        XCTAssertTrue(phone.waitForExistence(timeout: 20), "登录页没起来")
        phone.tap()
        phone.typeText("13800000001")
        let dismiss = app.buttons["收起键盘"].firstMatch
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }

        app.buttons["获取验证码"].firstMatch.tap()
        let codeField = anyElement(app, "loginVerificationCodeField")
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "发送成功后没有出现验证码输入框")

        // 先收键盘：键盘上方的工具栏区域盖着「登录」的上半截，带着键盘点会落空（2026-11-04 真机截图）。
        let hideKeyboard = app.buttons["收起键盘"].firstMatch
        if hideKeyboard.waitForExistence(timeout: 3) { hideKeyboard.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "键盘没收起")
        let login = app.buttons["登录"].firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        login.tap()

        let error = app.staticTexts["请输入验证码。验证码是 6 位数字。"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), "空验证码按登录没有任何提示")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "出错后焦点没回到验证码输入框，键盘没弹出")
        keepOnboardingScreenshot("onboarding-login-empty-code")
        try audit(app)
    }

    /// B-7 / V-25：点卡片只弹确认；「重新选择」什么都不提交。警示在卡片之前。
    func testRoleSelectionAsksBeforeSettingTheRoleAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchOnboarding(accessToken: "roleless-token")
        let blindCard = app.buttons["我是盲人跑者，预约陪跑员陪我跑步"].firstMatch
        XCTAssertTrue(blindCard.waitForExistence(timeout: 20), "没有进角色选择页")

        let notice = anyElement(app, "roleSelectionIrreversibleNotice")
        XCTAssertTrue(notice.exists, "页面上没有「不能更改」的警示")
        XCTAssertLessThan(notice.frame.minY, blindCard.frame.minY, "警示要在角色卡片之前，读屏先听到它")
        keepOnboardingScreenshot("onboarding-role-selection")
        try audit(app)

        blindCard.tap()
        let alert = app.alerts["确认你是盲人跑者？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "点卡片没有弹确认，直接提交了")
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不能更改")).firstMatch.exists,
            "确认里没说「不能更改」"
        )
        keepOnboardingScreenshot("onboarding-role-confirm")

        alert.buttons["重新选择"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(blindCard.waitForExistence(timeout: 5), "按「重新选择」后离开了角色页，说明已经提交")

        // 确认这条路要真的提交：弹窗关闭时绑定会清 pendingRole，确认按钮不能依赖它。
        blindCard.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["确认，我是盲人跑者"].tap()
        XCTAssertTrue(blindCard.waitForNonExistence(timeout: 10), "按了确认还停在角色页，角色没有提交")
    }

    /// B-6：保存成功要上屏一句。#812 起资料页是核对清单：点卡片弹出一题一屏，最后一题点「完成」整张卡保存，
    /// 那张卡的状态行换成绿字「已保存：xx」并成为读屏值。
    func testBlindProfileSaveShowsSavedNotice() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome()
        app.tabBars.firstMatch.buttons["我的"].tap(); app.openBlindAccountPage() // 个人资料在账户页（#711）
        let profileLink = app.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileLink.waitForExistence(timeout: 10))
        profileLink.tap()

        XCTAssertFalse(app.buttons["保存，保存资料"].firstMatch.waitForExistence(timeout: 3), "清单页不该有底部「保存」")
        let card = anyElement(app, "blindProfileCard_escort")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "清单页没有「陪跑方式」")
        XCTAssertTrue((card.value as? String ?? "").hasPrefix("牵引绳"), "种子档案是牵引绳：\(String(describing: card.value))")
        card.tap()
        let rope = app.buttons["blindProfileOption_tether_0"].firstMatch
        XCTAssertTrue(rope.waitForExistence(timeout: 8), "没弹出「引导方式」")
        XCTAssertTrue(rope.isSelected, "弹层没把当前值标成已选")

        let armHold = app.buttons["blindProfileOption_tether_1"].firstMatch
        armHold.tap()
        let advance = app.buttons["blindProfileFlowContinue"].firstMatch
        advance.tap()
        advance.tap() // 第 2 题配速已预选，直接「完成」
        XCTAssertTrue(advance.waitForNonExistence(timeout: 10), "点「完成」后弹层没关")
        let saved = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已保存：搀扶")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "保存成功后屏幕上没有任何反馈")
        XCTAssertTrue(card.isHittable, "存上的那张卡被挡住了")
        XCTAssertTrue((card.value as? String ?? "").hasPrefix("已保存：搀扶"), "卡片读屏值没换成「已保存」")
        keepOnboardingScreenshot("profile-choice-saved")
        try audit(app)
    }

    /// B-10：姓名框键盘上方有「下一项」。#807 起手动新增页只剩姓名、手机号，「从通讯录选择」在列表页，不在这里。
    func testManualEmergencyContactFormHasOnlyNameAndPhoneAndPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome()
        app.tabBars.firstMatch.buttons["我的"].tap(); app.openBlindAccountPage() // 个人资料在账户页（#711）
        let profileLink = app.buttons["个人资料"].firstMatch
        XCTAssertTrue(profileLink.waitForExistence(timeout: 10))
        profileLink.tap()
        let manage = app.buttons["管理紧急联系人"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        manage.tap()
        // 列表页的「从通讯录添加」直接弹系统选择器（#746），表单里的那枚要从「手动输入」进。
        let add = anyElement(app, "emergencyContactAddManually")
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.navigationBars["新增紧急联系人"].waitForExistence(timeout: 8))

        // #807：通讯录选人和手动输入分开，这一页不再有选人按钮、关系行和主联系人开关。
        XCTAssertFalse(anyElement(app, "emergencyContactPickFromContacts").exists, "手动新增页不该再有「从通讯录选择」")
        XCTAssertFalse(anyElement(app, "emergencyContactRelationshipRow").exists, "手动新增页不该再有「关系」")
        XCTAssertFalse(app.switches["设为主联系人"].exists, "手动新增页不该再有主联系人开关")
        let addButton = anyElement(app, "emergencyContactFormSave")
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "手动新增页底部没有「添加」")
        XCTAssertGreaterThanOrEqual(addButton.frame.height + 0.5, 64, "「添加」只有 \(addButton.frame.height)pt")
        keepOnboardingScreenshot("onboarding-contact-form")
        // 沿用原来的已知红灯口径（#676）：去掉主联系人开关后是否全绿，要真机跑过才知道，没跑前不改成严格审计。
        try auditKnownRedPage(app)

        let nameField = app.textFields["联系人姓名，必填"].firstMatch
        nameField.tap()
        XCTAssertTrue(app.buttons["下一项"].firstMatch.waitForExistence(timeout: 5), "姓名框键盘上方没有「下一项」")
        app.buttons["下一项"].firstMatch.tap()
        // 号码是最后一个输入框（关系改成选择页，#746），数字键盘上方是「收起键盘」。
        XCTAssertTrue(app.buttons["收起键盘"].firstMatch.waitForExistence(timeout: 5), "号码框键盘上方没有「收起键盘」")
        keepOnboardingScreenshot("onboarding-contact-form-next")
        app.buttons["收起键盘"].firstMatch.tap()
    }
}
