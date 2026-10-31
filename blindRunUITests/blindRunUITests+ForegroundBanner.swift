import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
extension blindRunUITests {
    /// #527：前台通知横幅的「关闭」可点区到 64pt。
    ///
    /// 整条横幅是一个合成的读屏元素，按钮不在无障碍树里，量不到它自己的高度，只能量横幅：
    /// 两行通知文字撑不到 96pt，到了这个高度只能是 64pt 的按钮加上下内边距撑的。
    /// 这条高度断言才是守卫。只靠下面的点击分不出来：横幅 5 秒后会自己消失（`notificationDuration`），
    /// 点没点中都会消失，第一版用例因此验红失败。
    @MainActor
    func testForegroundBannerDismissReachesWellBelowItsTextLine() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            realtimePriorityTest: true
        )
        let banner = app.descendants(matching: .any)["realtimeForegroundNotification"].firstMatch
        let highPriority = app.staticTexts["高优先级前台通知"]
        XCTAssertTrue(banner.waitForExistence(timeout: 12), "前提：横幅没出来")
        XCTAssertTrue(highPriority.waitForExistence(timeout: 3), "前提：高优先级那条没顶上来")

        XCTAssertGreaterThanOrEqual(banner.frame.height, 96, "「关闭」的 64pt 可点区没撑开这一行")

        // 横幅内边距 16，按钮靠右、顶部对齐，64pt 高：纵向 16…80。取 68，只有撑到 64pt 才点得中。
        let bannerTopLeft = banner.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        bannerTopLeft.withOffset(CGVector(dx: banner.frame.width - 46, dy: 68)).tap()

        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: highPriority)
        wait(for: [dismissed], timeout: 2)
    }
}
