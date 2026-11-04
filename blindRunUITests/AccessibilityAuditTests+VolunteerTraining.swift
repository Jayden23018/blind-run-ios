import XCTest

/// 陪跑培训四屏（列表 / 正文 / 整页答题 / 结果）照健康问卷重做后的用例（#698）。
///
/// 定稿：`docs/ui/mockups/volunteer-training-20261104/training-final.png`。负责人 2026-11-04 的四条意见各有断言守着：
/// ① 结果页没有「回到课程正文」；② 开始 / 提交 / 重答 / 完成都是贴底的通栏按钮，不用滚就点得到；
/// ③ 题干与选项之间的通栏分隔线（纯视觉，靠截图对比）；④ 选项短（Mock 数据，靠截图对比）。
///
/// Mock 默认「一门课都没学」，从「我的」页的常驻入口进 —— 首页那张培训卡在 #696 的改版范围里，不依赖它。
extension AccessibilityAuditTests {

    /// 陪跑基础两道题的 id 与选项（`MockAPIClient+Training.swift`）。XCUITest 是黑盒，只能抄一份。
    private enum TrainingFixture {
        static let basicsCourseId = 4001
        static let ropeQuestion = 41001     // 正确答案 B
        static let gravelQuestion = 41002   // 正确答案 A
    }

