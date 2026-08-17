---
name: aidrun-auth
description: AidRun 登录、验证码、JWT、角色与账号生命周期规则。改动 auth 流程、AppState.currentUser / activeRole、角色选择页，或处理登录类错误码时读。
---

# AidRun 登录与角色规则

从 `AGENTS.md` 第 5 节拆出。这些是契约事实，不是设计建议。

## 角色

App 内只有两个角色：

- `BLIND`
- `VOLUNTEER`

不要在 iOS App 里建管理员角色，除非新的产品需求明确加了它。管理员/客服端点存在于后端 spec 里（67 个 operation 中有相当一部分是），但 iOS 本来就不该调。

## 两步手机登录

1. `POST /api/auth/send-code`
2. `POST /api/auth/verify-code`

- 手机号首次登录会自动建账号。
- 当前测试登录用固定验证码 `000000`；长期测试账号在发布验证时继续用它。
- 登录成功返回 JWT `token`（`LoginResponse`: `token`, `userId`, `role`）。
- 首次登录可能不返回 `role`，此时 App 要路由到角色选择页。

## Token 存储

Token 存 Keychain（`blindRun/Core/KeychainTokenStore.swift`，`kSecAttrAccessibleAfterFirstUnlock`，这样锁屏期间的后台陪跑仍能读到）。

**不要把 access token 写进 `UserDefaults`。** 目前唯一残留的 `UserDefaults` 访问是 `restoreSession()` 里对历史值的一次性迁移。

## 角色切换：当前无端点

一个账号可以同时拥有盲人与志愿者身份。

⚠️ `POST /api/user/role` 这个切换端点**后端没有实现**，App 内入口已删除。相关错误码 `ACTIVE_ORDER_ROLE_SWITCH_BLOCKED` 属于「未决 / 未实现」，不要在前端映射它。见 `docs/04-user-flows-and-state-machine.md` 第 6 节。

如果后端后来加了该端点，规则是：用户存在 `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` 的订单时，切换被阻断。

## 下单前置条件（后端真实校验的只有一条）

`OrderCreationService` 的真实前置只有 **「盲人至少有一个紧急联系人」**。

- `EMERGENCY_CONTACT_REQUIRED`（403）是这条的报错。**必须在 UI 里硬拦**。
- `IDENTITY_NOT_VERIFIED`（403）排在它之前，但**实名认证在当前版本只是引导，不是硬门禁** —— `OrderCreationService` 从不读 `verifyStatus`，前端单方面拦是假门禁，任何非 iOS 调用方都能绕过。要播报、要提示，但不要阻断下单。
- `PROFILE_INCOMPLETE` 是历史条目，后端 `ErrorCode.java` 里根本没有这个码，真实后端永不返回。

紧急联系人本身的规则见 `AGENTS.md` 第 10 节：1~5 个，恰好一个 primary，删最后一个会被后端拒绝且 UI 也要拦。后端自 v1.5.0 起返回**明文**手机号（`EmergencyContactResponse.phone`），掩码是 iOS 展示层的责任，`phone` 字段可直接用于拨号。
