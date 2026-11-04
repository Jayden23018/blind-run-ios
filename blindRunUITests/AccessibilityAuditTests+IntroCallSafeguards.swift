import XCTest

/// #660：通话磨合的退出动作先确认、「未接到来电」延后出现、第一次接单说明手机号去向
/// （OpenSpec `safeguard-intro-call-to-meetup`）。文案与判定由单测 `IntroCallToMeetupSafeguardTests` 钉，
/// 这里只钉「按下去先弹确认、取消后什么都没发生」这条线。
extension AccessibilityAuditTests {

    /// 盲人端 B1：「更换陪跑员」按下先问；按「取消」留在通话页。
    @MainActor
    func testBlindIntroCallDeclineAsksBeforeEndingTheRound() throws {
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "PENDING_INTRO_CALL")
        let currentOrder = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(currentOrder.waitForExistence(timeout: 20), "有订单的盲人首页没起来")
        currentOrder.tap()

        let decline = app.descendants(matching: .any)["blindIntroCallDeclineButton"].firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 20), "通话页没出现「更换陪跑员」")
        for _ in 0..<4 where !decline.isHittable { app.swipeUp() }
        decline.tap()

        let alert = app.alerts["确认更换陪跑员？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "按「更换陪跑员」没有先确认")
        attachScreenshot(app, name: "blind-intro-call-decline-confirm")
        alert.buttons["取消"].tap()
        XCTAssertTrue(decline.waitForExistence(timeout: 5), "取消之后离开了通话页")
    }

    /// 陪跑员端 V1：「不合适」按下先问；「未接到来电」刚进页时不出现，原位置是一行说明。
    @MainActor
    func testVolunteerIntroCallDeclineAsksAndUnreachableWaits() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        let app = launchVolunteerHome(seedOrderStatus: "PENDING_INTRO_CALL")
        let header = app.descendants(matching: .any)["volunteerIntroCallHeader"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 25), "有通话中的单时冷启动没有自动进通话页")
        XCTAssertTrue(header.label.contains("聊完记得在这里提交结果"), "头卡没有提交提醒：\(header.label)")

        XCTAssertFalse(app.buttons["volunteerIntroCallUnreachableButton"].exists, "刚进页就能按「未接到来电」")
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerIntroCallUnreachablePending"].firstMatch.exists,
            "「未接到来电」还没出现时，原位置要说明什么时候出现"
        )

        let decline = app.buttons["volunteerIntroCallDeclineButton"].firstMatch
        XCTAssertTrue(decline.waitForExistence(timeout: 10))
        decline.tap()
        let alert = app.alerts["确认不合适？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "按「不合适」没有先确认")
        attachScreenshot(app, name: "volunteer-intro-call-decline-confirm")
        alert.buttons["取消"].tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5), "取消之后离开了通话页")
        XCTAssertTrue(header.label.contains("来电"), "取消之后本轮被结束了：\(header.label)")
        try audit(app)
    }

    /// 第一次按接单：先说明手机号去向，按「先不接」不发送，邀请卡还在。
    @MainActor
    func testFirstAcceptExplainsWhereThePhoneNumberGoes() throws {
        let app = launchVolunteerHome(
            extraEnvironment: ["AIDRUN_UI_TEST_FORCE_PHONE_SHARE_DISCLOSURE": "1"],
            seedInvites: 1
        )
        let accept = app.buttons["接下这次陪跑"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 25), "邀请卡没有弹出")
        accept.tap()

        let alert = app.alerts["接单前请知悉"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "第一次接单没有说明手机号去向")
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "完整手机号")).firstMatch.exists,
            "说明里没讲完整手机号会给跑者"
        )
        attachScreenshot(app, name: "volunteer-phone-share-disclosure")
        alert.buttons["先不接"].tap()
        XCTAssertTrue(accept.waitForExistence(timeout: 5), "按「先不接」后邀请卡不见了 —— 不该发出响应")
    }
}
