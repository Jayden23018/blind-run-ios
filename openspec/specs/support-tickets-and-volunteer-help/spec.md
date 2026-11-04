# support-tickets-and-volunteer-help Specification

## Purpose
TBD - created by archiving change add-support-entry-and-volunteer-help. Update Purpose after archive.
## Requirements
### Requirement: 两端「我的」页有名副其实的联系客服入口

系统 SHALL 在盲人端与陪跑员端的「我的」页提供「联系客服」入口，打开后可不带订单提交一条工单，分类为 `ACCOUNT`。入口行的可点高度 MUST 不低于 64pt。

#### Scenario: 盲人在「我的」页联系客服
- **WHEN** 盲人打开「我的」页并点「联系客服」
- **THEN** 系统显示工单页，正文为空，提交时不带订单号

#### Scenario: 文案指向的入口存在
- **WHEN** 任何文案叫用户「联系客服」或指向某个入口名
- **THEN** 该入口名 MUST 与「我的」页上的行同名

### Requirement: 工单页不承诺回复时限

工单页、跑步中面板的联系客服行、派单规则说明页 MUST NOT 出现具体回复时间，也 MUST NOT 出现「尽快」「马上」「回拨」。工单页 MUST 在输入框之前说明：不是即时通道，提交后会有工作人员查看，紧急情况拨 120 或 110。

#### Scenario: 打开工单页
- **WHEN** 用户打开工单页
- **THEN** 输入框之前的文字包含「不是即时通道」「120」「110」

#### Scenario: 陪跑员在跑步中提交客服请求
- **WHEN** 提交成功
- **THEN** 回显文案不含「尽快」，且说明不是即时通道

### Requirement: 用户能看到自己提交过的工单和回复

系统 SHALL 在「我的」页提供「我的工单」，读取 `GET /api/support/tickets`，按创建时间倒序显示每条工单的状态、正文和客服回复。

#### Scenario: 有已回复的工单
- **WHEN** 工单状态为 `REPLIED` 且 `csReply` 非空
- **THEN** 该行显示「已回复」和回复原文，读屏一次读完整行

#### Scenario: 状态值未知
- **WHEN** 后端返回不认识的状态或分类
- **THEN** 该条仍然显示，状态按「处理中」之外的中性说法显示，整页不崩

#### Scenario: 读取失败
- **WHEN** 读取工单列表失败
- **THEN** 页面 MUST 显示失败说明并提供重试，MUST NOT 显示「还没有工单」

### Requirement: 陪跑员有使用帮助

系统 SHALL 提供陪跑员使用帮助页，讲清一单怎么走完（确认、出发、到达、开跑、结束）以及出事找哪里（求助入口、本地拨号、客服工单）。设置页 MUST 有入口。帮助页 MUST NOT 声称有人会回拨、已通知，MUST 说明非跑步中 App 不会代用户发送求助。

#### Scenario: 第一次进订单页
- **WHEN** 陪跑员第一次打开处于出发前状态的订单页，且本机没有「已看过」标志
- **THEN** 系统自动打开帮助页一次
- **AND** 只有按下「知道了」才写标志

#### Scenario: 已经看过
- **WHEN** 本机有「已看过」标志
- **THEN** 订单页不再自动打开帮助页，设置页入口仍在

#### Scenario: 跑步中不打断
- **WHEN** 订单处于跑步中、已出发或已到达
- **THEN** 不自动打开帮助页

