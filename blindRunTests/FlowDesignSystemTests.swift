import SwiftUI
import XCTest
@testable import blindRun

/// 盲人端首页 / 单页订单流程色板与尺寸的检查。
///
/// 与 `LowVisionChannelTests` 的分工：那个文件验 `AppColors.tones` ——「这个语义**前景**色
/// 压在系统的两种背景上」。本文件验的是一套**表面色板**，配对关系是设计稿指定的具体组合
/// （深蓝卡上的三档字、黄底上的黑字、浅红底上的深红字…），塞进 `tones` 会得到方向反了的
/// 断言。理由在 `AppColors.Flow` 的类型注释里写全了。
///
/// 🔴 本文件里的每一条断言都对应设计稿上一个真实的前景/背景组合。**不要为了让某个取值
/// 通过而放宽门槛** —— 设计稿有三处原值算不过，处理办法是换取值（已换），不是降门槛。
final class FlowDesignSystemTests: XCTestCase {

    /// WCAG 1.4.3 正文阈值。与 `LowVisionChannelTests` 同一个数，理由也同一个：
    /// 本 App 的取值同时用在正文和大字上，按严的那条卡。
    private static let textMinimum: Double = 4.5
    /// WCAG 1.4.11 非文本（控件边界、纯图形）阈值。
    private static let nonTextMinimum: Double = 3.0

    // MARK: - 文字压在表面上

    func testEveryTextPairingClearsTheBodyThresholdInBothAppearances() {
        // (前景, 背景, 这一对出现在哪)
        let pairings: [(AppColors.Tone, AppColors.Tone, String)] = [
            (AppColors.Flow.primaryTextTone, AppColors.Flow.surfaceTone, "卡片正文"),
            (AppColors.Flow.primaryTextTone, AppColors.Flow.pageTone, "页面正文"),
            (AppColors.Flow.secondaryTextTone, AppColors.Flow.surfaceTone, "列表左侧标签 / 状态副标题"),
            (AppColors.Flow.secondaryTextTone, AppColors.Flow.pageTone, "页面上的次级文字"),
            (AppColors.Flow.accentTone, AppColors.Flow.surfaceTone, "卡片上的强调文字"),
            (AppColors.Flow.avatarInitialTone, AppColors.Flow.avatarBackgroundTone, "白卡上的头像姓氏"),
            (AppColors.Flow.onCTATone, AppColors.Flow.ctaTone, "主按钮文字"),
            // 倒计时那三秒的「准备中」。它压在浅黄上 14.06:1 —— 留这么多余量是有用的：
            // `.disabled()` 自带的系统减淡我们控制不了，而这四个字是那三秒里
            // 按钮唯一的语义载体。取具名色而不是 `.opacity` 的理由见 `Flow.ctaDisabled`。
            (AppColors.Flow.onCTATone, AppColors.Flow.ctaDisabledTone, "倒计时主按钮文字"),
            (AppColors.Flow.bookingTitleTone, AppColors.Flow.bookingBackgroundTone, "预约块标题"),
            (AppColors.Flow.bookingSubtitleTone, AppColors.Flow.bookingBackgroundTone, "预约块副标题"),
            (AppColors.Flow.helpTextTone, AppColors.Flow.helpBackgroundTone, "求助与安全按钮文字"),
            (AppColors.Flow.onNavySecondaryTone, AppColors.Flow.navyTone, "深蓝卡次要文字"),
            (AppColors.Flow.onNavyTertiaryTone, AppColors.Flow.navyTone, "深蓝卡地点文字"),
            // 亮色只有 4.58:1（余量 0.08），所以这一条必须在表里 —— 设计稿原值就踩着线。
            (AppColors.Flow.acceptingTextTone, AppColors.Flow.acceptingBackgroundTone, "「接单中」胶囊"),
        ]

        for (foreground, background, usage) in pairings {
            assertContrast(foreground.light, background.light, Self.textMinimum, "亮色", usage)
            assertContrast(foreground.dark, background.dark, Self.textMinimum, "暗色", usage)
        }
    }

