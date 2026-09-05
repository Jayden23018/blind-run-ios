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

    @MainActor
    func testMockBlindRunnerHomeKeepsAuxiliaryMapOutOfVoiceOverSoPrimaryActionComesFirst() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )

        let startButton = app.buttons["开始约跑"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 12), "Blind runner home should show start booking")
        // 删掉了一条断 `homeMapPlaceholder` 不存在的断言：那个 identifier App 侧从来没有过
        // （占位图真实的 id 是 `mapPlaceholder`），所以它恒真、等于没写。
        // 也不能直接改成 `mapPlaceholder`：UI 测试默认 `disableMap: true`，占位图是被强制渲染的。

        // 2026-08-07 这条用例断言的是「主操作排在地图之前」，从那天起就一直红着（27 vs 16），
        // 而且**改不动**：`allElementsBoundByAccessibilityElement` 是逐层枚举的（同深度的兄弟
        // 全排完才轮到它们的子元素），地图是 ZStack 的直接子层、按钮在滚动视图里面，两个下标
        // 差的是深度不是顺序，怎么排都填不平。
        //
        // 2026-08-14 在真机上实测了四种排法（裸 `accessibilitySortPriority`、换声明顺序 +
        // `zIndex`、三层都加 `children: .contain` 再排、地图改成内容层的 `.background`），
        // 地图一律排在内容前面 —— SwiftUI 把遍历顺序绑死在绘制顺序上，而地图必须画在最底层。
        // 详见 `docs/research/swiftui-voiceover-traversal-order-20260814.md`。
        //
        // 结论：地图改为对读屏**完全隐藏**（纯装饰、不可交互、信息在 `locationSummarySection`
        // 有文字版），读屏用户 0 次多余划动就够到主操作。所以这里断言的是「不在树里」。
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "blindRunnerHomeAuxiliaryMap").count, // guard:allow stale-ui-test-identifier
            0,
            "装饰性地图不得出现在无障碍元素树里"
        )

        // 仍然钉住一条真实的遍历顺序：内容层排在设置齿轮之前（齿轮曾经是进首页遍历到的第 2 个
        // 元素）。这两个是 ZStack 的直接子层，**同一深度**，下标可比。
        let elements = app.descendants(matching: .any).allElementsBoundByAccessibilityElement
        let contentIndex = elements.firstIndex { $0.identifier == "blindRunnerHomeScrollView" }
        let settingsIndex = elements.firstIndex { $0.label == "设置" }
        XCTAssertNotNil(contentIndex, "内容层必须在无障碍元素树里")
        XCTAssertNotNil(settingsIndex, "设置入口必须在无障碍元素树里")
        XCTAssertTrue(
            app.scrollViews["blindRunnerHomeScrollView"].buttons["开始约跑"].firstMatch.exists,
            "主操作必须在内容层内部，否则上面的下标比较证明不了主操作的位置"
        )
        if let contentIndex, let settingsIndex {
            XCTAssertLessThan(
                contentIndex,
                settingsIndex,
                "Voice-first home must place the primary action before auxiliary controls in VoiceOver traversal"
            )
        }
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
        XCTAssertTrue(app.buttons["开始约跑"].firstMatch.isHittable, "Committed home must remain interactive")
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

        // 「重复当前状态」排在 280pt 的「开始约跑」下面，无订单态里整段落在首屏之外
        // （`BlindRunnerHomeView.askQuestionButton` 的注释记着同一件事）。**必须先滚过去再点。**
        // 不滚也照样 `isHittable == true`，但触点落在屏幕底部常驻的「紧急呼叫」条上：
        // 2026-08-14 因此弹出本地拨号确认单，紧接着的 swipe 又在确认单上拖拽选中「拨打110」，
        // iOS 弹出 `com.apple.BusinessActionSheet` 选号单，对它的快照查询超时 ——
        // 报出来是 "Failed to get matching snapshots"，看着完全不像误触。
        let repeatButton = app.buttons["重复当前状态"].firstMatch
        // 断言滚动**真的成功了**：滚不动时 helper 会静默放弃，随后的 tap 打在求助条上，
        // 报出来的错（拨号确认单 / 系统选号单超时）和真因隔了三层，2026-08-14 因此查了半天。
        XCTAssertTrue(
            scrollElementIntoView(repeatButton, app: app),
            "没能把「重复当前状态」滚出底部常驻求助条的遮挡，接下来的 tap 必然误触"
        )
        XCTAssertTrue(repeatButton.isHittable, "Local TTS action must not wait for the backend")
        repeatButton.tap()
        // 误触求助条的回归钉子。真机上这条路径会真的拨出去，当时只有双卡选号单挡了一下。
        XCTAssertFalse(
            app.buttons["拨打110"].firstMatch.exists,
            "本地操作的触点落到了常驻求助条上，弹出了本地拨号确认单"
        )

        let settingsButton = app.buttons["设置"].firstMatch
        XCTAssertTrue(settingsButton.isHittable, "Settings must remain independent from home loading")
        settingsButton.tap()
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

        let topStatusBlock = app.descendants(matching: .any)["volunteerHomeTopStatusBlock"].firstMatch
        XCTAssertTrue(topStatusBlock.waitForExistence(timeout: 12), "Volunteer status block should be visible below the system status area")
        assertVolunteerTopStatusBlockPosition(topStatusBlock, app: app)
        let homeMaps = app.descendants(matching: .any).matching(identifier: "volunteerHomeMap")
        XCTAssertTrue(homeMaps.firstMatch.waitForExistence(timeout: 5), "Volunteer home should mount its map container")
        XCTAssertEqual(homeMaps.count, 1, "Committed volunteer home should mount exactly one home map")
        // 同上：`volunteerHomeMapPlaceholderBackground` 这个 identifier App 侧从来没有过，
        // 断言恒真。真 key 路径的对应断言在 `testRealAMapEnabledSmoke`。

        let currentOrderCard = app.descendants(matching: .any)["volunteerHomeCurrentOrderCard"].firstMatch
        XCTAssertTrue(currentOrderCard.waitForExistence(timeout: 5), "Preseeded active order should appear below the status block")
        XCTAssertGreaterThanOrEqual(currentOrderCard.frame.minY, topStatusBlock.frame.maxY, "Current order should remain directly below the top status block")

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
        let completeButton = app.buttons["结束服务"].firstMatch
        XCTAssertFalse(completeButton.waitForExistence(timeout: 1), "Arrived order must not allow completing service before IN_PROGRESS")
        startButton.tap()
        XCTAssertTrue(completeButton.waitForExistence(timeout: 8), "In-progress order should allow completing service")
        // 2026-08-01 起志愿者可以代盲人发起求助（后端已按订单参与方归属事件，不再回推给按按钮的人）。
        // 这里原本断言「志愿者永远看不到求助入口」，那是后端送错人时期的止血，现在反过来验它必须可用。
        assertEmergencyActionIsUsable(app)

        completeButton.tap()
        let confirmComplete = app.buttons["确认完成服务"].firstMatch
        XCTAssertTrue(
            confirmComplete.waitForExistence(timeout: 5),
            "Completing service should require an explicit confirmation action"
        )
        confirmComplete.tap()

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
        let availabilitySwitch = app.switches.firstMatch
        XCTAssertTrue(availabilitySwitch.waitForExistence(timeout: 8))
        XCTAssertEqual(availabilitySwitch.value as? String, "0", "Legacy completion must not automatically enable availability")
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
        let completeButton = app.buttons["结束服务"].firstMatch
        XCTAssertFalse(completeButton.waitForExistence(timeout: 1), "Arrived order should hide complete button")
        attachScreenshot(named: "volunteer-service-arrived", app: app)
        startButton.tap()
        XCTAssertTrue(completeButton.waitForExistence(timeout: 8), "Started service should show complete action")
        attachScreenshot(named: "volunteer-service-in-progress", app: app)
    }

    @MainActor
    func testMockVolunteerHomeMapAndControlsScreenshot() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true
        )

        let homeMaps = app.descendants(matching: .any).matching(identifier: "volunteerHomeMap")
        let homeMap = homeMaps.firstMatch
        XCTAssertTrue(
            homeMap.waitForExistence(timeout: 15),
            "Volunteer home should expose its map container"
        )
        XCTAssertEqual(homeMaps.count, 1, "Volunteer home must not duplicate its map during refresh")
        // 此前这里断的是 `volunteerHomeMapPlaceholderBackground` 不存在 —— 那个 identifier
        // **App 侧从来没有过**，断言恒真。同上：本用例 `disableMap` 默认 `true`，占位图是预期产物，
        // 换成真实的 `mapPlaceholder` 会必红；真 key 路径的断言在 `testRealAMapEnabledSmoke`。

        let availabilitySwitch = app.switches.firstMatch
        XCTAssertTrue(availabilitySwitch.waitForExistence(timeout: 5), "Availability switch should remain visible above the map")
        let topStatusBlock = app.descendants(matching: .any)["volunteerHomeTopStatusBlock"].firstMatch
        XCTAssertTrue(topStatusBlock.waitForExistence(timeout: 5), "Volunteer status block should be visible below the system status area")
        assertVolunteerTopStatusBlockPosition(topStatusBlock, app: app)
        XCTAssertFalse(app.descendants(matching: .any)["volunteerHomeCurrentOrderCard"].firstMatch.exists, "Home without an active order should only show the top status block")
        XCTAssertTrue(app.buttons["回到当前位置"].firstMatch.waitForExistence(timeout: 5), "Home should keep the local recenter control")
        XCTAssertTrue(app.staticTexts["系统派单"].firstMatch.waitForExistence(timeout: 5), "Volunteer home should show the system dispatch workbench")
        XCTAssertTrue(app.staticTexts["近期服务"].firstMatch.waitForExistence(timeout: 5), "Dispatch workbench should show recent service history")
        // 三格：完成 / 评分 / 接单率。此前这里断的是「积分」，而 `be4e030` 已经把那一格删了
        // —— 它的值是 `totalCompleted * 100`，后端从来没有积分字段（见 VolunteerHomeView 的注释）。
        XCTAssertTrue(app.staticTexts["接单率"].firstMatch.waitForExistence(timeout: 5), "Dispatch summary should show the acceptance rate")
        XCTAssertFalse(app.buttons["查看全部订单"].firstMatch.exists, "Primary volunteer home must not expose the public order list")

        attachScreenshot(named: "volunteer-home-map-and-controls", app: app)
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
        let panel = app.descendants(matching: .any)["volunteerHomeDemandPanel"].firstMatch
        let grabber = app.descendants(matching: .any)["volunteerHomeDemandPanelGrabber"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "Dispatch panel should load at AX5")
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))

        // 这一条就是「顶部状态块盖住抓手」的回归守卫：修之前顶部状态块从 y=149 长到 y=490，
        // 把 y=365–392 的抓手整个盖住，拖拽触点全被吃掉，面板高度拖完仍是 299.999…。
        // 用显式长按拖拽而不是 `grabber.swipeUp()`：后者在这种遮挡下同样无效，
        // 但失败时看不出是「拖不动」还是「手势没识别」。
        let panelHeightBefore = panel.frame.height
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)))
        XCTAssertGreaterThan(panel.frame.height, panelHeightBefore, "Dispatch panel must be expandable at AX5")

        // 三格在 `LazyVGrid` 里，屏幕外**不实例化**（无障碍树里是 `Other {{0,0},{0,0}}`），
        // 所以必须先滚到它再断言存在 —— `waitForExistence` 等不到，
        // `scrollElementIntoView` 第一行的 `guard element.exists` 也过不去。
        // 慢速滚：AX5 下滚动视口很浅而默认速度一次跨度远大于它，采样点会整段跳过格子区。
        let scrollView = app.scrollViews["volunteerHomeDemandScrollView"].firstMatch
        let rate = app.staticTexts["接单率"].firstMatch
        var drags = 0
        while !rate.exists && drags < 10 {
            scrollView.swipeUp(velocity: .slow)
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

        let panel = app.descendants(matching: .any)["volunteerHomeDemandPanel"].firstMatch
        let grabber = app.descendants(matching: .any)["volunteerHomeDemandPanelGrabber"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 12))
        XCTAssertTrue(grabber.waitForExistence(timeout: 3))
        let initialPanelTop = panel.frame.minY
        grabber.swipeUp()
        XCTAssertLessThan(panel.frame.minY, initialPanelTop, "Dispatch panel must remain draggable while loading")

        let refreshButton = app.buttons["刷新派单状态"].firstMatch
        XCTAssertTrue(refreshButton.isHittable)
        refreshButton.tap()

        let recordsButton = app.buttons["我的服务记录"].firstMatch
        // 「积分商城」是被撤掉的那个假占位页（积分写死 `--`、商品全是「敬请期待」），
        // 已由 `VolunteerServiceRecognitionView` 取代。用例没跟着改，于是这一条从那次
        // 改动起就一直红 —— 而红着的用例会把后来引入的失败一起吃掉（`continueAfterFailure`），
        // 志愿者首页因此有一段时间没有任何有效的 UI 覆盖。
        //
        // XCUITest 是黑盒，进不了 app 的类型 —— `VolunteerAchievementsCopy.navigationTitle`
        // 只能抄一份。抄错的方向是安全的：生产改了文案而这里没跟，断言会红不会绿。
        let recognitionTitle = "服务成就"
        let recognitionButton = app.buttons[recognitionTitle].firstMatch
        let settingsButton = app.buttons["设置"].firstMatch
        XCTAssertTrue(recordsButton.isHittable)
        XCTAssertTrue(recognitionButton.isHittable)
        XCTAssertTrue(settingsButton.isHittable)

        recordsButton.tap()
        XCTAssertTrue(app.navigationBars["服务记录"].waitForExistence(timeout: 5))
        popNavigationBar(app, title: "服务记录")

        XCTAssertTrue(waitForElementToBeHittable(recognitionButton, timeout: 5))
        recognitionButton.tap()
        XCTAssertTrue(app.navigationBars[recognitionTitle].waitForExistence(timeout: 5))
        popNavigationBar(app, title: recognitionTitle)

        XCTAssertTrue(waitForElementToBeHittable(settingsButton, timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMockBlindOrderHidesEmergencyActionInAcceptedStates() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true
        )

        let currentOrderButton = app.buttons["查看当前订单"].firstMatch
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

        let sos = emergencyAction(app)
        XCTAssertTrue(sos.waitForExistence(timeout: 8), "IN_PROGRESS should expose the blind SOS action")
        XCTAssertGreaterThanOrEqual(sos.frame.height, 64, "Blind primary actions must be at least 64pt high")

        // Exact second-confirmation copy, and cancel must send nothing.
        sos.tap()
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

        let currentOrderButton = app.buttons["查看当前订单"].firstMatch
        XCTAssertTrue(currentOrderButton.waitForExistence(timeout: 12))
        currentOrderButton.tap()

        for label in ["模拟志愿者接单", "模拟志愿者到达", "模拟服务开始"] {
            let button = app.buttons[label].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 8), "Mock control \(label) should exist")
            button.tap()
        }

        XCTAssertTrue(emergencyAction(app).waitForExistence(timeout: 8))
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

        let settingsButton = app.buttons["设置"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Blind runner home should expose settings")
        settingsButton.tap()

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
        let deleteOnlyContact = app.buttons["删除张三"].firstMatch
        XCTAssertTrue(deleteOnlyContact.waitForExistence(timeout: 8))
        scrollElementIntoView(deleteOnlyContact, app: app)
        tapWhenHittableOrByCoordinate(deleteOnlyContact, app: app)
        XCTAssertTrue(
            app.staticTexts["至少需要保留 1 位紧急联系人，不能删除最后一位。"].firstMatch.waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.alerts["确认删除联系人"].exists, "被拦下的删除不应弹出确认框")

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

    /// 诊断用，跑完就删：量一下失败反馈那一行到底落在哪。
    @MainActor
    func testDIAGContactFailureLineFallsOffScreen() throws {
        let app = launchBlindContactsApp()
        openContacts(app)
        waitForContactSummary(app, Self.seededContactSummary)

        for index in 2...5 {
            addContact(app, name: "联系人\(index)", phone: "1370013700\(index)", relationship: "朋友")
            waitForContactSummary(app, "共 \(index) 位紧急联系人，最多 5 位。主联系人是张三。")
        }

        for _ in 0..<6 { scrollableSurface(app).swipeDown() }

        let deletePrimary = app.buttons["删除张三"].firstMatch
        XCTAssertTrue(deletePrimary.waitForExistence(timeout: 8))
        scrollElementIntoView(deletePrimary, app: app)
        tapWhenHittableOrByCoordinate(deletePrimary, app: app)

        let blocked = app.staticTexts["这是当前主联系人。请先把另一位设为主联系人，再删除这一位。"].firstMatch
        _ = blocked.waitForExistence(timeout: 5)

        let appFrame = app.frame
        func describe(_ element: XCUIElement) -> String {
            guard element.exists else { return "absent" }
            let f = element.frame
            return "minY=\(f.minY) maxY=\(f.maxY) h=\(f.height)"
        }

        var diag = "DIAGFRAME window=\(appFrame.height) "
        diag += "afterTap_error=[\(describe(blocked))] "
        diag += "afterTap_add=[\(describe(app.buttons["新增紧急联系人"].firstMatch))] "

        var swipes = 0
        while !blocked.exists || blocked.frame.maxY > appFrame.maxY, swipes < 8 {
            scrollableSurface(app).swipeUp()
            swipes += 1
        }
        diag += "afterScroll_error=[\(describe(blocked))] swipes=\(swipes)"

        print(diag)
        XCTFail(diag)
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

        XCTAssertTrue(
            volunteerApp.descendants(matching: .any)["volunteerHomeMap"].firstMatch.waitForExistence(timeout: 20),
            "Real AMap run should expose the volunteer home map container"
        )
        XCTAssertFalse(
            volunteerApp.descendants(matching: .any)["mapPlaceholder"].firstMatch.exists,
            "配了真 key 的构建不该回落到缺 key 占位图"
        )
        XCTAssertFalse(volunteerApp.staticTexts["地图服务暂不可用"].exists, "Volunteer home must not fall back to the missing-key view")
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

    private func openSettings(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 12))
        settingsButton.tap()
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
        let bottom = appFrame.maxY - Self.persistentBottomBarInset
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
        let startButton = app.buttons["开始约跑"].firstMatch
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
        let home = app.buttons["开始约跑"].firstMatch
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
    private func emergencyAction(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["一键求助，遇到紧急情况时点击"].firstMatch
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
