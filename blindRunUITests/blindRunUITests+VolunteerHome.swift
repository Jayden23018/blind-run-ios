import XCTest

extension blindRunUITests {
    /// 订单页 v2 每一屏各留一张首屏、一张滚到底的截图，给「对照画板」（openspec 任务 4.10）用。
    ///
    /// 只断「页面到了」，不断长相 —— 长相是拿截图跟 `zhumangpao-handoff/reference/artboards/` 人工比的。
    /// ⚠️ 种子订单不带 `eta` / `meet` 这些 v2 字段，截到的是**字段缺失时的降级样子**，不是满配。
    @MainActor
    func testVolunteerOrderV2StatesProduceScreenshotsForDesignReview() throws {
        // 画板是竖屏的；而且横屏下 `app.swipeUp()` 会从底边划起、触发系统切 App（实测切走过一次）。
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        for status in ["SCHEDULED_CONFIRMED", "PENDING_ACCEPT", "DRIVER_EN_ROUTE", "DRIVER_ARRIVED"] {
            let app = launchApp(
                apiEnvironment: "mock",
                accessToken: "mock_jwt_token_for_testing",
                activeRole: "volunteer",
                preseedVolunteerProfile: true,
                preseedVolunteerAvailable: true,
                preseedVolunteerActiveOrder: true,
                seedOrderStatus: status
            )
            openCurrentVolunteerService(app, requirePhone: false)
            XCTAssertTrue(waitForVolunteerOrderPage(app, timeout: 10), "\(status) 没进到订单页")
            attachScreenshot(named: "v2-\(status)-top", app: app)
            app.scrollViews.firstMatch.swipeUp()
            app.scrollViews.firstMatch.swipeUp()
            attachScreenshot(named: "v2-\(status)-bottom", app: app)
            app.terminate()
        }

        let inviteApp = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            seedInvites: 1
        )
        XCTAssertTrue(inviteApp.buttons["接下这次陪跑"].firstMatch.waitForExistence(timeout: 20), "邀请卡没弹出来")
        attachScreenshot(named: "v2-INVITE", app: inviteApp)
        inviteApp.terminate()

        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            seedOrderStatus: "IN_PROGRESS"
        )
        openCurrentVolunteerService(app, requirePhone: false)
        let finishControl = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertTrue(finishControl.waitForExistence(timeout: 15), "没进到跑步中")
        finishControl.press(forDuration: 2.6)
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerOrderFlowRow-runRecord"].firstMatch.waitForExistence(timeout: 10),
            "长按结束后没到完成页"
        )
        attachScreenshot(named: "v2-COMPLETED-top", app: app)
        app.scrollViews.firstMatch.swipeUp()
        attachScreenshot(named: "v2-COMPLETED-bottom", app: app)
    }

    /// 邀请卡（设计交付 v3 §4.4.2）打开时，三个动作都真的在无障碍树里。
    ///
    /// 🚩 **断的是形状，不是行为。** 三枚都是真 `Button`，`tap()` 走得通；但这条用例**不点**
    /// 它们 —— 点下去要么发出一次真实的派单响应、要么进一条五秒延时链路，两者都会让这条用例
    /// 在验别的东西。行为那一半由 `blindRunTests` 里直接调 view model 的四条用例验
    /// （延时发送、撤销、过期、接下）。
    ///
    /// 🔴 **这一屏没有种子就到不了。** 派单只从 WebSocket 来，而 UI 测试默认
    /// `disableWebSocket` —— 所以走 `seedInvites`。种子名字打错时的表现是**卡片压根不出现**、
    /// 下面第一条断言当场红，不是静默通过。
    ///
    /// ⚠️ 主按钮按**文案**断而不是按 identifier：App 侧那个 id 是三元表达式
    /// （`? "volunteerDispatchInterestedButton" : "volunteerDispatchAcceptButton"`），
    /// 而 `stale-ui-test-identifier` 守卫的正则只认直接写在 `accessibilityIdentifier(...)`
    /// 里的字面量，看不见三元的两支 ⇒ 引用它们会被误拦。**不为讨好守卫去改 App 的代码形状**
    /// （记忆 `identifier-guard-blocks-any-edit-that-moves-a-literal`）；
    /// 「这一下会发哪个 action」本来就由单测断。
    @MainActor
    func testMockVolunteerInviteSheetExposesItsThreeActions() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            seedInvites: 2
        )

        let accept = app.buttons["接下这次陪跑"].firstMatch
        XCTAssertTrue(
            accept.waitForExistence(timeout: 20),
            "邀请卡应当自动弹出并带主按钮\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerInviteDeclineButton"].firstMatch.exists,
            "「这次去不了」必须在无障碍树里 —— 它是这张卡上唯一的退出方式"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerDispatchDetailButton"].firstMatch.exists,
            "「查看详情」必须在无障碍树里"
        )
        // 标题行按「N 个新邀请」报数（种子给了 2 条）。只留一条的实现会念成「新的陪跑邀请」。
        XCTAssertTrue(
            app.staticTexts["2 个新邀请"].firstMatch.exists,
            "多条邀请时标题行要报数\n\(app.debugDescription)"
        )
        // 三格数据按「标签，值」念，而不是屏幕上的上下顺序（值在上是为了扫读）。
        // 缺值不画格子，所以它的存在同时证明 `distanceKm` 那条路是通的。
        XCTAssertTrue(
            app.descendants(matching: .any)["离你，3.2 公里"].firstMatch.exists,
            "三格数据的读屏标签要先说这是什么\n\(app.debugDescription)"
        )

        // 跑者行（§4.4.2 第 7 项）。种子里塞了 `TOTAL_BLIND` + `TETHER_ROPE`
        // —— 真实路径上这两项由 `GET /api/orders/available` 补，而 mock 对那条路径恒返空数组。
        // 断的是「这一行在无障碍树里长什么样」，数据怎么来的由 `VolunteerInviteState.merge` 的单测验。
        XCTAssertTrue(
            app.descendants(matching: .any)["跑者李，全盲，牵引绳"].firstMatch.exists,
            "跑者行要合成一个焦点念全；种子姓名「李*」读屏只念「李」（#339）\n\(app.debugDescription)"
        )

        // 🔴 **邀请卡弹出时，下面那一屏必须从无障碍树里消失。**
        //
        // 这一条 2026-09-18 才有意义：卡片从 `.sheet` 换成了自定义 overlay，而系统 sheet
        // 白送的「背景变成 inert」overlay 不送。少了那道屏蔽的表现是 VoiceOver 用户
        // 一路右划就滑到了被压暗层盖住的首页上 —— 念得到、按得动，而屏幕上它在一块黑布底下。
        // 屏幕上看不出任何异常，所以只能靠这条断言。
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch.exists,
            "邀请卡盖住的那一屏不该还留在无障碍树里\n\(app.debugDescription)"
        )
        // 标签栏是 UIKit 的，和首页不是同一条屏蔽路径能不能盖住的问题 —— 单独断。
        XCTAssertFalse(
            app.tabBars.firstMatch.exists,
            "邀请卡盖住的标签栏也不该还留在无障碍树里\n\(app.debugDescription)"
        )

        // 🔴 **「查看详情」是这条用例唯一会点的东西，而它必须点。**
        // 这一跳是从**自定义 overlay** 里再弹一个 `fullScreenCover`
        // （设计交付 v3 §4.4.2 第 10 项 → §5 的「邀请」订单页）。
        // 2026-09-17 验过的是「从 sheet 里弹」，换成 overlay 之后那条结论**不自动成立** ——
        // 两层模态叠在一起在 iOS 16 上行不行读代码验不了，而本仓库模拟器通道永久不可用
        // ⇒ 只有真机点一下才知道。点它不会发出任何派单响应，所以不像另外两枚那样
        // 会把这条用例变成在验别的东西。
        app.descendants(matching: .any)["volunteerDispatchDetailButton"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["陪跑邀请"].firstMatch.waitForExistence(timeout: 10),
            "从邀请卡（自定义 overlay）里应当能再弹出完整订单页（fullScreenCover）\n\(app.debugDescription)"
        )
        // 引导绳停在第 1 步（v2 用绳子代替了四步进度条）。按前缀认：标签自 #399 起接着「。接下来：…」，精确匹配从那时就红。
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "第 1 步，共 4 步，邀请，还没约好")).firstMatch.exists,
            "详情页应当停在四步骨架的第 1 步\n\(app.debugDescription)"
        )

        app.buttons["返回"].firstMatch.tap()
        XCTAssertTrue(
            accept.waitForExistence(timeout: 10),
            "从详情页返回之后邀请卡还在，倒计时没有停"
        )
    }

    /// 上一条的另一半：屏蔽是**跟着卡片走**的，卡片收起后被盖住的那一屏必须回到无障碍树里。
    ///
    /// 屏蔽在 UIKit 侧置空了 tab bar controller 的子元素列表（`TabBarAccessibilityHider`），
    /// 没有这一条的话「忘了恢复」的表现是：卡片收起、屏幕上一切正常，而读屏用户整个首页和
    /// 标签栏都摸不到 —— 比没屏蔽更糟。收起走的是点压暗层（「不回复，先收起来」），
    /// 不发任何派单响应，所以这条不会变成在验别的东西。
    @MainActor
    func testMockVolunteerInviteSheetGivesTheScreenBehindBackOnceDismissed() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            seedInvites: 1
        )

        let accept = app.buttons["接下这次陪跑"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 20), "邀请卡应当自动弹出\n\(app.debugDescription)")
        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertFalse(identityRow.exists, "前提：卡片在的时候首页不在树里\n\(app.debugDescription)")

        // 压暗层本身对读屏隐藏，只能点坐标：屏幕上沿那一截是压暗层，卡片从底部升起够不到。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()

        XCTAssertTrue(
            identityRow.waitForExistence(timeout: 10),
            "卡片收起后首页必须回到无障碍树里\n\(app.debugDescription)"
        )
        XCTAssertFalse(accept.exists, "点压暗层应当收起卡片")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "卡片收起后标签栏必须回到无障碍树里")
    }

    /// 志愿者首页：页头 → 作业区 → 置顶（陪伴时长、连续陪跑、评分、最近陪跑、徽章）。没有地图、没有工作台、**没有派单状态**。
    ///
    /// > 2026-09-15 工作台被删（用户原话「好像是没什么用的」），派单状态并到首屏最底部。
    /// > 2026-11-04 陪跑员首页 v3（#694）：派单状态与定位摘要搬进接单页的状态卡，
    /// > 首页不再出现任何接单状态文字。接单页那一侧由 `AccessibilityAuditTests` 的滑块用例断。
    @MainActor
    func testMockVolunteerFirstScreenHasNoDispatchStatusMapOrWorkbench() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true
        )

        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 15), "Volunteer first screen should expose its identity row")
        assertVolunteerTopStatusBlockPosition(identityRow, app: app)
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerHomeCurrentOrderCard"].firstMatch.exists,
            "没有在途订单时不该渲染当前订单卡"
        )
        // Mock 的 `trainingProgress` 默认为空 ⇒ 派单摘要恒带 `TRAINING_INCOMPLETE`。
        // #706 起这**不再**让作业区出现：培训由底部胶囊「暂不能接单」说，首页顶部不再挂「需要你处理」
        // （原来的培训卡在作业区里面，整块不在就等于它也不在）。
        XCTAssertFalse(
            app.staticTexts["需要你处理"].firstMatch.exists,
            "没有订单、预约、定位异常或加载错误时，没学完培训也不该出现「需要你处理」（#706）"
        )
        XCTAssertTrue(
            app.staticTexts["置顶"].firstMatch.waitForExistence(timeout: 10),
            "First screen should lead with the impact section"
        )
        XCTAssertTrue(app.staticTexts["最近陪跑"].firstMatch.exists, "First screen should show the recent-run stream")
        XCTAssertFalse(app.buttons["查看全部订单"].firstMatch.exists, "Primary volunteer home must not expose the public order list")
        // 预置「已开启」但 Mock 默认未完成培训：开关开着也接不到单，所以按钮不是「进入接单」，
        // 而是「查看接单前进度」（#658）。真能接单时的形状由审计用例覆盖。
        XCTAssertTrue(
            app.buttons["查看接单前进度"].firstMatch.waitForExistence(timeout: 5),
            "开着但未完成培训时，滑块的无障碍按钮应当是「查看接单前进度」"
        )
        XCTAssertFalse(
            app.buttons["向右滑动，我现在有空陪跑"].firstMatch.exists,
            "已经开启了还提示「我现在有空陪跑」，等于告诉志愿者他没开"
        )
        attachScreenshot(named: "volunteer-profile-first-screen", app: app)

        // 工作台入口整行已删，没有任何二级页可进。
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerProfileWorkbenchEntry"].firstMatch.exists,  // guard:allow stale-ui-test-identifier
            "派单工作台已删除，首屏不该再有它的入口"
        )
        // 「回到当前位置」随地图一起删了 —— 它是 identifier 守卫管不到的中文文案，只能在这儿断。
        XCTAssertFalse(app.buttons["回到当前位置"].firstMatch.exists, "地图删除后「回到当前位置」不该还在")

        // 滚到底（徽章是最后一块）再断「没有派单状态」：屏幕外的元素在 ScrollView 里照样存在，
        // 所以不滚也断得出；滚到底是为了让截图看得到底部。
        let badgesHeader = app.staticTexts["徽章"].firstMatch
        for _ in 0..<16 where !badgesHeader.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(badgesHeader.exists, "首页最后一块应当是徽章\n\(app.debugDescription)")
        let dispatchCard = app.descendants(matching: .any)["volunteerDispatchSummaryCard"].firstMatch
        XCTAssertFalse(dispatchCard.exists, "派单状态已搬进接单页，首页不该再有（#694）")
        XCTAssertFalse(app.staticTexts["接单率"].firstMatch.exists, "接单率已删除，不该再出现")

        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerHomeMap"].firstMatch.exists,  // guard:allow stale-ui-test-identifier
            "志愿者辅助地图已删除，全 App 不该再有它"
        )

        attachScreenshot(named: "volunteer-first-screen-dispatch-stats", app: app)
    }

    /// 培训页导航栏标题，单一来源 `VolunteerTrainingCopy.navigationTitle`。
    ///
    /// XCUITest 是黑盒进不了 app 的类型，只能抄一份 —— 抄错的方向是安全的（会红不会绿）。
    private static let volunteerTrainingTitle = "陪跑培训"

    /// 没学完培训时，培训从**底部胶囊 → 接单前进度页 → 培训一步**可达（#706）。
    ///
    /// 首页作业区的整卡培训入口已删（负责人 2026-11-05：「下面的按钮暂不能接单就已经显示了
    /// 他需要做的东西了」）。这条守的是删掉之后培训仍然够得着，且只多一页。
    ///
    /// Mock 默认「一门课都没学」（`MockAPIClient.trainingProgress` 初始为空），
    /// 所以派单摘要默认就带 `TRAINING_INCOMPLETE` —— 不用额外预置。
    /// 胶囊点的是 `accessibilityRepresentation` 里那枚按钮的坐标，指针路径同样走 `onShowProgress`
    /// （同 `testBlockedSliderSaysWhyAndOpensReadinessProgress`）；进度页那一步是真 `NavigationLink`。
    @MainActor
    func testVolunteerTrainingIsReachableFromTheBlockedSliderThroughReadinessProgress() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true
        )

        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 15), "Volunteer first screen should render")

        let progressEntry = app.buttons["查看接单前进度"].firstMatch
        XCTAssertTrue(
            progressEntry.waitForExistence(timeout: 10),
            "没学完培训时底部胶囊应当通往接单前进度页\n\(app.debugDescription)"
        )
        let spokenReason = progressEntry.value as? String ?? ""
        XCTAssertTrue(
            spokenReason.contains("必修培训"),
            "胶囊要说出接不了单的原因（value=\(spokenReason)）"
        )
        attachScreenshot(named: "volunteer-home-without-training-todo", app: app)

        progressEntry.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerReadinessTitle"].firstMatch.waitForExistence(timeout: 15),
            "点胶囊应当进入接单前进度页\n\(app.debugDescription)"
        )
        let trainingStep = app.descendants(matching: .any)["volunteerReadinessStep.training"].firstMatch
        XCTAssertTrue(
            scrollElementIntoView(trainingStep, app: app),
            "进度页要列出培训这一步\n\(app.debugDescription)"
        )
        attachScreenshot(named: "volunteer-readiness-progress-training-step", app: app)

        trainingStep.tap()
        XCTAssertTrue(
            app.navigationBars[Self.volunteerTrainingTitle].waitForExistence(timeout: 8),
            "培训一步应当一下打开「\(Self.volunteerTrainingTitle)」\n\(app.debugDescription)"
        )
    }

    @MainActor
    func testVolunteerHomeRemainsInteractiveWhileDispatchRequestNeverReturns() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            hangHomeRequests: true,
            homeLoadTimeout: 8
        )

        // 首屏与派单摘要是两条独立的加载：摘要挂住时，身份行、影响力区和三个去处
        // 都必须照常可用 —— 改版前守的是「面板仍可拖动」，同一条约束换了个载体。
        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 12), "First screen must render while the dispatch request hangs")

        // 底部那排「记录 / 成就 / 设置」在 2026-09-14 改版里被吸收进首屏：
        // 记录 = 最近陪跑「全部 ›」，成就 = 徽章「全部 N 枚 ›」，设置 = 右上角齿轮。
        // 三个去处一个没少，所以这条用例守的东西没变，只是入口换了位置。
        //
        // XCUITest 是黑盒，进不了 app 的类型 —— 导航栏标题只能抄一份。
        // 抄错的方向是安全的：生产改了文案而这里没跟，断言会红不会绿。
        let recordsButton = app.buttons["我的陪跑记录"].firstMatch
        let recognitionButton = app.buttons["查看服务成就"].firstMatch
        let settingsButton = app.buttons["设置"].firstMatch

        // 🔴 `ScrollView` 屏幕外的子视图**照样** `isHittable == true`，而触点会被钳到
        // 最上层的控件上（`List` 是压根不渲染，两种坑不一样）。所以点之前必须
        // `scrollElementIntoView`，不能只判 `isHittable`（记忆 `snapshot-timeout-means-a-system-app-took-over`）。
        XCTAssertTrue(scrollElementIntoView(settingsButton, app: app), "齿轮入口应当可达")
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        popNavigationBar(app, title: "设置")

        XCTAssertTrue(scrollElementIntoView(recognitionButton, app: app), "徽章区「全部 ›」应当可达")
        recognitionButton.tap()
        XCTAssertTrue(app.navigationBars["服务成就"].waitForExistence(timeout: 5))
        popNavigationBar(app, title: "服务成就")

        XCTAssertTrue(scrollElementIntoView(recordsButton, app: app), "最近陪跑「全部 ›」应当可达")
        recordsButton.tap()
        XCTAssertTrue(app.navigationBars["陪跑记录"].waitForExistence(timeout: 5))
    }
}
