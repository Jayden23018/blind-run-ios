## 1. 实时协调器

- [ ] 1.1 `AppRealtimeCoordinator` 新增 `volunteerLostPublisher`，实时 `routeNotification` 与补读 `ingestCatchUp` 都发（只在陪跑员角色）

## 2. 订单页与首页

- [ ] 2.1 `RunOrderStatus` 新增穷举判据：哪些状态会被失联事件转走（`DRIVER_EN_ROUTE` / `DRIVER_ARRIVED`）
- [ ] 2.2 `VolunteerInServiceViewModel` 订阅失联事件：静默放下订单、注销活跃订单、置 `didLoseOrder`
- [ ] 2.3 推送来的 `REMATCHING` 且本人没发起取消时置 `didLoseOrder`；`VolunteerCancelAnnouncement` 记 `requested`
- [ ] 2.4 离开后在路上的流转请求不再播报、不再起确认任务
- [ ] 2.5 `VolunteerInServiceView` 收到 `didLoseOrder`：收起面板与弹窗后 dismiss
- [ ] 2.6 `VolunteerHomeViewModel` 订阅失联事件：静默清掉当前订单

## 3. 验证

- [ ] 3.1 单测：收到事件 → 离开且只念横幅那一句；补读同样离开；`IN_PROGRESS` 不离开；跑者端不发
- [ ] 3.2 单测：推送 `REMATCHING` 且非本人取消 → 离开；本人取消 → 不置 `didLoseOrder`
- [ ] 3.3 单测：其他安全事件不误触发；验红（实现退回后用例变红）
- [ ] 3.4 编译门禁 `build-for-testing` 与真机跑覆盖到的 suite
