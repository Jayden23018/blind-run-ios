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
    func testMockVolunteerOrderFlowSmoke() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true
        )

        openCurrentVolunteerService(app)

        let enRouteButton = app.buttons["我已出发"].firstMatch
        XCTAssertTrue(enRouteButton.waitForExistence(timeout: 5), "Accepted order should show en-route button")
        enRouteButton.tap()

        let arriveButton = app.buttons["我已到达约定地点"].firstMatch
        XCTAssertTrue(arriveButton.waitForExistence(timeout: 8), "En-route order should show arrive button")
        arriveButton.tap()

        let startButton = app.buttons["开始服务"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Arrived order should allow the volunteer to start service")
        let completeButton = app.buttons["结束服务"].firstMatch
        XCTAssertFalse(completeButton.waitForExistence(timeout: 1), "Arrived order must not allow completing service before IN_PROGRESS")
        startButton.tap()
        XCTAssertTrue(completeButton.waitForExistence(timeout: 8), "In-progress order should allow completing service")
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
        XCTAssertTrue(app.buttons["回到当前位置"].firstMatch.waitForExistence(timeout: 5), "Home map should include recenter control")
        XCTAssertTrue(app.staticTexts["系统派单"].firstMatch.waitForExistence(timeout: 5), "Volunteer home should show the system dispatch workbench")
        XCTAssertTrue(app.staticTexts["近期服务"].firstMatch.waitForExistence(timeout: 5), "Dispatch workbench should show recent service history")
        XCTAssertTrue(app.staticTexts["积分"].firstMatch.waitForExistence(timeout: 5), "Dispatch summary should show points")
        XCTAssertFalse(app.buttons["查看全部订单"].firstMatch.exists, "Primary volunteer home must not expose the public order list")

        attachScreenshot(named: "volunteer-home-map-uber-style", app: app)
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
        activeRole: String = "blind_runner",
        preseedBlindProfile: Bool = false,
        preseedVolunteerProfile: Bool = false,
        preseedVolunteerAvailable: Bool = false,
        preseedVolunteerActiveOrder: Bool = false,
        emptyMockOrders: Bool = false,
        disableMap: Bool = true,
        disableWebSocket: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = apiEnvironment
        app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = activeRole
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
        if emptyMockOrders {
            app.launchEnvironment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] = "1"
        }
        app.launch()
        dismissSystemAlertsIfPresent(app: app)
        return app
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

        let submitButton = app.buttons["提交预约"].firstMatch
        XCTAssertTrue(submitButton.waitForExistence(timeout: 15), "Booking form should open and show submit button")
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
