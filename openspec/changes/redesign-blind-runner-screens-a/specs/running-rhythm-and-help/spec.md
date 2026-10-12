## MODIFIED Requirements

### Requirement: 耳机语音播报开关
跑步页 SHALL 提供默认关闭的「耳机语音播报」开关，状态存本地、跨订单保留；开启时每满 1 公里播报「N 公里，用时 X 分 Y 秒」。跑步页 MUST NOT 播报任何节奏信号。

#### Scenario: 默认关
- **WHEN** 首次进入跑步页
- **THEN** 开关为关，跨过 1 公里不播报

#### Scenario: 开启后满 1 公里
- **WHEN** 开关为开且里程跨过 1 公里
- **THEN** 播报「1 公里，用时 X 分 Y 秒」，且不播报任何节奏相关的话

## REMOVED Requirements

### Requirement: 陪跑员节奏卡
**Reason**: 负责人 2026-10-07 定：跑步中跑者端不放节奏按钮（「跑者和陪跑员会直接沟通」），陪跑员端的节奏卡因此永远收不到信号，一并删除。
**Migration**: 无数据迁移。后端 `run.lastSignal` / `lastSignalAt` 字段客户端不再读取。

### Requirement: 新信号到达提醒
**Reason**: 随「陪跑员节奏卡」删除，不再有节奏信号可提醒。
**Migration**: 无。

### Requirement: 跑者节奏按钮
**Reason**: 跑步中的跑者端只保留「听当前状态」与求助，基本不需要碰手机（Train Fitness / ADA 2025 入围的同一思路）。节奏由两人直接说。
**Migration**: 客户端不再调用 `POST /api/orders/{id}/rhythm`，契约不动。
