# 01 · 设计常量与通用组件（iOS / SwiftUI）

画板按 390×844pt 设计。以下取值直接用 pt。画板里的 Manrope / 思源黑体只是示意，**实现用系统字体**：数字用 SF Pro Rounded，中文用苹方（系统默认）。

## 颜色

```swift
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum ZColor {
    // 底与文字
    static let ground        = Color(hex: 0xF2F3F6) // 页面底
    static let surface       = Color(hex: 0xFFFFFF) // 卡片
    static let surfaceSubtle = Color(hex: 0xF4F6FA) // 卡片内的浅块、气泡、标签
    static let divider       = Color(hex: 0xECEEF2)
    static let borderNeutral = Color(hex: 0xCDD2DC) // 次要按钮描边、白色色块描边
    static let ink           = Color(hex: 0x151A26) // 正文
    static let inkSecondary  = Color(hex: 0x5B6272) // 次要文字（白底约 6:1）
    static let decorMuted    = Color(hex: 0xC3C9D5) // 仅装饰：虚线、刻度
    static let decorMutedInk = Color(hex: 0x8A91A2) // 仅装饰：未约好的跑者头像字

    // 品牌
    static let navy          = Color(hex: 0x1B2657) // 头卡
    static let blue          = Color(hex: 0x2A5BD7) // 链接、图标、浅色引导绳
    static let bluePressed   = Color(hex: 0x1F47AD)
    static let blueTint      = Color(hex: 0xE6EDFC) // 图标底、快捷回复、标签底

    // 藏青头卡上
    static let onNavyEyebrow = Color(hex: 0xAEB8DA)
    static let onNavyBody    = Color(hex: 0xC9D1EC)
    static let onNavyStrong  = Color(hex: 0xDCE4FB)
    static let volunteerDot  = Color(hex: 0x4A76E8) // 陪跑员头像（深色背景）
    static let runnerDot     = Color(hex: 0x3B4A8A) // 跑者头像（深色背景）
    static let ropeOnNavy    = Color(hex: 0x7C9CF2)
    static let mutedOnNavy   = Color(hex: 0x4B587F) // 虚线、出发地小圈
    static let presenceGreen = Color(hex: 0x6BE79C) // "李明已到入口附近"的圆点

    // 主按钮与暖色
    static let yellow        = Color(hex: 0xF6C343)
    static let yellowBorder  = Color(hex: 0xD9A21E)
    static let onYellow      = Color(hex: 0x1E1A0B)
    static let gold          = Color(hex: 0xF6C343) // 汇合光环、完成时的绳子
    static let warmCard      = Color(hex: 0xFFF4D6) // 跑者留言卡
    static let warmCardTitle = Color(hex: 0x6B4A00)
    static let warmCardBody  = Color(hex: 0x3A2B00)
    static let urgent        = Color(hex: 0xD99A00) // 沿用 v3：剩余 <15 分钟、晚到

    // 功能色
    static let helpBg        = Color(hex: 0xFDECEC)
    static let helpInk       = Color(hex: 0xB42318)
    static let successBg     = Color(hex: 0xE3F4EA)
    static let successInk    = Color(hex: 0x1C7C45)
}
```

对比度：`ink`、`inkSecondary` 在白底和 `ground` 上均 ≥4.5:1；`onNavy*` 在藏青上 ≥7:1；`decorMuted` 和 `decorMutedInk` 只能用于装饰，不能承载信息。

## 字体

所有字号必须随动态字体缩放（`@ScaledMetric` 或 `Font.system(size:weight:design:)` 配合 `relativeTo:`）。数字一律等宽：`.monospacedDigit()`。

| Token | 字号 / 字重 | 用途 |
|---|---|---|
| `heroNumberXL` | 80 heavy, rounded | 出发页"8"分钟 |
| `heroNumberL` | 72 heavy, rounded | "15"分钟后出发 |
| `heroNumberM` | 56 heavy, rounded | "6:35" |
| `heroNumberS` | 44 heavy, rounded | 邀请页"周六 7:00" |
| `heroUnit` | 20–22 bold | 主角数字后的单位："出发"、"分钟后到" |
| `title` | 28 heavy | 汇合页"李明就在附近" |
| `title2` | 26 heavy | 完成页关系标题 |
| `headline` | 17 bold | 姓名、主按钮文字 |
| `body` | 16 regular，行高 1.6 | 跑者原话、留言 |
| `callout` | 15 regular / bold | 头卡副文、列表主文字、次要按钮 |
| `subhead` | 14 regular / bold | 卡片小标题、次要说明 |
| `caption` | 13 bold | 仅用于标签（"一起跑过 3 次"、"待认证"） |

