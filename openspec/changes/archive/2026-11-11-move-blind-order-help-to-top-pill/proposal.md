## Why

负责人 2026-11-11 定稿盲人订单页 v7（`docs/ui/mockups/blind-order-tracking-20261109/DECISION.md` 第 1、5、8、9、11、12 条）：求助挪到右上角胶囊，推翻 10-06 / 10-07「求助留底部」；进度只用一条竖线、只展开当前一步；通话与确认两屏是订单页的同一步「商量见面安排」。求助入口挪位属 AGENTS §10 大档，必须先有变更。issue Jayden23018/blind-run-ios#917。

## What Changes

- 盲人订单页在 `PENDING_MATCH`、`REMATCHING`、`PENDING_INTRO_CALL`、`SCHEDULED_CONFIRMED`、`PENDING_ACCEPT` 五个状态换成 v7 版式：深色头 + 白底抽屉 + 五步竖线（匹配陪跑员 → 商量见面安排 → 等出发 → 在集合点汇合 → 开跑），只展开当前一步。
- **BREAKING（界面）** 这五个状态底部不再有「求助与安全」按钮；右上角固定一枚「求助」胶囊，点下去仍打开求助与安全中心。判定仍走 `BlindHomeSOSMode.resolve`：这五个状态都不是 `IN_PROGRESS`，只给本地拨号，绝不调 `POST /api/emergency/trigger`。二次确认文案逐字不改。
- 顶栏：返回「‹ 订单」、重复当前状态（喇叭）、「···」更多操作、求助胶囊。②③「更换陪跑员」与 ④「取消预约 / 把行程告诉家人 / 给陪跑员留言」收进「···」。
- **BREAKING（行为）** 通话磨合不再弹出盖在订单页上的全屏页，改在订单页同页显示（②通电话、③确认见面安排）。
- 不变：`DRIVER_EN_ROUTE` 起各状态（#918 另做）、首页订单卡与进度绳组件、求助中心内部、本地出门提醒 1 小时。「最晚开跑前半小时会有结果」（backend#949）与「陪跑员约 x:xx 出发」（backend#943）后端没合前不显示。

## Capabilities

### New Capabilities
<!-- 无 -->

### Modified Capabilities
- `blind-order-page`：跑步前五个状态的版式、求助入口位置、竖线进度。
- `intro-call-pages`：盲人端通话两屏并入订单页，不再是全屏页；求助入口在右上角。

## Impact

- 代码：`blindRun/BlindRunner/BlindOrderStatusView*.swift`、`BlindIntroCallView.swift`、新增竖线、顶栏与五个状态的版式文件。
- 无 API / 契约变化，不需要后端改动。
- UI 用例里依赖底部「求助与安全」位置与通话全屏页的条目要同步改。
