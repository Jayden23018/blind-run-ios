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

    /// 「置顶 · 编辑」：把评分移出置顶 → 返回首页 → 评分卡不在、连续陪跑卡还在（#694，负责人 2026-11-04 要求）。
    ///
    /// 点的是行首那枚红色减号（`.borderless` 按钮，指针路径），不是系统的左滑删除。
    /// 断「评分卡不在」之前先断「连续陪跑卡在」：首页整块没渲染时前者也会假绿。
    @MainActor
    func testEditingPinnedCardsRemovesTheRatingCardFromHome() {
        let app = launchVolunteerHome()
        let rating = app.descendants(matching: .any)["volunteerHomeHalfCard.rating"].firstMatch
        XCTAssertTrue(rating.waitForExistence(timeout: 25), "默认置顶里应当有评分卡")

        let edit = app.descendants(matching: .any)["volunteerHomePinnedEditLink"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "「置顶」标题右边应当有「编辑」")
        edit.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerHomePinnedEditView"].firstMatch.waitForExistence(timeout: 10),
            "点「编辑」没有进编辑置顶页"
        )
        let remove = app.buttons["volunteerHomePinnedRemove.rating"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "编辑页里评分那一行没有移出按钮")
        remove.tap()
        XCTAssertTrue(
            app.buttons["volunteerHomePinnedAdd.rating"].firstMatch.waitForExistence(timeout: 5),
            "移出之后评分应当落到「其他卡片」里，带加入按钮"
        )
        attachScreenshot(app, name: "volunteer-home-pinned-edit")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let streak = app.descendants(matching: .any)["volunteerHomeHalfCard.streak"].firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 10), "连续陪跑卡应当还在首页")
        XCTAssertFalse(rating.exists, "评分已移出置顶，首页不该再有评分卡")
    }

    /// 编辑置顶页在亮 / 暗 / AX5 下过审计。先移出一张，让「其他卡片」那一组（带加入按钮）也在屏幕上。
    ///
    /// ⚠️ `List` 行的审计会误报「改不了字号」（记忆 `list-rows-false-dynamic-type-audit`）：
    /// 报了先看 AX5 截图里字有没有放大，再判真假。
    @MainActor
    func testVolunteerHomePinnedEditPassesAuditInLightDarkAndLargestText() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("performAccessibilityAudit 需要 iOS 17") }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for variant in Self.appearanceVariants {
            let app = launchVolunteerHome(extraEnvironment: variant.environment, extraArguments: variant.arguments)
            let edit = app.descendants(matching: .any)["volunteerHomePinnedEditLink"].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 25), "\(variant.name)：「置顶」标题右边没有「编辑」")
            edit.tap()
            // 移第一行：AX5 下它也一定在屏幕上。加入按钮落在列表最后，`List` 不渲染屏幕外的行，滚到它出现。
            let remove = app.buttons["volunteerHomePinnedRemove.duration"].firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 10), "\(variant.name)：编辑置顶页没出来")
            remove.tap()
            let add = app.buttons["volunteerHomePinnedAdd.duration"].firstMatch
            for _ in 0..<6 where !add.exists { app.swipeUp() }
            XCTAssertTrue(add.waitForExistence(timeout: 5), "\(variant.name)：移出后陪伴时长没落到「其他卡片」")
            waitUntilSettled(add)
            attachScreenshot(app, name: "volunteer-home-pinned-edit-\(variant.name)")
            try audit(app)
            app.terminate()
        }
    }
}

