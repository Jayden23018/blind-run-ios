# AidRun MVP v0.3 Consistency Check Report

## 检查范围

本次检查覆盖以下文档与 OpenSpec change：

- `docs/01-product-requirements.md` 至 `docs/10-ai-coding-tasks.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/proposal.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/design.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/tasks.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/*/spec.md`

最高优先级 source of truth 为 MVP v0.3 冻结口径：Swift 原生 iOS + SwiftUI/MVVM、iOS 16+、URLSession、Spring Boot、H2 demo、后续 PostgreSQL、REST API、Swagger/OpenAPI、JWT Bearer Auth、5 秒轮询、高德地图与定位、VoiceOver/TTS/Speech、3 天 demo 范围。

## 发现的问题

- `docs/02-mvp-scope.md` 仍写盲人端取消订单“仅匹配中状态可取消”，与冻结口径中 `matching / accepted / arrived` 服务开始前均可取消不一致。
- `docs/03-user-stories.md` 和 `docs/05-page-specs.md` 需要保留“获取验证码 / 验证码已发送 / 倒计时 / 重新发送”的用户体验，但工程口径仍是固定验证码 `123456`，不接入真实短信服务商。
- `docs/03-user-stories.md` 写 Mock 认证后 `isAvailable` 自动设为 true，与“Mock 认证只自动 approved，可服务开关单独控制”不一致。
- `docs/05-page-specs.md` 写新志愿者可服务开关默认 true，容易绕过“接单前必须主动处于 isAvailable = true”的口径。
- `docs/05-page-specs.md` 志愿者服务中页入口包含 `accepted / arrived / in_progress`，但未列出 accepted 状态的“我已到达”和 accepted / arrived 状态的取消操作。
- `docs/06-data-model.md` 与 `docs/07-api-contract.openapi.yaml` 将 `activeRole` 设为登录返回必填字段；首次登录应先进入角色选择页，选择前 `activeRole` 可为空。
- `docs/06-data-model.md` 与 `docs/07-api-contract.openapi.yaml` 使用同一个 `CancellationReason` 处理手动取消和系统超时取消，导致用户手动取消请求也可提交 `no_volunteer_available`。
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/auth-phone-login/spec.md` 写首次登录会设置 `activeRole`，与首次登录后进入角色选择页冲突。
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md` 未区分手动取消固定原因与系统生成的 `no_volunteer_available`。

## 已修正的问题

- 将 `docs/02-mvp-scope.md` 的盲人端取消规则改为 `matching / accepted / arrived` 服务开始前可取消。
- 登录页和登录用户故事保留验证码发送体验与倒计时，不在用户界面提示固定验证码；后端登录校验仍使用固定验证码 `123456`，不接入真实短信服务商。
- 将志愿者 Mock 认证改为只设置 `verificationStatus = approved` 和 `adminReviewStatus = approved`；`isAvailable` 由志愿者首页开关单独控制。
- 将新志愿者可服务开关默认状态改为关闭；seed demo 账号可预置开启以便演示。
- 补齐志愿者服务中页 accepted 状态的“我已到达”操作，以及 accepted / arrived 状态的取消操作、状态变化和无障碍要求。
- 将 `User.activeRole` 在 data model 和 OpenAPI 中改为首次角色选择前可为空；iOS 架构与 OpenSpec design 同步说明首次登录后应进入角色选择。
- 增加 `ManualCancellationReason`，手动取消请求只能使用 `time_conflict / wrong_location / temporary_issue / cannot_contact / other`；系统超时取消继续使用 `cancelledReason = no_volunteer_available`，且不设置手动 `cancelledBy`。
- 更新 OpenSpec `auth-phone-login`，首次登录创建用户但不预设 `activeRole`。
- 更新 OpenSpec `order-status-lifecycle`，明确手动取消原因和系统无人接单取消是两类规则。

## 未修正但需要人工确认的问题

- 无阻塞项。
- `no_volunteer_available` 保留为系统取消原因枚举值；它不是手动取消选项。
- 文档中的 Android、WebSocket、真实短信、真实实名认证、路线导航、支付、库存、App 内聊天等词只保留在 Non-Goals / Out-of-Scope / 明确“不做”说明中，未作为 MVP 功能保留。

## 最终 MVP 冻结结论

当前文档与 OpenSpec 已对齐到 MVP v0.3：

- 只做 Swift 原生 iOS，不做 Android 或 Flutter 当前方案。
- iOS 使用 SwiftUI + MVVM，网络层使用 URLSession，token MVP 存 UserDefaults，正式版迁移 Keychain。
- 后端使用 Spring Boot + H2 demo，后续迁移 PostgreSQL；启动时 seed 测试数据。
- 使用 REST API、JWT Bearer Auth、Swagger/OpenAPI，不做 WebSocket。
- 手机号登录使用固定验证码 `123456`，首次登录自动注册，首次角色选择前 `activeRole` 可为空。
- 一个账号可同时拥有盲人跑者和志愿者身份，共用 token，通过 `activeRole` 切换；`accepted / arrived / in_progress / emergency` 活跃订单阻断角色切换。
- 志愿者认证为 Mock 认证，MVP 自动 approved，不做真实实名认证或真实管理员后台。
- 订单状态仅使用 `matching / accepted / arrived / in_progress / completed / cancelled / emergency`。
- 正常流转为 `matching -> accepted -> arrived -> in_progress -> completed`。
- 普通取消流转为 `matching / accepted / arrived -> cancelled`。
- 求助流转为 `accepted / arrived / in_progress -> emergency`，且 emergency 为 MVP 终态。
- 高德地图用于显示地图、当前位置、订单 marker、距离；不做路线导航；key 放本地配置，不提交 Git。
- 盲人端订单详情每 5 秒轮询。
- 志愿者完成一次服务获得 +100 积分，积分商城仅占位展示，不做兑换、库存或支付。

## 修改过的文件

- `docs/00-consistency-check-report.md`
- `docs/02-mvp-scope.md`
- `docs/03-user-stories.md`
- `docs/05-page-specs.md`
- `docs/06-data-model.md`
- `docs/07-api-contract.openapi.yaml`
- `docs/08-ios-architecture.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/design.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/auth-phone-login/spec.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md`

## 校验结果

- 已运行 `openspec validate add-aidrun-ios-spring-mvp --strict --no-interactive`，结果：通过。
- 已用 Ruby/YAML 解析并检查 `docs/07-api-contract.openapi.yaml`，结果：通过。
  - OpenAPI version: `3.0.3`
  - paths: `21`
  - schemas: `37`
  - local `$ref`: `92`
  - required fields 均存在于对应 schema properties。
- 未发现仓库内 package manifest 或 OpenAPI lint 工具配置；未新增依赖。后续如需要更严格 API lint，可使用 Redocly CLI 或 Spectral 校验 `docs/07-api-contract.openapi.yaml`。
