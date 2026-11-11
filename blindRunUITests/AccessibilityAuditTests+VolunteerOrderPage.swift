import XCTest

/// 陪跑员订单页「约好」屏（`SCHEDULED_CONFIRMED`）的整页审计（#669）。
/// 这一屏此前没有审计用例：#524 的举报入口用例只守新加的两枚按钮，原有元素的红灯一直没人看到。
extension AccessibilityAuditTests {

    /// 头卡主角数字（开跑时刻，「15:49」）：`docs/ui/design-direction.md` §6.1 第一行，负责人 2026-09-26 拍板，
    /// 只有 `flowHeroNumber` 封顶 AX2、其余字照常不封顶。理由：80pt 的数字在 AX5 放大三倍会撑出屏幕，
    /// 且这个数字同时写在副文和读屏标签里，封顶不损失信息。审计的「改不了字号」判的正是这一封顶，属设计内。
    /// 判据只认「动态字号类、文字是 H:mm、高 ≥ 50pt」，别的文字照常审。
    @available(iOS 17.0, *)
    private func isHeroNumberCappedByDesign(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == .dynamicType, let element = issue.element else { return false }
        let isClock = element.label.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
        return isClock && element.frame.height >= 50
    }

    @MainActor
    func testVolunteerScheduledConfirmedOrderPagePassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let variants: [(name: String, environment: [String: String])] = [
            ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"]),
            ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"]),
        ]
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in variants {
            let app = launchVolunteerHome(seedOrderStatus: "SCHEDULED_CONFIRMED", extraEnvironment: variant.environment)
            let page = app.descendants(matching: .any)["volunteerOrderFlowStatusCard"].firstMatch
            if !page.waitForExistence(timeout: 15) {
                let current = app.staticTexts["当前订单"].firstMatch
                if current.waitForExistence(timeout: 5) { current.tap() }
            }
            XCTAssertTrue(page.waitForExistence(timeout: 15), "\(variant.name)：没到陪跑员订单页")
            waitUntilSettled(page)
            attachScreenshot(app, name: "volunteer-order-scheduled-confirmed-\(variant.name)-top")
            try audit(app, allowing: isHeroNumberCappedByDesign)
            // 下半屏：抽屉最底下是信息块，滚出来再审一遍。v7（#945）起「我去不了」收进顶栏「···」，不在页面里。
            for _ in 0..<3 { app.swipeUp() }
            attachScreenshot(app, name: "volunteer-order-scheduled-confirmed-\(variant.name)-bottom")
            try audit(app, allowing: isHeroNumberCappedByDesign)
            app.terminate()
        }
    }

    /// 最大字号下入口在屏外，列表不渲染屏外的行，所以先滚到它出现再等（#673：此前 ax5 变体在这里假失败）。
    @MainActor
    func waitForScrolledEntry(_ entry: XCUIElement, in app: XCUIApplication) -> Bool {
        _ = entry.waitForExistence(timeout: 5)
        for _ in 0..<12 where !entry.exists { app.swipeUp() }
        return entry.waitForExistence(timeout: 15)
    }
}
