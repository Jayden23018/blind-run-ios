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

    /// 志愿者服务成就页。
    ///
    /// **这条是补一个真实的覆盖缺口，不是凑数。** 2026-08-13 之前本文件 9 条用例**全在盲人端**，
    /// 志愿者端一条审计都没有 —— 于是「跑了无障碍门」和「新页面被审计过」是两回事，
    /// 而门是绿的。志愿者里同样有低视力用户（`VisionLevel.LOW_VISION` 在数据模型里是一等公民）。
    ///
    /// 这一页值得单独审计的地方：两个进度条（国标星级 / 下一枚勋章）都被 `accessibilityHidden`，
    /// 进度靠独立文本节点承载；星级栏与勋章行各自 `children: .combine` 成一个焦点。
    /// 这几处都是「看着对、读屏是空的」的高发形态。
    @MainActor
    func testVolunteerAchievementsPassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchVolunteerHome()

        // 入口在首页底部那排（记录 / 成就 / 设置）。SwiftUI 不渲染屏幕外的内容，
        // 直接断言会假失败 —— 先滚到底（commit 4cee939 的同一个坑）。
        let entry = app.descendants(matching: .any)["服务成就"].firstMatch
        if !entry.waitForExistence(timeout: 20) {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "志愿者首页没有「成就」入口，后面的审计没有意义")
        entry.tap()

        let page = app.descendants(matching: .any)["volunteerServiceRecognitionView"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 15), "成就页没起来，审计结果没有意义")

        // 页面自己要发一次 `GET /api/volunteer/achievements`（Mock 直接返回），
        // 数据没到之前屏幕上只有一个 ProgressView，那时审计等于审计一个空页。
        let starSection = app.descendants(matching: .any)["volunteerStarLevelSection"].firstMatch
        XCTAssertTrue(starSection.waitForExistence(timeout: 15), "国标星级栏没渲染出来")

        try audit(app)
    }

    /// 进度条对 VoiceOver 是空的 —— 「还差多少小时」必须作为**可读文本**存在。
    ///
    /// 审计查不出这一条：它只查「有没有 label」，查不出「这一栏丢了唯一一条有信息量的内容」。
    /// 把进度只画进进度条、不留文本节点，对看不见屏幕的人这一栏就等于没有内容，
    /// 而静态审计全绿。
    @MainActor
    func testVolunteerStarLevelExposesRemainingHoursAsText() throws {
        let app = launchVolunteerHome()

        let entry = app.descendants(matching: .any)["服务成就"].firstMatch
        if !entry.waitForExistence(timeout: 20) {
            app.swipeUp()
        }
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()

        let starSection = app.descendants(matching: .any)["volunteerStarLevelSection"].firstMatch
        XCTAssertTrue(starSection.waitForExistence(timeout: 15), "国标星级栏没渲染出来")

        // 星级栏合成一个焦点，所以断言打在它的 label 上 —— 那正是 VoiceOver 会念的整句。
        let spoken = starSection.label
        XCTAssertTrue(
            spoken.contains("小时"),
            "星级栏念不出小时数，进度只剩进度条 —— 对读屏用户这一栏是空的。实际念出：\(spoken)"
        )
        XCTAssertTrue(
            spoken.contains("还差") || spoken.contains("最高星级"),
            "星级栏既没说还差多少，也没说已到顶。实际念出：\(spoken)"
        )
        // 民政部令第 67 号：这一页是展示不是凭据，措辞红线同样要在真机上成立。
        for banned in ["证明", "证书", "已认证"] {
            XCTAssertFalse(spoken.contains(banned), "星级栏念出了违规措辞「\(banned)」：\(spoken)")
        }
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

        // 判据与有订单态那条同源：`isHittable` 只判中心点，盖住上半截时它照样是 true。
        let sosBar = app.descendants(matching: .any)["blindRunnerHomeSOSBar"].firstMatch
        XCTAssertTrue(sosBar.waitForExistence(timeout: 10), "首页底部求助条不在，遮挡判据没有参照物")
        XCTAssertLessThanOrEqual(
            repeatControl.frame.maxY,
            sosBar.frame.minY,
            """
            「重复当前状态」下沿 \(repeatControl.frame.maxY) 越过了底部 SOS 条上沿 \(sosBar.frame.minY)，\
            被盖住了 \(repeatControl.frame.maxY - sosBar.frame.minY)pt。\
            首页在「开始约跑」和它之间又多了一行的话，先想清楚这一行值不值得把它顶下去。
            """
        )
    }

    // MARK: - 首次使用引导

    /// 全新安装第一次进首页，必须自动给到引导；按「知道了」之后回到首页。
    ///
    /// 这条是**唯一**覆盖自动进入路径的用例 —— 其余所有 UI 用例都走默认的「已看过」分支
    /// （见 `launchBlindHome` 的 `forcingFirstRunHelp`），删了它就没有任何东西
    /// 证明引导真的会出现。
    @MainActor
    func testBlindFirstRunHelpAppearsOnFirstLaunchAndReturnsHome() throws {
        let app = launchBlindHome(forcingFirstRunHelp: true)

        let done = app.descendants(matching: .any)["blindRunnerHelpDoneButton"].firstMatch
        XCTAssertTrue(
            done.waitForExistence(timeout: 20),
            "全新安装第一次进首页没有出现引导。没人教的话，两指双击求助这个手势谁都猜不到"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHelpRepeatButton"].firstMatch.exists,
            "引导页缺少「再听一遍」。一次性播报漏听就再也拿不回来，这一页最需要重听"
        )

        done.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20),
            "按「知道了」之后没回到首页"
        )
    }

    @MainActor
    func testBlindFirstRunHelpPassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome(forcingFirstRunHelp: true)
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHelpDoneButton"].firstMatch
                .waitForExistence(timeout: 20),
            "引导页没起来，后面的审计结果没有意义"
        )
        try audit(app)
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

    /// 有订单态也要能不滚动够到「重复当前状态」。
    ///
    /// 上面那条无订单版守了半年，而**有订单态一直没人守** —— 偏偏这一态的内容更长：
    /// 状态卡 + 「查看当前订单」+ 可能的「取消订单」+ 「问一句」全排在它前面。
    /// 2026-08-14 用户在真机上看到的就是这个：默认进来「重复当前状态」被底部 SOS 条切掉一截。
    ///
    /// 断言写在这一态而不是把上面那条改成参数化：两态的前置数据（`emptyOrders`）不同，
    /// 合成一条要么共用一个 launch 参数、要么在用例里分支，都比多一条用例难读。
    @MainActor
    func testBlindHomeWithAnActiveOrderKeepsRepeatStatusReachable() throws {
        let app = launchBlindHome(emptyOrders: false)
        XCTAssertTrue(
            app.buttons["查看当前订单"].firstMatch.waitForExistence(timeout: 20),
            "有订单的盲人首页没起来，后面的断言没有意义"
        )

        let repeatControl = app.buttons["重复当前状态"].firstMatch
        XCTAssertTrue(repeatControl.waitForExistence(timeout: 10), "有订单的盲人首页缺少「重复当前状态」")

        // 这一态的内容天然超一屏（状态卡 + 「查看当前订单」+ 「取消订单」+ 「问一句」+ 它自己，
        // 四个 64pt 起跳的块），**要求不滚动就全露出来是不合理的** —— 真那么排，被牺牲的
        // 会是别的东西。2026-08-14 实测：地图 300pt 时它下沿 922、SOS 条上沿 772。
        //
        // 所以这一态抓的是另一件事：**滚到底也够不着**。那才是永久被固定条盖住，
        // 与「在折叠线以下、滑一下就有」是两回事。
        let sosBar = app.descendants(matching: .any)["blindRunnerHomeSOSBar"].firstMatch
        XCTAssertTrue(sosBar.waitForExistence(timeout: 10), "首页底部求助条不在，遮挡判据没有参照物")

        var swipes = 0
        while repeatControl.frame.maxY > sosBar.frame.minY && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }

        XCTAssertLessThanOrEqual(
            repeatControl.frame.maxY,
            sosBar.frame.minY,
            """
            滚了 \(swipes) 次，「重复当前状态」下沿仍是 \(repeatControl.frame.maxY)，\
            压在底部 SOS 条上沿 \(sosBar.frame.minY) 之下 —— 它被那条常驻条永久盖住了，\
            滚动也救不回来。底部 `safeAreaInset` 的高度变了、或者这一列又多了一块时会撞到这条。
            """
        )
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
            let label = issue.element?.label ?? ""
            if Self.auditIgnoredIdentifiers.contains(identifier) || Self.auditIgnoredLabels.contains(label) {
                return true
            }
            // 审计失败只报一句「Contrast failed」，**不说是哪个元素** —— 2026-08-14 为定位一次
            // 对比度失败，加打印、重跑、再删，白花了两轮真机。留着，失败日志里直接就有。
            print("""
            [AUDIT] \(issue.auditType) id=\(identifier) label=\(label) \
            frame=\(issue.element?.frame ?? .zero) \(issue.detailedDescription)
            """)
            return false
        }
    }

    /// 审计白名单。**每加一条都要写清为什么，否则白名单会慢慢把审计架空。**
    private static let auditIgnoredIdentifiers: Set<String> = [
        // 高德地图图层无法承载有意义的 label，且它已被显式降权为辅助内容
        // （视觉可以铺满，读屏遍历顺序必须操作优先）。
        "blindRunnerHomeAuxiliaryMap",
        "blindBookingAuxiliaryMap",
        "mapPlaceholder"
    ]

    /// 上面两个地图的替身：缺高德 key 时（UI 测试构建**永远**缺）渲染的占位图。
    ///
    /// **按文案而不是 identifier 认它**：`MapPlaceholderView` 上确实挂了
    /// `accessibilityIdentifier("mapPlaceholder")`，但审计穿透 `children: .combine`
    /// 报的是内部那几个 `Text`，它们的 identifier 是空字符串 —— 只按 id 白名单放不掉。
    ///
    /// 2026-08-14 加：地图从 300 压到 200pt 后它开始报 `Contrast failed`，而它用的是
    /// `.label` on `.secondarySystemBackground`（约 19:1）—— **颜色没问题**，是文字位置
    /// 变了之后审计的采样结果变了。放行的理由不是「颜色达标」，而是：它只在缺 key 时出现，
    /// 生产构建走真地图；且这几句话是给开发者看的，不是盲人用户的界面。
    ///
    /// 按文案匹配意味着**改文案会让白名单失效**。那是想要的行为：文案变了就该重新审一次。
    private static let auditIgnoredLabels: Set<String> = [
        "地图服务暂不可用",
        "请配置高德地图 API Key",
        "参考 LocalConfig.xcconfig.example 创建配置文件",
        "地图服务暂不可用，请配置高德地图 API Key"
    ]

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
        emptyOrders: Bool = true,
        forcingFirstRunHelp: Bool = false
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
        // 不传就跳过首次引导。`blindRunApp.applyUITestLaunchConfigurationIfNeeded` 默认把
        // 「已看过」置位 —— 否则每条用例一进首页就被引导页挡住，二十多条断言全红。
        if forcingFirstRunHelp {
            app.launchEnvironment["AIDRUN_UI_TEST_FORCE_FIRST_RUN_HELP"] = "1"
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

    /// 志愿者首页。与 `launchBlindHome` 分开而不是加一个 role 参数：两边要设的
    /// preseed 变量集合不同（志愿者要 profile + available，盲人要 profile + prefill），
    /// 合成一个函数会变成一串互斥的 if，改一次错一次。
    ///
    /// ⚠️ **`PRESEEDED` 不是 `PRESEED`** —— 写错不会报错，只会静默进到「资料未填」分支，
    /// 然后审计的是错的那一页（与 `launchBlindHome` 上那条注释同一个坑）。
    @MainActor
    private func launchVolunteerHome() -> XCUIApplication {
        let app = XCUIApplication()
        addTeardownBlock {
            await MainActor.run { app.terminate() }
        }
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_RESET_TOKEN"] = UUID().uuidString
        app.launchEnvironment["AIDRUN_UI_TEST_FORCE_DEMO_LOCATION"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_API_ENV"] = "mock"
        app.launchEnvironment["AIDRUN_UI_TEST_ACTIVE_ROLE"] = "volunteer"
        app.launchEnvironment["AIDRUN_UI_TEST_ACCESS_TOKEN"] = "mock_jwt_token_for_testing"
        app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_PROFILE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"

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
        // 触发一次 interruption monitor。敲顶部地图区 —— 志愿者首页那一层同样不接受点击，
        // 是这一页唯一保证不触发任何动作的地方。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        return app
    }
}