    /// 压在深色表面上的白字。单独一条是因为前景是字面量 `.white` 而不是某个 `Tone`。
    func testWhiteTextOnBrandSurfacesStaysReadable() {
        let white: UInt32 = 0xFFFFFF
        let surfaces: [(AppColors.Tone, Double, String)] = [
            (AppColors.Flow.navyTone, Self.textMinimum, "首页深蓝卡的 52pt 大字"),
            (AppColors.Flow.navyAvatarTone, Self.textMinimum, "深蓝卡上的头像姓氏"),
            // 对勾是**图形**不是文字，按 1.4.11 的 3:1 卡。
            (AppColors.Flow.successBadgeTone, Self.nonTextMinimum, "已汇合对勾徽标"),
        ]
        for (surface, threshold, usage) in surfaces {
            assertContrast(white, surface.light, threshold, "亮色", usage)
            assertContrast(white, surface.dark, threshold, "暗色", usage)
        }
    }

    // MARK: - 控件边界

    /// 「求助与安全」按钮的描边。
    ///
    /// 这是设计稿唯一一处**真缺陷**：原值 `#F4C3BE` 压在自身填充上 1.37:1，而填充压页面底
    /// 只有 1.05:1 ⇒ 作者画了一圈边界，而它在低视力用户眼里不存在，按钮退化成一段悬空红字。
    ///
    /// 严格讲 W3C Understanding 1.4.11 对自带达标文字标签的控件豁免边界比，所以这一条的
    /// 依据是**设计意图 + 低视力可发现性**而非规范强制。但门槛照 3:1 卡 —— 既然要画边界，
    /// 就画到看得见。
    func testSafetyButtonBorderIsVisibleAgainstBothItsFillAndThePage() {
        let stroke = AppColors.Flow.helpStrokeTone
        let fill = AppColors.Flow.helpBackgroundTone
        let page = AppColors.Flow.pageTone

        assertContrast(stroke.light, fill.light, Self.nonTextMinimum, "亮色", "求助按钮描边 vs 自身填充")
        assertContrast(stroke.dark, fill.dark, Self.nonTextMinimum, "暗色", "求助按钮描边 vs 自身填充")
        assertContrast(stroke.light, page.light, Self.nonTextMinimum, "亮色", "求助按钮描边 vs 页面底")
        assertContrast(stroke.dark, page.dark, Self.nonTextMinimum, "暗色", "求助按钮描边 vs 页面底")

        // 🔴 验红，也是这条用例被写下来的原因：设计稿原值必须真的算不过。
        // 没有这一条，上面四条断言可能是在一个恒真的公式上通过。
        let designOriginal: UInt32 = 0xF4C3BE
        XCTAssertLessThan(
            Self.contrastRatio(designOriginal, fill.light), Self.nonTextMinimum,
            "设计稿原值 #F4C3BE 压在自身填充上不达标，这条用例存在的理由就是挡住照抄它"
        )
    }

    /// 对勾徽标是**纯图形**（没有文字标签），所以 1.4.11 对它是真适用的：
    /// 它压在卡片底上必须看得出是一枚独立的徽标。
    /// 跑步中顶行那颗定位状态点。
    ///
    /// 🔴 这一对是 2026-09-16 **新出现**的组合，此前没有任何断言覆盖它：改版前这一行压在
    /// `AppColors.activeRunSurface`（深灰）上、由 `LowVisionChannelTests` 守着，
    /// 搬到白卡之后那套断言就守不到了。取值本身没换（仍是 `AppColors` 的两个语义色），
    /// **换的是它压在什么上面** —— 而对比度是一对值的属性，不是单个值的属性。
    ///
    /// 按非文本 3:1 卡而不是正文 4.5：状态由旁边的**文字**承担，点是纯装饰的扫读锚点
    /// （`accessibilityHidden(true)`）。实测四个方向都在 5 以上，留了足够余量。
    func testLocationDotStaysVisibleOnTheWhiteCard() throws {
        // 取值与 `AppColors.tones` 同源（:33-34）。这里按名字取而不是抄一份字面量 ——
        // 抄一份的话那边改了色，这边照样绿。
        let table = Dictionary(uniqueKeysWithValues: AppColors.tones.map { ($0.name, $0.tone) })
        let pairs: [(AppColors.Tone, String)] = [
            (try XCTUnwrap(table["success"], "AppColors.tones 里没有 success"), "定位正常那颗点"),
            (try XCTUnwrap(table["warning"], "AppColors.tones 里没有 warning"), "定位信号弱那颗点"),
        ]
        for (dot, usage) in pairs {
            assertContrast(dot.light, AppColors.Flow.surfaceTone.light, Self.nonTextMinimum, "亮色", usage)
            assertContrast(dot.dark, AppColors.Flow.surfaceTone.dark, Self.nonTextMinimum, "暗色", usage)
        }
    }

