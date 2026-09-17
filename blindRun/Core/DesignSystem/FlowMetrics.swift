import SwiftUI

// MARK: - Blind Runner Flow Metrics

/// 盲人端首页与单页订单流程的尺寸规格。取值来自设计稿 `design-reference/order-flow/`
/// 的 `home.html` 与 `prototype.html`（CSS 是精确值的唯一源，截图只是它的渲染）。
///
/// **两处刻意不照抄设计稿**：
///
/// 1. **按钮高度 58 → 64。** 本仓库的触达下限是 64pt（`AGENTS.md` §8、
///    `docs/05-page-specs.md` 多处 SHALL、`scripts/hooks/guard.mjs` 的 `small-touch-target`），
///    比 WCAG 2.5.5 的 44pt 更严，理由是视障用户靠手指扫过屏幕找控件 —— 按不中在盲人端
///    的表现是「点了没反应」。守卫的注释里记着六处 44～52pt 的历史缺陷，全在盲人自己要按
///    的路径上。两个按钮的间距从 10 提到 12 吸收这 12pt 的增量。
/// 2. **信息列表里**可点**的行从 52 提到 64**，纯展示行保留 52。同一条理由。
///    判据是「这一行按下去会发生事情吗」，不是「它看起来像不像按钮」。
///
/// 其余一律是设计稿原值。**不要为了像素一致把字号写死** —— 字号全部走
/// `FlowFont`（`@ScaledMetric` 驱动），用户调大字号后高度自然增长。
enum FlowMetrics {

    // MARK: 页面

    /// 页面左右边距。卡片在设计稿里是 `margin: 8px 16px 0`。
    static let pageHorizontalPadding: CGFloat = 16

    // MARK: 圆角

    /// 订单页卡片（`.card{border-radius:24px}`）。
    static let orderCardRadius: CGFloat = 24
    /// 首页卡片与预约块（`border-radius:26px`）。
    static let homeCardRadius: CGFloat = 26
    /// 按钮（`.btn{border-radius:17px}`）。**不随高度 58→64 等比放大** ——
    /// 17 是设计稿给的绝对值，按 64/58 缩放到 18.8 只会让两处按钮的圆角对不齐。
    static let buttonRadius: CGFloat = 17
    /// 深蓝卡底部那条半透明「打开订单」条（`border-radius:14px`）。
    static let navyFooterRadius: CGFloat = 14

    // MARK: 阴影（两层叠加）

    /// 设计稿：`box-shadow: 0 1px 2px rgba(17,26,46,.04), 0 4px 16px rgba(17,26,46,.04)`。
    ///
    /// ⚠️ CSS 的 `blur` 与 SwiftUI 的 `radius` **不是同一个量**：SwiftUI 的 radius 约等于
    /// blur 的一半。所以 2px → 1、16px → 8。直接把 2 和 16 填进 `radius` 会得到两倍模糊，
    /// 卡片看起来像浮在半空。
    ///
    /// 这两层阴影不是装饰：类型注释里说明了卡片「填充对页面底」的对比度**刻意不设断言**，
    /// 而阴影就是那条边界的承担者。删阴影等于让卡片在低视力用户眼里消失。
    struct ShadowLayer {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    /// 贴近卡片的那层（CSS `0 1px 2px`）。
    static let cardShadowNear = ShadowLayer(color: shadowInk, radius: 1, y: 1)
    /// 扩散的那层（CSS `0 4px 16px`）。
    static let cardShadowFar = ShadowLayer(color: shadowInk, radius: 8, y: 4)

    /// 两层用**具名常量而不是数组**：`.shadow()` 是修饰符，没法按运行时集合迭代套用，
    /// 而按下标取（`cardShadow[0]`）会在有人改数组长度时静默越界或错层。
    private static let shadowInk = Color(red: 17 / 255, green: 26 / 255, blue: 46 / 255).opacity(0.04)

    // MARK: 进度条

    static let stepperTopPadding: CGFloat = 16
    static let stepperHorizontalPadding: CGFloat = 20
    static let stepperBottomPadding: CGFloat = 14
    /// 节点直径。**不是触达目标** —— 整条进度条合成一个不可点的无障碍元素。
    static let stepNodeDiameter: CGFloat = 22
    /// 当前步骤节点里的实心圆点。
    static let stepNodeDotDiameter: CGFloat = 9
    static let stepNodeStrokeWidth: CGFloat = 2
    static let stepConnectorHeight: CGFloat = 2
    /// 单个步骤（节点 + 文字）的列宽。
    static let stepColumnWidth: CGFloat = 48

