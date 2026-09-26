import SwiftUI
import UIKit

// MARK: - Blind Runner Flow Palette

extension AppColors {
    /// 盲人端首页与单页订单流程（匹配 / 约好 / 出发 / 汇合）的专属色板。
    ///
    /// **为什么不并进 `AppColors.tones`**：那张表验的是「这个色**当前景**压在
    /// `systemBackground` 与 `secondarySystemBackground` 上」，而这里绝大多数取值是**表面色**
    /// （深蓝卡片底、黄色主按钮底、浅红求助底）。硬塞进去只会得到一条方向反了的断言 ——
    /// `AppColors.voiceStageSurface` 已经为同一件事留过一段注释，这里沿用那个办法：
    /// 取值单独暴露成 `Tone`，配对关系由 `FlowPaletteContrastTests` 按**真实的前景/背景组合**逐条验。
    ///
    /// ⚠️ 改这里任何一个取值，先跑 `FlowPaletteContrastTests` —— 它在亮/暗两套下各验
    /// 13 组文字（≥4.5:1）、3 组压色块的文字、3 组控件边界（≥3:1），并附 4 条验红。
    ///
    /// **设计稿有三处取值没有原样采用**，每一处都算过数：
    ///
    /// 1. `textTertiary #8C93A3`（原本给「出发 / 汇合」这类未到达步骤的文字）压在白卡上只有
    ///    **3.08:1**，WCAG 1.4.3 正文阈值是 4.5。未到达步骤的文字因此并到 `secondaryText`
    ///    （6.11:1），**状态差异全部交给蓝色节点与字重承担** —— 那两条线索本来就更强。
    /// 2. `helpStroke #F4C3BE` 压在自身填充上只有 **1.37:1**，而填充 `#FDECEC` 压页面底
    ///    `#F2F3F6` 是 **1.03:1** ⇒ 设计稿画了一圈描边，而它在低视力用户眼里不存在，
    ///    于是「求助与安全」退化成一段悬空的红字、没有按钮形状。改 `#C25A4E`（3.78 / 3.89）。
    ///    严格讲 WCAG 1.4.11 对**自带达标文字标签**的控件豁免边界比（W3C Understanding
    ///    原文），所以这一条的依据不是规范而是**设计意图 + 低视力可发现性**：作者画了边界，
    ///    那条边界就该看得见。同一条论证 `AppColors.activeRunDestructive` 已经写过一遍。
    /// 3. 主按钮文字**不能**用 `textPrimary`。它是跟随外观的动态色，暗色档是白色，
    ///    压在固定的 `#F6C343` 黄底上只有 **1.64:1**。黄底亮暗同值 ⇒ 它的前景也必须固定，
    ///    见 `onCTA`。这是「顺手复用 textPrimary」的必然结果，`FlowPaletteContrastTests`
    ///    有一条验红专门挡它。
    ///
    /// **刻意不验的一类**：卡片 / 预约块 / 主按钮的「填充对页面底」比值（亮色 1.13～1.50，
    /// 暗色 1.36～1.80）。两个理由，缺一条都不成立：
    /// ① W3C Understanding 1.4.11 对自带 ≥4.5:1 文字标签的控件明确豁免边界比，而这三块
    ///    分别有 52pt / 24pt / 18pt 的达标标签；iOS 自己的分组列表白卡压 `#F2F2F7` 也只有 1.06:1。
    /// ② 它在暗色下**构造上不可能达标** —— 深色品牌表面要保住白字 ≥4.5 就必然贴近页面底，
    ///    两个要求方向相反。写成断言只会逼出一个牺牲白字可读性的取值。
    ///    这三块的边界由设计稿的两层阴影承担（见 `FlowMetrics.cardShadow`）。
    enum Flow {

        // MARK: 表面

        /// 页面底。暗色不用纯黑之外的值：白卡 `surface` 与它的关系照搬 iOS 自己的
        /// `systemBackground` / `secondarySystemBackground` 分层。
        ///
        /// 亮色 2026-09-26 随陪跑员订单页 v2 从 `#F4F5F8` 改 `#F2F3F6`（交付包 01 `ground`）。
        static let pageTone = Tone(light: 0xF2F3F6, dark: 0x000000)
        static let page = flowDynamic(pageTone)