    func testSuccessBadgeStaysDistinguishableFromTheCardSurface() {
        let badge = AppColors.Flow.successBadgeTone
        let surface = AppColors.Flow.surfaceTone

        XCTAssertEqual(badge.light, badge.dark, "徽标亮暗同值：白对勾的可读性只在这个取值上验过")
        assertContrast(badge.light, surface.light, Self.nonTextMinimum, "亮色", "对勾徽标 vs 卡片底")
        assertContrast(badge.dark, surface.dark, Self.nonTextMinimum, "暗色", "对勾徽标 vs 卡片底")

        // 🔴 验红：`AppColors.success` 的暗色档 `#30D158` 是这里最自然的「顺手复用」，
        // 而白色对勾压上去只有 2.02:1。
        XCTAssertLessThan(
            Self.contrastRatio(0xFFFFFF, 0x30D158), Self.nonTextMinimum,
            "success 的暗色档压白对勾不达标，这条用例存在的理由就是挡住复用它"
        )
    }

    /// 邀请卡那条回复进度条转「深黄」之后，还看不看得见（设计交付 v3 §4.4.2 第 3 项）。
    ///
    /// 🔴 **这条挡的是「照设计稿抄色」。** 设计稿给的 `#D99A00` 压在进度条底 `#E2E6EE` 上
    /// 只有 1.96:1 —— 低视力用户看到的不是「变黄了」，而是**进度条不见了**，
    /// 而这条进度条要传达的正是「时间快到了」。
    func testUrgentReplyProgressStaysVisibleAgainstItsOwnTrack() {
        let fill = AppColors.Flow.replyProgressUrgentTone
        let track = AppColors.Flow.progressTrackTone

        assertContrast(fill.light, track.light, Self.nonTextMinimum, "亮色", "紧迫进度条 vs 进度条底")
        assertContrast(fill.dark, track.dark, Self.nonTextMinimum, "暗色", "紧迫进度条 vs 进度条底")

        // 平时那一档走品牌蓝，同一条断言也要过 —— 不然「变色」会从一个达标态掉进不达标态。
        assertContrast(
            AppColors.Flow.accentTone.light, track.light, Self.nonTextMinimum, "亮色", "常态进度条 vs 进度条底"
        )
        assertContrast(
            AppColors.Flow.accentTone.dark, track.dark, Self.nonTextMinimum, "暗色", "常态进度条 vs 进度条底"
        )

        XCTAssertLessThan(
            Self.contrastRatio(0xD99A00, track.light), Self.nonTextMinimum,
            "设计稿的 #D99A00 压亮轨不达标，这条用例存在的理由就是挡住照抄它"
        )
    }

    /// 同一时刻那行「还剩 X 秒回复」的文字。
    ///
    /// 🔴 验红挡的是**只给亮色档**：设计稿的 `#8A5A00` 压白卡 5.93 达标，
    /// 而同一个值压暗卡只有 2.87 —— 亮暗同值是这里最自然的偷懒写法。
    func testUrgentReplyLabelClearsTheBodyThresholdInBothAppearances() {
        let text = AppColors.Flow.replyUrgentTextTone
        let surface = AppColors.Flow.surfaceTone

        assertContrast(text.light, surface.light, Self.textMinimum, "亮色", "「还剩 X 秒回复」")
        assertContrast(text.dark, surface.dark, Self.textMinimum, "暗色", "「还剩 X 秒回复」")

        XCTAssertLessThan(
            Self.contrastRatio(0x8A5A00, surface.dark), Self.textMinimum,
            "设计稿那个值压暗卡不达标，暗色档必须自己补，不能亮暗同值"
        )
    }

