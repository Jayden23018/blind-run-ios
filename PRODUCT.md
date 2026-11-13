# Product

<!-- impeccable:product-schema 1 -->

<!-- 这份文件给 .claude/skills/impeccable 读（它按这里的 Platform 改用 Apple HIG 和原生审计）。
     不是产品需求的源真相：冲突时以 AGENTS.md 和 docs/ 为准，见 AGENTS.md §2。 -->

## Platform

ios

## Users

两类用户，同一个 App 里按角色切换：

- **盲人 / 低视力跑者**：主要靠 VoiceOver 和语音操作，部分用户用最大字号（AX4 / AX5）看屏幕。在这里约陪跑、看订单进度、跑步中求助。
- **陪跑员（志愿者）**：明眼人，常在骑车或小跑中单手扫一眼屏幕。在这里接单、去汇合、陪跑。

## Product Purpose

助盲跑把想跑步的视障跑者和志愿陪跑员配对，管理从约跑、匹配、出发、汇合、陪跑到结束的整个订单流程。

## Operating Context

- 原生 Swift + SwiftUI，部署目标 iOS 16，只上架 iPhone。
- 模拟器永久不可用（高德地图 SDK 没有 arm64 模拟器版本）。截图只能来自真机：`scripts/device-test.sh` 跑完后从 `.xcresult` 导出附件。UI 测试构建没有高德 key，地图区域是占位图，不是生产形态。

## Capabilities and Constraints

- 设计方向、色板、字体、两端差异：`docs/ui/design-direction.md`。设计稿索引：`docs/ui/mockups/INDEX.md`。
- 订单状态、求助（SOS）入口与文案有硬规则，见 `AGENTS.md` §5 §6。求助二次确认文案逐字锁定，不许按「去 AI 味」改写或删减。
- 字体用系统字体（San Francisco）和语义文字样式，不封顶 Dynamic Type（陪跑员订单页主角数字是唯一例外，见 `design-direction.md`）。

## Accessibility & Inclusion

- **触达**：
  - 盲人端关键主按钮 ≥ 64pt（`aidrun-a11y-voice`）。
  - 陪跑员端主按钮和最常按的次要按钮 64pt，其余（两列按钮、文字按钮、求助胶囊）下限 44pt，与 Apple HIG 一致。
- 正文对比度 ≥ 4.5:1，深色和浅色两套都要满足。
- 盲人端无障碍是第一约束：VoiceOver 遍历顺序、读屏标签、语音播报优先于视觉效果。
