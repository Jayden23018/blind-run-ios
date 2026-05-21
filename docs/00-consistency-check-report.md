# AidRun MVP v0.3 Consistency Check Report

## 检查范围

本次检查覆盖以下文档与 OpenSpec change：

- `docs/01-product-requirements.md` 至 `docs/10-ai-coding-tasks.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/proposal.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/design.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/tasks.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/*/spec.md`

最高优先级 source of truth 为 MVP v0.3 冻结口径：Swift 原生 iOS + SwiftUI/MVVM、Spring Boot、H2 demo、后续 PostgreSQL、REST API、Swagger/OpenAPI、JWT Bearer Auth、5 秒轮询、高德地图与定位、VoiceOver/TTS/Speech、3 天 demo 范围。

## 发现的问题

- `docs/04-user-flows-and-state-machine.md` 仍使用旧 API 写法：`POST /auth/login`、`GET /orders/{id}`、`GET /orders?status=matching`、`PATCH /orders/{id}/...`、`/start`。
- `docs/04-user-flows-and-state-machine.md` 存在 `emergency -> completed` 和“异常完成”流转，与 MVP 冻结口径中 `emergency` 不可恢复、不继续生命周期动作冲突。
- 志愿者端文档存在“导航按钮 / 打开高德地图导航到出发地点”表述，容易被理解为路线导航能力，超出 MVP。
- `docs/05-page-specs.md` 中盲人订单状态页只允许 `matching` 取消，未覆盖冻结口径中的 `accepted / arrived` 服务开始前取消。
- `docs/05-page-specs.md` 中志愿者定位权限拒绝时只“不显示距离”，未明确阻断距离排序相关订单查看与接单流程。
- `docs/05-page-specs.md` 中 Mock 认证完成同时设置 `isAvailable = true`，与“可服务开关单独控制”不一致。
- `docs/06-data-model.md` 与 `docs/07-api-contract.openapi.yaml` 中取消原因字段命名不一致，且 data model 使用 `blindRunnerPhoneVisibleToVolunteer` 布尔字段而 OpenAPI 使用 `blindRunnerPhone`。
- `docs/07-api-contract.openapi.yaml` 中 `RunOrderDto` 缺少 `cancelledAt`、`emergencyAt`，部分嵌套 DTO 未公开可追踪 `id`。
- OpenSpec 中 `volunteer-order-flow` 使用 `optional route metadata`，可能暗示路线导航；`order-status-lifecycle` 未显式写出 emergency 后 reject arrive / confirm-start / complete / cancel。

## 已修正的问题

- 统一 API 表述到 OpenAPI 契约：
  - 登录：`POST /api/auth/phone-login`
  - 创建订单：`POST /api/orders`
  - 订单详情轮询：`GET /api/orders/{orderId}`
  - 可接订单：`GET /api/orders/available`
  - 订单动作：`POST /api/orders/{orderId}/accept|arrive|confirm-start|complete|cancel|emergency|rating`
- 删除 `emergency -> completed`，将 `emergency` 明确为 MVP 异常终态。
- 将志愿者端“导航”能力改为“查看地图 / 查看出发点位置”，保留地图、当前位置、订单 marker、距离，不承诺路线规划或导航。
- 更新页面规格：`matching / accepted / arrived` 均可普通取消，`in_progress` 后只能求助。
- 更新页面规格：志愿者定位权限不可用时阻断距离排序相关订单查看与接单流程。
- 更新页面规格：Mock 认证只设置 `verificationStatus = approved` 与 `adminReviewStatus = approved`，`isAvailable` 由志愿者首页可服务开关控制。
- 统一取消字段为 `cancelledReason`；积分流水 `reason` 保持不变。
- 将 data model 的订单电话字段改为 `blindRunnerPhone`，说明接单前 API 不返回、接单后完整返回。
- OpenAPI `RunOrderDto` 补齐 `cancelledAt`、`emergencyAt`。
- OpenAPI `CancellationDto`、`EmergencyEventDto`、`ServiceSummaryDto`、`RatingDto` 补齐公开可追踪 `id`，并在适用处补齐 `orderId`。
- OpenSpec 更新：
  - `volunteer-order-flow/spec.md` 将 `optional route metadata` 改为 `optional destination or route description fields`。
  - `order-status-lifecycle/spec.md` 增加 emergency 后 reject arrive / confirm-start / complete / cancel 的场景。

## 未修正但需要人工确认的问题

- 无阻塞项。
- `no_volunteer_available` 保留为系统取消原因枚举值；它不属于用户手动取消固定选项，但用于“预约开始前 30 分钟仍无人接单”的系统取消。
- 文档中的“路线导航”仍保留在 Non-Goals / Out-of-Scope 列表或显式“不做”说明中，用于明确不做该能力；未作为 MVP 功能保留。

## 最终 MVP 冻结结论

当前文档与 OpenSpec 已对齐到 MVP v0.3：

- 只做 Swift 原生 iOS，不做 Android 或 Flutter 当前方案。
- iOS 使用 SwiftUI + MVVM，网络层使用 URLSession。
- 后端使用 Spring Boot + H2 demo，后续迁移 PostgreSQL。
- 使用 REST API、JWT Bearer Auth、Swagger/OpenAPI，不做 WebSocket。
- 手机号登录使用固定验证码 `123456`，首次登录自动注册。
- 志愿者认证为 Mock 认证，MVP 自动 approved，不做真实实名认证或真实管理员后台。
- 订单状态仅使用 `matching / accepted / arrived / in_progress / completed / cancelled / emergency`。
- 正常流转为 `matching -> accepted -> arrived -> in_progress -> completed`。
- 取消流转为 `matching / accepted / arrived -> cancelled`。
- 求助流转为 `accepted / arrived / in_progress -> emergency`，且 emergency 为 MVP 终态。
- 高德地图用于显示地图、当前位置、订单 marker、距离；不做路线导航。
- 盲人端订单详情每 5 秒轮询。
- 志愿者完成一次服务获得 +100 积分，积分商城仅占位展示，不做兑换、库存或支付。

## 修改过的文件

- `docs/00-consistency-check-report.md`
- `docs/01-product-requirements.md`
- `docs/03-user-stories.md`
- `docs/04-user-flows-and-state-machine.md`
- `docs/05-page-specs.md`
- `docs/06-data-model.md`
- `docs/07-api-contract.openapi.yaml`
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md`
- `openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-order-flow/spec.md`

## 校验结果

- 已运行 `openspec validate add-aidrun-ios-spring-mvp --strict --no-interactive`，结果：通过。
- 已用 Ruby/YAML 解析 `docs/07-api-contract.openapi.yaml`，结果：通过。
  - OpenAPI version: `3.0.3`
  - paths: `21`
  - schemas: `36`
  - local `$ref`: `92`
  - required fields 均存在于对应 schema properties。
- 未发现仓库内 package manifest 或 OpenAPI lint 工具配置；未新增依赖。后续如需要更严格 API lint，可使用 Redocly CLI 或 Spectral 校验 `docs/07-api-contract.openapi.yaml`。
