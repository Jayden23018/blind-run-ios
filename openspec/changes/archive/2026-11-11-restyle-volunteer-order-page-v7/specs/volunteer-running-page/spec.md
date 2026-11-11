## ADDED Requirements

### Requirement: 跑步中使用 v7 地图页
订单状态为 `IN_PROGRESS` 时，陪跑员订单页 SHALL 显示 v7 页面（#945）：上半屏地图（跑者位置与集合点）、下半屏抽屉（标题「和{姓}一起跑步中」、距离 / 用时 / 配速、目标进度）、顶栏（返回、右上求助胶囊）。页面 SHALL NOT 显示系统导航栏。最大字号或横屏时 SHALL 不画地图、抽屉占满。

#### Scenario: 从汇合页开始跑步
- **WHEN** 订单从 `DRIVER_ARRIVED` 变成 `IN_PROGRESS`
- **THEN** 抽屉内容原地换成跑步数据，地图不重建，右上求助胶囊为红底白字

#### Scenario: 暂停时标题换暂停文案
- **WHEN** 跑步中订单进入暂停
- **THEN** 抽屉标题换成「已暂停 · 计时停在 mm:ss」并显示「暂停期间不计志愿时长」，底部出现「继续陪跑」

## REMOVED Requirements

### Requirement: 跑步中使用 v2 页面且不显示地图
**Reason**: 负责人 2026-11-11 定陪跑员订单页整套换 v7（#945），跑步中改为地图 + 抽屉，取代 V19「保持主线现状、无地图」。
**Migration**: 无数据迁移；见「跑步中使用 v7 地图页」。
