import XCTest

// 跑步中求助中心里跑者自己的出路（#660 B-4 / F-10、F-20）。
extension AccessibilityAuditTests {
    /// 跑步中：方格下面有「陪跑员身体不适或倒地怎么办」与「陪跑员联系不上，结束本次陪跑」。
    /// 结束要先过确认框；「先不结束」什么都不发生，「结束陪跑」后弹层关闭、订单页进入已完成。
    /// Mock 的 `/finish` 不判陪跑员是否在线，所以这里走的是成功那一支；409 那一支（原话留在弹层里）在单测里。
    @MainActor
    func testRunSafetyHubOffersVolunteerUnwellGuideAndConfirmedEndRun() throws {
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "IN_PROGRESS")
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "有订单的盲人首页没起来")
        card.tap()
        let entry = app.descendants(matching: .any)["blindOrderFlowSafetyHubButton"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "跑步中页没有「求助与安全」")
        entry.tap()
        let hub = app.descendants(matching: .any)["blindSafetyHub"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 10), "求助中心没打开")

        let guide = app.descendants(matching: .any)["blindSafetyHubVolunteerUnwellGuide"].firstMatch
        let endRun = app.buttons["blindSafetyHubEndRunWithoutVolunteer"].firstMatch
        // 方格在 ScrollView 里，这一段排在最后。往上拖到按钮露出来，且不压在底部红胶囊上。
        let sos = app.descendants(matching: .any)["blindSafetyHubTriggerEmergency"].firstMatch
        for _ in 0..<6 where !(endRun.exists && endRun.isHittable && endRun.frame.maxY <= sos.frame.minY) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertTrue(guide.exists, "跑步中的求助中心没有「陪跑员身体不适或倒地怎么办」")
        XCTAssertTrue(guide.label.contains("120"), "指引没说先拨 120：\(guide.label)")
        XCTAssertTrue(endRun.exists && endRun.isHittable, "跑步中的求助中心没有结束出口")
        XCTAssertGreaterThanOrEqual(endRun.frame.height, Self.minimumBlindPrimaryButtonHeight, "盲人端按钮不得低于 64pt")
        XCTAssertLessThanOrEqual(endRun.frame.maxY, sos.frame.minY, "结束出口压在了红胶囊上")
        attachScreenshot(app, name: "blind-run-safety-hub-end-run")
        if #available(iOS 17.0, *) { try audit(app) }

        endRun.tap()
        let alert = app.alerts["结束本次陪跑？"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "没有二次确认")
        attachScreenshot(app, name: "blind-run-safety-hub-end-run-confirm")
        alert.buttons["先不结束"].tap()
        XCTAssertTrue(hub.waitForExistence(timeout: 3), "按「先不结束」后求助中心不该关")

        endRun.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["结束陪跑"].tap()
        XCTAssertTrue(hub.waitForNonExistence(timeout: 5), "确认后要先关弹层")
        let done = app.descendants(matching: .any)["blindOrderFlowPrimaryButton"].firstMatch
        let finished = NSPredicate(format: "label == %@", "完成")
        expectation(for: finished, evaluatedWith: done)
        waitForExpectations(timeout: 15)
        attachScreenshot(app, name: "blind-run-finished-by-runner")
    }

    /// 跑步前的求助中心（本地拨号档）既没有指引也没有结束出口：后端不收，指引也不适用。
    @MainActor
    func testSafetyHubBeforeTheRunHasNoEndRunExit() throws {
        let app = launchBlindHome(emptyOrders: false)
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let entry = app.descendants(matching: .any)["blindOrderFlowSafetyHubButton"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["blindSafetyHubLocalCall"].firstMatch.waitForExistence(timeout: 10))
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(app.buttons["blindSafetyHubEndRunWithoutVolunteer"].exists, "跑步前出现了结束出口")
        XCTAssertFalse(app.descendants(matching: .any)["blindSafetyHubVolunteerUnwellGuide"].exists)
    }
}