    // MARK: 状态卡视觉区

    /// 雷达 / 头像所在的方形区域。
    static let visualSide: CGFloat = 124
    /// 头像圆直径。
    static let avatarDiameter: CGFloat = 92
    /// 已汇合对勾徽标。
    static let successBadgeDiameter: CGFloat = 32
    static let successBadgeRingWidth: CGFloat = 3
    /// 出发态的进度环线宽。
    static let progressRingWidth: CGFloat = 4
    /// 状态标题距视觉区的间距。
    static let statusTitleTopSpacing: CGFloat = 10

    // MARK: 跑步中（③）

    /// 顶行「陪跑中 · 张伟」左侧那枚小头像。**与视觉区那枚 ⌀92 是同一个视图**
    /// （`matchedGeometryEffect`），所以两个直径必须都在这里，不能一个写死在视图里。
    static let partnerAvatarDiameter: CGFloat = 28
    /// 顶行的内边距（设计稿 `padding 14/18`）。
    static let partnerRowVerticalPadding: CGFloat = 14
    static let partnerRowHorizontalPadding: CGFloat = 18
    /// 里程那个巨数字的字距（设计稿 `letter-spacing: -2`）。
    ///
    /// **负字距只给这一个数字。** 82pt 的等宽数字默认间距在 390pt 宽的屏幕上会让
    /// 「10.00」顶到两边留白，而这一屏的全部意义就是这个数字一眼可读。
    static let runDistanceTracking: CGFloat = -2
    /// 时长 / 配速两格之间那条 1pt 竖分隔线的高度。
    static let runMetricDividerHeight: CGFloat = 44
    /// 顶行右侧那颗定位状态点。纯装饰、对读屏隐藏，所以不受 64pt 触达线约束。
    static let locationDotDiameter: CGFloat = 8

    // MARK: 信息列表

    /// 纯展示行的最小高度（设计稿 52）。
    static let infoRowDisplayMinHeight: CGFloat = 52
    /// **可点**行的最小高度。设计稿是 52，这里提到 64，见类型注释第 2 条。
    static let infoRowTappableMinHeight: CGFloat = 64
    /// 陪跑员行（两行值：姓名 + 经验）。
    static let volunteerRowMinHeight: CGFloat = 74
    static let infoRowHorizontalPadding: CGFloat = 18

    // MARK: 底部操作区

    /// 主按钮与「求助与安全」的最小高度。设计稿 58，见类型注释第 1 条。
    static let actionButtonMinHeight: CGFloat = 64
    /// 两个按钮之间的间距。设计稿 10，提到 12 以吸收 58→64 的增量。
    static let actionButtonSpacing: CGFloat = 12

    // MARK: 首页

    // MARK: 邀请卡（设计交付 v3 §4.4.2，取值来自 storyboard-v3.html 的 `.offer` 一族 CSS）

    /// `.offer{border-radius:22px 22px 0 0}` —— **只上两角**，卡本身就是 sheet、贴底。
    static let inviteSheetRadius: CGFloat = 22
    /// `.offer{padding:14px 16px 24px}`。
    static let inviteSheetTopPadding: CGFloat = 14
    static let inviteSheetHorizontalPadding: CGFloat = 16
    static let inviteSheetBottomPadding: CGFloat = 24
    /// `.offer{gap:8px}`。**不是 16** —— 均匀的 16 是这张卡此前读起来像一堵墙的主因之一。
    static let inviteRowSpacing: CGFloat = 8
    /// `.op{margin-top:-4px}`：地点贴住时间，两者成一组。
    static let invitePlaceOverlap: CGFloat = -4
    /// `.offer .grab{width:36px;height:4px}`。自己画，取代 `presentationDragIndicator`
    /// —— 自定义 overlay 没有系统那一枚。
    static let inviteGrabWidth: CGFloat = 36
    static let inviteGrabHeight: CGFloat = 4
    /// `.m3{border-radius:12px;padding:9px 4px}`。
    static let inviteMetricTileRadius: CGFloat = 12
    static let inviteMetricTileVerticalPadding: CGFloat = 9
    static let inviteMetricTileHorizontalPadding: CGFloat = 4
    /// `.orun .av{width:32px;height:32px}`。
    static let inviteAvatarDiameter: CGFloat = 32
    /// `.two{padding:0 18px}`。
    static let inviteSecondaryActionInset: CGFloat = 18
    /// 卡最多占容器多高。超过就内部滚动 —— AX5 下一张完整的卡装不进一屏，
    /// 而这一屏的每个字都要能看见（`.presentationDetents` 的 `.large` 那一档原本干的就是这件事）。
    static let inviteSheetMaxHeightFraction: CGFloat = 0.92
    /// 拖动收起的阈值（竖向）。
    static let inviteDismissDragDistance: CGFloat = 100
    /// 拖动翻页的阈值（横向）。比收起小 —— 翻页是可逆的，收起也不算回复，两者都不危险，
    /// 但横滑的自然幅度比竖滑小。
    static let invitePageDragDistance: CGFloat = 60

