## Why

负责人 2026-10-13（issue #397）：订单页要看得到「第几步、做过哪些、还有哪些」；汇合时要能直接打给陪跑员；各状态的头卡要一眼分得出。定稿 `docs/ui/mockups/intro-call-20261013/draft.png`（v6，负责人当晚批准）。负责人明确要求复用陪跑员端现有的 `RopeView`，不另起一套。

## What Changes

- 两端共用的引导绳加四个等距刻度（盲人端：匹配 · 约好 · 出发 · 汇合；陪跑员端：邀请 · 约好 · 出发 · 汇合），刻度文字在同一条水平线上。走过的刻度打勾，当前格加粗，没到的是空心圈。
- **「我」永远在左、对方在右**，每进一个阶段「我」挪一格；第四格就是对方的头像。**BREAKING（视觉）**：盲人端原来是陪跑员在左往右走向「我」，现在反过来；陪跑员端出发中不再按 `eta.progress` 连续移动，固定停在「出发」刻度上（还有几分钟到仍由头卡大数字说）。
- 汇合态不画刻度，改用陪跑员完成页的「两人并肩」插图（`RopeTogetherIllustration`），底色换成汇合橙；汇合头卡与完成页一样居中。
- 引导绳读屏标签在「第 N 步，共 4 步，<状态>」后补「接下来：…」，汇合那一格不补。
- 新增三个头卡状态色：匹配 / 邀请灰蓝 `#46506A`、通话前紫 `#6941C6`、通话后梅红 `#86377F`。盲人端匹配中、陪跑员端邀请不再是白卡。**取代** `redesign-blind-runner-screens-a` 里「匹配中仍是白卡」一句。
- 盲人端汇合页（`DRIVER_ARRIVED`，跑步前）在「开始跑步」与「求助与安全」之间加「打电话给<陪跑员姓氏>」：白底蓝框、80pt 高，走现有 `EmergencyDialer`；拿不到可拨的号码时不出现。

**不变**：主按钮与「求助与安全」的位置与文案、求助判据、号码不上屏不进读屏标签、跑步中 / 完成头卡。

## Capabilities

### New Capabilities
- `order-progress-rope`: 两端订单页头卡里的进度绳（刻度、方向、汇合插图、读屏）、头卡状态色与盲人端汇合页的打电话按钮。

### Modified Capabilities
（无。与 `redesign-blind-runner-screens-a` 冲突的那一句在本变更的需求里以新口径写明，避免两个未归档变更改同一条需求。）

## Impact

- 代码：`blindRun/Volunteer/RopeView.swift`、`blindRun/Core/DesignSystem/FlowPalette.swift`、`FlowV2Components.swift`（底部按钮区）、`blindRun/BlindRunner/BlindOrderV2.swift`、`BlindOrderFlowView.swift`、`BlindOrderStatusView.swift`（只接打电话回调）、`BlindHomeCards.swift`、`blindRun/Volunteer/VolunteerOrderV2.swift`、`VolunteerOrderFlowPage.swift`。
- 测试：`RopeAndDirectionTests`、`BlindOrderHeroTests`、`FlowDesignSystemTests`、`VolunteerOrderV2Tests`；真机截图 `ScreenTourTests`。
- 后端：无。