    /// 底部标签栏的两档标签文字，压在标签栏底上。
    ///
    /// 🔴 这条同时修掉一个**系统默认值带来的**缺陷：iOS 未选中态的灰是 `#8E8E93`，
    /// 压白底只有 **3.26:1** —— 而标签栏是 13pt 的小字，对低视力用户是全屏最难认的一处。
    /// 设计稿的 `#6B7385` 是 4.76:1。所以「照设计稿做」在这里同时是「修一个缺陷」。
    ///
    /// 暗色档**不能沿用** `#6B7385`（压标签栏底 `#1C1C1E` 只有 3.58:1）。
    func testTabBarLabelsClearTheBodyThresholdOnTheTabBarSurface() {
        // 标签栏底与卡片同一个表面色（`configureWithDefaultBackground` 给的就是这一档）。
        let surface = AppColors.Flow.surfaceTone
        for (name, tone) in [
            ("选中", AppColors.Flow.tabSelectedTone),
            ("未选中", AppColors.Flow.tabUnselectedTone),
        ] {
            assertContrast(tone.light, surface.light, Self.textMinimum, "亮色", "标签栏\(name)标签")
            assertContrast(tone.dark, surface.dark, Self.textMinimum, "暗色", "标签栏\(name)标签")
        }

        // 🔴 验红两条，缺一条这个用例就可能跑在恒真的公式上：
        // ① 系统默认的未选中灰压白底算不过 —— 这是本条用例存在的理由。
        XCTAssertLessThan(
            Self.contrastRatio(0x8E8E93, surface.light), Self.textMinimum,
            "iOS 默认的未选中灰压白底不达标，所以未选中态必须自己接管取色"
        )
        // ② 亮色那个取值直接搬到暗色也算不过 —— 挡住「两档共用一个值」。
        XCTAssertLessThan(
            Self.contrastRatio(AppColors.Flow.tabUnselectedTone.light, surface.dark), Self.textMinimum,
            "未选中态的亮色档压在暗色标签栏底上不达标，两档必须分开取值"
        )
    }

    /// 邀请卡那块三格数据（`离你 / 跑多远 / 配速`）。
    ///
    /// 2026-09-18 底色从浅蓝 `bookingBackground` 换成**页面灰** `page`，照 storyboard 的
    /// `.m3{background:var(--ui-bg)}`。换底色就得重新算一遍压在它上面的两档文字 ——
    /// 标签那一档只有 10pt，是这张卡上最小的字，走的是正文阈值 4.5 而不是大字的 3.0。
    ///
    /// 🔴 **验红挡的正是「照抄稿子的灰」**：稿子自己那一对（`--ui-sub #6B7180` 压
    /// `--ui-bg #F2F3F7`）只有 **4.38:1**，差一点点。本仓库的 `secondaryText #5E6679`
    /// 压 `page #F4F5F8` 是 5.28，所以这里要用我们自己的取值，不是把 CSS 变量整组搬过来。
    func testInviteMetricTileTextClearsTheBodyThresholdOnThePageGray() {
        let tile = AppColors.Flow.pageTone

        assertContrast(
            AppColors.Flow.primaryTextTone.light, tile.light, Self.textMinimum, "亮色", "三格数值"
        )
        assertContrast(
            AppColors.Flow.primaryTextTone.dark, tile.dark, Self.textMinimum, "暗色", "三格数值"
        )
        assertContrast(
            AppColors.Flow.secondaryTextTone.light, tile.light, Self.textMinimum, "亮色", "三格标签"
        )
        assertContrast(
            AppColors.Flow.secondaryTextTone.dark, tile.dark, Self.textMinimum, "暗色", "三格标签"
        )

        XCTAssertLessThan(
            Self.contrastRatio(0x6B7180, 0xF2F3F7), Self.textMinimum,
            "storyboard 的 --ui-sub 压 --ui-bg 只有 4.38:1，整组照搬 CSS 变量会把 10pt 的标签推到阈值以下"
        )
    }

    // MARK: - 挡住三条「顺手复用」

