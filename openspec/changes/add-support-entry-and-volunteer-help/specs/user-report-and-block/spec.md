## MODIFIED Requirements

### Requirement: 账号停用提示说清现状和出路

`ACCOUNT_SUSPENDED` MUST 朗读后端 message，并补上这是平台限制以及去哪里联系客服。入口名 MUST 与「我的」页上的行同名，即「联系客服」。App MUST NOT 把用户退回登录页。陪跑员派单摘要含这个原因时，首页滑块 MUST NOT 允许滑开。

#### Scenario: 下单被拒
- **WHEN** 下单返回 403 `ACCOUNT_SUSPENDED`
- **THEN** 提示里同时有后端 message 和「联系客服」的位置，登录态不变

#### Scenario: 后端 message 为空
- **WHEN** 同一个错误的 message 为空
- **THEN** 本地文案说清发生了什么、为什么、能做什么、谁能帮

#### Scenario: 派单摘要带未知原因
- **WHEN** `notAvailableReasons` 里有客户端不认识的值
- **THEN** 摘要照常解码，未知值落到 `.unknown`
