## Why

App 一启动就弹系统推送授权（`blindRunApp` → `requestAuthorizationAndRegister`），早于首启隐私同意页与登录（#521）。同意之前就申请权限与首启同意的顺序矛盾；读屏用户在不知道 App 是什么时听到系统弹窗，容易随手拒绝，之后求助、到达类推送就再也收不到。

## What Changes

- 启动时不再请求通知授权；向 APNs 注册仍跟着登录状态走（#459）。
- 第一个需要推送的时刻再问：盲人有了第一张订单、陪跑员第一次打开接单开关。先用一句话（弹窗正文 + 朗读）说明用途，用户按「开启通知」才弹系统授权框。
- 已经拒绝过：同一时刻改为说明后果，给「去系统设置打开」；两端设置页常驻一行「通知」状态，拒绝时给同一个入口。
- 每个角色在本机只主动提示一次。

## Capabilities

### New Capabilities
- `push-permission-timing`: 推送权限在隐私同意与登录之后、第一个需要推送的时刻先说明再请求；拒绝后有去系统设置的入口。

### Modified Capabilities

## Impact

`blindRun/Core/PushNotificationsManager.swift`（`requestAuthorization()` / `authorizationStatus()`）、`blindRun/blindRunApp.swift`（去掉启动时的请求）、新文件 `blindRun/Core/PushPermissionPrompt.swift`、`BlindRunnerTabView` 与 `VolunteerTabView` 各挂一个触发、两端设置页各加一行。
