# Core 核心模块

<cite>
**本文档引用的文件**
- [blindRunApp.swift](file://blindRun/blindRun/blindRunApp.swift)
- [ContentView.swift](file://blindRun/blindRun/ContentView.swift)
- [08-ios-architecture.md](file://docs/08-ios-architecture.md)
- [01-product-requirements.md](file://docs/01-product-requirements.md)
- [07-api-contract.openapi.yaml](file://docs/07-api-contract.openapi.yaml)
- [tasks.md](file://openspec/changes/add-aidrun-ios-spring-mvp/tasks.md)
- [spec.md](file://openspec/changes/add-aidrun-ios-spring-mvp/specs/backend-api-contract/spec.md)
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
Core 核心模块是应用基础设施层，负责：
- 应用环境与依赖注入容器
- 共享模型与全局状态管理
- 全局配置与环境切换
- 跨模块的服务与工具类共享
- 应用生命周期与认证状态管理

根据架构文档，Core 模块将为 Auth、Role、BlindRunner、Volunteer、Orders、Map、Voice、Safety、Profile 等模块提供统一的基础设施与共享能力。

## 项目结构
当前仓库包含最小可运行的 SwiftUI 应用骨架，以及完整的 iOS 架构与 API 合同文档。Core 模块尚未在代码中实现，但已在架构文档中明确定义其职责与边界。

```mermaid
graph TB
subgraph "应用入口"
App["blindRunApp<br/>应用入口"]
Content["ContentView<br/>根视图"]
end
subgraph "核心模块(Core)"
Env["环境配置<br/>APIEnvironment"]
DI["依赖注入容器<br/>服务注册与获取"]
State["全局状态管理<br/>认证状态/角色/配置"]
Shared["共享模型<br/>DTO/错误映射"]
end
subgraph "业务模块"
Auth["Auth<br/>登录/会话"]
Role["Role<br/>角色切换/守卫"]
BR["BlindRunner<br/>盲人端功能"]
Vol["Volunteer<br/>志愿者功能"]
Orders["Orders<br/>订单领域"]
Map["Map<br/>地图/定位"]
Voice["Voice<br/>语音/TTS"]
Safety["Safety<br/>安全/紧急"]
Profile["Profile<br/>个人资料"]
end
App --> Content
Content --> Core
Core --> Auth
Core --> Role
Core --> BR
Core --> Vol
Core --> Orders
Core --> Map
Core --> Voice
Core --> Safety
Core --> Profile
```

**图表来源**
- [08-ios-architecture.md:18-32](file://docs/08-ios-architecture.md#L18-L32)
- [blindRunApp.swift:10-17](file://blindRun/blindRun/blindRunApp.swift#L10-L17)
- [ContentView.swift:10-20](file://blindRun/blindRun/ContentView.swift#L10-L20)

**章节来源**
- [08-ios-architecture.md:18-32](file://docs/08-ios-architecture.md#L18-L32)
- [blindRunApp.swift:10-17](file://blindRun/blindRun/blindRunApp.swift#L10-L17)
- [ContentView.swift:10-20](file://blindRun/blindRun/ContentView.swift#L10-L20)

## 核心组件
Core 模块的核心职责包括：

- 依赖注入容器
  - 统一注册与获取服务实例
  - 在模块间共享单例与工厂
  - 支持 Mock 与真实实现切换

- 共享模型
  - DTO 与错误映射
  - 状态枚举与校验规则
  - 常用工具类型

- 应用状态管理
  - 用户认证状态
  - 活跃角色(activeRole)
  - 环境配置(APIEnvironment)
  - 应用生命周期事件

- 全局配置
  - 环境切换(mock/localBackend/production)
  - Token 存储与刷新
  - 无障碍与语音配置

**章节来源**
- [08-ios-architecture.md:22-31](file://docs/08-ios-architecture.md#L22-L31)
- [08-ios-architecture.md:50-82](file://docs/08-ios-architecture.md#L50-L82)

## 架构总览
Core 模块采用“基础设施即服务”的设计，向上提供稳定的服务契约，向下屏蔽具体实现细节。核心交互如下：

```mermaid
graph TB
subgraph "Core 核心"
DI["依赖注入容器"]
ENV["环境配置管理"]
STATE["全局状态管理"]
ERR["错误映射与提示"]
end
subgraph "网络层"
API["APIClient 协议"]
URL["URLSession 实现"]
MOCK["Mock 实现"]
end
subgraph "存储层"
UD["UserDefaults<br/>MVP: JWT/环境"]
KC["Keychain<br/>生产迁移"]
end
subgraph "业务模块"
Auth["Auth"]
Role["Role"]
BR["BlindRunner"]
Vol["Volunteer"]
Orders["Orders"]
Map["Map"]
Voice["Voice"]
Safety["Safety"]
Profile["Profile"]
end
DI --> API
DI --> STATE
DI --> ENV
API --> URL
API --> MOCK
STATE --> UD
STATE --> KC
Auth --> DI
Role --> DI
BR --> DI
Vol --> DI
Orders --> DI
Map --> DI
Voice --> DI
Safety --> DI
Profile --> DI
```

**图表来源**
- [08-ios-architecture.md:68-82](file://docs/08-ios-architecture.md#L68-L82)
- [08-ios-architecture.md:50-67](file://docs/08-ios-architecture.md#L50-L67)

## 详细组件分析

### 依赖注入容器
- 设计原则
  - 服务注册集中化，获取解耦化
  - 支持多实现切换(MVP: Mock/Real)
  - 避免循环依赖，保持低耦合
- 最佳实践
  - 使用协议抽象服务接口
  - 将构造函数参数注入容器
  - 对可选服务提供默认实现
  - 在 App 生命周期初始化容器

```mermaid
classDiagram
class DIContainer {
+register(service)
+resolve(type) Service
+mockMode(flag)
}
class APIClient {
<<protocol>>
+request() URLRequest
+decode() Result
}
class URLSessionClient {
+request() URLRequest
+decode() Result
}
class MockClient {
+request() URLRequest
+decode() Result
}
DIContainer --> APIClient : "注册/解析"
APIClient <|.. URLSessionClient : "实现"
APIClient <|.. MockClient : "实现"
```

**图表来源**
- [08-ios-architecture.md:68-82](file://docs/08-ios-architecture.md#L68-L82)

**章节来源**
- [08-ios-architecture.md:68-82](file://docs/08-ios-architecture.md#L68-L82)

### 全局状态管理
- 认证状态
  - JWT 令牌存储与续期
  - 登录/登出/会话恢复
  - 退出确认与清理
- 角色状态
  - activeRole 切换
  - 活跃订单阻断逻辑
  - 角色守卫与路由控制
- 环境配置
  - APIEnvironment 切换
  - Debug 下的环境选择器
  - LAN IP 支持(localBackend)
- 应用生命周期
  - 启动时状态恢复
  - 前后台切换处理
  - 异常状态兜底

```mermaid
stateDiagram-v2
[*] --> 未认证
未认证 --> 登录中 : "开始登录"
登录中 --> 已认证 : "登录成功"
登录中 --> 登录失败 : "登录失败"
已认证 --> 选择角色 : "首次登录/无activeRole"
已认证 --> 角色A : "已有activeRole"
选择角色 --> 角色A : "选择完成"
角色A --> 角色B : "切换角色"
角色B --> 角色A : "切换回A"
已认证 --> 登出中 : "触发登出"
登出中 --> 未认证 : "清理完成"
```

**图表来源**
- [08-ios-architecture.md:84-97](file://docs/08-ios-architecture.md#L84-L97)

**章节来源**
- [08-ios-architecture.md:84-97](file://docs/08-ios-architecture.md#L84-L97)

### 全局配置与环境切换
- 环境定义
  - mock: 本地假数据调试
  - localBackend: 开发者本机后端(LAN)
  - production: 预留部署
- 配置要点
  - baseURL 与显示名
  - 协议 APIClient 共用调用点
  - Debug 构建暴露小环境选择器
  - 生产 URL 保持占位直至部署

```mermaid
flowchart TD
Start(["应用启动"]) --> LoadEnv["加载环境配置"]
LoadEnv --> CheckBuild{"Debug 构建?"}
CheckBuild --> |是| ShowSelector["显示环境选择器"]
CheckBuild --> |否| UseDefault["使用默认环境"]
ShowSelector --> ApplyEnv["应用所选环境"]
UseDefault --> ApplyEnv
ApplyEnv --> InitServices["初始化服务"]
InitServices --> Ready(["应用就绪"])
```

**图表来源**
- [08-ios-architecture.md:50-67](file://docs/08-ios-architecture.md#L50-L67)

**章节来源**
- [08-ios-architecture.md:50-67](file://docs/08-ios-architecture.md#L50-L67)

### 共享模型与工具类
- DTO 与错误映射
  - 遵循 OpenAPI 合同
  - 错误码映射用户提示与 TTS
- 工具类
  - 日期/时间格式化
  - 地址/距离计算占位
  - 无障碍标签与提示

**章节来源**
- [07-api-contract.openapi.yaml:25-452](file://docs/07-api-contract.openapi.yaml#L25-L452)
- [08-ios-architecture.md:68-82](file://docs/08-ios-architecture.md#L68-L82)

### 新模块集成指南
- 步骤
  - 在 Core 中注册服务协议与实现
  - 在 ViewModel 中通过容器获取服务
  - 使用统一的错误映射与 TTS 提示
  - 遵循 MVVM 与依赖倒置原则
- 示例路径
  - [tasks.md:28-34](file://openspec/changes/add-aidrun-ios-spring-mvp/tasks.md#L28-L34)
  - [08-ios-architecture.md:33-49](file://docs/08-ios-architecture.md#L33-L49)

**章节来源**
- [tasks.md:28-34](file://openspec/changes/add-aidrun-ios-spring-mvp/tasks.md#L28-L34)
- [08-ios-architecture.md:33-49](file://docs/08-ios-architecture.md#L33-L49)

## 依赖关系分析
Core 模块与各业务模块的依赖关系如下：

```mermaid
graph LR
Core["Core 核心"] --> Auth["Auth"]
Core --> Role["Role"]
Core --> BR["BlindRunner"]
Core --> Vol["Volunteer"]
Core --> Orders["Orders"]
Core --> Map["Map"]
Core --> Voice["Voice"]
Core --> Safety["Safety"]
Core --> Profile["Profile"]
Auth --> Orders
BR --> Orders
Vol --> Orders
Orders --> Map
BR --> Voice
Vol --> Voice
Safety --> BR
Safety --> Vol
```

**图表来源**
- [08-ios-architecture.md:18-32](file://docs/08-ios-architecture.md#L18-L32)

**章节来源**
- [08-ios-architecture.md:18-32](file://docs/08-ios-architecture.md#L18-L32)

## 性能考虑
- 依赖注入
  - 避免在热路径频繁创建对象
  - 使用懒加载与单例缓存
- 网络层
  - URLSession 并发请求限制
  - 简单重试策略，避免复杂离线队列
- 状态管理
  - 认证状态变更通知最小化
  - 环境切换时的资源释放
- 无障碍与语音
  - TTS 队列与去重
  - 语音输入的中断处理

**章节来源**
- [08-ios-architecture.md:76-77](file://docs/08-ios-architecture.md#L76-L77)

## 故障排查指南
- 登录问题
  - 检查 UserDefaults 中 JWT 是否正确写入
  - 确认 APIClient 的 Authorization 头是否携带
  - 核对 API 合同中的错误码映射
- 角色切换阻断
  - 检查是否存在活跃订单
  - 确认 activeRole 切换接口返回
- 环境切换
  - Debug 构建下环境选择器是否可见
  - localBackend 的 LAN IP 是否可达
- 无障碍与语音
  - TTS 服务可用性
  - 语音输入权限与中断处理

**章节来源**
- [08-ios-architecture.md:84-97](file://docs/08-ios-architecture.md#L84-L97)
- [08-ios-architecture.md:50-67](file://docs/08-ios-architecture.md#L50-L67)
- [07-api-contract.openapi.yaml:469-542](file://docs/07-api-contract.openapi.yaml#L469-L542)

## 结论
Core 核心模块是应用的基础设施与共享中心，通过依赖注入、全局状态管理与统一配置，为各业务模块提供稳定可靠的支持。建议在实现过程中严格遵循 MVVM 与依赖倒置原则，确保模块间低耦合、高内聚，并为后续扩展预留空间。

## 附录
- 产品背景与技术约束
  - iOS 16+、SwiftUI + MVVM、URLSession、UserDefaults、高德地图、AVSpeechSynthesizer、Speech Framework
- API 合同要点
  - OpenAPI 文档覆盖认证、用户、资料、志愿者、订单等端点
  - 错误码稳定且可预测，便于前端统一处理

**章节来源**
- [01-product-requirements.md:79-95](file://docs/01-product-requirements.md#L79-L95)
- [07-api-contract.openapi.yaml:1-1117](file://docs/07-api-contract.openapi.yaml#L1-L1117)