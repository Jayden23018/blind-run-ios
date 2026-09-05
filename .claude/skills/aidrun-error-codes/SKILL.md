---
name: aidrun-error-codes
description: AidRun 后端错误码语义表与前端映射规则，含 DUPLICATE_ORDER 一码两义、PROFILE_INCOMPLETE 根本不存在等历史陷阱。处理 API 错误、写 TTS 错误播报、新增错误分支时读。
---

# AidRun 错误码语义

从 `AGENTS.md` 第 7 节拆出，并按后端 `ErrorCode.java` **逐条核对过**（2026-08-04）。

**唯一真相是后端 `demo/src/main/java/com/example/demo/exception/ErrorCode.java`。**
本仓库不留副本，用 `node scripts/validate-error-codes.mjs` 对撞两边的枚举 ——
前端映射了后端不存在的码就是死分支，那条分支和真分支长得一模一样，读代码看不出来。

## 为什么单独成篇

这份表里至少四条是**用事故换来的**：

| 码 | 事故 |
|---|---|
| `DUPLICATE_ORDER` | 曾经一码两义，重复评价被 TTS 念成「下单受阻」文案 |
| `PROFILE_INCOMPLETE` | 文档里写了很久，后端 `ErrorCode.java` 里**根本没有**，真实后端永不返回 |
| `ORDER_PERMISSION_DENIED` | 曾被复用来表达「缺紧急联系人」，现已拆出专用码 |
| `INVALID_ORDER_STATUS` / `VOLUNTEER_NOT_APPROVED` | **`AGENTS.md` 的散文表里码名抄错**，真名是 `ORDER_STATUS_NOT_ALLOWED` / `VOLUNTEER_NOT_VERIFIED`。代码里映射的是对的，只有文档错 —— 这正是「文档不是真相源」的标本 |

新增错误分支前先查这张表，不要凭码名猜语义。

## 完整表（码名与 HTTP 均取自后端源）

| 码 | HTTP | 端点 | 语义 |
|---|---|---|---|
| `INVALID_VERIFICATION_CODE` | 400 | verify-code | 验证码错 |
| `IDENTITY_NOT_VERIFIED` | 403 | `POST /api/orders` | 排在 `EMERGENCY_CONTACT_REQUIRED` **之前**。当前版本**只引导不阻断**（后端从不读 `verifyStatus`） |
| `EMERGENCY_CONTACT_REQUIRED` | 403 | `POST /api/orders` | 取代此前复用的通用 `ORDER_PERMISSION_DENIED`。**这条是真门禁，UI 必须硬拦** |
| `CONTACT_MINIMUM_REQUIRED` | 400 | 删联系人 | 删最后一个联系人被拒，UI 也要拦 |
| `ORDER_NOT_FOUND` | 404 | — | 订单不存在 |
| `ORDER_ALREADY_ACCEPTED` | 409 | respond | 已被别人接走 |
| `ORDER_STATUS_NOT_ALLOWED` | 409 | 状态流转端点 | 当前状态不允许该动作（**不叫** `INVALID_ORDER_STATUS`） |
| `DUPLICATE_ORDER` | 409 | `POST /api/orders` | 自 2026-07-31 起**只**表示「已有进行中的订单」 |
| `REVIEW_ALREADY_SUBMITTED` | 409 | `POST /api/orders/{id}/review` | 2026-07-31 从 `DUPLICATE_ORDER` 拆出 |
| `ORDER_PERMISSION_DENIED` | 403 | — | 后端确认只剩「只读查询越权」一种场景，文案「您无权查看此订单。」 |
| `NOT_ORDER_PARTICIPANT` | 403 | emergency/trigger | 非订单参与者 |
| `VOLUNTEER_NOT_AVAILABLE` | 403 | — | 志愿者未开启接单 |
| `VOLUNTEER_NOT_VERIFIED` | 403 | — | 志愿者未通过审核（**不叫** `VOLUNTEER_NOT_APPROVED`） |
| `ROLE_ALREADY_SET` | 409 | `setRole` | **一次性设角色**，角色非 UNSET 直接 409。只会出现在首次选角色的并发场景，不是「有进行中订单挡住切换」 |
| `APPOINTMENT_TOO_SOON` | 422 | `POST /api/orders` | 起始时间距今不足 30 分钟（`EnvironmentConfig.minimumBookingLeadMinutes`） |
| `APPOINTMENT_TOO_LONG` | 422 | `POST /api/orders` | `plannedEndTime - plannedStartTime` > 300 分钟（N134）。**客户端当前到不了**：表单最大 120 分钟、语音夹在 10–300 |
| `APPOINTMENT_IN_NIGHT_WINDOW` | 422 | `POST /api/orders` | 🚨 **整段行程**（不是开始时刻）有任一刻落进 `[22:00, 05:00)`（N134）。`21:00–22:30` 拒、`21:00–22:00` 放行、`05:00–06:00` 放行。**两条都命中时后端返回 `APPOINTMENT_TOO_LONG`**，所以那句文案不提时段 |
| `TOO_MANY_REQUESTS` | 429 | emergency/trigger 等 | 带 `retryAfterSeconds` 与 `Retry-After` 头 |
| ~~`PROFILE_INCOMPLETE`~~ | — | — | **不存在**，不要映射 |
| ~~`LOCATION_PERMISSION_REQUIRED`~~ | — | — | **后端没有这个码**，位置权限是纯客户端概念 |
| ~~`ACTIVE_ORDER_ROLE_SWITCH_BLOCKED`~~ | — | — | 不存在，后端无角色切换端点 |

后端有、iOS 未映射的码**当场取，别在这里抄一份**（抄一份就是制造一个必然过期的第二源 ——
2026-09-05 核对时这句话写的是「只有 `ORDER_SELF_DISPATCH_FORBIDDEN` 一个」，实际是 14 个）：

```bash
git -C /Users/mac/Downloads/demo show origin/main:src/main/java/com/example/demo/exception/ErrorCode.java > /tmp/ec.java
AIDRUN_BACKEND_ERROR_CODES=/tmp/ec.java node scripts/validate-error-codes.mjs
```

未映射**不是缺陷**，落到「未知错误 (状态码)」而用户又无从补救时才是。判据：这个码客户端到得了吗？
到了之后用户能做点什么吗？两个都是「是」才值得映射。

## 紧急端点的错误面（独立一套）

`POST /api/emergency/trigger`：

- 成功：`{success, eventId, status}`，`status` 是 `EmergencyStatus` 的名字
- 冷却拒绝：**429** `TOO_MANY_REQUESTS`，带 `retryAfterSeconds` 与 `Retry-After` 头
- 非订单参与者：**403** `NOT_ORDER_PARTICIPANT`
- 未知订单：**400** `BAD_REQUEST`

## 前端映射规则

- 一码多义时走 `ErrorCode.prefersServerMessage` 白名单，不要在客户端硬编码文案覆盖服务端。
- **枚举解码遇未知值不得让整条 payload 崩掉。** 曾经一个不认识的订单状态会让整页数据（地址、坐标、电话、计划时间）一起丢。回归用例在 `blindRunTests/OrderEnumLeniencyDecodingTests.swift`。
- 错误文案会被 TTS 念给盲人听，**语义错误的代价是用户按错误信息做出错误行动**，不只是显示难看。
