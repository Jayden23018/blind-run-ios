# Tasks

- [x] 1.1 模型接 `upcomingOrders`（可选，`nil` 与 `[]` 分开）。
- [x] 1.2 摘要带了就当预约列表、不再打 `orders/mine`；`nil` 回落到两条 `orders/mine`。
- [x] 1.3 不并进 `activeOrders`、不注册进位置协同。
- [x] 2.1 单测 `VolunteerUpcomingOrdersTests`；`build-for-testing`。
- [x] 2.2 真机跑 `VolunteerUpcomingOrdersTests`、`VolunteerDispatchHubTests`、`blindRunTests`；验红。（10-29 iPhone 16 Pro：`passed=380 failed=0`；打回 `[]` 回落 / 注册进位置协同 / 旧摘要闸三处后预期 3 条红）
