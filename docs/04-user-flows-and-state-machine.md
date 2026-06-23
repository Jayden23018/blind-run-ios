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
        BR_OrderStatus["订单状态等待页\n(PENDING_MATCH/PENDING_ACCEPT/DRIVER_ARRIVED)"]
        BR_InService["盲人服务中页\n(IN_PROGRESS)"]
        BR_Emergency["紧急求助提示\n(emergency event)"]
        BR_Completed["完成/评分页\n(COMPLETED)"]
    end

    subgraph Volunteer["志愿者端"]
        VOL_Profile["志愿者认证页\n(首次注册)"]
        VOL_Home["志愿者首页\n(附近订单+可服务开关)"]
        VOL_OrderList["订单列表页"]
        VOL_OrderDetail["订单详情页"]
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
    BR_OrderStatus -->|"志愿者到达"| BR_InService
    BR_OrderStatus -->|"取消订单"| BR_Home
    BR_OrderStatus -->|"记录紧急事件"| BR_Emergency
    BR_InService -->|"服务完成"| BR_Completed
    BR_InService -->|"记录紧急事件"| BR_Emergency
    BR_Completed -->|"评分/返回"| BR_Home
    BR_Emergency --> BR_Home

    VOL_Home -->|"查看全部"| VOL_OrderList
    VOL_OrderList -->|"点击订单"| VOL_OrderDetail
    VOL_OrderDetail -->|"接单"| VOL_InService
    VOL_OrderDetail -->|"查看出发点位置(AMap)"| VOL_InService
    VOL_InService -->|"结束服务"| VOL_Home
    VOL_InService -->|"记录紧急事件"| BR_Emergency

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

    PENDING_MATCH --> PENDING_ACCEPT: 志愿者接单成功\n(API: POST /api/orders/{orderId}/accept)
    PENDING_MATCH --> CANCELLED: 盲人取消\n(API: POST /api/orders/{orderId}/cancel)
    PENDING_MATCH --> NO_VOLUNTEER: 无可用志愿者

    PENDING_ACCEPT --> DRIVER_EN_ROUTE: 志愿者点击"我已出发"\n(API: POST /api/orders/{orderId}/en-route)
    PENDING_ACCEPT --> CANCELLED: 任一方取消\n(API: POST /api/orders/{orderId}/cancel)

    DRIVER_EN_ROUTE --> DRIVER_ARRIVED: 志愿者点击"我已到达"\n(API: POST /api/orders/{orderId}/arrived)
    DRIVER_EN_ROUTE --> emergency_event: 任一方触发求助\n(API: POST /api/emergency/trigger)

    DRIVER_ARRIVED --> IN_PROGRESS: 服务开始\n(云端状态通知)
    DRIVER_ARRIVED --> emergency_event: 任一方触发求助\n(API: POST /api/emergency/trigger)

    IN_PROGRESS --> COMPLETED: 志愿者结束服务\n(API: POST /api/orders/{orderId}/finish)
    IN_PROGRESS --> CANCELLED: 任一方取消\n(API: POST /api/orders/{orderId}/cancel)
    IN_PROGRESS --> emergency_event: 任一方触发求助\n(API: POST /api/emergency/trigger)

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
| PENDING_ACCEPT | CANCELLED | 盲人 / 志愿者 | 服务开始前可取消 |
| DRIVER_EN_ROUTE | DRIVER_ARRIVED | 志愿者 | 标记到达 |
| DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS | emergency event | 盲人 / 志愿者 | 通过 `POST /api/emergency/trigger` 记录求助事件，订单状态不改为 emergency |
| DRIVER_ARRIVED | IN_PROGRESS | 系统 / 云端通知 | 服务开始；当前云端 REST 契约没有单独 start endpoint |
| IN_PROGRESS | COMPLETED | 志愿者 | 正常结束 |
| IN_PROGRESS | CANCELLED | 盲人 / 志愿者 | 服务中可取消 |

