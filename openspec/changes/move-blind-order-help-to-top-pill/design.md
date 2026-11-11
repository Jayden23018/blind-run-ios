## Context

现状见 proposal。①–④ 原来走 `BlindOrderFlowView`（彩色头卡 + 引导绳 + 底栏「主按钮 + 求助与安全」），通话是 `BlindIntroCallView` 全屏页。⑤–⑧（出发起）由 #918 另做，会复用本变更的竖线与顶栏。

## Goals / Non-Goals

**Goals:** 五个跑步前状态按 v7 稿渲染；竖线与顶栏是独立组件，只吃纯数据，#918 能直接用；状态 → 步骤、折叠规则是纯函数，有单测。

**Non-Goals:** 出发起的地图与抽屉；匹配中动效；求助中心内部；后端未合的两行文字。

## Decisions

- **竖线组件只吃纯数据**：输入是「当前步位置 + 每步副标题 + 两个开关（下一步是否单列、是否折叠）」，不依赖页面 ViewModel。折叠规则放在纯函数里，视图只渲染它的结果。备选是把竖线写进页面视图，#918 无法复用，否决。
- **第四步叫「在集合点汇合」**：稿里「在南门汇合」的「南门」来自地址短名，地址是自由文本，拆不出短名。
- **求助胶囊样式由调用方传 `BlindHomeSOSMode`**：组件不判状态，判定仍集中在 `BlindHomeSOSMode.resolve`。
- **通话并入订单页**：稿里 ②③ 与 ①④ 同一顶栏、同一条竖线；保留全屏页会出现「关掉通话页后底下还有一层订单页」。通话的数据、轮询、10 分钟提醒、焦点回标题仍在 `BlindOrderStatusViewModel`，只换渲染位置。
- **identifier 尽量沿用**：头部沿用 `blindOrderFlowStatusCard`，喇叭沿用 `blindOrderFlowRepeatStatusButton`，「取消匹配」沿用 `blindOrderFlowLastRowButton`，安排单各行与确认按钮沿用 `blindIntroCall*`；求助胶囊用 `blindOrderFlowSafetyHubButton`。

## Risks / Trade-offs

- [通话不再整屏弹出，盲人可能错过] → 状态变化时焦点移到头部，现有状态播报不变。
- [UI 用例只改不跑] → PR 列出改过与怀疑受影响的用例，负责人统一真机时跑。
- [与 #918 同改订单页入口文件] → 本变更只加五个状态的分支，不动出发起分支。

## Migration Plan

纯客户端界面改动，随 App 版本发布；回滚即回退本 PR。
