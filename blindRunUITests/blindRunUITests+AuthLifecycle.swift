import XCTest

extension blindRunUITests {
    @MainActor
    func testAuthLifecycleRolelessRestoreRoutesToRoleSelection() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "roleless-token",
            activeRole: nil,
            emptyMockOrders: true
        )

        XCTAssertTrue(
            app.buttons["我是盲人跑者，预约陪跑员陪我跑步"].firstMatch.waitForExistence(timeout: 10),
            "Valid role-less session should route to role selection"
        )
        XCTAssertFalse(app.staticTexts["正在验证登录状态"].exists)
    }

    /// 服务端登出失败也照样退回登录页（#391 起，契约 blind-run-backend#669：无论成败都清本地会话）。
    /// 此前这里弹「服务端退出失败」让用户在重试 / 仅退出本机之间选 —— 那个弹窗已删。
    @MainActor
    func testAuthLifecycleLogoutFailureStillSignsOutLocally() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "logout-failure-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            mockLogoutFailure: true
        )
        openBlindAccount(app)
        let logoutButton = app.buttons["退出登录"].firstMatch
        XCTAssertTrue(scrollUntilExists(logoutButton, app: app), "设置页滚到底也没有「退出登录」")
        XCTAssertTrue(scrollElementIntoView(logoutButton, app: app), "「退出登录」滚不出求助条")
        logoutButton.tap()
        app.buttons["确认退出"].tap()

        XCTAssertTrue(app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts["服务端退出失败"].exists)
    }

    /// 🔴 退出登录 / 删除账户进行中那层进度遮罩盖住的整个根视图，必须退出无障碍树；
    /// 状态结束后必须回来。
    ///
    /// 遮罩是自定义 overlay（`SessionLifecycleStatusModifier`），不像系统 sheet 白送 inert。
    /// 背后是 `TabView`（UIKit 侧 `UITabBarController`）加 push 出来的设置页 ——
    /// SwiftUI 的 `.accessibilityHidden` 跨不过那道平台边界（记忆
    /// `hide-uikit-hosted-tree-from-accessibility`），所以断言要同时打在
    /// push 页里的按钮和 UIKit 标签栏上，只查一个会放过半个修复。
    @MainActor
    func testSessionLifecycleOverlayHidesTheScreenBehindItFromAccessibility() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "logout-failure-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            mockLogoutFailure: true,
            slowSessionEndSeconds: 8
        )
        assertLogoutOverlayHidesTheScreenBehindIt(app)
    }

    /// 同一个 modifier 挂在根上，但志愿者端的退出登录在另一份视图（账户页 `VolunteerAccountView`），
    /// 背后的标签栏容器也是另一个（`VolunteerTabView`）—— 不单独跑一遍就只是「推断」两端一样。
    @MainActor
    func testSessionLifecycleOverlayHidesTheVolunteerScreenBehindItFromAccessibility() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "logout-failure-token",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            emptyMockOrders: true,
            mockLogoutFailure: true,
            slowSessionEndSeconds: 8
        )
        assertLogoutOverlayHidesTheScreenBehindIt(app, throughAccountPage: true)
    }

    /// 删除账户走同一层遮罩（`accountDeletionState == .inProgress`）。mock 删除成功后直接回登录页，
    /// 所以「收起后」断的是登录页的手机号输入框在树里 —— 遮罩收起时 hider 必须放开新挂上的容器。
    @MainActor
    func testSessionLifecycleOverlayHidesTheScreenBehindItDuringAccountDeletion() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "mock_jwt_token_for_testing",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true,
            slowSessionEndSeconds: 8
        )
        openBlindAccount(app)
        let deleteButton = app.buttons["删除账户"].firstMatch
        // #711 起在账户页：页面藏了标签栏、一屏放得下，滚动辅助函数按 112pt 常驻栏判会误报，直接判可点。
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5) && deleteButton.isHittable, "账户页的「删除账户」点不到\n\(app.debugDescription)")
        deleteButton.tap()
        let proceed = app.buttons["继续删除账户"].firstMatch
        XCTAssertTrue(proceed.waitForExistence(timeout: 5), "删除账户应当先弹一次确认\n\(app.debugDescription)")
        proceed.tap()
        let finalConfirm = app.buttons["永久删除账户"].firstMatch
        XCTAssertTrue(finalConfirm.waitForExistence(timeout: 8), "预检通过后应当弹最终确认\n\(app.debugDescription)")
        finalConfirm.tap()

        assertSessionOverlayIsUpAndHidesTheScreenBehindIt(app, backgroundProbe: deleteButton)

        XCTAssertTrue(
            app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch.waitForExistence(timeout: 15),
            "删除完成回到登录页后，登录页必须在无障碍树里\n\(app.debugDescription)"
        )
    }

    /// 从设置页触发退出登录（慢退出 + 失败），断言遮罩期间背景不在树里、结束后登录页在树里。
    ///
    /// #391 起服务端登出失败也照样清本地会话（契约 blind-run-backend#669），所以遮罩收起后到的是登录页，
    /// 不再是「失败弹窗 → 取消 → 回到设置页」—— 收起后要验的是 hider 放开了新挂上的登录页。
    private func assertLogoutOverlayHidesTheScreenBehindIt(_ app: XCUIApplication, throughAccountPage: Bool = false) {
        openSettings(app)
        if throughAccountPage { app.openVolunteerAccountPage() } else { app.openBlindAccountPage() } // 两端的退出登录都在账户页（#700 / #711）
        let logoutButton = app.buttons["退出登录"].firstMatch
        XCTAssertTrue(scrollUntilExists(logoutButton, app: app), "设置页滚到底也没有「退出登录」")
        XCTAssertTrue(scrollElementIntoView(logoutButton, app: app), "「退出登录」滚不出求助条")
        logoutButton.tap()
        let confirm = app.buttons["确认退出"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        assertSessionOverlayIsUpAndHidesTheScreenBehindIt(app, backgroundProbe: logoutButton)

        // 慢退出到点后走失败分支（`mockLogoutFailure`）→ 照样清本地会话 → 登录页。
        XCTAssertTrue(
            app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch.waitForExistence(timeout: 15),
            "退出完成回到登录页后，登录页必须在无障碍树里\n\(app.debugDescription)"
        )
    }

    /// 进度提示在树里，设置页上的某个按钮（push 页，在 NavigationStack 里）与 UIKit 标签栏都不在。
    private func assertSessionOverlayIsUpAndHidesTheScreenBehindIt(
        _ app: XCUIApplication,
        backgroundProbe: XCUIElement
    ) {
        XCTAssertTrue(
            app.descendants(matching: .any)["请求正在处理中，请稍候"].firstMatch.waitForExistence(timeout: 3),
            "进度提示应当在树里\n\(app.debugDescription)"
        )
        XCTAssertTrue(
            waitForElementToDisappear(backgroundProbe, timeout: 2),
            "遮罩盖住的设置页不该还留在无障碍树里\n\(app.debugDescription)"
        )
        XCTAssertFalse(
            app.tabBars.firstMatch.exists,
            "遮罩盖住的标签栏不该还留在无障碍树里\n\(app.debugDescription)"
        )
    }

    @MainActor
    func testAuthLifecycleEveryLogoutSurfaceRequiresConfirmation() throws {
        let blindProfile = launchApp(
            apiEnvironment: "mock",
            accessToken: "blind-profile-token",
            activeRole: "blind_runner",
            emptyMockOrders: true
        )
        // 盲人侧没有「直接暴露退出登录」的界面：首页和引导流都只放设置入口，
        // 退出登录统一收在 BlindRunnerSettingsView（见 BlindRunnerOnboardingView 的容器注释）。
        openBlindAccount(blindProfile)
        assertLogoutRequiresConfirmation(blindProfile)

        // 志愿者资料页（`VolunteerModule` 的 header）是除设置页外唯一直接摆出退出登录的界面，
        // 只有未注册的志愿者才会停在这一页——不加 `unregisteredVolunteer` 的话 Mock 会喂一份
        // 已完成注册的资料，根路由直接进首页，这一档就退化成和下面设置页那档重复。
        let volunteerProfile = launchApp(
            apiEnvironment: "mock",
            accessToken: "volunteer-profile-token",
            activeRole: "volunteer",
            unregisteredVolunteer: true,
            emptyMockOrders: true
        )
        assertLogoutRequiresConfirmation(volunteerProfile)

        let volunteerSettings = launchApp(
            apiEnvironment: "mock",
            accessToken: "volunteer-settings-token",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            emptyMockOrders: true
        )
        openSettings(volunteerSettings)
        volunteerSettings.openVolunteerAccountPage()
        assertLogoutRequiresConfirmation(volunteerSettings)
    }

    @MainActor
    func testAuthLifecycleBlindAccountDeletionIsTwoStageAndCompletesOnce() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "blind-delete-token",
            activeRole: "blind_runner",
            preseedBlindProfile: true,
            emptyMockOrders: true
        )
        openBlindAccount(app)
        let deleteButton = app.buttons["删除账户"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteButton.isEnabled)
        // 不滑到底，「删除账户」可能在标签栏后面，触点落不到它上面。
        app.swipeUp()
        app.swipeUp()
        deleteButton.tap()

        let initialAlert = app.alerts["确认删除账户"].firstMatch
        XCTAssertTrue(initialAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(initialAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "仍需再次确认")).firstMatch.exists)
        app.buttons["继续删除账户"].tap()

        let finalAlert = app.alerts["最终确认删除账户"].firstMatch
        XCTAssertTrue(finalAlert.waitForExistence(timeout: 8))
        // 文案内容**不在这里断**。它的主是单测 `testAccountDeletionCopyStatesWhatIsDeletedAndWhatIsKept`
        // （`blindRunTests/AuthSessionLifecycleTests.swift`），那条进程内直接对
        // `AccountDeletionViewModel.finalConfirmationMessage(for:)` 断言，拿得到真源。
        // 这里再抄一份字面量只会周期性漂移 —— `9f9cede` 把「会失效」改成「立即失效」，
        // 单测跟着改了，抄在这儿的那份没有，于是这条用例红了 7 天。
        // UI 用例守的是流程：两段式弹窗、且只提交一次。
        let finalButton = app.buttons["永久删除账户"].firstMatch
        XCTAssertTrue(finalButton.exists)
        finalButton.tap()
        XCTAssertTrue(
            finalButton.waitForNonExistence(timeout: 2),
            "Final destructive action must disappear promptly to prevent duplicate submission"
        )
        XCTAssertTrue(app.textFields["手机号输入框，请输入 11 位手机号"].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testAuthLifecycleVolunteerDeletionRouteAndActiveOrderBlock() throws {
        let app = launchApp(
            apiEnvironment: "mock",
            accessToken: "volunteer-delete-token",
            activeRole: "volunteer",
            preseedVolunteerProfile: true,
            preseedVolunteerActiveOrder: true
        )
        // 预置了在途订单 ⇒ 冷启动直接进服务页（§4.1），而那一页藏了标签栏（设计交付 v3 §4.2
        // 总表：订单页底部是「求助与安全」不是标签栏）。要走「我的」tab 得先退回来。
        XCTAssertTrue(
            waitForVolunteerOrderPage(app, timeout: 25),
            "有在途订单时冷启动没有直接进服务页"
        )
        leaveVolunteerOrderPage(app)

        // ⚠️ 这一条自 2026-09-16（`d8b6307`，盲人端加标签栏）起一直是红的：`openSettings`
        // 那次改成走「我的」tab，而**志愿者端当时根本没有标签栏**，于是它卡在第一句断言上。
        // 本轮给志愿者端补上标签栏之后它才重新跑得通 —— 命中记忆
        // `merged-prs-whose-tests-never-ran`（CI 跑不了 XCTest，编译绿不代表用例跑过）。
        openSettings(app)
        app.openVolunteerAccountPage() // #700 起「删除账户」在账户页（「我的」→ 头像卡）
        let deleteAccount = app.buttons["删除账户"].firstMatch
        XCTAssertTrue(
            scrollUntilExists(deleteAccount, app: app),
            "设置页滚到底也没有「删除账户」"
        )
        deleteAccount.tap()
        XCTAssertTrue(app.alerts["确认删除账户"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["继续删除账户"].tap()

        // 拦截必须**自己弹出来**，而不是往设置页 `List` 末尾追加一行。
        // 这条断言原本找的就是那一行 `StaticText`，从 `089960e`（#76，设置页加了三个激励入口）
        // 起一直红：那一行被挤到第二屏，而 `List` 不渲染屏幕外的行 —— 屏幕上一个字都没多出来。
        // 拦截本身一直是好的（失败快照里没有「最终确认删除账户」弹窗），坏的是它没有可见的落点。
        // 文案内容不在这里断，主在单测 `testAccountDeletionPreflightSpeaksActiveOrderBlock`。
        let blocked = app.alerts["无法删除账户"].firstMatch
        XCTAssertTrue(blocked.waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts["最终确认删除账户"].exists)
        blocked.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["退出登录"].exists, "Blocked deletion must preserve the signed-in settings state")
    }
}
