# Role 角色模块

<cite>
**本文档引用的文件**
- [role-switching/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/role-switching/spec.md)
- [backend-api-contract/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/backend-api-contract/spec.md)
- [order-status-lifecycle/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md)
- [blind-runner-booking/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/blind-runner-booking/spec.md)
- [volunteer-order-flow/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-order-flow/spec.md)
- [volunteer-points/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-points/spec.md)
- [safety-basic-emergency/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md)
- [auth-phone-login/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/auth-phone-login/spec.md)
- [RoleSelectionView.swift](file://blindRun/Role/RoleSelectionView.swift)
- [RoleModule.swift](file://blindRun/Role/RoleModule.swift)
- [UserModels.swift](file://blindRun/Core/Models/UserModels.swift)
- [AppState.swift](file://blindRun/Core/AppState.swift)
- [AppColors.swift](file://blindRun/Core/DesignSystem/AppColors.swift)
- [HighContrastText.swift](file://blindRun/Core/DesignSystem/HighContrastText.swift)
- [ErrorModels.swift](file://blindRun/Core/Models/ErrorModels.swift)
- [ContentView.swift](file://blindRun/ContentView.swift)
- [blindRunApp.swift](file://blindRun/blindRunApp.swift)
- [SpeechService.swift](file://blindRun/Voice/SpeechService.swift)
</cite>

## 更新摘要
**变更内容**
- 角色选择系统重构：RoleSelectionViewModel.swift 文件已被删除，功能已整合到 RoleSelectionView.swift 中的新 RoleSelectionViewModel 类内
- 保持相同功能但代码结构已优化，采用单一文件内的类组织方式
- 新增完整的角色选择系统实现，包括双角色选择界面和高对比度设计
- 实现角色切换拦截机制和状态同步功能
- 添加无障碍访问支持和语音播报功能
- 更新路由系统以支持角色选择流程

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构总览](#架构总览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考量](#性能考量)
8. [故障排查指南](#故障排查指南)
9. [结论](#结论)
10. [附录](#附录)

## 简介
本文件面向 Role 角色模块的技术文档，聚焦于"盲人跑者"和"志愿者"两类角色的定义、权限差异、角色切换机制（含条件检查、活跃订单拦截）、单一 JWT 在多角色间的共享策略（activeRole 字段）、角色状态持久化与同步策略、UI 设计考虑（角色选择与切换确认流程），以及在各业务模块中基于角色的动态权限控制。**更新**：角色选择系统经过重构，采用更优化的代码结构，将 ViewModel 功能整合到 View 文件中，保持功能完整性的同时提升代码可维护性。

## 项目结构
iOS 前端采用 SwiftUI 应用骨架，当前内容视图与应用入口位于 ContentView.swift 和 blindRunApp.swift；角色相关的行为与约束主要由后端 API 合约与业务规范定义，并通过 OpenAPI 文档暴露给前端调用。**更新**：角色模块采用新的文件组织结构，将 ViewModel 内嵌到 View 文件中，简化了模块结构。

```mermaid
graph TB
subgraph "iOS 前端"
A["blindRunApp.swift<br/>应用入口"]
B["ContentView.swift<br/>根视图路由"]
C["Role 模块"]
D["RoleSelectionView.swift<br/>角色选择界面<br/>+ 内置 ViewModel"]
E["UserModels.swift<br/>用户模型"]
F["AppState.swift<br/>全局状态管理"]
G["SpeechService.swift<br/>语音播报服务"]
end
subgraph "后端 API"
H["用户/角色接口<br/>OpenAPI 定义"]
I["订单生命周期接口<br/>OpenAPI 定义"]
J["志愿者流程接口<br/>OpenAPI 定义"]
K["安全应急接口<br/>OpenAPI 定义"]
end
A --> B
B --> C
C --> D
D --> E
D --> F
D --> G
B --> H
B --> I
B --> J
B --> K
```

**图表来源**
- [blindRunApp.swift:10-17](file://blindRun/blindRunApp.swift#L10-L17)
- [ContentView.swift:10-34](file://blindRun/ContentView.swift#L10-L34)
- [RoleSelectionView.swift:96-100](file://blindRun/Role/RoleSelectionView.swift#L96-L100)

**章节来源**
- [blindRunApp.swift:1-18](file://blindRun/blindRunApp.swift#L1-L18)
- [ContentView.swift:1-41](file://blindRun/ContentView.swift#L1-L41)

## 核心组件
- 角色模型与切换
  - 单一账户可同时持有"盲人跑者"和"志愿者"角色，通过 activeRole 切换当前角色，不产生新的 JWT。
  - 切换条件：无处于特定状态的活跃订单时允许切换。
  - 活跃订单拦截：当存在处于 accepted、arrived、in_progress 或 emergency 状态的订单时，禁止切换并返回错误码。
- JWT 与认证
  - 所有受保护的用户、资料、志愿者、订单相关 API 均需携带 Bearer JWT。
  - 首次登录自动创建用户并返回 JWT；后续登录返回现有用户的新 JWT。
- 订单生命周期与角色权限
  - 订单状态流转严格限定，不同角色在不同状态下具备的操作权限不同。
  - 志愿者仅能接受处于 matching 状态的订单；完成服务需在 in_progress 状态下进行。
- 安全应急
  - 应急状态仅在 accepted、arrived、in_progress 三态之间触发，且不可恢复。
- 积分与服务记录
  - 完成服务后志愿者获得积分，支持查看服务记录。
- **更新** 角色选择系统
  - 内置 ViewModel：RoleSelectionViewModel 作为 RoleSelectionView 的内部类，提供更好的封装性
  - 双角色选择界面：提供高对比度设计的大卡片按钮
  - 无障碍支持：完整的 VoiceOver 和 TTS 支持
  - 状态同步：实时同步前端状态与后端服务器状态

**章节来源**
- [role-switching/spec.md:3-25](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/role-switching/spec.md#L3-L25)
- [auth-phone-login/spec.md:3-29](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/auth-phone-login/spec.md#L3-L29)
- [order-status-lifecycle/spec.md:3-66](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md#L3-L66)
- [volunteer-order-flow/spec.md:3-38](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-order-flow/spec.md#L3-L38)
- [volunteer-points/spec.md:3-26](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-points/spec.md#L3-L26)
- [safety-basic-emergency/spec.md:11-42](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L42)
- [RoleSelectionView.swift:96-100](file://blindRun/Role/RoleSelectionView.swift#L96-L100)

## 架构总览
角色系统围绕"单一 JWT + activeRole"的设计展开：前端在本地维护当前 activeRole，后续所有 API 调用均携带同一 JWT，后端据此判定当前角色并执行相应权限校验。**更新**：采用新的架构模式，将 ViewModel 作为 View 的内部类，提供更好的代码组织和封装性。

```mermaid
sequenceDiagram
participant U as "用户"
participant RS as "RoleSelectionView"
participant RVM as "RoleSelectionViewModel"
participant AS as "AppState"
participant API as "后端 API"
participant DB as "数据库"
U->>RS : "点击角色卡片"
RS->>RVM : "selectRole(role)"
RVM->>AS : "performRoleSwitch()"
RVM->>API : "PATCH /api/users/me/active-role"
API->>DB : "查询用户及订单状态"
DB-->>API : "返回用户与订单数据"
API->>API : "校验是否存在处于 accepted/arrived/in_progress/emergency 的订单"
alt "存在活跃订单"
API-->>RVM : "返回错误码 ACTIVE_ORDER_ROLE_SWITCH_BLOCKED"
RVM-->>RS : "showBlockedAlert = true"
RS-->>U : "弹出拦截提示"
else "无活跃订单"
API->>DB : "更新 activeRole 并持久化"
DB-->>API : "保存成功"
API-->>RVM : "返回更新后的用户信息"
RVM->>AS : "updateCurrentUser()"
AS->>AS : "persistActiveRole()"
RVM-->>RS : "切换成功"
RS-->>U : "跳转到对应角色首页"
end
```

**图表来源**
- [RoleSelectionView.swift:188-190](file://blindRun/Role/RoleSelectionView.swift#L188-L190)
- [RoleSelectionView.swift:34-41](file://blindRun/Role/RoleSelectionView.swift#L34-L41)
- [RoleSelectionView.swift:45-68](file://blindRun/Role/RoleSelectionView.swift#L45-L68)
- [AppState.swift:157-170](file://blindRun/Core/AppState.swift#L157-L170)

## 详细组件分析

### 角色选择界面与交互
**更新**：角色选择系统经过重构，采用更优化的代码结构。

- 界面设计
  - 高对比度设计：使用半透明背景色区分两个角色选项
  - 大卡片布局：每个角色使用独立的大卡片，便于触摸操作
  - 图标标识：使用 SF Symbols 图标增强视觉识别
  - 无障碍支持：完整的 VoiceOver 标签和提示
- 交互流程
  - 用户点击任一角色卡片
  - 显示加载状态，禁用其他交互
  - 调用后端 API 进行角色切换
  - 根据结果更新界面状态
- **更新** 代码结构优化
  - RoleSelectionViewModel 作为内部类，提供更好的封装性
  - 通过 @StateObject 属性包装，简化状态管理
  - 配置方法在 View.onAppear 中调用，确保依赖注入时机

```mermaid
flowchart TD
Start(["用户打开角色选择界面"]) --> Load["加载界面内容"]
Load --> ShowCards["显示两个角色卡片"]
ShowCards --> UserClick{"用户点击卡片？"}
UserClick --> |盲人跑者| CheckOrder1["检查活跃订单"]
UserClick --> |志愿者| CheckOrder2["检查活跃订单"]
CheckOrder1 --> HasActive1{"存在活跃订单？"}
CheckOrder2 --> HasActive2{"存在活跃订单？"}
HasActive1 --> |是| ShowAlert1["显示拦截提示"]
HasActive2 --> |是| ShowAlert2["显示拦截提示"]
HasActive1 --> |否| Switch1["调用 API 切换角色"]
HasActive2 --> |否| Switch2["调用 API 切换角色"]
ShowAlert1 --> Wait1["等待用户确认"]
ShowAlert2 --> Wait2["等待用户确认"]
Wait1 --> UserConfirm1{"用户确认？"}
Wait2 --> UserConfirm2{"用户确认？"}
UserConfirm1 --> |否| ShowCards
UserConfirm2 --> |否| ShowCards
UserConfirm1 --> |是| Switch1
UserConfirm2 --> |是| Switch2
Switch1 --> Success1["更新状态并跳转"]
Switch2 --> Success2["更新状态并跳转"]
Success1 --> End(["完成"])
Success2 --> End
```

**图表来源**
- [RoleSelectionView.swift:113-129](file://blindRun/Role/RoleSelectionView.swift#L113-L129)
- [RoleSelectionView.swift:34-41](file://blindRun/Role/RoleSelectionView.swift#L34-L41)
- [RoleSelectionView.swift:70-89](file://blindRun/Role/RoleSelectionView.swift#L70-L89)

**章节来源**
- [RoleSelectionView.swift:96-236](file://blindRun/Role/RoleSelectionView.swift#L96-L236)

### 角色切换机制
- 切换前提
  - 用户必须已认证（持有 JWT）。
  - 当前不存在处于 accepted、arrived、in_progress 或 emergency 状态的订单。
- 切换流程
  - 前端调用切换接口，携带 JWT。
  - 后端验证订单状态，若满足条件则更新 activeRole 并返回最新用户信息；否则返回错误码并保持原 activeRole。
- 错误处理
  - 返回统一错误码 ACTIVE_ORDER_ROLE_SWITCH_BLOCKED，前端据此提示用户。
- **更新** 状态同步
  - 成功切换后，前端通过 AppState.updateCurrentUser() 同步本地状态
  - 自动持久化到 UserDefaults，确保应用重启后状态保持
  - **新增** 内部类封装：RoleSelectionViewModel 作为内部类，提供更好的状态管理和依赖注入

```mermaid
sequenceDiagram
participant RVM as "RoleSelectionViewModel"
participant AS as "AppState"
participant API as "后端 API"
participant DB as "数据库"
RVM->>API : "PATCH /api/users/me/active-role"
API->>DB : "查询用户活跃订单"
DB-->>API : "返回订单状态"
alt "存在活跃订单"
API-->>RVM : "ACTIVE_ORDER_ROLE_SWITCH_BLOCKED"
RVM->>RVM : "handleSwitchError()"
RVM-->>RVM : "showBlockedAlert = true"
else "无活跃订单"
API->>DB : "更新 activeRole"
DB-->>API : "保存成功"
API-->>RVM : "返回更新后的用户信息"
RVM->>AS : "updateCurrentUser()"
AS->>AS : "persistActiveRole()"
RVM-->>RVM : "切换成功"
end
```

**图表来源**
- [RoleSelectionView.swift:45-68](file://blindRun/Role/RoleSelectionView.swift#L45-L68)
- [RoleSelectionView.swift:70-89](file://blindRun/Role/RoleSelectionView.swift#L70-L89)
- [AppState.swift:157-170](file://blindRun/Core/AppState.swift#L157-L170)

**章节来源**
- [role-switching/spec.md:3-25](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/role-switching/spec.md#L3-L25)
- [RoleSelectionView.swift:45-68](file://blindRun/Role/RoleSelectionView.swift#L45-L68)

### JWT 共享与 activeRole 字段
- 单一 JWT：切换角色不生成新令牌，保持会话连续性。
- activeRole：后端依据该字段决定当前操作的权限范围，前端负责在本地维护该值并在后续请求中透传。
- 认证要求：所有受保护 API 均需携带 Bearer JWT。
- **更新** 状态持久化
  - 使用 UserDefaults 持久化 activeRole 状态
  - 应用启动时自动恢复之前的角色状态
  - 支持跨会话的状态保持
  - **新增** 内部类优化：ViewModel 作为内部类，提供更好的状态封装和依赖管理

**章节来源**
- [role-switching/spec.md:5](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/role-switching/spec.md#L5)
- [auth-phone-login/spec.md:23-29](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/auth-phone-login/spec.md#L23-L29)
- [AppState.swift:236-242](file://blindRun/Core/AppState.swift#L236-L242)

### 订单生命周期与角色权限
- 状态机
  - 正常流程：matching → accepted → arrived → in_progress → completed。
  - 紧急状态：emergency 为终止态，不可恢复。
- 角色权限
  - 志愿者仅能接受处于 matching 的订单；完成服务需在 in_progress 状态下进行。
  - 盲人跑者可在等待与服务过程中轮询订单状态，取消权限受限于订单所处阶段。
- 轮询策略
  - 盲人跑者在等待与活动页面每 5 秒轮询一次订单详情。

```mermaid
stateDiagram-v2
[*] --> matching
matching --> accepted : "志愿者接受"
accepted --> arrived : "志愿者到达"
arrived --> in_progress : "盲人跑者确认开始"
in_progress --> completed : "志愿者完成服务"
accepted --> emergency : "盲人跑者触发应急"
arrived --> emergency : "盲人跑者触发应急"
in_progress --> emergency : "盲人跑者触发应急"
emergency --> [*] : "终止不可恢复"
```

**图表来源**
- [order-status-lifecycle/spec.md:3-29](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md#L3-L29)
- [volunteer-order-flow/spec.md:11-37](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-order-flow/spec.md#L11-L37)

**章节来源**
- [order-status-lifecycle/spec.md:3-66](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md#L3-L66)
- [volunteer-order-flow/spec.md:3-38](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-order-flow/spec.md#L3-L38)

### 安全应急与 UI 提示
- 触发条件：仅在 accepted、arrived、in_progress 三态之间允许进入 emergency。
- UI 行为：触发前需弹窗确认，明确告知进入应急状态后本次服务将标记为异常并记录当前订单状态。
- 数据存储：记录应急事件与联系人信息，但不触发真实通知。

**章节来源**
- [safety-basic-emergency/spec.md:11-42](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L42)

### 志愿者积分与服务记录
- 完成服务后获得固定积分，支持查看服务记录（时间、盲人昵称、起点、状态、积分）。
- MVP 阶段积分商店为展示用途，不支持兑换。

**章节来源**
- [volunteer-points/spec.md:3-26](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/volunteer-points/spec.md#L3-L26)

### 盲人跑者预约与 UI 限制
- 预约前置条件：需完善个人资料（昵称、紧急联系人姓名与电话）。
- 时间限制：预约时间至少距离当前时间 30 分钟以后。
- 可选路线字段：仅作为元数据，不会触发导航或自动路径规划。

**章节来源**
- [blind-runner-booking/spec.md:3-34](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/blind-runner-booking/spec.md#L3-L34)

### 无障碍访问与语音支持
**更新**：完整的无障碍访问支持，包括 VoiceOver 和 TTS 功能。

- VoiceOver 支持
  - 每个交互元素都有清晰的 accessibilityLabel 和 accessibilityHint
  - 角色卡片提供详细的描述性标签
  - 错误提示和状态变化都有适当的无障碍描述
- TTS 语音播报
  - 页面加载时自动播报欢迎信息
  - 错误发生时自动播报错误信息
  - 确保视障用户的完整使用体验
- **新增** 语音服务集成
  - SpeechService 作为独立服务类，提供集中化的语音播报功能
  - 支持错误信息播报和状态变化提醒
  - 防重复播报机制，避免轮询时的重复语音

**章节来源**
- [RoleSelectionView.swift:170](file://blindRun/Role/RoleSelectionView.swift#L170)
- [RoleSelectionView.swift:209-215](file://blindRun/Role/RoleSelectionView.swift#L209-L215)
- [SpeechService.swift:49-52](file://blindRun/Voice/SpeechService.swift#L49-L52)

## 依赖关系分析
- 前端依赖后端通过 OpenAPI 暴露的用户、订单、志愿者、安全等接口。
- 认证层依赖 JWT Bearer 认证，所有受保护接口均需携带有效令牌。
- 角色切换依赖后端对用户活跃订单状态的校验，防止在关键阶段切换角色。
- **更新** 角色选择系统依赖：
  - AppState：管理全局状态和持久化
  - SpeechService：提供语音播报功能
  - APIClient：处理网络请求
  - DesignSystem：提供统一的 UI 组件
  - **新增** 内部类优化：RoleSelectionViewModel 作为内部类，提供更好的封装和依赖管理

```mermaid
graph LR
RS["RoleSelectionView"] --> RVM["RoleSelectionViewModel<br/>(内部类)"]
RVM --> AS["AppState"]
RVM --> API["APIClient"]
RS --> DS["DesignSystem"]
AS --> UD["UserDefaults"]
AS --> AC["APIEnvironment"]
RVM --> ES["ErrorModels"]
RS --> HC["HighContrastText"]
RS --> AC["AppColors"]
RS --> SS["SpeechService"]
```

**图表来源**
- [RoleSelectionView.swift:96-100](file://blindRun/Role/RoleSelectionView.swift#L96-L100)
- [RoleSelectionView.swift:19-29](file://blindRun/Role/RoleSelectionView.swift#L19-L29)
- [AppState.swift:15-25](file://blindRun/Core/AppState.swift#L15-L25)

**章节来源**
- [backend-api-contract/spec.md:19-34](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/backend-api-contract/spec.md#L19-L34)
- [auth-phone-login/spec.md:3-29](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/auth-phone-login/spec.md#L3-L29)
- [RoleSelectionView.swift:96-236](file://blindRun/Role/RoleSelectionView.swift#L96-L236)

## 性能考量
- 订单轮询：盲人跑者在等待与活动页面每 5 秒轮询一次订单详情，建议在页面不可见或后台时降低轮询频率或暂停轮询，避免不必要的网络开销。
- JWT 复用：单一 JWT 减少重复登录与令牌刷新成本，前端应避免频繁重建会话。
- 状态一致性：前端本地 activeRole 与后端状态需保持最终一致，建议在每次关键网络请求后进行状态校验与同步。
- **更新** 角色选择优化：
  - 加载状态：切换过程中禁用交互，避免重复请求
  - 错误缓存：错误信息会在一定时间内缓存，减少重复网络请求
  - 状态恢复：应用重启后自动恢复之前的活跃角色
  - **新增** 内部类优化：减少模块间依赖，提高代码组织效率

## 故障排查指南
- 切换失败
  - 现象：点击切换角色后立即失败。
  - 排查：确认是否存在处于 accepted、arrived、in_progress 或 emergency 的订单；若存在，需先处理订单或等待其结束。
  - 参考：错误码 ACTIVE_ORDER_ROLE_SWITCH_BLOCKED。
- 认证失败
  - 现象：访问受保护接口返回未授权。
  - 排查：确认请求头中携带有效的 Bearer JWT；如已过期，需重新登录获取新令牌。
- 订单状态异常
  - 现象：志愿者无法接受订单或无法完成服务。
  - 排查：核对订单当前状态是否符合匹配/接受/到达/进行中/完成的流程；若处于 emergency，需等待其结束或按规则处理。
- 应急触发
  - 现象：触发应急后无法继续常规流程。
  - 排查：确认当前状态是否为 accepted、arrived 或 in_progress；emergency 为终止态，不可恢复。
- **更新** 角色选择问题
  - 现象：角色卡片无法点击或无响应。
  - 排查：检查网络连接状态，确认 API 请求正常；查看是否有加载状态阻塞。
  - 现象：TTS 语音不工作。
  - 排查：确认设备音量和系统语音设置；检查 SpeechService 初始化状态。
  - **新增** ViewModel 问题
    - 现象：角色切换无响应。
    - 排查：检查 RoleSelectionViewModel 是否正确初始化；确认依赖注入是否在 onAppear 中执行。

**章节来源**
- [role-switching/spec.md:11-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/role-switching/spec.md#L11-L17)
- [backend-api-contract/spec.md:19-25](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/backend-api-contract/spec.md#L19-L25)
- [order-status-lifecycle/spec.md:19-37](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md#L19-L37)
- [safety-basic-emergency/spec.md:27-33](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L27-L33)
- [RoleSelectionView.swift:70-89](file://blindRun/Role/RoleSelectionView.swift#L70-L89)

## 结论
本角色模块以"单一 JWT + activeRole"为核心，实现了同一账户在"盲人跑者"和"志愿者"之间的无缝切换，同时通过后端对活跃订单的严格拦截，保证了业务流程的正确性与安全性。**更新**：经过重构的角色选择系统采用了更优化的代码结构，将 ViewModel 作为内部类集成到 View 文件中，不仅保持了原有功能的完整性，还提升了代码的可维护性和封装性。新增的完整角色选择系统提供了优秀的用户体验，包括高对比度设计、无障碍访问支持和语音播报功能。前端应遵循规范，在 UI 层明确提示切换条件与应急流程，并在关键节点进行状态校验与同步，确保用户体验与系统一致性。

## 附录
- 使用示例
  - 新用户首次登录：提交固定验证码完成登录，系统创建用户并返回 JWT；随后进入角色选择界面，设置 activeRole。
  - 已有用户登录：直接返回现有用户的新 JWT；若尚未设置 activeRole，则引导进入角色选择。
  - 切换角色：在无活跃订单的前提下，选择目标角色并提交切换请求；成功后后续 API 自动以新角色身份执行。
  - **更新** 角色选择界面：用户看到两个大卡片，分别代表盲人跑者和志愿者，点击后进行角色切换。
  - **新增** 内部类优化：ViewModel 作为内部类，提供更好的代码组织和依赖管理。
- 边界情况
  - 存在活跃订单时禁止切换，需等待或完成订单。
  - emergency 状态不可恢复，需按规则处理。
  - 志愿者仅能在 matching 状态接受订单，完成服务需在 in_progress 状态下进行。
  - 盲人跑者预约需满足资料完整与时间间隔要求。
  - **更新** 角色选择异常：网络错误时显示错误提示；应用重启后自动恢复之前的角色状态。
  - **新增** 代码结构异常：ViewModel 初始化失败或依赖注入问题导致的切换无响应。