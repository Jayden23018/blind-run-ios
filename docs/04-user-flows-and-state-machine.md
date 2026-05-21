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
        BR_OrderStatus["订单状态等待页\n(匹配中/已接单/已到达)"]
        BR_InService["盲人服务中页\n(in_progress)"]
        BR_Emergency["紧急求助页\n(emergency)"]
        BR_Completed["完成/评分页\n(completed)"]
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
    BR_OrderStatus -->|"紧急求助"| BR_Emergency
    BR_InService -->|"服务完成"| BR_Completed
    BR_InService -->|"紧急求助"| BR_Emergency
    BR_Completed -->|"评分/返回"| BR_Home
    BR_Emergency --> BR_Home

    VOL_Home -->|"查看全部"| VOL_OrderList
    VOL_OrderList -->|"点击订单"| VOL_OrderDetail
    VOL_OrderDetail -->|"接单"| VOL_InService
    VOL_OrderDetail -->|"查看出发点位置(AMap)"| VOL_InService
    VOL_InService -->|"结束服务"| VOL_Home
    VOL_InService -->|"紧急求助"| BR_Emergency

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
    [*] --> matching: 盲人提交预约

    matching --> accepted: 志愿者接单成功\n(API: POST /api/orders/{orderId}/accept)
    matching --> cancelled: 盲人取消\n(API: POST /api/orders/{orderId}/cancel)
    matching --> cancelled: 超时自动取消\n(距预约时间<30min无人接单)

    accepted --> arrived: 志愿者点击"我已到达"\n(API: POST /api/orders/{orderId}/arrive)
    accepted --> cancelled: 任一方取消\n(API: POST /api/orders/{orderId}/cancel)
    accepted --> emergency: 任一方触发求助\n(API: POST /api/orders/{orderId}/emergency)

    arrived --> in_progress: 盲人确认开始服务\n(API: POST /api/orders/{orderId}/confirm-start)
    arrived --> cancelled: 任一方取消\n(API: POST /api/orders/{orderId}/cancel)
    arrived --> emergency: 任一方触发求助\n(API: POST /api/orders/{orderId}/emergency)

    in_progress --> completed: 志愿者结束服务\n(API: POST /api/orders/{orderId}/complete)
    in_progress --> emergency: 任一方触发求助\n(API: POST /api/orders/{orderId}/emergency)

    completed --> [*]: 订单结束
    cancelled --> [*]: 订单结束
    emergency --> [*]: 异常终态
```

### 状态流转规则表

| 当前状态 | 允许的目标状态 | 触发者 | 说明 |
|----------|---------------|--------|------|
| matching | accepted | 志愿者 | 接单（乐观锁保护） |
| matching | cancelled | 盲人 / 系统 | 手动取消或超时 |
| accepted | arrived | 志愿者 | 标记到达 |
| accepted | cancelled | 盲人 / 志愿者 | 服务开始前可取消 |
| accepted | emergency | 盲人 / 志愿者 | 一键求助 |
| arrived | in_progress | 盲人 | 确认开始服务 |
| arrived | cancelled | 盲人 / 志愿者 | 服务开始前可取消 |
| arrived | emergency | 盲人 / 志愿者 | 一键求助 |
| in_progress | completed | 志愿者 | 正常结束 |
| in_progress | emergency | 盲人 / 志愿者 | 一键求助 |

### 禁止的流转

- in_progress → cancelled（服务开始后不支持普通取消，只能走 emergency）
- emergency → 任何其他状态（MVP 不支持恢复或继续执行生命周期动作）
- completed → 任何状态（终态）
- cancelled → 任何状态（终态）

## 3. 盲人跑者正向流程（Happy Path）

```mermaid
sequenceDiagram
    actor BR as 盲人跑者
    participant App as iOS App
    participant API as 后端 API
    actor VOL as 志愿者

    BR->>App: 打开 App
    App->>API: POST /api/auth/phone-login (手机号 + 123456)
    API-->>App: { accessToken, user }
    App->>BR: 显示盲人首页
    Note over App: TTS: "欢迎来到助盲跑"

    BR->>App: 点击"开始约跑"
    App->>App: 检查定位权限
    App->>BR: 显示创建预约页

    BR->>App: 填写出发地点、时间、备注
    BR->>App: 点击"提交预约"
    App->>API: POST /api/orders (booking data)
    API-->>App: { orderId, status: "matching" }
    Note over App: TTS: "订单提交成功，等待志愿者接单"

    loop 每5秒轮询
        App->>API: GET /api/orders/{orderId}
        API-->>App: { status: "matching" }
    end

    VOL-->>API: 接单 (POST /api/orders/{orderId}/accept)
    Note over API: 状态: matching → accepted

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "accepted", volunteer: {...} }
    Note over App: TTS: "志愿者已接单"

    VOL-->>API: 到达 (POST /api/orders/{orderId}/arrive)
    Note over API: 状态: accepted → arrived

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "arrived" }
    Note over App: TTS: "志愿者已到达约定地点"

    BR->>App: 点击"确认开始服务"
    App->>API: POST /api/orders/{orderId}/confirm-start
    API-->>App: { status: "in_progress" }
    Note over App: TTS: "服务已开始"

    VOL-->>API: 结束服务 (POST /api/orders/{orderId}/complete)
    Note over API: 状态: in_progress → completed

    App->>API: GET /api/orders/{orderId}
    API-->>App: { status: "completed" }
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
    API-->>App: { status: "accepted" }
    App->>VOL: 显示盲人联系电话 + "查看地图"按钮

    VOL->>App: 点击"查看地图"
    App->>AMap: 显示出发点位置、当前位置和距离

    VOL->>App: 到达后点击"我已到达"
    App->>API: POST /api/orders/{orderId}/arrive
    API-->>App: { status: "arrived" }

    Note over API: 等待盲人确认开始

    App->>API: 轮询 → status: "in_progress"
    API-->>App: { status: "in_progress" }

    VOL->>App: 服务结束点击"结束服务"
    App->>App: 弹出确认弹窗
    VOL->>App: 确认
    App->>API: POST /api/orders/{orderId}/complete
    API-->>App: { status: "completed" }
    App->>VOL: 显示"服务完成，获得 +100 积分"
```

## 5. 紧急求助流程

```mermaid
sequenceDiagram
    actor User as 任一方用户
    participant App as iOS App
    participant API as 后端 API
    actor Other as 另一方用户

    Note over User,Other: 订单状态为 accepted / arrived / in_progress

    User->>App: 点击"紧急求助"按钮
    App->>User: 弹出确认弹窗\n"是否确认进入求助状态？\n确认后，本次服务将标记为异常"
    User->>App: 确认求助
    App->>API: POST /api/orders/{orderId}/emergency
    Note over API: 状态 → emergency
    API-->>App: { status: "emergency" }

    Note over App: TTS: "已进入求助状态"

    loop 另一方轮询
        Other->>API: GET /api/orders/{orderId}
        API-->>Other: { status: "emergency" }
        Note over Other: TTS: "进入求助状态" / UI 更新
    end

    Note over App,Other: 显示紧急联系人信息（盲人端）\n订单不可恢复，保持 emergency 终态
```

## 6. 角色切换拦截流程

```mermaid
flowchart TD
    Switch["用户点击切换角色"]
    CheckActive{"检查活跃订单\n(accepted / arrived /\nin_progress / emergency)"}
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
