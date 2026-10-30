import XCTest

/// 亮 / 暗 × 默认 / 最大字号，取值同空闲时间页那条审计用例。
private let privacyAuditVariants: [(name: String, environment: [String: String], arguments: [String])] = [
    ("light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], []),
    ("dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"], []),
    ("ax5-light", ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
    ("ax5-dark", ["AIDRUN_UI_TEST_COLOR_SCHEME": "dark"],
     ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
]

/// 「隐私与授权」页（#393）的整页审计。新页此前没有任何审计用例。
/// 每种外观在页首、页尾各审一次并截图：`audit` 不保证判到第一遍时整个在屏外的元素（见 `AccessibilityAuditTests+Audit.swift`）。
extension AccessibilityAuditTests {

    @MainActor
    func testBlindPrivacyAuthorizationPagePassesAuditInLightDarkAndLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in privacyAuditVariants {
            let app = launchBlindHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            openPrivacyAuthorization(app, entryIdentifier: "blindPrivacyAuthorizationSettingsEntry", variant: variant.name)
            // UI 用例默认跳过语音与位置两项同意（环境变量），两项都显示为已同意、都有撤回按钮。
            try auditPrivacyPage(
                app,
                firstButton: "privacyRevokeVoiceOrderConsent",
                lastButton: "privacyRevokeLocationTrackConsent",
                name: "blind-privacy-\(variant.name)"
            )
            app.terminate()
        }
    }

    /// 陪跑员端同一页（#530）：只有位置共享一项。撤回按钮可点高度 ≥ 64pt、读屏标签说清撤回哪一项，再整页审计。
    @MainActor
    func testVolunteerPrivacyAuthorizationPagePassesAuditInLightDarkAndLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in privacyAuditVariants {
            let app = launchVolunteerHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            openPrivacyAuthorization(app, entryIdentifier: "volunteerPrivacyAuthorizationSettingsEntry", variant: variant.name)
            let revoke = app.buttons["volunteerPrivacyRevokeLocationTrackConsent"].firstMatch
            XCTAssertTrue(revoke.waitForExistence(timeout: 10), "\(variant.name)：没有撤回位置共享的按钮")
            // 63.5 而不是 64：真机浮点噪声，口径同 `testPrivacyAuthorizationRevokeButtonsAreTallAndSayWhatTheyRevoke`。
            XCTAssertGreaterThanOrEqual(revoke.frame.height, 63.5, "\(variant.name)：可点高度不足 64pt：\(revoke.frame)")
            XCTAssertTrue(revoke.label.contains("位置"), "\(variant.name)：读屏标签没说撤回哪一项：\(revoke.label)")
            try auditPrivacyPage(
                app,
                firstButton: "volunteerPrivacyRevokeLocationTrackConsent",
                lastButton: "volunteerPrivacyRevokeLocationTrackConsent",
                name: "volunteer-privacy-\(variant.name)"
            )
            app.terminate()
        }
    }

    /// 「我的」→ 设置页里的「隐私与授权」入口。
    @MainActor
    func openPrivacyAuthorization(_ app: XCUIApplication, entryIdentifier: String, variant: String) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "\(variant)：底部标签栏不在")
        tabBar.buttons["我的"].tap()
        let entry = app.descendants(matching: .any)[entryIdentifier].firstMatch
        // 先拖再断言：最大字号下入口在列表很下面，`List` 不渲染屏幕外的行，不拖就永远等不到（2026-10-28 真机 ax5 红过一次）。
        _ = entry.waitForExistence(timeout: 5)
        scrollAboveBottomBars(entry, app: app, maxDrags: 24)
        XCTAssertTrue(entry.exists && entry.isHittable, "\(variant)：设置页拖到底也没有「隐私与授权」入口")
        entry.tap()
        XCTAssertTrue(
            app.navigationBars["隐私与授权"].waitForExistence(timeout: 10),
            "\(variant)：没进到隐私与授权页（失败现场若是「紧急呼叫」单，是点到了列表里的紧急入口）"
        )
    }

    /// 页首审一次，滑到最后一枚撤回按钮露出来再审一次。
    @available(iOS 17.0, *)
    @MainActor
    func auditPrivacyPage(_ app: XCUIApplication, firstButton: String, lastButton: String, name: String) throws {
        let first = app.buttons[firstButton].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "\(name)：页首的撤回按钮没出来")
        waitUntilSettled(first)
        attachScreenshot(app, name: "\(name)-top")
        try audit(app)

        let last = app.buttons[lastButton].firstMatch
        for _ in 0..<8 where !(last.exists && last.isHittable) { app.swipeUp() }
        XCTAssertTrue(last.exists && last.isHittable, "\(name)：滑到底也没露出最后一枚撤回按钮")
        waitUntilSettled(last)
        attachScreenshot(app, name: "\(name)-bottom")
        try audit(app)
    }

    /// 把元素拖到标签栏之上再点。`isHittable` 不判遮挡。每次只拖四分之一屏，免得把它拖出页首。
    @MainActor
    private func scrollAboveBottomBars(_ element: XCUIElement, app: XCUIApplication, maxDrags: Int = 8) {
        for _ in 0..<maxDrags {
            let tabBar = app.tabBars.firstMatch
            let barTop = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
            if element.isHittable, element.frame.maxY < barTop { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
    }
}
