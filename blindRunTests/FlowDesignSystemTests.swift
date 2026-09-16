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