主角数字用负字距：80pt 用 −3，56–72pt 用 −2，44pt 用 −1。在 AX 级字号下主角数字的上限为 1.4 倍，其余文字正常缩放（见 02 的"动态字体"一节）。

## 间距与圆角

```swift
enum ZMetric {
    static let screenPadding: CGFloat = 20   // 左右
    static let navHeight: CGFloat = 44
    static let sectionGap: CGFloat = 12      // 卡片之间
    static let cardPadding: CGFloat = 16     // 普通卡片；头卡 20 上下 / 22 左右
    static let radiusCard: CGFloat = 24      // 头卡、内容卡
    static let radiusRow: CGFloat = 20       // 可点的单行卡（集合点、导航）
    static let radiusChip: CGFloat = 16      // 快捷回复、三宫格底、偏好气泡
    static let radiusButton: CGFloat = 17    // 主、次按钮
    static let primaryHeight: CGFloat = 64
    static let secondaryHeight: CGFloat = 56 // 白色次要按钮、响铃按钮、快捷回复
    static let tertiaryHeight: CGFloat = 48  // 汇合页"打电话 / 找不到对方"
    static let textButtonHeight: CGFloat = 44
    static let minTouch: CGFloat = 44
    static let avatarList: CGFloat = 44
    static let iconBubble: CGFloat = 36
}
```

## 通用组件

实现为独立 View，每个都带 SwiftUI Preview。

**`PrimaryButton(title:)`**：高 64，圆角 17，底 `yellow`，1.5pt `yellowBorder` 描边，阴影 `yellowBorder` 28% 不透明度 / y 6 / 模糊 16，文字 17 heavy `onYellow`。按下时缩放到 0.98。**一屏最多一个。**

**`SecondaryButton(title:)`**：高 56，圆角 17，白底，1.5pt `borderNeutral` 描边，文字 16 bold `ink`。

**`TextButton(title:, tone:)`**：高 44，无底色；`tone = .neutral` 为 15 semibold `inkSecondary`（取消类一律用它），`.link` 为 15 bold `blue`。

**`HelpPill`**：导航栏右侧，高 44，圆角 22，左右内边距 14，底 `helpBg`，盾牌图标 16 + 「求助」15 bold `helpInk`。读屏：「求助与安全，按钮」。点击打开现有紧急求助流程。**所有订单页都有，位置不变。**

**`NavBar(title:, showsBack:)`**：高 44，左右各留 84pt 宽的槽（左放返回按钮 44×44，右放 `HelpPill`），标题 16 bold 居中。完成页左侧不放返回。

**`HeroCard(style:)`**：圆角 24，内边距 20 / 22。`style = .navy`（底 `navy`，文字白色）或 `.light`（白底，仅邀请）。内部从上到下依次是：小标题（14 semibold）、`RopeView`、主角区、副文。

**`RopeView(state:, progress:, theme:)`**：见 03。视图框 342×56，按容器宽度等比缩放（头卡内约 306×50）。

**`RunnerCard`**：白色卡片，内含头像 44（底 `blueTint`，姓氏 18 bold `navy`）、姓名 17 bold、说明 14 `inkSecondary`、可选标签「一起跑过 N 次」（13 bold，底 `surfaceSubtle`）、可选跑者留言气泡（底 `surfaceSubtle`，圆角左上 4 / 其余 16，15 regular）、分隔线、「他写给陪跑员」14 bold `inkSecondary` + 原话 16 / 1.6 行高，加中文引号。

**`PlaceRow`**：高 64，圆角 20，白底；左侧 36pt 圆形图标（底 `blueTint`、图标 `blue`），中间两行文字（15 bold + 14 `inkSecondary`），右侧「地图 ↗」15 bold `blue` 或单独一个 ↗ 图标。整行是一个按钮，点击跳转系统地图。

**`QuickReplyGrid`**：白色卡片，标题「一键告诉李明」14 bold `inkSecondary`，下方两列按钮，高 56、圆角 16、底 `blueTint`、字 `navy` 16 bold、左侧声波图标。

**`ClothingSwatches`**：白色卡片，左边「认准他」14 bold，右边两列：34×34 圆角 10 的色块（白色色块加 1.5pt `borderNeutral` 描边）+ 15 bold 名称。

**`DirectionDial`**：见 02 汇合一节与 03。

**`PresencePill`**：底为白色 12% 不透明度，圆角 999，内边距 9 / 14；8pt `presenceGreen` 圆点（外加 4pt 25% 不透明度的光圈）+ 15 bold 白字。

图标用 SF Symbols：`chevron.left`、`shield`、`mappin`、`arrow.up.right`、`location.north.fill`、`waveform`、`phone`、`magnifyingglass`、`clock`、`lock`、`speaker.wave.2`。
