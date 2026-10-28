import XCTest

/// 单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
extension blindRunUITests {
    /// #500：按下求助后屏 3b（「求助已发出」）弹出；返回跑步后再按一次，被后端并进未结案的那条时**重新弹出**，
    /// 并在屏上写出「这次没有新建求助」那句（念的那一路由单测
    /// `EmergencyUITestLocationSeamTests.testMergedRetriggerThroughTheCountdownEntryAnnouncesNoNewRequest` 守）。
    ///
    /// 两次弹出各靠 `EmergencyRecoveryPresentation` 的一个 `onChange`：第一次是事件 id 从无到有，
    /// 第二次 id 不变、靠 `mergedRetriggerCount` —— 此前没有任何 UI 用例走得到，改坏了不会红。
    /// 走得到是因为 UI 测试定位接缝（`AIDRUN_UI_TEST_EMERGENCY_LOCATION`，只在 DEBUG + Mock 下有样本）
    /// 与 Mock 照后端 #841 合并。
    @MainActor
    func testBlindSOSSentScreenPopsUpAgainWhenTheRetriggerIsMerged() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            seedOrderStatus: "IN_PROGRESS"
        )
        // 接缝只给这一条用：不往 `launchApp` 加参数（那个函数已超长），带上开关重启一次。
        app.terminate()
        app.launchEnvironment["AIDRUN_UI_TEST_EMERGENCY_LOCATION"] = "1"
        app.launch()

        let orderCard = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(orderCard.waitForExistence(timeout: 20), "有订单的盲人首页没起来，后面的断言没有意义")
        orderCard.tap()

        // 第一次：倒计时 3 秒 → 屏 3b。「返回跑步」只在倒计时结束后出现，所以等它就是在等 3b。
        sendSOSThroughSafetyHub(app)
        let sentScreen = app.descendants(matching: .any)["blindEmergencyCountdown"].firstMatch
        XCTAssertTrue(sentScreen.waitForExistence(timeout: 10), "按下求助后求助屏没有弹出")
        let backToRun = app.buttons["blindEmergencyCountdownClose"].firstMatch
        XCTAssertTrue(backToRun.waitForExistence(timeout: 15), "倒计时结束后没有进屏 3b（找不到「返回跑步」）")
        XCTAssertEqual(
            sentScreen.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "未发出")).count,
            0,
            "求助没发出去（UI 测试定位接缝没生效？）"
        )
        attachSentScreenShot("sos-sent-first")

        backToRun.tap()
        XCTAssertTrue(sentScreen.waitForNonExistence(timeout: 5), "「返回跑步」没有关掉屏 3b")

        // 第二次：Mock 并进同一条，事件 id 不变 —— 屏 3b 只能靠合并计数重新弹出。
        sendSOSThroughSafetyHub(app)
        XCTAssertTrue(sentScreen.waitForExistence(timeout: 10), "再按一次被合并时屏 3b 没有重新弹出")
        let mergedLine = sentScreen.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH %@", "这次没有新建求助")
        ).firstMatch
        XCTAssertTrue(mergedLine.waitForExistence(timeout: 5), "屏 3b 上没有说清「这次没有新建求助」")
        attachSentScreenShot("sos-sent-merged")
    }

    /// 执行屏底部的求助块 → 求助中心 → 「一键求助」→ 逐字锁定的二次确认 → 确认。
    /// 每一步都等元素出现再点：求助块是常驻的，没等页面起来就点会点到别处（记忆 `ui-test-tap-lands-on-persistent-sos-bar`）。
    @MainActor
    private func sendSOSThroughSafetyHub(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let hub = app.buttons["求助与安全，打开求助选项"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 15), "执行屏没有求助入口", file: file, line: line)
        hub.tap()
        let trigger = app.descendants(matching: .any)["blindSafetyHubTriggerEmergency"].firstMatch
        XCTAssertTrue(trigger.waitForExistence(timeout: 5), "求助中心没有「一键求助」", file: file, line: line)
        trigger.tap()
        let confirmation = app.alerts["一键求助"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "一键求助没有二次确认", file: file, line: line)
        confirmation.buttons["确认求助"].firstMatch.tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5), file: file, line: line)
    }

    @MainActor
    private func attachSentScreenShot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
