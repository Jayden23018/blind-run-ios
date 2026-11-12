import XCTest

extension blindRunUITests {
    @MainActor
    func testMockVolunteerOrderFlowSmoke() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true
        )

        // 有在途订单 ⇒ 打开 App 直接进服务页（设计交付 v3 §4.1 三岔路的第二岔）。
        // 首屏的版式断言要先退回来才做得了 —— 而「退得回来」本身也是那条自动导航的前提：
        // 推进去出不来的话，志愿者在订单走完之前碰不到主页（钉在 `ScheduledOrderTests`）。
        XCTAssertTrue(
            waitForVolunteerOrderPage(app, timeout: 25),
            "有在途订单时冷启动没有直接进服务页"
        )
        leaveVolunteerOrderPage(app)

        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
        XCTAssertTrue(identityRow.waitForExistence(timeout: 12), "Volunteer identity row should be visible below the system status area")
        assertVolunteerTopStatusBlockPosition(identityRow, app: app)
        // 🔴 志愿者端**整个 App 里已经没有这张辅助地图了**（2026-09-15 删，它的
        // `annotations` 恒为 `[]`，唯一信息「我在哪」在派单卡的覆盖范围文字里已有一份）。
        // 这条负断言留着当门卫：谁把它加回首屏，这里会红。
        XCTAssertFalse(
            app.descendants(matching: .any)["volunteerHomeMap"].firstMatch.exists,  // guard:allow stale-ui-test-identifier
            "志愿者辅助地图已删除，不该出现在「我」首屏"
        )

        let currentOrderCard = app.descendants(matching: .any)["volunteerHomeCurrentOrderCard"].firstMatch
        XCTAssertTrue(currentOrderCard.waitForExistence(timeout: 5), "Preseeded active order should appear on the first screen")
        // 🔴 作业区排在影响力区**之前**：带到期动作的东西必须先于「24 次陪跑」被念到。
        XCTAssertGreaterThanOrEqual(currentOrderCard.frame.minY, identityRow.frame.maxY, "Current order should sit directly below the identity row")
        let impactBlock = app.descendants(matching: .any)["volunteerHomeIncentiveCard"].firstMatch
        if impactBlock.waitForExistence(timeout: 10) {
            XCTAssertLessThan(
                currentOrderCard.frame.minY,
                impactBlock.frame.minY,
                "「需要你处理」必须排在影响力区之前 —— 读屏顺序播报，排序就是优先级"
            )
        }

        // 已经退回首页了，这次是真的从卡片点进去 —— 传 0 省掉那 25 秒的等待。
        openCurrentVolunteerService(app, alreadyOpenTimeout: 0)
        assertNoEmergencyAction(app)

        let enRouteLabel = tapVolunteerFlowPrimary(app)
        assertNoEmergencyAction(app)

        tapVolunteerFlowPrimary(app, after: enRouteLabel)
        assertNoEmergencyAction(app)

        // 汇合那一屏（2026-09-17 起也是骨架）：主按钮换成「开始跑步」，且必须给出
        // 「找不到对方」这条出口 —— 到了集合点看不见人，是这一态唯一会发生的麻烦。
        let startButton = app.buttons["volunteerOrderFlowPrimaryButton"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "汇合态没有主按钮，志愿者无法开始跑步")
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerOrderFlowRow-cannotFind"].firstMatch.exists,
            "汇合态必须有「找不到对方」"
        )
        // 按 identifier 取，不按文案：这枚按钮不带 `.isButton` trait（它没有轻点路径，
        // 读屏走自定义动作），`app.buttons[...]` 取不到它。
        let finishControl = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertFalse(finishControl.waitForExistence(timeout: 1), "Arrived order must not allow completing service before IN_PROGRESS")
        startButton.tap()
        XCTAssertTrue(finishControl.waitForExistence(timeout: 8), "In-progress order should expose the long-press finish control")
        // 2026-08-01 起志愿者可以代盲人发起求助（后端已按订单参与方归属事件，不再回推给按按钮的人）。
        // 这里原本断言「志愿者永远看不到求助入口」，那是后端送错人时期的止血，现在反过来验它必须可用。
        assertEmergencyActionIsUsable(app)

        // 结束要按满 2 秒（没有轻点路径）。松手即取消那一半在
        // `testVolunteerFinishesEscortOnlyAfterHoldingLongEnough` 里单独验 ——
        // 这条烟囱用例要先走完出发 / 到达 / 开始三步，沿途任何一条红灯都会把它挡在这之前。
        finishControl.press(forDuration: 2.6)

        // 2026-09-17：结束之后**先落在「已完成」那一屏**（结果 + 两个去处），
        // 轨迹在「查看跑步记录」后面。此前轨迹是直接铺在这里的。
        let runRecordRow = app.descendants(matching: .any)["volunteerOrderFlowRow-runRecord"].firstMatch
        XCTAssertTrue(runRecordRow.waitForExistence(timeout: 10), "结束陪跑后应落在已完成屏")
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerOrderFlowRow-reportIssue"].firstMatch.exists,
            "已完成屏必须留一条「上报问题」—— 陪跑员对此订单的异议只有这一个出口"
        )
        // 🔴 志愿服务时长**不在这一屏**：后端没有按单口径（只有累计的 `totalServiceMinutes`）。
        // 这条负断言是那个决定的看门狗 —— 谁把轨迹耗时换算成「0.7 小时」摆上去，这里会红。
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "志愿服务时长")).firstMatch.exists,
            "已完成屏不得出现「志愿服务时长」"
        )
        runRecordRow.tap()

        let summary = app.descendants(matching: .any)["completedTrackSummary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Completed service should show the reusable track summary")
        XCTAssertTrue(app.staticTexts["本次路线"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["里程"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["时长"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["平均配速"].firstMatch.exists)
        let repeatSummary = app.buttons["completedTrackRepeatSummary"].firstMatch
        XCTAssertTrue(repeatSummary.exists, "Track summary must remain usable without inspecting the map")
        // #383：bordered 按钮外挂 frame 时这里量到 34.7pt，frame 要挂在 label 里才撑得开可点区。
        XCTAssertGreaterThanOrEqual(repeatSummary.frame.height, 64, "「重复当前状态」可点区必须 ≥64pt")
        let routeMap = app.descendants(matching: .any)["completedTrackAuxiliaryMap"].firstMatch
        XCTAssertTrue(routeMap.exists, "The blind track should be available as an auxiliary map")
        XCTAssertLessThan(
            app.staticTexts["本次路线"].firstMatch.frame.minY,
            routeMap.frame.minY,
            "Textual status must precede the auxiliary map"
        )

        // 内嵌那张 220pt 的图看不清整条路线，大屏页才是「跑完看轨迹」的落点。
        // 入口做成独立一行而不是把地图本身变成链接：MAMapView 自己吃掉手势，
        // 包在 NavigationLink 里点不动，读屏用户也对不上焦点。
        let fullScreenLink = app.descendants(matching: .any)["completedTrackFullScreenLink"].firstMatch
        XCTAssertTrue(fullScreenLink.waitForExistence(timeout: 5), "Track summary must offer a full-screen route entry")
        fullScreenLink.tap()

        // D13：陪跑员这条链接进跑后详情，不再进 `OrderRouteReplayView`。
        let detail = app.descendants(matching: .any)["volunteerRunRecordDetail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "陪跑员点「查看跑后详情」应进新的跑后详情页")
        // 回归哨兵：防止旧的 `OrderRouteReplayView` 被接回来（identifier 已不存在，故意留着）。
        XCTAssertFalse(app.descendants(matching: .any)["orderRouteReplay"].firstMatch.exists)  // guard:allow stale-ui-test-identifier
        XCTAssertTrue(
            app.descendants(matching: .any)["runRecordDistance"].firstMatch.waitForExistence(timeout: 10),
            "跑后详情要有距离，不能只有地图"
        )
    }

    /// 跑步中那枚求助盾牌必须**点得到**（#217）。
    ///
    /// 单独成一条，不再只挂在烟囱用例的中段：那条长链前面任何一步红了（#193 让它死在开头 9 天，
    /// 之后又卡在首页身份栏的位置断言），这一句就不执行。盾牌被三数字卡盖住的缺陷就是这样藏住的 ——
    /// 09-16 在 `main@fdc6579` 上其实复现过同一签名，下面那条用例的注释还记着，但只是被绕开了。
    /// 直接预置 `IN_PROGRESS`，不走出发 → 到达 → 开始那条长路。
    @MainActor
    func testVolunteerRunningPageKeepsTheSOSButtonReachable() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            seedOrderStatus: "IN_PROGRESS"
        )

        // 横竖屏各验一次：放进内容区的任何修法都会在横屏（高 402pt）和三数字卡、底部面板抢空间 ——
        // 试过的 VStack 修法就是竖屏绿、横屏把面板压到 0，「长按结束」被挤出屏幕。
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        openCurrentVolunteerService(app, requirePhone: false)
        let finishControl = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertTrue(finishControl.waitForExistence(timeout: 15), "没进到跑步中")

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            assertEmergencyActionIsUsable(app)
            // 不断言 finishControl.exists：被挤出屏幕时它照样 exists。旧页面那次回归的表现是面板高度 0。
            // #218 之后结束按钮常驻在底部安全区里，横屏也必须是完整的 64pt（63.5 留浮点噪声的余量），
            // 而且点得到 —— 旧页面横屏只剩 60pt 的滚动区。
            XCTAssertGreaterThanOrEqual(
                finishControl.frame.height, 63.5,
                "\(orientation.rawValue) 方向下「长按结束」只有 \(finishControl.frame.height)pt"
            )
            XCTAssertTrue(finishControl.isHittable, "\(orientation.rawValue) 方向下「长按结束」点不到")
            // 回归哨兵：跑步中没有取消入口（#962，负责人 11-12「整个删掉」），底部只留长按结束。identifier 已不存在，故意留着。
            XCTAssertFalse(app.descendants(matching: .any)["volunteerRunningCancel"].firstMatch.exists)  // guard:allow stale-ui-test-identifier
        }
    }

    /// 长按 2 秒结束陪跑的**行为**那一半：松手即取消 / 按满才结束。
    ///
    /// 走**指针路径**（`press(forDuration:)` 注入的是物理触摸），形状那一半在
    /// `AccessibilityAuditTests.testVolunteerFinishEscortControlIsReachableAndBigEnough`。
    /// 两条路最终调的是同一个 `VolunteerFinishLongPressButton.fire()`。
    /// ⛔ 不要在这里改成「tap 一下再断言结束了」：`tap()` 不经过 accessibility action，
    /// 而这枚控件没有轻点路径 —— 那样写必红，且红得毫无信息量。
    ///
    /// 直接把订单预置在 `IN_PROGRESS`，不走烟囱用例那条出发 → 到达 → 开始的长路：
    /// 那条路上曾有一条与本功能无关的红灯（求助悬浮键 `isHittable == false`，
    /// 2026-09-16 在 `main@fdc6579` 上复现过同一签名；真缺陷，见 #217），挂在它后面等于这一条永远跑不到。
    @MainActor
    func testVolunteerFinishesEscortOnlyAfterHoldingLongEnough() throws {
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
        XCTAssertTrue(finishControl.waitForExistence(timeout: 15), "服务进行中必须有结束入口")

        // 「结束了没有」的判据换成已完成屏那一行（2026-09-17 起轨迹不再直接铺在结束后那一屏，
        // 而是退到「查看跑步记录」后面）。这一行只在 `COMPLETED` 出现，仍然是个干净的信号。
        let completedScreen = app.descendants(matching: .any)["volunteerOrderFlowRow-runRecord"].firstMatch
        // 两个时长写死在这里而不是引用 App 侧常量（UI 测试是另一个进程，`@testable import`
        // 够不着）：阈值本身由 `VolunteerFinishLongPressTests` 钉住，这里只要一个明显不足、
        // 一个明显足够。
        finishControl.press(forDuration: 0.6)
        XCTAssertFalse(
            completedScreen.waitForExistence(timeout: 3),
            "松手即取消：不足 2 秒就结束了陪跑，等于误触一次不可撤销的操作"
        )
        XCTAssertTrue(finishControl.exists, "取消一次长按之后，结束入口必须还在原地")

        finishControl.press(forDuration: 2.6)
        XCTAssertTrue(
            completedScreen.waitForExistence(timeout: 10),
            "按满 2 秒必须真的结束 —— 否则这枚按钮对不开读屏的人就是个按不动的东西"
        )
    }

    @MainActor
    func testVolunteerServiceRemainsInteractiveWhenTransitionConfirmationNeverReturns() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerAvailable: true,
            preseedVolunteerActiveOrder: true,
            hangTransitionConfirmation: true,
            homeLoadTimeout: 3
        )

        openCurrentVolunteerService(app, requirePhone: false)
        tapVolunteerFlowPrimary(app)

        XCTAssertTrue(
            app.staticTexts["已提交，正在确认状态。"].waitForExistence(timeout: 3),
            "POST completion must release the action spinner before confirmation GET completes"
        )
        // 🔴 这一条是本用例的核心：同一次流转不许被提交两次。
        // 2026-09-17 换成四步骨架时它**第一版就漏了** —— 骨架的主按钮没有接上
        // `transitionsDisabled`，志愿者可以连点两下「我出发了」。是这行编译不过才暴露的。
        XCTAssertFalse(
            app.buttons["volunteerOrderFlowPrimaryButton"].firstMatch.isEnabled,
            "The same transition must not be submitted twice"
        )

        // 🚩 `PENDING_ACCEPT` 已从地图 + 底部面板换成四步骨架，所以这里不再断言地图底图、
        // 「取消订单」与「导航到出发地点」那三个旧控件。**被测行为没变**：确认挂住时界面
        // 不能变成模态，其余入口照样点得到。骨架上对应的是「我去不了」那一行与返回键。
        // v7（#945）起「我去不了」收进顶栏「···」：入口就是那枚「···」。
        let moreMenu = app.buttons["volunteerOrderNavMoreMenu"].firstMatch
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(moreMenu.isHittable, "Cancellation entry must remain locally interactive")
        // v2 页面藏了系统导航栏，返回键在页面自带的导航栏上。
        XCTAssertTrue(app.buttons["返回"].firstMatch.isHittable, "Back navigation must remain usable")

        XCTAssertTrue(
            app.staticTexts["状态还没确认，请稍后点「重新确认状态」。"]
                .waitForExistence(timeout: 5),
            "A permanently suspended confirmation must become a delayed, nonmodal state"
        )
        XCTAssertTrue(app.buttons["重新确认状态"].firstMatch.isHittable)
    }
}
