## Why

盲人端第二轮零上下文打分吸引力只有 5.0（`docs/review/ui-aesthetic-scoring-20261005.md`），而本轮目标是 Apple Design Awards「Inclusivity」入围水准：闭眼用 VoiceOver 能顺畅完成每件事，视觉上与陪跑员端 v2 是同一个产品。负责人 2026-10-07 选定方向 A「同一根绳」（issue #369，定稿 `docs/ui/mockups/blind-redesign-20261007/final/A-final.png`）。

## What Changes

- 盲人订单页头卡按订单状态着彩色底：约好藏青、出发蓝、汇合与倒计时琥珀、跑步中青绿、已完成绿；匹配中（还没有陪跑员）仍是白卡。头卡文字改用陪跑员端已验过对比度的 `onHero*` 半透明白。**推翻负责人 10-06「盲人端头卡用浅色」一条。**
- 跑步中 / 已完成：白色跑步卡换成彩色头卡，内含并肩金绳（`RopeState.together`）与里程 / 时长 / 配速三个数字。
- **BREAKING（行为）**：删除跑者端跑步中的三个节奏按钮；同时删除陪跑员跑步页「跑者的节奏」卡、新信号到达提醒、耳机播报中的节奏信号。节奏靠两人直接说。后端 `/rhythm` 端点不再被调用，契约不动。
- 订单页所有状态隐藏底部标签栏；跑步中 / 已完成**恢复返回箭头**（不恢复就没有出口，结束权只在陪跑员手上）。
- 引导绳状态切换的弹簧阻尼 0.85 → 0.6（两端共用 `RopeView`），绳子落定前轻晃；「减弱动态效果」下照旧只做 0.2 秒淡入淡出；**不加静止时的摆动**（`design-direction.md` §7）。
- 首页订单卡加约好态引导绳。
- 星火页不显示在线志愿者人数；概要句改为「N 对跑友正在同行」，读屏对地图区念同一句描述。
- 语音预约屏删除屏上的说明文字，改由读屏提示承担。
- 完成页评价 5 档的图标改为跑步小人，契约 1–5 星不变。

**不变**：订单页底部「求助与安全」的位置与文案、`SafetyHubView`、「我的」页求助条、求助二次确认锁定文案、非 `IN_PROGRESS` 降级本地拨号的判据。

## Capabilities

### New Capabilities
- `blind-runner-surfaces`: 盲人端首页订单卡、星火页概要、语音预约屏与完成页评价图标的呈现规则，以及两端共用引导绳的状态切换动效。

### Modified Capabilities
- `blind-order-page`: 头卡由浅色改为按状态着色；跑步中 / 已完成改为彩色头卡；隐藏标签栏并恢复返回箭头。
- `running-rhythm-and-help`: 删除「陪跑员节奏卡」「新信号到达提醒」「跑者节奏按钮」三条需求，「耳机语音播报开关」去掉节奏信号播报。

## Impact

- 代码：`blindRun/BlindRunner/BlindOrderFlowView.swift`、`BlindOrderV2.swift`、`BlindActiveRunView.swift`、`BlindOrderStatusView.swift`（只按符号定点改）、`BlindHomeCards.swift`、`BlindBookingView.swift`（只改语音那一屏）、`RunnerRhythm.swift`（删除）、`blindRun/Volunteer/RopeView.swift`、陪跑员跑步页节奏卡所在文件、`blindRun/Xinghuo/`。
- 测试：`FlowDesignSystemTests`（新配对）、`AccessibilityAuditTests`、`ScreenTourTests`、节奏相关单测与 UI 用例同步删除或改写。
- 后端：无契约改动。`POST /api/orders/{id}/rhythm` 客户端不再调用。
- 文档：`docs/ui/design-direction.md` 例外段、`docs/ui/mockups/INDEX.md`。