    static let homeCardPadding: CGFloat = 22
    /// 深蓝卡底部内边距（设计稿 `padding:22px 22px 18px`）。
    static let homeCardBottomPadding: CGFloat = 18
    static let bookingBlockVerticalPadding: CGFloat = 22
    static let bookingBlockHorizontalPadding: CGFloat = 20
    /// 预约块里的蓝色加号圆。
    static let bookingPlusDiameter: CGFloat = 56
    /// 深蓝卡上的陪跑员头像。
    static let homeVolunteerAvatarDiameter: CGFloat = 44
    /// 深蓝卡底部「打开订单」条的最小高度。它在**整张卡是一个按钮**的结构里属于装饰
    /// （真正的触达目标是整张卡），所以 48 不受 64pt 线约束。
    static let navyFooterMinHeight: CGFloat = 48
}

// MARK: - Dynamic Type 驱动的字号

/// 设计稿给的是 393pt 宽屏幕、默认字号下的绝对值（34 / 52 / 18 / 16 / 15 / 13 …），
/// 而 SwiftUI 在 iOS 16 上没有「系统字体 + 任意字号 + 跟随 Dynamic Type」的直接 API：
/// `Font.system(size:)` **不缩放**，`Font.custom(_:size:relativeTo:)` 只给自定义字体。
///
/// 所以走 `@ScaledMetric(relativeTo:)` 缩放**字号数值**再交给 `Font.system(size:)` ——
/// 这是本仓库 `swiftui-pro/references/accessibility.md` 对 iOS 18 及以前给的做法。
/// 封装成一个 `ViewModifier` 而不是让每个视图各自声明 `@ScaledMetric`：那样有十几处，
/// 漏一处的症状是「这一行字调大字号不变」，而自己不调字号就永远看不见。
///
/// ⛔ **不封顶 Dynamic Type。** 理由同 `HighContrastText`：AX4 / AX5 正是低视力用户实际会
/// 设的档位，封顶等于把最后两级从目标用户手里拿走。风险因此转移到布局上，由
/// `blindRunUITests/AccessibilityAuditTests` 的 `.dynamicType` 与 `.textClipped` 审计守门。
private struct FlowFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let usesMonospacedDigit: Bool

    init(size: CGFloat, weight: Font.Weight, relativeTo textStyle: Font.TextStyle, monospacedDigit: Bool) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.usesMonospacedDigit = monospacedDigit
    }

    func body(content: Content) -> some View {
        content.font(resolvedFont)
    }

    private var resolvedFont: Font {
        let base = Font.system(size: size, weight: weight)
        // 倒计时与「已等待 01:32」每秒变一次。等宽数字之外的字形宽度不同，
        // 不设等宽会让整行文字随秒数左右抖动 —— 对低视力用户是持续的干扰。
        return usesMonospacedDigit ? base.monospacedDigit() : base
    }
}

extension View {
    /// 设计稿字号 + Dynamic Type 缩放。`relativeTo` 决定缩放速率（不同文字样式的缩放
    /// 曲线不同，见 `docs/research/dynamic-type-scale-20260812.md`），所以必须显式给。
    func flowFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(
            FlowFont(size: size, weight: weight, relativeTo: textStyle, monospacedDigit: monospacedDigit)
        )
    }
}

