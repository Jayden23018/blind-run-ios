import XCTest

extension blindRunUITests {
    /// 进到「出发」那一态，返回刚点过的那枚主按钮的文案（给下一次流转当去重依据）。
    @discardableResult
    func openAcceptedVolunteerService(_ app: XCUIApplication) -> String {
        openCurrentVolunteerService(app)
        return tapVolunteerFlowPrimary(app)
    }

    /// 点陪跑员订单页的主按钮，返回它当时的文案。
    ///
    /// 四步骨架里这枚按钮**位置一格不动、只换文字**（`我出发了` → `我已到达集合点`），
    /// 所以两次流转取的是同一个 identifier。按中文文案取会在每次文案微调时全线飘红，
    /// 而那种红没有任何信息量（记忆 `merged-prs-whose-tests-never-ran`）。
    ///
    /// `after` 不为空时先等文案真的换过 —— 否则连点两次会落在同一个状态上，
    /// 而第二次点击会被后端拒绝，用例红在一个与被测行为无关的地方。
    @discardableResult
    func tapVolunteerFlowPrimary(
        _ app: XCUIApplication,
        after previousLabel: String? = nil,
        timeout: TimeInterval = 8
    ) -> String {
        let button = app.buttons["volunteerOrderFlowPrimaryButton"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "陪跑员订单页没有主按钮")
        if let previousLabel {
            expectation(
                for: NSPredicate(format: "label != %@", previousLabel),
                evaluatedWith: button
            )
            waitForExpectations(timeout: timeout)
        }
        let label = button.label
        button.tap()
        return label
    }

    /// 陪跑员订单页在不在屏上。
    ///
    /// 🚩 **不认导航栏标题。** 原来的判据是 `navigationBars["服务中"]`，而 2026-09-17 四步骨架之后
    /// 订单页标题就改叫「陪跑订单」、v2（2026-09-26）又把系统导航栏整条藏了（页面自带导航栏）——
    /// 这个判据在两种页面上都等不到，4 条用例因此卡在开头（#193 的根因）。
    /// 改认 identifier：v2 头卡 `volunteerOrderFlowStatusCard`，或跑步中页的 `volunteerRunningStatsCard`（#218）。
    func waitForVolunteerOrderPage(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let v2Page = app.descendants(matching: .any)["volunteerOrderFlowStatusCard"].firstMatch
        let runningPage = app.descendants(matching: .any)["volunteerRunningStatsCard"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if v2Page.waitForExistence(timeout: 1) || runningPage.exists { return true }
        } while Date() < deadline
        return false
    }

    /// 从订单页退回首页：先找页面上标着「返回」的按钮（v2 页面自带导航栏），没有再点系统导航栏的第一个按钮。
    func leaveVolunteerOrderPage(_ app: XCUIApplication) {
        let pageBack = app.buttons["返回"].firstMatch
        if pageBack.exists {
            pageBack.tap()
        } else {
            app.navigationBars.firstMatch.buttons.firstMatch.tap()
        }
    }

    /// 走到志愿者的服务中页。
    ///
    /// 🚩 **有在途订单时它本来就已经在那一页了**：设计交付 v3 §4.1 的三岔路让打开 App
    /// 直接进订单页，不再经过首页那张当前订单卡。所以这里先看服务页在不在，不在才回落到
    /// 「从首页点卡片进去」那条路 —— 两条路径都是真实的（后者是用户返回首页之后再点进来）。
    func openCurrentVolunteerService(
        _ app: XCUIApplication,
        requirePhone: Bool = true,
        alreadyOpenTimeout: TimeInterval = 25
    ) {
        if !waitForVolunteerOrderPage(app, timeout: alreadyOpenTimeout) {
            let currentOrderLabel = app.staticTexts["当前订单"].firstMatch
            XCTAssertTrue(currentOrderLabel.waitForExistence(timeout: 15), "Volunteer home should show the assigned current order")

            let firstOrder = app.staticTexts["李明"].firstMatch
            XCTAssertTrue(firstOrder.waitForExistence(timeout: 5), "Current order card should show the assigned blind runner")
            tapWhenHittableOrByCoordinate(firstOrder, app: app)
        }

        if requirePhone {
            // 号码上屏是**掩码**的（`VolunteerOrderFlowViews.swift` 走 `EmergencyContactResponse.maskPhone`）：
            // VoiceOver 外放，念全号等于把盲人的号码广播给周围所有人（`f404de2` / 审计 F10）。
            // 全号只进 `tel:`，所以这里两条一起断 —— 只断掩码的话，拨号按钮被删掉也不会有人发现，
            // 而那是志愿者接单后唯一够得到真号的出口。
            let maskedPhone = app.staticTexts["138****1001"].firstMatch
            XCTAssertTrue(
                maskedPhone.waitForExistence(timeout: 8),
                "接单后应展示掩码号码，全号不上屏、不朗读"
            )
            XCTAssertFalse(
                app.staticTexts["13800001001"].firstMatch.exists,
                "全号不得作为可见文本出现"
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["volunteerOrderFlowRow-phone"].firstMatch.exists,
                "掩码之后，拨号那一行是志愿者够到真号的唯一出口"
            )
        } else {
            // **两条路都算「进到订单页了」**：邀请 / 约好 / 出发 / 汇合 / 已完成 / 跑者已取消是
            // v2 骨架，跑步中是它自己的页面（#218）—— 调用方各自 seed 不同状态，这个 helper 两边都要认。
            //
            // 断 identifier 而不是断导航栏标题：标题是用户可见文案，抄进 UI 测试的
            // 误报率见记忆 `merged-prs-whose-tests-never-ran`。
            let skeleton = app.descendants(matching: .any)["volunteerOrderFlowStatusCard"].firstMatch
            let runningPage = app.descendants(matching: .any)["volunteerRunningStatsCard"].firstMatch
            XCTAssertTrue(
                skeleton.waitForExistence(timeout: 8) || runningPage.waitForExistence(timeout: 8),
                "没进到订单页：v2 骨架与跑步中页都没出现"
            )
        }
    }
}
