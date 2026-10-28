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

精确位置关闭的同行会话中，会话健康提示 SHALL 进入「精确位置已关闭」一档，横幅 SHALL 可见，且进入这一档时 SHALL 朗读一次。文案 SHALL 说明同行位置共享已暂停、对方看不到这一端的位置，并给出恢复办法（弹出提示时选允许，或到系统设置打开精确位置）。盲人端文案 SHALL 另外说明紧急求助会因此发不出去。这一档 SHALL 排在网络断开之后、样本缺失之前。

#### Scenario: 陪跑员端看到并听到提示
- **WHEN** 陪跑员端同行会话中精确位置关闭、网络连通
- **THEN** 健康提示为「精确位置已关闭」一档，文案含「暂停」与「精确位置」，不含「求助」

#### Scenario: 盲人端提示带上求助后果
- **WHEN** 盲人端同行会话中精确位置关闭、网络连通
- **THEN** 文案含「暂停」与「求助」

### Requirement: 会话开始时两端都申请临时精确位置

同行会话进入 `DRIVER_EN_ROUTE` 时精确位置关闭的话，App SHALL 为该订单申请一次临时精确位置；进入 `IN_PROGRESS` 时若仍关闭 SHALL 再申请一次；同一单同一阶段 SHALL NOT 重复申请。陪跑员端的用途说明 SHALL 讲陪跑员自己的后果，SHALL NOT 沿用盲人端「求助才能带上你的准确位置」那条。只在连着云端实时通道时申请（Mock 与 UI 测试不弹系统框）。

#### Scenario: 陪跑员出发时精确位置关闭
- **WHEN** 陪跑员订单进入 `DRIVER_EN_ROUTE`，精确位置关闭
- **THEN** 以陪跑员用途申请一次临时精确位置；进入 `DRIVER_ARRIVED` 不再申请

#### Scenario: 盲人跑步开始时仍关闭
- **WHEN** 盲人订单进入 `IN_PROGRESS`，精确位置仍关闭
- **THEN** 以盲人陪跑用途再申请一次

