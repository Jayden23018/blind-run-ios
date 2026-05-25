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
        preseedBlindProfile: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = apiEnvironment
        app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = "blind_runner"
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
        app.launch()
        dismissSystemAlertsIfPresent(app: app)
        return app
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
