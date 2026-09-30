## Why

陪跑员跑步中页的头卡此前是藏青：#227 落地时 `AppColors.Flow` 没有跑步中青绿，`design-direction.md` 又不许顺手新增强调色，所以先用藏青（归档变更 `restyle-volunteer-running-page-v2` 决策 3，写明「要换青绿需另行拍板」）。项目负责人 2026-09-30 拍板：保持跑步中页现状，**启用**交付包 v2 C01 的青绿 `#0A6B72`。这样订单页各状态的头卡色才成套：约好藏青 · 出发主蓝 · 汇合琥珀 · 跑步中青绿 · 暂停灰 · 完成绿。

## What Changes

- `AppColors.Flow` 新增 `stateRunning`（`#0A6B72`，亮暗同值，与其他状态色一致）。
- 跑步中头卡从藏青改成 `stateRunning`；暂停仍是 `statePaused`。
- 头卡对比度用例把 `stateRunning` 纳入逐色覆盖，并补一条断言钉住它的色值（管不到视图层是否取用，见 design.md 决策 4）。
- 文档同步：`docs/ui/design-direction.md` §6.1、`docs/ui/mockups/INDEX.md`（跑步中一行「待确认」→「Current」，去掉冲突 1）、`docs/ui/mockups/volunteer-order-page-v2/DECISIONS-v2.md`（V4 作废、新增 V19）。
- **不改**：跑步中页布局与功能（节奏卡、暂停、提示条、求助面板、长按结束）；锁屏实时活动卡（FE-2，PR #231，它在 widget 目标里自带一份色板）。

## Capabilities

### New Capabilities

### Modified Capabilities
- `volunteer-running-page`：「跑步中使用 v2 页面且不显示地图」一条里，头卡由「藏青」改为「青绿」。

## Impact

- `blindRun/Core/DesignSystem/FlowPalette.swift`：新增一个色常量，更新过时的注释。
- `blindRun/Volunteer/VolunteerOrderFlowPage.swift`：`VolunteerRunningPage.heroCard` 取色一处。
- `blindRunTests/FlowDesignSystemTests.swift`：`heroStates` 加一项，新增一条用例。
- 只影响陪跑员跑步中头卡的底色，头卡上的字仍是白 / 半透明白，对比度复算见 design.md。
- 盲人端不受影响（状态色只给陪跑员订单页，见 `design-direction.md` §6.1）。
