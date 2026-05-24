# Safety 安全模块

<cite>
**本文引用的文件**
- [safety-basic-emergency/spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md)
- [04-user-flows-and-state-machine.md](file://docs/04-user-flows-and-state-machine.md)
- [02-mvp-scope.md](file://docs/02-mvp-scope.md)
- [09-accessibility-and-voice-guidelines.md](file://docs/09-accessibility-and-voice-guidelines.md)
- [blindRunApp.swift](file://blindRun/blindRunApp.swift)
- [ContentView.swift](file://blindRun/ContentView.swift)
- [03-user-stories.md](file://docs/03-user-stories.md)
- [01-product-requirements.md](file://docs/01-product-requirements.md)
</cite>

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构总览](#架构总览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排查指南](#故障排查指南)
9. [结论](#结论)
10. [附录](#附录)

## 简介
本文件面向 iOS 安全模块（Safety），聚焦紧急求助功能的实现与规范，包括紧急按钮设计、触发条件、求助流程、危险操作的双重确认机制、安全确认对话框的交互与逻辑、安全状态的全局管理、紧急情况下的备用通信与故障转移策略、与订单状态机的集成方式，以及测试策略与边界情况处理。文档严格基于仓库内的规格与需求文档，确保实现与产品目标一致。

## 项目结构
- 安全模块位于 iOS 应用的业务边界内，与订单状态机、轮询机制、无障碍播报（TTS）协同工作。
- 当前仓库中 iOS 应用骨架（SwiftUI）尚未包含具体安全实现代码，但安全模块的需求与流程已在文档中明确，可据此指导实现。

```mermaid
graph TB
subgraph "应用层"
App["应用入口<br/>blindRunApp"]
Views["视图层<br/>ContentView 等"]
Safety["安全模块<br/>紧急求助/确认对话框"]
Orders["订单状态机<br/>轮询/状态流转"]
Voice["无障碍播报<br/>TTS"]
end
subgraph "后端接口"
API["后端 API<br/>/orders/{orderId}/emergency"]
end
App --> Views
Views --> Safety
Safety --> Orders
Safety --> API
Orders --> Voice
```

**图表来源**
- [blindRunApp.swift:10-17](file://blindRun/blindRunApp.swift#L10-L17)
- [ContentView.swift:10-20](file://blindRun/ContentView.swift#L10-L20)
- [04-user-flows-and-state-machine.md:230-257](file://docs/04-user-flows-and-state-machine.md#L230-L257)

**章节来源**
- [blindRunApp.swift:10-17](file://blindRun/blindRunApp.swift#L10-L17)
- [ContentView.swift:10-20](file://blindRun/ContentView.swift#L10-L20)
- [04-user-flows-and-state-machine.md:1-70](file://docs/04-user-flows-and-state-machine.md#L1-L70)

## 核心组件
- 紧急求助触发器：在订单处于 accepted / arrived / in_progress 时可用，任一方（盲人/志愿者）均可触发。
- 确认对话框：触发紧急求助前弹出二次确认，确认文案与行为在无障碍与安全规范中有明确规定。
- 订单状态机：紧急求助导致状态进入 emergency，MVP 终态，不可恢复。
- 无障碍播报：进入 emergency 后，应用通过 TTS 播报状态变化。
- 全局安全状态管理：通过订单状态与页面状态联动，确保在紧急状态下关键流程被阻断。

**章节来源**
- [safety-basic-emergency/spec.md:11-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L17)
- [04-user-flows-and-state-machine.md:72-96](file://docs/04-user-flows-and-state-machine.md#L72-L96)
- [09-accessibility-and-voice-guidelines.md:97-106](file://docs/09-accessibility-and-voice-guidelines.md#L97-L106)

## 架构总览
安全模块与订单状态机紧密耦合，紧急求助作为状态机的一个外部事件源，驱动状态从 accepted / arrived / in_progress 转入 emergency，并通过轮询与 TTS 通知另一方用户。

```mermaid
sequenceDiagram
participant User as "任一方用户"
participant App as "iOS 应用"
participant API as "后端 API"
participant Other as "另一方用户"
Note over User,Other : 订单状态为 accepted / arrived / in_progress
User->>App : 点击"紧急求助"按钮
App->>User : 弹出确认弹窗<br/>“是否确认进入求助状态？”
User->>App : 确认求助
App->>API : POST /api/orders/{orderId}/emergency
API-->>App : { status : "emergency" }
App->>App : TTS 播报“已进入求助状态”
loop 另一方轮询
Other->>API : GET /api/orders/{orderId}
API-->>Other : { status : "emergency" }
Other->>Other : UI 更新 + TTS 提示
end
Note over App,Other : 显示紧急联系人信息盲人端<br/>订单不可恢复，保持 emergency 终态
```

**图表来源**
- [04-user-flows-and-state-machine.md:230-257](file://docs/04-user-flows-and-state-machine.md#L230-L257)

## 详细组件分析

### 紧急按钮与触发条件
- 触发条件：仅当订单状态为 accepted / arrived / in_progress 时，紧急按钮可用。
- 触发主体：盲人与志愿者任一方均可触发。
- 触发结果：状态进入 emergency，记录前序状态，MVP 终态。

```mermaid
flowchart TD
Start(["进入服务中页面"]) --> Check["检查订单状态"]
Check --> |accepted / arrived / in_progress| Enable["显示紧急求助按钮"]
Check --> |其他状态| Disable["隐藏/禁用紧急按钮"]
Enable --> Tap["用户点击紧急求助"]
Tap --> Confirm["弹出确认对话框"]
Confirm --> |确认| Emergency["POST /orders/{orderId}/emergency"]
Emergency --> End(["状态进入 emergency"])
Confirm --> |取消| Cancel["返回原页面"]
```

**图表来源**
- [04-user-flows-and-state-machine.md:19-21](file://docs/04-user-flows-and-state-machine.md#L19-L21)
- [04-user-flows-and-state-machine.md:82-91](file://docs/04-user-flows-and-state-machine.md#L82-L91)

**章节来源**
- [safety-basic-emergency/spec.md:19-25](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L19-L25)
- [04-user-flows-and-state-machine.md:19-21](file://docs/04-user-flows-and-state-machine.md#L19-L21)

### 危险操作的双重确认策略
- 需要二次确认的操作清单：取消订单、进入紧急状态、志愿者结束服务、退出登录。
- 紧急求助确认文案与提示：明确告知“确认后本次服务将标记为异常，系统会记录当前订单状态”，并伴随 TTS 提示。
- 确认后行为：立即发起 API 请求，进入 emergency 状态；MVP 不自动通知真实管理员或发送短信。

```mermaid
flowchart TD
Action["危险操作触发"] --> Confirm["弹出二次确认对话框"]
Confirm --> Choice{"用户选择"}
Choice --> |确认| Proceed["执行操作并记录日志"]
Choice --> |取消| Abort["取消操作并返回"]
Proceed --> Notify["TTS 提示操作结果"]
Notify --> Next["进入下一阶段流程"]
Abort --> End(["结束"])
Next --> End
```

**图表来源**
- [09-accessibility-and-voice-guidelines.md:88-106](file://docs/09-accessibility-and-voice-guidelines.md#L88-L106)
- [02-mvp-scope.md:73](file://docs/02-mvp-scope.md#L73)

**章节来源**
- [09-accessibility-and-voice-guidelines.md:88-106](file://docs/09-accessibility-and-voice-guidelines.md#L88-L106)
- [02-mvp-scope.md:73](file://docs/02-mvp-scope.md#L73)

### 安全确认对话框实现
- 用户界面设计：简洁明确的确认文案，突出风险提示；按钮采用高对比度与大尺寸，符合无障碍规范。
- 确认逻辑：仅在订单处于 active 状态（accepted / arrived / in_progress）时出现；确认后立即发起 API 请求。
- 取消处理：取消后回到原页面，不改变订单状态；确保用户不会误触。

```mermaid
classDiagram
class SafetyDialog {
+showConfirmation()
+onConfirm()
+onCancel()
-message : String
-orderStatus : Enum
}
class OrderStateMachine {
+currentState : String
+transitionToEmergency()
+canTriggerEmergency() : Bool
}
class API {
+postEmergency(orderId) : Promise
}
SafetyDialog --> OrderStateMachine : "检查状态"
SafetyDialog --> API : "提交请求"
```

**图表来源**
- [04-user-flows-and-state-machine.md:230-257](file://docs/04-user-flows-and-state-machine.md#L230-L257)
- [safety-basic-emergency/spec.md:11-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L17)

**章节来源**
- [safety-basic-emergency/spec.md:11-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L17)
- [09-accessibility-and-voice-guidelines.md:62-70](file://docs/09-accessibility-and-voice-guidelines.md#L62-L70)

### 安全状态的全局管理
- 启用时机：任一方在 accepted / arrived / in_progress 状态下触发紧急求助。
- 禁用时机：订单进入 emergency、completed、cancelled 任一终态后，紧急按钮不再可用。
- 全局一致性：emergency 为 MVP 终态，不可恢复；另一方轮询到状态变化后，UI 与 TTS 同步更新。

```mermaid
stateDiagram-v2
[*] --> matching
matching --> accepted
accepted --> arrived
arrived --> in_progress
in_progress --> emergency : "紧急求助"
accepted --> emergency : "紧急求助"
arrived --> emergency : "紧急求助"
emergency --> [*]
completed --> [*]
cancelled --> [*]
```

**图表来源**
- [04-user-flows-and-state-machine.md:72-96](file://docs/04-user-flows-and-state-machine.md#L72-L96)
- [01-product-requirements.md:154](file://docs/01-product-requirements.md#L154)

**章节来源**
- [04-user-flows-and-state-machine.md:72-96](file://docs/04-user-flows-and-state-machine.md#L72-L96)
- [01-product-requirements.md:154](file://docs/01-product-requirements.md#L154)

### 备用通信与故障转移策略
- MVP 不自动拨打电话、发送短信或通知真实管理员；紧急事件仅记录在系统中。
- 建议的备用通信方案（概念性）：在应用内提供“显示紧急联系人信息”的页面，供盲人端展示；若网络异常，仍可通过应用内提示与 TTS 提醒维持基本可用性。
- 故障转移：若 API 请求失败，应用应保留当前页面状态，允许用户重试或稍后重试；TTS 提示错误信息，避免用户误以为操作已生效。

**章节来源**
- [safety-basic-emergency/spec.md:35-41](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L35-L41)
- [09-accessibility-and-voice-guidelines.md:101-106](file://docs/09-accessibility-and-voice-guidelines.md#L101-L106)

### 与订单状态机的集成
- 紧急求助作为外部事件，直接驱动状态机从 active 状态转入 emergency。
- 与轮询机制协同：另一方持续轮询订单状态，一旦进入 emergency，立即 UI 更新与 TTS 提示。
- 与角色切换拦截配合：若存在 emergency 订单，阻止用户切换角色，避免干扰应急流程。

```mermaid
sequenceDiagram
participant App as "应用"
participant State as "状态机"
participant Poll as "轮询引擎"
participant VO as "另一方用户"
App->>State : 触发 emergency
State-->>App : 状态=emergency
Poll->>State : 查询状态
State-->>Poll : emergency
Poll-->>VO : 返回状态并更新 UI
VO->>VO : TTS 提示“进入求助状态”
```

**图表来源**
- [04-user-flows-and-state-machine.md:275-299](file://docs/04-user-flows-and-state-machine.md#L275-L299)
- [04-user-flows-and-state-machine.md:250-257](file://docs/04-user-flows-and-state-machine.md#L250-L257)

**章节来源**
- [04-user-flows-and-state-machine.md:275-299](file://docs/04-user-flows-and-state-machine.md#L275-L299)
- [04-user-flows-and-state-machine.md:250-257](file://docs/04-user-flows-and-state-machine.md#L250-L257)

## 依赖关系分析
- 安全模块依赖订单状态机与轮询机制，确保紧急状态能被及时感知与传播。
- 与无障碍模块（TTS）强耦合，保证状态变化与风险提示同步传达。
- 与 UI 导航（紧急求助页）协作，确保在 emergency 终态下用户路径清晰。

```mermaid
graph LR
Safety["安全模块"] --> StateMachine["订单状态机"]
Safety --> Polling["轮询引擎"]
Safety --> TTS["TTS 无障碍播报"]
Safety --> UI["紧急求助页"]
StateMachine --> API["后端 API"]
Polling --> API
```

**图表来源**
- [04-user-flows-and-state-machine.md:230-257](file://docs/04-user-flows-and-state-machine.md#L230-L257)
- [09-accessibility-and-voice-guidelines.md:97-106](file://docs/09-accessibility-and-voice-guidelines.md#L97-L106)

**章节来源**
- [04-user-flows-and-state-machine.md:230-257](file://docs/04-user-flows-and-state-machine.md#L230-L257)
- [09-accessibility-and-voice-guidelines.md:97-106](file://docs/09-accessibility-and-voice-guidelines.md#L97-L106)

## 性能考虑
- 紧急求助请求应尽量短路：仅包含必要的订单 ID 与上下文，避免额外网络开销。
- 轮询频率与紧急状态下的 UI 更新需平衡：紧急状态下可提高轮询频率以缩短感知延迟，但应避免过度频繁导致电量消耗。
- TTS 播报应简洁高效，避免冗长文本影响紧急响应速度。

## 故障排查指南
- 紧急求助无响应
  - 检查订单状态是否为 accepted / arrived / in_progress。
  - 检查网络请求是否成功，必要时重试。
  - 检查 TTS 是否正常工作。
- 状态未更新
  - 检查轮询是否仍在运行（仅限订单相关页面）。
  - 检查另一方是否收到状态变更通知。
- 确认对话框未出现
  - 检查当前页面是否为服务中页面。
  - 检查紧急按钮是否被禁用（非 active 状态）。

**章节来源**
- [04-user-flows-and-state-machine.md:275-299](file://docs/04-user-flows-and-state-machine.md#L275-L299)
- [09-accessibility-and-voice-guidelines.md:97-106](file://docs/09-accessibility-and-voice-guidelines.md#L97-L106)

## 结论
安全模块围绕紧急求助展开，强调“仅在服务中可用、二次确认、MVP 终态不可恢复”。其实现需与订单状态机、轮询与 TTS 无缝集成，确保在关键时刻能够中断常规流程并准确传达状态变化。当前仓库中 iOS 应用骨架尚未包含具体实现代码，但安全需求与流程已在文档中明确，可据此进行开发与测试。

## 附录
- 相关用户故事与演示场景可参考用户故事与状态机文档中的相应章节，以验证端到端流程。

**章节来源**
- [03-user-stories.md:148](file://docs/03-user-stories.md#L148)
- [03-user-stories.md:340](file://docs/03-user-stories.md#L340)
- [03-user-stories.md:644](file://docs/03-user-stories.md#L644)
- [02-mvp-scope.md:178-186](file://docs/02-mvp-scope.md#L178-L186)