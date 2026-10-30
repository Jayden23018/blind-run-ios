## 1. 实现

- [x] 1.1 去掉启动时的通知授权请求；`PushNotificationsManager` 加 `requestAuthorization()` / `authorizationStatus()`
- [x] 1.2 `asksForPushPermission` 提示（说明 + 朗读 + 请求 / 去设置），每个角色只提示一次
- [x] 1.3 盲人端（第一张订单）与陪跑员端（第一次开接单开关）挂触发；两端设置页加「通知」一行

## 2. 验证

- [x] 2.1 单测：提示决策四种情形、两个角色分开记、文案要素
- [x] 2.2 编译门禁、SwiftLint 棘轮
- [x] 2.3 真机（iPhone 16 Pro 有线，2026-10-28，21eae427）：`PushPermissionPromptTests` `PendingSessionRevocationTests` `NotificationCatchUpTests` 与界面用例 `testSettingsShowNotificationRowWithTallButtonOnBothSides` `passed=48 failed=0`；验红（拒绝过也再弹、提示过也再弹、两角色共用标记）→ 预期的 3 条红（`failed=3`）。
  人工部分（新装 App 启动不弹系统框、盲人第一次下单先听到说明再出系统框、拒绝后设置页有入口）挪到人工验收 issue #410
- [x] 2.4 rebase 到 #553 之后的时机修正（`PushPermissionPrompt.volunteerNeedsPush`，03040b9c）：真机（iPhone 16 Pro 有线，2026-10-29）同一批目标 `passed=49 failed=0`，其中 `PushPermissionPromptTests` 7 条含新用例 `testVolunteerPushAskWaitsWhilePreciseLocationBlocksDispatch`；验红（打回成只看 `isAvailable`）→ 这一条变红（`passed=6 failed=1`）。
  人工部分（精确位置关着时打开接单开关，完整听到精确位置那句、没有通知说明抢话）记到人工验收 issue #410
