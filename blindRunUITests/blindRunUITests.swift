//
//  blindRunUITests.swift
//  blindRunUITests
//
//  Created by Jerry on 5/18/26.
//

import XCTest

final class blindRunUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testMockBlindRunnerBookingSmoke() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true
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

        XCTAssertTrue(app.staticTexts["正在后台同步当前状态，页面仍可使用"].waitForExistence(timeout: 12))

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
            "切 tab 的触点落到了「我的」底部那条求助条上，弹出了本地拨号确认单"
        )

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
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

    @MainActor
    func testMockVolunteerOrderFlowSmoke() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true
        )

        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 12), "Volunteer identity row should be visible below the system status area")
        assertVolunteerTopStatusBlockPosition(identityRow, app: app)
        // 🔴 志愿者端**整个 App 里已经没有这张辅助地图了**（2026-09-15 删，它的
        // `annotations` 恒为 `[]`，唯一信息「我在哪」在派单卡的覆盖范围文字里已有一份）。
        // 这条负断言留着当门卫：谁把它加回首屏，这里会红。
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerHomeMap"].firstMatch.exists,  // guard:allow stale-ui-test-identifier
            "志愿者辅助地图已删除，不该出现在「我」首屏"
        )

        let currentOrderCard = app.descendants(matching: .any)["volunteerHomeCurrentOrderCard"].firstMatch
        XCTAssertTrue(currentOrderCard.waitForExistence(timeout: 5), "Preseeded active order should appear on the first screen")
        // 🔴 作业区排在影响力区**之前**：带到期动作的东西必须先于「24 次陪跑」被念到。
        XCTAssertGreaterThanOrEqual(currentOrderCard.frame.minY, identityRow.frame.maxY, "Current order should sit directly below the identity row")
        let impactBlock = app.descendants(matching: .any)["volunteerHomeIncentiveCard"].firstMatch
        if impactBlock.waitForExistence(timeout: 10) {
            XCTAssertLessThan(
                currentOrderCard.frame.minY,
                impactBlock.frame.minY,
                "「需要你处理」必须排在影响力区之前 —— 读屏顺序播报，排序就是优先级"
            )
        }

        openCurrentVolunteerService(app)
        assertNoEmergencyAction(app)

        let enRouteButton = app.buttons["我已出发"].firstMatch
        XCTAssertTrue(enRouteButton.waitForExistence(timeout: 5), "Accepted order should show en-route button")
        enRouteButton.tap()
        assertNoEmergencyAction(app)

        let arriveButton = app.buttons["我已到达约定地点"].firstMatch
        XCTAssertTrue(arriveButton.waitForExistence(timeout: 8), "En-route order should show arrive button")
        arriveButton.tap()
        assertNoEmergencyAction(app)

        let startButton = app.buttons["开始服务"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Arrived order should allow the volunteer to start service")
        // 按 identifier 取，不按文案：这枚按钮不带 `.isButton` trait（它没有轻点路径，
        // 读屏走自定义动作），`app.buttons[...]` 取不到它。
        let finishControl = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertFalse(finishControl.waitForExistence(timeout: 1), "Arrived order must not allow completing service before IN_PROGRESS")
        startButton.tap()
        XCTAssertTrue(finishControl.waitForExistence(timeout: 8), "In-progress order should expose the long-press finish control")
        // 2026-08-01 起志愿者可以代盲人发起求助（后端已按订单参与方归属事件，不再回推给按按钮的人）。
        // 这里原本断言「志愿者永远看不到求助入口」，那是后端送错人时期的止血，现在反过来验它必须可用。
        assertEmergencyActionIsUsable(app)

        // 结束要按满 2 秒（没有轻点路径）。松手即取消那一半在
        // `testVolunteerFinishesEscortOnlyAfterHoldingLongEnough` 里单独验 ——
        // 这条烟囱用例要先走完出发 / 到达 / 开始三步，沿途任何一条红灯都会把它挡在这之前。
        finishControl.press(forDuration: 2.6)

        let summary = app.descendants(matching: .any)["completedTrackSummary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Completed service should show the reusable track summary")
        XCTAssertTrue(app.staticTexts["本次路线"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["里程"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["时长"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["平均配速"].firstMatch.exists)
        XCTAssertTrue(app.buttons["重复当前状态"].firstMatch.exists, "Track summary must remain usable without inspecting the map")
        let routeMap = app.descendants(matching: .any)["completedTrackAuxiliaryMap"].firstMatch
        XCTAssertTrue(routeMap.exists, "The blind track should be available as an auxiliary map")
        XCTAssertLessThan(
            app.staticTexts["本次路线"].firstMatch.frame.minY,
            routeMap.frame.minY,
            "Textual status must precede the auxiliary map"
        )

        // 内嵌那张 220pt 的图看不清整条路线，大屏页才是「跑完看轨迹」的落点。
        // 入口做成独立一行而不是把地图本身变成链接：MAMapView 自己吃掉手势，
        // 包在 NavigationLink 里点不动，读屏用户也对不上焦点。
        let fullScreenLink = app.descendants(matching: .any)["completedTrackFullScreenLink"].firstMatch
        XCTAssertTrue(fullScreenLink.waitForExistence(timeout: 5), "Track summary must offer a full-screen route entry")
        fullScreenLink.tap()

        let replay = app.descendants(matching: .any)["orderRouteReplay"].firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout: 10), "Tapping the entry should open the full-screen route replay")
        XCTAssertTrue(
            app.descendants(matching: .any)["routeReplayRepeatStatus"].firstMatch.waitForExistence(timeout: 5),
            "The replay page must stay usable without inspecting the map"
        )
    }

    /// 长按 2 秒结束陪跑的**行为**那一半：松手即取消 / 按满才结束。
    ///
    /// 走**指针路径**（`press(forDuration:)` 注入的是物理触摸），形状那一半在
    /// `AccessibilityAuditTests.testVolunteerFinishEscortControlIsReachableAndBigEnough`。
    /// 两条路最终调的是同一个 `VolunteerFinishLongPressButton.fire()`。
    /// ⛔ 不要在这里改成「tap 一下再断言结束了」：`tap()` 不经过 accessibility action，
    /// 而这枚控件没有轻点路径 —— 那样写必红，且红得毫无信息量。
    ///
    /// 直接把订单预置在 `IN_PROGRESS`，不走烟囱用例那条出发 → 到达 → 开始的长路：
    /// 那条路上有一条与本功能无关的既有红灯（求助悬浮键 `isHittable == false`，
    /// 2026-09-16 在 `main@fdc6579` 上复现过同一签名），挂在它后面等于这一条永远跑不到。
    @MainActor
    func testVolunteerFinishesEscortOnlyAfterHoldingLongEnough() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            seedOrderStatus: "IN_PROGRESS"
        )

        openCurrentVolunteerService(app, requirePhone: false)

        let finishControl = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertTrue(finishControl.waitForExistence(timeout: 15), "服务进行中必须有结束入口")

        let completedSummary = app.descendants(matching: .any)["completedTrackSummary"].firstMatch
        // 两个时长写死在这里而不是引用 App 侧常量（UI 测试是另一个进程，`@testable import`
        // 够不着）：阈值本身由 `VolunteerFinishLongPressTests` 钉住，这里只要一个明显不足、
        // 一个明显足够。
        finishControl.press(forDuration: 0.6)
        XCTAssertFalse(
            completedSummary.waitForExistence(timeout: 3),
            "松手即取消：不足 2 秒就结束了陪跑，等于误触一次不可撤销的操作"
        )
        XCTAssertTrue(finishControl.exists, "取消一次长按之后，结束入口必须还在原地")

        finishControl.press(forDuration: 2.6)
        XCTAssertTrue(
            completedSummary.waitForExistence(timeout: 10),
            "按满 2 秒必须真的结束 —— 否则这枚按钮对不开读屏的人就是个按不动的东西"
        )
    }

    @MainActor
    func testVolunteerServiceRemainsInteractiveWhenTransitionConfirmationNeverReturns() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            hangTransitionConfirmation: true,
            homeLoadTimeout: 3
        )

        openCurrentVolunteerService(app, requirePhone: false)
        let enRouteButton = app.buttons["我已出发"].firstMatch
        XCTAssertTrue(enRouteButton.waitForExistence(timeout: 5))
        enRouteButton.tap()

        XCTAssertTrue(
            app.staticTexts["操作已提交，状态待确认。页面其他功能仍可使用。"].waitForExistence(timeout: 3),
            "POST completion must release the action spinner before confirmation GET completes"
        )
        XCTAssertFalse(enRouteButton.isEnabled, "The same transition must not be submitted twice")

        let cancelButton = app.buttons["取消订单"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        XCTAssertTrue(cancelButton.isHittable, "Cancellation entry must remain locally interactive")
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerServiceMapBackdrop"].firstMatch.exists,
            "The service map layer must remain mounted while confirmation is pending"
        )
        XCTAssertTrue(app.buttons["导航到出发地点"].firstMatch.isHittable)
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.isHittable, "Back navigation must remain usable")

        XCTAssertTrue(
            app.staticTexts["状态确认延迟，请稍后点击“重新确认状态”。请勿重复提交同一操作。"]
                .waitForExistence(timeout: 5),
            "A permanently suspended confirmation must become a delayed, nonmodal state"
        )
        XCTAssertTrue(app.buttons["重新确认状态"].firstMatch.isHittable)
    }

    @MainActor
    func testRealtimeEnRouteWithHungDetailAndLocationSendRemainsScrollable() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            disableMap: false,
            hangTransitionConfirmation: true,
            confirmTransitionViaRealtime: true,
            hangEscortLocationSend: true,
            homeLoadTimeout: 3
        )

        openCurrentVolunteerService(app, requirePhone: false)
        let enRouteButton = app.buttons["我已出发"].firstMatch
        XCTAssertTrue(enRouteButton.waitForExistence(timeout: 5))
        enRouteButton.tap()

        let arriveButton = app.buttons["我已到达约定地点"].firstMatch
        XCTAssertTrue(
            arriveButton.waitForExistence(timeout: 5),
            "The ordered realtime event must advance UI before location sending completes"
        )
        let panel = app.descendants(matching: .any)["volunteerServicePanel"].firstMatch
        XCTAssertTrue(panel.exists)
        panel.swipeUp()
        panel.swipeDown()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.isHittable)
        // 面板内容高于可视区：回到顶部后「取消订单」落在折叠区以下，本来就点不到。
        // 这条测试要证明的是「卡住的详情/上报没有冻住面板，控件滚一下仍然可达」，
        // 不是「任意滚动位置都能看见底部按钮」，所以先滚到底再断言可点。
        panel.swipeUp()
        XCTAssertTrue(waitForElementToBeHittable(app.buttons["取消订单"].firstMatch, timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["volunteerServiceMapBackdrop"].firstMatch.exists)
    }

    @MainActor
    func testRealtimeArrivedWithRealMapDoesNotEnterSwiftUIRefreshLoop() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            disableMap: false,
            hangTransitionConfirmation: true,
            confirmTransitionViaRealtime: true,
            hangEscortLocationSend: true,
            homeLoadTimeout: 3
        )

        openCurrentVolunteerService(app, requirePhone: false)
        let enRouteButton = app.buttons["我已出发"].firstMatch
        XCTAssertTrue(enRouteButton.waitForExistence(timeout: 5))
        enRouteButton.tap()
        let arriveButton = app.buttons["我已到达约定地点"].firstMatch
        XCTAssertTrue(arriveButton.waitForExistence(timeout: 5))
        arriveButton.tap()

        XCTAssertTrue(app.buttons["开始服务"].firstMatch.waitForExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["volunteerServicePanel"].firstMatch
        XCTAssertTrue(panel.exists)
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            panel.swipeUp()
            panel.swipeDown()
            XCTAssertTrue(app.navigationBars.buttons.firstMatch.isHittable)
            XCTAssertTrue(app.descendants(matching: .any)["volunteerServiceMapBackdrop"].firstMatch.exists)
        }
    }

    @MainActor
    func testMockVolunteerLegacyTrainingCompletesWithoutTrainingAndReturnsHomeUnavailable() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            forceRealVolunteerRegistration: true,
            unregisteredVolunteer: true,
            legacyTrainingStatusAfterFaceVerify: true
        )

        let entry = app.descendants(matching: .any)["volunteerRealRegistrationEntry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 12), "Volunteer profile should expose the registration entry")
        entry.tap()

        XCTAssertTrue(app.descendants(matching: .any)["volunteerRegistrationStep.1"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["volunteerRegistrationStep.2"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["培训学习"].exists)
        XCTAssertFalse(app.buttons["加载测验"].exists)
        XCTAssertFalse(app.buttons["提交测验"].exists)

        let nameField = app.textFields.element(boundBy: 0)
        let phoneField = app.textFields.element(boundBy: 1)
        let idCardField = app.textFields.element(boundBy: 2)
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("测试志愿者")
        phoneField.tap()
        phoneField.typeText("13800000002")
        dismissKeyboardIfPresent(app: app)
        idCardField.tap()
        idCardField.typeText("110101199001011234")
        dismissKeyboardIfPresent(app: app)

        let submit = app.buttons["提交身份信息"].firstMatch
        XCTAssertTrue(waitForElementToBeEnabled(submit, timeout: 5))
        submit.tap()

        // 身份证号与人脸要单独同意才发得出去（`c46da3c`，闸门在
        // `VolunteerRegistrationFlowView.handleBasicInfoSubmitTapped`）。UI 用例一律 `RESET_STATE`，
        // 同意没有落盘，所以这道门每次都会出现 —— 不点它，后面的活体认证永远不来。
        let identityConsentAgree = app.buttons["volunteerIdentityConsentAgreeButton"].firstMatch
        XCTAssertTrue(
            identityConsentAgree.waitForExistence(timeout: 8),
            "提交实名信息前必须先过单独的告知同意门"
        )
        identityConsentAgree.tap()

        let faceVerify = app.buttons["开始活体认证"].firstMatch
        XCTAssertTrue(faceVerify.waitForExistence(timeout: 8))
        faceVerify.tap()

        let completion = app.descendants(matching: .any)["volunteerRegistrationCompleted"].firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 12))
        XCTAssertEqual(completion.label, "注册完成，请返回首页开启可服务状态")
        let returnHome = app.buttons["返回志愿者首页"].firstMatch
        XCTAssertTrue(returnHome.exists)
        XCTAssertFalse(app.staticTexts["培训学习"].exists)
        XCTAssertFalse(app.buttons["提交测验"].exists)

        returnHome.tap()
        // 2026-09-14 改版把首页那个 `Toggle` 换成了底部的滑动 CTA，`app.switches` 不再存在。
        // 「没有被自动打开」这条约束没变，判据换成：滑块的无障碍按钮名是**关闭态**那一个。
        //
        // 2026-09-17 滑块改成双向（右开 / 左关）之后状态条也不存在了，两态都是同一条轨道，
        // 只有无障碍表示的按钮名不同：关闭态「向右滑动，开始接单」/ 开启态「进入接单」。
        let slider = app.buttons["向右滑动，开始接单"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 8), "回到首屏后底部应当是关闭态的滑动 CTA")
        XCTAssertFalse(
            app.buttons["进入接单"].exists,
            "Legacy completion must not automatically enable availability"
        )
    }

    @MainActor
    func testMockVolunteerServiceArrivedWaitingScreenshots() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true
        )

        openAcceptedVolunteerService(app)
        attachScreenshot(named: "volunteer-service-accepted", app: app)

        let arriveButton = app.buttons["我已到达约定地点"].firstMatch
        XCTAssertTrue(arriveButton.waitForExistence(timeout: 5), "Accepted service page should show arrive action")
        arriveButton.tap()

        let startButton = app.buttons["开始服务"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Arrived order should show start-service action")
        let finishControl = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertFalse(finishControl.waitForExistence(timeout: 1), "Arrived order should hide the finish control")
        attachScreenshot(named: "volunteer-service-arrived", app: app)
        startButton.tap()
        XCTAssertTrue(finishControl.waitForExistence(timeout: 8), "Started service should show the long-press finish control")
        attachScreenshot(named: "volunteer-service-in-progress", app: app)
    }

    /// 志愿者端**只有一屏**：身份 → 作业区 → 影响力 → 徽章 → 最近陪跑 → 派单状态。
    /// 没有地图，也没有任何二级的「工作台」。
    ///
    /// > 2026-09-14 改版前这一条断的是「地图铺满 + 底部面板」那套，改版后改成「首屏 + 工作台」两段。
    /// > 2026-09-15 工作台被删（用户原话「好像是没什么用的」），于是又并回一段：
    /// > 派单统计现在就在首屏最底部，地图整个不存在了。
    @MainActor
    func testMockVolunteerFirstScreenKeepsDispatchStatsWithoutAMapOrWorkbench() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true
        )

        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 15), "Volunteer first screen should expose its identity row")
        assertVolunteerTopStatusBlockPosition(identityRow, app: app)
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerHomeCurrentOrderCard"].firstMatch.exists,
            "没有在途订单时不该渲染当前订单卡"
        )
        // ⚠️ 上面那条**不等于**「作业区不渲染」——原文的断言消息是这么写的，而它已经不成立：
        // Mock 的 `trainingProgress` 默认为空 ⇒ 派单摘要恒带 `TRAINING_INCOMPLETE`
        // ⇒ `hasTodo` 恒为真 ⇒ 作业区一定在。这才是本轮改动的版式回归钉：
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerHomeTrainingEntry"].firstMatch.exists,
            "Mock 默认未完成培训，作业区里必须有那张培训卡"
        )
        XCTAssertTrue(
            app.staticTexts["我的陪伴"].firstMatch.waitForExistence(timeout: 10),
            "First screen should lead with the impact section"
        )
        XCTAssertTrue(app.staticTexts["最近陪跑"].firstMatch.exists, "First screen should show the recent-run stream")
        XCTAssertFalse(app.buttons["查看全部订单"].firstMatch.exists, "Primary volunteer home must not expose the public order list")
        // 预置「已开启」时轨道还在（双向滑块两态同一条轨道），但无障碍表示换成
        // 「进入接单」那一枚按钮 —— 已开启之后向右滑做的是导航，不是再开一次。
        XCTAssertTrue(
            app.buttons["进入接单"].firstMatch.waitForExistence(timeout: 5),
            "已开启时滑块的无障碍按钮应当是「进入接单」"
        )
        XCTAssertFalse(
            app.buttons["向右滑动，开始接单"].firstMatch.exists,
            "已经开启了还提示「开始接单」，等于告诉志愿者他没开"
        )
        attachScreenshot(named: "volunteer-profile-first-screen", app: app)

        // 工作台入口整行已删，没有任何二级页可进。
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerProfileWorkbenchEntry"].firstMatch.exists,  // guard:allow stale-ui-test-identifier
            "派单工作台已删除，首屏不该再有它的入口"
        )
        // 「回到当前位置」随地图一起删了 —— 它是 identifier 守卫管不到的中文文案，只能在这儿断。
        XCTAssertFalse(app.buttons["回到当前位置"].firstMatch.exists, "地图删除后「回到当前位置」不该还在")

        // 三格：完成 / 评分 / 接单率，现在就在首屏最底部。此前这里断的是「积分」，
        // 而 `be4e030` 已经把那一格删了 —— 它的值是 `totalCompleted * 100`，后端从来没有积分字段。
        //
        // 🔴 `ScrollView` 屏幕外的子视图 `isHittable` 照样为真，但 `LazyVGrid` 的格子屏幕外
        // **不实例化**，所以必须先滚到它再断言存在（同 `testVolunteerDispatchSummaryTilesSurviveAX5`）。
        let rate = app.staticTexts["接单率"].firstMatch
        var drags = 0
        while !rate.exists && drags < 16 {
            app.swipeUp(velocity: .slow)
            drags += 1
        }
        XCTAssertTrue(rate.exists, "派单统计必须留在首屏（drags=\(drags)）\n\(app.debugDescription)")

        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerHomeMap"].firstMatch.exists,  // guard:allow stale-ui-test-identifier
            "志愿者辅助地图已删除，全 App 不该再有它"
        )

        attachScreenshot(named: "volunteer-first-screen-dispatch-stats", app: app)
    }

    /// 培训页导航栏标题，单一来源 `VolunteerTrainingCopy.navigationTitle`。
    private static let volunteerTrainingTitle = "陪跑培训"
    /// 培训卡的标题，单一来源 `VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText`。
    ///
    /// XCUITest 是黑盒进不了 app 的类型，这两个只能抄一份 —— 抄错的方向是安全的（会红不会绿）。
    private static let volunteerTrainingIncompleteReason = "尚未完成必修培训"

    /// ③ 必修培训入口：**在首屏、整卡可点、一下直达培训页**。
    ///
    /// 用户原话：「必须在派单工作台点进去再点击一个贼小的去培训，一点都不显眼」。
    /// 三条断言逐条对应那句话的三个毛病：不在首屏 / 不显眼 / 不直达。
    ///
    /// Mock 默认「一门课都没学」（`MockAPIClient.trainingProgress` 初始为空），
    /// 所以派单摘要默认就带 `TRAINING_INCOMPLETE`，这张卡默认可见 —— 不用额外预置。
    ///
    /// 点的是真 `NavigationLink`（指针路径），不是 `accessibilityRepresentation`，
    /// 所以不踩「XCUITest 的 tap() 够不着 accessibility action」那条坑。
    @MainActor
    func testVolunteerTrainingEntryIsOnTheFirstScreenAndOpensTraining() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true
        )

        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 15), "Volunteer first screen should render")

        let trainingEntry = app.descendants(matching: .any)["volunteerHomeTrainingEntry"].firstMatch
        // ① 在首屏：不 tap 任何东西就能滚到它。滚动本身不改变「它属于这一屏」这个事实。
        XCTAssertTrue(
            scrollElementIntoView(trainingEntry, app: app),
            "必修培训入口必须直接在首屏上，不能藏在二级页里\n\(app.debugDescription)"
        )
        // ② 显眼：整卡可点的一大块，不是一枚小链接。64pt 是这条意见的量化形式。
        XCTAssertGreaterThanOrEqual(
            trainingEntry.frame.height,
            64,
            "培训入口必须是一整张卡而不是一行小链接（height=\(trainingEntry.frame.height)）"
        )
        // ②之二 原因本身就是入口：卡上写的是「为什么接不到单」，不是一枚「去培训」小链接。
        // 少了这一条，上面那个 64pt 断言就只是在复读实现里的常量 —— 把标题换成「去培训」
        // 它照样绿，而「原因本身就是入口」正是用户那句话里最实质的一半。
        XCTAssertTrue(
            trainingEntry.label.contains(Self.volunteerTrainingIncompleteReason),
            "培训入口的可读名必须就是原因本身（label=\(trainingEntry.label)）"
        )

        // 而且它排在影响力区之前 —— 作业区是第一档，读屏顺序播报，排序就是优先级。
        //
        // ⛔ **不要写成 `if impactBlock.exists { … }`**：「我的陪伴」不在树里时整条顺序断言
        // 会静默跳过、用例照报 passed，而这正是本仓库记过的「验红假绿」形状。
        // 同文件上面那条用例已经证明这个字面量可以无条件等到。
        let impactBlock = app.staticTexts["我的陪伴"].firstMatch
        XCTAssertTrue(impactBlock.waitForExistence(timeout: 10), "影响力区应当渲染，否则下面的顺序无从判起")
        XCTAssertLessThan(
            trainingEntry.frame.minY,
            impactBlock.frame.minY,
            "「需要你处理」里的培训入口必须排在影响力区之前"
        )

        attachScreenshot(named: "volunteer-training-entry-on-first-screen", app: app)

        // ③ 直达：点一下就是培训页，中间没有别的页。
        trainingEntry.tap()
        XCTAssertTrue(
            app.navigationBars[Self.volunteerTrainingTitle].waitForExistence(timeout: 8),
            "培训入口应当一步打开「\(Self.volunteerTrainingTitle)」\n\(app.debugDescription)"
        )
    }

    /// 派单卡片在 AX5 下仍然三格成行 —— 这是本仓库第一条 Dynamic Type 用例，
    /// 见记忆 `low-vision-visual-channel-unaudited`：字号上限一直没人系统性看过。
    @MainActor
    func testVolunteerDispatchSummaryTilesSurviveAX5() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        // 三格统计自 2026-09-15 起就在首屏最底部（工作台那一跳已随二级页一起删掉）。
        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 15), "AX5 下首屏也要先渲染出来")

        // 三格在 `LazyVGrid` 里，屏幕外**不实例化**（无障碍树里是 `Other {{0,0},{0,0}}`），
        // 所以必须先滚到它再断言存在 —— `waitForExistence` 等不到，
        // `scrollElementIntoView` 第一行的 `guard element.exists` 也过不去。
        // 慢速滚：AX5 下滚动视口很浅而默认速度一次跨度远大于它，采样点会整段跳过格子区。
        // 上限从 10 提到 24：三格现在住在**整张首屏的最底部**（身份 → 作业区 → 影响力 →
        // 徽章 → 最近陪跑 → 派单状态），AX5 下这条路比原先那个短短的工作台页长得多。
        let rate = app.staticTexts["接单率"].firstMatch
        var drags = 0
        while !rate.exists && drags < 24 {
            app.swipeUp(velocity: .slow)
            drags += 1
        }
        XCTAssertTrue(rate.exists, "Acceptance-rate tile must still render at AX5 (drags=\(drags))\n\(app.debugDescription)")
        // 上一版传的是 `...AccessibilityExtraExtraExtraLarge`（不是真的常量名），被静默忽略，
        // 截图与默认字号一模一样却看着像验过了。钉一条断言，别再靠肉眼分辨。
        XCTAssertGreaterThan(rate.frame.height, 30, "AX5 launch argument did not take effect (height=\(rate.frame.height))")
        attachScreenshot(named: "volunteer-dispatch-summary-ax5", app: app)
    }

    @MainActor
    func testVolunteerHomeRemainsInteractiveWhileDispatchRequestNeverReturns() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            hangHomeRequests: true,
            homeLoadTimeout: 8
        )

        // 首屏与派单摘要是两条独立的加载：摘要挂住时，身份行、影响力区和三个去处
        // 都必须照常可用 —— 改版前守的是「面板仍可拖动」，同一条约束换了个载体。
        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 12), "First screen must render while the dispatch request hangs")

        // 底部那排「记录 / 成就 / 设置」在 2026-09-14 改版里被吸收进首屏：
        // 记录 = 最近陪跑「全部 ›」，成就 = 徽章「全部 N 枚 ›」，设置 = 右上角齿轮。
        // 三个去处一个没少，所以这条用例守的东西没变，只是入口换了位置。
        //
        // XCUITest 是黑盒，进不了 app 的类型 —— 导航栏标题只能抄一份。
        // 抄错的方向是安全的：生产改了文案而这里没跟，断言会红不会绿。
        let recordsButton = app.buttons["我的服务记录"].firstMatch
        let recognitionButton = app.buttons["查看服务成就"].firstMatch
        let settingsButton = app.buttons["设置"].firstMatch

        // 🔴 `ScrollView` 屏幕外的子视图**照样** `isHittable == true`，而触点会被钳到
        // 最上层的控件上（`List` 是压根不渲染，两种坑不一样）。所以点之前必须
        // `scrollElementIntoView`，不能只判 `isHittable`（记忆 `snapshot-timeout-means-a-system-app-took-over`）。
        XCTAssertTrue(scrollElementIntoView(settingsButton, app: app), "齿轮入口应当可达")
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        popNavigationBar(app, title: "设置")

        XCTAssertTrue(scrollElementIntoView(recognitionButton, app: app), "徽章区「全部 ›」应当可达")
        recognitionButton.tap()
        XCTAssertTrue(app.navigationBars["服务成就"].waitForExistence(timeout: 5))
        popNavigationBar(app, title: "服务成就")

        XCTAssertTrue(scrollElementIntoView(recordsButton, app: app), "最近陪跑「全部 ›」应当可达")
        recordsButton.tap()
        XCTAssertTrue(app.navigationBars["服务记录"].waitForExistence(timeout: 5))
    }

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
        hub.tap()
        let hubSheet = app.sheets["求助"].firstMatch
        XCTAssertTrue(hubSheet.waitForExistence(timeout: 5), "求助块没有打开求助中心")
        XCTAssertTrue(
            hubSheet.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "还没有发送求助")
            ).firstMatch.exists,
            "求助中心的第一句必须先说清什么都还没发出去"
        )
        XCTAssertFalse(
            hubSheet.staticTexts["是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"]
                .firstMatch.exists,
            "逐字锁定的二次确认文案不许被挪用成菜单正文"
        )

        // 云端那条走的仍是「一键求助」，且二次确认一步不减。
        hubSheet.buttons["一键求助"].firstMatch.tap()
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
        openSettings(app)

        let logoutButton = app.buttons["退出登录"].firstMatch
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 5), "Settings should expose logout")
        logoutButton.tap()

        XCTAssertTrue(app.alerts["确认退出"].firstMatch.waitForExistence(timeout: 5), "Logout should require confirmation")
        XCTAssertTrue(app.buttons["确认退出"].firstMatch.exists)
        XCTAssertTrue(app.buttons["取消"].firstMatch.exists)
    }

    // MARK: - 紧急联系人无障碍

    /// 列表行只播报掩码手机号，且朗读顺序为「概览 → 联系人 → 新增」。
    @MainActor
    func testContactRowAnnouncesMaskedPhoneInReadingOrder() throws {
        let app = launchBlindContactsApp()
        openContacts(app)

        let summary = app.staticTexts[Self.seededContactSummary].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 12))

        let row = app.staticTexts["张三，关系家人，电话139****9001，主联系人"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "行内容应合并成一条含掩码手机号的播报")
        XCTAssertFalse(
            app.staticTexts["13900139001"].firstMatch.exists,
            "列表不得展示或朗读完整手机号"
        )

        let addButton = app.buttons["新增紧急联系人"].firstMatch
        XCTAssertTrue(addButton.exists)
        XCTAssertLessThan(summary.frame.minY, row.frame.minY)
        XCTAssertLessThan(row.frame.minY, addButton.frame.minY)
    }

    /// 新增 → 编辑 → 删除的完整往返。
    @MainActor
    func testContactAddEditAndDeleteRoundTrip() throws {
        let app = launchBlindContactsApp()
        openContacts(app)
        waitForContactSummary(app, Self.seededContactSummary)

        addContact(app, name: "李四", phone: "13700137000", relationship: "朋友")
        waitForContactSummary(app, "共 2 位紧急联系人，最多 5 位。主联系人是张三。")
        XCTAssertTrue(
            app.staticTexts["李四，关系朋友，电话137****7000，非主联系人"].firstMatch.waitForExistence(timeout: 8),
            "新增后应回写重新拉取的整份列表"
        )

        let editButton = app.buttons["编辑李四"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 8))
        scrollElementIntoView(editButton, app: app)
        tapWhenHittableOrByCoordinate(editButton, app: app)
        XCTAssertTrue(app.navigationBars["编辑紧急联系人"].waitForExistence(timeout: 8))

        let phoneField = app.textFields["联系人手机号，必填，11 位"].firstMatch
        XCTAssertTrue(phoneField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForTextFieldValue(phoneField, equals: "13700137000", timeout: 5),
            "后端返回明文，编辑时应明文回填"
        )
        replaceText(in: phoneField, with: "13611116666", app: app)
        tapWhenHittableOrByCoordinate(app.buttons["保存"].firstMatch, app: app)
        XCTAssertTrue(
            waitForElementToDisappear(app.navigationBars["编辑紧急联系人"], timeout: 15),
            "保存成功后编辑表单应自动关闭"
        )

        XCTAssertTrue(
            app.staticTexts["李四，关系朋友，电话136****6666，非主联系人"].firstMatch.waitForExistence(timeout: 10)
        )

        deleteContact(app, named: "李四")
        waitForContactSummary(app, Self.seededContactSummary)
    }

    /// 设主联系人是原子的（旧主自动降级），且最后一位联系人不可删除。
    @MainActor
    func testSetPrimaryIsAtomicAndLastContactCannotBeDeleted() throws {
        let app = launchBlindContactsApp()
        openContacts(app)
        waitForContactSummary(app, Self.seededContactSummary)

        // 只剩一位时删除被本地守卫拦下，不发请求、不弹确认框。
        //
        // 拦截必须**自己弹出来**。它此前唯一的展示面是 `List` 末尾的一个 Section，2026-09-05
        // 真机实测（iPhone 16 Pro，window 高 874，**默认字号**，5 位联系人）：点完「删除张三」，
        // 那一行 **根本不在无障碍树里**（`List` 不渲染屏幕外的行），要往下滑一屏才出现在
        // minY=747.7 / maxY=820.0 —— 失败分支跑了、`speakError` 播了，屏幕上一个字都不多。
        // 这里只有 1 位联系人，那一行本来就在屏内，所以断言弹窗才是能抓住回归的写法：
        // 改回内联文字，`app.alerts` 这条立刻变红，与联系人有几位无关。
        // 同形状的缺陷在账号删除预检那里同日修过
        // （`testAuthLifecycleVolunteerDeletionRouteAndActiveOrderBlock`）。
        let deleteOnlyContact = app.buttons["删除张三"].firstMatch
        XCTAssertTrue(deleteOnlyContact.waitForExistence(timeout: 8))
        scrollElementIntoView(deleteOnlyContact, app: app)
        tapWhenHittableOrByCoordinate(deleteOnlyContact, app: app)
        let blocked = app.alerts["紧急联系人提示"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 8))
        XCTAssertTrue(blocked.staticTexts["至少需要保留 1 位紧急联系人，不能删除最后一位。"].exists)
        XCTAssertFalse(app.alerts["确认删除联系人"].exists, "被拦下的删除不应弹出确认框")
        blocked.buttons["知道了"].tap()
        XCTAssertTrue(waitForElementToDisappear(blocked, timeout: 8))

        addContact(app, name: "李四", phone: "13700137000", relationship: "朋友")
        XCTAssertTrue(
            app.staticTexts["李四，关系朋友，电话137****7000，非主联系人"].firstMatch.waitForExistence(timeout: 15)
        )

        let setPrimary = app.buttons["把李四设为主联系人"].firstMatch
        XCTAssertTrue(setPrimary.waitForExistence(timeout: 8))
        scrollElementIntoView(setPrimary, app: app)
        tapWhenHittableOrByCoordinate(setPrimary, app: app)
        let primaryAlert = app.alerts["确认设为主联系人"]
        XCTAssertTrue(primaryAlert.waitForExistence(timeout: 8), "切换主联系人需要二次确认")
        primaryAlert.buttons["设为主联系人"].tap()
        XCTAssertTrue(waitForElementToDisappear(primaryAlert, timeout: 8), "确认后弹窗应关闭")

        waitForContactSummary(app, "共 2 位紧急联系人，最多 5 位。主联系人是李四。")
        XCTAssertTrue(
            app.staticTexts["张三，关系家人，电话139****9001，非主联系人"].firstMatch.waitForExistence(timeout: 8),
            "原主联系人必须同步降级，保持恰好一位主联系人"
        )
    }

    /// 达到 5 位上限后新增被禁用并说明原因。
    @MainActor
    func testContactUpperLimitBlocksTheSixthContact() throws {
        let app = launchBlindContactsApp()
        openContacts(app)
        waitForContactSummary(app, Self.seededContactSummary)

        for index in 2...5 {
            addContact(app, name: "联系人\(index)", phone: "1370013700\(index)", relationship: "朋友")
            waitForContactSummary(app, "共 \(index) 位紧急联系人，最多 5 位。主联系人是张三。")
        }

        let addButton = app.buttons["新增紧急联系人"].firstMatch
        scrollUntilExists(addButton, app: app)
        XCTAssertTrue(addButton.waitForExistence(timeout: 8))
        scrollElementIntoView(addButton, app: app)

        // 上限文案排在按钮下方，同样可能还没渲染
        let limitNotice = app.staticTexts["已保存 5 位紧急联系人，达到上限。如需新增，请先删除一位。"].firstMatch
        scrollUntilExists(limitNotice, app: app)
        XCTAssertTrue(limitNotice.waitForExistence(timeout: 8))
        XCTAssertFalse(addButton.isEnabled, "到达上限后新增按钮必须禁用")
    }


    @MainActor
    func testAuthLifecycleRolelessRestoreRoutesToRoleSelection() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "roleless-token",
            activeRole: nil,
            emptyMockOrders: true
        )

        XCTAssertTrue(
            app.buttons["我是盲人跑者，预约志愿者陪我跑步"].firstMatch.waitForExistence(timeout: 10),
            "Valid role-less session should route to role selection"
        )
        XCTAssertFalse(app.staticTexts["正在验证登录状态"].exists)
    }

    @MainActor
    func testAuthLifecycleLogoutFailureOffersWarnedLocalOnlyFallback() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "logout-failure-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            mockLogoutFailure: true
        )
        openSettings(app)
        app.buttons["退出登录"].tap()
        app.buttons["确认退出"].tap()

        let alert = app.alerts["服务端退出失败"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "远端 Token 继续有效")).firstMatch.exists)
        XCTAssertTrue(app.buttons["重试"].exists)
        XCTAssertTrue(app.buttons["仅退出本机"].exists)
        app.buttons["仅退出本机"].tap()
        XCTAssertTrue(app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testAuthLifecycleEveryLogoutSurfaceRequiresConfirmation() throws {
        let blindProfile = launchApp(
            apiEnvironment: "mock",
            accessToken: "blind-profile-token",
            activeRole: "blind_runner",
            emptyMockOrders: true
        )
        // 盲人侧没有「直接暴露退出登录」的界面：首页和引导流都只放设置入口，
        // 退出登录统一收在 BlindRunnerSettingsView（见 BlindRunnerOnboardingView 的容器注释）。
        openSettings(blindProfile)
        assertLogoutRequiresConfirmation(blindProfile)

        // 志愿者资料页（`VolunteerModule` 的 header）是除设置页外唯一直接摆出退出登录的界面，
        // 只有未注册的志愿者才会停在这一页——不加 `unregisteredVolunteer` 的话 Mock 会喂一份
        // 已完成注册的资料，根路由直接进首页，这一档就退化成和下面设置页那档重复。
        let volunteerProfile = launchApp(
            apiEnvironment: "mock",
            accessToken: "volunteer-profile-token",
            activeRole: "volunteer",
            unregisteredVolunteer: true,
            emptyMockOrders: true
        )
        assertLogoutRequiresConfirmation(volunteerProfile)

        let volunteerSettings = launchApp(
            apiEnvironment: "mock",
            accessToken: "volunteer-settings-token",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            emptyMockOrders: true
        )
        openSettings(volunteerSettings)
        assertLogoutRequiresConfirmation(volunteerSettings)
    }

    @MainActor
    func testAuthLifecycleBlindAccountDeletionIsTwoStageAndCompletesOnce() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "blind-delete-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
        openSettings(app)
        let deleteButton = app.buttons["删除账户"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteButton.isEnabled)
        deleteButton.tap()

        let initialAlert = app.alerts["确认删除账户"].firstMatch
        XCTAssertTrue(initialAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(initialAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "仍需再次确认")).firstMatch.exists)
        app.buttons["继续删除账户"].tap()

        let finalAlert = app.alerts["最终确认删除账户"].firstMatch
        XCTAssertTrue(finalAlert.waitForExistence(timeout: 8))
        // 文案内容**不在这里断**。它的主是单测 `testAccountDeletionCopyStatesWhatIsDeletedAndWhatIsKept`
        // （`blindRunTests/blindRunTests.swift`），那条进程内直接对
        // `AccountDeletionViewModel.finalConfirmationMessage(for:)` 断言，拿得到真源。
        // 这里再抄一份字面量只会周期性漂移 —— `9f9cede` 把「会失效」改成「立即失效」，
        // 单测跟着改了，抄在这儿的那份没有，于是这条用例红了 7 天。
        // UI 用例守的是流程：两段式弹窗、且只提交一次。
        let finalButton = app.buttons["永久删除账户"].firstMatch
        XCTAssertTrue(finalButton.exists)
        finalButton.tap()
        XCTAssertTrue(
            finalButton.waitForNonExistence(timeout: 2),
            "Final destructive action must disappear promptly to prevent duplicate submission"
        )
        XCTAssertTrue(app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testAuthLifecycleVolunteerDeletionRouteAndActiveOrderBlock() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "volunteer-delete-token",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerActiveOrder: true
        )
        openSettings(app)
        app.buttons["删除账户"].tap()
        XCTAssertTrue(app.alerts["确认删除账户"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["继续删除账户"].tap()

        // 拦截必须**自己弹出来**，而不是往设置页 `List` 末尾追加一行。
        // 这条断言原本找的就是那一行 `StaticText`，从 `089960e`（#76，设置页加了三个激励入口）
        // 起一直红：那一行被挤到第二屏，而 `List` 不渲染屏幕外的行 —— 屏幕上一个字都没多出来。
        // 拦截本身一直是好的（失败快照里没有「最终确认删除账户」弹窗），坏的是它没有可见的落点。
        // 文案内容不在这里断，主在单测 `testAccountDeletionPreflightSpeaksActiveOrderBlock`。
        let blocked = app.alerts["无法删除账户"].firstMatch
        XCTAssertTrue(blocked.waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts["最终确认删除账户"].exists)
        blocked.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["退出登录"].exists, "Blocked deletion must preserve the signed-in settings state")
    }

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

        // 🔴 志愿者首页**没有任何地图了**（2026-09-15 随「派单工作台」一起删）。
        // 真 key 构建下唯一该出现的志愿者地图在「服务中」页，即下面 `volunteerServiceMapBackdrop`
        // 那条。这里只断言首页确实一张都没有 —— 配了真 key 也不该冒出来。
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

        openCurrentVolunteerService(volunteerApp)
        XCTAssertTrue(
            volunteerApp.descendants(matching: .any)["volunteerServiceMapBackdrop"].firstMatch.waitForExistence(timeout: 20),
            "Real AMap run should expose the volunteer service map container"
        )
        XCTAssertFalse(volunteerApp.staticTexts["地图服务暂不可用"].exists, "Real AMap smoke must not fall back to the missing-key placeholder")
        XCTAssertFalse(volunteerApp.staticTexts["请配置高德地图 API Key"].exists, "Real AMap smoke requires a configured local AMap key")

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
            disableWebSocket: false
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

    private var isPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    private var shouldRunRealAMapSmoke: Bool {
        ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_REAL_AMAP"] == "1" || isPhysicalDevice
    }

    private var shouldRunCloudSmoke: Bool {
        ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_RUN_CLOUD_SMOKE"] == "1" || isPhysicalDevice
    }

    private func launchApp(
        apiEnvironment: String,
        accessToken: String? = nil,
        activeRole: String? = "blind_runner",
        preseedBlindProfile: Bool = false,
        preseedVolunteerProfile: Bool = false,
        preseedVolunteerAvailable: Bool = false,
        preseedVolunteerActiveOrder: Bool = false,
        /// 直接把预置订单落在某个状态上（`AIDRUN_UI_TEST_SEED_ORDER_STATUS`），
        /// 免得为了验一个 `IN_PROGRESS` 的行为先走完出发 / 到达 / 开始三步。
        /// 走那三步的用例会连带吃掉沿途每一条断言的红灯，验的东西就不是自己那一条了。
        seedOrderStatus: String? = nil,
        forceRealVolunteerRegistration: Bool = false,
        unregisteredVolunteer: Bool = false,
        legacyTrainingStatusAfterFaceVerify: Bool = false,
        emptyMockOrders: Bool = false,
        disableMap: Bool = true,
        disableWebSocket: Bool = true,
        mockLogoutFailure: Bool = false,
        realtimePriorityTest: Bool = false,
        hangHomeRequests: Bool = false,
        hangTransitionConfirmation: Bool = false,
        confirmTransitionViaRealtime: Bool = false,
        hangEscortLocationSend: Bool = false,
        homeLoadTimeout: TimeInterval? = nil,
        forcePrivacyConsent: Bool = false,
        contentSizeCategory: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        // 误触求助条 = 真的拨 110（2026-08-14 差一层双卡选号单就拨出去了）。
        // DEBUG 构建里这个开关让 `EmergencyDialer.dial` 只记一次痕迹、不真的拨号。
        // 别的启动 helper 不必重复这一行：没显式设时 `EmergencyDialer.resolveDialBlock`
        // 认 `AIDRUN_UI_TEST_RESET_STATE` 就默认拦。
        app.launchEnvironment["AIDRUN_UI_TEST_BLOCK_TEL_DIAL"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = apiEnvironment
        if let activeRole {
            app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = activeRole
        }
        app.launchEnvironment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] = "1"
        if disableWebSocket {
            app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        }
        if disableMap {
            app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"
        }
        if realtimePriorityTest {
            app.launchEnvironment["AIDRUN_UI_TEST_REALTIME_PRIORITY"] = "1"
        }
        if hangHomeRequests {
            app.launchEnvironment["AIDRUN_UI_TEST_HANG_HOME_REQUESTS"] = "1"
        }
        if hangTransitionConfirmation {
            app.launchEnvironment["AIDRUN_UI_TEST_HANG_TRANSITION_CONFIRMATION"] = "1"
        }
        if confirmTransitionViaRealtime {
            app.launchEnvironment["AIDRUN_UI_TEST_CONFIRM_TRANSITION_VIA_REALTIME"] = "1"
        }
        if hangEscortLocationSend {
            app.launchEnvironment["AIDRUN_UI_TEST_HANG_ESCORT_SEND"] = "1"
        }
        if let homeLoadTimeout {
            app.launchEnvironment["AIDRUN_UI_TEST_HOME_LOAD_TIMEOUT"] = String(homeLoadTimeout)
        }
        if let accessToken {
            app.launchEnvironment["AIDRUN_UI_TEST_ACCESS_TOKEN"] = accessToken
        }
        if preseedBlindProfile {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE"] = "1"
        }
        if preseedVolunteerProfile {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_PROFILE"] = "1"
        }
        if preseedVolunteerAvailable {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] = "1"
        }
        if preseedVolunteerActiveOrder {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_ACTIVE_ORDER"] = "1"
        }
        if let seedOrderStatus {
            app.launchEnvironment["AIDRUN_UI_TEST_SEED_ORDER_STATUS"] = seedOrderStatus
        }
        if forceRealVolunteerRegistration {
            app.launchEnvironment["AIDRUN_UI_TEST_FORCE_REAL_REGISTRATION"] = "1"
        }
        if unregisteredVolunteer {
            app.launchEnvironment["AIDRUN_UI_TEST_UNREGISTERED_VOLUNTEER"] = "1"
        }
        if legacyTrainingStatusAfterFaceVerify {
            app.launchEnvironment["AIDRUN_UI_TEST_LEGACY_TRAINING_STATUS"] = "1"
        }
        if emptyMockOrders {
            app.launchEnvironment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] = "1"
        }
        if mockLogoutFailure {
            app.launchEnvironment["AIDRUN_MOCK_LOGOUT_FAILURE"] = "1"
        }
        // 同意门默认跳过（判定在 `AppState.resolveInitialPrivacyConsent`）：UI 用例一律
        // `RESET_STATE`，不跳过的话每一条都会被挡在告知页，断言全红。只有专测它的用例打开这一条。
        if forcePrivacyConsent {
            app.launchEnvironment["AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT"] = "1"
        }
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
        app.launch()
        dismissSystemAlertsIfPresent(app: app)
        return app
    }

    /// 打开盲人端的设置。
    ///
    /// 🔄 **2026-09-16 起走「我的」tab，不再是首页右上角的悬浮齿轮。**
    /// 齿轮已随首页改版删除（设计稿的首页只有问候 + 订单卡 + 预约块）。
    /// 抽成 helper 的价值就在这里：入口换了一次，三个调用点一起跟上。
    private func openSettings(_ app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 12), "盲人端标签栏没起来，够不到设置")
        let profileTab = tabBar.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5), "标签栏缺少「我的」")
        profileTab.tap()
        XCTAssertTrue(
            app.navigationBars["设置"].waitForExistence(timeout: 10),
            "「我的」tab 里没有设置页"
        )
    }

    // MARK: - 紧急联系人 helpers

    /// Mock 种子联系人（`MockAPIClient.seedDemoData`）：张三 / 13900139001 / 家人 / 主联系人。
    private static let seededContactSummary = "共 1 位紧急联系人，最多 5 位。主联系人是张三。"

    private func launchBlindContactsApp() -> XCUIApplication {
        launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
    }

    /// 首页 → 设置 → 个人资料 → 管理紧急联系人。
    ///
    /// 设置页没有「紧急联系人」直达行，管理页挂在个人资料页下面，所以是三跳。
    private func openContacts(_ app: XCUIApplication) {
        openSettings(app)
        tapNavigationRow(app, labelBeginsWith: "个人资料")
        tapNavigationRow(app, labelBeginsWith: "管理紧急联系人")
        XCTAssertTrue(
            app.navigationBars["紧急联系人"].waitForExistence(timeout: 12),
            "应已进入紧急联系人管理页"
        )
    }

    private func addContact(_ app: XCUIApplication, name: String, phone: String, relationship: String) {
        let addButton = app.buttons["新增紧急联系人"].firstMatch
        // 必须先滚：联系人到 4 个时列表已经把「新增」入口顶出屏幕，SwiftUI List 不渲染屏幕外的行，
        // 元素根本不在无障碍树里 —— 先断言存在会直接失败，而 scrollElementIntoView 又要求元素已存在。
        scrollUntilExists(addButton, app: app)
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        scrollElementIntoView(addButton, app: app)
        tapWhenHittableOrByCoordinate(addButton, app: app)
        XCTAssertTrue(app.navigationBars["新增紧急联系人"].waitForExistence(timeout: 8))

        let nameField = app.textFields["联系人姓名，必填"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        tapWhenHittableOrByCoordinate(nameField, app: app)
        nameField.typeText(name)

        let phoneField = app.textFields["联系人手机号，必填，11 位"].firstMatch
        tapWhenHittableOrByCoordinate(phoneField, app: app)
        phoneField.typeText(phone)

        let relationshipField = app.textFields["与联系人的关系，选填"].firstMatch
        tapWhenHittableOrByCoordinate(relationshipField, app: app)
        relationshipField.typeText(relationship)

        // 「保存」在导航栏，不会被键盘挡住，所以不需要先收键盘。
        tapWhenHittableOrByCoordinate(app.buttons["保存"].firstMatch, app: app)
        XCTAssertTrue(
            waitForElementToDisappear(app.navigationBars["新增紧急联系人"], timeout: 15),
            "保存成功后新增表单应自动关闭"
        )
    }

    private func deleteContact(_ app: XCUIApplication, named name: String) {
        let deleteButton = app.buttons["删除\(name)"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 8))
        scrollElementIntoView(deleteButton, app: app)
        tapWhenHittableOrByCoordinate(deleteButton, app: app)

        let alert = app.alerts["确认删除联系人"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "删除是危险操作，必须二次确认")
        alert.buttons["确认删除"].tap()
        XCTAssertTrue(waitForElementToDisappear(alert, timeout: 8), "确认后弹窗应关闭")
    }

    /// 概览行在列表顶部，联系人多起来后会被滚出可见区、单元格被回收而查不到。
    /// 先直接等，等不到再往回滚一屏确认一次。
    private func waitForContactSummary(_ app: XCUIApplication, _ expected: String) {
        let summary = app.staticTexts[expected].firstMatch
        if summary.waitForExistence(timeout: 12) { return }
        scrollableSurface(app).swipeDown()
        scrollableSurface(app).swipeDown()
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "紧急联系人概览应更新为「\(expected)」")
    }

    private func replaceText(in field: XCUIElement, with newValue: String, app: XCUIApplication) {
        tapWhenHittableOrByCoordinate(field, app: app)
        let current = (field.value as? String) ?? ""
        if !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(newValue)
    }

    /// List 里的 `NavigationLink` 可能暴露成 button 也可能暴露成 cell，两种都试。
    private func tapNavigationRow(_ app: XCUIApplication, labelBeginsWith prefix: String) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 10) {
            scrollElementIntoView(button, app: app)
            tapWhenHittableOrByCoordinate(button, app: app)
            return
        }
        let cell = app.cells.matching(predicate).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "未找到以「\(prefix)」开头的入口")
        scrollElementIntoView(cell, app: app)
        tapWhenHittableOrByCoordinate(cell, app: app)
    }

    /// 把控件滚进可见区。判据是"中心点落在可见区内"而不是 `isHittable`：
    /// 禁用态的按钮永远不 hittable，用 `isHittable` 会让上限用例白白滑满 maxSwipes 次。
    /// 在惰性渲染的列表里把元素**滚到渲染出来**。
    ///
    /// 与 `scrollElementIntoView` 的分工：那个第一行就是 `guard element.exists else { return }`，
    /// 只能处理「已在无障碍树里、但不在可视区」；而 SwiftUI 的 List 对屏幕外的行根本不渲染，
    /// 元素压根不在树里，`exists` 为 false，那个 helper 会直接放弃、`waitForExistence` 也永远等不到。
    /// 联系人列表随数量增长会把下方的「新增」入口顶出屏幕，必须先滚动才谈得上断言存在。
    @discardableResult
    private func scrollUntilExists(_ element: XCUIElement, app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        if element.exists { return true }
        for _ in 0..<maxSwipes {
            scrollableSurface(app).swipeUp()
            if element.exists { return true }
        }
        return element.exists
    }

    /// 底部常驻栏（`safeAreaInset(edge: .bottom)`）画在滚动内容之上：落在它下面的控件
    /// `isHittable` 仍然是 `true`，但触点会被钳到栏上。
    ///
    /// 2026-08-14 因此在盲人首页误触常驻求助条、差点拨出 110（`a68bed4`）；2026-08-22 二分
    /// 确认它自 `30b0770` 起复发（`docs/review/ui-test-red-triage-20260822.md`）。当时的判据
    /// 只问「在屏幕矩形内」—— 真机 402×874 上「重复当前状态」在 y 763–827、求助条在 y 772–836，
    /// 中心点 795 落在 `insetBy(dy: 44)` 给出的 44…830 里，于是 helper 一次都没滚就返回了。
    ///
    /// ponytail: 固定 112pt，不去查每个底栏的真实高度 —— 那要按 identifier 逐个登记，而全仓有
    /// 9 处 `safeAreaInset(edge: .bottom)`，登记表必然漏掉下一个。代价是在没有底栏的页面多滚
    /// 一两下（无害）。真要精确时再改成按 identifier 取底栏 frame。
    /// （盲人首页实测底栏顶边 772，874 − 772 = 102，这里留 10pt 余量。）
    private static let persistentBottomBarInset: CGFloat = 112

    /// 把控件滚进「真正能点」的区域。
    ///
    /// 判据是「中心点在可见区内 **且** 整个 frame 不越过可见区底边」：只判中心点会放过
    /// 下半截被底栏盖住的控件 —— 那正是上面那次误触的成因。用中心点而不是 `isHittable`：
    /// 禁用态的按钮永远不 hittable，用它会让上限用例白白滑满 `maxSwipes` 次。
    ///
    /// 返回是否真的滚到位。**底部有常驻栏的页面必须断言返回值** —— 否则滚不动时这里静默放弃，
    /// 接下来的 `tap()` 打在别的控件上，报出来的错和真因毫无关系。
    @discardableResult
    private func scrollElementIntoView(_ element: XCUIElement, app: XCUIApplication, maxSwipes: Int = 5) -> Bool {
        let appFrame = app.frame
        guard !appFrame.isNull, !appFrame.isEmpty else { return false }
        let top = appFrame.minY + 44
        let bottom = min(
            appFrame.maxY - Self.persistentBottomBarInset,
            measuredBottomBarTop(app) ?? .greatestFiniteMagnitude
        )
        guard bottom > top else { return false }
        let visibleArea = CGRect(x: appFrame.minX, y: top, width: appFrame.width, height: bottom - top)

        func isUncovered() -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            guard !frame.isNull, !frame.isEmpty else { return false }
            return visibleArea.contains(CGPoint(x: frame.midX, y: frame.midY))
                && frame.maxY <= visibleArea.maxY
        }

        for _ in 0..<maxSwipes {
            if isUncovered() { return true }
            guard element.exists else { return false }
            scrollableSurface(app).swipeUp()
        }
        return isUncovered()
    }

    /// 量得到真实高度的底栏，返回它的顶边；量不到返回 `nil`（退回固定的 112pt）。
    ///
    /// 🔴 **为什么这个不能只靠上面那个常量**：112 是照盲人首页的底栏（实测 102pt）定的，
    /// 而志愿者「我」首屏底部那条可服务 CTA 在**已开启**时轨道里是两行字（主文案 + 副提示），
    /// AX5 下更高 —— 实测远超 112。常量偏小的后果不是「多滚一下」，
    /// 而是 helper 认为控件已经露出来了、直接返回 true，接着 `tap()` 打在底栏上。
    /// 那正是 2026-08-14 差点拨出 110 的同一个形状。
    ///
    /// ponytail: 只登记**已知会超过 112pt 的**那一个，不做全量登记表 ——
    /// 上面那条注释说得对，登记表必然漏掉下一个。这里漏掉的会退回旧行为，不会变得更糟。
    private func measuredBottomBarTop(_ app: XCUIApplication) -> CGFloat? {
        ["volunteerAvailabilitySlider"]
            .map { app.descendants(matching: .any)[$0].firstMatch }
            .filter { $0.exists }
            .map(\.frame)
            .filter { !$0.isNull && !$0.isEmpty }
            .map(\.minY)
            .min()
    }

    private func scrollableSurface(_ app: XCUIApplication) -> XCUIElement {
        for candidate in [
            app.collectionViews.firstMatch,
            app.tables.firstMatch,
            app.scrollViews.firstMatch
        ] where candidate.exists {
            return candidate
        }
        return app
    }

    private func assertLogoutRequiresConfirmation(_ app: XCUIApplication) {
        let logoutButton = app.buttons["退出登录"].firstMatch
        XCTAssertTrue(logoutButton.waitForExistence(timeout: 10))
        logoutButton.tap()
        XCTAssertTrue(app.alerts["确认退出"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["确认退出"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)
    }

    private func openAcceptedVolunteerService(_ app: XCUIApplication) {
        openCurrentVolunteerService(app)

        let enRouteButton = app.buttons["我已出发"].firstMatch
        XCTAssertTrue(enRouteButton.waitForExistence(timeout: 5), "Accepted service page should show en-route action")
        enRouteButton.tap()
    }

    private func openCurrentVolunteerService(
        _ app: XCUIApplication,
        requirePhone: Bool = true
    ) {
        let currentOrderLabel = app.staticTexts["当前订单"].firstMatch
        XCTAssertTrue(currentOrderLabel.waitForExistence(timeout: 15), "Volunteer home should show the assigned current order")

        let firstOrder = app.staticTexts["李明"].firstMatch
        XCTAssertTrue(firstOrder.waitForExistence(timeout: 5), "Current order card should show the assigned blind runner")
        tapWhenHittableOrByCoordinate(firstOrder, app: app)

        if requirePhone {
            // 号码上屏是**掩码**的（`VolunteerOrderFlowViews.swift` 走 `EmergencyContactResponse.maskPhone`）：
            // VoiceOver 外放，念全号等于把盲人的号码广播给周围所有人（`f404de2` / 审计 F10）。
            // 全号只进 `tel:`，所以这里两条一起断 —— 只断掩码的话，拨号按钮被删掉也不会有人发现，
            // 而那是志愿者接单后唯一够得到真号的出口。
            let maskedPhone = app.staticTexts["138****1001"].firstMatch
            XCTAssertTrue(
                maskedPhone.waitForExistence(timeout: 8),
                "接单后应展示掩码号码，全号不上屏、不朗读"
            )
            XCTAssertFalse(
                app.staticTexts["13800001001"].firstMatch.exists,
                "全号不得作为可见文本出现"
            )
            XCTAssertTrue(
                app.buttons["拨打盲人电话"].firstMatch.exists,
                "掩码之后，拨号按钮是志愿者够到真号的唯一出口"
            )
        } else {
            XCTAssertTrue(app.navigationBars["服务中"].waitForExistence(timeout: 8))
        }
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func login(app: XCUIApplication, phone: String, code: String = "000000") {
        let phoneField = app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch
        XCTAssertTrue(phoneField.waitForExistence(timeout: 10), "Login phone field should appear")
        tapWhenHittableOrByCoordinate(phoneField, app: app)
        phoneField.typeText(phone)
        dismissKeyboardIfPresent(app: app)

        let requestCodeButton = app.buttons["获取验证码"].firstMatch
        XCTAssertTrue(waitForElementToBeEnabled(requestCodeButton, timeout: 5), "Request code button should be enabled after entering a valid phone")
        tapWhenHittableOrByCoordinate(requestCodeButton, app: app)
        dismissSystemAlertsIfPresent(app: app, activateWhenNoAlert: false)

        let codeField = app.textFields["验证码输入框，请输入 6 位验证码"].firstMatch
        XCTAssertTrue(codeField.waitForExistence(timeout: 5), "Verification code field should appear")
        XCTAssertTrue(
            waitForElementToBeHittable(codeField, timeout: 5),
            "Verification code field should be visible and ready for typing after requesting a code"
        )
        tapWhenHittableOrByCoordinate(codeField, app: app)
        codeField.typeText(code)
        dismissKeyboardIfPresent(app: app)

        let loginButton = app.buttons["登录"].firstMatch
        XCTAssertTrue(waitForElementToBeEnabled(loginButton, timeout: 5), "Login button should be enabled after entering the fixed demo code")
        tapWhenHittableOrByCoordinate(loginButton, app: app)
        dismissSystemAlertsIfPresent(app: app, activateWhenNoAlert: false)
        waitForPostLoginRoute(app)
    }

    private func tapWhenHittableOrByCoordinate(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected element to exist before tapping")
        if element.isHittable {
            element.tap()
            return
        }

        let elementFrame = element.frame
        let appFrame = app.frame
        if !elementFrame.isNull && !elementFrame.isEmpty && !appFrame.isNull && !appFrame.isEmpty {
            let centerX = elementFrame.midX / appFrame.width
            let centerY = elementFrame.midY / appFrame.height
            app.coordinate(withNormalizedOffset: CGVector(dx: centerX, dy: centerY)).tap()
            return
        }

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func chooseBlindRunnerRoleIfNeeded(_ app: XCUIApplication) {
        waitForPostLoginRoute(app)
        let blindRoleButton = app.buttons["我是盲人跑者，预约志愿者陪我跑步"].firstMatch
        if blindRoleButton.waitForExistence(timeout: 8) {
            blindRoleButton.tap()
            dismissSystemAlertsIfPresent(app: app)
        }
    }

    private func completeBlindRunnerProfileIfNeeded(_ app: XCUIApplication) {
        let title = app.staticTexts["完善信息"].firstMatch
        let editTitle = app.staticTexts["编辑资料"].firstMatch
        guard title.waitForExistence(timeout: 8) || editTitle.exists else { return }

        enterTextIfNeeded(app: app, fieldLabel: "昵称，必填", placeholder: "请输入昵称", text: "UITestBlind")
        enterTextIfNeeded(app: app, fieldLabel: "紧急联系人姓名，必填", placeholder: "请输入紧急联系人姓名", text: "UITestContact")
        enterTextIfNeeded(app: app, fieldLabel: "紧急联系人电话，必填，11位手机号", placeholder: "请输入11位手机号", text: "13800001111")
        dismissKeyboardIfPresent(app: app)

        let saveButton = firstExistingButton(app, labels: ["完成，保存资料", "保存，保存资料"])
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Profile save button should appear")
        XCTAssertTrue(waitForElementToBeEnabled(saveButton, timeout: 5), "Profile save button should be enabled")
        tapWhenHittableOrByCoordinate(saveButton, app: app)
        dismissSystemAlertsIfPresent(app: app, activateWhenNoAlert: false)
    }

    /// 这个用例验的是**下单链路**，不是分步表单的步数。
    ///
    /// 2026-08-08 起预约页是语音态 / 表单态二选一，进来落在哪一步由麦克风授权决定：
    /// 授权成功时向导把表单同步到确认步（能直接提交），被拒时才停在第 1 步。
    /// 原来写死「第 1 步 → 第 2 步 → 第 3 步 → 提交」的走法在前一种设备上必挂，
    /// 而挂的原因和下单链路无关。所以改成：先退出语音，然后一路按主操作走到「提交预约」。
    private func createBookingAndAssertMatching(_ app: XCUIApplication) {
        // 2026-09-16 起首页的下单入口是浅蓝「预约新的陪跑」块。identifier 与改版前逐字相同，
        // 所以按 identifier 找而不是按中文标签 —— 标签这一轮就改了，而 guard 的
        // `stale-ui-test-identifier` 只对 identifier 做双向校验，抓不到中文文案漂移。
        let startButton = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 12), "Blind runner home should show start booking")
        startButton.tap()

        let stopVoice = app.descendants(matching: .any)["blindBookingStopVoiceButton"].firstMatch
        if stopVoice.waitForExistence(timeout: 8) {
            stopVoice.tap()
        }

        let submitButton = app.buttons["提交预约"].firstMatch
        let nextActionLabels = ["下一步：预约时间", "下一步：跑步需求", "下一步：确认预约"]
        let deadline = Date().addingTimeInterval(45)
        while !submitButton.exists, Date() < deadline {
            guard let next = nextActionLabels
                .map({ app.buttons[$0].firstMatch })
                .first(where: { $0.exists && $0.isEnabled })
            else {
                _ = submitButton.waitForExistence(timeout: 2)
                continue
            }
            next.tap()
        }

        XCTAssertTrue(submitButton.waitForExistence(timeout: 10), "Guided booking should reach the submit step")
        XCTAssertTrue(waitForElementToBeEnabled(submitButton, timeout: 10), "Submit booking button should be enabled with demo location")
        submitButton.tap()
        dismissSystemAlertsIfPresent(app: app)

        let matchingStatus = app.staticTexts["系统派单中"].firstMatch
        XCTAssertTrue(matchingStatus.waitForExistence(timeout: 15), "Created booking should enter system dispatch status")
    }

    private func cancelCurrentOrder(_ app: XCUIApplication) {
        let cancelButton = app.buttons["取消订单"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Cloud smoke test should clean up its pending order")
        cancelButton.tap()

        let confirmButton = app.buttons["确认取消"].firstMatch
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Cancellation should require confirmation")
        confirmButton.tap()

        XCTAssertTrue(
            app.staticTexts["已取消"].firstMatch.waitForExistence(timeout: 10),
            "Cloud smoke test order should be cancelled after verification"
        )
    }

    private func enterTextIfNeeded(app: XCUIApplication, fieldLabel: String, placeholder: String, text: String) {
        let field = app.textFields[fieldLabel].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(fieldLabel) should appear")
        if let currentValue = field.value as? String,
           !currentValue.isEmpty,
           currentValue != placeholder {
            return
        }

        field.tap()
        field.typeText(text)
    }

    private func waitForPostLoginRoute(_ app: XCUIApplication) {
        let role = app.buttons["我是盲人跑者，预约志愿者陪我跑步"].firstMatch
        let profile = app.staticTexts["完善信息"].firstMatch
        let editProfile = app.staticTexts["编辑资料"].firstMatch
        // 同上：按 identifier，不按已改的中文标签。此前这里是 `buttons["开始约跑"]`，
        // 改版后恒为 false —— 同一个 OR 里有 `rootRoute.blindHome` 兜着，所以不会让用例变红，
        // 但下次有人据它判断「首页起来了」会拿到一个永远不成立的探针。
        let home = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        let homeRoute = app.descendants(matching: .any)["rootRoute.blindHome"].firstMatch
        let error = app.staticTexts["网络错误，请重试。"].firstMatch
        let loginFailed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "登录失败")).firstMatch
        let invalidCode = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "验证码错误")).firstMatch
        let throttled = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "请求过于频繁")).firstMatch

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            dismissSystemAlertsIfPresent(app: app, activateWhenNoAlert: false)
            if error.exists {
                XCTFail("Cloud backend login failed with network error")
                return
            }
            if loginFailed.exists {
                XCTFail("Cloud backend login failed with generic login error")
                return
            }
            if invalidCode.exists {
                XCTFail("Cloud backend rejected the verification code")
                return
            }
            if throttled.exists {
                XCTFail("Cloud backend throttled the login request")
                return
            }
            if role.exists || profile.exists || editProfile.exists || home.exists || homeRoute.exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        attachScreenshot(named: "cloud-login-route-timeout", app: app)
        XCTFail("Login did not route to role selection, profile, or blind runner home. App state: \(app.state.rawValue). UI: \(app.debugDescription)")
    }

    private func firstExistingButton(_ app: XCUIApplication, labels: [String]) -> XCUIElement {
        for label in labels {
            let button = app.buttons[label].firstMatch
            if button.exists {
                return button
            }
        }
        return app.buttons[labels[0]].firstMatch
    }

    private func waitForElementToBeEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.isEnabled
    }

    private func waitForElementToBeHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.isHittable
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return !element.exists
    }

    /// 退栈并确认真的退回去了。
    ///
    /// 直接 `tap()` 完就断言上一页的元素会 flaky：调用方那条用例故意让首页请求永不返回，
    /// 加载超时后首页会重绘，撞上退栈动画时返回键的这一下有概率被吞掉，
    /// 于是「等积分商城按钮出现」白等 5 秒。这里改成先等返回键可点、点完再确认导航栏消失，
    /// 被吞掉就补一次，把时序竞争关在helper 里。
    private func popNavigationBar(_ app: XCUIApplication, title: String) {
        let navigationBar = app.navigationBars[title]
        let backButton = navigationBar.buttons.firstMatch
        XCTAssertTrue(waitForElementToBeHittable(backButton, timeout: 5), "\(title) 的返回键应当可点")
        backButton.tap()

        if waitForElementToDisappear(navigationBar, timeout: 3) { return }
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        }
        XCTAssertTrue(waitForElementToDisappear(navigationBar, timeout: 5), "应当已退出「\(title)」")
    }

    private func waitForTextFieldValue(_ element: XCUIElement, equals expectedValue: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return (element.value as? String) == expectedValue
    }

    private func assertVolunteerTopStatusBlockPosition(
        _ topStatusBlock: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let appStatusBar = app.statusBars.firstMatch
        let springboardStatusBar = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        if appStatusBar.exists || springboardStatusBar.exists {
            let statusBar = appStatusBar.exists ? appStatusBar : springboardStatusBar
            XCTAssertGreaterThanOrEqual(
                topStatusBlock.frame.minY,
                statusBar.frame.maxY - 1,
                "Volunteer status block should remain below the system status area",
                file: file,
                line: line
            )
        } else {
            XCTAssertGreaterThanOrEqual(
                topStatusBlock.frame.minY,
                20,
                "Volunteer status block should preserve a conservative top safe area when iPadOS does not expose a status-bar accessibility element",
                file: file,
                line: line
            )
        }
        XCTAssertLessThan(
            topStatusBlock.frame.minY,
            100,
            "Volunteer status block should remain at the top instead of double-counting the safe area",
            file: file,
            line: line
        )
    }

    private func assertNoEmergencyAction(
        _ app: XCUIApplication,
        _ why: String = "SOS 只在服务进行中出现，任何一方都一样",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(
            app.buttons["一键求助，遇到紧急情况时点击"].firstMatch.exists, why, file: file, line: line
        )
        XCTAssertFalse(app.buttons["一键求助"].firstMatch.exists, why, file: file, line: line)
    }

    /// 求助按钮必须**点得到**，不只是存在于无障碍树里。
    ///
    /// `exists` 只说明控件被渲染进了树，一个被面板挤出屏幕、或被其它视图盖住的按钮同样 `exists`。
    /// 志愿者「服务中」页是 ZStack + 有高度预算的底部面板，求助入口是后加进去的 —— 这一条断言就是
    /// 那次布局改动唯一的把关：安全按钮点不到等于没有。
    private func assertEmergencyActionIsUsable(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = app.buttons["一键求助，遇到紧急情况时点击"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8), "服务进行中必须提供求助入口", file: file, line: line)
        XCTAssertTrue(button.isHittable, "求助按钮存在但点不到 —— 多半是被底部面板挤出了可视区", file: file, line: line)
    }

    /// The SOS button, located by its accessibility label so the assertion also covers VoiceOver.
    ///
    /// 志愿者端仍然是这一个。**盲人端陪跑中已不是** —— 那一屏 2026-09-15 起是求助中心，
    /// 见下面 `blindSafetyHub`。
    private func emergencyAction(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["一键求助，遇到紧急情况时点击"].firstMatch
    }

    /// 盲人端陪跑中贴底的那块求助中心。
    ///
    /// 🚩 它的标签**刻意不含「一键求助」** —— 那四个字在本 App 里专指云端链路（记事件、
    /// 通知同行志愿者与客服），而按开这一层菜单一个字节都没发出去。两者用同一个词，
    /// 看不见屏幕的人会以为求助已经发出。
    private func blindSafetyHub(_ app: XCUIApplication) -> XCUIElement {
        // 逐字对应 `EmergencySafetyCopy.hubAccessibilityLabel`。
        app.buttons["求助与安全，打开求助选项"].firstMatch
    }

    private func dismissKeyboardIfPresent(app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }

        let dismissButton = app.buttons["收起键盘"].firstMatch
        if dismissButton.waitForExistence(timeout: 1) {
            dismissButton.tap()
            if app.keyboards.firstMatch.waitForNonExistence(timeout: 2) {
                return
            }
        }

        for button in [
            app.keyboards.buttons["Return"].firstMatch,
            app.keyboards.buttons["Done"].firstMatch,
            app.keyboards.buttons["完成"].firstMatch
        ] where button.exists && button.isHittable {
            button.tap()
        }
        if app.keyboards.firstMatch.waitForNonExistence(timeout: 1) {
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 1)
    }

    private func dismissSystemAlertsIfPresent(app: XCUIApplication, activateWhenNoAlert: Bool = true) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 0.2) else {
            if activateWhenNoAlert {
                app.activate()
            }
            return
        }

        for title in [
            "允许使用 App 时", "允许使用App时", "使用 App 时允许", "使用App时允许", "允许一次",
            "Allow While Using App", "Allow Once",
            "允许", "Allow", "好", "OK", "继续", "Continue"
        ] {
            let button = alert.buttons[title].firstMatch
            if button.exists {
                if button.isHittable {
                    button.tap()
                } else {
                    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                app.activate()
                return
            }
        }

        app.activate()
    }
}

private extension String {
    func leftPadded(toLength length: Int, withPad character: Character = "0") -> String {
        if count >= length {
            return String(suffix(length))
        }
        return String(repeating: String(character), count: length - count) + self
    }
}
