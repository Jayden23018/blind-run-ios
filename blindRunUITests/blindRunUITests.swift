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
    func testMockBlindRunnerHomePlacesPrimaryActionBeforeAuxiliaryMap() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )

        let startButton = app.buttons["开始约跑"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 12), "Blind runner home should show start booking")
        let auxiliaryMap = app.descendants(matching: .any)["blindRunnerHomeAuxiliaryMap"].firstMatch
        XCTAssertTrue(auxiliaryMap.waitForExistence(timeout: 12), "Blind runner home should keep the auxiliary map available")
        XCTAssertLessThan(
            startButton.frame.minY,
            auxiliaryMap.frame.minY,
            "Voice-first home should place primary action before auxiliary map visually"
        )
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
        assertNoEmergencyAction(app)

        completeButton.tap()
        XCTAssertTrue(
            app.buttons["确认完成服务"].firstMatch.waitForExistence(timeout: 5),
            "Completing service should require an explicit confirmation action"
        )
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
    func testMockVolunteerHomeMapScreenshot() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true
        )

        let map = app.descendants(matching: .any)["volunteerHomeMap"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15), "Volunteer home should expose the map as the primary visual")

        let availabilitySwitch = app.switches.firstMatch
        XCTAssertTrue(availabilitySwitch.waitForExistence(timeout: 5), "Availability switch should be visible on the map overlay")
        let topStatusBlock = app.descendants(matching: .any)["volunteerHomeTopStatusBlock"].firstMatch
        XCTAssertTrue(topStatusBlock.waitForExistence(timeout: 5), "Volunteer status block should be visible below the system status area")
        assertVolunteerTopStatusBlockPosition(topStatusBlock, app: app)
        XCTAssertFalse(app.descendants(matching: .any)["volunteerHomeCurrentOrderCard"].firstMatch.exists, "Home without an active order should only show the top status block")
        XCTAssertTrue(app.buttons["回到当前位置"].firstMatch.waitForExistence(timeout: 5), "Home map should include recenter control")
        XCTAssertTrue(app.staticTexts["系统派单"].firstMatch.waitForExistence(timeout: 5), "Volunteer home should show the system dispatch workbench")
        XCTAssertTrue(app.staticTexts["近期服务"].firstMatch.waitForExistence(timeout: 5), "Dispatch workbench should show recent service history")
        XCTAssertTrue(app.staticTexts["积分"].firstMatch.waitForExistence(timeout: 5), "Dispatch summary should show points")
        XCTAssertFalse(app.buttons["查看全部订单"].firstMatch.exists, "Primary volunteer home must not expose the public order list")

        attachScreenshot(named: "volunteer-home-map-uber-style", app: app)
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
        assertNoEmergencyAction(app)
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
        assertLogoutRequiresConfirmation(blindProfile)

        let volunteerProfile = launchApp(
            apiEnvironment: "mock",
            accessToken: "volunteer-profile-token",
            activeRole: "volunteer",
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
        XCTAssertTrue(finalAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "所有登录令牌会失效")).firstMatch.exists)
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

        let blocked = app.staticTexts["当前存在进行中的服务，请处理完成后再删除账户。"].firstMatch
        XCTAssertTrue(blocked.waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts["最终确认删除账户"].exists)
        XCTAssertTrue(app.buttons["退出登录"].exists, "Blocked deletion must preserve the signed-in settings state")
    }

    @MainActor
    func testRealAMapEnabledSmoke() throws {
        guard shouldRunRealAMapSmoke else {
            throw XCTSkip("Run on validation device 111 / iPad Pro (2), or set AIDRUN_UI_TEST_REAL_AMAP=1, to execute real AMap smoke.")
        }

        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            disableMap: false
        )

        let map = app.descendants(matching: .any)["volunteerHomeMap"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 20), "Real AMap run should expose the volunteer home map container")
        XCTAssertFalse(app.staticTexts["地图服务暂不可用"].exists, "Real AMap smoke must not fall back to the missing-key placeholder")
        XCTAssertFalse(app.staticTexts["请配置高德地图 API Key"].exists, "Real AMap smoke requires a configured local AMap key")

        attachScreenshot(named: "real-amap-volunteer-home", app: app)
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
        mockLogoutFailure: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
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
        app.launch()
        dismissSystemAlertsIfPresent(app: app)
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 12))
        settingsButton.tap()
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

    private func openCurrentVolunteerService(_ app: XCUIApplication) {
        let currentOrderLabel = app.staticTexts["当前订单"].firstMatch
        XCTAssertTrue(currentOrderLabel.waitForExistence(timeout: 15), "Volunteer home should show the assigned current order")

        let firstOrder = app.staticTexts["李明"].firstMatch
        XCTAssertTrue(firstOrder.waitForExistence(timeout: 5), "Current order card should show the assigned blind runner")
        tapWhenHittableOrByCoordinate(firstOrder, app: app)

        let phoneText = app.staticTexts["13800001001"].firstMatch
        XCTAssertTrue(phoneText.waitForExistence(timeout: 8), "Phone should be shown for an accepted current service")
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

    private func createBookingAndAssertMatching(_ app: XCUIApplication) {
        let startButton = app.buttons["开始约跑"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 12), "Blind runner home should show start booking")
        startButton.tap()

        let appointmentStepButton = app.buttons["下一步：预约时间"].firstMatch
        XCTAssertTrue(appointmentStepButton.waitForExistence(timeout: 15), "Guided booking should start at the start-point step")
        XCTAssertTrue(waitForElementToBeEnabled(appointmentStepButton, timeout: 10), "Start-point step should be valid with demo location")
        appointmentStepButton.tap()

        let needsStepButton = app.buttons["下一步：跑步需求"].firstMatch
        XCTAssertTrue(needsStepButton.waitForExistence(timeout: 10), "Guided booking should proceed to appointment time")
        XCTAssertTrue(waitForElementToBeEnabled(needsStepButton, timeout: 10), "Default appointment time should satisfy the 30-minute gate")
        needsStepButton.tap()

        let reviewStepButton = app.buttons["下一步：确认预约"].firstMatch
        XCTAssertTrue(reviewStepButton.waitForExistence(timeout: 10), "Guided booking should proceed to optional needs")
        XCTAssertTrue(waitForElementToBeEnabled(reviewStepButton, timeout: 5), "Optional needs step should be skippable")
        reviewStepButton.tap()

        let submitButton = app.buttons["提交预约"].firstMatch
        XCTAssertTrue(submitButton.waitForExistence(timeout: 10), "Review step should show submit button")
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
            if role.exists || profile.exists || editProfile.exists || home.exists {
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
        let statusBar = app.statusBars.firstMatch
        XCTAssertTrue(statusBar.exists, "System status bar should be available for safe-area verification", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            topStatusBlock.frame.minY,
            statusBar.frame.maxY - 1,
            "Volunteer status block should remain below the system status area",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            topStatusBlock.frame.minY,
            100,
            "Volunteer status block should remain at the top instead of double-counting the safe area",
            file: file,
            line: line
        )
    }

    private func assertNoEmergencyAction(_ app: XCUIApplication) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertFalse(app.buttons["一键求助，遇到紧急情况时点击"].firstMatch.exists, "Current release should hide the emergency action")
        XCTAssertFalse(app.buttons["一键求助"].firstMatch.exists, "Current release should hide the emergency action")
        XCTAssertFalse(
            app.staticTexts["当前版本未开放紧急求助入口，请按既定人工安全预案处理。"].firstMatch.exists,
            "Current release should hide deferred emergency copy"
        )
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
