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

        // 入口在首屏徽章区的「全部 N 枚 ›」（2026-09-14 改版前是底部那排「记录 / 成就 / 设置」）。
        // SwiftUI 不渲染屏幕外的内容，直接断言会假失败 —— 先往下滚（commit 4cee939 的同一个坑）。
        let entry = achievementsEntry(app)
        XCTAssertTrue(entry.exists, "志愿者首屏没有「成就」入口，后面的审计没有意义")
        entry.tap()

        let page = app.descendants(matching: .any)["volunteerServiceRecognitionView"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 15), "成就页没起来，审计结果没有意义")

        // 页面自己要发一次 `GET /api/volunteer/achievements`（Mock 直接返回），
        // 数据没到之前屏幕上只有一个 ProgressView，那时审计等于审计一个空页。
        let starSection = app.descendants(matching: .any)["volunteerStarLevelSection"].firstMatch
        XCTAssertTrue(starSection.waitForExistence(timeout: 15), "国标星级栏没渲染出来")

        try audit(app)
    }

    /// 陪跑员端的底部三标签（设计交付 v3 §4.1）。
    ///
    /// 改版前这三样只有一条路：「记录」在首屏「最近一次」旁的「全部 ›」里、「我的」是首屏
    /// 右上角一枚齿轮。**那两个旧入口刻意保留着**，所以「首屏还能进到设置」不足以证明
    /// 标签栏还在 —— 这条断的是标签栏本身，以及切过去之后目标页真的渲染出来了。
    ///
    /// 🚩 顺手钉住「订单页不带标签栏」的反面：那一族页面藏标签栏的前提是返回箭头一直在
    /// （见 `VolunteerInServiceView` 上那段注释），这里不重复验，由服务页自己的用例覆盖。
    @MainActor
    func testVolunteerTabBarOffersHomeRecordsAndProfile() throws {
        let app = launchVolunteerHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
                .waitForExistence(timeout: 20),
            "陪跑员首页没起来"
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "底部标签栏不在")
        for title in ["首页", "记录", "我的"] {
            XCTAssertTrue(
                tabBar.buttons[title].exists,
                "标签栏缺少「\(title)」—— 设计交付 v3 §4.1 要的就是这三个"
            )
        }

        tabBar.buttons["记录"].tap()
        XCTAssertTrue(
            app.navigationBars["服务记录"].waitForExistence(timeout: 15),
            "「记录」tab 没到服务记录页"
        )

        tabBar.buttons["我的"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerScheduleSettingsEntry"].firstMatch
                .waitForExistence(timeout: 15),
            "「我的」tab 没到设置页 —— 空闲时间是那一页的第一组，它不在就说明挂错了页面"
        )

        tabBar.buttons["首页"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerProfileIdentityRow"].firstMatch
                .waitForExistence(timeout: 15),
            "切不回首页"
        )
    }

    /// 进度条对 VoiceOver 是空的 —— 「还差多少小时」必须作为**可读文本**存在。
    ///
    /// 审计查不出这一条：它只查「有没有 label」，查不出「这一栏丢了唯一一条有信息量的内容」。
    /// 把进度只画进进度条、不留文本节点，对看不见屏幕的人这一栏就等于没有内容，
    /// 而静态审计全绿。
    @MainActor
    func testVolunteerStarLevelExposesRemainingHoursAsText() throws {
        let app = launchVolunteerHome()

        let entry = achievementsEntry(app)
        XCTAssertTrue(entry.exists)
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
    ///
    /// 🔄 **2026-09-16 起它是问候行右侧的一枚图标按钮**（项目负责人拍板），
    /// 不再是内容列里的全宽次级按钮。用例因此加了两条断言：
    ///
    /// 1. **必须是可见的按钮，而不是 accessibility custom action。** 后者是这次改版里
    ///    被否掉的候选方案，而它的两条硬伤恰好都逃得过一条只查「存不存在」的断言：
    ///    不开读屏的低视力用户够不到，且 `XCUIElement.tap()` 注入的是物理触摸、
    ///    **不经过 accessibility action**（记忆 `xcuitest-cannot-invoke-accessibility-actions`）
    ///    —— 真做成 custom action，`waitForExistence` 会通过而 `isHittable` 不会。
    /// 2. **64pt 触达 + 不滚动即可达。** 它在问候行上，本就该在首屏。
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

        // 见上面第 1 条：这一句是「可见按钮」与「custom action」的分界线。
        XCTAssertTrue(
            repeatControl.isHittable,
            "「重复当前状态」在无障碍树里但按不到 —— 做成 accessibility custom action 了？"
                + "那样不开读屏的低视力用户够不到它。"
        )
        XCTAssertGreaterThanOrEqual(
            repeatControl.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "「重复当前状态」只有 \(repeatControl.frame.height)pt，低于盲人端 64pt 触达下限"
        )

        // 不滚动即可达：它在问候行上，落在首屏之外只可能是布局出了问题。
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "底部标签栏不在，遮挡判据没有参照物")
        XCTAssertLessThanOrEqual(
            repeatControl.frame.maxY,
            tabBar.frame.minY,
            "「重复当前状态」下沿 \(repeatControl.frame.maxY) 越过了标签栏上沿 \(tabBar.frame.minY)"
        )
    }

    /// 首页最大的那一块必须是**即将开始的那一单**，没有订单时才轮到预约入口。
    ///
    /// 🔄 **2026-09-16 换了被守的对象，守的是同一个用户需求。** 原用例叫
    /// `testBlindRunnerPrimaryButtonDominatesTheScreen`，断言「开始约跑」占屏 ≥25%
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §1，对标 Be My Eyes 的
    /// `Call a volunteer` 占内容区约 75%）。那个 280pt 按钮已按设计稿
    /// `design-reference/order-flow/screens/01-home.png` 删除。
    ///
    /// **设计稿反转的不是「主操作要大」，是「谁才是主操作」**：视障用户打开 App 第一句
    /// 该听到、第一眼该看到的是最重要的**信息**（下一次陪跑），不是下单这个**动作**。
    /// 所以阈值从「按钮占屏 ≥25%」改成「有订单时订单卡比预约块高」+「预约块本身不许
    /// 被缩回次级按钮那一档」。后半句保留了原用例真正防的东西 ——
    /// 它此前和「重复当前状态」同高时全绿，而用户看到的是「约跑的按钮还是小」。
    ///
    /// ⚠️ 阈值刻意不写成固定的占屏比：这一屏在 iPad 上高 820、在 iPhone SE 上高 667，
    /// 而订单卡的高度由内容（52pt 大字 + 几行文字）决定、随 Dynamic Type 长。
    /// 比**两块之间的相对大小**在所有设备与所有字号下都成立，比固定比例稳。
    /// 记忆 `verified-on-one-device-is-not-verified` 记着原用例在 iPad 上长红
    /// （23.7% < 25%）—— 固定占屏比就是那条长红的来源。
    @MainActor
    func testBlindRunnerHomeGivesTheLargestBlockToTheUpcomingOrder() throws {
        let app = launchBlindHome(emptyOrders: false)
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "有订单的盲人首页没起来")

        let booking = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(booking.waitForExistence(timeout: 10), "首页缺少预约入口")

        XCTAssertGreaterThan(
            card.frame.height,
            booking.frame.height,
            """
            订单卡实测 \(card.frame.height)pt，不高于预约块 \(booking.frame.height)pt。
            首页最大的位置必须留给即将开始的那一单 —— 打开 App 第一眼该看到的是最重要的
            信息，不是下单这个动作。要改这条先看 design-reference/order-flow/screens/01-home.png。
            """
        )

        // 预约块自己也不许被缩回次级按钮那一档（原用例真正防的就是这件事）。
        // 判据用「明显高于 64pt 触达下限」而不是占屏比：它在设计稿里是 56pt 加号圆 +
        // 两行文字 + 上下各 22pt 内边距，默认字号下约 100pt。
        XCTAssertGreaterThan(
            booking.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            """
            预约块只有 \(booking.frame.height)pt，等于缩回了 64pt 触达下限那一档。
            它是无订单时这一屏唯一的主操作，低视力用户要能一眼看到。
            """
        )
    }


    // MARK: - 首屏可达性

    /// 无订单首页不得出现「问一句」，且「重复当前状态」必须**不滚动**就够得着。
    ///
    /// 两笔改动叠在一起造出过这个缺陷：`925e78c` 把「开始约跑」放大到 280pt，
    /// 当天晚些的 `03f3e40` 又在它后面无条件追加了「问一句」，于是 64 + 24 的一行把
    /// 「重复当前状态」整个顶进底部 SOS 条后面。
    ///
    /// 🔄 **2026-09-16 改版后这条用例换了被守的对象，但守的是同一件事。**
    /// 首页收成「问候 + 订单卡 + 预约块」三块：「问一句」「重复当前状态」都不在首页了
    /// （前者进求助与安全中心，后者按项目负责人拍板也进那个弹层），底部常驻求助条移到
    /// 「我的」tab。于是屏幕底部的固定条从求助条变成了**标签栏**，而不变式没变：
    /// **这一屏唯一的主操作不许被底部那条固定条永久盖住。**
    ///
    /// 判据仍用 `frame` 边界而不是 `isHittable` —— 后者只判中心点，
    /// 上半截被盖住时它照样是 `true`（同 `testBlindOrderStatusKeepsEmergencyReachableWithoutScrolling`）。
    @MainActor
    func testBlindHomeWithoutAnOrderKeepsTheBookingEntryClearOfTheTabBar() throws {
        let app = launchBlindHome()
        let booking = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(
            booking.waitForExistence(timeout: 20),
            "盲人首页没起来，后面的断言没有意义"
        )

        // 无订单时深蓝订单卡整块不渲染，预约块自然落到它的位置 —— 这条断言钉的是
        // 「不渲染」而不是「渲染成一张空卡」：空卡对读屏用户是一个念不出内容的元素。
        XCTAssertFalse(
            app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch.exists,
            "无订单首页出现了深蓝订单卡 —— 它没有内容可展示，只会多一次划动"
        )

        XCTAssertGreaterThanOrEqual(
            booking.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "预约入口只有 \(booking.frame.height)pt，低于盲人端 64pt 触达下限"
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "底部标签栏不在，遮挡判据没有参照物")
        XCTAssertLessThanOrEqual(
            booking.frame.maxY,
            tabBar.frame.minY,
            """
            预约入口下沿 \(booking.frame.maxY) 越过了标签栏上沿 \(tabBar.frame.minY)，\
            被盖住了 \(booking.frame.maxY - tabBar.frame.minY)pt。\
            首页在问候和它之间又多了一块的话，先想清楚这一块值不值得把主操作顶下去。
            """
        )
    }

    /// 三个 tab 都必须在，且标签可读。
    ///
    /// 单独一条而不是并进上面：**这是本仓库第一个 `TabView`**（改版前全仓命中 0 处），
    /// 而根导航换掉之后「有没有起来」和「起来了但少一个 tab」是两种不同的失败。
    @MainActor
    func testBlindRunnerTabBarOffersHomeHistoryAndProfile() throws {
        let app = launchBlindHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20),
            "盲人首页没起来"
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "底部标签栏不在")
        for title in ["首页", "记录", "我的"] {
            XCTAssertTrue(
                tabBar.buttons[title].exists,
                "标签栏缺少「\(title)」—— 改版后历史订单与设置只有这一条路可走"
            )
        }

        // 紧急入口从首页移到了「我的」tab（项目负责人 2026-09-16 拍板）。
        // **这条断言是那个决定的唯一机器守卫**：求助条在任何一个 tab 上都摸不到时，
        // 表现只是「首页干净了」，没有任何东西会报警。
        tabBar.buttons["我的"].tap()
        let sosBar = app.descendants(matching: .any)["blindRunnerHomeSOSBar"].firstMatch
        XCTAssertTrue(
            sosBar.waitForExistence(timeout: 10),
            "「我的」tab 底部没有兜底的紧急入口 —— 首页那条已经移除，这里是它现在唯一的落点"
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

    /// Mock 横幅必须待在状态栏那一条里，不许压到导航栏上。
    ///
    /// 它此前挂在 `.safeAreaInset(edge: .top)` 上，而各路由自己建 `NavigationStack` ——
    /// 外层的安全区改动压不动里面那条栏。2026-09-05 iPhone 16 Pro 实测：横幅
    /// `y 0..101.3`、导航栏 `y 62..116`、标题 `y 73.7..94.3`，标题整条被盖住。
    /// 直接后果是 `.contrast` 审计采到横幅的黄底黑字、报的却是被盖住的标题，
    /// 创建预约 / 使用帮助 / 服务成就三条审计用例随机红 —— 失败元素的
    /// Element Screenshot 就是那条黄横幅本身。
    ///
    /// 用 frame 相交判而不是「横幅存不存在」：真正的不变式是**它不遮挡导航**，
    /// 把它藏起来只是达成这条的一种方式。
    @MainActor
    func testMockBannerStaysClearOfTheNavigationBar() throws {
        let app = launchBlindHome(forcingFirstRunHelp: true)
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHelpDoneButton"].firstMatch
                .waitForExistence(timeout: 20),
            "引导页没起来，下面要比的两个 frame 没有意义"
        )

        let banner = app.descendants(matching: .any)["mockEnvironmentBanner"].firstMatch
        // 明确 skip 而不是静默通过：横幅是 `#if DEBUG` + Mock 专属，别的构建里本来就没有，
        // 「没跑」和「跑过了」必须可区分。
        try XCTSkipUnless(
            banner.waitForExistence(timeout: 5),
            "这个构建里没有 Mock 横幅（非 DEBUG 或非 Mock 环境）—— 这条断言无从判定"
        )

        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10), "引导页没有导航栏，没有参照物")

        XCTAssertFalse(
            banner.frame.intersects(navigationBar.frame),
            """
            Mock 横幅 \(banner.frame) 压在导航栏 \(navigationBar.frame) 上，页面标题会被盖住。
            别把它改回 `.safeAreaInset(edge: .top)`：那条 inset 缩的是外层安全区，
            压不动各路由自己那条 `NavigationStack` 的导航栏，只会又盖回去。
            """
        )
    }

    /// 有订单时首页那张深蓝卡必须是**一个**无障碍元素，而且念出来是一句完整的话。
    ///
    /// 🔄 这条取代了改版前的 `testBlindHomeWithAnActiveOrderOffersAskQuestion`
    /// （「问一句」已从首页移入求助与安全中心，那个入口的用例在
    /// `testSafetyHubPutsEmergencyFirstInTheAccessibilityOrder` 一带）。
    ///
    /// 换过来的这条守的是设计里最要紧的那一点：**视障用户打开 App 第一句听到的就该是
    /// 最重要的信息，而且是一句完整的话** —— 不是被拆成时间、地点、姓名、小按钮各滑一次。
    /// 所以断言分两半：① 卡片本身是一个 button 元素；② 时间、地点、陪跑员三样都在它的
    /// label 里，而不是散成同层的兄弟元素。
    ///
    /// ⚠️ 不断言 label 的**逐字内容**：中文文案漂移在 UI 测试里误报率极高
    /// （记忆 `merged-prs-whose-tests-never-ran`）。断的是「这三样信息在不在同一个元素里」。
    @MainActor
    func testBlindHomeOrderCardIsOneElementThatReadsAsAFullSentence() throws {
        let app = launchBlindHome(emptyOrders: false)
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 20),
            "有订单的盲人首页没起来，后面的断言没有意义"
        )
        XCTAssertTrue(card.isHittable, "订单卡存在但够不着，等于没有")

        // 种子订单的出发地点（`MockAPIClient.seedDemoData`）。地点是这张卡上唯一
        // 「不在别处重复」的信息，拿它当「三样都进了同一个 label」的探针。
        XCTAssertTrue(
            card.label.contains("公园"),
            "订单卡的读屏标签里没有出发地点。当前 label：\(card.label)"
        )
        XCTAssertTrue(
            card.label.contains("下一次陪跑"),
            "订单卡的读屏标签没有以「下一次陪跑」开头 —— 那是它回答的第一个问题。当前 label：\(card.label)"
        )

        // 卡片内部的元素不许自己冒出来：底部那条「打开订单 ›」是给看得见的人的视觉线索，
        // 整张卡已经是按钮了，再冒一个同名元素就是同一个动作在读屏里出现两次。
        XCTAssertFalse(
            app.buttons["打开订单"].firstMatch.exists,
            "「打开订单」冒成了独立元素 —— 它应当对读屏隐藏，动作由卡片自己的 hint 说明"
        )
    }

    /// 有订单时首页两块内容都要够得着，且不被标签栏永久盖住。
    ///
    /// 🔄 取代改版前的 `testBlindHomeWithAnActiveOrderKeepsRepeatStatusReachable`：
    /// 「重复当前状态」已不在首页，而**「有订单态内容更长、更容易被底部固定条吃掉」这个
    /// 风险没有消失** —— 现在排在一起的是订单卡（含 52pt 大字，AX 档还会长）和预约块。
    ///
    /// 抓的是「滚到底也够不着」，不是「首屏内全露出来」—— 后者在这一态本就不合理，
    /// 真那么排会牺牲别的东西。
    @MainActor
    func testBlindHomeWithAnActiveOrderKeepsBothBlocksReachable() throws {
        let app = launchBlindHome(emptyOrders: false)
        let card = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "有订单的盲人首页没起来")

        let booking = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(
            booking.waitForExistence(timeout: 10),
            "有订单时预约入口不见了 —— 盲人同时最多能有 3 张未完成预约，这个入口不该消失"
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "底部标签栏不在，遮挡判据没有参照物")

        var swipes = 0
        while booking.frame.maxY > tabBar.frame.minY && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }

        XCTAssertLessThanOrEqual(
            booking.frame.maxY,
            tabBar.frame.minY,
            """
            滚了 \(swipes) 次，预约入口下沿仍是 \(booking.frame.maxY)，\
            压在标签栏上沿 \(tabBar.frame.minY) 之下 —— 它被永久盖住了，滚动也救不回来。
            """
        )
    }

    /// 匹配态（`PENDING_MATCH`）这一屏**没有**「继续等待」，而它该有的三样东西都在。
    ///
    /// 🔄 **2026-09-16 整条改向。** 原来它断言的是「后端 `ORDER_CANCELLATION_WARNING`
    /// 正文让用户点的那个控件真的在屏幕上」。项目负责人当日拍板删掉 `PENDING_MATCH` 那个
    /// 按钮（后端 `handleMatchTimeout` 每轮超时自己就把窗口往后推，客户端一次不调订单寿命
    /// 相同），于是原断言成了反向守卫：它会逼人把一个按了等于没按的按钮加回来。
    ///
    /// 那句后端文案的问题改由**客户端覆盖正文**解决，钉在
    /// `AppRealtimeCoordinatorTests.testCancellationWarningDropsTheDeletedButtonHintWhilePendingMatch`
    /// —— UI 测试是黑盒，读不到通知正文，只能在这里断言「控件确实不在」这一半。
    ///
    /// 剩下三样必须在，一样都不能少：
    /// 1. **「取消匹配」不滚动就够得着** —— 删掉「继续等待」之后它是这一态唯一的决定；
    /// 2. **二次确认里带「匹配规则说明」** —— 《互联网信息服务算法推荐管理规定》第十六条的
    ///    「显著方式告知」，改版把它原来的落点（那条滚动列表）整段换掉了（设计稿 §3.5）；
    /// 3. **「重复当前状态」在导航栏右侧** —— skill `aidrun-a11y-voice` 的硬规则，
    ///    系统 Speak Screen 读不到一次性 `announcement`，没有它盲人错过一次播报就拿不回来。
    @MainActor
    func testBlindOrderStatusMatchingStateOffersCancelAndRuleNoticeInsteadOfKeepWaiting() throws {
        let app = launchBlindHome(emptyOrders: false)
        let currentOrder = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(
            currentOrder.waitForExistence(timeout: 20),
            "有订单的盲人首页没起来，后面的断言没有意义"
        )
        currentOrder.tap()

        // 种子订单是 PENDING_MATCH（`MockAPIClient.seedDemoData`），落在骨架的「匹配」格。
        let statusCard = app.descendants(matching: .any)["blindOrderFlowStatusCard"].firstMatch
        XCTAssertTrue(statusCard.waitForExistence(timeout: 15), "订单页四步骨架没起来")

        XCTAssertFalse(
            app.descendants(matching: .any)["blindOrderStatusKeepWaitingButton"].firstMatch.exists,
            "PENDING_MATCH 又出现了「继续等待」—— 按了等于没按，而盲人无从发现这件事"
        )

        // ① 「取消匹配」。判据用 `frame` 边界不用 `isHittable`：后者只判中心点，
        // 一个上半截被底栏盖住的按钮照样是 true（与
        // `testBlindOrderStatusKeepsEmergencyReachableWithoutScrolling` 同源）。全程不滚动。
        let lastRow = app.descendants(matching: .any)["blindOrderFlowLastRowButton"].firstMatch
        XCTAssertTrue(lastRow.waitForExistence(timeout: 5), "信息列表最后一行不见了")
        XCTAssertEqual(lastRow.label, "取消匹配", "匹配态这一行的文案是设计稿原文")
        XCTAssertLessThanOrEqual(
            lastRow.frame.maxY,
            app.frame.maxY,
            """
            「取消匹配」下沿 \(lastRow.frame.maxY) 超出屏幕底 \(app.frame.maxY)，要下滑才够得到。\
            删掉「继续等待」之后它是这一态唯一的决定，放在首屏外等于这一态什么都做不了。
            """
        )

        // ③ 「重复当前状态」—— 先断言它在，再去点取消（弹窗会盖住导航栏）。
        XCTAssertTrue(
            app.descendants(matching: .any)["blindOrderFlowRepeatStatusButton"].firstMatch.exists,
            "导航栏右侧没有「重复当前状态」—— 盲人错过一次状态播报就再也拿不回来"
        )

        // ② 二次确认 + 里面那条「匹配规则说明」。
        lastRow.tap()
        let confirmCancel = app.buttons["确认取消"].firstMatch
        XCTAssertTrue(
            confirmCancel.waitForExistence(timeout: 5),
            "「取消匹配」没有二次确认 —— 这是不可逆动作"
        )
        let ruleNotice = app.buttons["匹配规则说明"].firstMatch
        XCTAssertTrue(
            ruleNotice.exists,
            """
            取消确认弹窗里没有「匹配规则说明」。改版把它原来的落点整段换掉了，\
            而算法告知是法规要求的「显著方式」—— 沉到设置页深处不算显著。
            """
        )
        // 不点「确认取消」：那会把种子订单毁掉，后面重跑这条用例就没有订单可用了。
        //
        // 🔴 **`.cancel` 那个按钮在这台机器上根本不在元素树里。**
        // 2026-09-16 真机实测（iPhone 16 Pro / iOS 26.6.1）：`confirmationDialog` 被渲染成
        // `Popover`，里面只有消息 `StaticText` + 我们声明的两个非 cancel 按钮，
        // 而 `Button("不取消", role: .cancel)` 被系统换成了
        // `identifier: 'PopoverDismissRegion', label: 'dismiss popup'`。
        // 按 `app.buttons["不取消"]` 找它必然落空 —— 这不是文案漂移，是呈现形态变了。
        //
        // ⚠️ **顺带一条产品事实，已记进交接**：那个唯一的退出口 label 是**英文**
        // 「dismiss popup」。读屏用户在一个中文的破坏性二次确认上，
        // 听到的退出方式是一句英文 —— 这是系统给的，不是我们的文案。
        //
        // 两条路都留着：旧系统把它渲染成操作表时 `不取消` 是真按钮。
        // `PopoverDismissRegion` 是**系统**的 identifier，App 侧不会产出它，
        // 所以这里对 `stale-ui-test-identifier` 显式豁免。
        let dismissRegion = app.descendants(matching: .any)["PopoverDismissRegion"].firstMatch  // guard:allow stale-ui-test-identifier
        if dismissRegion.exists {
            dismissRegion.tap()
        } else {
            app.buttons["不取消"].firstMatch.tap()
        }
    }

    /// 🔴 **非 `IN_PROGRESS` 的求助中心，底部必须是本地拨号，不是云端求助。**
    ///
    /// 这是 2026-09-16 引入四步骨架时新开的一个洞：骨架底部那枚「求助与安全」让求助中心
    /// 第一次可以在 `PENDING_MATCH` / `SCHEDULED_CONFIRMED` / `DRIVER_EN_ROUTE` /
    /// `DRIVER_ARRIVED` 打开，而云端求助两端都只在 `IN_PROGRESS` 开放（`AGENTS.md` §6）。
    /// 照走云端的真实后果：`beginCountdown` 在资格 guard 落 `.failed`、全屏倒计时不弹，
    /// 而骨架这一屏没有 `EmergencyStatusNotice` 的渲染点 ——
    /// **长按 3 秒之后屏幕零变化、一个字也不播。**
    ///
    /// 判据是**哪一个控件在底部**，不是点下去发生了什么：后者会真的走到拨号
    /// （DEBUG 下有 `EmergencyDialer` 的拦截，但不值得在这里赌）。
    @MainActor
    func testSafetyHubOutsideTheActiveRunOffersLocalDialInsteadOfCloudSOS() throws {
        let app = launchBlindHome(emptyOrders: false)
        let currentOrder = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(currentOrder.waitForExistence(timeout: 20), "有订单的盲人首页没起来")
        currentOrder.tap()

        let entry = app.descendants(matching: .any)["blindOrderFlowSafetyHubButton"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "骨架底部没有「求助与安全」")
        entry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["blindSafetyHub"].firstMatch.waitForExistence(timeout: 10),
            "求助中心没打开"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["blindSafetyHubLocalCall"].firstMatch.exists,
            "PENDING_MATCH 的求助中心底部不是「紧急呼叫」—— 云端那条在这一态发不出去"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["blindSafetyHubTriggerEmergency"].firstMatch.exists,
            """
            PENDING_MATCH 的求助中心还挂着云端「一键求助」。\
            按下去会静默失败：不弹倒计时、屏幕零变化、一个字不播。
            """
        )

        // 设计稿 §3.5 的迁移落点：「分享实时位置给家人 → 求助与安全中心」。
        // 只断存在、不断 `isHittable` —— 方格在 ScrollView 里，最后一格可能在首屏之外，
        // 而 SwiftUI 的 `ScrollView` 屏幕外子视图照样在无障碍树里
        //（`List` 才是压根不渲染，两种坑不一样）。
        XCTAssertTrue(
            app.descendants(matching: .any)["blindSafetyHubShareLiveLocation"].firstMatch.exists,
            "「分享实时位置给家人」没落到求助中心 —— 骨架换掉了它原来那条列表，功能就丢了"
        )

        app.descendants(matching: .any)["blindSafetyHubDismissButton"].firstMatch.tap()
    }

    // MARK: - 求助入口的位置

    /// 服务进行中，盲人端的求助按钮必须**不滚动**就在屏幕上。
    ///
    /// 2026-08-19 之前它排在滚动内容第 7 位（`actionSection`），上面压着状态卡、140pt 的
    /// 「打电话给志愿者」、行程分享、180pt 装饰地图 —— 内容顶到它约 700pt，而底部常驻条吃掉
    /// 约 164pt 后视口只剩约 550pt。**看不见屏幕的人在跑步中要先滑一段才摸得到求助。**
    /// 更阴的是它不稳定：拿不到志愿者位置时地图退化成一行文字，求助又回到首屏 ——
    /// 于是「手测了一次没问题」不代表下一次也在。
    ///
    /// 判据用 `frame` 边界而不是 `isHittable`：后者只判中心点，一个上半截被盖住的按钮照样是 true
    /// （与 `testBlindHomeWithoutAnOrderHidesAskQuestionAndKeepsRepeatStatusReachable` 同源）。
    /// 全程**一次滚动都不做** —— 这条断言的全部意义就是「不滚也在」。
    ///
    /// 2026-09-15：`IN_PROGRESS` 改走执行屏（`BlindActiveRunView`）之后，这一页的求助从
    /// 「一键求助」按钮变成了贴底的**求助中心**红块，标签随之改成 `hubAccessibilityLabel`。
    /// 断言的**不变式一个字没变**：不滚就在、≥64pt、上下沿都在屏内。
    @MainActor
    func testBlindOrderStatusKeepsEmergencyReachableWithoutScrolling() throws {
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "IN_PROGRESS")
        let currentOrder = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(
            currentOrder.waitForExistence(timeout: 20),
            "有订单的盲人首页没起来，后面的断言没有意义"
        )
        currentOrder.tap()

        let emergency = app.buttons[Self.safetyHubLabel].firstMatch
        XCTAssertTrue(
            emergency.waitForExistence(timeout: 15),
            "服务进行中的订单状态页没有求助入口 —— 这一页最要紧的动作不在了"
        )
        XCTAssertGreaterThanOrEqual(
            emergency.frame.minY,
            app.frame.minY,
            "求助按钮上沿越过了屏幕顶，说明它其实在滚动区更上方、当前是被滚出去的"
        )
        XCTAssertLessThanOrEqual(
            emergency.frame.maxY,
            app.frame.maxY,
            """
            求助按钮下沿 \(emergency.frame.maxY) 超出屏幕底 \(app.frame.maxY)，要下滑才够得到。\
            它必须留在底部常驻条（`BlindOrderStatusView.repeatStatusArea`）里；\
            往那条常驻区加东西之前，先想清楚多的那一行值不值得把求助顶下去。
            """
        )
        XCTAssertGreaterThanOrEqual(
            emergency.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "盲人端主动作触达高度不得低于 64pt"
        )

        // 「重复当前状态」这个**功能**必须跨页可达且位置一致（WCAG 3.2.6）。
        //
        // 2026-09-16 它在这一屏换了载体：跑步中的主按钮就是「播报当前数据」，
        // 按下去调的是同一个 `viewModel.repeatStatus()`（播状态 + 里程 / 时长 / 配速）。
        // 导航栏那枚小图标在这一幕收起 —— 两枚按钮播同一段话，对看不见屏幕的人
        // 只是多一次误触面。所以断言换成主按钮，**不变式没变**：不滚就在、≥64pt。
        let announce = app.descendants(matching: .any)["blindOrderFlowPrimaryButton"].firstMatch
        XCTAssertTrue(
            announce.waitForExistence(timeout: 5),
            "跑步中没有主按钮 —— 它是盲人按一下就听全当前状态与三个数字的唯一入口"
        )
        XCTAssertEqual(
            announce.label, "播报当前数据",
            "跑步中的主按钮换了文案 —— 位置可以不动，但这一格承担的是「重复当前状态」"
        )
        XCTAssertGreaterThanOrEqual(
            announce.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "盲人端主动作触达高度不得低于 64pt"
        )
        XCTAssertLessThanOrEqual(
            announce.frame.maxY, app.frame.maxY,
            "主按钮下沿超出屏幕底，要下滑才够得到"
        )

        // 「问一句」2026-09-15 搬进求助中心（屏 2）第三格。**它没有被删、也没有被降级成
        // 纯 accessibility action** —— 后者会把不开读屏的低视力用户永久排除在外
        // （记忆 `low-vision-visual-channel-unaudited`）。所以这里断言的是
        // 「打开求助中心之后，那一格作为一个真实可见元素存在」，不是「某个动作名存在」。
        emergency.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindSafetyHubAskQuestion"].firstMatch
                .waitForExistence(timeout: 10),
            "「问一句」在求助中心里不存在 —— 从执行屏搬走之后它没有落到任何地方"
        )
        // 求助中心必须能退回去，否则跑者被关在这一层里。
        let dismiss = app.descendants(matching: .any)["blindSafetyHubDismissButton"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "求助中心没有「收起，返回跑步」")
        dismiss.tap()
    }

    /// 求助中心（屏 2）打开后，**读屏第一个念到的必须是「一键求助」**。
    ///
    /// 它在视觉上贴在最底下，遍历顺序却排第一 —— 这两件事靠的是**声明顺序**
    /// （`BlindSafetyHubView.body` 的 `ZStack` 把它声明在最前）。
    /// `accessibilitySortPriority` 在本仓库实测排不动叠放层，四种写法真机全废
    /// （`docs/research/swiftui-voiceover-traversal-order-20260814.md`），
    /// 所以这条断言是那个结构唯一的守卫：谁把 `ZStack` 里两块的顺序调回来，它就红。
    @MainActor
    func testSafetyHubPutsEmergencyFirstInTheAccessibilityOrder() throws {
        let app = launchBlindHome(emptyOrders: false, seedOrderStatus: "IN_PROGRESS")
        let currentOrder = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(currentOrder.waitForExistence(timeout: 20), "有订单的盲人首页没起来")
        currentOrder.tap()

        let entry = app.buttons[Self.safetyHubLabel].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "执行屏没有求助入口")
        entry.tap()

        let hub = app.descendants(matching: .any)["blindSafetyHub"].firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 10), "求助中心没打开")

        // 只比**同一次枚举里**的元素：`allElementsBoundByAccessibilityElement` 是逐层枚举，
        // 跨深度比下标恒不成立（记忆 `swiftui-traversal-order-follows-paint-order`）。
        // 所以这里问的是「弹层根下第一个可访问后代是不是它」。
        let first = hub.descendants(matching: .any).allElementsBoundByAccessibilityElement.first
        XCTAssertEqual(
            first?.identifier,
            "blindSafetyHubTriggerEmergency",
            """
            求助中心第一个可访问元素是 \(first?.identifier ?? "（空）")，不是一键求助。\
            读屏用户要多划过几站才摸得到这一层里唯一救命的那个动作。
            """
        )

        app.descendants(matching: .any)["blindSafetyHubDismissButton"].firstMatch.tap()
    }

    /// 志愿者端服务中页，求助入口必须待在**屏幕上三分之一**，不和常规操作按钮混在一起。
    ///
    /// 2026-08-19 之前它是底部面板上方那个全宽 64pt 红色 `PrimaryButton`：与「结束服务」
    /// 「取消订单」同一个组件、同一个宽度、同样落在拇指自然区，而且面板高度按内容自适应，
    /// 于是它的垂直位置**会上下漂移**。对标产品无一例外把安全入口做成地图角落的悬浮图标
    /// （见 `docs/research/volunteer-sos-button-placement-20260819.md`）。
    ///
    /// 误触在这一侧撤不回来：后端对志愿者的 `FALSE_ALARM` 恒 403
    /// `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`。所以「远离拇指区」是安全要求，不是观感偏好。
    ///
    /// `blindRunUITests` 里的 `assertEmergencyActionIsUsable` 管的是「点得到」，与本条互补：
    /// 那条防它被挤出可视区，这条防它被挪回操作按钮堆里。
    @MainActor
    func testVolunteerInServiceSOSStaysOutOfTheActionButtonCluster() throws {
        // 有在途订单时**打开 App 就直接进服务页**（设计交付 v3 §4.1 三岔路的第二岔），
        // 不再经过首页那张当前订单卡 —— 那张卡仍然在，只是这条路径上碰不到它了。
        let app = launchVolunteerHome(seedOrderStatus: "IN_PROGRESS")
        XCTAssertTrue(
            app.navigationBars["服务中"].waitForExistence(timeout: 25),
            "冷启动没有直接进服务页"
        )

        let sos = app.buttons["volunteerServiceSOSButton"].firstMatch
        XCTAssertTrue(sos.waitForExistence(timeout: 10), "服务进行中必须提供求助入口")
        XCTAssertLessThan(
            sos.frame.midY,
            app.frame.minY + app.frame.height * 0.4,
            """
            求助按钮中心落在 \(sos.frame.midY)，已经进了屏幕下 60%（拇指自然区）。\
            它此前正是这样和「结束服务」「取消订单」挤在一起、且位置随面板高度漂移的。
            """
        )
        // 志愿者端走 Apple 的 44pt 线（`guard.mjs` 的 `small-touch-target` 显式排除
        // `/blindRun/Volunteer/`），这里量的是别把悬浮按钮做成一个图标大小的点。
        XCTAssertGreaterThanOrEqual(sos.frame.height, 44, "求助按钮触达高度不足 44pt")
        XCTAssertGreaterThanOrEqual(sos.frame.width, 44, "求助按钮触达宽度不足 44pt")

        // 换了形态不等于换了语义：读屏念出来的必须还是那句完整的。
        XCTAssertEqual(sos.label, Self.emergencyActionLabel)
    }

    /// 长按 2 秒结束陪跑 —— 这一条只量**形状**：读屏取得到、触达够大、标签带着「要按多久」。
    ///
    /// 行为那一半在 `blindRunUITests.testMockVolunteerOrderFlowSmoke` 里走指针路径
    /// （`press(forDuration:)`），两条路最终调的是同一个 `VolunteerFinishLongPressButton.fire()`。
    /// **不在这里 `tap()` 再断言订单结束了**：`XCUIElement.tap()` 注入的是物理触摸，
    /// 不经过 accessibility action，而公开 API 里没有「执行默认无障碍动作」的口子 ——
    /// 那样写必红，且红得毫无信息量（元素找得到、`isEnabled` 为真、点完纹丝不动）。
    ///
    /// 文案逐字是什么由 `VolunteerFinishLongPressTests` 钉住，这里不抄 ——
    /// UI 用例里抄中文文案的误报率见记忆 `merged-prs-whose-tests-never-ran`。
    @MainActor
    func testVolunteerFinishEscortControlIsReachableAndBigEnough() throws {
        // 有在途订单时**打开 App 就直接进服务页**（设计交付 v3 §4.1 三岔路的第二岔），
        // 不再经过首页那张当前订单卡 —— 那张卡仍然在，只是这条路径上碰不到它了。
        let app = launchVolunteerHome(seedOrderStatus: "IN_PROGRESS")
        XCTAssertTrue(app.navigationBars["服务中"].waitForExistence(timeout: 25), "冷启动没有直接进服务页")

        let finish = app.descendants(matching: .any)["volunteerFinishEscortButton"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "服务进行中必须给陪跑员结束入口")
        // 63.5 而不是 64：真机量出来是 63.999999999999886 —— `minHeight: 64` 经过一轮
        // 布局取整后的浮点噪声，不是真的矮了。留半点余量仍然分得出 44pt 与 64pt 两档。
        XCTAssertGreaterThanOrEqual(
            finish.frame.height,
            63.5,
            "结束陪跑的触达高度只有 \(finish.frame.height)pt，不足 64"
        )
        XCTAssertFalse(
            finish.label.isEmpty,
            "结束陪跑在无障碍树里没有标签 —— 容器上的 identifier 盖掉子元素时就是这个样子"
        )
        XCTAssertTrue(
            finish.label.contains("2"),
            "标签里没有「按多久」这个数字：\(finish.label)。读屏用户没别的地方能知道要按 2 秒"
        )
    }

    // MARK: - 横屏与宽窗口

    /// 横屏审计。**这是本仓库唯一能验「横屏裁切」的通道** ——
    /// `docs/review/blind-app-full-review-20260812.md` §6 第 11 项（M 档，WCAG 1.3.4）
    /// 说的就是这块：单测覆盖不到布局，而此前 12 条 UI 用例**全部**在 `setUp` 里钉死竖屏，
    /// 于是「横屏一个字都没被验过」和「审计全绿」长期同时成立。
    ///
    /// 审计里真正抓这件事的是 `.textClipped` 与 `.hitRegion`：矮窗口下被装饰地图挤扁的文本、
    /// 被底部常驻条盖住的按钮，都从这两条出来。
    @MainActor
    func testBlindRunnerHomeInLandscapePassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome()
        XCTAssertTrue(
            app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
                .waitForExistence(timeout: 20),
            "盲人首页没起来，后面的审计结果没有意义"
        )
        rotateToLandscape(app)
        try audit(app)
    }

    @MainActor
    func testBlindBookingInLandscapePassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        XCTAssertTrue(waitForBookingScreen(app), "下单页没起来")
        rotateToLandscape(app)
        try audit(app)
    }

    /// 订单状态页横屏。这一页横屏最吃亏：状态卡 + 同行地图（此前写死 180pt）+ 生命周期
    /// 全排在一列里，而横屏可用高度只有约 390pt。
    @MainActor
    func testBlindOrderStatusInLandscapePassesAccessibilityAudit() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit 需要 iOS 17+ 运行时")
        }
        let app = launchBlindHome(emptyOrders: false)
        let currentOrder = app.descendants(matching: .any)["blindRunnerHomeOrderCard"].firstMatch
        XCTAssertTrue(currentOrder.waitForExistence(timeout: 20), "有订单的盲人首页没起来")
        currentOrder.tap()
        // 探针换成骨架的状态卡（2026-09-16）。原来等的是
        // `blindOrderStatusKeepWaitingButton` —— 那个按钮在 `PENDING_MATCH` 已经删掉，
        // 继续等它的话这一页**永远等不到**，而失败信息会写着「订单状态页没起来」，
        // 指向一个根本不存在的故障。状态卡在四步骨架的四态里都有，是更稳的探针。
        XCTAssertTrue(
            app.descendants(matching: .any)["blindOrderFlowStatusCard"].firstMatch
                .waitForExistence(timeout: 15),
            "订单状态页没起来"
        )
        rotateToLandscape(app)
        try audit(app)
    }

    /// 宽窗口下正文列必须收窄，不许铺满整屏。
    ///
    /// 静态审计抓不到这一条：一行横跨 1024pt 的文字**没有任何**审计问题 ——
    /// 有 label、不裁切、对比度达标。它只是让低视力用户把字放大后要横扫整屏，
    /// 换行时找不回下一行的行首（`BlindLayout.readableContentWidth` 里有完整理由）。
    ///
    /// **在 iPhone 横屏上就是真检查，不是只有 iPad 才算数**：iPhone 16 Pro 横屏 852pt，
    /// 已经宽过 700pt 的列宽。前置断言保证窗口真的够宽，否则这条会静默变成空过。
    @MainActor
    func testBlindPagesKeepPrimaryActionsWithinReadableWidthOnWideWindows() throws {
        let app = launchBlindHome()
        let start = app.descendants(matching: .any)["blindRunnerHomeStartBookingButton"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "盲人首页没起来")
        rotateToLandscape(app)

        let windowWidth = app.windows.firstMatch.frame.width
        try XCTSkipUnless(
            windowWidth > Self.readableContentWidth,
            "窗口只有 \(windowWidth)pt，不宽于 \(Self.readableContentWidth)pt —— 这条断言在这台设备上无从判定"
        )

        XCTAssertLessThanOrEqual(
            start.frame.width,
            Self.readableContentWidth,
            "「预约新的陪跑」宽 \(start.frame.width)pt，超过可读列宽 —— 内容列没有收窄"
        )
        // 反向锚一下：收窄不等于收没了。触达下限仍是 64pt（`AGENTS.md` §8，
        // 且 `scripts/hooks/guard.mjs` 的 small-touch-target 在静态面上守同一条）。
        XCTAssertGreaterThanOrEqual(
            start.frame.height,
            Self.minimumBlindPrimaryButtonHeight,
            "横屏收窄之后主按钮被压到 64pt 以下"
        )
        XCTAssertTrue(start.isHittable, "横屏下「预约新的陪跑」够不着")
    }

    // MARK: - Helpers

    /// 转横屏并等布局落定。
    ///
    /// 转完必须等一次：`XCUIDevice.orientation` 的 setter 一返回，SwiftUI 还没重排完，
    /// 立刻断言 `frame` 拿到的是旧值。用 `waitForExistence` 而不是 `sleep` ——
    /// 等的是一次真实的查询往返，快的设备上不会白等满一秒。
    @MainActor
    private func rotateToLandscape(_ app: XCUIApplication) {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock {
            await MainActor.run { XCUIDevice.shared.orientation = .portrait }
        }
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
    }

    /// `BlindLayout.readableContentWidth` 的副本。XCUITest 是黑盒，进不了 app 的类型 ——
    /// 只能抄一份。抄错的方向是安全的：把生产值调**大**而这里没跟，断言会红不会绿。
    private static let readableContentWidth: CGFloat = 700
    private static let minimumBlindPrimaryButtonHeight: CGFloat = 64

    /// 求助按钮按 **accessibilityLabel** 找，不按可见文字 —— 两端的可见文字已经不一样了
    /// （盲人端仍是「一键求助」，志愿者端是圆形盾牌里的「求助」两个字），而读屏念出来的
    /// 必须是同一句。字面量与 `EmergencySafetyCopy.accessibilityLabel` 对齐；
    /// UI 测试 target 拿不到 App 的类型，只能抄一份，改文案时两处一起改。
    private static let emergencyActionLabel = "一键求助，遇到紧急情况时点击"

    /// 盲人端陪跑中那块贴底的求助中心。**与上面那条是两个东西**：
    /// `emergencyActionLabel` 是云端一键求助按钮（志愿者端仍在用），这条是打开求助菜单的入口
    /// —— 按下去什么都还没发出去，所以刻意不叫「一键求助」。
    // ⚠️ 与 `EmergencySafetyCopy.hubAccessibilityLabel` 逐字一致。中文文案漂移
    // `guard.mjs` **抓不到**（实测误报 93%，那条守卫只判 identifier 形状的键），
    // 而本仓库 CI 跑不了 XCTest —— 漂了不会有任何信号，只会在真机上红成
    // 「执行屏没有求助入口」这种指向完全错误的失败信息。
    private static let safetyHubLabel = "求助与安全，打开求助选项"

    // 🗑 `minimumBlindPrimaryButtonScreenShare = 0.25` 已删除（零引用）。
    //
    // 它服务的是 `testBlindRunnerPrimaryButtonDominatesTheScreen`，而那条用例在
    // 2026-09-16 换成了 `testBlindRunnerHomeGivesTheLargestBlockToTheUpcomingOrder`
    // —— 比两块之间的相对大小，不再比固定占屏比。
    //
    // 顺带解决一条长红：固定占屏比在 iPad Air 5（窗口高 820）上永远是 23.7% < 25%，
    // 记忆 `verified-on-one-device-is-not-verified` 记着它连续三次复测一字未变。
    // 那条红的根因不是按钮太小，是**阈值写成了与屏高绑定的固定比例**。

    /// 低版本设备上明确 skip 而不是静默通过 —— 「没跑」和「跑过了」必须可区分。
    @available(iOS 17.0, *)
    private func audit(_ app: XCUIApplication) throws {
        // iOS 侧七个审计类型**全部**启用。少一项就少一类缺陷，而少了哪一项从测试结果上
        // 完全看不出来 —— 用例照样报绿，绿的是剩下那几项。守卫 `a11y-audit-types`
        // 会拦住任何缺项（`scripts/hooks/guard.mjs`）。
        //
        // 2026-09-02 补进 `.textClipped` 与 `.trait`：此前这两项从未启用，而本文件
        // `:560-566` 的注释逐字宣称「审计里真正抓这件事的是 `.textClipped` 与 `.hitRegion`」，
        // 并把三条横屏用例定为「本仓库唯一能验横屏裁切的通道」⇒ 那三条长期在验另外五项，
        // 横屏裁切一次都没被检查过。`.trait` 同样是盲人端硬伤：按钮缺 `.button` trait 时
        // VoiceOver 不念「按钮」，用户不知道那是个能点的东西。
        try app.performAccessibilityAudit(
            for: [
                .contrast, .dynamicType, .elementDetection, .hitRegion,
                .sufficientElementDescription, .textClipped, .trait
            ]
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
        //
        // `blindRunnerHomeAuxiliaryMap` 已于 2026-08-14（`30b0770`）随「盲人首页装饰地图对读屏隐藏」
        // 一起删除，不再需要白名单 —— 死条目会让人以为这一项还在被放行。
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
    /// - Parameter seedOrderStatus: 把那张种子订单直接钉在某个 `RunOrderStatus` 的 raw value 上
    ///   （例 `"IN_PROGRESS"`）。要验服务进行中的页面时用它，别去点订单页底部那三个 mock 按钮 ——
    ///   那要先滚到最底、连点三次，慢且是误触的温床。只在 `emptyOrders: false` 时有意义。
    @MainActor
    private func launchBlindHome(
        forcingVoiceStage: Bool = false,
        emptyOrders: Bool = true,
        forcingFirstRunHelp: Bool = false,
        seedOrderStatus: String? = nil
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
        if let seedOrderStatus {
            app.launchEnvironment["AIDRUN_UI_TEST_SEED_ORDER_STATUS"] = seedOrderStatus
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
    /// - Parameter seedOrderStatus: 同 `launchBlindHome` 的同名参数。传非空值时一并置上
    ///   `PRESEEDED_VOLUNTEER_ACTIVE_ORDER`，让志愿者首页确实认这张单为「当前订单」。

    /// 🔴 **志愿者首屏的影响力区必须渲染出东西来。**
    ///
    /// 钉的是一个真机上发生过、而单测完全照不到的缺陷：那一块原来写成
    /// `Group { if let summary = ..., summary.isRenderable { content } }`，
    /// 条件不成立时整个 Group 解析成空，而 **`.task` 挂在空子树上不会触发** ——
    /// 于是 `summary` 永远是 nil ⇒ 永远渲染空 ⇒ 永远不加载。
    /// 单测直接调 `loadIfNeeded()`，绕过了视图，所以一路全绿而线上什么都没有。
    ///
    /// 2026-09-14 首屏改版后这条缺陷的复发面**更大**了（新首屏全是条件卡片），
    /// 所以用例跟着搬到新结构上，而不是随旧结构一起删掉。
    @MainActor
    func testVolunteerHomeShowsTheIncentiveCard() {
        let app = launchVolunteerHome()

        // 前提断言：首屏本身确实渲染了。少了这条，下面那条失败时分不清是
        // 「影响力区没渲染」还是「整屏都没渲染」。
        let identityRow = app.descendants(matching: .any)["volunteerProfileIdentityRow"]
        XCTAssertTrue(identityRow.waitForExistence(timeout: 25), "首屏整体没出来 —— 这不是影响力区的问题")
        XCTAssertTrue(
            app.staticTexts["我的陪伴"].waitForExistence(timeout: 20),
            "分区标题都没有 —— 这不是影响力区的问题"
        )

        let card = app.descendants(matching: .any)["volunteerHomeIncentiveCard"]
        let loading = app.descendants(matching: .any)["volunteerHomeIncentiveLoading"]
        let failure = app.descendants(matching: .any)["volunteerHomeIncentiveFailure"]

        // 三态**必有其一**。一个都没有 = 视图压根没渲染，就是那个 `.task` 缺陷复发了。
        let anyState = card.waitForExistence(timeout: 20) || loading.exists || failure.exists
        XCTAssertTrue(anyState, "「我的陪伴」三种状态一个都没出现 —— .task 没触发，影响力区把自己锁死了")

        // Mock 环境下数据是齐的，应该落在正式内容那一态。
        XCTAssertTrue(card.exists, "Mock 数据齐全时应该渲染正式内容，实际落到了占位态")
        XCTAssertTrue(
            app.descendants(matching: .any)["volunteerHomeIncentiveAchievementsLink"].exists,
            "「查看服务成就」必须在合成元素之外，否则 VoiceOver 点不到"
        )
    }

    /// 🔴 **滑动开启「可服务」必须给辅助技术留一个标准 action。**
    ///
    /// VoiceOver / Switch Control / Voice Control 会彻底改变用户的物理交互方式，
    /// 很多人根本不触碰屏幕（Apple Developer Forums 线程 729098）——
    /// 只有裸拖拽手势的话，这一屏唯一的主操作对他们等于不存在。
    ///
    /// 实现走 `.accessibilityRepresentation { Button(…) }`：无障碍树里是一枚普通按钮，
    /// 而指针路径仍然只有滑动。**验红方式**：删掉那个 modifier，元素退回 `.other`，
    /// `app.buttons[...]` 立刻找不到，这条必挂。
    ///
    /// 🔴 **这条**只**断言无障碍树的形状，不断言点它会怎样** —— 因为 XCUITest 做不到：
    /// `XCUIElement.tap()` 注入的是一次**物理触摸**，落在真实那棵视图上（只有 `DragGesture`），
    /// 根本不经过 accessibility action；公开 API 里也没有「执行默认无障碍动作」这个口子。
    /// 照着写会得到一条**必红且红得毫无信息量**的用例（实测：按钮找得到、`isEnabled` 为真，
    /// 而 tap 之后开关纹丝不动）。
    ///
    /// 「按下去真的会开」由下面那条拖拽用例覆盖 —— 两条路径调的是**同一个** `activate()`，
    /// 所以「按钮在」+「`activate()` 是对的」合起来就是这条要求的完整覆盖。
    @MainActor
    func testAvailabilitySliderExposesAStandardActionToAssistiveTech() {
        // 默认 `preseedVolunteerAvailable` 为真，那会渲染成「进入接单」那一枚 —— 要的是关闭态。
        let app = launchVolunteerHome(available: false)

        let slider = app.buttons["向右滑动，开始接单"]
        XCTAssertTrue(
            slider.waitForExistence(timeout: 25),
            "滑动 CTA 在无障碍树里不是按钮 —— 不触碰屏幕的用户没有任何办法开启可服务开关"
        )
        XCTAssertTrue(slider.isEnabled, "资质已通过的志愿者，这枚按钮必须是可用的")
        // 关闭态下**不许**出现开启态那枚按钮：那会让读屏用户听到一枚此刻没有意义的按钮。
        XCTAssertFalse(app.buttons["进入接单"].exists, "关闭态不该同时暴露开启态的按钮")
    }

    /// 向右拖过 20% 真的会开启并进入接单主页；向左拖过 35% 真的会停止接单。
    ///
    /// 🔴 **双向滑块是 2026-09-17 产品拍板的结果**，它推翻了此前「关闭是普通点按」那一条
    /// （依据是 Uber 司机下线挽留被 NYT 点名的 dark pattern）。被推翻的只有**手势**：
    /// 关闭路径上仍然不许有任何挽留或确认弹窗，所以下面那条 `alerts.count == 0` 保留。
    ///
    /// 🔴 **这条只能走指针路径**：`XCUIElement.tap()` 注入的是物理触摸，不经过
    /// accessibility action，所以「停止接单」那个自定义动作在 XCUITest 里调不到
    /// （记忆 `xcuitest-cannot-invoke-accessibility-actions`）。形状由上一条断，行为由这条断。
    @MainActor
    func testSlidingRightOpensAvailabilityAndSlidingLeftStopsIt() {
        let app = launchVolunteerHome(available: false)

        let slider = app.descendants(matching: .any)["volunteerAvailabilitySlider"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 25), "滑动 CTA 没渲染出来")

        // 从滑块位置横着拖到轨道右端。开启阈值是 20%，拖到 95% 有足够余量。
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            )

        // 开启那一下同时进入接单主页（设计交付 v3 的流程）。返回之后才看得到滑块的开启态。
        let hubPill = app.descendants(matching: .any)["volunteerDispatchHubAcceptingPill"].firstMatch
        XCTAssertTrue(hubPill.waitForExistence(timeout: 20), "滑过阈值后没有开启，或者没有进入接单主页")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let enterHub = app.buttons["进入接单"]
        XCTAssertTrue(enterHub.waitForExistence(timeout: 15), "回到首页后滑块应当是开启态")

        // 反方向：从右端拖到左端。停止阈值是 35%，拖到 5% 有足够余量。
        let openSlider = app.descendants(matching: .any)["volunteerAvailabilitySlider"].firstMatch
        openSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: openSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            )

        XCTAssertTrue(
            app.buttons["向右滑动，开始接单"].waitForExistence(timeout: 15),
            "向左滑没有停止接单"
        )
        XCTAssertEqual(app.alerts.count, 0, "停止接单不得弹任何挽留对话框")
    }

    /// 首屏徽章区那个「全部 N 枚 ›」入口。滚到它为止再返回。
    ///
    /// ⚠️ 标题里带**枚数**（`全部 3 枚`），所以只能按 `accessibilityLabel` 找，不能按可见文字找。
    /// 那个 label 的单一来源是 `VolunteerHomeIncentiveCopy.achievementsLinkTitle`。
    @MainActor
    private func achievementsEntry(_ app: XCUIApplication) -> XCUIElement {
        let entry = app.descendants(matching: .any)["查看服务成就"].firstMatch
        if entry.waitForExistence(timeout: 20) { return entry }
        var drags = 0
        while !entry.exists && drags < 8 {
            app.swipeUp()
            drags += 1
        }
        return entry
    }

    @MainActor
    private func launchVolunteerHome(
        seedOrderStatus: String? = nil,
        available: Bool = true
    ) -> XCUIApplication {
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
        if available {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] = "1"
        }
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] = "1"
        app.launchEnvironment["AIDRUN_UI_TEST_DISABLE_MAP"] = "1"
        if let seedOrderStatus {
            app.launchEnvironment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_ACTIVE_ORDER"] = "1"
            app.launchEnvironment["AIDRUN_UI_TEST_SEED_ORDER_STATUS"] = seedOrderStatus
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
        // 触发一次 interruption monitor。敲顶部地图区 —— 志愿者首页那一层同样不接受点击，
        // 是这一页唯一保证不触发任何动作的地方。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        return app
    }
}
