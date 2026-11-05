import XCTest

/// 志愿者注册第 1 步拆屏之后（#699）的填表走法，`blindRunUITests` 与 `AccessibilityAuditTests` 共用。
///
/// 按 `accessibilityIdentifier` 找输入框，不按 `textFields` 下标：拆屏前的用例按下标填，
/// 换一次字段顺序就把手机号填进身份证号框。单独成文件：`blindRunUITests.swift` 已超长，SwiftLint 棘轮不许它再变长。
@MainActor
enum VolunteerRegistrationUITestSteps {
    static let identityValues: [(identifier: String, text: String)] = [
        ("volunteerRegistrationField.姓名", "测试志愿者"),
        ("volunteerRegistrationField.身份证号", "110101199001011234"),
        ("volunteerRegistrationField.手机号", "13800000002"),
    ]

    /// 在身份那一屏填三项必填。每填完一项就用键盘上的「完成」收起键盘（手机号是数字键盘，没有回车）：
    /// AX5 下三行上下排，下一个框会落在键盘后面，不收起的话 `tap()` 会点到键盘上的键。
    static func fillIdentity(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for value in identityValues {
            let field = app.textFields[value.identifier].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 8), "没找到 \(value.identifier)", file: file, line: line)
            for _ in 0..<3 where !field.isHittable { app.swipeUp() }
            field.tap()
            field.typeText(value.text)
            let done = app.buttons["收起键盘"].firstMatch
            if done.waitForExistence(timeout: 2) { done.tap() }
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
    }

    /// 说明页点「开始」→ 填身份 →「下一步」→ 经历页勾选同意 →「下一步」。
    static func submitIdentityAndExperience(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let start = app.buttons["volunteerRegistrationIntroStartButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 8), "进注册先看到说明页", file: file, line: line)
        XCTAssertTrue(
            app.buttons["volunteerRegistrationIntroAlternativeButton"].exists,
            "说明页要有改走人工审核的入口", file: file, line: line
        )
        start.tap()

        let identityNext = app.buttons["volunteerRegistrationIdentityNextButton"].firstMatch
        XCTAssertTrue(identityNext.waitForExistence(timeout: 8), file: file, line: line)
        XCTAssertFalse(identityNext.isEnabled, "三项必填没填完时「下一步」不能点", file: file, line: line)
        fillIdentity(app, file: file, line: line)
        XCTAssertTrue(identityNext.isEnabled, "三项填好后「下一步」要能点", file: file, line: line)
        identityNext.tap()

        let submit = app.buttons["volunteerRegistrationSubmitButton"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 8), "身份填完进经历那一屏", file: file, line: line)
        XCTAssertTrue(app.buttons["volunteerRegistrationSkipButton"].exists, "经历是选填，要能跳过", file: file, line: line)
        // 身份证号与人脸的单独同意：提交按钮上方的勾选框，默认不勾（#769）。
        let consent = app.buttons["volunteerIdentityConsentCheckbox"].firstMatch
        XCTAssertTrue(consent.exists, "提交前要有单独同意的勾选框", file: file, line: line)
        consent.tap()
        submit.tap()
    }
}
