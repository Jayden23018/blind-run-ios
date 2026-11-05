import XCTest

/// 盲人端实名认证页（#751，定稿 `docs/ui/mockups/blind-identity-20261105/identity-final.png`）：
/// 未认证 / 未通过 / 已认证三屏；「重复当前状态」在状态卡里、64pt；没填完按钮不可点并写「还差：xx」；
/// 未通过时按钮叫「重新提交」；已认证不出表单。盲人端四种外观：亮、暗、AX5 亮、AX5 暗。
private let blindIdentityVariants: [(name: String, environment: [String: String], arguments: [String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], []),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"], []),
    ("ax5-light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
    ("ax5-dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
]

extension AccessibilityAuditTests {

    @MainActor
    func testBlindIdentityNotVerifiedShowsMissingFieldsAndRepeatInStatusCard() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        try forEachIdentityVariant(status: "NOT_VERIFIED") { app, variant in
            XCTAssertTrue(app.staticTexts["先确认是你本人"].exists, "\(variant)：没有顶部标题")
            attachScreenshot(app, name: "blind-identity-not-verified-\(variant)-top")
            try audit(app)
            assertStatusRow(app, displayName: "未实名认证", variant: variant)
            XCTAssertFalse(app.staticTexts["*"].exists, "\(variant)：必填红星应已去掉")

            let submit = app.buttons["blindIdentitySubmitButton"].firstMatch
            XCTAssertTrue(submit.exists, "\(variant)：没有提交按钮")
            XCTAssertEqual(submit.label, "提交核验", variant)
            XCTAssertFalse(submit.isEnabled, "\(variant)：没填完时「提交核验」不该能点")
            let footnote = app.staticTexts["blindIdentitySubmitFootnote"].firstMatch
            XCTAssertEqual(footnote.label, "还差：姓名、身份证号", variant)
            // 定稿空表单也画着两行蓝字（逐位朗读没填号码时念「还没有输入」）。
            XCTAssertTrue(app.buttons["blindIdentityRevealToggle"].exists, "\(variant)：没有「临时显示身份证号」")
            XCTAssertTrue(app.buttons["blindIdentityReadDigits"].exists, "\(variant)：空表单时也要有「逐位朗读身份证号」")

            // 填了姓名之后「还差」只剩身份证号。
            let name = app.textFields["真实姓名，必填"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5), "\(variant)：没有姓名输入框")
            for _ in 0..<4 where !name.isHittable { app.swipeUp() }
            attachScreenshot(app, name: "blind-identity-not-verified-\(variant)-form")
            try audit(app, contentScrolledUnderNavigationBar: true)
            name.tap()
            name.typeText("王小明")
            XCTAssertTrue(
                footnote.waitForLabel("还差：身份证号", timeout: 5),
                "\(variant)：填了姓名后「还差」没更新：\(footnote.label)"
            )
            XCTAssertFalse(submit.isEnabled, "\(variant)：只填了姓名不该能提交")

            // 号码没填满时说差几位，不再只写「身份证号」（#751 审查）。AX5 下键盘会盖住号码框，只在默认字号验。
            guard !variant.hasPrefix("ax5") else { return }
            let idField = app.secureTextFields["身份证号，必填，18位"].firstMatch
            idField.tap()
            idField.typeText("11010")
            XCTAssertTrue(
                footnote.waitForLabel("还差：身份证号还差 13 位", timeout: 5),
                "\(variant)：号码没填满时「还差」没说差几位：\(footnote.label)"
            )
        }
    }

    @MainActor
    func testBlindIdentityFailedKeepsFormAndCallsTheButtonResubmit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        try forEachIdentityVariant(status: "FAILED") { app, variant in
            XCTAssertTrue(app.staticTexts["没有通过核验"].exists, "\(variant)：没有「没有通过核验」")
            attachScreenshot(app, name: "blind-identity-failed-\(variant)-top")
            try audit(app)
            assertStatusRow(app, displayName: "实名认证未通过", variant: variant)
            let idField = app.secureTextFields["身份证号，必填，18位"].firstMatch
            XCTAssertTrue(idField.exists, "\(variant)：未通过时表单要保留")
            let submit = app.buttons["blindIdentitySubmitButton"].firstMatch
            XCTAssertEqual(submit.label, "重新提交", variant)
            for _ in 0..<4 where !idField.isHittable { app.swipeUp() }
            attachScreenshot(app, name: "blind-identity-failed-\(variant)-form")
            try audit(app, contentScrolledUnderNavigationBar: true)
        }
    }

    @MainActor
    func testBlindIdentityVerifiedShowsOnlyTheResult() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        try forEachIdentityVariant(status: "VERIFIED") { app, variant in
            XCTAssertTrue(app.staticTexts["已实名认证"].exists, "\(variant)：没有「已实名认证」")
            XCTAssertTrue(app.staticTexts["可以正常预约跑步。"].exists, variant)
            attachScreenshot(app, name: "blind-identity-verified-\(variant)-top")
            try audit(app)
            assertStatusRow(app, displayName: "已实名认证", variant: variant)
            XCTAssertFalse(app.buttons["blindIdentitySubmitButton"].exists, "\(variant)：已认证不该有提交按钮")
            XCTAssertFalse(app.secureTextFields["身份证号，必填，18位"].exists, "\(variant)：已认证不该出现表单")
        }
    }

    // MARK: - Helpers

    /// 每种外观各起一次 App：「我的」→ 账户页 → 实名认证。未认证时启动会先问一次实名，点「稍后再说」。
    @available(iOS 17.0, *)
    @MainActor
    private func forEachIdentityVariant(
        status: String,
        _ check: (XCUIApplication, String) throws -> Void
    ) throws {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in blindIdentityVariants {
            var environment = variant.environment
            environment["AIDRUN_MOCK_BLIND_VERIFY_STATUS"] = status
            let app = launchBlindHome(extraEnvironment: environment, extraArguments: variant.arguments)
            let later = app.buttons["稍后再说"].firstMatch
            if later.waitForExistence(timeout: 8) { later.tap() }
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "\(variant.name)：标签栏没起来")
            tabBar.buttons["我的"].tap()
            app.openBlindAccountPage()
            let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "实名认证，当前状态")).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10), "\(variant.name)：账户页没有实名认证")
            entry.tap()
            XCTAssertTrue(app.navigationBars["实名认证"].waitForExistence(timeout: 10), "\(variant.name)：没进到实名认证页")
            XCTAssertFalse(app.tabBars.firstMatch.exists, "\(variant.name)：二级页要藏标签栏")
            try check(app, variant.name)
            app.terminate()
        }
    }

    /// 状态行读屏仍念「当前实名状态，xx」；「重复当前状态」在卡里、整行 ≥ 64pt、点得到。
    @MainActor
    private func assertStatusRow(_ app: XCUIApplication, displayName: String, variant: String) {
        let row = app.descendants(matching: .any)["blindIdentityStatusRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(variant)：没有状态行")
        XCTAssertEqual(row.label, "当前实名状态，\(displayName)", variant)
        let repeatRow = app.buttons["blindIdentityRepeatStatusRow"].firstMatch
        XCTAssertTrue(repeatRow.exists, "\(variant)：没有「重复当前状态」")
        // AX5 下状态卡可能在第一屏下面：先滚到它（ScrollView 不懒加载，存在但不一定在屏上）。
        for _ in 0..<4 where !repeatRow.isHittable { app.swipeUp() }
        XCTAssertEqual(repeatRow.label, "重复当前状态", variant)
        XCTAssertGreaterThanOrEqual(repeatRow.frame.height, 63.5, "\(variant)：「重复当前状态」不足 64pt：\(repeatRow.frame)")
        XCTAssertTrue(repeatRow.isHittable, "\(variant)：「重复当前状态」点不到")
    }
}

private extension XCUIElement {
    func waitForLabel(_ expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
