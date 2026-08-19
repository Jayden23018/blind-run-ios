# AidRun AI Coding Tasks

本文档只拆分原生 iOS 前端任务。服务端位于本仓库之外，AI 不得在本仓库实现、构建或部署服务端。

## 1. iOS Core Tasks

### PR-IOS-01 Core App Shell

- 维护 Core、Auth、Role、BlindRunner、Volunteer、Orders、Map、Voice、Safety、Profile 模块。
- 使用 `AppState` 集中管理 token、用户、角色和前端环境。
- 使用统一 `APIClient` 协议提供 Mock 与 URLSession 实现。
- Debug 支持 Mock / Demo Cloud；Demo 和 Production 构建固定 Demo Cloud。
- 根路由使用唯一 `RootRoute` 和可取消账号恢复任务；资料读取完成后一次性提交目标页面，任意时刻只挂载一个登录/资料/首页根页面，AMap 不得跨根路由残留。

Acceptance:

- Mock 不需要网络且不会创建网络请求。
- 所有真实 HTTP 请求固定使用 `http://47.114.113.171`。
- 所有真实 WebSocket 连接固定使用 `ws://47.114.113.171`。

### PR-IOS-02 Auth and Role

- 实现手机号验证码登录；预置测试账号固定验证码 `000000`。
- JWT 存入 Keychain（`KeychainTokenStore`，走可注入的 `TokenStoring` 门面）；不要再往 `UserDefaults` 写 token，旧 token 只保留一次性迁移读取。
- 其余 AppState 字段仍走可注入的 `AppStatePersistence`：所有 AppState 测试必须注入隔离持久化域；UI 测试每次启动清空 UI-test 域与 UI-test Keychain service，不得读写正常 App 的 token、userId、角色或环境。真机测试脚本前后只比较这些字段的脱敏哈希，并在结束后终止测试宿主、恢复 DemoRelease。
- 实现角色选择、角色切换和退出登录二次确认。
- 显示外部 API 返回的稳定业务错误。

Acceptance:

- 登录会话可恢复。
- 活跃订单角色切换错误可正确展示和播报。

### PR-IOS-03 Blind Runner Flow

- 实现盲人资料、紧急联系人管理（1～5 个，恰好 1 个主联系人）、预约、订单状态、取消和评分流程；一键求助只在 `IN_PROGRESS` 开放，~~志愿者端全状态隐藏~~ —— 自后端 `a5ba523`（SOS-1，2026-07-31）按订单参与方归属事件起，志愿者端同样在 `IN_PROGRESS` 开放（形态见 `docs/05-page-specs.md` 页面 13）。
- 一键求助：二次确认文案逐字固定，取消不发送任何请求；无新鲜真实 GCJ-02 样本不发请求并如实播报「求助未发出」；提交 `POST /api/emergency/trigger`（`orderId` + `gpsLat` + `gpsLng` 三个字段一律上送）；求助不改变 `RunOrderStatus`；文案不得声称短信已送达或联系人已被联系上。
- 下单硬前置条件为「实名认证已通过」+「至少 1 个紧急联系人且恰好 1 个主联系人」，与后端 `OrderCreationService` 的校验一致（403 `IDENTITY_NOT_VERIFIED` / 403 `EMERGENCY_CONTACT_REQUIRED`）；缺失时阻断 `POST /api/orders` 并播报第一个可执行的缺失项。
- 实名认证（`verifyStatus`：`NOT_VERIFIED` / `VERIFIED` / `FAILED`，无审核中态）自 2026-07-30 起是**下单硬门槛**（`demo/docs/handoff.md` Q1 按方案 ① 答复），客户端门槛必须与后端同序：实名在紧急联系人**之前**。
- 盲人首页和创建预约为语音优先流程：状态/主操作/重复当前状态先于辅助地图；创建预约按出发地点、预约时间、选填需求、确认提交分步引导。
- DemoRelease/Release 的盲人首页默认使用不可交互位置占位，不创建 `MAMapView`；权威活跃订单尚未确认时禁止进入新建预约，但保留设置、记录、状态播报和重试。
- 盲人订单状态按 PENDING_MATCH / PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED、IN_PROGRESS、COMPLETED、终态分别路由到等待、服务中、完成/评分或结束视图。
- WebSocket 断开时每 5 秒轮询订单状态。
- 为关键页面提供 VoiceOver、TTS 和“重复当前状态”。

Acceptance:

- 从预约到服务完成和可选评价的前端流程可演示。
- 无紧急联系人或主联系人不唯一时阻止预约，并提供跳转紧急联系人管理页的引导。
- 紧急联系人管理覆盖 1～5 上限、最后 1 个不可删除、设为主联系人后主联系人唯一。
- 实名认证三态可展示；非 `VERIFIED`（含字段缺失）时阻止预约，并给出能走通的实名入口，且在紧急联系人也缺失时只播报实名这一档。
- 定位拒绝时阻止预约并提示前往设置。
- 真机验收需覆盖 VoiceOver 顺序、重复当前状态文案、首页位置占位不拦截触摸、订单详情/服务页高德地图仍可渲染，以及 `111` / `iPad Pro (2)` 双设备流程。

### PR-IOS-04 Volunteer Flow

