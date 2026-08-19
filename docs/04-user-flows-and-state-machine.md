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
        BR_Contacts["紧急联系人管理页\n(1~5 个，恰好 1 个主联系人)"]
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

    BR_Profile -->|"资料完成"| BR_Contacts
    BR_Contacts -->|"至少 1 个联系人且恰好 1 个主联系人"| BR_Home
    VOL_Profile -->|"认证完成"| VOL_Home

    BR_Home -->|"开始约跑"| CreateBooking
    BR_Home -->|"缺少紧急联系人 / 主联系人"| BR_Contacts
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

    BR_Home -.->|"切换角色（未决/未实现）"| VOL_Home
    VOL_Home -.->|"切换角色（未决/未实现）"| BR_Home
```

**【未决 / 未实现】** 上图两条虚线（切换角色）当前**不存在**：后端没有角色切换端点，App 内入口已删除。详见第 6 节。

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
- 盲人跑者端在 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS` 不显示取消按钮。

求助入口显示规则：

- 盲人跑者端仅在 `IN_PROGRESS` 显示"一键求助"，需二次确认（`RunOrderStatus.canBlindRunnerTriggerEmergency` / `canTriggerEmergency(as:)`，`blindRun/Core/Models/OrderModels.swift`）。
- 志愿者端同样仅在 `IN_PROGRESS` 显示求助入口（`canVolunteerTriggerEmergency == (self == .inProgress)`），**自 2026-07-31 起已开放**。~~此前全状态隐藏，因为后端按触发人建事件~~ —— 后端 commit `a5ba523`（SOS-1）把 `event.userId` 改为取订单的盲人方、用 `TriggerType.VOLUNTEER_BUTTON` 区分来源后，该理由不再成立。志愿者**没有撤销权**（后端 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`）：一对一陪跑里志愿者可能就是威胁来源，撤销权只在受助者本人和客服手里。

### 禁止的流转

- COMPLETED / CANCELLED / NO_VOLUNTEER → 任何状态（终态）
- 后端 emergency event 不得作为订单状态；盲人端触发求助后订单仍保持 `IN_PROGRESS`，`RunOrderStatus` 不因求助改变。

## 3. 盲人跑者正向流程（Happy Path）

### 下单前置条件

创建预约（`POST /api/orders`）在以下条件全部满足前必须被阻断：

1. 当前角色为 `BLIND`。
2. 盲人基础资料完整。
3. **实名认证已通过（`verifyStatus == VERIFIED`）。** 外部后端 `OrderCreationService` 自 2026-07-30 起硬校验此项，未通过返回 403 `IDENTITY_NOT_VERIFIED`。
4. **已保存 1～5 个紧急联系人，且其中恰好 1 个为主联系人。** 后端只检查联系人是否存在（缺失时 403 `EMERGENCY_CONTACT_REQUIRED`），客户端的阻断与之保持一致并额外要求主联系人唯一。
5. 定位权限已授予。
6. 已确认出发地点。
7. 预约时间至少在当前时间 30 分钟之后。

第 3 条必须排在第 4 条**之前**：后端的判定顺序就是先实名后联系人，客户端顺序若相反，用户补完联系人仍会被 403 挡回来。实名状态（`BlindProfileResponse.verifyStatus`）仅 `NOT_VERIFIED` / `VERIFIED` / `FAILED` 三态，字段缺失一律按未通过处理。

任一条件不满足时，App 展示并播报**第一个可执行的**缺失项，"重复当前状态"必须包含该阻断原因。

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

## 5. 盲人一键求助流程

```mermaid
sequenceDiagram
    actor BR as 盲人跑者
    participant App as iOS App
    participant Loc as LocationService
    participant API as 云端 API

    Note over BR,App: 仅订单状态为 IN_PROGRESS 时显示入口，两端都显示（志愿者端自 2026-07-31 起已开放，见上文）

    BR->>App: 点击"一键求助"
    App->>BR: 二次确认"是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"

    alt 用户取消
        BR->>App: 取消
        App->>BR: 不发送任何请求，订单状态不变
    else 用户确认
        BR->>App: 确认求助
        App->>Loc: 取最新真实 GCJ-02 样本
        alt 无新鲜真实坐标
            Loc-->>App: nil
            App->>BR: "求助未发出：当前无法获取你的位置。请在设置中允许定位后重试，或直接拨打110。"
        else 有新鲜真实坐标
            Loc-->>App: GCJ-02 坐标
            App->>API: POST /api/emergency/trigger { orderId, gpsLat, gpsLng }
            alt 受理
                API-->>App: { success, eventId, status }
                App->>BR: 按 status 播报进行时文案；订单仍为 IN_PROGRESS
            else 冷却
                API-->>App: 429 TOO_MANY_REQUESTS + retryAfterSeconds
                App->>BR: 按权威秒数提示稍后再试 + 拨打110
            else 非参与方 / 订单不存在
                API-->>App: 403 NOT_ORDER_PARTICIPANT / 400 BAD_REQUEST
                App->>BR: "求助未发出：…" + 拨打110
            end
        end
    end

    API-->>App: EMERGENCY_CONTACT_NOTIFIED（实时通知）
    App->>BR: "系统正在联系你的紧急联系人，尚未确认对方是否收到。若情况危急请立即拨打110。"
    Note over App,BR: 永不声称短信已送达或联系人已被联系上
