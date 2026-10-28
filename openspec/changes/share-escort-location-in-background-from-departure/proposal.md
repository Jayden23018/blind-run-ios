## Why

陪跑员按「出发」后通常切到高德或 Apple 地图导航，本 App 进后台。此前后台定位只在 `IN_PROGRESS` 允许（`plan.md` 原文「仅 IN_PROGRESS 开启锁屏/后台定位」），于是出发与汇合两态一切走，位置共享就停了：盲人那边看到的陪跑员位置停在出发点，走散判断也失去依据（Jayden23018/blind-run-ios#523，严重程度高）。

两端的位置轨迹同意（#368）已经向用户写明「从出发到这次跑步结束……锁屏后仍在定位」，所以这是实现落后于告知，不是新的数据收集。

## What Changes

- 同行三态（`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`）都允许后台继续定位并显示系统蓝色定位标记；离开三态、会话或身份失效立即关闭（不变）。
- 跑步专用的增强精度（fitness 活动类型、导航级精度、5 米距离过滤）仍只在 `IN_PROGRESS`。
- 健康横幅「同行位置共享已开启」那句改为说清切到导航或锁屏后仍会继续共享。
- `plan.md`、`docs/04`、skill `aidrun-a11y-voice` 里「仅 IN_PROGRESS 后台定位」三处同步改。

## Capabilities

### New Capabilities
- `escort-background-location`: 同行会话三态都在后台继续共享位置，增强精度只在跑步中。

### Modified Capabilities

## Impact

- `blindRun/Map/LocationService.swift`：`setEscortBackgroundMode(enabled:)` 换成三档 `setEscortLocationMode(_:)`。
- `blindRun/Core/LiveEscortSessionCoordinator.swift`：按状态选档位。
- 电量：出发与汇合期间后台继续定位（普通精度、10 米距离过滤），时长通常在一小时内。