- 实现志愿者资料、身份证二要素核验、CloudAuth 动作活体认证、可选资质证书状态、可服务开关、系统派单工作台、30 秒派单弹窗和服务操作。
- iOS 使用真实定位计算距离并排序。
- 接单前隐藏敏感信息，接单后显示完整联系电话。
- 派单摘要进入首页立即独立请求，不等待资料、注册状态或定位传播；刷新使用唯一 request ID、可取消 request group 和 20 秒可见超时，旧摘要存在时保持可操作。
- DemoRelease/Release 的志愿者首页默认使用不可交互位置占位，不创建 `MAMapView`；资料和注册状态使用独立辅助任务，绝不延长派单摘要主转圈。
- 所有志愿者订单状态 POST 及其权威详情刷新使用 12 秒应用层截止；超时取消请求、释放操作按钮、提示结果未确认并交由 WebSocket/轮询恢复，禁止永久转圈或乐观伪造状态。

Acceptance:

- 不可服务、未认证、管理员未通过或无定位权限时不能接单。
- `DRIVER_ARRIVED` 必须显示志愿者端"开始服务"动作并调用 `/api/orders/{id}/start-service`；结束服务必须二次确认，并且只能在 `IN_PROGRESS` 调用 `/api/orders/{id}/finish`。

### PR-IOS-05 Map, Voice and Accessibility

- 从本地忽略配置读取 AMap key。
- 订单详情、服务中和完成轨迹页展示地图、当前位置和订单标记；首页为冻结恢复默认使用文字位置占位。志愿者前往出发地点可跳转外部地图 App 步行导航，不实现 App 内路线规划或公共实时轨迹分享。专项变更允许订单双方同行 marker 与完成后盲人轨迹总结。
- 使用 `AVSpeechSynthesizer`、Speech framework 和 VoiceOver 标注。

Acceptance:

- 模拟器与真机可使用模拟坐标或真实定位。
- 语音识别失败时允许键盘输入。

## 2. Cloud Integration Tasks

### PR-CLOUD-01 Contract Integration

- 以后端仓库的 `docs/api_spec.yaml` 实现请求和 DTO。
- 以后端仓库的 `docs/websocket-protocol.md` 实现实时消息。
- 对 WebSocket 断线保留 REST 轮询降级。

Acceptance:

- 仓库内不存在第二个真实服务器地址。
- URLSession 与 WebSocket 均连接 `47.114.113.171`。

### PR-CLOUD-02 Production Verification

- 准备双设备演示账号和脚本。
- 运行真机 `111` 和 `iPad Pro (2)` XCTest、真实高德 smoke、真实云端 UI smoke、OpenSpec validation 和文档检查。
- 外部服务可用时运行 `scripts/cloud-e2e.mjs`。

Acceptance:

- `openspec validate remove-local-backend-use-cloud-only --strict --no-interactive` 通过。
- `AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/production-readiness-check.sh` 结果被记录。
- 本地真机测试结果与外部服务可用性分别报告。
- 盲人/志愿者首页刷新必须具备单次 generation、取消清理和 20 秒可见超时；超时结束遮罩并提供可访问的重试入口。
- 登录恢复、派单摘要和订单恢复诊断只能包含匿名 request ID、归一化 endpoint、HTTP 状态、耗时和失败阶段；不得记录 token、手机号、姓名、坐标或响应正文。

## 3. Roadmap Capabilities

Android、完整管理员端、真实短信、真实身份审核、公共实时轨迹分享、自动电话/短信、AI 助手、自然语言时间解析、App 内路线导航、完整积分商城、支付、库存、App 内聊天、复杂风控、摔倒检测、电子围栏、即时呼叫或多人活动报名不再是硬性禁止项。接入前必须补充产品规则、后端/API 契约、隐私/安全说明和验收测试。志愿者端本期仅允许跳转已安装的外部地图 App 做步行导航。
## 账户生命周期执行约束

实施 `harden-auth-account-lifecycle` 时按 OpenSpec 任务顺序完成：先锁定云端契约，再实现模型/网络、会话恢复、统一注销、账户删除、限流体验和测试。不得加入后端代码；云端黑名单、所有 Token 失效、软删除和手机号复用仅通过 iOS/脚本验证。

## 实时协调执行约束

实施 `complete-realtime-fallback-and-notifications` 时，raw WebSocket 订阅只能存在于 `AppRealtimeCoordinator`；订单详情继续由 ViewModel 通过 REST/五秒轮询维护。不得在该变更内加入 peer marker、轨迹、分离判定或 SOS 动作（SOS 由 `enable-independent-sos-safely` 交付）。验证必须覆盖 service 替换、刷新合并、导航期间派单、通知优先级/去重/无障碍、双向位置校验、重连恢复和双真机。

## 实时同行与完成轨迹执行约束

实施 `enable-live-escort-location-and-track-summary` 时先更新契约，再依次完成坐标来源/单次转换、串行发送与双角色心跳、app-lifetime 会话、后台定位、双向 marker、安全告警、轨迹模型/AMap polyline/完成摘要和测试。不得上传 Demo 坐标、持久化/打印同行原始坐标、显示志愿者默认路线或计算未获批异常结论；SOS UI 不属于本变更范围，由 `enable-independent-sos-safely` 交付。
