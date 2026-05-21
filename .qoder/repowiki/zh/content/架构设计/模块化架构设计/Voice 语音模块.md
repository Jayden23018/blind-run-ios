# Voice 语音模块

<cite>
**本文档引用的文件**
- [09-无障碍与语音指南.md](file://docs/09-accessibility-and-voice-guidelines.md)
- [08-iOS 架构.md](file://docs/08-ios-architecture.md)
- [01-产品需求文档.md](file://docs/01-product-requirements.md)
- [02-MVP 范围.md](file://docs/02-mvp-scope.md)
- [03-用户故事.md](file://docs/03-user-stories.md)
- [spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/accessibility-voice-ui/spec.md)
- [tasks.md](file://openspec/changes/add-aidrun-ios-spring-mvp/tasks.md)
- [proposal.md](file://openspec/changes/add-aidrun-ios-spring-mvp/proposal.md)
- [10-AI 编码任务.md](file://docs/10-ai-coding-tasks.md)
- [ContentView.swift](file://blindRun/ContentView.swift)
- [blindRunApp.swift](file://blindRun/blindRunApp.swift)
</cite>

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构概览](#架构概览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排除指南](#故障排除指南)
9. [结论](#结论)
10. [附录](#附录)

## 简介

Voice 语音模块是 AidRun MVP 项目中的关键无障碍功能模块，专注于为盲人用户提供完整的语音交互体验。该模块基于 iOS 原生技术栈，实现了文本转语音(TTS)、语音输入、重复当前状态播报等核心功能。

### 核心功能特性

- **文本转语音(TTS)**：使用 AVSpeechSynthesizer 实现流畅的语音播报
- **语音输入**：集成 iOS Speech 框架进行语音识别
- **重复当前状态**：提供"重复当前状态"按钮功能
- **无障碍深度集成**：与 VoiceOver 屏幕阅读器完美配合
- **统一语音服务**：通过 SpeechService 提供一致的语音体验

## 项目结构

Voice 模块在项目中采用模块化设计，位于独立的 `Voice` 模块中，与其他核心模块协同工作。

```mermaid
graph TB
subgraph "Voice 模块"
VS[SpeechService]
TTS[TTS 引擎]
SI[语音输入助手]
RCS[重复状态按钮]
end
subgraph "核心模块"
BR[BlindRunner]
VM[ViewModels]
ORD[Orders]
SAF[Safety]
end
subgraph "系统框架"
AVS[AVSpeechSynthesizer]
SPEECH[iOS Speech 框架]
VO[VoiceOver]
end
VS --> AVS
VS --> SPEECH
VS --> VO
BR --> VS
VM --> VS
ORD --> VS
SAF --> VS
TTS --> AVS
SI --> SPEECH
```

**图表来源**
- [08-iOS 架构.md:29](file://docs/08-ios-architecture.md#L29)
- [09-无障碍与语音指南.md:15](file://docs/09-accessibility-and-voice-guidelines.md#L15)

**章节来源**
- [08-iOS 架构.md:18-31](file://docs/08-ios-architecture.md#L18-L31)
- [09-无障碍与语音指南.md:13-36](file://docs/09-accessibility-and-voice-guidelines.md#L13-L36)

## 核心组件

### SpeechService 抽象层

SpeechService 是 Voice 模块的核心抽象，提供统一的语音服务接口：

- **单一职责**：集中管理所有语音相关功能
- **跨模块共享**：被 BlindRunner、Volunteer、Safety 等模块共享
- **状态管理**：维护语音队列和当前播报状态
- **错误处理**：统一处理语音服务异常

### TTS 引擎组件

基于 AVSpeechSynthesizer 的文本转语音实现：

- **语音参数配置**：音量、语速、音调、语音类型
- **语音队列管理**：避免语音播报冲突和堆积
- **状态感知**：根据应用状态调整播报策略
- **本地化支持**：支持中文普通话语音合成

### 语音输入助手

集成 iOS Speech 框架的语音识别功能：

- **权限管理**：按需请求麦克风和语音识别权限
- **实时识别**：提供实时语音转文本功能
- **错误降级**：识别失败时提供键盘输入替代方案
- **文本字段专用**：仅用于文本输入场景

### 重复状态按钮

每个关键页面都提供"重复当前状态"功能：

- **一致性设计**：统一的按钮样式和标签
- **状态感知**：根据当前页面状态提供准确播报
- **无障碍支持**：完整的 VoiceOver 标签和提示

**章节来源**
- [09-无障碍与语音指南.md:32-35](file://docs/09-accessibility-and-voice-guidelines.md#L32-L35)
- [08-iOS 架构.md:29](file://docs/08-ios-architecture.md#L29)

## 架构概览

Voice 模块采用分层架构设计，确保功能分离和可维护性。

```mermaid
graph TD
subgraph "应用层"
BR[BlindRunner 页面]
VM[ViewModels]
SAF[Safety 页面]
end
subgraph "服务层"
SS[SpeechService]
TTS[AVSpeechSynthesizer]
SI[Speech Recognition]
end
subgraph "系统层"
AVS[AVSpeechSynthesizer Framework]
SPEECH[iOS Speech Framework]
VO[VoiceOver System]
end
BR --> VM
VM --> SS
SAF --> SS
SS --> TTS
SS --> SI
SS --> VO
TTS --> AVS
SI --> SPEECH
VO --> VO
style SS fill:#e1f5fe
style AVS fill:#f3e5f5
style SPEECH fill:#e8f5e8
```

**图表来源**
- [08-iOS 架构.md:140-146](file://docs/08-ios-architecture.md#L140-L146)
- [09-无障碍与语音指南.md:15](file://docs/09-accessibility-and-voice-guidelines.md#L15)

### 语音服务生命周期

```mermaid
sequenceDiagram
participant User as 用户
participant Page as 页面
participant VM as ViewModel
participant SS as SpeechService
participant TTS as AVSpeechSynthesizer
participant VO as VoiceOver
User->>Page : 触发语音播报
Page->>VM : 请求语音播报
VM->>SS : speak(text, options)
SS->>SS : 检查语音队列状态
SS->>TTS : enqueue(speechUtterance)
TTS-->>SS : 播报完成回调
SS-->>VM : 播报完成通知
VM-->>Page : 更新界面状态
VO-->>User : 屏幕阅读器同步
```

**图表来源**
- [09-无障碍与语音指南.md:32-35](file://docs/09-accessibility-and-voice-guidelines.md#L32-L35)

## 详细组件分析

### SpeechService 类设计

```mermaid
classDiagram
class SpeechService {
-speechSynthesizer : AVSpeechSynthesizer
-speechRecognizer : SFSpeechRecognizer
-voiceQueue : [String]
-lastSpokenStatus : String
-isSpeaking : Bool
+shared : SpeechService
+speak(text : String, options : SpeechOptions) Promise~Void~
+repeatCurrentStatus() Promise~Void~
+stopSpeaking() Void
+configureVoiceParameters(params : VoiceParams) Void
-processSpeechQueue() Void
-handleSpeechCompletion() Void
}
class SpeechOptions {
+queueMode : QueueMode
+interruptible : Bool
+shouldDelay : Bool
}
class VoiceParams {
+rate : Float
+volume : Float
+pitchMultiplier : Float
+voiceType : VoiceType
}
SpeechService --> SpeechOptions
SpeechService --> VoiceParams
```

**图表来源**
- [09-无障碍与语音指南.md:32-35](file://docs/09-accessibility-and-voice-guidelines.md#L32-L35)

### 语音参数配置

Voice 模块支持多种语音参数配置：

| 参数类别 | 配置项 | 默认值 | 说明 |
|---------|--------|--------|------|
| 语音速率 | rate | 0.5 | 0.0-1.0，0.5为默认语速 |
| 语音音量 | volume | 1.0 | 0.0-1.0，1.0为最大音量 |
| 音调倍数 | pitchMultiplier | 1.0 | 0.5-2.0，调节音调高低 |
| 语音类型 | voiceType | System Voice | 系统预设或自定义语音 |

### 语音队列管理系统

```mermaid
flowchart TD
Start([语音播报请求]) --> CheckQueue{"检查语音队列"}
CheckQueue --> |队列为空| CheckSpeaking{"正在播报?"}
CheckQueue --> |队列有内容| ProcessQueue["处理队列中的下一个项目"]
CheckSpeaking --> |是| AddToQueue["添加到队列末尾"]
CheckSpeaking --> |否| SpeakNow["立即播报"]
AddToQueue --> WaitComplete["等待当前播报完成"]
WaitComplete --> ProcessQueue
SpeakNow --> UpdateStatus["更新最后播报状态"]
ProcessQueue --> UpdateStatus
UpdateStatus --> End([完成])
```

**图表来源**
- [09-无障碍与语音指南.md:34](file://docs/09-accessibility-and-voice-guidelines.md#L34)

**章节来源**
- [09-无障碍与语音指南.md:30-35](file://docs/09-accessibility-and-voice-guidelines.md#L30-L35)

### 语音输入集成

语音输入功能专门用于文本字段，遵循严格的使用限制：

```mermaid
sequenceDiagram
participant User as 用户
participant Field as 文本输入字段
participant SI as 语音输入助手
participant Speech as Speech Framework
participant TTS as TTS 引擎
User->>Field : 点击麦克风按钮
Field->>SI : 请求语音识别
SI->>Speech : 请求麦克风权限
Speech-->>SI : 权限授权
SI->>Speech : 开始语音识别
Speech-->>SI : 实时识别文本
SI-->>Field : 更新输入框内容
SI->>TTS : 播报识别结果
TTS-->>User : 语音反馈
```

**图表来源**
- [09-无障碍与语音指南.md:75-86](file://docs/09-accessibility-and-voice-guidelines.md#L75-L86)

**章节来源**
- [09-无障碍与语音指南.md:71-87](file://docs/09-accessibility-and-voice-guidelines.md#L71-L87)

### 重复当前状态功能

每个关键页面都提供重复状态按钮，确保用户能够随时获取当前状态信息：

```mermaid
stateDiagram-v2
[*] --> Idle : 页面加载
Idle --> Listening : 用户点击"重复当前状态"
Listening --> Processing : 检索当前状态文本
Processing --> Speaking : 触发语音播报
Speaking --> Completed : 播报完成
Completed --> Idle : 返回页面状态
state Processing {
[*] --> ExtractText : 提取状态文本
ExtractText --> CheckText : 验证文本有效性
CheckText --> |有效| SpeakText : 触发语音播报
CheckText --> |无效| ErrorState : 显示错误
SpeakText --> [*]
ErrorState --> [*]
}
```

**图表来源**
- [09-无障碍与语音指南.md:29-35](file://docs/09-accessibility-and-voice-guidelines.md#L29-L35)

**章节来源**
- [09-无障碍与语音指南.md:27-35](file://docs/09-accessibility-and-voice-guidelines.md#L27-L35)

## 依赖关系分析

Voice 模块与项目其他组件存在紧密的依赖关系：

```mermaid
graph LR
subgraph "Voice 模块依赖"
SS[SpeechService]
TTS[AVSpeechSynthesizer]
SI[Speech Recognition]
end
subgraph "被依赖模块"
BR[BlindRunner]
VM[ViewModels]
ORD[Orders]
SAF[Safety]
MAP[Map]
end
subgraph "系统框架"
AVS[AVSpeechSynthesizer Framework]
SPEECH[iOS Speech Framework]
VO[VoiceOver System]
end
BR --> SS
VM --> SS
ORD --> SS
SAF --> SS
MAP --> SS
SS --> AVS
SS --> SPEECH
SS --> VO
```

**图表来源**
- [08-iOS 架构.md:140-146](file://docs/08-iOS-architecture.md#L140-L146)

### 模块间耦合度分析

| 依赖模块 | 耦合程度 | 说明 | 影响范围 |
|---------|---------|------|----------|
| BlindRunner | 高 | 订单状态播报、页面引导 | 订单全流程 |
| ViewModel | 中 | 状态变更触发、业务逻辑协调 | 所有业务页面 |
| Orders | 高 | 订单状态轮询、状态变化通知 | 订单状态管理 |
| Safety | 中 | 紧急状态播报、求助流程 | 安全功能 |
| Map | 低 | 地图相关语音提示 | 地图导航辅助 |

**章节来源**
- [08-iOS 架构.md:140-146](file://docs/08-iOS-architecture.md#L140-L146)

## 性能考虑

### 语音服务性能优化

Voice 模块在性能方面采取了多项优化措施：

- **语音队列去重**：避免重复播报相同状态
- **智能暂停机制**：应用后台运行时自动暂停语音播报
- **内存管理**：及时释放语音资源，避免内存泄漏
- **异步处理**：所有语音操作都在后台队列执行

### 电池消耗控制

```mermaid
flowchart TD
Start([应用状态]) --> Foreground{"前台运行?"}
Foreground --> |是| EnableVoice[启用语音服务]
Foreground --> |否| DisableVoice[禁用语音服务]
EnableVoice --> MonitorUsage[监控语音使用频率]
MonitorUsage --> HighUsage{"高频使用?"}
HighUsage --> |是| OptimizeSettings[优化语音设置]
HighUsage --> |否| NormalUsage[正常语音服务]
OptimizeSettings --> ReduceRate[降低语音速率]
OptimizeSettings --> ReduceVolume[降低语音音量]
OptimizeSettings --> DisableNonEssential[禁用非必要播报]
DisableVoice --> End([后台状态])
ReduceRate --> End
ReduceVolume --> End
DisableNonEssential --> End
NormalUsage --> End
```

**图表来源**
- [09-无障碍与语音指南.md:34](file://docs/09-accessibility-and-voice-guidelines.md#L34)

### 语音质量优化

- **网络适应性**：根据网络状况调整语音质量
- **设备适配**：针对不同设备优化语音参数
- **环境噪声处理**：在嘈杂环境中提高语音清晰度
- **电池优化**：智能节流语音服务以延长电池续航

## 故障排除指南

### 常见问题及解决方案

| 问题类型 | 症状描述 | 解决方案 | 预防措施 |
|---------|---------|---------|----------|
| 语音不播放 | TTS 无声音 | 检查系统语音设置、音量设置 | 定期检查音频配置 |
| 语音识别失败 | 语音输入无响应 | 检查麦克风权限、网络连接 | 提供权限引导 |
| 重复状态无效 | "重复当前状态"无反应 | 检查页面状态、语音服务状态 | 添加状态检查 |
| 语音冲突 | 多个播报同时进行 | 检查语音队列管理 | 优化队列处理逻辑 |

### 错误处理策略

Voice 模块采用多层次的错误处理机制：

```mermaid
flowchart TD
Error([语音服务错误]) --> CheckType{"错误类型"}
CheckType --> |权限错误| HandlePermission[处理权限问题]
CheckType --> |网络错误| HandleNetwork[处理网络问题]
CheckType --> |系统错误| HandleSystem[处理系统问题]
CheckType --> |业务错误| HandleBusiness[处理业务逻辑错误]
HandlePermission --> ShowPermissionAlert[显示权限提示]
HandleNetwork --> RetryLater[稍后重试]
HandleSystem --> FallbackToText[回退到文本显示]
HandleBusiness --> LogError[记录错误日志]
ShowPermissionAlert --> End([错误处理完成])
RetryLater --> End
FallbackToText --> End
LogError --> End
```

**图表来源**
- [09-无障碍与语音指南.md:85](file://docs/09-accessibility-and-voice-guidelines.md#L85)

**章节来源**
- [09-无障碍与语音指南.md:80-87](file://docs/09-accessibility-and-voice-guidelines.md#L80-L87)

## 结论

Voice 语音模块作为 AidRun MVP 的核心无障碍功能，成功实现了以下目标：

### 技术成就

- **统一接口设计**：通过 SpeechService 提供一致的语音体验
- **深度无障碍集成**：与 VoiceOver 完美配合，提供完整的屏幕阅读器支持
- **智能语音管理**：有效的语音队列管理和状态感知机制
- **性能优化**：合理的资源管理和电池消耗控制

### 业务价值

- **用户体验提升**：为盲人用户提供流畅的语音交互体验
- **功能完整性**：涵盖 TTS、语音输入、重复状态播报等核心功能
- **可维护性**：模块化设计确保代码的可维护性和可扩展性
- **合规性**：完全符合无障碍设计规范和要求

### 未来发展

Voice 模块为后续的功能扩展奠定了坚实基础，包括：

- **多语言支持**：为国际化做好准备
- **高级语音功能**：如语音控制、语音导航等
- **个性化配置**：用户可自定义语音偏好设置
- **智能语音助手**：在现有基础上扩展更多智能化功能

## 附录

### 语音服务配置参考

| 配置项 | 建议值 | 说明 |
|-------|--------|------|
| 最小语音间隔 | 1秒 | 避免频繁播报造成干扰 |
| 队列最大长度 | 5条 | 控制内存使用和响应时间 |
| 语音超时时间 | 30秒 | 防止语音服务长时间占用 |
| 重试次数 | 3次 | 平衡可靠性与性能 |
| 缓存有效期 | 5分钟 | 减少重复播报的频率 |

### 最佳实践建议

1. **统一管理**：所有语音相关功能通过 SpeechService 集中管理
2. **状态同步**：确保语音播报与应用状态保持同步
3. **用户控制**：提供语音功能开关，让用户自主控制
4. **错误优雅降级**：语音功能失败时提供文本替代方案
5. **性能监控**：定期监控语音服务的性能指标