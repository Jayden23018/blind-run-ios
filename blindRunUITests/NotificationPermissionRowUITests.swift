import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长（同 `PrivacyAuthorizationUITests`）。
extension blindRunUITests {
    /// #521：两端设置页常驻「通知」一行，说清开没开。有按钮时（拒绝过 → 去系统设置；还没问过 → 开启通知）可点高度 ≥ 64pt。
    /// 测试机上本 App 的通知授权状态不归用例管（装过就留着），所以按钮在不在都接受，在就量高度。
    @MainActor
    func testSettingsShowNotificationRowWithTallButtonOnBothSides() throws {
        for role in ["blind_runner", "volunteer"] {
            let app = launchApp(
                apiEnvironment: "mock",
                accessToken: "mock_jwt_token_for_testing",
                activeRole: role,
                preseedBlindProfile: role == "blind_runner",
                preseedVolunteerProfile: role == "volunteer",
                emptyMockOrders: true
            )
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "\(role)：标签栏没起来")
            tabBar.buttons["我的"].tap()

            let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "通知：")).firstMatch
            // 只滑不点：这一行在「退出登录」上面，靠近标签栏。
            for _ in 0..<10 where !row.exists { app.swipeUp() }
            XCTAssertTrue(row.exists, "\(role)：设置页没有「通知」一行")
            // 「正在读取」是读授权状态前的中间态，等它落定再判按钮。
            let settled = expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "正在读取"), evaluatedWith: row)
            XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 5), .completed, "\(role)：通知状态一直是「正在读取」")

            for identifier in ["notificationPermissionSettingsLink", "notificationPermissionRequestButton"] {
                let button = app.buttons[identifier].firstMatch
                guard button.exists else { continue }
                // 63.5 而不是 64：真机浮点噪声，口径同 `testPrivacyAuthorizationRevokeButtonsAreTallAndSayWhatTheyRevoke`。
                XCTAssertGreaterThanOrEqual(button.frame.height, 63.5, "\(role)：\(identifier) 可点高度不足 64pt：\(button.frame)")
            }
            app.terminate()
        }
    }
}
