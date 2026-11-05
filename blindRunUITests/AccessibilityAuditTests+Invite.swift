import XCTest

/// 「邀请好友」页（#755 定稿）：两端共用，盲人端四种外观各走一遍。
///
/// 守的是改版后容易丢的几件事：码逐字念、卡内「复制邀请码」整行 64pt、人数两行、
/// 「怎么算数」三条里的警告还在、二级页藏标签栏、整页过审计。
extension AccessibilityAuditTests {
    @MainActor
    func testBlindInvitePageShowsCodeCopyRowCountsAndRulesInEveryAppearance() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in Self.appearanceVariants {
            let app = launchBlindHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "\(variant.name)：标签栏没起来")
            tabBar.buttons["我的"].tap()
            revealInviteEntry(app, "blindInviteCodeSettingsEntry").tap()

            let any = app.descendants(matching: .any)
            let code = any["inviteCodeValue"].firstMatch
            XCTAssertTrue(code.waitForExistence(timeout: 10), "\(variant.name)：没打开邀请好友页")
            XCTAssertTrue(app.navigationBars["邀请好友"].exists, "\(variant.name)：页名要与「我的」里的方块同名")
            XCTAssertTrue(code.label.hasPrefix("我的邀请码"), "\(variant.name)：码的读屏标签不对：\(code.label)")
            XCTAssertFalse(app.tabBars.firstMatch.exists, "\(variant.name)：二级页要藏标签栏")

            let copy = app.buttons["inviteCodeCopyButton"].firstMatch
            XCTAssertTrue(copy.exists, "\(variant.name)：没有「复制邀请码」")
            XCTAssertGreaterThanOrEqual(copy.frame.height, 63.5, "\(variant.name)：复制行可点高度不足 64pt：\(copy.frame)")
            // 整行可点：卡片占满页宽减左右各 16pt 页边距，复制行要和卡片一样宽。
            let cardWidth = app.windows.firstMatch.frame.width - 32
            XCTAssertGreaterThanOrEqual(copy.frame.width, cardWidth - 1, "\(variant.name)：复制行没有铺满卡片：\(copy.frame)")

            // Mock 回的是 3 人用过、1 人发了奖励。
            XCTAssertTrue(any["用了你的邀请码，3 人"].firstMatch.exists, "\(variant.name)：没有「用了你的邀请码」那一行")
            XCTAssertTrue(any["已发放奖励，1 人"].firstMatch.exists, "\(variant.name)：没有「已发放奖励」那一行")
            attachScreenshot(app, name: "invite-\(variant.name)-0")
            try audit(app)

            // 警告与合规小字在页底，滚到才渲染。
            let warning = any["inviteCodeOneShotWarning"].firstMatch
            for _ in 0..<8 where !(warning.exists && warning.isHittable) { app.swipeUp() }
            XCTAssertTrue(warning.label.contains("注册完成后无法补填"), "\(variant.name)：警告那条不见了：\(warning.label)")
            XCTAssertTrue(any["邀请陪跑员，等他完成第一次陪跑，你们各得 20 积分。"].firstMatch.exists, "\(variant.name)：发分规则不对")
            let disclaimer = any["inviteCodePointsDisclaimer"].firstMatch
            for _ in 0..<4 where !(disclaimer.exists && disclaimer.isHittable) { app.swipeUp() }
            XCTAssertEqual(disclaimer.label, "积分不能提现、不能转让、不能兑换现金。", "\(variant.name)：合规句要一字不改")
            attachScreenshot(app, name: "invite-\(variant.name)-1")
            app.terminate()
        }
    }

    /// 拖到入口露出且不压在底栏后面（同 `revealSupportRow`，那个是 private）。
    @MainActor
    private func revealInviteEntry(_ app: XCUIApplication, _ identifier: String, maxDrags: Int = 24) -> XCUIElement {
        let element = app.buttons[identifier].firstMatch
        _ = element.waitForExistence(timeout: 8)
        for _ in 0..<maxDrags {
            let bar = app.tabBars.firstMatch
            let bottom = bar.exists ? bar.frame.minY : app.frame.maxY - 112
            if element.exists, element.isHittable, element.frame.maxY < bottom { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(identifier) 没有露出来")
        return element
    }
}
