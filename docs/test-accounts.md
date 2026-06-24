# 测试账号 & 对接指南（前端）

> **版本**: v1.2.0 | **更新**: 2026-05-23
> **对接人**: 后端 Jayden

---

## 一、环境地址

| 项目 | 地址 |
|------|------|
| API Base URL | `http://47.114.113.171` |
| Swagger UI | 当前已关闭，联调契约以仓库 `docs/` 为准 |

---

## 二、用户测试账号

云端已提供以下预置用户账号，供 iOS 与云端 API / WebSocket 联调使用。预置测试账号的演示验证码统一为 `000000`。
`scripts/cloud-e2e.mjs` 默认使用主账号；如需覆盖账号，可设置 `AIDRUN_E2E_BLIND_PHONE` 和 `AIDRUN_E2E_VOLUNTEER_PHONE`。

| 手机号 | 角色 | 状态 | 推荐用途 |
|------|------|------|------|
| `13800000001` | 盲人用户 | 已认证 | 云端 E2E 盲人端主账号 |
| `13800000003` | 盲人用户 | 已认证 | 云端 E2E 盲人端备用账号 |
| `13800000002` | 志愿者 | 注册完成、已认证 | 云端 E2E 志愿者主账号 |
| `13800000004` | 志愿者 | 注册完成、已认证 | 云端 E2E 志愿者备用账号 |

前端仓库不接入真实 SMS，也不保存真实短信验证码。若需要用非预置手机号跑自动化 E2E，必须由后端提供测试账号或可自动化验证的测试验证码机制。

### 2.1 创建测试用户（通用步骤）

**步骤 1**: 发送验证码

```
POST /api/auth/send-code
Content-Type: application/json

{
  "phone": "13800010001"
}
```

响应：
```json
{
  "success": true,
  "message": "验证码已发送"
}
```

> 当前云端预置测试账号实测验证码为 `000000`。非预置手机号不作为前端自动化 E2E 的默认前提。

**步骤 2**: 验证码登录

```
POST /api/auth/verify-code
Content-Type: application/json

{
  "phone": "13800010001",
  "code": "000000"
}
```

响应：
```json
{
  "success": true,
  "token": "eyJhbGciOi...",
  "userId": 1
}
```

**步骤 3**: 设置角色（**必须保存返回的新 token！**）

```
POST /api/user/role
Authorization: Bearer <步骤2的token>
Content-Type: application/json

{
  "role": "BLIND"  // 或 "VOLUNTEER"
}
```

响应：
```json
{
  "success": true,
  "role": "BLIND",
  "token": "eyJhbGciOi..."  // ← 新 token，必须替换旧的！
}
```

### 2.2 盲人用户完整流程

```bash
# 假设已登录并设置角色为 BLIND，拿到 token

# 1. 完善盲人资料
curl -X PUT http://47.114.113.171/api/blind/profile \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "测试盲人",
    "runningPace": "MODERATE",
    "hasGuideDog": false
  }'

# 2. 添加紧急联系人（至少1个才能下单）
curl -X POST http://47.114.113.171/api/users/{userId}/emergency-contacts \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "紧急联系人",
    "phone": "13900139001",
    "relationship": "家人"
  }'

# 3. 连接 WebSocket
# ws://47.114.113.171/ws/blind?token=<token>

# 4. 创建订单
curl -X POST http://47.114.113.171/api/orders \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "startLatitude": 39.9042,
    "startLongitude": 116.4074,
    "startAddress": "朝阳公园南门",
    "plannedStartTime": "2099-06-01T18:00:00",
    "plannedEndTime": "2099-06-01T19:00:00"
  }'
```

### 2.3 志愿者用户完整流程