/// 设计稿里每一处字号的具名落点。**只在这里出现字面量**，视图里一律引用这些常量 ——
/// 同一个数字散在多个视图里，改一次就会漏一处，而「某一行字号不对」没人会发现。
enum FlowFonts {
    /// 首页问候「你好，李明」34 / Semibold。
    static func homeGreeting() -> (CGFloat, Font.Weight, Font.TextStyle) { (34, .semibold, .largeTitle) }
    /// 首页卡片时间「明天 7:00」52 / Semibold / 等宽数字。
    static func homeCardTime() -> (CGFloat, Font.Weight, Font.TextStyle) { (52, .semibold, .largeTitle) }
    /// 首页卡片状态小字 16 / Regular。
    static func homeCardCaption() -> (CGFloat, Font.Weight, Font.TextStyle) { (16, .regular, .callout) }
    /// 首页卡片地点 18 / Regular。
    static func homeCardPlace() -> (CGFloat, Font.Weight, Font.TextStyle) { (18, .regular, .body) }
    /// 首页卡片陪跑员姓名 17 / Semibold，以及底部「打开订单」条。
    static func homeCardRowTitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (17, .semibold, .body) }
    /// 首页卡片陪跑员经验行 14 / Regular。
    static func homeCardRowDetail() -> (CGFloat, Font.Weight, Font.TextStyle) { (14, .regular, .subheadline) }
    /// 首页预约块标题 24 / Semibold。
    static func bookingTitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (24, .semibold, .title2) }

    // MARK: 邀请卡（`.offer` 一族 CSS 的逐条落点）

    /// 🔴 **这一组是邀请卡专用，不要拿去别处，也不要用 `homeCardXxx` 顶替。**
    ///
    /// 2026-09-18 之前这张卡借用 `homeCardRowTitle()`(17) / `homeCardPlace()`(18)，
    /// 于是时间 : 地点 = 28 : 18 ≈ **1.55×**，而稿子是 28 : 12.5 ≈ **2.24×** ——
    /// 每一行字号都差不多，读起来是一堵墙而不是「一个大字 + 一堆安静的小字」。
    /// 项目负责人的原话是「看着非常僵硬」。
    ///
    /// 那两个 token **不能改**：`BlindHomeCards.swift:89/112/145` 也在用，
    /// 改一处会把盲人端首页卡一起改掉。所以另开一组。
    ///
    /// 字号仍然全走 `@ScaledMetric`：12.5 是**默认档**的基准值，用户调大字号照常长大。
    /// 基准偏小带来的 AX5 截断风险由 `AccessibilityAuditTests` 的 `.textClipped` 审计守门。

    /// `.oh b` —— 标题行「N 个新邀请」。
    static func inviteHeader() -> (CGFloat, Font.Weight, Font.TextStyle) { (12.5, .bold, .footnote) }
    /// `.oh span` —— 「还剩 X 秒回复」。
    static func inviteCountdown() -> (CGFloat, Font.Weight, Font.TextStyle) { (11.5, .regular, .caption) }
    /// `.ot` —— 那行大字时间。**800 不是 600**：稿子写的就是 `font-weight:800`，
    /// 而 SF 在 28pt 上 heavy 与 semibold 的差别是这张卡层级感的一半。
    /// 比订单页的 `statusTitle()`（34）小 —— 那是一整页的主角，这是一张贴底的卡。
    static func inviteTime() -> (CGFloat, Font.Weight, Font.TextStyle) { (28, .heavy, .title) }
    /// `.op` —— 集合点名称。
    static func invitePlace() -> (CGFloat, Font.Weight, Font.TextStyle) { (12.5, .regular, .footnote) }
    /// `.m3 b` / `.m3 b small` / `.m3 span` —— 三格的值、单位、标签。
    static func inviteMetricValue() -> (CGFloat, Font.Weight, Font.TextStyle) { (17, .bold, .body) }
    static func inviteMetricUnit() -> (CGFloat, Font.Weight, Font.TextStyle) { (10.5, .regular, .caption2) }
    static func inviteMetricLabel() -> (CGFloat, Font.Weight, Font.TextStyle) { (10, .regular, .caption2) }
    /// `.orun b` / `.orun span` —— 跑者行。
    static func inviteRunnerName() -> (CGFloat, Font.Weight, Font.TextStyle) { (13, .bold, .footnote) }
    static func inviteRunnerDetail() -> (CGFloat, Font.Weight, Font.TextStyle) { (10.5, .regular, .caption2) }
    /// `.two` —— 底部两个文字按钮。
    static func inviteSecondaryAction() -> (CGFloat, Font.Weight, Font.TextStyle) { (13, .semibold, .footnote) }
    /// 首页预约块副标题 15 / Regular。
    static func bookingSubtitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (15, .regular, .subheadline) }
    /// 订单页状态标题 34 / Semibold / 等宽数字。
    static func statusTitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (34, .semibold, .largeTitle) }
    /// 订单页状态副标题 16 / Regular。
    static func statusSubtitle() -> (CGFloat, Font.Weight, Font.TextStyle) { (16, .regular, .callout) }
    /// 列表左侧标签 15 / Regular。
    static func rowLabel() -> (CGFloat, Font.Weight, Font.TextStyle) { (15, .regular, .subheadline) }
    /// 列表右侧值 16 / Medium。
    static func rowValue() -> (CGFloat, Font.Weight, Font.TextStyle) { (16, .medium, .callout) }
    /// 陪跑员姓名 16 / Semibold。
    static func rowValueEmphasized() -> (CGFloat, Font.Weight, Font.TextStyle) { (16, .semibold, .callout) }
    /// 陪跑员经验行 13 / Regular。
    static func rowDetail() -> (CGFloat, Font.Weight, Font.TextStyle) { (13, .regular, .footnote) }
    /// 进度条文字 13。当前步骤 Semibold，其余 Regular。
    static func stepLabel(isCurrent: Bool) -> (CGFloat, Font.Weight, Font.TextStyle) {
        (13, isCurrent ? .semibold : .regular, .footnote)
    }
    /// 按钮文字 18 / Semibold。
    static func actionButton() -> (CGFloat, Font.Weight, Font.TextStyle) { (18, .semibold, .body) }
    /// 按钮标题下面那行小字 13 / Regular。目前只有陪跑员端「长按 2 秒 · 松手取消」用。
    ///
    /// **和 `rowDetail()` 取值相同但不复用它**：那一档的语义是「列表行的次要信息」，
    /// 而这一档是「这枚按钮该怎么按」—— 两者哪天要分开调（比如这行字要更醒目），
    /// 复用会让改一处伤到另一处，而按钮上那行字调没调对没人会发现。
    static func actionButtonHint() -> (CGFloat, Font.Weight, Font.TextStyle) { (13, .regular, .footnote) }
    /// 头像里的姓氏。视觉区那枚 38，首页深蓝卡那枚 18，跑步中顶行那枚 ⌀28 用 13。
    ///
    /// 三档按**直径**分，不按调用点：同一个 `FlowAvatar` 在三个地方用，
    /// 让调用点各传一个字号必然会漂 —— 而「小头像里的字挤成一坨」不会有任何东西报警。
    static func avatarInitial(diameter: CGFloat) -> (CGFloat, Font.Weight, Font.TextStyle) {
        if diameter >= FlowMetrics.avatarDiameter { return (38, .semibold, .title) }
        if diameter >= FlowMetrics.homeVolunteerAvatarDiameter { return (18, .semibold, .title) }
        return (13, .semibold, .footnote)
    }

    // MARK: 跑步中（③）与倒计时（②）

    /// 里程。**全屏最大字号**，等宽数字。
    ///
    /// 🔴 基准取 **82 不是 70**。设计包里这个数字自相矛盾：README 写「82（基准 70）」，
    /// 清单 §22 写「70×1.76＝123」，§23 写「123→101（`minimumScaleFactor(0.7)`）」。
    /// 123×0.7＝86 ≠ 101，而 **82×1.76＝144、144×0.7＝101** —— 只有 82 能同时满足
    /// §23 给的两个数，所以 §22 那句是旧值。
    static func runDistance() -> (CGFloat, Font.Weight, Font.TextStyle) { (82, .semibold, .largeTitle) }
    /// 里程下方的时长 / 配速。
    static func runMetric() -> (CGFloat, Font.Weight, Font.TextStyle) { (36, .semibold, .title) }
    /// 三个数字各自的标签。里程的标签 16、时长配速的标签 15（设计稿两档不同）。
    static func runPrimaryLabel() -> (CGFloat, Font.Weight, Font.TextStyle) { (16, .regular, .callout) }
    static func runSecondaryLabel() -> (CGFloat, Font.Weight, Font.TextStyle) { (15, .regular, .subheadline) }
    /// 顶行「陪跑中 · 张伟」。
    static func partnerHeadline() -> (CGFloat, Font.Weight, Font.TextStyle) { (15, .semibold, .subheadline) }
    /// 倒计时那三个数字，压在 ⌀92 的品牌蓝实心圆上。
    static func countdownNumber() -> (CGFloat, Font.Weight, Font.TextStyle) { (52, .semibold, .largeTitle) }
}

extension View {
    /// `FlowFonts` 的元组直接喂给 `flowFont`，省掉每个调用点解元组。
    func flowFont(_ spec: (CGFloat, Font.Weight, Font.TextStyle), monospacedDigit: Bool = false) -> some View {
        flowFont(size: spec.0, weight: spec.1, relativeTo: spec.2, monospacedDigit: monospacedDigit)
    }
}
