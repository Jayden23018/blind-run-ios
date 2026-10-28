# escort-precise-location-gate Specification

## Purpose
陪跑同行位置在系统「精确位置」关闭时两端都不上报区域代表点，可见可听地告诉用户共享已暂停与恢复办法，并在会话开始时申请临时精确位置。
## Requirements
### Requirement: 精确位置关闭时不上报同行位置

同行会话（`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`）期间，任一端定位已授权但精确位置关闭时，该端 SHALL NOT 上报同行位置；精确位置恢复且有新的真实样本后 SHALL 自动恢复上报，不需要用户重进页面。盲人端与陪跑员端 SHALL 遵守同一条规则。

#### Scenario: 陪跑员端精确位置关闭
- **WHEN** 陪跑员订单处于 `DRIVER_EN_ROUTE`，定位已授权但精确位置关闭，本机有 60 秒内的样本
- **THEN** 不发送任何同行位置

#### Scenario: 盲人端精确位置关闭
- **WHEN** 盲人订单处于 `IN_PROGRESS`，定位已授权但精确位置关闭
- **THEN** 不发送任何同行位置

#### Scenario: 精确位置恢复
- **WHEN** 精确位置从关闭变为开启，之后收到新的真实样本
- **THEN** 同行位置恢复上报

### Requirement: 精确位置关闭时两端都可见可听地告知

精确位置关闭的同行会话中，会话健康提示 SHALL 进入「精确位置已关闭」一档，横幅 SHALL 可见，且进入这一档时 SHALL 朗读一次。文案 SHALL 说明同行位置共享已暂停、对方看不到这一端的位置，SHALL 说明开始跑步后一直关着的话几分钟后系统会按失联处理、自动启动求助流程，并给出恢复办法（弹出提示时选允许，或到系统设置打开精确位置）。时长 SHALL 只说「几分钟后」，SHALL NOT 写具体秒数或分钟数（那是后端配置项）。文案 SHALL NOT 含「已发出」「已通知」「短信」。盲人端文案 SHALL 另外说明紧急求助会因此发不出去；陪跑员端 SHALL NOT 说求助发不出去。这一档 SHALL 排在网络断开之后、样本缺失之前。

#### Scenario: 陪跑员端看到并听到提示
- **WHEN** 陪跑员端同行会话中精确位置关闭、网络连通
- **THEN** 健康提示为「精确位置已关闭」一档，文案含「暂停」「精确位置」「失联」，不含「发不出去」

#### Scenario: 盲人端提示带上求助后果
- **WHEN** 盲人端同行会话中精确位置关闭、网络连通
- **THEN** 文案含「暂停」「求助」「失联」

#### Scenario: 文案守住求助红线
- **WHEN** 任一端、跑步前或跑步中的这一档文案
- **THEN** 不含「已发出」「已通知」「短信」，也不含具体时长

### Requirement: 会话开始时两端都申请临时精确位置

同行会话进入 `DRIVER_EN_ROUTE` 时精确位置关闭的话，App SHALL 为该订单申请一次临时精确位置；进入 `IN_PROGRESS` 时若仍关闭 SHALL 再申请一次；同一单同一阶段 SHALL NOT 重复申请。陪跑员端的用途说明 SHALL 讲陪跑员自己的后果，SHALL NOT 沿用盲人端「求助才能带上你的准确位置」那条。只在连着云端实时通道时申请（Mock 与 UI 测试不弹系统框）。

#### Scenario: 陪跑员出发时精确位置关闭
- **WHEN** 陪跑员订单进入 `DRIVER_EN_ROUTE`，精确位置关闭
- **THEN** 以陪跑员用途申请一次临时精确位置；进入 `DRIVER_ARRIVED` 不再申请

#### Scenario: 盲人跑步开始时仍关闭
- **WHEN** 盲人订单进入 `IN_PROGRESS`，精确位置仍关闭
- **THEN** 以盲人陪跑用途再申请一次

### Requirement: 进入跑步时再提醒一次

同行会话进入 `IN_PROGRESS` 时精确位置仍关闭的话，健康提示 SHALL 换成跑步中的那一句，横幅 SHALL 随之更新，并 SHALL 再朗读一次。出发与汇合之间 SHALL NOT 重复朗读。

#### Scenario: 开跑时精确位置仍关闭
- **WHEN** 订单从 `DRIVER_ARRIVED` 进入 `IN_PROGRESS`，精确位置仍关闭
- **THEN** 健康提示换成跑步中那一句，根视图再朗读一次

#### Scenario: 出发到汇合
- **WHEN** 订单从 `DRIVER_EN_ROUTE` 进入 `DRIVER_ARRIVED`，精确位置仍关闭
- **THEN** 健康提示不变，不再朗读

