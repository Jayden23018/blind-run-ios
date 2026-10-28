import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长（同 `AccountDeletionBlockedUITests`）。
extension blindRunUITests {
    /// 撤回按钮可点高度 ≥ 64pt，读屏标签说清撤回哪一项。UI 用例默认跳过语音与位置两项同意（环境变量），
    /// 所以两项都显示为已同意、都有撤回按钮；撤回后的状态切换由单测 `PrivacyAuthorizationTests` 守。
    @MainActor
    func testPrivacyAuthorizationRevokeButtonsAreTallAndSayWhatTheyRevoke() throws {
        let app = launchBlindContactsApp()
        openSettings(app)
        tapNavigationRow(app, labelBeginsWith: "隐私与授权")

        for (identifier, word) in [("privacyRevokeVoiceOrderConsent", "语音下单"), ("privacyRevokeLocationTrackConsent", "位置")] {
            let button = app.buttons[identifier].firstMatch
            XCTAssertTrue(scrollUntilExists(button, app: app), "没有 \(identifier)")
            XCTAssertTrue(scrollElementIntoView(button, app: app), "\(identifier) 滚不出底部")
            // 63.5 而不是 64：真机浮点噪声，口径同 `testBlindProfileGuideDogChoiceIsTallAndSpeaksTheCurrentValue`。
            XCTAssertGreaterThanOrEqual(button.frame.height, 63.5, "可点高度不足 64pt：\(button.frame)")
            XCTAssertTrue(button.label.contains(word), "读屏标签没说撤回哪一项：\(button.label)")
        }
    }
}
