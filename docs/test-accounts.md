# 测试账号 & 对接指南（前端）

> **版本**: v1.2.0 | **更新**: 2026-05-23
> **对接人**: 后端 Jayden

---

## 一、环境地址

| 项目 | 地址 |
|------|------|
| API Base URL | `http://47.114.113.171` |
| Swagger UI | 生产已关闭，本地开发可用 `http://localhost:8081/swagger-ui/index.html` |

---

## 二、CS 管理员账号

| 字段 | 值 |
|------|-----|
| 用户名 | `admin` |
| 密码 | `admin123` |
| 角色 | ADMIN |
| 部门 | 运营部 |

### 登录

```
POST /api/cs/auth/login
Content-Type: application/json

{
  "username": "admin",
  "password": "admin123"
}
```

响应：
```json
{
  "success": true,
  "token": "eyJhbGciOi...",
  "role": "ADMIN"
}
```

### 使用范围

- 志愿者身份证审核
- 培训课程管理
- 通知模板管理
- 紧急事件处理
- 所有 `/api/admin/**` 和 `/api/cs/**` 端点

---

## 三、用户测试账号（通过 API 创建）

普通用户账号通过手机验证码登录创建，没有预置账号。验证码会通过短信发送到你填的手机号上。

### 3.1 创建测试用户（通用步骤）

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

> 验证码会发到你填的手机号上，直接看手机短信即可。

**步骤 2**: 验证码登录

```
POST /api/auth/verify-code
Content-Type: application/json

{
  "phone": "13800010001",
  "code": "123456"  // ← 从后端日志中获取
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

### 3.2 盲人用户完整流程

```bash
# 假设已登录并设置角色为 BLIND，拿到 token

# 1. 完善盲人资料
curl -X PUT http://localhost:8081/api/blind/profile \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "测试盲人",
    "runningPace": "MODERATE",
    "hasGuideDog": false
  }'

# 2. 身份验证（二要素）
curl -X POST http://localhost:8081/api/blind/verify-identity \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "idCardName": "张三",
    "idCardNumber": "110101199001011234"
  }'

# 3. 添加紧急联系人（至少1个才能下单）
curl -X POST http://localhost:8081/api/users/{userId}/emergency-contacts \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "紧急联系人",
    "phone": "13900139001",
    "relationship": "家人"
  }'

# 4. 连接 WebSocket
# ws://localhost:8081/ws/blind?token=<token>

# 5. 创建订单
curl -X POST http://localhost:8081/api/orders \
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

### 3.3 志愿者用户完整流程

```bash
# 假设已登录并设置角色为 VOLUNTEER，拿到 token

# 1. 完善志愿者资料
curl -X PUT http://localhost:8081/api/volunteer/profile \
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

# 2. 注册 Step 1: 基本信息
curl -X POST http://localhost:8081/api/volunteer/registration/step1 \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "测试志愿者",
    "phone": "13800010002",
    "runningExperience": "有2年跑步经验",
    "hasGuidedBefore": false,
    "emergencyExperience": "无"
  }'

# 3. 注册 Step 2: 上传身份证
curl -X POST http://localhost:8081/api/volunteer/registration/step2/id-card \
  -H "Authorization: Bearer <token>" \
  -F "idCardName=张三" \
  -F "idCardNumber=440305200001011234" \
  -F "frontFile=@/path/to/id-front.jpg" \
  -F "backFile=@/path/to/id-back.jpg"

# 4. 注册 Step 3: 人脸验证
curl -X POST http://localhost:8081/api/volunteer/registration/step3/face-verify \
  -H "Authorization: Bearer <token>" \
  -F "facePhoto=@/path/to/face.jpg"

# 5. 管理员审核身份证（用 CS admin token）
curl -X POST http://localhost:8081/api/admin/volunteers/review/id \
  -H "Authorization: Bearer <admin-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 2,
    "approved": true
  }'

# 6. 注册 Step 4: 培训课程
# 获取课程列表
curl http://localhost:8081/api/volunteer/registration/training/courses \
  -H "Authorization: Bearer <token>"

# 提交学习进度
curl -X POST http://localhost:8081/api/volunteer/registration/training/progress \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "courseId": 1,
    "progressPercent": 100,
    "lastPositionSeconds": 900,
    "timeSpentSeconds": 900
  }'

# 获取测验题
curl http://localhost:8081/api/volunteer/registration/training/quiz/1 \
  -H "Authorization: Bearer <token>"

# 提交测验答案（每次提交一道题）
curl -X POST http://localhost:8081/api/volunteer/registration/training/quiz/answer \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "courseId": 1,
    "questionId": 1,
    "answers": ["5分钟内"],
    "timeSpentSeconds": 10
  }'

# 7. 连接 WebSocket
# ws://localhost:8081/ws/volunteer?token=<token>

# 8. 上报位置
# 通过 WebSocket 发送: {"type":"LOCATION_UPDATE","lat":39.92,"lng":116.47}

# 9. 响应派单
curl -X POST http://localhost:8081/api/orders/{orderId}/respond \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"action":"ACCEPT"}'
```

---

## 四、Postman 快速导入

### 4.1 导入 API 规范

1. 打开 Postman → Import → 选择 File
2. 选择 `docs/api_spec.yaml`
3. Postman 会自动识别 OpenAPI 3.1 格式并生成所有请求

### 4.2 配置认证

1. 在 Postman Collection 中设置 Variables：
   - `base_url` = 后端告诉你的地址
   - `token` = （登录后获取）

2. 在 Collection Auth 中设置：
   - Type: Bearer Token
   - Token: `{{token}}`

### 4.3 推荐的测试顺序

1. **发送验证码** → `POST /api/auth/send-code`
2. **登录** → `POST /api/auth/verify-code`（从后端日志获取验证码）
3. **设置角色** → `POST /api/user/role`（**保存返回的新 token 到变量**）
4. 根据角色继续后续操作

---

## 五、常见问题

### Q: 验证码是什么？
验证码会通过阿里云短信发送到你填的手机号，查手机短信即可。

### Q: 设置角色后 403 了？
设置角色后返回的新 token 包含角色信息。如果你还在用旧 token，会因为缺少角色而被 403 拒绝。**必须替换为新 token**。

### Q: 为什么创建订单失败？
创建订单需要：
1. 用户角色为 BLIND
2. 至少添加 1 个紧急联系人
3. Token 中包含角色信息（已设置角色并替换 token）

### Q: 志愿者收不到派单？
志愿者必须：
1. 完成 4 步注册流程（基本信息 + 身份证 + 人脸 + 培训）
2. 管理员审核身份证通过
3. WebSocket 保持连接
4. 定时上报位置（至少一次）

### Q: WebSocket 连接被拒绝？
检查：
- token 是否有效（未过期、未登出）
- 连接的端点是否匹配角色（BLIND → `/ws/blind`，VOLUNTEER → `/ws/volunteer`）

### Q: 手机号格式要求？
11 位中国手机号：以 1 开头，第二位 3-9。正则：`^1[3-9]\d{9}$`

---

## 六、验证码获取方式

验证码通过阿里云短信发送到你填的手机号，查手机短信即可。