### 禁止的流转

- COMPLETED / CANCELLED / NO_VOLUNTEER → 任何状态（终态）
- emergency event → 订单状态（求助是独立事件，不是订单状态流转）

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
    App->>BR: 显示创建预约页

    BR->>App: 填写出发地点、时间、备注
    BR->>App: 点击"提交预约"
    App->>API: POST /api/orders (booking data)
    API-->>App: { orderId, status: "PENDING_MATCH" }
    Note over App: TTS: "订单提交成功，等待志愿者接单"

    loop 每5秒轮询
        App->>API: GET /api/orders/{orderId}
        API-->>App: { status: "PENDING_MATCH" }
    end

    VOL-->>API: 接单 (POST /api/orders/{orderId}/accept)
    Note over API: 状态: PENDING_MATCH → PENDING_ACCEPT

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "PENDING_ACCEPT", volunteer: {...} }
    Note over App: TTS: "志愿者已接单"

    VOL-->>API: 出发 (POST /api/orders/{orderId}/en-route)
    Note over API: 状态: PENDING_ACCEPT → DRIVER_EN_ROUTE

    VOL-->>API: 到达 (POST /api/orders/{orderId}/arrived)
    Note over API: 状态: DRIVER_EN_ROUTE → DRIVER_ARRIVED

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "DRIVER_ARRIVED" }
    Note over App: TTS: "志愿者已到达约定地点"

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
    App->>VOL: 显示志愿者首页
    App->>API: GET /api/orders/available
    API-->>App: [{ order1, order2, ... }]
    App->>App: 按距离排序

    VOL->>App: 查看订单列表
    App->>VOL: 距离最近订单排最前

    VOL->>App: 点击订单
    App->>API: GET /api/orders/{orderId}
    API-->>App: 订单详情（隐藏盲人电话）
    App->>VOL: 显示订单详情

    VOL->>App: 点击"接单"
    App->>API: POST /api/orders/{orderId}/accept
    API-->>App: { status: "PENDING_ACCEPT" }
    App->>VOL: 显示盲人联系电话 + "查看地图"按钮

    VOL->>App: 点击"查看地图"
    App->>AMap: 显示出发点位置、当前位置和距离

    VOL->>App: 点击"我已出发"
    App->>API: POST /api/orders/{orderId}/en-route
    API-->>App: { status: "DRIVER_EN_ROUTE" }

    VOL->>App: 到达后点击"我已到达"
    App->>API: POST /api/orders/{orderId}/arrived
    API-->>App: { status: "DRIVER_ARRIVED" }

    App->>API: WebSocket / 轮询 → status: "IN_PROGRESS"
    API-->>App: { status: "IN_PROGRESS" }

    VOL->>App: 服务结束点击"结束服务"
    App->>App: 弹出确认弹窗
    VOL->>App: 确认
    App->>API: POST /api/orders/{orderId}/finish
    API-->>App: { status: "COMPLETED" }
    App->>VOL: 显示"服务完成，获得 +100 积分"
```

## 5. 紧急求助流程

```mermaid
sequenceDiagram
    actor User as 任一方用户
    participant App as iOS App
    participant API as 后端 API
    actor Other as 另一方用户

    Note over User,Other: 订单状态为 DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS

    User->>App: 点击"紧急求助"按钮
    App->>User: 弹出确认弹窗\n"是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
    User->>App: 确认求助
    App->>API: POST /api/emergency/trigger
    Note over API: 记录 emergency event，订单状态不改为 emergency
    API-->>App: { success: true }

    Note over App: TTS: "已进入求助状态"

    loop 另一方轮询
        Other->>API: GET /api/orders/{orderId}
        API-->>Other: { type: "EMERGENCY_VOLUNTEER_ALERT" / "APP_NOTIFICATION" }
        Note over Other: TTS: "进入求助状态" / UI 更新
    end

    Note over App,Other: 显示求助提示；后续处理通过 emergency event 跟踪
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
