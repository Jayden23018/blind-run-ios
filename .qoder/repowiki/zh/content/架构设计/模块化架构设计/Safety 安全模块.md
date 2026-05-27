# Safety 安全模块

<cite>
**本文引用的文件**
- [SafetyModule.swift](file://blindRun/blindRun/Safety/SafetyModule.swift)
- [spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md)
- [OrderDisplayHelpers.swift](file://blindRun/Core/Models/OrderDisplayHelpers.swift)
- [BlindOrderStatusView.swift](file://blindRun/BlindRunner/BlindOrderStatusView.swift)
- [VolunteerOrderFlowViews.swift](file://blindRun/Volunteer/VolunteerOrderFlowViews.swift)
- [OrderModels.swift](file://blindRun/Core/Models/OrderModels.swift)
- [04-user-flows-and-state-machine.md](file://docs/04-user-flows-and-state-machine.md)
- [02-mvp-scope.md](file://docs/02-mvp-scope.md)
- [09-accessibility-and-voice-guidelines.md](file://docs/09-accessibility-and-voice-guidelines.md)
- [blindRunApp.swift](file://blindRun/blindRunApp.swift)
- [ContentView.swift](file://blindRun/ContentView.swift)
- [03-user-stories.md](file://docs/03-user-stories.md)
- [01-product-requirements.md](file://docs/01-product-requirements.md)
</cite>

## 更新摘要
**变更内容**
- 新增 EmergencySafetyCopy 枚举，统一管理紧急求助功能的文案和无障碍标签
- 新增 EmergencyActionButton 结构体，实现紧急求助按钮的组件化设计
- 新增 emergencyConfirmationAlert 扩展，为所有视图提供标准化的紧急确认对话框
- 实现紧急求助功能的组件化和标准化，提升代码复用性和维护性
- 完善紧急求助按钮在盲人端和志愿者端的集成

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

**更新** 本版本重点介绍了新增的安全模块组件化实现，包括 EmergencySafetyCopy 枚举、EmergencyActionButton 结构体和 emergencyConfirmationAlert 扩展的标准化设计。

## 项目结构
- 安全模块位于 iOS 应用的业务边界内，与订单状态机、轮询机制、无障碍播报（TTS）协同工作。
- 当前仓库中 iOS 应用骨架（SwiftUI）已包含具体安全实现代码，通过专门的安全模块进行统一管理。

```mermaid
graph TB
subgraph "应用层"
App["应用入口<br/>blindRunApp"]
Views["视图层<br/>ContentView 等"]
Safety["安全模块<br/>EmergencySafetyCopy<br/>EmergencyActionButton<br/>emergencyConfirmationAlert"]
Orders["订单状态机<br/>RunOrderStatus<br/>OrderDisplayHelpers"]
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
- [SafetyModule.swift:1-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L1-L42)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)
- [BlindOrderStatusView.swift:348-352](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L348-L352)

**章节来源**
- [SafetyModule.swift:1-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L1-L42)
- [OrderDisplayHelpers.swift:1-159](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L1-L159)
- [BlindOrderStatusView.swift:162-238](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L162-L238)

## 核心组件
- **EmergencySafetyCopy 枚举**：统一管理紧急求助功能的所有文案、确认按钮标题、取消按钮标题、确认消息和无障碍标签，确保界面一致性。
- **EmergencyActionButton 结构体**：实现紧急求助按钮的组件化设计，支持加载状态和动作回调，继承自 PrimaryButton 并设置破坏性样式。
- **emergencyConfirmationAlert 扩展**：为所有 SwiftUI 视图提供标准化的紧急确认对话框功能，自动使用 EmergencySafetyCopy 的文案配置。
- **订单状态机**：紧急求助导致状态进入 emergency，MVP 终态，不可恢复。
- **无障碍播报**：进入 emergency 后，应用通过 TTS 播报状态变化。
- **全局安全状态管理**：通过订单状态与页面状态联动，确保在紧急状态下关键流程被阻断。

**更新** 新增了三个核心安全模块组件，实现了紧急求助功能的组件化和标准化。

**章节来源**
- [SafetyModule.swift:5-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L5-L42)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)
- [spec.md:11-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L17)

## 架构总览
安全模块与订单状态机紧密耦合，紧急求助作为状态机的一个外部事件源，驱动状态从 accepted / arrived / in_progress 转入 emergency，并通过轮询与 TTS 通知另一方用户。

```mermaid
sequenceDiagram
participant User as "任一方用户"
participant App as "iOS 应用"
participant Safety as "安全模块"
participant API as "后端 API"
participant Other as "另一方用户"
Note over User,Other : 订单状态为 accepted / arrived / in_progress
User->>App : 点击"一键求助"按钮
App->>Safety : EmergencyActionButton 触发
Safety->>User : 弹出确认弹窗<br/>"是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
User->>Safety : 确认求助
Safety->>API : POST /api/orders/{orderId}/emergency
API-->>Safety : { status : "emergency" }
Safety-->>App : 状态更新
App->>App : TTS 播报"已进入求助状态"
loop 另一方轮询
Other->>API : GET /api/orders/{orderId}
API-->>Other : { status : "emergency" }
Other->>Other : UI 更新 + TTS 提示
end
Note over App,Other : 显示紧急联系人信息盲人端<br/>订单不可恢复，保持 emergency 终态
```

**图表来源**
- [BlindOrderStatusView.swift:92-98](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L92-L98)
- [SafetyModule.swift:30-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L30-L42)

## 详细组件分析

### 紧急按钮与触发条件
- **触发条件**：仅当订单状态为 accepted / arrived / in_progress 时，紧急按钮可用。通过 `RunOrderStatus.canEnterEmergency` 属性控制按钮显示。
- **触发主体**：盲人与志愿者任一方均可触发。
- **触发结果**：状态进入 emergency，记录前序状态，MVP 终态。
- **组件化实现**：EmergencyActionButton 结构体提供统一的按钮样式和无障碍标签。

```mermaid
flowchart TD
Start(["进入服务中页面"]) --> Check["检查订单状态<br/>RunOrderStatus.canEnterEmergency"]
Check --> |true| Enable["显示紧急求助按钮<br/>EmergencyActionButton"]
Check --> |false| Disable["隐藏/禁用紧急按钮"]
Enable --> Tap["用户点击紧急求助"]
Tap --> Confirm["弹出确认对话框<br/>emergencyConfirmationAlert"]
Confirm --> |确认| Emergency["POST /orders/{orderId}/emergency"]
Emergency --> End(["状态进入 emergency"])
Confirm --> |取消| Cancel["返回原页面"]
```

**图表来源**
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)
- [BlindOrderStatusView.swift:348-352](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L348-L352)
- [VolunteerOrderFlowViews.swift:1490-1492](file://blindRun/Volunteer/VolunteerOrderFlowViews.swift#L1490-L1492)

**章节来源**
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)
- [SafetyModule.swift:14-28](file://blindRun/blindRun/Safety/SafetyModule.swift#L14-L28)
- [BlindOrderStatusView.swift:348-352](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L348-L352)

### 危险操作的双重确认策略
- **需要二次确认的操作清单**：取消订单、进入紧急状态、志愿者结束服务、退出登录。
- **紧急求助确认文案与提示**：通过 EmergencySafetyCopy 枚举统一管理，明确告知"确认后本次服务将标记为异常，系统会记录当前订单状态"，并伴随 TTS 提示。
- **确认后行为**：立即发起 API 请求，进入 emergency 状态；MVP 不自动通知真实管理员或发送短信。
- **标准化实现**：emergencyConfirmationAlert 扩展为所有视图提供一致的确认对话框体验。

```mermaid
flowchart TD
Action["危险操作触发"] --> Confirm["弹出二次确认对话框<br/>emergencyConfirmationAlert"]
Confirm --> Choice{"用户选择"}
Choice --> |确认| Proceed["执行操作并记录日志<br/>EmergencySafetyCopy 文案"]
Choice --> |取消| Abort["取消操作并返回"]
Proceed --> Notify["TTS 提示操作结果"]
Notify --> Next["进入下一阶段流程"]
Abort --> End(["结束"])
Next --> End
```

**图表来源**
- [SafetyModule.swift:30-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L30-L42)
- [spec.md:15-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L15-L17)

**章节来源**
- [SafetyModule.swift:30-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L30-L42)
- [spec.md:11-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L17)

### 安全确认对话框实现
- **用户界面设计**：通过 emergencyConfirmationAlert 扩展自动创建，使用 EmergencySafetyCopy 枚举中的统一文案，确保界面一致性。
- **确认逻辑**：仅在订单处于 active 状态（accepted / arrived / in_progress）时出现；确认后立即发起 API 请求。
- **取消处理**：取消后回到原页面，不改变订单状态；确保用户不会误触。
- **无障碍支持**：自动应用无障碍标签和提示，符合无障碍规范要求。

```mermaid
classDiagram
class EmergencySafetyCopy {
+title : String
+confirmButtonTitle : String
+cancelButtonTitle : String
+confirmationMessage : String
+accessibilityLabel : String
+accessibilityHint : String
}
class EmergencyActionButton {
+isLoading : Bool
+action : () -> Void
+body : View
}
class SafetyDialogExtension {
+emergencyConfirmationAlert() : View
+alert() : Alert
}
class OrderStateMachine {
+currentState : String
+transitionToEmergency()
+canTriggerEmergency() : Bool
}
class API {
+postEmergency(orderId) : Promise
}
EmergencySafetyCopy --> EmergencyActionButton : "提供文案"
EmergencySafetyCopy --> SafetyDialogExtension : "提供文案"
EmergencyActionButton --> OrderStateMachine : "检查状态"
SafetyDialogExtension --> API : "提交请求"
```

**图表来源**
- [SafetyModule.swift:5-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L5-L42)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)

**章节来源**
- [SafetyModule.swift:5-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L5-L42)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)

### 安全状态的全局管理
- **启用时机**：任一方在 accepted / arrived / in_progress 状态下触发紧急求助。
- **禁用时机**：订单进入 emergency、completed、cancelled 任一终态后，紧急按钮不再可用。
- **全局一致性**：emergency 为 MVP 终态，不可恢复；另一方轮询到状态变化后，UI 与 TTS 同步更新。
- **组件化优势**：通过 EmergencyActionButton 和 emergencyConfirmationAlert 统一管理，减少重复代码。

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
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)
- [OrderModels.swift:12-23](file://blindRun/Core/Models/OrderModels.swift#L12-L23)

**章节来源**
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)
- [OrderModels.swift:5-34](file://blindRun/Core/Models/OrderModels.swift#L5-L34)

### 备用通信与故障转移策略
- **MVP 不自动拨打电话、发送短信或通知真实管理员**；紧急事件仅记录在系统中。
- **建议的备用通信方案**（概念性）：在应用内提供"显示紧急联系人信息"的页面，供盲人端展示；若网络异常，仍可通过应用内提示与 TTS 提醒维持基本可用性。
- **故障转移**：若 API 请求失败，应用应保留当前页面状态，允许用户重试或稍后重试；TTS 提示错误信息，避免用户误以为操作已生效。
- **组件化容错**：通过 performAction 方法统一处理 API 调用错误，提供一致的错误处理体验。

**章节来源**
- [spec.md:35-41](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L35-L41)
- [BlindOrderStatusView.swift:127-146](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L127-L146)

### 与订单状态机的集成
- **紧急求助作为外部事件**，直接驱动状态机从 active 状态转入 emergency。
- **与轮询机制协同**：另一方持续轮询订单状态，一旦进入 emergency，立即 UI 更新与 TTS 提示。
- **与角色切换拦截配合**：若存在 emergency 订单，阻止用户切换角色，避免干扰应急流程。
- **组件化集成**：EmergencyActionButton 和 emergencyConfirmationAlert 与订单状态机无缝集成，提供一致的用户体验。

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
VO->>VO : TTS 提示"进入求助状态"
```

**图表来源**
- [BlindOrderStatusView.swift:92-98](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L92-L98)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)

**章节来源**
- [BlindOrderStatusView.swift:92-98](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L92-L98)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)

## 依赖关系分析
- **安全模块依赖**订单状态机与轮询机制，确保紧急状态能被及时感知与传播。
- **与无障碍模块**（TTS）强耦合，保证状态变化与风险提示同步传达。
- **与 UI 导航**（紧急求助页）协作，确保在 emergency 终态下用户路径清晰。
- **组件化优势**：EmergencySafetyCopy、EmergencyActionButton 和 emergencyConfirmationAlert 形成完整的安全模块生态系统。

```mermaid
graph LR
Safety["安全模块"] --> StateMachine["订单状态机"]
Safety --> Polling["轮询引擎"]
Safety --> TTS["TTS 无障碍播报"]
Safety --> UI["紧急求助页"]
Safety --> Components["组件化安全组件"]
StateMachine --> API["后端 API"]
Polling --> API
Components --> EmergencySafetyCopy["统一文案管理"]
Components --> EmergencyActionButton["按钮组件化"]
Components --> EmergencyConfirmationAlert["对话框扩展"]
```

**图表来源**
- [SafetyModule.swift:1-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L1-L42)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)

**章节来源**
- [SafetyModule.swift:1-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L1-L42)
- [OrderDisplayHelpers.swift:25-32](file://blindRun/Core/Models/OrderDisplayHelpers.swift#L25-L32)

## 性能考虑
- **紧急求助请求应尽量短路**：仅包含必要的订单 ID 与上下文，避免额外网络开销。
- **轮询频率与紧急状态下的 UI 更新需平衡**：紧急状态下可提高轮询频率以缩短感知延迟，但应避免过度频繁导致电量消耗。
- **TTS 播报应简洁高效**：避免冗长文本影响紧急响应速度。
- **组件化优化**：通过统一的组件设计减少重复计算和内存占用。

## 故障排查指南
- **紧急求助无响应**
  - 检查订单状态是否为 accepted / arrived / in_progress。
  - 检查网络请求是否成功，必要时重试。
  - 检查 TTS 是否正常工作。
  - 验证 EmergencyActionButton 组件是否正确初始化。
- **状态未更新**
  - 检查轮询是否仍在运行（仅限订单相关页面）。
  - 检查另一方是否收到状态变更通知。
  - 验证 apply 方法是否正确调用。
- **确认对话框未出现**
  - 检查当前页面是否为服务中页面。
  - 检查紧急按钮是否被禁用（非 active 状态）。
  - 验证 emergencyConfirmationAlert 扩展是否正确应用。
- **组件化问题**
  - 检查 EmergencySafetyCopy 枚举中的文案是否正确。
  - 验证 EmergencyActionButton 的 accessibility 标签是否生效。

**章节来源**
- [BlindOrderStatusView.swift:127-146](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L127-L146)
- [SafetyModule.swift:30-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L30-L42)

## 结论
安全模块围绕紧急求助展开，强调"仅在服务中可用、二次确认、MVP 终态不可恢复"。通过新增的 EmergencySafetyCopy 枚举、EmergencyActionButton 结构体和 emergencyConfirmationAlert 扩展，实现了紧急求助功能的组件化和标准化，提升了代码复用性和维护性。其实现与订单状态机、轮询与 TTS 无缝集成，确保在关键时刻能够中断常规流程并准确传达状态变化。新的组件化设计为未来的功能扩展奠定了坚实基础。

## 附录
- 相关用户故事与演示场景可参考用户故事与状态机文档中的相应章节，以验证端到端流程。
- **新增组件使用示例**：
  - `EmergencySafetyCopy.title` - 获取按钮标题
  - `EmergencyActionButton(isLoading: true, action: myAction)` - 创建紧急按钮
  - `.emergencyConfirmationAlert(isPresented: $showAlert, onConfirm: confirmAction)` - 添加确认对话框

**章节来源**
- [spec.md:11-17](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/safety-basic-emergency/spec.md#L11-L17)
- [SafetyModule.swift:5-42](file://blindRun/blindRun/Safety/SafetyModule.swift#L5-L42)
- [BlindOrderStatusView.swift:348-352](file://blindRun/BlindRunner/BlindOrderStatusView.swift#L348-L352)