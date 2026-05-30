# Mock API 客户端功能增强

<cite>
**本文档引用的文件**
- [APIClient.swift](file://blindRun/Core/APIClient.swift)
- [MockAPIClient.swift](file://blindRun/Core/MockAPIClient.swift)
- [AppState.swift](file://blindRun/Core/AppState.swift)
- [EnvironmentConfig.swift](file://blindRun/Core/EnvironmentConfig.swift)
- [UserModels.swift](file://blindRun/Core/Models/UserModels.swift)
- [OrderModels.swift](file://blindRun/Core/Models/OrderModels.swift)
- [ProfileModels.swift](file://blindRun/Core/Models/ProfileModels.swift)
- [LoginView.swift](file://blindRun/Auth/LoginView.swift)
- [LoginViewModel.swift](file://blindRun/Auth/LoginViewModel.swift)
- [AidRunBackendApplication.java](file://backend/src/main/java/com/aidrun/backend/AidRunBackendApplication.java)
- [application.yml](file://backend/src/main/resources/application.yml)
- [AuthController.java](file://backend/src/main/java/com/aidrun/backend/auth/AuthController.java)
- [RunOrderController.java](file://backend/src/main/java/com/aidrun/backend/order/RunOrderController.java)
- [ProfileController.java](file://backend/src/main/java/com/aidrun/backend/profile/ProfileController.java)
- [07-api-contract.openapi.yaml](file://docs/07-api-contract.openapi.yaml)
- [ProfileControllerIntegrationTest.java](file://backend/src/test/java/com/aidrun/backend/profile/ProfileControllerIntegrationTest.java)
- [DemoDataSeederTests.java](file://backend/src/test/java/com/aidrun/backend/DemoDataSeederTests.java)
- [blindRunUITests.swift](file://blindRunUITests/blindRunUITests.swift)
</cite>

## 更新摘要
**所做更改**
- 更新了资料更新方法部分，反映ProfileResponse对象完整返回的改进
- 新增了测试可靠性提升的相关内容
- 增强了Mock客户端状态管理的描述
- 更新了UI测试环境变量的说明

## 目录
1. [项目概述](#项目概述)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构概览](#架构概览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排除指南](#故障排除指南)
9. [结论](#结论)

## 项目概述

本项目是一个为视障人士设计的跑步辅助应用，包含完整的前后端架构。项目的核心功能是提供Mock API客户端功能增强，支持离线开发和演示，模拟真实的API交互流程。

项目采用SwiftUI框架构建iOS前端应用，Spring Boot构建后端服务，实现了从手机号登录到订单管理的完整业务流程。Mock API客户端作为核心组件，提供了完整的订单生命周期管理和状态转换功能，现已支持资料更新方法返回完整的ProfileResponse对象。

## 项目结构

```mermaid
graph TB
subgraph "iOS前端应用"
AppState[AppState<br/>全局状态管理]
APIClient[APIClient<br/>协议层]
MockClient[MockAPIClient<br/>模拟客户端]
URLSessionClient[URLSessionAPIClient<br/>网络客户端]
Models[模型定义<br/>用户/订单/状态/资料]
Views[视图层<br/>登录/主页/订单/资料]
end
subgraph "后端服务"
Backend[Spring Boot后端]
AuthCtrl[认证控制器]
OrderCtrl[订单控制器]
ProfileCtrl[资料控制器]
Config[应用配置]
end
subgraph "数据库"
H2[H2内存数据库]
end
AppState --> APIClient
APIClient --> MockClient
APIClient --> URLSessionClient
AppState --> Models
AppState --> Views
MockClient --> Models
URLSessionClient --> Backend
Backend --> AuthCtrl
Backend --> OrderCtrl
Backend --> ProfileCtrl
Backend --> H2
AuthCtrl --> H2
OrderCtrl --> H2
ProfileCtrl --> H2
```

**图表来源**
- [AppState.swift:87-105](file://blindRun/Core/AppState.swift#L87-L105)
- [APIClient.swift:46-58](file://blindRun/Core/APIClient.swift#L46-L58)
- [MockAPIClient.swift:7-27](file://blindRun/Core/MockAPIClient.swift#L7-L27)

**章节来源**
- [AppState.swift:1-313](file://blindRun/Core/AppState.swift#L1-L313)
- [APIClient.swift:1-269](file://blindRun/Core/APIClient.swift#L1-L269)
- [MockAPIClient.swift:1-642](file://blindRun/Core/MockAPIClient.swift#L1-L642)

## 核心组件

### API客户端协议体系

项目实现了统一的API客户端协议，支持多种实现方式：

```mermaid
classDiagram
class APIClientProtocol {
<<protocol>>
+request(method, path, query, body, requiresAuth) T
+get(path, query, requiresAuth) T
+post(path, body, requiresAuth) T
+put(path, body, requiresAuth) T
+patch(path, body, requiresAuth) T
+delete(path, requiresAuth) T
}
class URLSessionAPIClient {
-baseURL : URL
-session : URLSession
-tokenProvider : () -> String?
+request() T
+upload() T
}
class MockAPIClient {
-mockToken : String?
-orders : [OrderDetailResponse]
-blindProfile : BlindProfileResponse?
+routeRequest() Any
+handleCreateOrder() OrderResponse
+handleUpdateBlindProfile() BlindProfileResponse
+handleUpdateVolunteerProfile() VolunteerProfileResponse
}
class DisabledAPIClient {
+request() T
}
APIClientProtocol <|-- URLSessionAPIClient
APIClientProtocol <|-- MockAPIClient
APIClientProtocol <|-- DisabledAPIClient
```

**图表来源**
- [APIClient.swift:46-58](file://blindRun/Core/APIClient.swift#L46-L58)
- [APIClient.swift:103-133](file://blindRun/Core/APIClient.swift#L103-L133)
- [MockAPIClient.swift:7-27](file://blindRun/Core/MockAPIClient.swift#L7-L27)
- [AppState.swift:302-312](file://blindRun/Core/AppState.swift#L302-L312)

### 状态管理系统

全局状态管理器负责协调各个模块的工作：

- **会话管理**：JWT令牌存储、用户身份验证
- **环境配置**：支持开发、演示、生产三种环境
- **WebSocket连接**：实时通信支持
- **数据持久化**：UserDefaults存储关键配置
- **资料缓存**：盲人和志愿者资料的本地缓存

**章节来源**
- [AppState.swift:9-313](file://blindRun/Core/AppState.swift#L9-L313)
- [EnvironmentConfig.swift:5-89](file://blindRun/Core/EnvironmentConfig.swift#L5-L89)

## 架构概览

```mermaid
sequenceDiagram
participant User as 用户
participant LoginView as 登录视图
participant LoginVM as 登录ViewModel
participant AppState as 应用状态
participant APIClient as API客户端
participant MockClient as Mock客户端
participant Backend as 后端服务
User->>LoginView : 输入手机号
LoginView->>LoginVM : requestCode()
LoginVM->>AppState : 获取apiClient
AppState->>APIClient : 返回MockAPIClient
APIClient->>MockClient : 发送验证码请求
MockClient-->>LoginVM : 成功响应
LoginVM->>LoginView : 显示验证码输入
User->>LoginView : 输入验证码
LoginView->>LoginVM : submitLogin()
LoginVM->>AppState : 获取apiClient
AppState->>APIClient : 返回MockAPIClient
APIClient->>MockClient : 验证码验证
MockClient-->>LoginVM : 登录响应
LoginVM->>AppState : 处理登录成功
AppState->>AppState : 更新会话状态
```

**图表来源**
- [LoginView.swift:150-200](file://blindRun/Auth/LoginView.swift#L150-L200)
- [LoginViewModel.swift:149-213](file://blindRun/Auth/LoginViewModel.swift#L149-L213)
- [AppState.swift:87-105](file://blindRun/Core/AppState.swift#L87-L105)

## 详细组件分析

### Mock API客户端增强功能

Mock API客户端实现了完整的订单生命周期管理，现已支持资料更新方法返回完整的ProfileResponse对象：

#### 订单状态流转

```mermaid
stateDiagram-v2
[*] --> PENDING_MATCH : 创建订单
PENDING_MATCH --> PENDING_ACCEPT : 志愿者接单
PENDING_ACCEPT --> DRIVER_EN_ROUTE : 志愿者出发
DRIVER_EN_ROUTE --> DRIVER_ARRIVED : 志愿者到达
DRIVER_ARRIVED --> IN_PROGRESS : 开始跑步
IN_PROGRESS --> COMPLETED : 服务完成
PENDING_MATCH --> CANCELLED : 用户取消
PENDING_ACCEPT --> CANCELLED : 志愿者取消
IN_PROGRESS --> CANCELLED : 紧急取消
```

**图表来源**
- [OrderModels.swift:5-68](file://blindRun/Core/Models/OrderModels.swift#L5-L68)
- [MockAPIClient.swift:393-451](file://blindRun/Core/MockAPIClient.swift#L393-L451)

#### 资料更新功能增强

**更新** Mock API客户端现已支持完整的资料更新功能，包括盲人和志愿者资料的更新，返回完整的ProfileResponse对象：

- **盲人资料更新**：支持昵称、配速偏好、特殊需求等字段的更新
- **志愿者资料更新**：支持可用性、时间安排、配速范围等字段的更新
- **完整响应对象**：更新后返回完整的ProfileResponse对象，包含所有字段
- **状态同步**：更新后的资料立即反映在应用状态中

**章节来源**
- [MockAPIClient.swift:224-241](file://blindRun/Core/MockAPIClient.swift#L224-L241)
- [MockAPIClient.swift:265-279](file://blindRun/Core/MockAPIClient.swift#L265-L279)
- [ProfileModels.swift:4-49](file://blindRun/Core/Models/ProfileModels.swift#L4-L49)
- [ProfileModels.swift:82-114](file://blindRun/Core/Models/ProfileModels.swift#L82-L114)

#### 认证流程

Mock客户端支持完整的认证机制：

- **手机号验证**：支持中国大陆手机号格式验证
- **验证码系统**：固定验证码123456用于演示
- **JWT令牌管理**：模拟令牌生成和刷新
- **角色切换**：支持盲人和志愿者角色切换

**章节来源**
- [MockAPIClient.swift:162-198](file://blindRun/Core/MockAPIClient.swift#L162-L198)
- [UserModels.swift:24-52](file://blindRun/Core/Models/UserModels.swift#L24-L52)

### 测试可靠性提升

**新增** 项目引入了全面的UI测试环境变量，显著提升了测试的可靠性：

#### UI测试环境变量

| 环境变量 | 用途 | 默认值 | 描述 |
|---------|------|--------|------|
| AIDRUN_UI_TEST_RESET_STATE | 重置应用状态 | "1" | 清空本地存储，确保测试隔离 |
| AIDRUN_UI_TEST_FORCE_DEMO_LOCATION | 强制演示位置 | "1" | 使用固定位置进行测试 |
| AIDRUN_UI_TEST_API_ENV | API环境选择 | "mock" | 支持mock、local、demo、production |
| AIDRUN_UI_TEST_ACTIVE_ROLE | 激活角色 | "blind_runner" | 设置默认用户角色 |
| AIDRUN_UI_TEST_DISABLE_WEBSOCKET | 禁用WebSocket | "1" | 禁用实时通信，稳定测试 |
| AIDRUN_UI_TEST_DISABLE_MAP | 禁用地图 | "1" | 禁用地图功能，提高稳定性 |
| AIDRUN_UI_TEST_PREFILL_PROFILE_FORM | 预填充资料表单 | "1" | 自动填写测试资料 |
| AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE | 预设盲人资料 | "1" | 提前设置盲人资料 |
| AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_PROFILE | 预设志愿者资料 | "1" | 提前设置志愿者资料 |
| AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE | 志愿者可用性 | "1" | 设置志愿者为可用状态 |
| AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS | 空订单集合 | "1" | 清空模拟订单数据 |

#### 测试稳定性改进

- **状态隔离**：每次测试前自动重置应用状态
- **网络稳定性**：禁用WebSocket和地图功能，减少网络干扰
- **数据一致性**：预设测试数据，确保测试可重复性
- **超时处理**：智能等待机制，适应不同测试环境

**章节来源**
- [MockAPIClient.swift:543-569](file://blindRun/Core/MockAPIClient.swift#L543-L569)
- [blindRunUITests.swift:160-195](file://blindRunUITests/blindRunUITests.swift#L160-L195)

### 环境配置管理

应用支持四种运行环境：

| 环境类型 | 用途 | 特点 |
|---------|------|------|
| Mock | 本地开发 | 完全离线，模拟所有API |
| Local Backend | 本地联调 | 连接本地Spring Boot服务 |
| Demo Cloud | 演示环境 | 连接云端演示服务 |
| Production | 生产环境 | 连接正式生产服务 |

**章节来源**
- [EnvironmentConfig.swift:49-89](file://blindRun/Core/EnvironmentConfig.swift#L49-L89)
- [AppState.swift:87-105](file://blindRun/Core/AppState.swift#L87-L105)

### 数据模型设计

项目实现了完整的数据模型体系：

#### 用户模型
- **UserRole**：盲人、志愿者、未设置三种角色
- **认证请求**：手机号登录、验证码验证
- **响应模型**：登录响应、角色切换响应

#### 订单模型
- **RunOrderStatus**：完整的订单状态枚举
- **偏好设置**：配速偏好、路线偏好
- **分页响应**：支持后端返回的分页数据

#### 资料模型增强
**更新** 资料模型现已支持完整的ProfileResponse对象：

- **盲人资料**：包含昵称、配速、视觉等级、牵引偏好等
- **志愿者资料**：包含验证状态、可用性、时间安排等
- **紧急联系人**：支持多联系人管理
- **枚举类型**：视觉等级、牵引偏好、聊天偏好等

**章节来源**
- [UserModels.swift:5-60](file://blindRun/Core/Models/UserModels.swift#L5-L60)
- [OrderModels.swift:108-195](file://blindRun/Core/Models/OrderModels.swift#L108-L195)
- [ProfileModels.swift:1-214](file://blindRun/Core/Models/ProfileModels.swift#L1-214)

## 依赖关系分析

```mermaid
graph TD
subgraph "核心依赖"
APIClient[APIClient.swift]
MockClient[MockAPIClient.swift]
AppState[AppState.swift]
EnvConfig[EnvironmentConfig.swift]
end
subgraph "模型依赖"
UserModel[UserModels.swift]
OrderModel[OrderModels.swift]
ProfileModel[ProfileModels.swift]
ErrorModel[ErrorModels.swift]
end
subgraph "视图依赖"
LoginView[LoginView.swift]
LoginVM[LoginViewModel.swift]
end
subgraph "后端依赖"
BackendApp[AidRunBackendApplication.java]
AuthCtrl[AuthController.java]
OrderCtrl[RunOrderController.java]
ProfileCtrl[ProfileController.java]
AppConfig[application.yml]
end
APIClient --> UserModel
APIClient --> OrderModel
APIClient --> ProfileModel
APIClient --> ErrorModel
MockClient --> APIClient
AppState --> APIClient
AppState --> EnvConfig
LoginView --> LoginVM
LoginVM --> AppState
BackendApp --> AuthCtrl
BackendApp --> OrderCtrl
BackendApp --> ProfileCtrl
AuthCtrl --> UserModel
OrderCtrl --> OrderModel
ProfileCtrl --> ProfileModel
AppConfig --> BackendApp
```

**图表来源**
- [APIClient.swift:1-269](file://blindRun/Core/APIClient.swift#L1-L269)
- [MockAPIClient.swift:1-642](file://blindRun/Core/MockAPIClient.swift#L1-L642)
- [AppState.swift:1-313](file://blindRun/Core/AppState.swift#L1-L313)

**章节来源**
- [AuthController.java:1-28](file://backend/src/main/java/com/aidrun/backend/auth/AuthController.java#L1-L28)
- [RunOrderController.java:1-140](file://backend/src/main/java/com/aidrun/backend/order/RunOrderController.java#L1-L140)
- [ProfileController.java:1-33](file://backend/src/main/java/com/aidrun/backend/profile/ProfileController.java#L1-L33)

## 性能考虑

### Mock客户端优化策略

1. **网络延迟模拟**：300ms延迟模拟真实网络环境
2. **内存管理**：使用结构体而非类减少内存分配
3. **类型安全**：严格的类型检查避免运行时错误
4. **异步处理**：全面使用async/await提升并发性能
5. **状态缓存**：资料更新后立即缓存，避免重复查询

### 缓存策略

- **会话缓存**：UserDefaults存储令牌和用户信息
- **配置缓存**：环境配置持久化
- **状态缓存**：订单状态本地缓存
- **资料缓存**：盲人和志愿者资料本地缓存

## 故障排除指南

### 常见问题及解决方案

#### 认证相关问题
- **验证码错误**：检查Mock客户端中的固定验证码123456
- **手机号格式错误**：验证11位数字格式
- **登录失败**：检查Mock客户端状态初始化

#### 订单相关问题
- **订单创建失败**：确认盲人资料和紧急联系人完整性
- **状态转换异常**：验证订单状态转换规则
- **查询结果为空**：检查Mock数据种子配置

#### 资料更新问题
**更新** 资料更新功能的常见问题：
- **更新后未生效**：确认返回的是完整的ProfileResponse对象
- **字段更新失败**：检查ProfileUpdateRequest的字段映射
- **状态不同步**：验证AppState中的资料缓存更新

#### 测试相关问题
**新增** UI测试的常见问题：
- **测试不稳定**：检查环境变量配置是否正确
- **数据不一致**：确认AIDRUN_UI_TEST_RESET_STATE是否启用
- **网络干扰**：验证AIDRUN_UI_TEST_DISABLE_WEBSOCKET设置

#### 环境配置问题
- **无法连接后端**：检查本地IP配置和防火墙设置
- **环境切换失效**：验证构建通道配置
- **演示数据缺失**：检查环境变量设置

**章节来源**
- [MockAPIClient.swift:302-353](file://blindRun/Core/MockAPIClient.swift#L302-L353)
- [AppState.swift:207-228](file://blindRun/Core/AppState.swift#L207-L228)

## 结论

Mock API客户端功能增强项目成功实现了以下目标：

1. **完整的离线开发支持**：Mock客户端提供完整的API模拟功能
2. **灵活的环境配置**：支持多种运行环境的无缝切换
3. **健壮的状态管理**：完善的订单生命周期管理
4. **增强的资料管理**：支持完整的ProfileResponse对象更新
5. **可靠的测试支持**：通过UI测试环境变量提升测试稳定性
6. **优秀的用户体验**：符合视障用户需求的界面设计

**更新** 最重要的改进包括：
- 资料更新方法现在返回完整的ProfileResponse对象，确保数据一致性
- 全面的UI测试环境变量系统，显著提升测试可靠性
- 更好的状态管理和缓存机制，改善应用性能

该项目为后续的功能扩展奠定了坚实的基础，特别是在订单管理、用户认证、实时通信和资料管理方面的实现，为完整的业务流程提供了可靠的支撑。