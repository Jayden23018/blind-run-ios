import XCTest

extension blindRunUITests {
    @MainActor
    func testRealAMapEnabledSmoke() throws {
        guard shouldRunRealAMapSmoke else {
            throw XCTSkip("Run on validation device 111 / iPad Pro (2), or set AIDRUN_UI_TEST_REAL_AMAP=1, to execute real AMap smoke.")
        }

        let blindApp = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            disableMap: false
        )

        // 盲人首页的装饰地图自 `30b0770` 起对读屏隐藏，identifier 一并删了（那是隐藏它的既定代价），
        // 所以**不能**再按 identifier 断言它挂上了。改成断反面：配了真 key 就不该渲染缺 key 占位图。
        // `mapPlaceholder` 是真实存在的那个（`blindRun/Map/MapPlaceholderView.swift`）。
        XCTAssertTrue(
            blindApp.descendants(matching: .any)["blindRunnerHomeScrollView"].firstMatch.waitForExistence(timeout: 20),
            "Real AMap run should still commit the blind-runner home"
        )
        XCTAssertFalse(
            blindApp.descendants(matching: .any)["mapPlaceholder"].firstMatch.exists,
            "配了真 key 的构建不该回落到缺 key 占位图"
        )
        XCTAssertFalse(blindApp.staticTexts["地图服务暂不可用"].exists, "Blind home must not fall back to the missing-key view")
        XCTAssertFalse(blindApp.staticTexts["请配置高德地图 API Key"].exists, "Blind home real AMap smoke requires a configured local key")

