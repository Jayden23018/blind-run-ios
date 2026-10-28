## Decisions

1. **触发点挂在两端根容器**：盲人端订同行协调器的 `activeOrderID`（首页 / 订单页都会把含 `PENDING_MATCH` 的订单交给它；嵌套 ObservableObject 不经 `AppState` 转发，所以直接订发布者）；陪跑员端看首页 view model 的 `isAvailable`。不挂在下单页 / 首页：那两个文件已到 SwiftLint 棘轮上限，且盲人下单后离开下单页才轮到订单。
2. **说明用系统 alert 承载**：读屏会自动聚焦并念出正文；另外朗读一次，照顾没开读屏的低视力用户。用户按「开启通知」才调 `requestAuthorization`，系统框紧跟说明。
3. **每个角色只主动提示一次**（本机 `persistence` 记一个标记）：拒绝过还反复弹是打扰；之后的出路在设置页那一行。
4. 打开系统设置不是拨号，走 `SystemSettingsLink.open()`（行尾 `guard:allow raw-open-url`）。

## Risks / Trade-offs

- 盲人第一张订单之前不会收到任何推送 → 那之前也没有需要推送的事件。
- 老用户（启动时已经被问过）不受影响：已授权不打扰，已拒绝时第一次用到给一次设置入口。