```bash
# 假设已登录并设置角色为 VOLUNTEER，拿到 token

# 1. 完善志愿者资料
curl -X PUT http://47.114.113.171/api/volunteer/profile \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "测试志愿者",
    "paceRange": "MODERATE",
    "acceptsGuideDog": true,
    "availableTimeSlots": [
      { "dayOfWeek": "SATURDAY", "startTime": "09:00", "endTime": "12:00" },
      { "dayOfWeek": "SUNDAY", "startTime": "09:00", "endTime": "12:00" }
    ]
  }'

# 2. Mock 志愿者认证：MVP 自动 approved，不调用真实身份认证或管理员审核接口

# 3. 连接 WebSocket
# ws://47.114.113.171/ws/volunteer?token=<token>

# 4. 上报位置
# 通过 WebSocket 发送: {"type":"LOCATION_UPDATE","lat":39.92,"lng":116.47}

# 5. 接单
curl -X POST http://47.114.113.171/api/orders/{orderId}/respond \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "ACCEPT"
  }'
```

---

## 三、Postman 快速导入

### 3.1 导入 API 规范

1. 打开 Postman → Import → 选择 File
2. 选择 `docs/07-api-contract.openapi.yaml`
3. Postman 会自动识别 OpenAPI 3.1 格式并生成所有请求

### 3.2 配置认证

1. 在 Postman Collection 中设置 Variables：
   - `base_url` = `http://47.114.113.171`
   - `token` = （登录后获取）

2. 在 Collection Auth 中设置：
   - Type: Bearer Token
   - Token: `{{token}}`

### 3.3 推荐的测试顺序

1. **发送验证码** → `POST /api/auth/send-code`
2. **登录** → `POST /api/auth/verify-code`（MVP 测试验证码固定为 `000000`）
3. **设置角色** → `POST /api/user/role`（**保存返回的新 token 到变量**）
4. 根据角色继续后续操作

---

## 四、常见问题

### Q: 验证码是什么？
MVP 测试阶段验证码固定为 `000000`，不接入真实短信。

### Q: 设置角色后 403 了？
设置角色后返回的新 token 包含角色信息。如果你还在用旧 token，会因为缺少角色而被 403 拒绝。**必须替换为新 token**。

### Q: 为什么创建订单失败？
创建订单需要：
1. 用户角色为 BLIND
2. 至少添加 1 个紧急联系人
3. Token 中包含角色信息（已设置角色并替换 token）

### Q: 志愿者收不到派单？
志愿者必须：
1. 完善志愿者资料并由 MVP Mock 认证自动 approved
2. 手动开启可服务状态
3. WebSocket 保持连接
4. 定时上报位置（至少一次）

### Q: WebSocket 连接被拒绝？
检查：
- token 是否有效（未过期、未登出）
- 连接的端点是否匹配角色（BLIND → `/ws/blind`，VOLUNTEER → `/ws/volunteer`）

### Q: 手机号格式要求？
11 位中国手机号：以 1 开头，第二位 3-9。正则：`^1[3-9]\d{9}$`

---

## 五、验证码获取方式

预置测试账号验证码固定为 `000000`。如果预置账号返回验证码错误或过期，需要后端确认测试验证码策略是否已开启。

---

## 六、后端待修问题（2026-06-19 联调）

以下问题不能由前端伪造状态或绕过业务校验修复：

1. `GET/PUT /api/volunteer/profile` 必须持久化并返回 `isAvailable`；开启后 `/api/orders/available` 应返回可接订单。
2. 接单失败不得返回 HTTP 500，应返回 `VOLUNTEER_NOT_AVAILABLE`、`ORDER_ALREADY_ACCEPTED` 等统一业务错误。
3. 创建距当前时间不足 30 分钟的预约必须拒绝，并返回 `APPOINTMENT_TOO_SOON`。
4. 验证码错误应返回统一 `INVALID_VERIFICATION_CODE` 错误结构；前端暂时兼容当前 `{ "error": ... }`。
5. 当前用户读取自己的紧急联系人时应返回完整电话，或明确提供“不修改掩码电话”的更新语义。
6. 后端需明确在没有盲人确认按钮的流程中，`DRIVER_ARRIVED -> IN_PROGRESS` 的触发方和接口。
