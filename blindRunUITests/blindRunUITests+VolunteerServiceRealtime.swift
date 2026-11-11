import XCTest

extension blindRunUITests {
    @MainActor
    func testRealtimeEnRouteWithHungDetailAndLocationSendRemainsScrollable() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            disableMap: false,
            hangTransitionConfirmation: true,
            confirmTransitionViaRealtime: true,
            hangEscortLocationSend: true,
            homeLoadTimeout: 3
        )

        openCurrentVolunteerService(app, requirePhone: false)
        let enRouteLabel = tapVolunteerFlowPrimary(app)

        // 实时事件必须在「上报位置」那条请求挂住的情况下就把界面推进到下一态 ——
        // 判据是主按钮的文案换了（`我出发了` → `我已到达集合点`），位置一格没动。
        let primary = app.buttons["volunteerOrderFlowPrimaryButton"].firstMatch
        expectation(for: NSPredicate(format: "label != %@", enRouteLabel), evaluatedWith: primary)
        waitForExpectations(timeout: 5)

        // 🚩 2026-09-17：这一态（`DRIVER_EN_ROUTE`）已从地图 + 底部面板换成四步骨架，
        // 所以这里不再断言 `volunteerServicePanel` 与地图底图。**被测行为没变** ——
        // 「挂住的详情/上报没有冻住界面，控件滚一下仍然可达」在新页面上同样要成立。
        // v7（#945）起「我去不了」收进顶栏「···」。
        let moreMenu = app.buttons["volunteerOrderNavMoreMenu"].firstMatch
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 5), "顶栏没有「···」（「我去不了」在里面）")
        app.swipeUp()
        app.swipeDown()
        XCTAssertTrue(app.buttons["返回"].firstMatch.isHittable, "返回键在页面自带的导航栏上，滚动后也该点得到")
        XCTAssertTrue(waitForElementToBeHittable(primary, timeout: 3), "主按钮贴底常驻，任何滚动位置都该点得到")
    }

    @MainActor
    func testRealtimeTransitionIntoRunningDoesNotEnterSwiftUIRefreshLoop() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            disableMap: false,
            hangTransitionConfirmation: true,
            confirmTransitionViaRealtime: true,
            hangEscortLocationSend: true,
            homeLoadTimeout: 3
        )

        openCurrentVolunteerService(app, requirePhone: false)
        let enRouteLabel = tapVolunteerFlowPrimary(app)
        // 🚩 2026-09-26（#218）：跑步中也换成 v2 页面，**整条陪跑流程已经没有地图**。
        // 原名 `testRealtimeArrivedWithRealMap…`，验的是「真地图 + 挂住的请求会不会把 SwiftUI
        // 拖进重绘循环」。地图没了，剩下那一半照样要成立：实时推送把页面推进到跑步中、
        // 挂住的确认与位置上报还在后台，页面仍然能滚、返回键与结束按钮仍然点得到。
        let arrivedLabel = tapVolunteerFlowPrimary(app, after: enRouteLabel)
        tapVolunteerFlowPrimary(app, after: arrivedLabel)

        let card = app.descendants(matching: .any)["volunteerRunningStatsCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), "开始跑步之后没有换成跑步中页")
        let finish = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            card.swipeUp()
            card.swipeDown()
            XCTAssertTrue(app.buttons["返回"].firstMatch.isHittable)
            XCTAssertTrue(finish.isHittable)
        }
    }

    @MainActor
    func testMockVolunteerLegacyTrainingCompletesWithoutTrainingAndReturnsHomeUnavailable() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            forceRealVolunteerRegistration: true,
            unregisteredVolunteer: true,
            legacyTrainingStatusAfterFaceVerify: true
        )

        let entry = app.descendants(matching: .any)["volunteerRealRegistrationEntry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 12), "Volunteer profile should expose the registration entry")
        entry.tap()

        // #699 拆屏：说明页 → 身份 → 经历（选填）→ 同意层 → 刷脸。逐屏断言在 `VolunteerRegistrationUITestSteps`。
        XCTAssertFalse(app.staticTexts["培训学习"].exists)
        XCTAssertFalse(app.buttons["加载测验"].exists)
        XCTAssertFalse(app.buttons["提交测验"].exists)
        VolunteerRegistrationUITestSteps.submitIdentityAndExperience(app)

        let faceVerify = app.buttons["volunteerFaceVerifyStartButton"].firstMatch
        XCTAssertTrue(faceVerify.waitForExistence(timeout: 8))
        faceVerify.tap()

        // 人脸通过后自动进志愿者首页，不再停在结束页等「返回志愿者首页」（#768）。
        // 2026-09-14 改版把首页那个 `Toggle` 换成了底部的滑动 CTA，`app.switches` 不再存在。
        // 「没有被自动打开」这条约束没变，判据换成：滑块的无障碍按钮名是**关闭态**那一个。
        //
        // 2026-09-17 滑块改成双向（右开 / 左关）之后状态条也不存在了，两态都是同一条轨道，
        // 只有无障碍表示的按钮名不同：关闭态「向右滑动，我现在有空陪跑」/ 开启态「进入接单」。
        //
        // Mock 默认未完成培训，所以这里是第三态：滑不开，按钮名是「查看接单前进度」（#658）。
        let slider = app.buttons["查看接单前进度"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 12), "未完成培训时底部应当是通往进度页的入口")
        XCTAssertFalse(app.buttons["返回首页"].exists, "人脸通过后不该再要用户手动返回")
        XCTAssertFalse(
            app.buttons["进入接单"].exists,
            "Legacy completion must not automatically enable availability"
        )
    }

    @MainActor
    func testMockVolunteerServiceArrivedWaitingScreenshots() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true
        )

        let enRouteLabel = openAcceptedVolunteerService(app)
        attachScreenshot(named: "volunteer-service-accepted", app: app)

        tapVolunteerFlowPrimary(app, after: enRouteLabel)

        // 汇合那一屏 2026-09-17 起也是骨架，主按钮从「开始服务」换成「开始跑步」
        // —— 按 identifier 取，不按文案。
        let startButton = app.buttons["volunteerOrderFlowPrimaryButton"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Arrived order should show start-service action")
        let finishControl = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertFalse(finishControl.waitForExistence(timeout: 1), "Arrived order should hide the finish control")
        attachScreenshot(named: "volunteer-service-arrived", app: app)
        startButton.tap()
        XCTAssertTrue(finishControl.waitForExistence(timeout: 8), "Started service should show the long-press finish control")
        attachScreenshot(named: "volunteer-service-in-progress", app: app)
    }

    /// 后端放行时刻（#340 / 后端 #546）接进了订单页：没到 `earliestDepartureAt` 时「我已经出发了」原位不可按，
    /// 过了就能按。单测只钉了 `VolunteerActionGate` 这个纯函数；这条钉的是它真的接到了按钮上。
    @MainActor
    func testVolunteerDepartureButtonStaysDisabledUntilTheServerReleaseTime() throws {
        for (minutes, shouldBeEnabled) in [(90, false), (-1, true)] {
            let app = launchApp(
                apiEnvironment: "mock",
                accessToken: "mock_jwt_token_for_testing",
                activeRole: "volunteer",
                preseedVolunteerProfile: true,
                preseedVolunteerAvailable: true,
                preseedVolunteerActiveOrder: true,
                seedOrderStatus: "PENDING_ACCEPT",
                seedEarliestDepartureMinutes: minutes
            )
            openCurrentVolunteerService(app, requirePhone: false)
            XCTAssertTrue(waitForVolunteerOrderPage(app, timeout: 10), "PENDING_ACCEPT 没进到订单页")
            let primary = app.buttons["volunteerOrderFlowPrimaryButton"].firstMatch
            XCTAssertTrue(primary.waitForExistence(timeout: 10), "订单页没有主按钮")
            XCTAssertEqual(
                primary.isEnabled, shouldBeEnabled,
                "放行时刻在 \(minutes) 分钟后，主按钮「\(primary.label)」可按状态不对"
            )
            app.terminate()
        }
    }
}
