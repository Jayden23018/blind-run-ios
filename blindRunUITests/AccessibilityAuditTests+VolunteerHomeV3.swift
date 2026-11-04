import XCTest

/// 陪跑员首页 v3（#694）：底部入口开启 / 暂停接单、接单页的派单状态卡、最近陪跑卡的同意闸。
/// 拆在这里是为了不让 `AccessibilityAuditTests` 主体再变长（SwiftLint 棘轮）。
extension AccessibilityAuditTests {
    /// 向右拖过 20% 真的会开启并进入接单主页；接单页的「暂停接单」确认后真的会停止接单。
    ///
    /// 🔴 **v3（#694）去掉了向左滑停止**（2026-09-17 的双向滑块），停止走接单页。
    /// 关闭路径上仍然不许有任何挽留，所以确认框只有一次、不劝，下面那条 `alerts.count == 0` 保留。
    /// 派单状态卡也在这里断：它 v3 起只在接单页上。
    ///
    /// 🔴 **这条只能走指针路径**：`XCUIElement.tap()` 注入的是物理触摸，不经过
    /// accessibility action（记忆 `xcuitest-cannot-invoke-accessibility-actions`）。
    @MainActor
    func testSlidingRightOpensAvailabilityAndHubPauseStopsIt() {
        let app = launchVolunteerHome(available: false)

        let slider = app.descendants(matching: .any)["volunteerAvailabilitySlider"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 25), "滑动 CTA 没渲染出来")
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerDispatchSummaryCard"].firstMatch.exists,
            "派单状态已搬进接单页，首页不该再有（#694）"
        )

        // 从滑块位置横着拖到轨道右端。开启阈值是 20%，拖到 95% 有足够余量。
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            )

        // 开启那一下同时进入接单主页（设计交付 v3 的流程）。
        let hubPill = app.descendants(matching: .any)["volunteerDispatchHubAcceptingPill"].firstMatch
        XCTAssertTrue(hubPill.waitForExistence(timeout: 20), "滑过阈值后没有开启，或者没有进入接单主页")
        let dispatchCard = app.descendants(matching: .any)["volunteerDispatchSummaryCard"].firstMatch
        XCTAssertTrue(dispatchCard.waitForExistence(timeout: 10), "接单页的状态卡里应当有派单状态")
        XCTAssertTrue(dispatchCard.label.contains("公里"), "派单状态要说覆盖范围：\(dispatchCard.label)")
        attachScreenshot(app, name: "volunteer-dispatch-hub-v3")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["进入接单"].waitForExistence(timeout: 15), "回到首页后入口应当是开启态")

        // 点按胶囊进入接单页（开启态没有滑块，整枚胶囊是入口）。
        app.buttons["进入接单"].firstMatch.tap()
        XCTAssertTrue(hubPill.waitForExistence(timeout: 15), "点按开启态的胶囊没有进入接单页")

        let pause = app.descendants(matching: .any)["volunteerDispatchHubPauseRow"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "接单页应当有「暂停接单」")
        for _ in 0..<10 where !pause.isHittable { app.swipeUp() }
        XCTAssertTrue(pause.isHittable, "「暂停接单」滚不到可点的位置")
        pause.tap()
        let confirm = app.buttons
            .matching(NSPredicate(format: "label == %@ AND identifier != %@", "暂停接单", "volunteerDispatchHubPauseRow"))
            .firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "暂停接单要先确认一次\n\(app.debugDescription)")
        confirm.tap()

        XCTAssertTrue(
            app.buttons["向右滑动，我现在有空陪跑"].waitForExistence(timeout: 15),
            "确认暂停后没有回到首页，或者没有停止接单"
        )
        XCTAssertEqual(app.alerts.count, 0, "停止接单不得弹任何挽留对话框")
    }

    /// 派单状态卡在 AX5 下仍然渲染、字确实放大了（2026-11-04 随派单状态搬进接单页，#694）。
    /// 见记忆 `low-vision-visual-channel-unaudited`：字号上限一直没人系统性看过。
    @MainActor
    func testDispatchHubStatusCardSurvivesAX5() {
        let app = launchVolunteerHome(
            extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        let enterHub = app.buttons["进入接单"].firstMatch
        XCTAssertTrue(enterHub.waitForExistence(timeout: 25), "AX5 下首页底部入口没渲染出来")
        enterHub.tap()

        let dispatchCard = app.descendants(matching: .any)["volunteerDispatchSummaryCard"].firstMatch
        XCTAssertTrue(dispatchCard.waitForExistence(timeout: 15), "AX5 下接单页的派单状态没渲染出来\n\(app.debugDescription)")
        // 上一版传错过常量名，被静默忽略，截图与默认字号一模一样却看着像验过了。钉一条断言。
        // 默认字号下这块（覆盖范围 + 保持开着）约 40pt，AX5 下必然远超 80。
        XCTAssertGreaterThan(dispatchCard.frame.height, 80, "AX5 launch argument did not take effect (height=\(dispatchCard.frame.height))")
        attachScreenshot(app, name: "volunteer-dispatch-hub-ax5")
    }

    /// #421：从首页点进去的那一页不许在同意之前申请定位权限。
    ///
    /// 2026-11-04 起（#694）首页「最近陪跑」卡点进去是跑后记录详情（`VolunteerRunRecordView`），
    /// 不再是订单详情。这条走真实路径：强制同意闸 + 没有同意记录 ⇒ 点卡片进详情 ⇒
    /// 任何无闸的 `requestPermission()` 会撞上 `LocationService.trackConsentPreconditionForDebug` 的断言、App 当场崩掉。
    @MainActor
    func testVolunteerRecentRunFromHomeDoesNotRequestLocationBeforeConsent() {
        let app = launchVolunteerHome(
            available: false,
            extraEnvironment: [
                "AIDRUN_UI_TEST_FORCE_LOCATION_TRACK_CONSENT": "1",
                "AIDRUN_UI_TEST_SEED_HOME_HISTORY": "this"
            ]
        )
        let card = app.descendants(matching: .any)["volunteerProfileRecentRunCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 25), "首页没有最近陪跑卡")
        for _ in 0..<10 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable, "滚到底了最近陪跑卡仍点不到")
        card.tap()

        // 详情页的 `.task` 在出现时就跑；给它一段时间，崩溃（assertionFailure）会让 App 离开前台。
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(
            app.state, .runningForeground,
            "App 不在前台 —— 多半是跑后详情在没有位置轨迹同意时调了 requestPermission()，撞上了调试断言"
        )
        XCTAssertFalse(card.isHittable, "点了最近陪跑卡没有离开首页")
    }
}
