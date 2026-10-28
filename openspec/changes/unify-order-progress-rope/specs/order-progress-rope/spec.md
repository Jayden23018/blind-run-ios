## ADDED Requirements

### Requirement: 进度绳用等距刻度表示四个阶段
两端订单页头卡里的引导绳 SHALL 画四个等距刻度，第四个刻度就是对方的头像。「我」 SHALL 永远画在左侧并停在当前阶段的刻度上，对方 SHALL 画在右侧。当前阶段之前的刻度 SHALL 画成打勾的实心圆，之后的 SHALL 画成空心圈。刻度文字 SHALL 在同一条水平线上：盲人端为「匹配 · 约好 · 出发 · 汇合」，陪跑员端为「邀请 · 约好 · 出发 · 汇合」。

#### Scenario: 盲人端约好
- **WHEN** 订单为 `SCHEDULED_CONFIRMED`，盲人打开订单页
- **THEN** 「我」在左侧第二个刻度上，第一个刻度打勾，第三个是空心圈，陪跑员头像在最右

#### Scenario: 陪跑员端出发中
- **WHEN** 订单为 `DRIVER_EN_ROUTE`，陪跑员打开订单页
- **THEN** 「我」停在第三个刻度上，不随 `eta.progress` 移动

### Requirement: 汇合态用并肩插图
订单为 `DRIVER_ARRIVED`（含倒计时三秒）时，头卡 SHALL NOT 画刻度，SHALL 画与陪跑员完成页同一张「两人并肩」插图，「我」在左；插图的分隔色与姓氏色 SHALL 取当前头卡色。头卡文字 SHALL 居中。

#### Scenario: 陪跑员已到达
- **WHEN** 盲人订单为 `DRIVER_ARRIVED`
- **THEN** 头卡为汇合橙，中间是「我」与陪跑员并肩的插图，标题居中

### Requirement: 进度绳读屏说出还剩哪些阶段
引导绳的读屏标签 SHALL 在「第 N 步，共 4 步，<状态>」之后接「接下来：<之后的阶段名>」；第 4 步 SHALL NOT 追加。头卡里 SHALL NOT 再有一行可见的「第 N 步」文字。

#### Scenario: 盲人端匹配中
- **WHEN** 订单为 `PENDING_MATCH`
- **THEN** 引导绳读屏标签为「第 1 步，共 4 步，匹配中，还没约好。接下来：约好、出发、汇合」

### Requirement: 每个状态一种头卡色，两端同一套
订单页头卡 SHALL 按状态着色，两端取同一套颜色：匹配 / 邀请灰蓝、约好藏青、出发蓝、汇合橙、跑步中青绿、完成绿；「先通个电话」整步沿用匹配 / 邀请灰蓝，不另配颜色（视觉稿 v2 决定 1）。任何状态的头卡 SHALL NOT 是白卡。头卡上的白字（含 90% / 94% 半透明白）在每一种状态色上 SHALL 达到 4.5:1。

#### Scenario: 盲人端匹配中
- **WHEN** 订单为 `PENDING_MATCH`
- **THEN** 头卡为灰蓝，文字为白色

#### Scenario: 陪跑员收到邀请
- **WHEN** 陪跑员打开邀请
- **THEN** 头卡为与盲人端匹配中相同的灰蓝

### Requirement: 盲人端汇合页可以直接打给陪跑员
订单为 `DRIVER_ARRIVED`（跑步前，以及按下开始后那三秒倒计时）、且订单详情给出了可拨的陪跑员号码时，盲人订单页底部 SHALL 在主按钮与「求助与安全」之间显示「打电话给<陪跑员姓氏>」，白底、主色描边、高 80pt；按下 SHALL 走 `EmergencyDialer`（系统先弹拨号确认）。号码 MUST NOT 出现在屏幕或读屏标签里。拿不到可拨号码时该按钮 SHALL NOT 出现。

#### Scenario: 有号码
- **WHEN** 订单为 `DRIVER_ARRIVED`，`volunteerPhone` 为明文可拨号码
- **THEN** 底部依次是「开始跑步」、「打电话给张」、「求助与安全」

#### Scenario: 倒计时那三秒
- **WHEN** 订单刚进 `IN_PROGRESS`，本地倒计时还在 3、2、1
- **THEN** 「打电话给张」仍在原位，「求助与安全」不移动；倒计时结束进入跑步中后才收起

#### Scenario: 没有号码
- **WHEN** 订单为 `DRIVER_ARRIVED`，`volunteerPhone` 为 null
- **THEN** 底部只有「开始跑步」与「求助与安全」
