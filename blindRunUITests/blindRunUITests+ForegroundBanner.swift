import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
extension blindRunUITests {
    /// #527：前台通知横幅的「关闭」可点区到 64pt。
    ///
    /// 整条横幅是一个合成的读屏元素，按钮不在无障碍树里，量不到它的高度，所以按真实点击验：
    /// 点在按钮文字下方约 50pt。原来的系统按钮只有一行字高，这个位置落在按钮外面，点了没反应。
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

        // 横幅内边距 16，按钮靠右、顶部对齐，64pt 高：纵向 16…80。取 68，只有撑到 64pt 才点得中。
        let bannerTopLeft = banner.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        bannerTopLeft.withOffset(CGVector(dx: banner.frame.width - 46, dy: 68)).tap()

        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: highPriority)
        wait(for: [dismissed], timeout: 5)
    }
}
