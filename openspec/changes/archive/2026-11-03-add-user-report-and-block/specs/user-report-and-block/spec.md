## ADDED Requirements

### Requirement: 举报与拉黑入口只凭后端下发的对方 id 显示

入口 MUST 只在后端下发了对方 id 时显示。订单详情与记录详情取 `counterpartUserId`，通话页取通话端点的 `counterpartUserId`，固定搭档页取原有的 id 字段。客户端 MUST NOT 猜测或拼凑 id，MUST NOT 用这个字段判断别的事，也 MUST NOT 为它加提示。

#### Scenario: 字段为空时不显示入口
- **WHEN** 订单详情的 `counterpartUserId` 为空
- **THEN** 这一页不出现「举报」和「不再匹配此人」

#### Scenario: 字段类型不对时订单照常显示
- **WHEN** 后端把 `counterpartUserId` 下发成非数字
- **THEN** 订单解码成功，这个字段按空处理

#### Scenario: 跑步中页不放入口
- **WHEN** 订单状态是 `IN_PROGRESS`
- **THEN** 跑步中页不出现这两个入口，这一屏的安全动作仍只有求助

### Requirement: 只有对方写的留言可以举报

留言的「举报」MUST 只给 `fromRole` 不等于当前角色的留言，并在请求里带留言 `id`。`fromRole` 未知时 MUST NOT 显示。

#### Scenario: 自己写的留言
- **WHEN** 陪跑员看自己发的留言
- **THEN** 这条留言旁没有「举报」

#### Scenario: 对方写的留言
- **WHEN** 跑者看陪跑员发的留言，且本单的 `counterpartUserId` 有值
- **THEN** 这条留言旁有「举报」，提交时 `messageId` 是这条留言的 `id`

### Requirement: 举报请求符合后端契约

举报原因 MUST 只取 `HARASSMENT`、`UNSAFE_BEHAVIOR`、`FALSE_INFO`、`OTHER`。补充说明可空，MUST 去掉首尾空白，MUST 按 UTF-16 计数且不超过 1000。没选原因时 MUST NOT 发请求。

#### Scenario: 补充说明超长
- **WHEN** 补充说明超过 1000 个 UTF-16 单元
- **THEN** 不发请求，屏幕显示并朗读原因，已写的字保留

#### Scenario: 提交成功
- **WHEN** 后端返回 201
- **THEN** 页面留在原处显示工单号，并朗读同一句话

### Requirement: 不再匹配此人需要二次确认且对方无感知

点「不再匹配此人」MUST 先弹确认，确认文案 MUST 说清后果与解除位置。App MUST NOT 在对方的任何界面暴露拉黑关系。

#### Scenario: 用户取消
- **WHEN** 用户在确认里选取消
- **THEN** 不发请求

#### Scenario: 确认成功
- **WHEN** 用户确认且后端返回 204
- **THEN** 屏幕显示并朗读结果，这一页不再显示这个入口

### Requirement: 已拉黑的人可以查看和解除

「我的」页 MUST 有「已拉黑的人」列表，列表 MUST 有加载中、空、失败三种状态。解除 MUST 二次确认。列表里解不了码的一项 MUST 被跳过，MUST NOT 让整页失败。

#### Scenario: 解除
- **WHEN** 用户确认解除
- **THEN** 发 `DELETE /api/users/{userId}/block`，重新拉取列表，并朗读结果

### Requirement: 对象不符合条件时不区分原因

举报或拉黑返回 404 `RESOURCE_NOT_FOUND` 时，App MUST 只显示一句通用文案，MUST NOT 区分对方不存在、没有交集或订单对不上。

#### Scenario: 拉黑被拒
- **WHEN** 拉黑返回 404 `RESOURCE_NOT_FOUND`
- **THEN** 屏幕显示并朗读通用文案

### Requirement: 账号停用提示说清现状和出路

`ACCOUNT_SUSPENDED` MUST 朗读后端 message，并补上这是平台限制以及去哪里联系客服。App MUST NOT 把用户退回登录页。陪跑员派单摘要含这个原因时，首页滑块 MUST NOT 允许滑开。

#### Scenario: 下单被拒
- **WHEN** 下单返回 403 `ACCOUNT_SUSPENDED`
- **THEN** 提示里同时有后端 message 和「上报问题」的位置，登录态不变

#### Scenario: 后端 message 为空
- **WHEN** 同一个错误的 message 为空
- **THEN** 本地文案说清发生了什么、为什么、能做什么、谁能帮

#### Scenario: 派单摘要带未知原因
- **WHEN** `notAvailableReasons` 里有客户端不认识的值
- **THEN** 摘要照常解码，未知值落到 `.unknown`
