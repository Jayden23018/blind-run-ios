import XCTest

extension blindRunUITests {
    @MainActor
    func testMockBlindOrderHidesEmergencyActionInAcceptedStates() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true
        )

        // 2026-09-16 起首页的入口是整张深蓝订单卡，不再是「查看当前订单」按钮。
        // 这两条是 SOS 红线用例，入口挂掉会让它们在第一行就 waitForExistence 失败 ——
        // 表现是「求助入口不存在」这种指向完全错误的失败信息，而红线其实没被验过。
        let currentOrderButton = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(currentOrderButton.waitForExistence(timeout: 12), "Blind runner home should expose current order")
        currentOrderButton.tap()

        let acceptButton = app.buttons["模拟志愿者接单"].firstMatch
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 8), "Mock controls should allow accepting the order")
        acceptButton.tap()
        assertNoEmergencyAction(app)

        let arriveButton = app.buttons["模拟志愿者到达"].firstMatch
        XCTAssertTrue(arriveButton.waitForExistence(timeout: 8), "Mock controls should allow moving to arrived state")
        arriveButton.tap()
        assertNoEmergencyAction(app, "DRIVER_ARRIVED is not yet an active run")

        let startButton = app.buttons["模拟服务开始"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Mock controls should allow starting the service")
        startButton.tap()

        let hub = blindSafetyHub(app)
        XCTAssertTrue(hub.waitForExistence(timeout: 8), "IN_PROGRESS should expose the blind safety hub")
        XCTAssertGreaterThanOrEqual(hub.frame.height, 64, "Blind primary actions must be at least 64pt high")

        // 2026-09-15：求助中心是**一层菜单**，不是那个二次确认。
        // 🔴 打开它必须什么都还没发生 —— 菜单里第一项是「联系志愿者」这种无害动作，
        // 所以这一层的正文绝不能是那句逐字锁定的确认文案。
        // 09-15 `fd4f0cc` 起求助中心是自绘层 `blindSafetyHub`，不再是 `confirmationDialog`
        // （XCUITest 认成的那个 `sheets["求助"]`），理由见 `SafetyHubView.swift` 的
        // 「为什么不是 `confirmationDialog`」。标题区是合成元素，所以两条文案断言都用 CONTAINS。
        hub.tap()
        let hubLayer = app.descendants(matching: .any)["blindSafetyHub"].firstMatch
        XCTAssertTrue(hubLayer.waitForExistence(timeout: 5), "求助块没有打开求助中心")
        XCTAssertTrue(
            hubLayer.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "还没有发送求助")
            ).firstMatch.exists,
            "求助中心的第一句必须先说清什么都还没发出去"
        )
        XCTAssertEqual(
            hubLayer.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "是否确认进入求助状态")
            ).count,
            0,
            "逐字锁定的二次确认文案不许被挪用成菜单正文"
        )

        // 云端那条走的仍是「一键求助」，且二次确认一步不减。
        // 轻点（读屏双击同理）= 关掉求助中心再弹二次确认；长按 3 秒才跳过确认直发，这里不走。
        let trigger = app.descendants(matching: .any)["blindSafetyHubTriggerEmergency"].firstMatch
        XCTAssertTrue(trigger.waitForExistence(timeout: 5), "IN_PROGRESS 的求助中心没有「一键求助」")
        trigger.tap()
        let confirmation = app.alerts["一键求助"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), "SOS must require a second confirmation")
        XCTAssertTrue(
            confirmation.staticTexts["是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"]
                .firstMatch.exists,
            "Second-confirmation copy is mandated verbatim by AGENTS.md section 10"
        )
        confirmation.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        // 不能写成 `...containing("求助").firstMatch.label.contains("已记录")`：
        // 取消后若一条含「求助」的文本都不存在，对空查询的 firstMatch 取 .label 会抛
        // "Failed to get matching snapshot" 而不是返回空串 —— 行为越正确断言越会炸。
        // 直接断言「不存在同时含『求助』和『已记录』的文本」，空集自然为真。
        let recorded = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "求助", "已记录")
        )
        XCTAssertEqual(recorded.count, 0, "Cancelling the confirmation must not submit anything")
    }

    /// The app must never tell a blind runner that a contact received the SMS: the backend pushes
    /// `EMERGENCY_CONTACT_NOTIFIED` before the SMS is attempted, and never corrects a failure.
    @MainActor
    func testBlindEmergencyCopyNeverClaimsSmsDelivery() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true
        )

        // 2026-09-16 起首页的入口是整张深蓝订单卡，不再是「查看当前订单」按钮。
        // 这两条是 SOS 红线用例，入口挂掉会让它们在第一行就 waitForExistence 失败 ——
        // 表现是「求助入口不存在」这种指向完全错误的失败信息，而红线其实没被验过。
        let currentOrderButton = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(currentOrderButton.waitForExistence(timeout: 12))
        currentOrderButton.tap()

        for label in ["模拟志愿者接单", "模拟志愿者到达", "模拟服务开始"] {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 8), "Mock control \(label) should exist")
            button.tap()
        }

        XCTAssertTrue(blindSafetyHub(app).waitForExistence(timeout: 8))
        for claim in ["联系人已收到短信", "已收到短信", "已通知家属", "已通知你的联系人"] {
            XCTAssertFalse(
                app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", claim))
                    .firstMatch.exists,
                "SOS screen must never claim SMS delivery (“\(claim)”)"
            )
        }
    }

    @MainActor
    func testMockBlindLogoutRequiresConfirmation() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )

        // 入口走「我的」tab（齿轮已随首页改版删除），与紧急联系人那批用例共用同一个 helper。
        openBlindAccount(app) // #711 起盲人端的退出登录在账户页（「我的」→ 头像卡）

        let logoutButton = app.buttons["退出登录"].firstMatch
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5), "Settings should expose logout")
        XCTAssertTrue(scrollElementIntoView(logoutButton, app: app), "「退出登录」滚不出求助条")
        logoutButton.tap()

        XCTAssertTrue(app.alerts["确认退出"].firstMatch.waitForExistence(timeout: 5), "Logout should require confirmation")
        XCTAssertTrue(app.buttons["确认退出"].firstMatch.exists)
        XCTAssertTrue(app.buttons["取消"].firstMatch.exists)
    }
}
