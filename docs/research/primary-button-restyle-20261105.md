# 主按钮与次要按钮样式（#749）

日期：2026-11-05。问题：负责人评全 App 的主按钮 `PrimaryButton`（全宽、64pt、圆角 12、实心深蓝）是「一个蓝色方块，非常丑」。苹果自带 App 在 iOS 26/27 上怎么画同功能按钮？哪些能用在助盲跑上？

本轮只补 [`apple-premium-minimal-ui-20261101.md`](./apple-premium-minimal-ui-20261101.md) 缺的那一段（按钮的形状、次要按钮的画法、iOS 26 的玻璃按钮 API）。那份报告的 HIG 摘录与对比度数字仍可用。

## 1. 结论

1. **「方块感」主要来自形状，不是颜色。** iOS 26 起苹果把手机上靠近屏幕边缘的按钮统一成胶囊形（半径 = 高度的一半），并让按钮离屏幕边缘多留一点。我们的按钮是 64pt 高、12pt 圆角，圆角只占高度的 19%，看起来就是一块方砖。
2. **次要按钮苹果用浅色底，不用描边。** 健康「共享」页是一个实心蓝胶囊（与他人共享）配一个浅蓝底蓝字胶囊（请求他人共享）。我们的次要按钮是 2pt 蓝色描边。
3. **系统玻璃按钮 `.glassProminent` 不能直接用。** 它只在 iOS 26 起可用（我们部署 iOS 16），而且外观随背后内容变，对比度没法用一个固定值钉住。系统的 `.controlSize(.extraLarge)` 在 iPhone 上等于 `.large`，高度够不到 64pt。⇒ 仍用自定义 `ButtonStyle`，只照搬苹果的形状和层级。
4. **同一屏最多一到两个醒目按钮**（HIG 原文）。下单页现在有两块实心蓝（下一步、重复当前状态），属于页面用法问题，与组件样式分开问。
5. **暗色主按钮白字 3.65:1**，现在靠「20pt 粗体算大字、门槛 3:1」过线（`PrimaryButton.swift` 注释）。若底色调深到 `#0A6FE0`，白字 4.81:1，不再依赖大字例外；底色压黑底 4.36:1，仍过 3:1。这是新颜色，要负责人点头并补 `LowVisionChannelTests`。

## 2. 一手来源（2026-11-05 读原文）

| 来源 | 原话要点 | 怎么取的 |
|---|---|---|
| Apple HIG Buttons（最后更新 2025-12-16「Updated guidance for Liquid Glass」） | 最可能的操作用醒目样式；"Keep the number of prominent buttons to one or two per view"；用样式而不是尺寸区分主次；自定义按钮必须有按下态；危险操作不给主按钮角色 | `developer.apple.com/tutorials/data/design/human-interface-guidelines/buttons.json`（网页是动态加载，见记忆 `hig-page-needs-json-endpoint`） |
| 同页 visionOS 一节 | "In general, prefer circular or capsule-shape buttons. People's eyes tend to be drawn toward the corners in a shape" —— 只写在 visionOS 下，iOS 节没有对应条款，只作理由参考 | 同上 |
| WWDC25 session 356「Get to know the new design system」逐字稿 | "Capsules use a radius that's half the height of the container"；"For phone layouts, use a capsule with extra margin to create space near the screen edge" | `developer.apple.com/videos/play/wwdc2025/356/` |
| SwiftUI 文档 | `glassProminent` 引入于 iOS 26.0；`buttonSizing(_:)` 引入于 iOS 26.0；`ControlSize.extraLarge` 在 visionOS 以外解析为 `large`；`ButtonBorderShape.capsule` 引入于 iOS 15.0 | `developer.apple.com/tutorials/data/documentation/swiftui/<符号>.json` |

## 3. 苹果 App 同功能按钮（负责人 iPhone，iOS 27，真机截图）

截图含负责人个人数据，只存本机 `~/Documents/aidrun-design-archive/2026-11-05-buttons/ref-apple/`，不进仓库。下表的尺寸是在 1206×2622 像素截图上量的，除以 3 得 pt。

| App · 页面 | 时刻 | 按钮 | 量到的 |
|---|---|---|---|
| 健康 · 心理健康问卷（底部「完成」） | 提交一份表单 | 底部固定，全宽胶囊，玻璃材质；没答完时是灰色玻璃 | 高约 50pt，左右各距屏幕约 23pt |
| 健康 · 共享 | 主操作 + 次操作 | 「与他人共享」实心蓝胶囊；「请求他人共享」浅蓝底蓝字胶囊；两枚同宽同高 | 胶囊，内容区内居中 |
| 健身 · 共享 | 开始一个流程 | 「开始使用」实心荧光绿胶囊、深色字（暗色页面） | 全宽胶囊 |
| 健康 · 医疗急救卡（首次） | 卡片内的入口 | 小号实心蓝胶囊「开始使用」 | 按内容收窄 |
| 健康 · 编辑信息（弹层） | 弹层里的确认 | 右上角蓝色圆形玻璃 ✓（工具栏按钮，我们的审计过不了，见记忆 `sheet-toolbar-text-button-fails-audit`） | — |

共同点：主按钮都是胶囊；次要按钮是同形状、同尺寸、浅色底；没有一枚是圆角矩形。

## 4. 对比度（WCAG 相对亮度公式，本轮算）

| 前景 / 背景 | 亮 | 暗 |
|---|---|---|
| 白字 / 主色 `primary`（`#0058C7` / `#0A84FF`） | 6.52 | 3.65（靠大字门槛 3:1） |
| 白字 / 候选暗色主色 `#0A6FE0` | — | 4.81 |
| 主色字 / 主色 12% 浅底（压白底） | 5.41 | — |
| 主色字 / 主色 12% 浅底（压分组灰底 `#F2F2F7`） | 4.89 | — |
| `#0A84FF` 字 / 主色 18% 浅底（压 `#1C1C1E`） | — | 3.75 ✗ |
| `#409CFF` 字 / 主色 18% 浅底（压 `#1C1C1E` / 压黑） | — | 4.83 / 6.33 |
| 浅底 / 页面底（按钮外形） | 1.2 左右 | 1.1–1.2 |

⚠️ 浅底次要按钮的外形对页面只有约 1.2:1。WCAG 1.4.11 对自带达标文字的控件豁免外形对比度，但 `OutlineSecondaryButtonStyle` 的注释写明「低视力用户靠轮廓认出这是能按的」。所以次要按钮若改浅底，建议保留一圈细描边，这一点请负责人在稿上定。

## 5. 没查到 / 没做

- iOS 27 的 HIG 没有单独的「按钮尺寸表」（iOS 节只给 44pt 下限），50pt 是从截图量的，不是官方数字。
- 没有找到 Liquid Glass 按钮的同行评审对比度研究；Infinum 的审计（11-01 报告）仍是唯一第三方数字。
- 无障碍 App 的大按钮：10-28 报告（`copy-tone-benchmark-20261028.md`）已覆盖 Be My Eyes / Aira / Seeing AI 的按钮文案与层级，本轮没有新增。
