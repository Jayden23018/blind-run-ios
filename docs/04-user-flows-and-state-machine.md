# 04 — 用户流程与状态机

## 1. App 整体导航图

```mermaid
flowchart TD
    subgraph Common["通用流程"]
        Login["登录页\n(手机号 + 验证码)"]
        RoleSelect{"角色选择页\n(首次登录)"}
        Settings["设置页"]
        ProfileEdit["个人资料编辑"]
    end

    subgraph BlindRunner["盲人跑者端"]
        BR_Profile["盲人资料页\n(首次注册)"]
        BR_Home{"盲人首页\n(有/无活跃订单)"}
        CreateBooking["创建预约页"]
        BR_OrderStatus["订单状态等待页\n(PENDING_MATCH/PENDING_ACCEPT/DRIVER_EN_ROUTE/DRIVER_ARRIVED/REMATCHING)"]
        BR_InService["盲人服务中页\n(IN_PROGRESS)"]
        BR_Completed["完成/评分页\n(COMPLETED)"]
    end

    subgraph Volunteer["志愿者端"]
        VOL_Profile["志愿者认证页\n(首次注册)"]
        VOL_Home["志愿者首页\n(系统派单工作台+可服务开关)"]
        VOL_DispatchPrompt["30秒派单弹窗"]
        VOL_OrderDetail["已接订单详情页"]
        VOL_InService["志愿者服务中页"]
        VOL_History["服务记录页"]
        VOL_Points["积分/商城占位页"]
    end

    Login -->|"验证码正确"| RoleSelect
    Login -->|"已有token"| BR_Home
    Login -->|"已有token"| VOL_Home

    RoleSelect -->|"选择盲人跑者"| BR_Profile
    RoleSelect -->|"选择志愿者"| VOL_Profile

    BR_Profile -->|"资料完成"| BR_Home
    VOL_Profile -->|"认证完成"| VOL_Home

    BR_Home -->|"开始约跑"| CreateBooking
    BR_Home -->|"查看当前订单"| BR_OrderStatus
    CreateBooking -->|"提交预约"| BR_OrderStatus
    BR_OrderStatus -->|"服务开始"| BR_InService
    BR_OrderStatus -->|"取消订单"| BR_Home
    BR_InService -->|"服务完成"| BR_Completed
    BR_Completed -->|"评分/返回"| BR_Home

    VOL_Home -->|"收到 NEW_ORDER"| VOL_DispatchPrompt
    VOL_DispatchPrompt -->|"接受派单"| VOL_InService
    VOL_OrderDetail -->|"调试/兼容接单成功"| VOL_InService
    VOL_InService -->|"结束服务"| VOL_Home

    VOL_Home -->|"服务记录"| VOL_History
    VOL_Home -->|"积分商城"| VOL_Points
    VOL_Home -->|"设置"| Settings
    BR_Home -->|"设置"| Settings
    Settings -->|"编辑资料"| ProfileEdit

    BR_Home -.->|"切换角色"| VOL_Home
    VOL_Home -.->|"切换角色"| BR_Home
```

## 2. 订单状态机

```mermaid
stateDiagram-v2
    [*] --> PENDING_MATCH: 盲人提交预约

    PENDING_MATCH --> PENDING_ACCEPT: 志愿者接单成功\n(API: POST /api/orders/{orderId}/respond, action=ACCEPT)
    PENDING_MATCH --> CANCELLED: 盲人取消\n(API: POST /api/orders/{orderId}/cancel)
    PENDING_MATCH --> NO_VOLUNTEER: 无可用志愿者

    PENDING_ACCEPT --> DRIVER_EN_ROUTE: 志愿者点击"我已出发"\n(API: POST /api/orders/{orderId}/en-route)
    PENDING_ACCEPT --> CANCELLED: 盲人取消\n(API: POST /api/orders/{orderId}/cancel)
    PENDING_ACCEPT --> REMATCHING: 志愿者取消\n(API: POST /api/orders/{orderId}/cancel)

    DRIVER_EN_ROUTE --> DRIVER_ARRIVED: 志愿者点击"我已到达"\n(API: POST /api/orders/{orderId}/arrived)
    DRIVER_EN_ROUTE --> REMATCHING: 志愿者取消\n(API: POST /api/orders/{orderId}/cancel)

    DRIVER_ARRIVED --> IN_PROGRESS: 志愿者点击"开始服务"\n(API: POST /api/orders/{orderId}/start-service)
    DRIVER_ARRIVED --> REMATCHING: 志愿者取消\n(API: POST /api/orders/{orderId}/cancel)

    IN_PROGRESS --> COMPLETED: 志愿者结束服务\n(API: POST /api/orders/{orderId}/finish)
    IN_PROGRESS --> REMATCHING: 志愿者取消\n(API: POST /api/orders/{orderId}/cancel)
    REMATCHING --> CANCELLED: 盲人取消\n(API: POST /api/orders/{orderId}/cancel；盲人 token)

    COMPLETED --> [*]: 订单结束
    CANCELLED --> [*]: 订单结束
    NO_VOLUNTEER --> [*]: 订单结束
```

### 状态流转规则表

