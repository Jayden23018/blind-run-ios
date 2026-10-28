## Purpose

同行会话三态都在后台继续共享位置：陪跑员出发后切到外部导航、或任一方锁屏时，对方仍能看到位置；跑步专用的增强精度只在跑步中。

## ADDED Requirements

### Requirement: 同行三态都在后台继续共享位置

订单处于 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED` 或 `IN_PROGRESS` 且本机同意过位置轨迹时，App SHALL 允许后台继续定位并显示系统定位标记；离开这三态、同行会话结束或身份变化时 SHALL 立即关闭后台定位。

#### Scenario: 陪跑员出发后切去导航
- **WHEN** 陪跑员订单进入 `DRIVER_EN_ROUTE`
- **THEN** 后台定位已允许，App 进后台后同行位置继续上报

#### Scenario: 订单结束
- **WHEN** 订单变为 `COMPLETED`
- **THEN** 后台定位立即关闭

### Requirement: 增强精度只在跑步中

跑步专用的增强精度（fitness 活动类型、导航级精度、5 米距离过滤）SHALL 只在 `IN_PROGRESS` 使用；出发与汇合 SHALL 使用普通精度。

#### Scenario: 从出发进入跑步
- **WHEN** 订单从 `DRIVER_ARRIVED` 进入 `IN_PROGRESS`
- **THEN** 定位档位从普通共享切到跑步增强
