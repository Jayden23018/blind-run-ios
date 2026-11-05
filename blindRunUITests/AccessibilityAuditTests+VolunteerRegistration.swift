import XCTest

/// 陪跑员注册第 1 步拆屏（#699）：说明页、第 1 步身份、第 2 步经历、第 3 步刷脸。
///
/// 这几屏此前**没有任何审计用例**（拆屏前那一整屏长表单也没有）。亮 / 暗各一遍，每屏截图，
/// 截图拿去和定稿 `docs/ui/mockups/volunteer-identity-20261104/identity-final.png` 逐项对比。
/// 陪跑员端只测默认字号（负责人 2026-11-05 定）：最大字号（AX5）只在盲人端测。
extension AccessibilityAuditTests {

    @MainActor
    func testVolunteerRegistrationStepsPassAuditInLightAndDark() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in Self.appearanceVariants where ["light", "dark"].contains(variant.name) {
            let app = launchUnregisteredVolunteerRegistration(
                extraEnvironment: variant.environment, extraArguments: variant.arguments
            )
            try auditRegistrationIntroAndIdentity(app, variant: variant.name)
            try auditRegistrationExperienceAndFace(app, variant: variant.name)
            app.terminate()
        }
    }

    /// 说明页选「不想刷脸？改为上传身份材料」：身份照样要填，提交通过后直接落到现有的替代路径页，
    /// 不再被引去刷脸。
    @MainActor
    func testRegistrationIntroAlternativeChoiceLandsOnTheUploadEntryAfterIdentity() throws {
        let app = launchUnregisteredVolunteerRegistration()

        let alternative = app.buttons["volunteerRegistrationIntroAlternativeButton"].firstMatch
        XCTAssertTrue(alternative.waitForExistence(timeout: 25), "说明页没出来")
        alternative.tap()

        // 改走人工审核也要先填姓名和身份证号：拒绝人脸的接口要求二要素先通过。
        VolunteerRegistrationUITestSteps.fillIdentity(app)
        app.buttons["volunteerRegistrationIdentityNextButton"].firstMatch.tap()

        let skip = app.buttons["volunteerRegistrationSkipButton"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        // 跳过也要先勾单独同意（#769：勾选框在提交按钮上方，默认不勾）。
        let consent = app.buttons["volunteerIdentityConsentCheckbox"].firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 8), "跳过也要先勾单独同意")
        consent.tap()
        skip.tap()

        let declined = app.descendants(matching: .any)["volunteerFaceVerifyDeclined"].firstMatch
        XCTAssertTrue(declined.waitForExistence(timeout: 12), "身份通过后应直接落到「已选择替代认证方式」")
        XCTAssertTrue(app.descendants(matching: .any)["volunteerDeclinedUploadEntry"].firstMatch.exists)
        XCTAssertFalse(app.buttons["volunteerFaceVerifyStartButton"].exists, "不该再被引去刷脸")
        attachScreenshot(app, name: "identity-alternative-landing")
    }

    // MARK: - Helpers

    @available(iOS 17.0, *)
    @MainActor
    private func auditRegistrationIntroAndIdentity(_ app: XCUIApplication, variant: String) throws {
        let start = app.buttons["volunteerRegistrationIntroStartButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 25), "\(variant)：说明页没出来")
        waitUntilSettled(start)
        attachScreenshot(app, name: "identity-intro-\(variant)")
        try audit(app)
        start.tap()

        let nameField = app.textFields["volunteerRegistrationField.姓名"].firstMatch
        let next = app.buttons["volunteerRegistrationIdentityNextButton"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 8), "\(variant)：第 1 步没出来")
        waitUntilSettled(nameField)
        XCTAssertFalse(next.isEnabled, "\(variant)：没填时「下一步」不可点")
        XCTAssertEqual(
            app.staticTexts["volunteerRegistrationMissingFields"].label, "还差：姓名、身份证号",
            "\(variant)：按钮下要写清还差哪几项"
        )
        attachScreenshot(app, name: "identity-step1-empty-\(variant)")
        try audit(app)

        VolunteerRegistrationUITestSteps.fillIdentity(app)
        XCTAssertTrue(next.isEnabled, "\(variant)：三项填好后「下一步」要能点")
        attachScreenshot(app, name: "identity-step1-filled-\(variant)")
        next.tap()
    }

    @available(iOS 17.0, *)
    @MainActor
    private func auditRegistrationExperienceAndFace(_ app: XCUIApplication, variant: String) throws {
        let submit = app.buttons["volunteerRegistrationSubmitButton"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 8), "\(variant)：第 2 步没出来")
        waitUntilSettled(submit)
        XCTAssertTrue(app.buttons["volunteerRegistrationBackButton"].exists)
        XCTAssertTrue(app.buttons["volunteerRegistrationSkipButton"].exists)
        attachScreenshot(app, name: "identity-step2-\(variant)")
        try audit(app)
        let consent = app.buttons["volunteerIdentityConsentCheckbox"].firstMatch
        XCTAssertTrue(consent.exists, "\(variant)：提交前要先勾单独同意")
        consent.tap()
        submit.tap()

        let faceStart = app.buttons["volunteerFaceVerifyStartButton"].firstMatch
        XCTAssertTrue(faceStart.waitForExistence(timeout: 12), "\(variant)：第 3 步没出来")
        waitUntilSettled(faceStart)
        attachScreenshot(app, name: "identity-step3-\(variant)")
        try audit(app)
        app.swipeUp()
        attachScreenshot(app, name: "identity-step3-bottom-\(variant)")
    }

    @MainActor
    private func launchUnregisteredVolunteerRegistration(
        extraEnvironment: [String: String] = [:],
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = "mock"
        app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = "volunteer"
        app.launchEnvironment["AIDRUN_UI_TEST_ACCESS_TOKEN"] = "mock_jwt_token_for_testing"
        app.launchEnvironment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_REAL_REGISTRATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_UNREGISTERED_VOLUNTEER"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"
        app.launchEnvironment.merge(extraEnvironment) { _, new in new }
        app.launchArguments += extraArguments
        app.launch()

        let entry = app.descendants(matching: .any)["volunteerRealRegistrationEntry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 25), "资料页没有注册入口")
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        return app
    }
}