| 当前状态 | 允许的目标状态 | 触发者 | 说明 |
|----------|---------------|--------|------|
| PENDING_MATCH | PENDING_ACCEPT | 志愿者 | 接单（乐观锁保护） |
| PENDING_MATCH | CANCELLED / NO_VOLUNTEER | 盲人 / 系统 | 手动取消或无可用志愿者 |
| PENDING_ACCEPT | DRIVER_EN_ROUTE | 志愿者 | 标记出发 |
| PENDING_ACCEPT | CANCELLED | 盲人 | 服务开始前盲人可取消 |
| PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS | REMATCHING | 志愿者 | 志愿者取消后进入重新匹配，志愿者端退出当前服务流程 |
| DRIVER_EN_ROUTE | DRIVER_ARRIVED | 志愿者 | 标记到达 |
| DRIVER_ARRIVED | IN_PROGRESS | 志愿者 | 开始服务；调用 `POST /api/orders/{orderId}/start-service`，iOS 不允许从 DRIVER_ARRIVED 直接结束 |
| IN_PROGRESS | COMPLETED | 志愿者 | 正常结束 |
| REMATCHING | CANCELLED | 盲人 | 志愿者主动取消已接单订单后进入重新匹配；盲人可用自己的 token 调用 `/cancel` 退出本次订单，志愿者 token 不适用 |

取消按钮显示规则：

- 盲人跑者端仅在 `PENDING_MATCH`、`PENDING_ACCEPT`、`REMATCHING` 显示"取消订单"，均需二次确认。
- 志愿者端仅在 `PENDING_ACCEPT`、`DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS` 显示"取消订单"，均需二次确认；取消成功后不再用志愿者 token 拉取该订单详情。
- 盲人跑者端在 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS` 不显示取消按钮；当前 release 也不显示求助入口，真实安全求助需后续专项恢复。

### 禁止的流转

- COMPLETED / CANCELLED / NO_VOLUNTEER → 任何状态（终态）
- 后端 emergency event 不得作为订单状态；当前 release iOS UI 不触发该事件。

## 3. 盲人跑者正向流程（Happy Path）

```mermaid
sequenceDiagram
    actor BR as 盲人跑者
    participant App as iOS App
    participant API as 后端 API
    actor VOL as 志愿者

    BR->>App: 打开 App
    App->>API: POST /api/auth/send-code
    App->>API: POST /api/auth/verify-code (手机号 + 000000)
    API-->>App: { token, userId, role }
    App->>BR: 显示盲人首页
    Note over App: TTS: "欢迎来到助盲跑"

    BR->>App: 点击"开始约跑"
    App->>App: 检查定位权限
    App->>BR: 显示语音优先引导式创建预约页

    BR->>App: 确认出发地点（当前位置或高德 POI）
    BR->>App: 使用 DatePicker 选择至少 30 分钟后的预约时间
    BR->>App: 可选填写路线备注、时长、配速、路线偏好、导盲犬和特殊说明
    BR->>App: 在确认页点击"提交预约"
    App->>API: POST /api/orders (booking data)
    API-->>App: { orderId, status: "PENDING_MATCH" }
    Note over App: TTS: "订单提交成功，系统正在为您派单"

    loop 每5秒轮询
        App->>API: GET /api/orders/{orderId}
        API-->>App: { status: "PENDING_MATCH" }
    end

    API-->>VOL: WebSocket NEW_ORDER（30秒响应）
    VOL-->>API: 接受派单 (POST /api/orders/{orderId}/respond, action=ACCEPT)
    Note over API: 状态: PENDING_MATCH → PENDING_ACCEPT

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "PENDING_ACCEPT", volunteer: {...} }
    Note over App: TTS: "志愿者已接单"，朗读预约时间和出发地点，提示前往或等待在出发地点

    VOL-->>API: 出发 (POST /api/orders/{orderId}/en-route)
    Note over API: 状态: PENDING_ACCEPT → DRIVER_EN_ROUTE
    Note over App: 后续提示: "志愿者已出发，正在前往出发地点"

    VOL-->>API: 到达 (POST /api/orders/{orderId}/arrived)
    Note over API: 状态: DRIVER_EN_ROUTE → DRIVER_ARRIVED

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "DRIVER_ARRIVED" }
    Note over App: TTS: "志愿者已到达约定地点"

    VOL-->>API: 开始服务 (POST /api/orders/{orderId}/start-service)
    Note over API: 状态: DRIVER_ARRIVED → IN_PROGRESS
    App->>API: WebSocket / 轮询获取服务开始状态
    API-->>App: { status: "IN_PROGRESS" }
    Note over App: TTS: "服务已开始"

    VOL-->>API: 结束服务 (POST /api/orders/{orderId}/finish)
    Note over API: 状态: IN_PROGRESS → COMPLETED

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "COMPLETED" }
    Note over App: TTS: "服务已完成"

    BR->>App: 对志愿者评分（可选）
    App->>App: 返回盲人首页
