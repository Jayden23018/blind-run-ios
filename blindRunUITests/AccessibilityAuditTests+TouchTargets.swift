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
        // 右上角的退出图标只在**首次填资料**（引导里的「完善信息」，`isEditing == false`）出现；
        // 从「设置 → 个人资料」进来的是「编辑资料」，没有这枚图标（退出在设置页）。不预置资料，Mock 就停在引导这一页。
        let onboarding = launchBlindHome(extraEnvironment: ["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE": "0"], tapsAfterLaunch: false)
        let logout = onboarding.buttons["退出登录"].firstMatch
        XCTAssertTrue(logout.waitForExistence(timeout: 20), "首次填资料页没有退出登录")
        assertBlindTouchTarget(logout, name: "退出登录")
        onboarding.terminate()

        let app = launchBlindHome()
        openBlindProfile(app)

        let tether = app.descendants(matching: .any)["blindProfileTetherPreferencePicker"].firstMatch
        XCTAssertTrue(swipeUntilHittable(tether, in: app), "资料页没有「希望怎么被引导」")
        assertBlindTouchTarget(tether, name: "希望怎么被引导")
        XCTAssertFalse((tether.value as? String ?? "").isEmpty, "读屏没念当前选项")
        attachScreenshot(app, name: "blind-profile-tether")
        try audit(app)

        let contactsRow = navigationRow(app, labelBeginsWith: "管理紧急联系人")
        XCTAssertTrue(swipeUntilHittable(contactsRow, in: app), "资料页没有「管理紧急联系人」")
        contactsRow.tap()
        XCTAssertTrue(app.navigationBars["紧急联系人"].waitForExistence(timeout: 12), "没进紧急联系人页")

        // Mock 种子联系人只有张三一位且是主联系人：有「编辑」「删除」，没有「设为主联系人」。
        for (label, name) in [("编辑张三", "编辑"), ("删除张三", "删除")] {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(swipeUntilHittable(button, in: app), "联系人行没有「\(name)」")
            assertBlindTouchTarget(button, name: name)
        }
        attachScreenshot(app, name: "blind-emergency-contacts")
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

    /// 首页 →「我的」→ 设置 → 个人资料。
    @MainActor
    private func openBlindProfile(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "标签栏没起来")
        tabBar.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10), "「我的」里没有设置页")
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
