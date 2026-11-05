import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长（同 `AccountDeletionBlockedUITests`）。
extension blindRunUITests {
    /// #754 起「隐私与授权」分两层：第一层三行只看状态、没有撤回按钮；撤回行在每项的详情页里。
    /// 撤回行可点高度 ≥ 64pt，读屏标签说清撤回哪一项。UI 用例默认跳过语音与位置两项同意（环境变量），
    /// 所以两项都显示为已同意、详情页都有撤回行；撤回后的状态切换由单测 `PrivacyAuthorizationTests` 守。
    @MainActor
    func testPrivacyAuthorizationRevokeButtonsAreTallAndSayWhatTheyRevoke() throws {
        let app = launchBlindContactsApp()
        openBlindAccount(app) // 隐私与授权在账户页（#711）
        tapNavigationRow(app, labelBeginsWith: "隐私与授权")
        let listBar = app.navigationBars["隐私与授权"]
        XCTAssertTrue(listBar.waitForExistence(timeout: 10), "没进到隐私与授权页")
        XCTAssertFalse(app.buttons["privacyRevokeVoiceOrderConsent"].exists, "第一层不该再有撤回按钮")

        let items = [
            (entry: "privacyVoiceOrderConsentEntry", revoke: "privacyRevokeVoiceOrderConsent", word: "语音下单"),
            (entry: "privacyLocationTrackConsentEntry", revoke: "privacyRevokeLocationTrackConsent", word: "位置"),
        ]
        for item in items {
            let row = app.descendants(matching: .any)[item.entry].firstMatch
            XCTAssertTrue(scrollUntilExists(row, app: app), "第一层没有 \(item.entry)")
            XCTAssertTrue(row.label.contains("已同意"), "第一层那一行没说当前状态：\(row.label)")
            scrollElementIntoView(row, app: app)
            tapWhenHittableOrByCoordinate(row, app: app)

            let button = app.buttons[item.revoke].firstMatch
            XCTAssertTrue(scrollUntilExists(button, app: app), "详情页没有 \(item.revoke)")
            XCTAssertTrue(scrollElementIntoView(button, app: app), "\(item.revoke) 滚不出底部")
            // 63.5 而不是 64：真机浮点噪声，口径同 `testBlindProfileGuideDogChoiceIsTallAndSpeaksTheCurrentValue`。
            XCTAssertGreaterThanOrEqual(button.frame.height, 63.5, "可点高度不足 64pt：\(button.frame)")
            XCTAssertTrue(button.label.contains(item.word), "读屏标签没说撤回哪一项：\(button.label)")

            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(listBar.waitForExistence(timeout: 10), "从 \(item.entry) 的详情页没回到第一层")
        }
    }
}