        // 装饰地图对读屏隐藏这件事，此前**只在占位图路径上验过** ——
        // `testMockBlindRunnerHomeKeepsAuxiliaryMapOutOfVoiceOverSoPrimaryActionComesFirst`
        // 走的是 `disableMap: true`。而真 key 路径上 `MapViewWrapper` 会自己合成一个带 label 的
        // 无障碍元素，外层的 `.accessibilityHidden(true)` 盖不住它：2026-08-22 从
        // `testRealAMapEnabledSmoke` 的失败快照里读到 `Other 402x200 «地图，显示当前位置和订单地点»`
        // 排在 `blindRunnerHomeScrollView` **前面** —— 正是 `30b0770` 声称修掉的那个问题。
        // 生产构建走的就是这条真 key 路径，所以这条断言守的是真实用户的遍历顺序。
        XCTAssertEqual(
            blindApp.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "地图，显示当前位置和订单地点"))
                .count,
            0,
            "真 key 构建下，盲人首页的装饰地图仍然不得出现在无障碍树里"
        )

        attachScreenshot(named: "real-amap-blind-home", app: blindApp)
        blindApp.terminate()

        let volunteerApp = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            disableMap: false
        )

        // 预置了在途订单 ⇒ 冷启动直接进服务页（§4.1），要看首屏得先退回来。
        XCTAssertTrue(
            waitForVolunteerOrderPage(volunteerApp, timeout: 25),
            "有在途订单时冷启动没有直接进服务页"
        )
        leaveVolunteerOrderPage(volunteerApp)

        // 🔴 志愿者首页**没有任何地图了**（2026-09-15 随「派单工作台」一起删），
        // 订单页也没有了（2026-09-26 跑步中换成 v2 页面，#218）。配了真 key 也不该冒出来。
        XCTAssertTrue(
            volunteerApp.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch.waitForExistence(timeout: 20),
            "Real AMap run should render the volunteer first screen"
        )
        XCTAssertEqual(
            volunteerApp.descendants(matching: .any).matching(identifier: "volunteerHomeMap").count,  // guard:allow stale-ui-test-identifier
            0,
            "配了真 key 的构建同样不该让已删除的志愿者辅助地图回到首屏"
        )
        attachScreenshot(named: "real-amap-volunteer-home", app: volunteerApp)

        openCurrentVolunteerService(volunteerApp, alreadyOpenTimeout: 0)
        XCTAssertEqual(
            volunteerApp.descendants(matching: .any).matching(identifier: "volunteerServiceMapBackdrop").count,  // guard:allow stale-ui-test-identifier
            0,
            "陪跑员订单页 v2 全流程不画地图（#218）"
        )

        attachScreenshot(named: "real-amap-volunteer-service", app: volunteerApp)
    }

    @MainActor
    func testCloudBackendBlindRunnerBookingSmoke() throws {
        #if !DEMO
        throw XCTSkip("Cloud UI smoke runs under blindRun-Demo / DemoRelease so the app is locked to the external cloud service.")
        #else
        guard shouldRunCloudSmoke else {
            throw XCTSkip("Run Demo cloud UI smoke on validation device 111 / iPad Pro (2), or set AIDRUN_UI_TEST_RUN_CLOUD_SMOKE=1.")
        }
        let app = launchApp(
            apiEnvironment: "demoCloud",
            disableMap: false,
            disableWebSocket: false,
            daytimeAppointment: true
        )
        let cloudPhone = "13800000001"

        login(app: app, phone: cloudPhone, code: "000000")
        chooseBlindRunnerRoleIfNeeded(app)
        completeBlindRunnerProfileIfNeeded(app)
        createBookingAndAssertMatching(app)
        cancelCurrentOrder(app)
        #endif
    }

    /// 首次启动的告知与同意门。**同意之前不许出现任何会收集信息的界面**，登录页也算 ——
    /// 手机号是个人信息，把登录页放在同意之前就等于「未经同意即开始收集」。
    ///
    /// 这条必须是 UI 测试：单测能证明标志位对，证明不了它真的挡在根路由前面。
    @MainActor
    func testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted() throws {
        let app = launchApp(apiEnvironment: "mock", activeRole: nil, forcePrivacyConsent: true)

        let gate = app.descendants(matching: .any)["appLaunchConsentView"].firstMatch
        XCTAssertTrue(gate.waitForExistence(timeout: 20), "首次启动必须先出现隐私告知页")
        XCTAssertFalse(
            app.descendants(matching: .any)["rootRoute.unauthenticated"].firstMatch.exists,
            "同意之前不该出现登录页"
        )

        // 拒绝是一个合法选择：说明后果，但留在本页，不退出 App（退出对看不见屏幕的人是「App 坏了」）。
        let decline = app.buttons["appLaunchConsentDeclineButton"].firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 10))
        decline.tap()
        XCTAssertTrue(app.staticTexts["appLaunchConsentDeclineNotice"].waitForExistence(timeout: 10))
        XCTAssertTrue(gate.exists, "拒绝后仍应停在告知页")
        XCTAssertFalse(app.descendants(matching: .any)["rootRoute.unauthenticated"].firstMatch.exists)

        app.buttons["appLaunchConsentAgreeButton"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["rootRoute.unauthenticated"].firstMatch.waitForExistence(timeout: 20),
            "同意后应当放行到登录页"
        )
    }

    /// 首启页的形态（issue #277）：同意 / 不同意**不滚动就点得到**，常规字号下它们常驻在屏幕底部。
    /// 此前整页摊开 7 条告知、按钮排在最底下 —— 与常规 App「摘要 + 链接 + 按钮」不同，
    /// 用户要滚过整份清单才找得到出口。`isHittable` 是判据：它为 true 才说明按钮此刻在可点击的屏幕范围内。
    /// 同时留默认字号与最大辅助功能字号两张截图，供人对照「差在哪」。
    @MainActor
    func testFirstLaunchDecisionButtonsAreReachableWithoutScrolling() throws {
        let app = launchApp(apiEnvironment: "mock", activeRole: nil, forcePrivacyConsent: true)
        XCTAssertTrue(app.descendants(matching: .any)["appLaunchConsentView"].firstMatch.waitForExistence(timeout: 20))

        let agree = app.buttons["appLaunchConsentAgreeButton"].firstMatch
        let decline = app.buttons["appLaunchConsentDeclineButton"].firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: 10))
        XCTAssertTrue(agree.isHittable, "同意按钮必须不滚动就能点到")
        XCTAssertTrue(decline.isHittable, "不同意按钮必须不滚动就能点到")
        XCTAssertTrue(app.buttons["appLaunchConsentFullListLink"].firstMatch.exists, "完整收集清单入口必须在弹窗里")
        // 常规 App 的首启隐私是**居中的小卡片弹窗**，不是整页：卡片要明显比屏幕矮、比屏幕窄，
        // 且同意在右、不同意在左（与常规 App 一致，点错的代价由位置习惯承担）。
        let popup = app.descendants(matching: .any)["appLaunchConsentPopup"].firstMatch
        XCTAssertTrue(popup.exists, "首启必须是弹窗卡片，而不是整页")
        XCTAssertLessThan(popup.frame.height, app.frame.height * 0.8, "弹窗不该撑满整个屏幕")
        XCTAssertLessThan(popup.frame.width, app.frame.width, "弹窗左右要留出压暗的背景")
        XCTAssertLessThan(decline.frame.minX, agree.frame.minX, "左边是不同意，右边是同意")
        attachScreenshot(named: "first-launch-consent-default", app: app)

        // 最大辅助功能字号：底部栏退回内联（否则按钮占掉大半屏）。只要求都还在，并留图。
        let large = launchApp(
            apiEnvironment: "mock", activeRole: nil, forcePrivacyConsent: true,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(large.buttons["appLaunchConsentAgreeButton"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(large.buttons["appLaunchConsentDeclineButton"].firstMatch.exists)
        attachScreenshot(named: "first-launch-consent-ax5", app: large)
    }
}
