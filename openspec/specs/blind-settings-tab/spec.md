# blind-settings-tab Specification

## Purpose
盲人端「我的」与账户页上各入口放在哪、读屏念什么、大字号下怎么排，保证改版后入口一个不少、无障碍标识不变、「我的」不放常驻求助入口。
## Requirements
### Requirement: 「我的」按头像卡、类别方块、列表三段排列
盲人端「我的」SHALL 依次显示：头像卡（点进账户页）、「类别」四个方块（固定搭档、邀请好友、使用帮助、联系客服）、列表（我的工单、通知、关于）。除紧急呼叫行外，原有的每个入口 SHALL 仍能从「我的」或账户页到达，且无障碍标识不变。

#### Scenario: 视障跑者打开「我的」
- **WHEN** 视障跑者点底部「我的」
- **THEN** 默认字号下第一屏能看到头像卡和四个方块，读屏顺序是 我的 → 头像卡 → 类别 → 方块 → 列表

### Requirement: 「我的」不放求助入口
盲人端「我的」SHALL NOT 显示任何紧急呼叫或求助入口，陪跑中也不显示。求助 SHALL 仍可通过标签栏容器上的 Magic Tap 与订单页的「求助与安全」触发。

#### Scenario: 陪跑中打开「我的」
- **WHEN** 订单是 `IN_PROGRESS`，视障跑者点底部「我的」
- **THEN** 页面上没有「求助与安全」或「紧急呼叫」行

#### Scenario: 在「我的」上做 Magic Tap
- **WHEN** 订单是 `IN_PROGRESS`，读屏用户在「我的」上做 Magic Tap
- **THEN** 订单页被推上来并弹出逐字锁定的二次确认

#### Scenario: 找固定搭档入口
- **WHEN** UI 测试按标识 `blindFavoriteVolunteersSettingsEntry` 找入口
- **THEN** 找到的是「固定搭档」方块，点开是固定搭档页

### Requirement: 方块与列表行的可点区不低于 64pt
每个方块和列表行 SHALL 是一个读屏焦点，可点高度不低于 64pt（`AppTouchTarget.blindPrimary`）。方块标签只是名称，特性为按钮，白字与底色对比度 SHALL 不低于 4.5:1。

#### Scenario: VoiceOver 扫到方块
- **WHEN** 读屏焦点落到「使用帮助」方块
- **THEN** 念「使用帮助，按钮」，不念图标

### Requirement: 大字号下方块改单列
系统字号为 AX3 及以上时，方块 SHALL 排成一列；以下为两列。

#### Scenario: 字号调到 AX5
- **WHEN** 系统字号为 accessibility5
- **THEN** 四个方块上下排成一列，名称不截断

### Requirement: 账户页收拢个人与账户操作
点头像卡 SHALL 进入账户页，页上 SHALL 有：名字与「视障跑者」；个人资料；实名认证（念出当前状态，点进实名页）；隐私与授权、已拉黑的人；退出登录、删除账户。退出登录与删除账户 SHALL 保留原来的二次确认。

#### Scenario: 删除账户
- **WHEN** 视障跑者在账户页点「删除账户」
- **THEN** 先弹「确认删除账户」，通过预检后再弹「最终确认删除账户」，与改版前一致

#### Scenario: 引导页进来的设置
- **WHEN** 从引导页进入同一页
- **THEN** 标题叫「设置」，其余入口照常

