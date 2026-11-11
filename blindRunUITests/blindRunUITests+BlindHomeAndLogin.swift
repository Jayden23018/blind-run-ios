import XCTest

extension blindRunUITests {
    @MainActor
    func testMockBlindRunnerBookingSmoke() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            daytimeAppointment: true
        )

        createBookingAndAssertMatching(app)
    }

    /// 首页的读屏遍历顺序：问候（标题）→ 主内容 → 标签栏。
    ///
    /// 🔄 **2026-09-16 改版后这条换了守的对象。** 原用例叫
    /// `testMockBlindRunnerHomeKeepsAuxiliaryMapOutOfVoiceOverSoPrimaryActionComesFirst`，
    /// 断的是「铺满上半屏的装饰地图不在无障碍树里」+「内容层排在设置齿轮之前」。
    /// 改版把装饰地图和悬浮齿轮**双双删除**（设计稿的首页只有问候 + 订单卡 + 预约块，
    /// 设置进了「我的」tab），那两条断言的对象都不存在了 ——
    /// 留着会变成恒真断言，也就是「写了等于没写」。
    ///
    /// 接手的不变式是设计稿第 5.1 节的读屏顺序：**问候 → 订单卡 → 预约块 → 标签栏**。
    /// 这里能比的是前两者：它们同在滚动视图内部、同一深度，下标可比。
    ///
    /// ⚠️ 不拿标签栏进下标比较：`allElementsBoundByAccessibilityElement` 是**逐层枚举**的
    /// （同深度的兄弟全排完才轮到子元素），标签栏与滚动视图内容差的是深度不是顺序 ——
    /// 2026-08-07 那条红了半年的断言就是这么来的。
    @MainActor
    func testBlindRunnerHomeReadsGreetingBeforeTheMainAction() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )

        let booking = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(booking.waitForExistence(timeout: 12), "盲人首页没起来")

        let greeting = app.descendants(matching: .any)["blindRunnerHomeGreeting"].firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 5), "首页缺少问候 —— 它是这一屏的标题")

        let elements = app.descendants(matching: .any).allElementsBoundByAccessibilityElement
        let greetingIndex = elements.firstIndex { $0.identifier == "blindRunnerHomeGreeting" }
        let bookingIndex = elements.firstIndex { $0.identifier == "blindRunnerHomeStartBookingButton" }
        XCTAssertNotNil(greetingIndex, "问候必须在无障碍元素树里")
        XCTAssertNotNil(bookingIndex, "预约入口必须在无障碍元素树里")
        if let greetingIndex, let bookingIndex {
            XCTAssertLessThan(
                greetingIndex,
                bookingIndex,
                "问候必须排在主操作之前 —— 打开 App 第一句该先知道「这是谁的首页」"
            )
        }

        // 装饰地图已整块删除。断「不在树里」而不是「不存在」：它此前的洞恰恰是
        // 外层 `accessibilityHidden` 盖不住内部合成的元素（真 key 构建上实测），
        // 所以判据必须落在无障碍树上。
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "blindRunnerHomeAuxiliaryMap").count, // guard:allow stale-ui-test-identifier
            0,
            "装饰性地图不得出现在无障碍元素树里"
        )
    }

    @MainActor
    func testRootHydrationMountsOnlyBlindHomeWithoutLoginOrProfileGhosts() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )

        let home = app.descendants(matching: .any)["rootRoute.blindHome"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 12), "Hydration should commit the blind home route")
        XCTAssertFalse(app.descendants(matching: .any)["rootRoute.unauthenticated"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["rootRoute.blindProfile"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["rootRoute.restoringAccount"].firstMatch.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch.isHittable,
            "Committed home must remain interactive"
        )
    }

    @MainActor
    func testBlindHomeRemainsInteractiveWhileInitialRequestNeverReturns() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            hangHomeRequests: true,
            homeLoadTimeout: 3
        )

        XCTAssertTrue(app.staticTexts["正在更新状态"].waitForExistence(timeout: 12))

        let scrollView = app.scrollViews["blindRunnerHomeScrollView"].firstMatch
        XCTAssertTrue(scrollView.exists, "Blind home must expose a scrollable surface during loading")
        scrollView.swipeUp()
        // 2026-08-14 起地图对读屏隐藏（`accessibilityHidden(true)`，理由见
        // `docs/research/swiftui-voiceover-traversal-order-20260814.md`），XCUITest 只看得见
        // 无障碍树，所以这里不再断言地图已挂载 —— 那是隐藏地图的既定代价。
        // 「加载挂起时首页仍可用」由上下文的滚动、重试、设置三条断言覆盖。
        // 此前这里断的是 `homeMapPlaceholder` 不存在 —— 那个 identifier **App 侧从来没有过**
        // （全历史 `git log -S` 0 命中），断言恒真，写下之日起就是摆设。
        // 也不能改成真实的 `mapPlaceholder`：本用例走 `disableMap` 默认值 `true`，占位图是被
        // 强制渲染的，断它不存在必红。真 key 路径的对应断言在 `testRealAMapEnabledSmoke`。
        scrollView.swipeDown()

        let retryButton = app.buttons["重试加载"].firstMatch
        XCTAssertTrue(retryButton.waitForExistence(timeout: 5), "A non-cooperative request must release loading at the deadline")
        XCTAssertTrue(retryButton.isHittable)

        // 🔄 **2026-09-16 改版后这一段换了对象。** 原来点的是首页的「重复当前状态」，
        // 并且必须先 `scrollElementIntoView` 把它滚出底部常驻求助条的遮挡 —— 不滚也
        // `isHittable == true`，但触点会落在求助条上，2026-08-14 因此真的走到了拨号确认单，
        // 再被后续 swipe 拖到「拨打110」，最后报成一个完全不像误触的快照超时。
        //
        // 改版后首页既没有「重复当前状态」也没有求助条（前者进求助与安全中心、
        // 后者进「我的」tab），底部的固定条是标签栏。所以这里改成验**加载挂起时
        // 标签栏仍然可用**：那是这一屏此刻唯一还能带用户离开的东西。
        //
        // 误触那条回归钉子保留 —— 判据从「求助条」换成「标签栏」，但要防的事情没变：
        // 本地操作的触点不许落到底部固定条上。
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "加载挂起时底部标签栏消失了")

        let profileTab = tabBar.buttons["我的"]
        XCTAssertTrue(profileTab.isHittable, "Tab bar must remain independent from home loading")
        profileTab.tap()
        // 误触求助条的回归钉子。真机上那条路径会真的拨出去，当时只有双卡选号单挡了一下。
        XCTAssertFalse(
            app.buttons["拨打110"].firstMatch.exists,
            "切 tab 的触点落到了紧急入口上，弹出了本地拨号确认单"
        )

        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5)) // 标签根页叫「我的」，首页齿轮进去的仍叫「设置」
    }

    @MainActor
    func testForegroundRealtimeHighPriorityIsAccessibleAndNavigationIndependent() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            realtimePriorityTest: true
        )

        let banner = app.descendants(matching: .any)["realtimeForegroundNotification"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 12), "Foreground notification should be owned above feature navigation")
        XCTAssertTrue(
            app.staticTexts["高优先级前台通知"].waitForExistence(timeout: 3),
            "HIGH notification should preempt the currently visible NORMAL notification"
        )
        XCTAssertTrue(banner.label.contains("高优先级前台通知"), "Visible and VoiceOver notification copy should be equivalent")
    }

    @MainActor
    func testLoginEnvironmentSwitcherMatchesBuildChannel() throws {
        let app = launchApp(apiEnvironment: "mock")
        let environmentSwitcher = app.buttons["API 环境切换"].firstMatch

        #if DEBUG
        XCTAssertTrue(environmentSwitcher.waitForExistence(timeout: 5), "Debug login should expose the API environment switcher")
        #else
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(environmentSwitcher.exists, "Demo and production builds must not expose the API environment switcher")
        #endif
    }

    @MainActor
    func testLoginPhoneFieldLimitsInputToElevenDigits() throws {
        let app = launchApp(apiEnvironment: "mock")

        let phoneField = app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch
        XCTAssertTrue(phoneField.waitForExistence(timeout: 10), "Login phone field should appear")
        tapWhenHittableOrByCoordinate(phoneField, app: app)
        phoneField.typeText("13800000001000000")

        XCTAssertTrue(
            waitForTextFieldValue(phoneField, equals: "13800000001", timeout: 5),
            "Phone field should immediately keep only the first eleven digits"
        )
        dismissKeyboardIfPresent(app: app)
        let requestCodeButton = app.buttons["获取验证码"].firstMatch
        XCTAssertTrue(waitForElementToBeEnabled(requestCodeButton, timeout: 5), "Request code button should be enabled with the normalized phone number")
        tapWhenHittableOrByCoordinate(requestCodeButton, app: app)

        let codeField = app.textFields["验证码输入框，请输入 6 位验证码"].firstMatch
        XCTAssertTrue(codeField.waitForExistence(timeout: 5), "Verification code field should appear after requesting a code")
        tapWhenHittableOrByCoordinate(codeField, app: app)
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Demo 验证码")).firstMatch.exists,
            "Login view should not reveal the fixed demo verification code"
        )
        XCTAssertFalse(
            app.staticTexts["Demo 验证码：000000"].firstMatch.exists,
            "Login view should not reveal the fixed demo verification code"
        )

        codeField.typeText("000000")
        waitForPostLoginRoute(app)
    }
}
