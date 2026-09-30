## MODIFIED Requirements

### Requirement: 跑步中使用 v2 页面且不显示地图
订单状态为 `IN_PROGRESS` 时，陪跑员订单页 SHALL 显示 v2 页面：页面自带的导航栏（返回、标题「陪跑中」、右上求助胶囊）和青绿头卡（暂停时为暂停灰）。页面 SHALL NOT 显示地图，也 SHALL NOT 显示系统导航栏。

#### Scenario: 从汇合页开始跑步
- **WHEN** 订单从 `DRIVER_ARRIVED` 变成 `IN_PROGRESS`
- **THEN** 页面原地换成跑步中页，标题为「陪跑中」，屏幕上没有地图，头卡底色为青绿

#### Scenario: 暂停时头卡换灰
- **WHEN** 跑步中订单进入暂停
- **THEN** 头卡底色由青绿换成暂停灰，暂停结束后换回青绿
