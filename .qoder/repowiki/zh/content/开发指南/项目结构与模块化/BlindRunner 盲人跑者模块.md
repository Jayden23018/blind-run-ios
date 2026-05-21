# BlindRunner 盲人跑者模块

<cite>
**本文档引用的文件**
- [blindRunApp.swift](file://blindRun/blindRunApp.swift)
- [ContentView.swift](file://blindRun/ContentView.swift)
- [04-user-flows-and-state-machine.md](file://docs/04-user-flows-and-state-machine.md)
- [07-api-contract.openapi.yaml](file://docs/07-api-contract.openapi.yaml)
- [08-ios-architecture.md](file://docs/08-ios-architecture.md)
- [09-accessibility-and-voice-guidelines.md](file://docs/09-accessibility-and-voice-guidelines.md)
- [00-consistency-check-report.md](file://docs/00-consistency-check-report.md)
- [blind-runner-booking/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/blind-runner-booking/spec.md)
- [order-status-lifecycle/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md)
- [amap-location/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/amap-location/spec.md)
- [accessibility-voice-ui/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/accessibility-voice-ui/spec.md)
- [blindRunTests.swift](file://blindRunTests/blindRunTests.swift)
- [blindRunUITests.swift](file://blindRunUITests/blindRunUITests.swift)
</cite>

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构总览](#架构总览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排除指南](#故障排除指南)
9. [结论](#结论)
10. [附录](#附录)

## 简介
本文件为 BlindRunner 盲人跑者模块的功能实现文档，面向 iOS 开发团队与产品设计人员，系统阐述盲人跑者端从登录、资料管理、预约创建、订单状态跟踪到服务完成的完整使用流程。文档重点说明订单生命周期的状态机实现、轮询机制与状态更新通知策略、无障碍设计（VoiceOver、TTS、大按钮）以及定位权限处理、地图集成与紧急求助等关键技术细节。

## 项目结构
当前仓库包含最小可用的 SwiftUI 应用骨架与完整的业务与技术规范文档。应用入口为 SwiftUI App 类型，主视图为简单占位内容视图，实际业务页面与 ViewModel 将按 MVVM 架构组织在后续开发中。

```mermaid
graph TB
subgraph "应用入口"
App["blindRunApp<br/>应用入口"]
Content["ContentView<br/>占位视图"]
end
subgraph "业务规范"
UserFlows["用户流程与状态机<br/>04-user-flows-and-state-machine.md"]
APIContract["API 合同<br/>07-api-contract.openapi.yaml"]
IOSArch["iOS 架构<br/>08-ios-architecture.md"]
Access["无障碍与语音指南<br/>09-accessibility-and-voice-guidelines.md"]
end
App --> Content
App --> UserFlows
App --> APIContract
App --> IOSArch
App --> Access
```

**图表来源**
- [blindRunApp.swift:10-17](file://blindRun/blindRunApp.swift#L10-L17)
- [ContentView.swift:10-20](file://blindRun/ContentView.swift#L10-L20)
- [04-user-flows-and-state-machine.md:1-70](file://docs/04-user-flows-and-state-machine.md#L1-L70)
- [07-api-contract.openapi.yaml:1-50](file://docs/07-api-contract.openapi.yaml#L1-L50)
- [08-ios-architecture.md:1-32](file://docs/08-ios-architecture.md#L1-L32)
- [09-accessibility-and-voice-guidelines.md:1-36](file://docs/09-accessibility-and-voice-guidelines.md#L1-L36)

**章节来源**
- [blindRunApp.swift:10-17](file://blindRun/blindRunApp.swift#L10-L17)
- [ContentView.swift:10-20](file://blindRun/ContentView.swift#L10-L20)

## 核心组件
- 订单生命周期与状态机：定义了从匹配到完成的标准流程及紧急状态的终态特性。
- 轮询机制：盲人端在关键页面以固定频率轮询订单状态，确保实时更新与 TTS 通知。
- 无障碍与语音：基于 VoiceOver、TTS 与大按钮的设计准则，保障视障用户的完整操作闭环。
- 定位与地图：集成高德地图，实现真实地图、当前位置与订单起点标注，以及本地距离计算与排序。
- 紧急求助：统一的求助触发机制，进入紧急状态后不再允许常规生命周期动作。

**章节来源**
- [04-user-flows-and-state-machine.md:72-118](file://docs/04-user-flows-and-state-machine.md#L72-L118)
- [08-ios-architecture.md:125-139](file://docs/08-ios-architecture.md#L125-L139)
- [09-accessibility-and-voice-guidelines.md:13-36](file://docs/09-accessibility-and-voice-guidelines.md#L13-L36)
- [amap-location/spec.md:3-38](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/amap-location/spec.md#L3-L38)

## 架构总览
BlindRunner 模块遵循 SwiftUI + MVVM 架构，采用 URLSession 进行网络通信，使用本地 UserDefaults 存储 JWT（生产环境需迁移到 Keychain）。应用通过 OpenAPI 合同约束前后端契约，确保状态机与轮询行为的一致性。

```mermaid
graph TB
subgraph "视图层"
BRHome["盲人首页"]
BRBooking["创建预约页"]
BRStatus["订单状态等待页"]
BRInSvc["服务中页"]
BREmer["紧急求助页"]
BRCompleted["完成/评分页"]
end
subgraph "视图模型层"
VMBooking["BlindBookingViewModel"]
VMStatus["BlindOrderStatusViewModel"]
VMEmer["EmergencyViewModel"]
end
subgraph "服务层"
APIClient["APIClient<br/>URLSession + JWT"]
Speech["SpeechService<br/>AVSpeechSynthesizer"]
Map["AMapBridge<br/>定位与地图"]
end
BRHome --> VMBooking
BRBooking --> VMStatus
BRStatus --> VMStatus
BRInSvc --> VMStatus
BREmer --> VMEmer
VMBooking --> APIClient
VMStatus --> APIClient
VMEmer --> APIClient
VMStatus --> Speech
VMStatus --> Map
APIClient --> Map
```

**图表来源**
- [08-ios-architecture.md:33-49](file://docs/08-ios-architecture.md#L33-L49)
- [07-api-contract.openapi.yaml:150-387](file://docs/07-api-contract.openapi.yaml#L150-L387)
- [09-accessibility-and-voice-guidelines.md:13-36](file://docs/09-accessibility-and-voice-guidelines.md#L13-L36)

## 详细组件分析

### 订单生命周期与状态机
订单状态机覆盖正常流转与异常终态，明确各状态间的允许转换与禁止转换规则。轮询机制确保在关键页面持续监控状态变化，并通过 TTS 与 UI 同步更新。

```mermaid
stateDiagram-v2
[*] --> matching : "盲人提交预约"
matching --> accepted : "志愿者接单成功"
matching --> cancelled : "盲人取消/超时自动取消"
accepted --> arrived : "志愿者点击'我已到达'"
accepted --> cancelled : "任一方取消"
accepted --> emergency : "任一方触发求助"
arrived --> in_progress : "盲人确认开始服务"
arrived --> cancelled : "任一方取消"
arrived --> emergency : "任一方触发求助"
in_progress --> completed : "志愿者结束服务"
in_progress --> emergency : "任一方触发求助"
completed --> [*]
cancelled --> [*]
emergency --> [*]
```

**图表来源**
- [04-user-flows-and-state-machine.md:75-96](file://docs/04-user-flows-and-state-machine.md#L75-L96)

**章节来源**
- [04-user-flows-and-state-machine.md:72-118](file://docs/04-user-flows-and-state-machine.md#L72-L118)
- [order-status-lifecycle/spec.md:3-50](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md#L3-L50)

### 轮询机制与状态更新通知
盲人端在订单状态等待页与服务中页以固定周期轮询订单详情，检测状态变化后同步更新 UI 并播报 TTS。轮询在页面离开、订单进入终态或用户登出时停止。

```mermaid
sequenceDiagram
participant BR as "盲人用户"
participant App as "iOS App"
participant API as "后端 API"
participant TTS as "AVSpeechSynthesizer"
loop 每5秒仅订单相关页面
App->>API : "GET /api/orders/{orderId}"
API-->>App : "{ status, ... }"
alt 状态变化
App->>App : "更新 UI"
App->>TTS : "播报新状态"
TTS-->>App : "播报完成"
else 状态未变
App->>App : "保持当前 UI"
end
end
Note over App : "离开订单页面时停止轮询"
```

**图表来源**
- [04-user-flows-and-state-machine.md:277-299](file://docs/04-user-flows-and-state-machine.md#L277-L299)
- [08-ios-architecture.md:125-139](file://docs/08-ios-architecture.md#L125-L139)

**章节来源**
- [04-user-flows-and-state-machine.md:275-299](file://docs/04-user-flows-and-state-machine.md#L275-L299)
- [08-ios-architecture.md:125-139](file://docs/08-ios-architecture.md#L125-L139)

### 盲人跑者正向使用流程
从登录到完成的完整路径，包含定位权限检查、预约创建、志愿者接单、到达确认、服务开始与结束、以及可选评分环节。

```mermaid
sequenceDiagram
actor BR as "盲人跑者"
participant App as "iOS App"
participant API as "后端 API"
BR->>App : "打开 App"
App->>API : "POST /api/auth/phone-login"
API-->>App : "{ accessToken, user }"
App->>BR : "显示盲人首页"
BR->>App : "点击'开始约跑'"
App->>App : "检查定位权限"
App->>BR : "显示创建预约页"
BR->>App : "填写出发地点、时间、备注"
BR->>App : "点击'提交预约'"
App->>API : "POST /api/orders"
API-->>App : "{ orderId, status : 'matching' }"
loop 每5秒轮询
App->>API : "GET /api/orders/{orderId}"
API-->>App : "{ status : 'matching' }"
end
API-->>App : "{ status : 'accepted', volunteer : {...} }"
API-->>App : "{ status : 'arrived' }"
BR->>App : "点击'确认开始服务'"
App->>API : "POST /api/orders/{orderId}/confirm-start"
API-->>App : "{ status : 'in_progress' }"
API-->>App : "{ status : 'completed' }"
BR->>App : "对志愿者评分可选"
App->>App : "返回盲人首页"
```

**图表来源**
- [04-user-flows-and-state-machine.md:123-178](file://docs/04-user-flows-and-state-machine.md#L123-L178)
- [07-api-contract.openapi.yaml:150-387](file://docs/07-api-contract.openapi.yaml#L150-L387)

**章节来源**
- [04-user-flows-and-state-machine.md:120-178](file://docs/04-user-flows-and-state-machine.md#L120-L178)
- [blind-runner-booking/spec.md:11-25](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/blind-runner-booking/spec.md#L11-L25)

### 紧急求助流程
任一方在特定状态下触发求助，订单进入紧急终态，系统不再允许常规生命周期动作，同时向另一方推送状态变化并播报 TTS。

```mermaid
sequenceDiagram
actor User as "任一方用户"
participant App as "iOS App"
participant API as "后端 API"
User->>App : "点击'紧急求助'按钮"
App->>User : "弹出确认弹窗"
User->>App : "确认求助"
App->>API : "POST /api/orders/{orderId}/emergency"
API-->>App : "{ status : 'emergency' }"
Note over App : "TTS : '已进入求助状态'"
loop 另一方轮询
API-->>App : "{ status : 'emergency' }"
App->>App : "UI 更新"
end
Note over App : "显示紧急联系人信息<br/>订单不可恢复，保持 emergency 终态"
```

**图表来源**
- [04-user-flows-and-state-machine.md:232-257](file://docs/04-user-flows-and-state-machine.md#L232-L257)
- [order-status-lifecycle/spec.md:27-30](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md#L27-L30)

**章节来源**
- [04-user-flows-and-state-machine.md:230-257](file://docs/04-user-flows-and-state-machine.md#L230-L257)
- [order-status-lifecycle/spec.md:27-30](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/order-status-lifecycle/spec.md#L27-L30)

### 角色切换拦截流程
当存在活跃订单时，系统阻止用户切换角色，防止影响正在进行的服务。

```mermaid
flowchart TD
Switch["用户点击切换角色"]
CheckActive{"检查活跃订单<br/>accepted / arrived / in_progress / emergency"}
Block["弹出警告弹窗<br/>'您有进行中的订单，无法切换角色'"]
Stay["保持当前角色页面"]
Allow["切换到目标角色<br/>导航至对应首页"]
Switch --> CheckActive
CheckActive --> |"存在活跃订单"| Block
Block --> Stay
CheckActive --> |"无活跃订单"| Allow
```

**图表来源**
- [04-user-flows-and-state-machine.md:261-273](file://docs/04-user-flows-and-state-machine.md#L261-L273)
- [07-api-contract.openapi.yaml:61-81](file://docs/07-api-contract.openapi.yaml#L61-L81)

**章节来源**
- [04-user-flows-and-state-machine.md:259-273](file://docs/04-user-flows-and-state-machine.md#L259-L273)
- [07-api-contract.openapi.yaml:61-81](file://docs/07-api-contract.openapi.yaml#L61-L81)

### 无障碍设计实现方案
- VoiceOver 支持：为关键按钮、输入框与状态文本提供清晰的 accessibilityLabel 与 accessibilityHint。
- TTS 语音播报：在状态变更时播报关键节点，避免轮询期间重复播报。
- 大按钮设计：主操作按钮高度不低于 64pt，确保触控准确性。
- 语音输入：仅在文本输入场景使用 Speech 框架，失败时回退键盘输入。
- 危险操作确认：取消订单、进入紧急状态、完成服务等均需二次确认。

```mermaid
flowchart TD
Start(["进入关键页面"]) --> InitTTS["初始化 TTS 服务"]
InitTTS --> Announce["播报页面进入与当前状态"]
Announce --> WaitAction["等待用户操作或轮询"]
WaitAction --> CheckChange{"状态是否变化？"}
CheckChange --> |是| SpeakNew["播报新状态"]
CheckChange --> |否| Continue["继续等待"]
SpeakNew --> WaitAction
Continue --> WaitAction
WaitAction --> Danger{"危险操作？"}
Danger --> |是| Confirm["二次确认弹窗"]
Danger --> |否| Proceed["执行操作"]
Confirm --> Proceed
Proceed --> WaitAction
```

**图表来源**
- [09-accessibility-and-voice-guidelines.md:13-36](file://docs/09-accessibility-and-voice-guidelines.md#L13-L36)
- [09-accessibility-and-voice-ui/spec.md:19-34](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/accessibility-voice-ui/spec.md#L19-L34)

**章节来源**
- [09-accessibility-and-voice-guidelines.md:13-36](file://docs/09-accessibility-and-voice-guidelines.md#L13-L36)
- [09-accessibility-and-voice-ui/spec.md:1-42](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/accessibility-voice-ui/spec.md#L1-L42)

### 定位权限处理与地图集成
- 定位权限：盲人端创建预约与志愿者端按距离筛选订单均需定位权限，拒绝时阻断核心流程并播报 TTS 提示。
- 地图集成：显示真实地图、当前位置与订单起点标记；志愿者端在本地计算距离并排序。
- 演示回退：模拟器无定位时使用默认坐标，但需明确提示真实定位权限要求。

```mermaid
flowchart TD
Start(["进入需要定位的页面"]) --> CheckPerm["检查定位权限"]
CheckPerm --> Granted{"已授权？"}
Granted --> |是| ShowMap["显示地图与标记"]
Granted --> |否| DenyBlock["阻断核心功能"]
DenyBlock --> TTSNotify["TTS 提示并引导授权"]
TTSNotify --> End(["返回上一页或等待授权"])
ShowMap --> End
```

**图表来源**
- [amap-location/spec.md:11-38](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/amap-location/spec.md#L11-L38)
- [08-ios-architecture.md:107-118](file://docs/08-ios-architecture.md#L107-L118)

**章节来源**
- [amap-location/spec.md:1-38](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/amap-location/spec.md#L1-L38)
- [08-ios-architecture.md:98-118](file://docs/08-ios-architecture.md#L98-L118)

### 资料管理与预约创建
- 资料要求：盲人端在创建预约前必须完善昵称、紧急联系人姓名与电话。
- 预约规则：预约时间至少在当前时间 30 分钟之后；可选目的地、路线描述、备注等元数据。
- 错误处理：资料不完整、定位权限缺失、预约时间过近等场景返回明确错误码并播报 TTS。

**章节来源**
- [blind-runner-booking/spec.md:3-34](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/blind-runner-booking/spec.md#L3-L34)
- [07-api-contract.openapi.yaml:150-187](file://docs/07-api-contract.openapi.yaml#L150-L187)

## 依赖关系分析
- 视图与视图模型：页面负责渲染状态与转发用户意图，ViewModel 负责加载状态、验证、API 调用、轮询与 TTS 触发。
- 服务边界：APIClient 封装网络请求与错误映射；SpeechService 统一 TTS；AMapBridge 封装地图与定位能力。
- 环境配置：API 环境（mock/localBackend/production）通过单一 APIClient 协议实现多实现切换。

```mermaid
graph LR
View["View页面"] --> VM["ViewModel业务逻辑"]
VM --> Service["ServiceAPI/平台能力"]
Service --> APIClient["APIClient"]
VM --> Speech["SpeechService"]
VM --> Map["AMapBridge"]
APIClient --> Network["网络层"]
Map --> Platform["系统定位/地图"]
```

**图表来源**
- [08-ios-architecture.md:33-49](file://docs/08-ios-architecture.md#L33-L49)

**章节来源**
- [08-ios-architecture.md:68-83](file://docs/08-ios-architecture.md#L68-L83)

## 性能考虑
- 轮询频率：每 5 秒轮询一次，平衡实时性与资源消耗；在页面消失、订单终态或登出时及时停止。
- 网络重试：MVP 不引入复杂重试队列，保持简单可靠。
- UI 渲染：避免在轮询期间频繁重建视图，尽量局部更新。
- 语音播报：去重上次播报内容，避免轮询期间重复播报造成干扰。

## 故障排除指南
- 定位权限被拒：阻断预约创建与志愿者距离筛选，提示用户前往设置开启权限并播报 TTS。
- 状态轮询无响应：检查网络连通性与 API 环境配置；确认页面仍在轮询范围内。
- 紧急状态无法恢复：MVP 设计为紧急终态，不支持恢复或继续执行生命周期动作。
- 错误码识别：根据后端返回的错误码映射用户可读提示与 TTS 语音，便于快速定位问题。

**章节来源**
- [07-api-contract.openapi.yaml:469-542](file://docs/07-api-contract.openapi.yaml#L469-L542)
- [09-accessibility-and-voice-guidelines.md:88-107](file://docs/09-accessibility-and-voice-guidelines.md#L88-L107)

## 结论
BlindRunner 盲人跑者模块以清晰的订单状态机为核心，结合严格的轮询机制与无障碍语音播报，构建了视障用户可独立完成的完整服务闭环。通过高德地图与定位权限的规范处理，确保真实场景下的可用性与安全性。建议在后续开发中严格遵循 MVVM 架构与 OpenAPI 合同，确保跨端一致性与可维护性。

## 附录
- 测试框架：XCTest 单测与 XCUIAutomation UI 测试已配置，建议补充业务场景与轮询行为的自动化测试。
- 文档一致性：以 MVP v0.3 冻结口径为准，确保文档与 OpenSpec、API 合同保持一致。

**章节来源**
- [blindRunTests.swift:11-39](file://blindRunTests/blindRunTests.swift#L11-L39)
- [blindRunUITests.swift:10-44](file://blindRunUITests/blindRunUITests.swift#L10-L44)
- [00-consistency-check-report.md:45-63](file://docs/00-consistency-check-report.md#L45-L63)