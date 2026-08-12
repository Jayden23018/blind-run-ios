//
//  AccessibilityAuditTests.swift
//  blindRunUITests
//
//  这是一个盲人 App。AGENTS.md 第 8 节和 skill `aidrun-a11y-voice` 对 VoiceOver、
//  64pt 触达、「重复当前状态」按钮有硬性要求，但此前**没有一条自动检查**。
//
//  `performAccessibilityAudit`（Xcode 15+）做的是 Accessibility Inspector 那套静态检查：
//  缺 label、文本被截断、对比度不足、不支持 Dynamic Type。它不驱动 VoiceOver，
//  所以「遍历顺序」「重复当前状态存在」这类语义要求仍需单独断言 —— 见本文件后半。
//
//  只能真机跑（高德无 arm64-sim slice，模拟器通道永久不可用）：
//    scripts/device-test.sh -only-testing:blindRunUITests/AccessibilityAuditTests
//

import XCTest

final class AccessibilityAuditTests: XCTestCase {

    override func setUpWithError() throws {
        // 默认 false 会在第一个问题就停下，那样一次只能看见一条。
        // 无障碍审计的价值恰恰在于一次列全，所以这里反过来。
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - 静态审计

    @MainActor
    func testBlindRunnerHomePassesAccessibilityAudit() throws {
        // 内联 guard 而不是抽成 helper：只有内联的 `#available` 才能让编译器
        // 在后续语句里窄化可用性，helper 里 throw XCTSkip 编译不过。
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20),
            "盲人首页没起来，后面的审计结果没有意义"
        )
        try audit(app)
    }

    @MainActor
    func testBlindBookingPassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()

        // 落在语音态还是表单态由麦克风授权决定，两个都算「下单页起来了」。
        // 此前这里只等 `blindBookingVoiceOrderButton`（表单态才有），授权成功的设备上会误报「页面没起来」。
        XCTAssertTrue(
            waitForBookingScreen(app),
            "下单页没起来"
        )
        try audit(app)
    }

    // MARK: - 语音态与表单态互斥

    /// 语音在跑的时候，屏幕上**一个表单控件都不许有**。
    ///
    /// 这一页此前把语音区和四步表单堆在同一个滚动视图里，进来面对的是十几条 StaticText
    /// 加两个文本框。用户 2026-08-08 的原话：「表单的形式不应该给盲人用」。
    ///
    /// 用 `AIDRUN_UI_TEST_FORCE_VOICE_STAGE` 把向导按在运行态 —— 真机跑 UI 测试拿不到语音识别
    /// 授权，不加这个接缝，语音态在自动化里永远不出现，这条约束就只能靠人肉手测。
    @MainActor
    func testVoiceStageRendersNoFormControls() throws {
        let app = launchBlindHome(forcingVoiceStage: true)
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()

        let surface = app.descendants(matching: .any)["blindBookingFinishSpeakingSurface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 20), "语音态没起来，后面的断言没有意义")

        // 逃生口必须在。它在 `safeAreaInset` 的底栏里，不被内容区盖住。
        XCTAssertTrue(
            app.descendants(matching: .any)["blindBookingStopVoiceButton"].firstMatch.exists,
            "语音态必须留着「改用表单」这个逃生口"
        )

        // 表单那一套一个都不许出现。
        XCTAssertFalse(app.textFields["搜索出发地点"].firstMatch.exists, "语音态不许渲染地点搜索框")
        XCTAssertFalse(app.textFields["出发地点补充描述"].firstMatch.exists, "语音态不许渲染补充描述框")
        XCTAssertFalse(
            app.descendants(matching: .any)["blindBookingAuxiliaryMap"].firstMatch.exists,
            "语音态不许渲染辅助地图"
        )
        XCTAssertFalse(app.buttons["搜索地点"].firstMatch.exists, "语音态不许渲染搜索按钮")
        XCTAssertFalse(
            app.descendants(matching: .any)["blindBookingVoiceOrderButton"].firstMatch.exists,
            "「用语音重新说一次」是表单态的按钮，语音已经在跑时它是噪音"
        )
        XCTAssertFalse(
            app.staticTexts["按步骤确认出发地点、预约时间和选填需求，最后再提交。"].firstMatch.exists,
            "语音态不许渲染表单的说明文字"
        )
    }

    // MARK: - 静态审计抓不到的语义要求

    /// `AGENTS.md`：盲人端关键主按钮高度 ≥ 64pt。
    /// audit 查不到这个 —— 一个 20pt 高但有完整 label 的按钮能通过全部静态检查。
    @MainActor
    func testBlindRunnerPrimaryButtonMeetsMinimumTouchTarget() throws {
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))

        XCTAssertGreaterThanOrEqual(
            start.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "盲人端主按钮实测 \(start.frame.height)pt，低于硬性要求的 \(Self.minimumBlindPrimaryButtonHeight)pt"
        )
    }

    /// `AGENTS.md`：每个关键盲人页面必须有「重复当前状态」。
    /// 它不冗余 —— 系统 Speak Screen 读不到一次性的 announcement，没有这个按钮，
    /// 盲人错过一次播报就再也拿不回来。
    @MainActor
    func testBlindRunnerHomeOffersRepeatCurrentStatus() throws {
        let app = launchBlindHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20)
        )

        let repeatControl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "重复当前状态"))
            .firstMatch
        XCTAssertTrue(
            repeatControl.waitForExistence(timeout: 10),
            "盲人首页缺少「重复当前状态」。可以降视觉权重，但不能删。"
        )
    }

    /// 主按钮必须**看起来**就是主按钮，不只是够得着。
    ///
    /// 上一条只查 64pt，而 64pt 正是它此前和「重复当前状态」同高时的值 —— 那一版全绿，
    /// 用户看到的却是「约跑的按钮还是小」。对标 Be My Eyes 的 `Call a volunteer` 占内容区约 75%
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1）。
    ///
    /// 阈值取窗口高度的 25% 而不是 55%：内容区在窗口里还要扣掉地图、SOS 条与次级按钮，
    /// 这里要抓的是「有没有被缩回次级按钮那一档」，不是精确复刻某个比例。
    @MainActor
    func testBlindRunnerPrimaryButtonDominatesTheScreen() throws {
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))

        let windowHeight = app.windows.firstMatch.frame.height
        XCTAssertGreaterThan(windowHeight, 0, "拿不到窗口高度，这条断言等于没跑")

        let share = start.frame.height / windowHeight
        XCTAssertGreaterThanOrEqual(
            share,
            Self.minimumBlindPrimaryButtonScreenShare,
            """
            主按钮实测 \(start.frame.height)pt，只占屏高 \(Int(share * 100))%，\
            低于 \(Int(Self.minimumBlindPrimaryButtonScreenShare * 100))%。\
            低视力用户找不到它。要改这个阈值先看对标文档 §1。
            """
        )
    }


    // MARK: - 首屏可达性

    /// 无订单首页不得出现「问一句」，且「重复当前状态」必须**不滚动**就够得着。
    ///
    /// 两笔改动叠在一起造出过这个缺陷：`925e78c` 把「开始约跑」放大到 280pt，
    /// 当天晚些的 `03f3e40` 又在它后面无条件追加了「问一句」，于是 64 + 24 的一行把
    /// 「重复当前状态」整个顶进底部 SOS 条后面（那条用 `.ultraThinMaterial`，看着就是被挡住）。
    ///
    /// 后半句断言才是真正拦根因的那一条 —— 它对「谁又往这一列追加了一行」一律报警，
    /// 不只认「问一句」这一个名字。`blindRunUITests.swift:97` 有一条同源断言，
    /// 但那条只在「请求挂起」的加载态里跑，正常首页没人守。
    @MainActor
    func testBlindHomeWithoutAnOrderHidesAskQuestionAndKeepsRepeatStatusReachable() throws {
        let app = launchBlindHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20),
            "盲人首页没起来，后面的断言没有意义"
        )

        XCTAssertFalse(
            app.descendants(matching: .any)["blindRunnerHomeAskQuestionButton"].firstMatch.exists,
            """
            无订单首页出现了「问一句」。它在这一态下对四个意图统一回「当前没有进行中的预约」\
            （VoiceStatusQuery.swift:109），按下去只换来 header 已经念过的同一句话。
            """
        )

        let repeatControl = app.buttons["重复当前状态"].firstMatch
        XCTAssertTrue(repeatControl.waitForExistence(timeout: 10), "盲人首页缺少「重复当前状态」")
        XCTAssertTrue(
            repeatControl.isHittable,
            """
            「重复当前状态」要滚动才够得着 —— 它被底部 SOS 条盖住了。\
            首页在「开始约跑」和它之间又多了一行的话，先想清楚这一行值不值得把它顶下去。
            """
        )
    }

    /// 反向断言：有进行中订单时「问一句」必须在。
    /// 防止把上一条用「整个删掉」来满足 —— 那是这个能力真正有用的唯一状态。
    @MainActor
    func testBlindHomeWithAnActiveOrderOffersAskQuestion() throws {
        let app = launchBlindHome(emptyOrders: false)
        XCTAssertTrue(
            app.buttons["查看当前订单"].firstMatch.waitForExistence(timeout: 20),
            "有订单的盲人首页没起来，后面的断言没有意义"
        )

        let ask = app.descendants(matching: .any)["blindRunnerHomeAskQuestionButton"].firstMatch
        XCTAssertTrue(
            ask.waitForExistence(timeout: 10),
            "有进行中订单时首页必须能「问一句」—— 这是它唯一有答案可给的状态"
        )
        XCTAssertTrue(ask.isHittable, "「问一句」存在但够不着，等于没有")
    }

    /// 后端的 `ORDER_CANCELLATION_WARNING` 正文逐字是「您的订单即将因长时间无人接单被取消，
    /// **点击继续等待可延长**」。这条用例钉的就是那句话响起时，屏幕上真的有这个控件、
    /// 而且**不用滚动**就够得着 —— 播报里让人点一个只存在于后端文案里的按钮，
    /// 对看不见屏幕的人是纯粹的死路。
    ///
    /// 播报内容本身（「重复当前状态」要念到这个动作）由单测
    /// `KeepWaitingTests.testRepeatStatusMentionsKeepWaitingWhileWaiting` 断言 ——
    /// UI 测试是黑盒，读不到 TTS 文本，在这里断言只能断言个寂寞。
    @MainActor
    func testBlindOrderStatusOffersKeepWaitingWhileWaitingForAMatch() throws {
        let app = launchBlindHome(emptyOrders: false)
        let currentOrder = app.buttons["查看当前订单"].firstMatch
        XCTAssertTrue(
            currentOrder.waitForExistence(timeout: 20),
            "有订单的盲人首页没起来，后面的断言没有意义"
        )
        currentOrder.tap()

        // 种子订单是 PENDING_MATCH（`MockAPIClient.seedDemoData`），正是可延长的状态。
        let keepWaiting = app.descendants(matching: .any)["blindOrderStatusKeepWaitingButton"].firstMatch
        XCTAssertTrue(
            keepWaiting.waitForExistence(timeout: 15),
            "PENDING_MATCH 的订单状态页没有「继续等待」—— 后端预警文案让用户点的正是它"
        )
        XCTAssertTrue(keepWaiting.isHittable, "「继续等待」存在但够不着，等于没有")
        XCTAssertGreaterThanOrEqual(
            keepWaiting.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "盲人端主动作触达高度不得低于 64pt"
        )
        XCTAssertEqual(keepWaiting.label, "继续等待", "读屏念出来的必须就是这四个字")

        // 幂等且方向是保住订单，所以**不弹二次确认**（取消订单那条才弹）。
        keepWaiting.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertFalse(
            confirmation.waitForExistence(timeout: 3),
            "「继续等待」不该有二次确认：多一轮确认对读屏用户是实打实的十几秒"
        )
    }

    // MARK: - Helpers

    private static let minimumBlindPrimaryButtonHeight: CGFloat = 64
    private static let minimumBlindPrimaryButtonScreenShare: CGFloat = 0.25

    /// 低版本设备上明确 skip 而不是静默通过 —— 「没跑」和「跑过了」必须可区分。
    @available(iOS 17.0, *)
    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(
            for: [.contrast, .dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription]
        ) { issue in
            // 高德地图图层无法承载有意义的 label，且它已被显式降权为辅助内容
            // （视觉可以铺满，读屏遍历顺序必须操作优先）。这是唯一的白名单项 ——
            // 每加一条都要写清为什么，否则白名单会慢慢把审计架空。
            let identifier = issue.element?.identifier ?? ""
            return identifier == "blindRunnerHomeAuxiliaryMap" || identifier == "blindBookingAuxiliaryMap"
        }
    }

    /// 下单页起来了没有 —— 语音态和表单态各有一个标志元素，命中任一即可。
    @MainActor
    private func waitForBookingScreen(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let voiceSurface = app.descendants(matching: .any)["blindBookingFinishSpeakingSurface"].firstMatch
        let formButton = app.descendants(matching: .any)["blindBookingVoiceOrderButton"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if voiceSurface.exists || formButton.exists { return true }
            _ = voiceSurface.waitForExistence(timeout: 1)
        }
        return false
    }

    /// - Parameter emptyOrders: `true` 走无订单首页（默认，绝大多数用例要的就是这一态）。
    ///   传 `false` 就不设 `AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS`，`MockAPIClient` 会 seed 一张
    ///   `PENDING_MATCH` 订单（`MockAPIClient.swift:1924-1933`）—— 不需要另造 mock。
    @MainActor
    private func launchBlindHome(
        forcingVoiceStage: Bool = false,
        emptyOrders: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = "mock"
        app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = "blind_runner"
        app.launchEnvironment["AIDRUN_UI_TEST_ACCESS_TOKEN"] = "mock_jwt_token_for_testing"
        // 注意是 PRESEEDED 不是 PRESEED —— 与 blindRunUITests.launchApp 保持一致，
        // 写错不会报错，只会静默进到「资料未填」分支，然后审计的是错的那一页。
        app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE"] = "1"
        if emptyOrders {
            app.launchEnvironment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] = "1"
        }
        app.launchEnvironment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"
        if forcingVoiceStage {
            app.launchEnvironment["AIDRUN_UI_TEST_FORCE_VOICE_STAGE"] = "1"
        }

        addUIInterruptionMonitor(withDescription: "系统权限弹窗") { alert in
            for title in ["允许", "好", "使用App时允许", "OK", "Allow"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        // 触发一次 interruption monitor，否则弹窗要等下一次交互才被处理。
        //
        // **不能用 `app.tap()`** —— 它敲的是屏幕正中，而首页正中现在是「开始约跑」，
        // 一启动就被导航进下单页，然后每条用例都报「找不到 blindRunnerHomeStartBookingButton」，
        // 看起来像首页没起来。改敲顶部地图区：那一层 `allowsHitTesting(false)`，
        // 是这一页唯一保证不会触发任何动作的地方（设置齿轮在右上，dx 0.5 躲得开）。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        return app
    }
}