    /// 设计稿的 `textTertiary #8C93A3` 给的是未到达步骤的文字，而它压在白卡上只有 3.08:1。
    /// 实现里已并到 `secondaryText`。这条验红挡住把它加回来。
    func testDesignTertiaryGrayIsRejectedForStepLabels() {
        XCTAssertLessThan(
            Self.contrastRatio(0x8C93A3, AppColors.Flow.surfaceTone.light), Self.textMinimum,
            "设计稿 textTertiary 压白卡不达正文阈值，未到达步骤的文字必须用 secondaryText"
        )
        // 并到 secondaryText 之后必须真的达标 —— 否则上面那条只是在抱怨，没有给出出路。
        assertContrast(
            AppColors.Flow.secondaryTextTone.light, AppColors.Flow.surfaceTone.light,
            Self.textMinimum, "亮色", "未到达步骤文字（已改用 secondaryText）"
        )
    }

    /// 主按钮的文字**不能**用跟随外观的 `primaryText`：它的暗色档是白色，压在固定的黄底上
    /// 只有 1.64:1。黄底亮暗同值 ⇒ 前景也必须固定。
    func testCTAForegroundIsPinnedInsteadOfFollowingTheAppearance() {
        let cta = AppColors.Flow.ctaTone
        let onCTA = AppColors.Flow.onCTATone

        XCTAssertEqual(cta.light, cta.dark, "黄底刻意不跟随外观，两套必须同值")
        XCTAssertEqual(onCTA.light, onCTA.dark, "黄底固定 ⇒ 它的前景也必须固定")

        // 🔴 验红：`primaryText` 的暗色档（白）压黄底算不过。
        XCTAssertLessThan(
            Self.contrastRatio(AppColors.Flow.primaryTextTone.dark, cta.dark), Self.textMinimum,
            "primaryText 的暗色档压黄底不达标，这条用例存在的理由就是挡住复用它"
        )
    }

    // MARK: - 公式自检

    /// 把已知不达标的取值喂进同一个计算，必须算出不达标；并验公式的上界。
    ///
    /// 没有这一条，上面所有断言在公式写错时会静默全绿 —— 一个恒返回 21 的
    /// `contrastRatio` 能让每条断言通过。
    func testTheContrastFormulaRejectsKnownFailuresAndHitsItsUpperBound() {
        XCTAssertLessThan(Self.contrastRatio(0xFF9500, 0xFFFFFF), Self.textMinimum, "systemOrange 压白底")
        XCTAssertLessThan(Self.contrastRatio(0x007AFF, 0xFFFFFF), Self.textMinimum, "systemBlue 压白底")
        XCTAssertEqual(Self.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.01, "纯黑压纯白是公式上界")
        XCTAssertEqual(Self.contrastRatio(0x777777, 0x777777), 1, accuracy: 0.001, "同色必须是 1:1")
    }

    /// 与 `LowVisionChannelTests` 用的是同一个公式，两处必须算出同一个数 ——
    /// 否则「这个色在那边过了、在这边没过」会被当成取值问题去查，而真因是两份公式漂了。
    func testThisFileAgreesWithTheExistingPaletteCheckOnASharedValue() {
        let textSecondary = AppColors.tones.first { $0.name == "textSecondary" }!.tone
        // `LowVisionChannelTests` 断言它压 `systemBackground`（亮色 #FFFFFF）≥ 4.5。
        assertContrast(textSecondary.light, 0xFFFFFF, Self.textMinimum, "亮色", "AppColors.textSecondary 压白底")
    }

    // MARK: - 陪跑员订单页 v2（交付包 zhumangpao-handoff/01）

