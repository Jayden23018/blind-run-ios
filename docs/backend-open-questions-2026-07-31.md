# 待后端确认清单 · 2026-07-31

起因：志愿者在设置页点「切换角色」，无任何订单却提示「存在进行中的订单，无法切换角色」。排查发现后端 `POST /api/user/role` 是一次性设角色接口（`RoleController.java:54`，角色非 UNSET 直接 409 `ROLE_ALREADY_SET`），后端根本没有角色切换端点；客户端把该码误命名为 `activeOrderRoleSwitchBlocked` 并映射成订单拦截文案。前端已删掉这个必然失败的入口并修正错码语义。

下面按「必须回答」和「确认即可」两档列，每条都标了证据出处。后端仓库指 `/Users/mac/Downloads/demo`。

---

## 一、必须回答（挡住功能决策）

### Q1. 双身份到底做不做？

- **现状**：后端 `RoleController.setRole` 角色一经设定不可改，全仓无切换端点（`docs/api_spec.yaml` 里 `role` 相关路径只有 `/api/user/role` 一条）。
- **冲突**：本仓库 `docs/02-mvp-scope.md:24` 把「角色切换拦截」列为 **P0**，`docs/03-user-stories.md:129` 有 US-ROLE-002「角色切换成功」，`docs/04-user-flows-and-state-machine.md:275` 画了完整的切换拦截流程图。这些都是照着一份从未在后端落地的契约写的。
- **要什么答复**：
  - 若**要做**：需要新增端点（建议 `PUT /api/user/role`），并明确活跃订单拦截规则——拦哪些状态？建议与账户注销的 `UserService.java:35-43` 两个 `ACTIVE_ORDER_STATUSES` 常量保持一致，拦截时返回哪个错误码（不要复用 `ROLE_ALREADY_SET`）。切换后旧角色的历史订单如何呈现？是否重新签发 token？
  - 若**不做**：请确认「一号一身份」是最终产品形态，我们把 `docs/02` `docs/03` `docs/04` 三份文档里的角色切换章节一并删掉，并在角色选择页明确提示不可逆（已加）。
- **前端现状**：设置页入口已删除，`RoleSelectionView` 保留首次选角色的 409 兜底分支。

### Q2. `/api/user/role` 的契约没写进 spec

`docs/api_spec.yaml:683-700` 里这个端点只写了 `'200': description: OK` + `schema: type: object`，**既没写 409 `ROLE_ALREADY_SET`，也没写成功返回体里有 `token`**。前端实际依赖的返回是 `RoleController.java:79` 的 `{success, role, token}`。

这正是这次踩坑的根源——前端只能猜语义。**请补全该端点的 spec**（成功体字段 + 409 分支）。

### Q3. `/api/user/role` 的返回体不走统一信封

其它端点都返回 `ApiResponse`（`{success, code, message, data}`），只有这一个返回裸 `Map.of("success","role","token")`。前端为它单独写了 `SetRoleResponse`。

问：这是有意为之还是历史遗留？若计划统一成信封，请提前通知——前端要改解码。

---

## 二、确认即可（回一句是/否就行）

### Q4. 这三个错误码是否永远不会出现？

前端曾定义、后端 `ErrorCode.java` 里查无此码，已在本次改动中删除：

| 码 | 前端原文案 |
|---|---|
| `PROFILE_INCOMPLETE` | 请先完善个人资料。 |
| `LOCATION_PERMISSION_REQUIRED` | 需要定位权限才能继续操作。 |
| `RATE_LIMITED` | 操作过于频繁，请稍后重试。 |

请确认**包括网关 / Nginx / 拦截器层在内**都不会吐这三个码。限流统一走 429 `TOO_MANY_REQUESTS`（`GlobalExceptionHandler.java:223`），对吗？

### Q5. `rateLimitBucket` 是否有计划？

前端 `ErrorResponse` 和 `APIErrorEnvelope` 都在解析 `rateLimitBucket` 字段（枚举 `AUTH` / `REGISTRATION` / `GENERAL`），但后端 429 handler（`GlobalExceptionHandler.java:219-230`）只发 `retryAfterSeconds` 和 `Retry-After` 头，**从不发 bucket**。

问：后端是否计划区分限流桶？不计划的话前端把这个字段删掉（目前恒为 nil，属于死代码）。

### Q6. `DUPLICATE_ORDER` 的语义边界

`docs/api_spec.yaml` 写的是「已有进行中订单（PENDING_MATCH/PENDING_ACCEPT/IN_PROGRESS/DRIVER_EN_ROUTE/DRIVER_ARRIVED/REMATCHING）时拒绝，409」。前端文案已据此从「存在重复订单。」改为「**您已有进行中的订单，完成后才能再次预约。**」

请确认这个码**不会**用于其它「重复」场景（例如同一请求重复提交、幂等键冲突）。若将来要复用，请新开一个码——这正是 `ROLE_ALREADY_SET` 这次出事的模式。

### Q7. `ORDER_IN_PROGRESS` 目前只有一个抛出点？

后端仅在取消受阻处抛（`OrderService`，message「志愿者已出发或服务进行中，如需取消请联系志愿者」）。前端文案已按这个唯一场景写死。

请确认；若复用到别的场景，需提前通知前端改成通用文案。

### Q8. `ORDER_PERMISSION_DENIED` 的剩余覆盖面

它是 `OrderPermissionException` 的**默认兜底构造**（`OrderPermissionException.java:22`），目前单参调用点只有一处：`OrderQueryService.java:39`「您无权查看此订单」。前端文案是「没有权限操作此订单。」（查看 vs 操作，略有出入）。

问：这个码今后还会兜住哪些场景？如果只有「无权查看订单」这一种，前端把文案改成「您无权查看此订单」更准确。

---

## 三、本次已核对无误的部分（无需回复，仅备案）

- **端点覆盖**：把客户端代码里所有 `/api/*` 调用路径与 `docs/api_spec.yaml` 的 60 条路径做了全量比对，**没有任何客户端调用打到不存在的端点**。唯一的例外 `/api/volunteer/mock-verification/approve` 只在 `currentEnvironment == .mock` 下可达（`VolunteerModule.swift:120-123` 门控），走本地 MockAPIClient，不会打到真实后端。
- **错误码覆盖**：后端 `ErrorCode.java` 的 35 个码，客户端 `ErrorCode` 枚举**全部覆盖，无缺失**。
- **语义已核对一致、不动的码**：`VOLUNTEER_NOT_AVAILABLE`（对应 `DispatchService.java:290` 关闭可服务状态）、`VOLUNTEER_NOT_VERIFIED`、`IDENTITY_NOT_VERIFIED`、`EMERGENCY_CONTACT_REQUIRED`、`CONTACT_LIMIT_EXCEEDED` / `CONTACT_MINIMUM_REQUIRED` / `CONTACT_FIELD_REQUIRED`。

---

## 四、给后端的一条流程建议

这次的根因不是某个码写错了，而是**码的名字与语义脱节，且客户端优先用本地文案覆盖了后端 message**（`APIClient.swift:84`）。建议在 `docs/api_spec.yaml` 里维护一张权威的「错误码 → 触发场景 → 建议用户文案」表，新增或复用错误码时同步更新。前端据此对齐，就不会再出现「后端说身份已设定、界面说你有进行中的订单」这种事。
