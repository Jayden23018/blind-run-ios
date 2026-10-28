## Context

- iOS 只申请了「使用期间」授权；配合 `UIBackgroundModes = location`、`allowsBackgroundLocationUpdates = true` 与 `showsBackgroundLocationIndicator = true`，前台开始的持续定位进后台后继续，系统显示蓝色标记。
- 此前 `setEscortBackgroundMode(enabled:)` 把「后台允许」和「跑步增强精度」绑成一个开关，只在 `IN_PROGRESS` 打开。

## Decisions

1. **拆成三档**：`.off` / `.sharing`（后台允许、普通精度）/ `.running`（后台 + 增强精度）。出发与汇合用 `.sharing`，跑步用 `.running`。
   增强精度只在跑步中：出发路上需要的是「对方看得到我在来的路上」，不需要导航级精度与 5 米过滤的电量代价。
2. **告知不新增**：同意文案已写明出发起锁屏仍定位；系统蓝色标记让用户随时看得到。只改健康横幅那一句，让陪跑员知道切去导航不会断。
3. **不改导航选择页文案**：根因修好后「切走后对方看不到你」不再成立，不需要那句警告。

## Risks / Trade-offs

- 出发与汇合期间多耗电 → 普通精度 + 10 米距离过滤，时长有限；横幅照旧提示电量。
- 「使用期间」授权下，App 被系统终止后不会自动恢复后台定位 → 与跑步中相同，不在本变更处理。
