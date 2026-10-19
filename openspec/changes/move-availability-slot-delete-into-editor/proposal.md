## Why

#466 要让「空闲时间」页的整页无障碍审计在真机上转绿。修完对比度与工具栏之后，剩下的几条「改不了字号 / 可能被裁」都落在 `List` 下半屏的元素上（页脚、最后一枚「按日期添加」），而最大字号截图里这些字明明放大了 —— 是 `List` 一类的审计误报（项目记忆 `list-rows-false-dynamic-type-audit`）。仓库里对这一类唯一验证过的修法是把页面容器换成常驻的 `ScrollView` + `VStack`。项目负责人 2026-10-19 拍板走这条路。

`ScrollView` 没有 `List` 的左滑删除，所以删除一段要换个入口。左滑删除对读屏用户本来也不好发现（要在转子里找「删除」动作），换成编辑页里一枚看得见、念得清的按钮更好。

## What Changes

- 空闲时间页的容器由 `List` 换成 `ScrollView` + `VStack`，外观仍是分组卡片（组标题、卡片、页脚），行内容、读屏文案、两枚添加入口不变。
- **左滑删除取消**，改成：点一段打开编辑页，编辑页底部有一枚「删除这一段」按钮（只在编辑已有的一段时出现，新增时不出现），触达不小于 64pt，读屏念出删的是哪一段（如「删除 周六 07:00 – 09:00」）。
- 按下先弹确认框（与 App 里删除紧急联系人同一种：标题「确认删除…」、「确认删除」/「取消」两枚按钮、一句说明），确认后关掉编辑页、从列表去掉这一段，并走既有的整体 `PUT /api/volunteer/profile` 保存。一次性时段（带日期的）同样能删。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `volunteer-availability-schedule`：新增「在编辑页删除一段空闲时间」这一条要求（删除入口、确认、整体保存不改坏其余时段）。

## Impact

- 代码：`blindRun/Volunteer/VolunteerAvailabilityScheduleView.swift`（页面容器、编辑页删除按钮与确认、view model 按 id 删除）。
- 测试：`blindRunTests/VolunteerAvailabilityScheduleSaveTests.swift`（删除后整体保存的请求体）、`blindRunUITests/AccessibilityAuditTests.swift`（删除按钮可达与 64pt、整页审计亮 / 暗 / 最大字号）。
- 接口：无变化，仍是整体 `PUT /api/volunteer/profile`。
