## Context

方向 A 定稿见 `docs/ui/mockups/blind-redesign-20261007/final/A-final.png`。盲人订单页已经在 #349 用上陪跑员 v2 的骨架（`BlindOrderFlowView` + `BlindOrderHero`），彩色头卡 `FlowHeroCard(.tinted)`、`onHero*` 半透明白与 `RopeView(theme: .onHero)` 都已在陪跑员端落地且对比度逐色验过（`FlowDesignSystemTests`）。本变更主要是把这些现成件接到跑者端，并删掉节奏功能。

## Goals / Non-Goals

**Goals:** 订单页头卡按状态着色；跑步中 / 已完成改成彩色头卡；跑步中只剩「听当前状态」与求助；订单页无标签栏但始终有返回；首页卡加绳；星火去掉在线志愿者数；语音预约屏去说明文字；评价图标换跑步小人；绳子切换带弹性。

**Non-Goals:** 求助入口位置与 `SafetyHubView`；求助文案；后端契约；跑后记录页；预约表单页。

## Decisions

1. **头卡颜色映射放在 `BlindOrderHero`**：新增 `tint: Color?`（`nil` = 白卡）。匹配 → `nil`；约好 → `stateAgreed`；出发 → `stateDeparted`；汇合 / 倒计时 → `stateArrived`。视图按 `tint` 选 `FlowHeroCard` 样式、文字色与绳子主题。判定仍只从 `presentation.step / phase` 派生，不新造状态判定。
2. **跑步卡复用 `FlowHeroCard(.tinted)`**：`BlindActiveRunView` 加一个 `onHero` 开关切前景色，不复制一份视图。并肩绳 `RopeState.together`。顶行「陪跑中 · 陈」与定位新鲜度搬进头卡小标题行；定位圆点在彩色底上用 `presenceGreen` / `gold`，状态仍由文字承担。
3. **警示文字在彩色底上不用红色**（红压琥珀 / 蓝不达标）：改白色粗体 + `exclamationmark.triangle.fill` 图标，读屏标签不变。
4. **返回箭头**：删 `navigationBarBackButtonHidden(isRunningPhase || isFinishedPhase)`，订单页根视图加 `.toolbar(.hidden, for: .tabBar)`（记忆 `tab-bar-clips-the-last-line-of-secondary-pages` 验过这是唯一有效写法）。注释里那条「若将来隐藏标签栏必须同时撤销」正是这里兑现。
5. **绳子弹性**：`RopeView.animation` 的 `dampingFraction` 0.85 → 0.6，`response` 不变。共用组件，陪跑员端同步变化，属同一设计语言。
6. **节奏删除**：删 `RunnerRhythm.swift`、`flowFooter` 里的按钮；陪跑员端删 `VolunteerRhythmCard` 及其 presentation、到达提醒与耳机播报节奏分支。`OrderRunState.lastSignal*` 解码字段保留（后端仍可能下发，删掉解码没有收益）。
7. **星火**：`XinghuoSnapshot.sentences` 与 `XinghuoMapView` 两处改用 `pairsRunning`；统计条去掉「志愿者在线」一格。`volunteersOnline` 字段保留在模型里（mock 数据源仍有），只是不上屏不进读屏。
8. **语音预约**：屏上不渲染 `VoiceOrderWizard` 的长提示，改为短标题「什么时候、在哪里跑？」；长提示继续用于 TTS 与主按钮 `accessibilityHint`。

## Risks / Trade-offs

- [推翻 10-06 浅色头卡] → 负责人 10-07 明确拍板，写进 `design-direction.md` 例外段与 mockups INDEX。
- [返回箭头成为跑步中读屏第一站，可能误退] → 退出只是离开页面，订单继续；首页订单卡可再进入。
- [陪跑员端动效变化] → 只是阻尼值，「减弱动态效果」路径不变。
- [删节奏是对上线功能的回退] → 负责人拍板，后端端点保留，可恢复。

## Migration Plan

单 PR。无数据迁移。回滚 = revert 该 PR。
