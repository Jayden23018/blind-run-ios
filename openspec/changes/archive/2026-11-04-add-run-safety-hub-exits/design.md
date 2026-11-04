## Context

求助中心（`BlindSafetyHubView`）是订单页底部「求助与安全」打开的弹层。跑步中底部是云端求助，其余状态底部是本地拨号。
`SafetyHubView.swift`、`BlindOrderStatusView.swift`、`BlindOrderFlowStep.swift` 都在 SwiftLint 棘轮的冻结名单里，只许变短。

## Decisions

1. **结束入口只在 `IN_PROGRESS` 且登录有效时出现。** 后端只接受 `IN_PROGRESS`；登录过期时 `finish` 必然 401。用求助中心的 `mode == .cloudTrigger` 判，它本身就是「`IN_PROGRESS` 且登录有效」，不另判状态。
2. **二次确认放在弹层里面，确认后先关弹层再执行。** 与「一键求助」同一个坑：弹在被弹层盖住的页面上的 alert 不会出现。
3. **陪跑员是否掉线由后端判。** 契约原话「客户端不用自己判，按下去看返回即可」。按钮常驻，409 时念后端 `message`。
4. **`VOLUNTEER_STILL_ONLINE` 不进 `ErrorCode` 枚举。** `ErrorModels.swift` 已 400 行，加一行就越线；未知码本来就念后端 `message`。按 `ErrorResponse.code` 原串判空 `message` 的兜底。
5. **完成句按「这一单是不是我结束的」选择。** 在发请求之前记下订单号，失败时撤销。WebSocket 状态推送可能先于 HTTP 响应到达，先记能保证完成句不说成陪跑员结束。只存内存。
6. **`ORDER_OVERDUE` 在端上换文案。** 后端 2026-08-13 说过播报文案是 iOS 的边界；复用已有的 `overriddenBody`，只在盲人角色时换。
7. **系统 SOS 提醒排在「开始跑步」之后，用 `.onDemand` 档。** 同档会切断「开始跑步」；低一档会排队等它说完。每单只在倒计时走完时说一次（冷启动进跑步中不说）。

## Risks / Trade-offs

- 盲人结束后陪跑员手机恢复联网，会看到订单已完成。后端照常给陪跑员记完成与时长，这是契约行为。
- App 在后台时 `ORDER_OVERDUE` 走 APNs，正文是后端模板，仍说「让志愿者点击结束服务」。要后端改模板，记进交接。