```

## 4. 志愿者正向流程（Happy Path）

```mermaid
sequenceDiagram
    actor VOL as 志愿者
    participant App as iOS App
    participant API as 后端 API
    participant AMap as 高德地图

    VOL->>App: 打开 App（已有 token）
    App->>API: 验证 token
    API-->>App: token 有效
    App->>VOL: 显示系统派单工作台
    App->>API: GET /api/volunteer/dispatch-summary
    API-->>App: 派单状态、覆盖范围、统计、当前订单
    App->>API: 连接 /ws/volunteer
    App->>API: WebSocket LOCATION_UPDATE（当前位置）
    API-->>App: WebSocket NEW_ORDER（30秒倒计时）
    App->>VOL: 显示接受 / 拒绝派单弹窗

    VOL->>App: 点击"接受"
    App->>API: WebSocket LOCATION_UPDATE（接单前补报当前位置）
    App->>API: POST /api/orders/{orderId}/respond (action=ACCEPT)
    API-->>App: { status: "PENDING_ACCEPT" }
    App->>API: GET /api/orders/{orderId} + GET /api/volunteer/dispatch-summary
    App->>VOL: 进入志愿者服务流，显示"前往出发地点"
    App->>AMap: 服务流地图中心固定出发地点，红色出发地点 marker 按 id 更新并保持稳定；当前位置仅作辅助显示

    VOL->>App: 点击"我已出发"
    App->>API: POST /api/orders/{orderId}/en-route
    API-->>App: { status: "DRIVER_EN_ROUTE" }

    VOL->>App: 到达后点击"我已到达"
    App->>API: POST /api/orders/{orderId}/arrived
    API-->>App: { status: "DRIVER_ARRIVED" }

    VOL->>App: 点击"开始服务"
    App->>API: POST /api/orders/{orderId}/start-service
    API-->>App: { status: "IN_PROGRESS" }

    VOL->>App: 服务结束点击"结束服务"
    App->>App: 弹出确认弹窗
    VOL->>App: 确认
    App->>API: POST /api/orders/{orderId}/finish
    API-->>App: { status: "COMPLETED" }
    App->>VOL: 显示"服务完成，获得 +100 积分"
```

## 5. 紧急求助当前 release 处理

```mermaid
sequenceDiagram
    actor User as 任一方用户
    participant App as iOS App
    participant Probe as 合同探针脚本
    participant API as 云端 API

    Note over User,App: 订单状态为 DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS

    User->>App: 查看订单/服务页面
    App->>User: 不显示"紧急求助"或"一键求助"入口

    Probe->>API: POST /api/emergency/trigger
    API-->>Probe: emergency event
    Note over Probe,API: 仅验证后端合同，不代表 iOS UI 已上线求助能力
```

## 6. 角色切换拦截流程

```mermaid
flowchart TD
    Switch["用户点击切换角色"]
    CheckActive{"检查活跃订单\n(PENDING_ACCEPT / DRIVER_EN_ROUTE /\nDRIVER_ARRIVED / IN_PROGRESS)"}
    Block["弹出警告弹窗\n'您有进行中的订单，无法切换角色'"]
    Stay["保持当前角色页面"]
    Allow["切换到目标角色\n导航至对应首页"]

    Switch --> CheckActive
    CheckActive -->|"存在活跃订单"| Block
    Block --> Stay
    CheckActive -->|"无活跃订单"| Allow
```

## 7. 轮询机制

```mermaid
sequenceDiagram
    participant App as iOS App
    participant API as 后端 API
    participant TTS as AVSpeechSynthesizer

    loop 每5秒（仅订单相关页面）
        App->>API: GET /api/orders/{orderId}
        API-->>App: { status, ... }

        alt 状态变化
            App->>App: 更新 UI
            App->>TTS: 播报新状态
            TTS-->>App: 播报完成
        else 状态未变
            App->>App: 保持当前 UI
        end

        Note over App: 等待 5 秒后再次请求
    end

    Note over App: 离开订单页面时停止轮询
```

### 需要轮询的页面

| 页面 | 角色 | 轮询终止条件 |
|------|------|-------------|
| 订单状态等待页 | 盲人 | 页面离开 / 订单进入终态 |
| 盲人服务中页 | 盲人 | 页面离开 / 订单进入终态 |
| 志愿者服务中页 | 志愿者 | 页面离开 / 订单进入终态 |
| 志愿者订单详情页（已接单） | 志愿者 | 页面离开 |
## 会话与账户生命周期流程

```text
启动 -> 读取本地 JWT -> GET /api/auth/me
  -> 有效且角色为 BLIND/VOLUNTEER -> 建立对应 WebSocket -> 角色主页
  -> 有效且角色缺省/UNSET -> 不建立角色 WebSocket -> 角色选择
  -> 401/已删除账户 -> 完整清理本地会话 -> 登录

确认退出 -> POST /api/auth/logout
  -> 200/401 -> 完整本地清理 -> 登录
  -> 网络/5xx -> 保留会话 -> 重试 / 二次确认“仅退出本机”

账户删除第一阶段确认 -> 活动订单预检 -> 第二阶段确认 -> DELETE /api/users/{currentUser.id}
  -> 成功 -> 完整本地清理 -> 登录
  -> 活动订单/其他失败 -> 保留账户与会话
```