```

## 6. 角色切换拦截流程

**【未决 / 未实现】** 「一号一身份 vs 双身份」尚未有产品结论（见 `demo/docs/handoff.md` 2026-07-31「一号一身份是不是最终产品形态」）。后端当前**没有任何角色切换端点**，App 内切换角色入口已删除，下面这张图不描述任何已实现的流程。

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

## 8. App-lifetime 实时协调流程

```mermaid
sequenceDiagram
    participant WS as Role WebSocket
    participant ARC as AppRealtimeCoordinator
    participant VM as Feature ViewModel
    participant REST as REST API
    participant UI as Shared Foreground UI

    WS-->>ARC: ORDER_STATUS_CHANGED(messageId/orderId/fromStatus/toStatus)
    ARC-->>ARC: UUID/指纹去重并协调状态前进
    ARC-->>VM: 立即发布已校验目标状态
    VM-->>UI: 更新状态并用本地文案播报一次
    ARC-->>ARC: 按 orderId 合并后台详情刷新
    ARC-->>VM: pending refresh ID
    VM->>REST: GET /api/orders/{orderId}
    REST-->>VM: 完整 OrderDetail / 断线降级
    VM-->>UI: 补齐字段且不得回退已接受状态

    WS-->>ARC: APP_NOTIFICATION(messageId/eventType/priority)
    ARC-->>ARC: 生命周期语义抑制、普通去重、HIGH 抢占
    ARC-->>UI: 可见 + VoiceOver + TTS 等价呈现
```

- `ORDER_STATUS_CHANGED` 的相同 UUID/指纹重发不再次更新、播报或刷新；UUID 身份碰撞不采用内容，只触发一次有界安全刷新。缺失或非法 UUID 记录匿名合同异常后仍按旧消息兼容路径协调状态。
- REST 详情刷新与盲人端五秒轮询继续补齐完整字段并兜底断线或漏事件；WebSocket 即时状态不得被迟到 REST 旧值回退。
- 生命周期 `APP_NOTIFICATION` 与结构化状态事件并行到达时只播报客户端固定状态文案一次；终态移除活动订单后的 30 秒内继续按目标状态语义抑制模板通知，安全告警不受影响。
- `NEW_ORDER` 由协调器保留至响应、超时、失效或角色变化；志愿者首页重新出现时按原始截止时间恢复倒计时。
- 退出、角色/token 变化或 WebSocket 服务替换时先取消旧订阅，再清空前一用户的派单、通知、位置和安全事件内存状态。
- 重连后活动订单重新请求详情，志愿者摘要等依赖功能收到恢复信号并恢复自己的 cadence。
- `VOLUNTEER_LOCATION_UPDATE` / `BLIND_LOCATION_UPDATE` 只在角色、订单和坐标合法时路由；本流程不决定地图展示。

## 9. 实时同行会话与完成轨迹

```text
权威订单进入 DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS
  -> 立即发送最新真实位置 -> 每 5 秒发送
  -> 同行样本匹配订单且 <=15 秒 -> 更新辅助 marker
  -> 设备/同行样本 >15 秒 -> 停止复用旧值 / 隐藏 marker / 可见与 TTS 降级

IN_PROGRESS -> 开启 fitness 后台定位
离开 IN_PROGRESS 或会话/身份失效 -> 关闭后台定位并清空同行内存

COMPLETED -> GET /api/orders/{id}/track
  -> blindTrack 作为“本次路线”
  -> 空/部分数据结合 response.status 说明
  -> volunteerTrack 仅保留，不输出异常判断
```

- PING/PONG 两角色均为 30 秒；服务端 90 秒无消息关闭后走现有重连。
- `ESCORT_DISTANCE_ALERT` 和 `ESCORT_SIGNAL_LOST` 只产生高优先级提醒，不改变订单状态或触发 iOS SOS。
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
