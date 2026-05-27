//
//  blindRunUITests.swift
//  blindRunUITests
//
//  Created by Jerry on 5/18/26.
//

import XCTest

final class blindRunUITests: XCTestCase {
    private let localBackendURL = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_LOCAL_BACKEND_URL"]
        ?? "http://192.168.1.17:8080"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testMockBlindRunnerBookingSmoke() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            preseedBlindProfile: true
        )

        createBookingAndAssertMatching(app)
    }

    @MainActor
    func testMockVolunteerOrderFlowSmoke() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true
        )

        let firstOrder = app.staticTexts["李明"].firstMatch
        XCTAssertTrue(firstOrder.waitForExistence(timeout: 15), "Volunteer home should show available mock orders")
        firstOrder.tap()

        XCTAssertFalse(app.staticTexts["13800001001"].exists, "Phone must be hidden before accepting")
        let disabledAcceptButton = app.buttons["接单"].firstMatch
        XCTAssertTrue(disabledAcceptButton.waitForExistence(timeout: 5), "Accept button should exist")
        XCTAssertFalse(disabledAcceptButton.isEnabled, "Accept should be disabled when isAvailable=false")

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let availabilitySwitch = app.switches.firstMatch
        XCTAssertTrue(availabilitySwitch.waitForExistence(timeout: 5), "Availability switch should exist")
        availabilitySwitch.tap()

        XCTAssertTrue(firstOrder.waitForExistence(timeout: 5), "Order should still be visible after availability toggle")
        firstOrder.tap()

        let acceptButton = app.buttons["接单"].firstMatch
        XCTAssertTrue(waitForElementToBeEnabled(acceptButton, timeout: 8), "Accept should become enabled after availability is on")
        acceptButton.tap()
        app.buttons["确认接单"].tap()

        let phoneText = app.staticTexts["13800001001"].firstMatch
        XCTAssertTrue(phoneText.waitForExistence(timeout: 8), "Phone should be shown after accepting")

        let serviceButton = app.buttons["进入服务页面"].firstMatch
        XCTAssertTrue(serviceButton.waitForExistence(timeout: 5), "Accepted order should allow entering service page")
        serviceButton.tap()

        let arriveButton = app.buttons["我已到达约定地点"].firstMatch
        XCTAssertTrue(arriveButton.waitForExistence(timeout: 5), "Accepted order should show arrive button")
        arriveButton.tap()

        let waitingText = app.staticTexts["已到达，等待盲人确认开始服务"].firstMatch
        XCTAssertTrue(waitingText.waitForExistence(timeout: 8), "Arrived state should wait for blind runner confirmation")

        let mockConfirmStartButton = app.buttons["模拟盲人确认开始"].firstMatch
        XCTAssertTrue(mockConfirmStartButton.waitForExistence(timeout: 5), "Mock mode should allow confirming service start")
        mockConfirmStartButton.tap()

        let completeButton = app.buttons["结束服务"].firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 8), "In-progress order should show complete button")
        completeButton.tap()

        let sheetCompleteButton = app.buttons["确认结束服务"].firstMatch
        XCTAssertTrue(sheetCompleteButton.waitForExistence(timeout: 5), "Completion sheet should require a second action")
        sheetCompleteButton.tap()

        let confirmCompleteButton = app.buttons["确认结束"].firstMatch
        XCTAssertTrue(confirmCompleteButton.waitForExistence(timeout: 5), "Complete service should show confirmation")
        confirmCompleteButton.tap()

        let completedStatus = app.staticTexts["已完成"].firstMatch
        XCTAssertTrue(completedStatus.waitForExistence(timeout: 8), "Order should reach completed status")
    }

    @MainActor
    func testMockVolunteerServiceInProgressScreenshots() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true
        )

        openAcceptedVolunteerService(app)
        attachScreenshot(named: "volunteer-service-accepted", app: app)

        let arriveButton = app.buttons["我已到达约定地点"].firstMatch
        XCTAssertTrue(arriveButton.waitForExistence(timeout: 5), "Accepted service page should show arrive action")
        arriveButton.tap()

        let waitingText = app.staticTexts["已到达，等待盲人确认开始服务"].firstMatch
        XCTAssertTrue(waitingText.waitForExistence(timeout: 8), "Arrived state should wait for blind runner confirmation")
        attachScreenshot(named: "volunteer-service-arrived", app: app)

        let mockConfirmStartButton = app.buttons["模拟盲人确认开始"].firstMatch
        XCTAssertTrue(mockConfirmStartButton.waitForExistence(timeout: 5), "Mock mode should allow confirming service start")
        mockConfirmStartButton.tap()

        let completeButton = app.buttons["结束服务"].firstMatch
        XCTAssertTrue(completeButton.waitForExistence(timeout: 8), "In-progress order should show complete button")
        attachScreenshot(named: "volunteer-service-in-progress", app: app)

        completeButton.tap()
        let sheetCompleteButton = app.buttons["结束服务"].firstMatch
        XCTAssertTrue(sheetCompleteButton.waitForExistence(timeout: 5), "Completion sheet should appear")
        attachScreenshot(named: "volunteer-service-complete-summary", app: app)
    }

    @MainActor
    func testMockVolunteerHomeMapScreenshot() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true
        )

        let map = app.descendants(matching: .any)["volunteerHomeMap"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15), "Volunteer home should expose the map as the primary visual")

        let availabilitySwitch = app.switches.firstMatch
        XCTAssertTrue(availabilitySwitch.waitForExistence(timeout: 5), "Availability switch should be visible on the map overlay")
        XCTAssertTrue(app.buttons["回到当前位置"].firstMatch.waitForExistence(timeout: 5), "Home map should include recenter control")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "附近需求")).firstMatch.waitForExistence(timeout: 5), "Demand panel should show nearby demand count")
        XCTAssertTrue(app.buttons["查看全部订单"].firstMatch.waitForExistence(timeout: 5), "Demand panel should expose all-orders entry")
        XCTAssertTrue(app.staticTexts["李明"].firstMatch.waitForExistence(timeout: 5), "Nearby demand list should show mock available orders")

        attachScreenshot(named: "volunteer-home-map-uber-style", app: app)
    }

    @MainActor
    func testLocalBackendBlindRunnerBookingSmoke() throws {
        let uniquePhone = "139" + String(Int(Date().timeIntervalSince1970) % 100_000_000).leftPadded(toLength: 8)
        let app = launchApp(
            apiEnvironment: "localBackend",
            localBackendURL: localBackendURL
        )

        login(app: app, phone: uniquePhone)
        chooseBlindRunnerRoleIfNeeded(app)
        completeBlindRunnerProfileIfNeeded(app)
        createBookingAndAssertMatching(app)
    }

    private func launchApp(
        apiEnvironment: String,
        localBackendURL: String? = nil,
        accessToken: String? = nil,
        activeRole: String = "blind_runner",
        preseedBlindProfile: Bool = false,
        preseedVolunteerProfile: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = apiEnvironment
        app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = activeRole
        app.launchEnvironment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] = "1"
        if let localBackendURL {
            app.launchEnvironment["AIDRUN_UI_TEST_LOCAL_BACKEND_URL"] = localBackendURL
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
        app.launch()
        dismissSystemAlertsIfPresent(app: app)
        return app
    }

    private func openAcceptedVolunteerService(_ app: XCUIApplication) {
        let firstOrder = app.staticTexts["李明"].firstMatch
        XCTAssertTrue(firstOrder.waitForExistence(timeout: 15), "Volunteer home should show available mock orders")

        let availabilitySwitch = app.switches.firstMatch
        XCTAssertTrue(availabilitySwitch.waitForExistence(timeout: 5), "Availability switch should exist")
        availabilitySwitch.tap()

        XCTAssertTrue(firstOrder.waitForExistence(timeout: 5), "Order should still be visible after availability toggle")
        firstOrder.tap()

        let acceptButton = app.buttons["接单"].firstMatch
        XCTAssertTrue(waitForElementToBeEnabled(acceptButton, timeout: 8), "Accept should become enabled after availability is on")
        acceptButton.tap()
        app.buttons["确认接单"].tap()

        let serviceButton = app.buttons["进入服务页面"].firstMatch
        XCTAssertTrue(serviceButton.waitForExistence(timeout: 8), "Accepted order should allow entering service page")
        serviceButton.tap()
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func login(app: XCUIApplication, phone: String) {
        let phoneField = app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch
        XCTAssertTrue(phoneField.waitForExistence(timeout: 10), "Login phone field should appear")
        phoneField.tap()
        phoneField.typeText(phone)

        app.buttons["获取验证码"].tap()
        dismissSystemAlertsIfPresent(app: app)

        let codeField = app.textFields["验证码输入框，请输入 6 位验证码"].firstMatch
        XCTAssertTrue(codeField.waitForExistence(timeout: 5), "Verification code field should appear")
        codeField.tap()
        codeField.typeText("123456")

        app.buttons["登录"].tap()
        dismissSystemAlertsIfPresent(app: app)
        waitForPostLoginRoute(app)
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
        guard title.waitForExistence(timeout: 8) else { return }

        enterTextIfNeeded(app: app, fieldLabel: "昵称，必填", placeholder: "请输入昵称", text: "UITestBlind")
        enterTextIfNeeded(app: app, fieldLabel: "紧急联系人姓名，必填", placeholder: "请输入紧急联系人姓名", text: "UITestContact")
        enterTextIfNeeded(app: app, fieldLabel: "紧急联系人电话，必填，11位手机号", placeholder: "请输入11位手机号", text: "13800001111")

        let saveButton = app.buttons["完成，保存资料"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Profile save button should appear")
        saveButton.tap()
        dismissSystemAlertsIfPresent(app: app)
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

        let matchingStatus = app.staticTexts["匹配中"].firstMatch
        XCTAssertTrue(matchingStatus.waitForExistence(timeout: 15), "Created booking should enter matching status")
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
        let home = app.buttons["开始约跑"].firstMatch
        let error = app.staticTexts["网络错误，请重试。真机请填写电脑局域网 IP，不能使用 127.0.0.1。"].firstMatch

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            dismissSystemAlertsIfPresent(app: app)
            if error.exists {
                XCTFail("Local backend login failed with network error")
                return
            }
            if role.exists || profile.exists || home.exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
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

    private func dismissSystemAlertsIfPresent(app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 0.2) else {
            app.activate()
            return
        }

        for title in ["允许", "Allow", "好", "OK", "继续", "Continue"] {
            let button = alert.buttons[title].firstMatch
            if button.exists {
                button.tap()
                app.activate()
                return
            }
        }

        if alert.buttons.count > 0 {
            alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
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
