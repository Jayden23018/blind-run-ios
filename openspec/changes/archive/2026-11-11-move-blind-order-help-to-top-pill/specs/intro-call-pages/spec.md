## ADDED Requirements

### Requirement: Runner intro call is part of the order page
For the runner, `PENDING_INTRO_CALL` SHALL be shown on the order page itself as the timeline step "商量见面安排", not as a full-screen page over the order page. Before a meetup plan arrives the step SHALL show the existing call texts and a bottom button "致电陪跑员<掩码称呼>" (or "再次致电" after returning from the call). When a plan arrives the step SHALL list the plan items and the bottom SHALL show "有异议，致电沟通" and "确认见面安排" at the same height. Dialling SHALL use only `dialableCounterpartPhone`. The page SHALL NOT show call rounds or the counterpart's stance.

#### Scenario: Order enters the intro call
- **WHEN** the order moves from `PENDING_MATCH` to `PENDING_INTRO_CALL` while the order page is open
- **THEN** the order page SHALL change in place to the call step and no full-screen page SHALL appear

#### Scenario: Plan submitted
- **WHEN** the volunteer submits a meetup plan
- **THEN** the page SHALL list every plan item, show "确认见面安排" and "有异议，致电沟通", and move VoiceOver focus to the plan title

## MODIFIED Requirements

### Requirement: 通话页与订单页同一套版式
陪跑员端「先通个电话」页 SHALL 使用订单页的彩色头卡与底栏：头卡依次是小标题（时间 · 集合地点 · 距离）、进度绳、大标题、副文与剩余时间胶囊；底栏依次是主按钮、次要按钮、求助入口。小标题里任何一段取不到 SHALL 省掉那一段，不显示占位。盲人端的通话在订单页同页显示，版式见 `Runner intro call is part of the order page`。

#### Scenario: 盲人端还没拨号
- **WHEN** 盲人在订单页走到「商量见面安排」、还没按过拨号
- **THEN** 深色头为「先通个电话 / 陪跑员<掩码称呼>已响应」，底部主按钮为「致电陪跑员<掩码称呼>」，「更换陪跑员」在「···」里，求助在右上角

#### Scenario: 陪跑员端恢复路径没有距离
- **WHEN** 陪跑员冷启动回到通话页，没有派单载荷
- **THEN** 小标题只有时间与集合地点，不显示距离

### Requirement: 通话整步沿用匹配色，子状态靠那句话与绳子图标区分
陪跑员端通话页头卡 SHALL 整步使用「匹配 / 邀请」那一格的灰蓝，SHALL NOT 为通话前后另配颜色（视觉稿 v2 决定 1，`docs/ui/mockups/intro-call-meetup-plan-20261015/`，取代 v6 的通话前紫与通话后梅红）。子状态 SHALL 靠头卡大标题与绳子第一格的小图标区分：等通话挂电话，等见面安排挂灰色单子。盲人端子状态 SHALL 靠深色头的大标题区分：等通话「陪跑员<掩码称呼>已响应」，等见面安排「等待见面安排」，听安排「见面安排（N 项变更）」。

#### Scenario: 盲人拨号回来
- **WHEN** 盲人按了拨号、App 从后台回到前台，见面安排还没到
- **THEN** 深色头大标题为「等待见面安排」，底部主按钮为「再次致电」，「更换陪跑员」在「···」里，求助在右上角