        /// 卡片底（订单页状态卡与信息列表卡、标签栏）。
        static let surfaceTone = Tone(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let surface = flowDynamic(surfaceTone)

        /// 分隔线。纯装饰，不承载状态，所以不设对比度门槛。
        static let separator = flowDynamic(Tone(light: 0xEEF0F4, dark: 0x38383A))

        /// 邀请卡背后那层压暗（storyboard-v3.html `.dim{background:rgba(15,20,35,.42)}` 逐字）。
        ///
        /// 亮暗同值：它压的是 App 自己的界面，而「背景压暗但仍可见」是设计稿点名要的效果
        /// （`png/02-新邀请进来.png` 的注解：「从底部升起，背景压暗但仍可见」）。
        /// 暗色档再加深会变成一块看不出后面还有东西的黑布。
        ///
        /// 2026-09-18 起由自定义 overlay 自己画 —— 此前是 `.sheet` 的系统压暗。
        static let scrim = Color(red: 15 / 255, green: 20 / 255, blue: 35 / 255).opacity(0.42)

        // MARK: 文字

        /// 亮色 2026-09-26 从 `#111A2E` 改 `#151A26`（交付包 01 `ink`，压白 17.39 / 压页面底 15.67）。
        static let primaryTextTone = Tone(light: 0x151A26, dark: 0xFFFFFF)
        static let primaryText = flowDynamic(primaryTextTone)

        /// 次要文字：列表左侧标签、状态副标题、**以及未到达步骤的文字**（见类型注释第 1 条）。
        ///
        /// 「增强对比度」打开时并到 `primaryText`，与 `HighContrastText` 同一个办法 ——
        /// 亮色 5.51:1（压页面底）过 4.5 但余量不大，用户显式要求增强时给到 AAA 那一档。
        /// 判断做在 `UIColor` 的 trait 闭包里，所以调用点零成本、也不会漏。
        /// 亮色 2026-09-26 从 `#5E6679` 改 `#5B6272`（交付包 01 `inkSecondary`，压白 6.11）。
        static let secondaryTextTone = Tone(light: 0x5B6272, dark: 0xAEAEB2)
        static let secondaryText = flowDynamic(secondaryTextTone, highContrast: primaryTextTone)

        /// 强调蓝：进度条已完成/当前节点、雷达中心、加号圆底。
        static let accentTone = Tone(light: 0x2A5BD7, dark: 0x0A84FF)
        static let accent = flowDynamic(accentTone)

        /// 未到达节点的描边、进度线底色。
        ///
        /// 纯装饰：进度信息由「蓝色节点 + 文字 + 字重」三重冗余承载，且整条进度条合成
        /// **一个**无障碍元素并把「第 N 步，共 4 步」写进标签。所以这两个取值保留设计稿原值
        /// （1.40 / 1.25），不进任何断言 —— 把它们提到 3:1 会让「没走到」看起来像「走到了」。
        static let nodeStroke = flowDynamic(Tone(light: 0xD5DAE3, dark: 0x48484A))
        /// 暴露成 `Tone` 是因为下面那条「回复进度条」的断言要按名字取它当背景 ——
        /// 抄一份字面量的话这里改了色，那条断言照样绿。
        static let progressTrackTone = Tone(light: 0xE2E6EE, dark: 0x3A3A3C)
        static let progressTrack = flowDynamic(progressTrackTone)

        // MARK: 邀请卡的回复进度条（设计交付 v3 §4.4.2 第 3 项）

        /// 剩余时间不多时，进度条从品牌蓝转「深黄」。
        ///
        /// ⚠️ **设计稿给的 `#D99A00` 没有原样采用** —— 它压在进度条底 `#E2E6EE` 上只有
        /// **1.96:1**（WCAG 1.4.11 非文本门槛 3:1），而同一条进度条平时用的蓝 `#2A5BD7`
        /// 是 4.69。也就是说照设计稿改色之后，「时间快到了」这个转折在低视力用户眼里
        /// 是**进度条消失**，不是变黄。改 `#9C6F00`（3.58）。
        /// 这是 FlowPalette 类型注释里那份「设计稿取值没有原样采用」清单的第 4 条。
        ///
        /// 暗色档设计稿没给（§1.2 只要求给提示条和「接单中」补暗色值，进度条这一处是
        /// §4.4.2 独有的）。`#F0B429` 压暗轨 `#3A3A3C` 是 6.09。
        static let replyProgressUrgentTone = Tone(light: 0x9C6F00, dark: 0xF0B429)
        static let replyProgressUrgent = flowDynamic(replyProgressUrgentTone)

        /// 同一时刻那行「还剩 X 秒回复」的文字色（设计稿 `#8A5A00`，压白卡 5.93 ⇒ 原样采用）。
        /// 暗色档同样要自己补：`#8A5A00` 压暗卡 `#1C1C1E` 只有 2.87。
        static let replyUrgentTextTone = Tone(light: 0x8A5A00, dark: 0xF0B429)
        static let replyUrgentText = flowDynamic(replyUrgentTextTone)

        // MARK: 雷达（匹配态视觉区，纯装饰）

        static let radarOuter = flowDynamic(Tone(light: 0xF6F8FE, dark: 0x16203A))
        static let radarOuterStroke = flowDynamic(Tone(light: 0xE3EAFA, dark: 0x22304F))
        static let radarInner = flowDynamic(Tone(light: 0xEEF3FD, dark: 0x1B2745))
        static let radarInnerStroke = flowDynamic(Tone(light: 0xDCE5FA, dark: 0x28375A))

        // MARK: 陪跑员头像

        /// 白卡上的头像底。
        static let avatarBackgroundTone = Tone(light: 0xDCE6FB, dark: 0x2A3C78)
        static let avatarBackground = flowDynamic(avatarBackgroundTone)

        /// 头像里的姓氏。亮色是蓝字压浅蓝底（4.69:1），暗色是白字压深蓝底（10.42:1）——
        /// 两套的前景不是同一个语义色，所以单独一个 `Tone`，不复用 `accent`。
        static let avatarInitialTone = Tone(light: 0x2A5BD7, dark: 0xFFFFFF)
        static let avatarInitial = flowDynamic(avatarInitialTone)

        // MARK: 首页深蓝订单卡

        /// 深蓝卡底。
        ///
        /// 暗色**不能沿用亮色的 `#15224A`**：它压在纯黑页面上只有 1.36:1，整张卡会化进背景。
        /// `#203570` 白字仍有 11.64:1，而对黑底 1.80:1 —— 看得出是一块卡。
        /// （3:1 在这里构造上不可达，理由见类型注释末段。）
        ///
        /// 亮色 2026-09-26 随陪跑员订单页 v2 从 `#15224A` 改 `#1B2657`（交付包 01 `navy`，
        /// 白字 14.37:1）。它同时是盲人端首页深蓝卡的底 —— 那边的变化是同一个产品方向，不是副作用。
        static let navyTone = Tone(light: 0x1B2657, dark: 0x203570)
        static let navy = flowDynamic(navyTone)

        /// 深蓝卡上的次要文字（「下一次陪跑，已约好」、陪跑经验行）。亮暗同值 —— 底色是品牌
        /// 深色表面，前景跟着变反而会在其中一套上失配。「增强对比度」时提到纯白。
        static let onNavySecondaryTone = Tone(light: 0xB8C3E6, dark: 0xB8C3E6)
        static let onNavySecondary = flowDynamic(onNavySecondaryTone, highContrast: Tone(light: 0xFFFFFF, dark: 0xFFFFFF))

        /// 深蓝卡上的地点文字。比 `onNavySecondary` 亮一档，理由是它带图标、是一行独立信息。
        static let onNavyTertiaryTone = Tone(light: 0xDCE3F5, dark: 0xDCE3F5)
        static let onNavyTertiary = flowDynamic(onNavyTertiaryTone)

        /// 深蓝卡上的头像底（白字）。
        static let navyAvatarTone = Tone(light: 0x2A3C78, dark: 0x2A3C78)
        static let navyAvatar = flowDynamic(navyAvatarTone)

        // MARK: 首页浅蓝预约块

        static let bookingBackgroundTone = Tone(light: 0xDDE8FC, dark: 0x14294D)
        static let bookingBackground = flowDynamic(bookingBackgroundTone)

        /// 预约块标题。亮色是深蓝字压浅蓝底，暗色是白字压深蓝底。
        static let bookingTitleTone = Tone(light: 0x15224A, dark: 0xFFFFFF)
        static let bookingTitle = flowDynamic(bookingTitleTone)

        static let bookingSubtitleTone = Tone(light: 0x3D4F80, dark: 0xC3D2F0)
        static let bookingSubtitle = flowDynamic(bookingSubtitleTone, highContrast: bookingTitleTone)

        // MARK: 主按钮（黄）

        /// 黄底亮暗同值：它是「当前最重要的那一个动作」的唯一标记，跟随外观变化会让这条
        /// 线索在两套外观里强弱不一。
        static let ctaTone = Tone(light: 0xF6C343, dark: 0xF6C343)
        static let cta = flowDynamic(ctaTone)

        /// 黄底上的文字。**固定深色，不用 `primaryText`** —— 见类型注释第 3 条。
        static let onCTATone = Tone(light: 0x111A2E, dark: 0x111A2E)
        static let onCTA = flowDynamic(onCTATone)

        /// 倒计时那三秒里主按钮的底色（设计稿 `#FBE6AE`）。亮暗同值，理由同 `cta`。
        ///
        /// 🔴 **不是 `cta.opacity(...)`。** 透明度会把 `onCTA` 一起淡掉，而「准备中」
        /// 那四个字是这三秒里按钮唯一的语义载体 —— 淡成多少、压在页面底上还剩多少对比度，
        /// 都不可控。取具名色之后 `onCTA` 压在它上面是 **14.06:1**，`.disabled()`
        /// 自带的系统减淡怎么算都还在 4.5 以上（`FlowPaletteContrastTests` 钉住这一条）。
        static let ctaDisabledTone = Tone(light: 0xFBE6AE, dark: 0xFBE6AE)
        static let ctaDisabled = flowDynamic(ctaDisabledTone)

        // MARK: 「求助与安全」按钮（浅红）

        /// 浅红填充。**实心红只留给求助中心里的「紧急求助」**（AGENTS.md §6 / 设计意图
        /// 第 1.7 条）：入口醒目，但不能让人以为按一下就报警。
        static let helpBackgroundTone = Tone(light: 0xFDECEC, dark: 0x3A1A18)
        static let helpBackground = flowDynamic(helpBackgroundTone)

        static let helpTextTone = Tone(light: 0xB42318, dark: 0xFF453A)
        static let helpText = flowDynamic(helpTextTone)

        /// 描边。设计稿原值 `#F4C3BE` 只有 1.37:1，见类型注释第 2 条。
        static let helpStrokeTone = Tone(light: 0xC25A4E, dark: 0xFF453A)
        static let helpStroke = flowDynamic(helpStrokeTone)

        // MARK: 「接单中」胶囊（志愿者接单主页）

        /// 设计交付 v3 §1.2 新增的那一对（底 `#E3F4EA` / 字 `#1C7C45`）。
        ///
        /// 亮色按设计稿原值：`#1C7C45` 压 `#E3F4EA` 实测 **4.58:1** —— 过 4.5，
        /// 但余量只有 0.08，**改动其中任何一个值之前先跑一遍对比度用例**。
        ///
        /// 暗色设计稿没给，按本色板既有做法自己定：底 `#10381F` / 字 `#7BD99E`，**7.63:1**。
        /// **不能沿用亮色那一对** —— `#E3F4EA` 在暗色下是一块几乎纯白的色块，
        /// 而它挂在导航栏右上角，整块会比页面还亮。
        ///
        /// 配对断言在 `FlowDesignSystemTests.testEveryTextPairingClearsTheBodyThresholdInBothAppearances`。
        static let acceptingBackgroundTone = Tone(light: 0xE3F4EA, dark: 0x10381F)
        static let acceptingBackground = flowDynamic(acceptingBackgroundTone)

        static let acceptingTextTone = Tone(light: 0x1C7C45, dark: 0x7BD99E)
        static let acceptingText = flowDynamic(acceptingTextTone)

        // MARK: 已汇合对勾徽标

        /// 亮暗同值：它是一枚**纯图形**（白色对勾，没有文字标签），所以 WCAG 1.4.11 的
        /// 3:1 对它是真适用的 —— 亮色压白卡 4.38:1、暗色压深灰卡 3.89:1，两套都过。
        /// 沿用设计稿原值 `#1F8A4C`；`AppColors.success` 的暗色档 `#30D158` 压白对勾只有
        /// 2.02:1，不能复用。
        static let successBadgeTone = Tone(light: 0x1F8A4C, dark: 0x1F8A4C)
        static let successBadge = flowDynamic(successBadgeTone)

        // 跑步中顶行那颗定位状态点**刻意没有 Flow 版本**，直接用 `AppColors.success`
        // / `.warning`。这里记一笔，免得下一个人照「颜色一律走 Flow」的字面意思又加一对：
        //
        // ① 那两个是**语义色**（好 / 需注意），不是表面色，正是这颗点要表达的东西；
        //    本色板存在的理由恰恰是「它装的是表面色」（见类型注释首段）。
        // ② 它们压白卡是 **5.07:1 / 5.20:1**，压深卡是 8.42 / 8.28，四个方向都过线；
        //    2026-09-16 试过另造一对（`#1F8A4C` / `#B45309`），暗色档反而从 8.42 掉到 3.89。
        //    配对断言在 `FlowDesignSystemTests.testLocationDotStaysVisibleOnTheWhiteCard`。

        // MARK: 描边按钮（次级）

        /// 亮色 2026-09-26 从 `#D5DAE3` 改 `#CDD2DC`（交付包 01 `borderNeutral`）。
        /// 压白 1.52:1 —— 带达标文字标签的控件，按 W3C 1.4.11 豁免，理由同主按钮。
        static let ghostStrokeTone = Tone(light: 0xCDD2DC, dark: 0x48484A)
        static let ghostStroke = flowDynamic(ghostStrokeTone)

        // MARK: 陪跑员订单页 v2（交付包 zhumangpao-handoff/01，2026-09-26）
        //
        // 交付包给的是只有亮色的 `ZColor`；按 design-direction §2「不另起第二套色板」并进这里，
        // 暗色档自己补。配对断言在 `FlowDesignSystemTests.testVolunteerOrderV2PairingsClearTheirThresholds`。
        //
        // 设计稿取值没有原样采用的第 5 条：陪跑员头像底 `#4A76E8` 压白色姓氏只有 **4.16:1**，
        // 改 `#3C6CE6`（4.69）。它压亮色藏青 3.07、压暗色藏青只有 2.48 —— 暗色档两个要求
        // 方向相反、构造上不可达，轮廓比按「自带达标文字标签」豁免（见 `FlowDesignSystemTests`）。

        /// 卡片里的浅块：三宫格底、留言气泡、「一起跑过 N 次」标签。
        static let surfaceSubtleTone = Tone(light: 0xF4F6FA, dark: 0x2C2C2E)
        static let surfaceSubtle = flowDynamic(surfaceSubtleTone)

        /// 浅蓝底：图标圆底、快捷回复按钮底、「待认证」标签底。
        static let blueTintTone = Tone(light: 0xE6EDFC, dark: 0x1B2A4F)
        static let blueTint = flowDynamic(blueTintTone)
        /// 压在 `blueTint` 上的蓝字（「待认证」）。6.98 / 7.89。
        static let bluePressedTone = Tone(light: 0x1F47AD, dark: 0xA9C1FF)
        static let bluePressed = flowDynamic(bluePressedTone)
        /// 压在 `blueTint` 上的深字（快捷回复按钮）。亮色是藏青（12.24），暗色白字（14.09）。
        static let onBlueTintTone = Tone(light: 0x1B2657, dark: 0xFFFFFF)
        static let onBlueTint = flowDynamic(onBlueTintTone)

        /// 藏青头卡上的三档字。亮暗同值 —— 底是品牌深色表面，理由同 `onNavySecondary`。
        /// 压亮 / 暗两档 navy：小标题 7.30 / 5.91，副文 9.45 / 7.66，强调 11.31 / 9.16。
        static let onNavyEyebrowTone = Tone(light: 0xAEB8DA, dark: 0xAEB8DA)
        static let onNavyEyebrow = flowDynamic(onNavyEyebrowTone, highContrast: Tone(light: 0xFFFFFF, dark: 0xFFFFFF))
        static let onNavyBodyTone = Tone(light: 0xC9D1EC, dark: 0xC9D1EC)
        static let onNavyBody = flowDynamic(onNavyBodyTone, highContrast: Tone(light: 0xFFFFFF, dark: 0xFFFFFF))
        static let onNavyStrongTone = Tone(light: 0xDCE4FB, dark: 0xDCE4FB)
        static let onNavyStrong = flowDynamic(onNavyStrongTone)

        /// 引导绳上的两枚头像（深色主题）。白色姓氏压在上面：4.69 / 8.29。
        static let volunteerDotTone = Tone(light: 0x3C6CE6, dark: 0x3C6CE6)
        static let volunteerDot = flowDynamic(volunteerDotTone)
        static let runnerDotTone = Tone(light: 0x3B4A8A, dark: 0x3B4A8A)
        static let runnerDot = flowDynamic(runnerDotTone)
        /// 深色主题的绳子（压藏青 5.40）与虚线 / 出发地小圈（纯装饰，2.05）。
        static let ropeOnNavyTone = Tone(light: 0x7C9CF2, dark: 0x7C9CF2)
        static let ropeOnNavy = flowDynamic(ropeOnNavyTone)
        static let mutedOnNavy = flowDynamic(Tone(light: 0x4B587F, dark: 0x4B587F))
        /// 「跑者已到入口附近」胶囊里的圆点。胶囊有文字，圆点是冗余线索。
        static let presenceGreen = flowDynamic(Tone(light: 0x6BE79C, dark: 0x6BE79C))

        /// v2 主按钮的 1.5pt 描边与暖色阴影（交付包 D14）。压页面底 2.07 ——
        /// 按钮自带 10.6:1 的文字标签，边界比按 W3C 1.4.11 豁免；描边的作用是强光下的形状线索。
        static let ctaStrokeTone = Tone(light: 0xD9A21E, dark: 0xD9A21E)
        static let ctaStroke = flowDynamic(ctaStrokeTone)

        /// 金色：汇合光环、完成时的绳子、快迟到时的主角数字（压 navy 8.76 / 7.10）。
        /// 与 `cta` 同值但语义不同 —— 一个是「现在按这个」，一个是「时间 / 汇合」的强调。
        static let goldTone = Tone(light: 0xF6C343, dark: 0xF6C343)
        static let gold = flowDynamic(goldTone)

        /// 跑者留言卡与快迟到提醒条。标题 7.36 / 8.90，正文 12.56 / 11.88。
        static let warmCardTone = Tone(light: 0xFFF4D6, dark: 0x3A2E0A)
        static let warmCard = flowDynamic(warmCardTone)
        static let warmCardTitleTone = Tone(light: 0x6B4A00, dark: 0xF5CF6B)
        static let warmCardTitle = flowDynamic(warmCardTitleTone)
        static let warmCardBodyTone = Tone(light: 0x3A2B00, dark: 0xFFF1CC)
        static let warmCardBody = flowDynamic(warmCardBodyTone)

        /// **仅装饰**：邀请态虚线、未约好的跑者头像描边与姓氏。不能承载信息
        /// （`decorMutedInk` 压白只有 3.16）—— 邀请态的「还没约好」由读屏标签与虚线形状承担。
        static let decorMuted = flowDynamic(Tone(light: 0xC3C9D5, dark: 0x48484A))
        static let decorMutedInk = flowDynamic(Tone(light: 0x8A91A2, dark: 0x8E8E93))

        // MARK: 底部标签栏

        /// 选中的标签。走 SwiftUI 的 `.tint()`，所以要 `Color`。
        static let tabSelectedTone = Tone(light: 0x15224A, dark: 0xFFFFFF)
        static let tabSelected = flowDynamic(tabSelectedTone)

        // 未选中态**没有** `Color` 版本：SwiftUI 到 iOS 16 没有对应的修饰符，
        // 只能走 `UITabBarAppearance`，而那里要的是 `UIColor`。
        // 构造在 `BlindRunnerTabView.applyTabBarAppearance()`，直接读下面那个 `Tone`。

        /// 未选中的标签。
        ///
        /// 照设计稿取 `#6B7385`（压白底 **4.76:1**）顺手修掉一个真实缺陷：
        /// **iOS 默认的未选中灰 `#8E8E93` 压白底只有 3.26:1**，够不到正文阈值 4.5。
        /// 标签栏文字是 13pt 的小字，对低视力用户是全屏最难认的一处。
        ///
        /// 暗色**不能沿用** `#6B7385`：压在标签栏底 `#1C1C1E` 上只有 3.58:1。
        /// 改用已在 `AppColors.tones` 里验过的 `textSecondary` 暗色档 `#AEAEB2`（7.69:1）。
        static let tabUnselectedTone = Tone(light: 0x6B7385, dark: 0xAEAEB2)
    }

    /// `Tone` → 跟随外观（并可选跟随「增强对比度」）的 `Color`。
    ///
    /// 不复用 `AppColors.dynamic`：那个是 `private`，且不接 `accessibilityContrast`。
    /// 增强对比度做在这里而不是调用点，是因为调用点有几十处，漏一处没有任何症状。
    fileprivate static func flowDynamic(_ tone: Tone, highContrast: Tone? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let effective = traits.accessibilityContrast == .high ? (highContrast ?? tone) : tone
            return UIColor(rgb: isDark ? effective.dark : effective.light)
        })
    }
}