    func testVolunteerOrderV2PairingsClearTheirThresholds() {
        let F = AppColors.Flow.self
        let text: [(AppColors.Tone, AppColors.Tone, String)] = [
            (F.bluePressedTone, F.blueTintTone, "「待认证」标签"),
            (F.onBlueTintTone, F.blueTintTone, "快捷回复按钮"),
            (F.onBlueTintTone, F.surfaceSubtleTone, "「一起跑过 N 次」标签"),
            (F.primaryTextTone, F.surfaceSubtleTone, "留言气泡"),
            (F.secondaryTextTone, F.surfaceSubtleTone, "三宫格标签"),
            (F.warmCardTitleTone, F.warmCardTone, "留言卡标题 / 快迟到提醒条"),
            (F.warmCardBodyTone, F.warmCardTone, "留言卡正文"),
            (F.onCTATone, F.ctaTone, "v2 主按钮文字"),
            (F.arrivedInkTone, F.arrivedTintTone, "汇合页响铃按钮"),
        ]
        for (foreground, background, usage) in text {
            assertContrast(foreground.light, background.light, Self.textMinimum, "亮色", usage)
            assertContrast(foreground.dark, background.dark, Self.textMinimum, "暗色", usage)
        }

        // 纯图形（WCAG 1.4.11，3:1）。方位盘在白 / 暗灰卡面上，箭头是它唯一的方向线索。
        let graphics: [(AppColors.Tone, AppColors.Tone, String)] = [
            (F.accentTone, F.blueTintTone, "地点行图标"),
            (F.stateArrivedTone, F.surfaceTone, "方位盘箭头"),
        ]
        for (foreground, background, usage) in graphics {
            assertContrast(foreground.light, background.light, Self.nonTextMinimum, "亮色", usage)
            assertContrast(foreground.dark, background.dark, Self.nonTextMinimum, "暗色", usage)
        }
    }

    /// 头卡用到的四种状态色（v2 C01）。跑步中青绿 / 暂停灰不走这个页面（V4）。
    private static let heroStates: [(AppColors.Tone, String)] = [
        (AppColors.Flow.stateAgreedTone, "约好 / 跑者取消"),
        (AppColors.Flow.stateDepartedTone, "出发"),
        (AppColors.Flow.stateArrivedTone, "汇合"),
        (AppColors.Flow.stateDoneTone, "完成"),
    ]

    /// 彩色头卡上的字是**半透明白**，实际颜色 = 白以 α 叠在状态色上，所以逐色合成后再算。
    /// 交付包说「`onHero*` 在五种状态色上 ≥4.5:1」—— 那句话按原值不成立，见下一条验红。
    func testHeroCardTextClearsTheBodyThresholdOnEveryStateColour() {
        let F = AppColors.Flow.self
        for (state, name) in Self.heroStates {
            for (appearance, bg) in [("亮色", state.light), ("暗色", state.dark)] {
                assertContrast(0xFFFFFF, bg, Self.textMinimum, appearance, "\(name)：主角数字 / 标题")
                assertContrast(Self.white(F.onHeroEyebrowOpacity, over: bg), bg, Self.textMinimum, appearance, "\(name)：小标题")
                assertContrast(Self.white(F.onHeroBodyOpacity, over: bg), bg, Self.textMinimum, appearance, "\(name)：副文")
                // 陪跑员头像：白色实心，姓氏用当前状态色。
                assertContrast(bg, 0xFFFFFF, Self.textMinimum, appearance, "\(name)：陪跑员头像姓氏")
                // 跑者头像：白字压「白 8% 叠状态色」。
                assertContrast(0xFFFFFF, Self.white(F.runnerFillOpacity, over: bg), Self.textMinimum, appearance, "\(name)：跑者头像姓氏")
                assertContrast(Self.white(F.ropeLineOpacity, over: bg), bg, Self.nonTextMinimum, appearance, "\(name)：引导绳")
            }
        }
    }

    /// 金色只当**大字**（80pt 主角数字、20pt 粗体单位、28pt 过点标题）和**图形**（光环、并肩绳），
    /// 所以按 WCAG 大字 / 图形的 3:1 卡。压出发主蓝 4.32 —— 如果哪天它被拿去写正文，这条不够用。
    func testGoldOnlyAppearsAsLargeTextOrGraphicsOnStateColours() {
        let F = AppColors.Flow.self
        for (state, name) in Self.heroStates {
            assertContrast(F.goldTone.light, state.light, Self.nonTextMinimum, "亮色", "金色压\(name)")
            assertContrast(F.goldTone.dark, state.dark, Self.nonTextMinimum, "暗色", "金色压\(name)")
        }
        XCTAssertEqual(F.goldTone.light, 0xFFD978, "C04：与主按钮黄分开")
        XCTAssertNotEqual(F.goldTone.light, F.ctaTone.light)
    }

