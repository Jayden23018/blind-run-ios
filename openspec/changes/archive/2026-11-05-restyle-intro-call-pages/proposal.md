## Why

负责人 2026-10-13（issue #397）：两端「先通个电话」页（`PENDING_INTRO_CALL`）与其余页面割裂，要按订单页同一套样式重做；聊前与聊后要用不同颜色；陪跑员端「这一单是你的了」「这一单已经安排好了」两屏不要。定稿 `docs/ui/mockups/intro-call-20261013/draft.png`（v6）。依赖 `unify-order-progress-rope`（进度绳与状态色）。

> **2026-10-28 订正（#575）**：本变更的配色与结局两部分已被视觉稿 v2（`docs/ui/mockups/intro-call-meetup-plan-20261015/`，负责人 10-15 批准，#433 / #434 实现）推翻，规格已按 v2 改写：通话整步沿用匹配灰蓝（紫 / 梅红已于 #446 删除）；盲人「聊过了，合适」去掉，改为听见面安排后确认；陪跑员没约成停在「本次沟通已结束」+「返回首页」，不自动关页。下面 What Changes 保留 v6 原文作为历史。

## What Changes

- 两端通话页改用订单页的版式：彩色头卡（小标题 · 进度绳 · 大标题 · 副文 · 剩余时间胶囊）+ 订单页同一条底栏。
- 头卡色：通话前紫（盲人端没拨号 / 陪跑员端等来电），通话后梅红（盲人端拨号回来 / 任一端已说合适）。盲人订单页在 `PENDING_INTRO_CALL` 时头卡也是紫色。
- 进度绳新增「先通个电话」三档：停在第 1 格、虚线、对方实心；通话前在绳上挂电话图标；已说合适时「我」头像上加小勾。只画自己的表态。
- 盲人端：「重复当前状态」从底部移到导航栏右侧（与订单页同一位置）；左上返回箭头读屏仍念「返回订单」；底栏加「求助与安全」（通话页先收起、再打开求助中心）。主按钮改黄色（原「聊过了，合适」是绿色）。
- 陪跑员端：订单页同一个导航栏（左返回、右求助胶囊，本地拨号）。**BREAKING（行为）**：双方都说合适后通话页原地变成订单页「约好」，不再停在「已约好，这一单是你的」+「进入服务流程」；本轮没成时自动关页回首页，只播报「这次通话确认已结束，感谢你的响应。」，不再停在「这一单已经安排好了」+「返回首页」。陪跑员已说合适后只留「不合适」。

**不变**（`AGENTS.md` §5）：不显示对方表态、不显示「第几位志愿者」、陪跑员端掩码号不拼 `tel:`、盲人端两段式且打完回来保留「再打一次」、「一直没接到电话」与「不合适」是两个端点。

## Capabilities

### New Capabilities
- `intro-call-pages`: 两端「先通个电话」页的版式、配色、结局处理。

## Impact

- 代码：`blindRun/BlindRunner/BlindIntroCallView.swift`、`BlindOrderStatusView.swift`（只改弹出通话页那一段）、`BlindOrderV2.swift`、`BlindOrderFlowView.swift`（配色映射）、`blindRun/Volunteer/VolunteerIntroCallView.swift`、`RopeView.swift`、`blindRun/Core/Models/IntroCallModels.swift`（文案）、`blindRun/Core/DesignSystem/`（底栏次要按钮槽、头卡小胶囊）。
- 测试：`IntroCallTests`、`RopeAndDirectionTests`、`BlindOrderHeroTests`、`FlowDesignSystemTests`；真机截图 `ScreenTourTests`（B21 与陪跑员通话页）。
- 后端：无。
