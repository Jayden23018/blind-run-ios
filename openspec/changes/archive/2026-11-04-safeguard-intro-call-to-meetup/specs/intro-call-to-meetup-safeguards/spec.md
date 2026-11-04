## ADDED Requirements

### Requirement: 通话磨合的退出动作先确认

盲人端「更换陪跑员」、陪跑员端「不合适」与「未接到来电」按下后 SHALL 先弹确认，用户确认后才调用对应端点。确认文案 MUST NOT 出现磨合轮次、剩余机会或对方表态。

#### Scenario: 跑者误触「更换陪跑员」

- **WHEN** 跑者在通话页按「更换陪跑员」
- **THEN** 弹出「确认更换陪跑员？」
- **AND** 按「取消」后不调用 `POST /intro-call/decision`，页面不变

#### Scenario: 陪跑员确认「不合适」

- **WHEN** 陪跑员按「不合适」并在确认框里按「确认不合适」
- **THEN** 客户端调用 `POST /intro-call/decision`，`decision = DECLINE`

### Requirement: 「未接到来电」延后出现

陪跑员通话页在本次启动里第一次看到该订单的通话页之后，满 `volunteerUnreachableDelayMinutes`（5）分钟才 SHALL 显示「未接到来电」。之前原位置 SHALL 显示一行说明，告诉陪跑员多久后可以在这里报告。

#### Scenario: 刚进通话页

- **WHEN** 陪跑员进页不足 5 分钟
- **THEN** 没有「未接到来电」按钮
- **AND** 原位置显示说明文字

#### Scenario: 进页满 5 分钟

- **WHEN** 距第一次看到通话页满 5 分钟
- **THEN** 出现「未接到来电」，按下先确认

### Requirement: 陪跑员通话页提醒聊完提交

陪跑员通话页在等来电那一步 SHALL 显示「聊完记得在这里提交结果」。收到跑者来电提醒时，播报 SHALL 在来电那句后面接「聊完记得回到这一页提交结果」。

#### Scenario: 等来电

- **WHEN** 陪跑员在通话页、还没提交见面安排
- **THEN** 头卡最后一行是提交提醒

### Requirement: 第一次接单说明手机号去向

陪跑员第一次在邀请卡上按接单类按钮时，系统 SHALL 先说明完整手机号会提供给跑者，按「知道了，继续」才发送响应，并按账号记住已说明。按「先不接」MUST NOT 发送响应，也不记住。锁屏通知上的「接受」在还没说明过时 SHALL 只打开邀请卡。

#### Scenario: 第一次接单

- **WHEN** 陪跑员第一次按「有意向」
- **THEN** 弹出手机号去向说明，不发送 `respond`
- **AND** 按「知道了，继续」后发送 `respond`

#### Scenario: 第二次接单

- **WHEN** 已经说明过的陪跑员再按接单
- **THEN** 直接发送 `respond`，不再弹说明

### Requirement: 约好后两端提醒带引导绳

订单处于 `SCHEDULED_CONFIRMED` 或 `PENDING_ACCEPT` 时，两端订单页 SHALL 显示带绳提醒，说明现场谁带了就用谁的。`tetherPreference` 为 `ARM_HOLD` 或 `VERBAL_ONLY` 时 MUST NOT 显示。没给或认不出时照常显示。陪跑员「开始跑步」上方那行小字 SHALL 按引导方式换说法。

#### Scenario: 跑者选搀扶

- **WHEN** 订单 `tetherPreference = ARM_HOLD`，状态 `PENDING_ACCEPT`
- **THEN** 两端都不显示带绳提醒
- **AND** 陪跑员「开始跑步」上方不出现「引导绳」

#### Scenario: 跑者没给引导方式

- **WHEN** 订单 `tetherPreference` 为空，状态 `SCHEDULED_CONFIRMED`
- **THEN** 两端都显示带绳提醒

### Requirement: 汇合时提示核对身份

陪跑员汇合页头卡 SHALL 固定显示「见面时先报姓氏，说明是助盲跑的陪跑员」。盲人端汇合页副标题与到达播报 SHALL 包含「按开始前，先核对对方姓氏」。

#### Scenario: 陪跑员到达

- **WHEN** 订单进入 `DRIVER_ARRIVED`
- **THEN** 跑者听到的到达播报包含「先核对对方姓氏」
- **AND** 陪跑员汇合页头卡有开口那一行

### Requirement: 陪跑员首单提示

派单摘要 `totalCompleted == 0` 时，陪跑员订单页在跑步前各步 SHALL 显示「这是你的第一次陪跑」。`totalCompleted` 拿不到时 MUST NOT 显示。首单要点 SHALL 出现在第一次打开订单页时自动弹出的「使用帮助」里。

#### Scenario: 新人的约好页

- **WHEN** `totalCompleted = 0`，订单 `PENDING_ACCEPT`
- **THEN** 订单页显示「这是你的第一次陪跑」

#### Scenario: 摘要没拉到

- **WHEN** 派单摘要请求失败
- **THEN** 不显示首单标签