    @MainActor
    func testVolunteerTrainingQuizRetriesOnlyTheWrongAnswerAndEachScreenPassesAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let app = openVolunteerTraining(environment: ["AIDRUN_UI_TEST_COLOR_SCHEME": "light"], arguments: [])
        let basicsRow = try checkListAndCourseThenOpenQuiz(app)
        let submit = app.buttons["volunteerTrainingSubmitButton"].firstMatch
        try answerOneWrongAndCheckTheResult(app, submit: submit)
        try retryOnlyTheWrongOneAndFinish(app, submit: submit, basicsRow: basicsRow)
    }

    /// 列表 → 正文 → 打开答题页，每屏截图 + 审计。返回列表里「陪跑基础」那一行，最后回列表时还要看它。
    @available(iOS 17.0, *)
    @MainActor
    private func checkListAndCourseThenOpenQuiz(_ app: XCUIApplication) throws -> XCUIElement {
        // 列表：进度卡说清还差哪门、为什么接不到单
        let banner = app.descendants(matching: .any)["volunteerTrainingBlockedBanner"].firstMatch
        XCTAssertTrue(banner.label.contains("已完成 0 门，共 2 门"), "进度卡要读出门数（label=\(banner.label)）")
        XCTAssertTrue(banner.label.contains("学完才能接单"), "进度卡要说清没学完就接不到单（label=\(banner.label)）")
        let basicsRow = app.buttons["volunteerTrainingCourseRow_\(TrainingFixture.basicsCourseId)"].firstMatch
        XCTAssertTrue(basicsRow.waitForExistence(timeout: 10))
        XCTAssertTrue(basicsRow.label.contains("去学习"), "没学的必修课胶囊应是「去学习」（label=\(basicsRow.label)）")
        attachScreenshot(app, name: "training-list-light")
        try audit(app)

        // 正文：「开始答题」贴底，不滚动就点得到，高度不低于 64pt
        basicsRow.tap()
        let start = app.buttons["volunteerTrainingStartQuizButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "正文页没出来")
        XCTAssertTrue(start.isHittable, "「开始答题」应固定在底部，读到哪里都点得到")
        XCTAssertGreaterThanOrEqual(start.frame.height + 0.5, Self.minimumBlindPrimaryButtonHeight, "「开始答题」只有 \(start.frame.height)pt")
        attachScreenshot(app, name: "training-course-light")
        try audit(app)

        // 答题：一页全部题；没答完时提交不可用，并写出差哪几题
        start.tap()
        return basicsRow
    }

    /// 第 1 题答对、第 2 题答错，交卷后看结果页：一句结论 + 错题卡 + 唯一的「重答这 1 题」。
    @available(iOS 17.0, *)
    @MainActor
    private func answerOneWrongAndCheckTheResult(_ app: XCUIApplication, submit: XCUIElement) throws {
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "答题页没出来")
        XCTAssertFalse(submit.isEnabled, "一题没答时「提交答案」应不可用")
        XCTAssertEqual(unansweredHint(app), "还差第 1、2 题")
        XCTAssertTrue(app.buttons["volunteerTrainingQuizBackButton"].exists, "答题页左上要有返回")
        XCTAssertTrue(app.buttons["volunteerTrainingQuizCloseButton"].exists, "答题页右上要有关闭")
        attachScreenshot(app, name: "training-quiz-light")
        try audit(app)

        // 第 1 题答对（B），第 2 题答错（B）
        chooseOption(app, question: TrainingFixture.ropeQuestion, option: "B")
        chooseOption(app, question: TrainingFixture.gravelQuestion, option: "B")
        XCTAssertTrue(submit.isEnabled, "全部答完后「提交答案」应可用")
        XCTAssertFalse(app.staticTexts["volunteerTrainingUnansweredHint"].exists, "答完后不该再写还差哪题")
        attachScreenshot(app, name: "training-quiz-answered-light")
        submit.tap()

        // 没全对：一句结论 + 错题卡 + 唯一的「重答这 1 题」，没有「回到课程正文」
        let result = app.staticTexts["volunteerTrainingQuizResult"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "结果页没出来")
        XCTAssertEqual(result.label, "答对 1 题，共 2 题")
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerTrainingWrongQuestion_\(TrainingFixture.gravelQuestion)"].firstMatch.exists,
            "答错的第 2 题要有错题卡"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerTrainingWrongQuestion_\(TrainingFixture.ropeQuestion)"].firstMatch.exists,
            "答对的第 1 题不该进错题卡"
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "回到课程")).firstMatch.exists,
            "负责人 2026-11-04 去掉了结果页的「回到课程正文」"
        )
        let retry = app.buttons["volunteerTrainingRetryQuizButton"].firstMatch
        XCTAssertEqual(retry.label, "重答这 1 题")
        XCTAssertTrue(retry.isHittable, "「重答这 1 题」应固定在底部")
        attachScreenshot(app, name: "training-result-wrong-light")
        try audit(app)

        retry.tap()
    }

    /// 重答：答对的第 1 题保留，只清掉第 2 题；答对后「完成」回到列表，进度跟着变。
    @available(iOS 17.0, *)
    @MainActor
    private func retryOnlyTheWrongOneAndFinish(_ app: XCUIApplication, submit: XCUIElement, basicsRow: XCUIElement) throws {
        let result = app.staticTexts["volunteerTrainingQuizResult"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        XCTAssertEqual(unansweredHint(app), "还差第 2 题", "重答只该清掉答错的那题")
        let keptOption = option(app, question: TrainingFixture.ropeQuestion, option: "B")
        reveal(keptOption, in: app)
        XCTAssertTrue(keptOption.isSelected, "答对的第 1 题的选择要保留")
        chooseOption(app, question: TrainingFixture.gravelQuestion, option: "A")
        submit.tap()

        // 全对：结论 + 还差哪门必修 + 唯一的「完成」
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "2 题全对")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "还差 1 门必修：突发情况处置")).firstMatch.exists,
            "全对页要说还差哪门必修"
        )
        let finish = app.buttons["volunteerTrainingFinishButton"].firstMatch
        XCTAssertTrue(finish.isHittable)
        attachScreenshot(app, name: "training-result-passed-light")
        try audit(app)

        // 「完成」回到列表，进度跟着变
        finish.tap()
        XCTAssertTrue(basicsRow.waitForExistence(timeout: 10), "「完成」后应回到课程列表")
        let refreshed = NSPredicate(format: "label CONTAINS %@", "已完成")
        expectation(for: refreshed, evaluatedWith: basicsRow)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerTrainingBlockedBanner"].firstMatch.label.contains("已完成 1 门，共 2 门"),
            "回到列表后进度卡应变成 1 / 2 门"
        )
        attachScreenshot(app, name: "training-list-after-light")
    }

    /// 深色与最大字号（AX5）各走一遍四屏：截图供定稿对比，每屏过审计。
    @MainActor
    func testVolunteerTrainingScreensPassAuditInDarkAndLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let variants = Self.appearanceVariants.filter { ["dark", "ax5-light"].contains($0.name) }
        XCTAssertEqual(variants.count, 2, "appearanceVariants 里找不到 dark / ax5-light")
        for variant in variants {
            let app = openVolunteerTraining(environment: variant.environment, arguments: variant.arguments)
            attachScreenshot(app, name: "training-list-\(variant.name)")
            try audit(app)

            app.buttons["volunteerTrainingCourseRow_\(TrainingFixture.basicsCourseId)"].firstMatch.tap()
            let start = app.buttons["volunteerTrainingStartQuizButton"].firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 10), "\(variant.name)：正文页没出来")
            XCTAssertTrue(start.isHittable, "\(variant.name)：「开始答题」应固定在底部")
            attachScreenshot(app, name: "training-course-\(variant.name)")
            try audit(app)

            start.tap()
            let submit = app.buttons["volunteerTrainingSubmitButton"].firstMatch
            XCTAssertTrue(submit.waitForExistence(timeout: 10), "\(variant.name)：答题页没出来")
            chooseOption(app, question: TrainingFixture.ropeQuestion, option: "B")
            reveal(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "第 1 题")).firstMatch, in: app)
            attachScreenshot(app, name: "training-quiz-\(variant.name)")
            try audit(app)

            chooseOption(app, question: TrainingFixture.gravelQuestion, option: "B")
            submit.tap()
            let result = app.staticTexts["volunteerTrainingQuizResult"].firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10), "\(variant.name)：结果页没出来")
            attachScreenshot(app, name: "training-result-wrong-\(variant.name)")
            try audit(app)
            app.terminate()
        }
    }

    // MARK: - 步骤

    /// 从「我的」页的常驻入口进培训列表，等进度卡出来。
    @MainActor
    private func openVolunteerTraining(environment: [String: String], arguments: [String]) -> XCUIApplication {
        // Mock 默认一门课都没学；launchVolunteerHome 默认把必修标成已完成，这里关掉
        let app = launchVolunteerHome(
            available: false,
            extraEnvironment: environment.merging(["AIDRUN_MOCK_VOLUNTEER_TRAINING_COMPLETED": "0"]) { _, new in new },
            extraArguments: arguments
        )
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 25), "陪跑员标签栏没出来")
        tabBar.buttons["我的"].tap()
        let entry = app.buttons["volunteerTrainingSettingsEntry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "「我的」页没有陪跑培训入口")
        reveal(entry, in: app)
        entry.tap()
        let banner = app.descendants(matching: .any)["volunteerTrainingBlockedBanner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "培训列表的进度卡没出来\n\(app.debugDescription)")
        waitUntilSettled(banner)
        return app
    }

    private func option(_ app: XCUIApplication, question: Int, option: String) -> XCUIElement {
        app.buttons["volunteerTrainingOption_\(question)_\(option)"].firstMatch
    }

    /// 滚到选项露在底栏上沿以上再点 —— 直接 tap 会落在贴底的按钮栏上（记忆 `ui-test-tap-lands-on-persistent-sos-bar`）。
    @MainActor
    private func chooseOption(_ app: XCUIApplication, question: Int, option optionId: String) {
        let element = option(app, question: question, option: optionId)
        XCTAssertTrue(element.waitForExistence(timeout: 10), "找不到第 \(question) 题的选项 \(optionId)")
        reveal(element, in: app)
        element.tap()
        XCTAssertTrue(element.isSelected, "点了第 \(question) 题的选项 \(optionId) 却没有选中")
    }

    private func unansweredHint(_ app: XCUIApplication) -> String? {
        let hint = app.staticTexts["volunteerTrainingUnansweredHint"].firstMatch
        return hint.exists ? hint.label : nil
    }

    /// 把元素滚进「顶部导航栏以下、底栏 / 标签栏以上」的可见区。SwiftUI 不渲染屏幕外的内容，断言前先滚（commit 4cee939）。
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, maxDrags: Int = 24) {
        for _ in 0..<maxDrags {
            let bar = app.descendants(matching: .any)["volunteerTrainingBottomBar"].firstMatch
            let tabBar = app.tabBars.firstMatch
            let bottom = bar.exists ? bar.frame.minY : (tabBar.exists && tabBar.isHittable ? tabBar.frame.minY : app.frame.maxY - 60)
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 100
            guard element.exists else {
                drag(app, up: true)
                continue
            }
            if element.frame.maxY > bottom {
                drag(app, up: true)
            } else if element.frame.minY < top {
                drag(app, up: false)
            } else {
                break
            }
        }
    }

    private func drag(_ app: XCUIApplication, up: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.62 : 0.4))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.42 : 0.6))
        from.press(forDuration: 0.05, thenDragTo: to)
    }
}
