import XCTest

/// 下单页语音输入框：最大字号下折行而不是截字，回车行为与改之前一致（下单输入框截断）。
///
/// 单行 `TextField` 在大字号下把字截掉，真机审计报 textClipped（#565 的用例第一次审到第 3 步时发现）。
/// 改成 `axis: .vertical` 之后回车默认插入换行，所以另外钉住：搜索框回车仍然发起搜索、框里不留换行。
extension AccessibilityAuditTests {

    @MainActor
    func testBookingTextFieldsWrapAtLargestTextAndPassAudit() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchBlindHome(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openBookingForm(app)

        // 停掉语音后表单落在最后一步「确认」，往回一步是「需求」，再往回两步是「地点」。
        for (step, labels) in [("需求", ["路线备注，选填", "特殊说明，选填"]), ("地点", ["搜索出发地点", "出发地点补充描述"])] {
            let first = app.descendants(matching: .any)[labels[0]].firstMatch
            XCTAssertTrue(goBack(until: first, in: app), "没走到「\(step)」这一步")
            for label in labels {
                let field = app.descendants(matching: .any)[label].firstMatch
                XCTAssertTrue(swipeUntilVisible(field, in: app), "「\(step)」这一步没有「\(label)」")
            }
            attachScreenshot(app, name: "booking-voice-fields-ax-xxxl-\(step)")
            try audit(app)
        }
    }

    /// 回车：搜索框按下去照样搜索，框里不留换行；「路线备注」本来就该多行，回车保留换行。
    @MainActor
    func testBookingTextFieldsKeepTheirReturnKeyBehaviour() throws {
        let app = launchBlindHome()
        openBookingForm(app)

        let routeNotes = app.descendants(matching: .any)["路线备注，选填"].firstMatch
        XCTAssertTrue(goBack(until: routeNotes, in: app), "没走到「需求」这一步")
        XCTAssertTrue(swipeUntilVisible(routeNotes, in: app))
        routeNotes.tap()
        routeNotes.typeText("沿公园\n慢跑")
        XCTAssertTrue((routeNotes.value as? String ?? "").contains("\n"), "路线备注应保留换行：\(String(describing: routeNotes.value))")

        let search = app.descendants(matching: .any)["搜索出发地点"].firstMatch
        XCTAssertTrue(goBack(until: search, in: app), "没走到「地点」这一步")
        XCTAssertTrue(swipeUntilVisible(search, in: app))
        search.tap()
        search.typeText("公园\n")
        XCTAssertTrue(app.staticTexts["搜索结果"].firstMatch.waitForExistence(timeout: 10), "搜索框按回车没有发起搜索")
        XCTAssertFalse((search.value as? String ?? "").contains("\n"), "搜索框里留下了换行：\(String(describing: search.value))")
    }

    // MARK: - 辅助

    @MainActor
    private func openBookingForm(_ app: XCUIApplication) {
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "下单页没起来")
        let stopVoice = app.descendants(matching: .any)["blindBookingStopVoiceButton"].firstMatch
        if stopVoice.waitForExistence(timeout: 5) { stopVoice.tap() }
    }

    /// 按「上一步」直到目标出现。上一步在底栏里，常驻可点。
    @MainActor
    private func goBack(until element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<4 {
            if element.waitForExistence(timeout: 3) { return true }
            let back = app.buttons["上一步"].firstMatch
            guard back.exists else { return false }
            back.tap()
        }
        return element.waitForExistence(timeout: 3)
    }

    /// 滚到元素整个露在底栏（「重复当前状态」所在那一条）上方。
    @MainActor
    private func swipeUntilVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let barTop = app.buttons["重复当前状态"].firstMatch.frame.minY
        for _ in 0..<10 {
            if element.exists, element.isHittable, element.frame.maxY < barTop - 4 { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }
}