    /// 验红：交付包原值（小标题白 80%、副文白 86%、跑者填充白 18%）压完成绿都过不了 4.5。
    /// 有人以「恢复设计一致性」为理由改回去时，上面那条会红，而这条说明为什么。
    func testDesignOnHeroOpacitiesAreRejectedOnTheDoneGreen() {
        let done = AppColors.Flow.stateDoneTone.light
        XCTAssertLessThan(Self.contrastRatio(Self.white(0.80, over: done), done), Self.textMinimum, "交付包 onHeroEyebrow")
        XCTAssertLessThan(Self.contrastRatio(Self.white(0.86, over: done), done), Self.textMinimum, "交付包 onHeroBody")
        XCTAssertLessThan(Self.contrastRatio(0xFFFFFF, Self.white(0.18, over: done)), Self.textMinimum, "交付包 runnerFill")
    }

    /// 白色以 `alpha` 叠在 `background` 上（sRGB 空间逐通道混合，与 UIKit 的默认合成一致）。
    private static func white(_ alpha: Double, over background: UInt32) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let channel = Double((background >> UInt32(shift)) & 0xFF)
            let mixed = UInt32((255 * alpha + channel * (1 - alpha)).rounded())
            return result | (mixed << UInt32(shift))
        }
    }

    /// 触达：主 / 次按钮 64（沿用 `actionButtonMinHeight`），辅助动作 ≥44（项目负责人 2026-09-26）。
    func testVolunteerOrderV2AuxiliaryTargetsKeepTheFortyFourFloor() {
        let hig: CGFloat = 44
        XCTAssertGreaterThanOrEqual(FlowMetrics.v2TextButtonMinHeight, hig, "文字按钮 / 求助胶囊")
        XCTAssertGreaterThanOrEqual(FlowMetrics.v2TertiaryMinHeight, hig, "汇合页两列按钮")
        XCTAssertGreaterThanOrEqual(FlowMetrics.v2NavHeight, hig, "导航栏")
        XCTAssertGreaterThanOrEqual(FlowMetrics.v2PlaceRowMinHeight, 64, "地点行是整行按钮，按 64 卡")
    }

    // MARK: - 尺寸

    /// 触达下限。**这条是机器守卫，不是描述** —— 设计稿给的是 58 / 52，实现里刻意提到 64。
    /// 有人以「恢复设计一致性」为理由改回去时，这条会红。
    func testEveryTappableMetricClearsTheSixtyFourPointFloor() {
        let floor: CGFloat = 64
        XCTAssertGreaterThanOrEqual(
            FlowMetrics.actionButtonMinHeight, floor,
            "底部操作按钮低于 64pt。设计稿是 58，但本仓库的触达下限是 64（AGENTS.md §8）"
        )
        XCTAssertGreaterThanOrEqual(
            FlowMetrics.infoRowTappableMinHeight, floor,
            "信息列表可点行低于 64pt。设计稿是 52，但可点就是触达目标"
        )
        XCTAssertGreaterThanOrEqual(
            FlowMetrics.volunteerRowMinHeight, floor,
            "陪跑员行低于 64pt。它在部分状态下承载可点的拨号入口"
        )
        // 纯展示行**不受**这条线约束，它不是触达目标。写成断言是为了说明这不是遗漏：
        // 如果哪天它被改成可点的，上面那条常量才是它该用的。
        XCTAssertLessThan(
            FlowMetrics.infoRowDisplayMinHeight, floor,
            "纯展示行沿用设计稿的 52。它一旦变成可点行，要改用 infoRowTappableMinHeight"
        )
    }

    /// CSS 的 `blur` 与 SwiftUI 的 `radius` 差一倍。设计稿是 `blur: 2` 与 `blur: 16`。
    ///
    /// 这条看着琐碎，但直接填 2 / 16 会得到两倍模糊、卡片像浮在半空 ——
    /// 而卡片阴影是「填充对页面底」对比度**刻意不设断言**时那条边界的唯一承担者。
    /// 🔴 里程字号基准是 **82，不是 70**。
    ///
    /// 设计包自己在这个数上自相矛盾：README 写「82（基准 70）」，清单 §22 写「70×1.76＝123」，
    /// §23 写「123→101（`minimumScaleFactor(0.7)`）」。123×0.7＝86 ≠ 101，
    /// 而 **82×1.76＝144、144×0.7＝101** —— 只有 82 能同时满足 §23 给的两个数。
    /// 没有这条断言，下一个人照 README 那半句改回 70 不会有任何东西变红。
    func testRunDistanceKeepsTheEightyTwoBaselineNotSeventy() {
        XCTAssertEqual(FlowFonts.runDistance().0, 82, "里程基准被改了 —— 82 的推导见本用例注释")
        XCTAssertNotEqual(FlowFonts.runDistance().0, 70, "70 是设计包里的旧值，算不出 §23 的 101")
        // AX5 缩放约 1.76 倍，再乘 minimumScaleFactor(0.7)，落点应当是 §23 写的 101。
        XCTAssertEqual(Int((82 * 1.76 * 0.7).rounded()), 101)
        // 它是全屏最大字号：任何一个别的字号追上它，这一屏的视觉层级就塌了。
        let others = [
            FlowFonts.runMetric().0, FlowFonts.countdownNumber().0,
            FlowFonts.statusTitle().0, FlowFonts.homeCardTime().0,
        ]
        for size in others {
            XCTAssertLessThan(size, FlowFonts.runDistance().0, "里程不再是全屏最大字号")
        }
    }

    func testCardShadowConvertsCSSBlurToSwiftUIRadius() {
        XCTAssertEqual(FlowMetrics.cardShadowNear.radius, 1, "CSS blur 2px → SwiftUI radius 1")
        XCTAssertEqual(FlowMetrics.cardShadowNear.y, 1)
        XCTAssertEqual(FlowMetrics.cardShadowFar.radius, 8, "CSS blur 16px → SwiftUI radius 8")
        XCTAssertEqual(FlowMetrics.cardShadowFar.y, 4)
    }

    // MARK: - 进度条读屏标签

    func testStepperAnnouncesThePositionAndTheCurrentStepName() {
        let titles = ["匹配", "约好", "出发", "汇合"]
        for (index, name) in titles.enumerated() {
            XCTAssertEqual(
                FlowStepper.accessibilityLabel(currentStep: index, titles: titles),
                "进度，第 \(index + 1) 步，共 4 步，\(name)"
            )
        }
    }

    /// 越界的 step 不该产出「第 0 步」或「第 5 步，共 4 步」这种念出来就是错的标签。
    /// 后端加状态、映射表漏一条时落到的就是这里。
    ///
    /// 取值刻意落在**两种实现之间**：夹不夹会得到不同结果。随手取 `currentStep = 1`
    /// 那种「明显该通过」的值，夹逻辑被删掉后用例照样绿。
    func testStepperClampsOutOfRangeStepsInsteadOfAnnouncingNonsense() {
        let titles = ["匹配", "约好", "出发", "汇合"]
        XCTAssertEqual(
            FlowStepper.accessibilityLabel(currentStep: -3, titles: titles),
            "进度，第 1 步，共 4 步，匹配"
        )
        XCTAssertEqual(
            FlowStepper.accessibilityLabel(currentStep: 99, titles: titles),
            "进度，第 4 步，共 4 步，汇合"
        )
        // 空标题不该崩，也不该念出「共 0 步」。
        XCTAssertEqual(FlowStepper.accessibilityLabel(currentStep: 0, titles: []), "进度")
    }

    // MARK: - 辅助

    private func assertContrast(
        _ foreground: UInt32,
        _ background: UInt32,
        _ threshold: Double,
        _ appearance: String,
        _ usage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = Self.contrastRatio(foreground, background)
        XCTAssertGreaterThanOrEqual(
            ratio, threshold,
            "[\(appearance)] \(usage)：#\(String(format: "%06X", foreground)) 压 "
                + "#\(String(format: "%06X", background)) 只有 \(String(format: "%.2f", ratio)):1"
                + "（门槛 \(threshold)）",
            file: file, line: line
        )
    }

    /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
    private static func relativeLuminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let raw = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
