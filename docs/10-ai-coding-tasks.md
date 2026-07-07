# AidRun AI Coding Tasks

本文档只拆分原生 iOS 前端任务。服务端位于本仓库之外，AI 不得在本仓库实现、构建或部署服务端。

## 1. iOS Core Tasks

### PR-IOS-01 Core App Shell

- 维护 Core、Auth、Role、BlindRunner、Volunteer、Orders、Map、Voice、Safety、Profile 模块。
- 使用 `AppState` 集中管理 token、用户、角色和前端环境。
- 使用统一 `APIClient` 协议提供 Mock 与 URLSession 实现。
- Debug 支持 Mock / Demo Cloud；Demo 和 Production 构建固定 Demo Cloud。

Acceptance:

- Mock 不需要网络且不会创建网络请求。
- 所有真实 HTTP 请求固定使用 `http://47.114.113.171`。
- 所有真实 WebSocket 连接固定使用 `ws://47.114.113.171`。

### PR-IOS-02 Auth and Role

- 实现手机号验证码登录；预置测试账号固定验证码 `000000`。
- 当前将 JWT 存入 UserDefaults，并保留迁移 Keychain 的注释；上线硬化优先迁移 Keychain。
- 实现角色选择、角色切换和退出登录二次确认。
- 显示外部 API 返回的稳定业务错误。

Acceptance:

- 登录会话可恢复。
- 活跃订单角色切换错误可正确展示和播报。

### PR-IOS-03 Blind Runner Flow

- 实现盲人资料与紧急联系人、预约、订单状态、取消和评分流程；当前 release 隐藏求助入口，后续安全专项再启用。
- 盲人首页和创建预约为语音优先流程：状态/主操作/重复当前状态先于辅助地图；创建预约按出发地点、预约时间、选填需求、确认提交分步引导。
- 盲人订单状态按 PENDING_MATCH / PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED、IN_PROGRESS、COMPLETED、终态分别路由到等待、服务中、完成/评分或结束视图。
- WebSocket 断开时每 5 秒轮询订单状态。
- 为关键页面提供 VoiceOver、TTS 和“重复当前状态”。

Acceptance:

- 从预约到服务完成和可选评价的前端流程可演示。
- 定位拒绝时阻止预约并提示前往设置。
- 真机验收需覆盖 VoiceOver 顺序、重复当前状态文案、真实高德地图辅助区域仍可渲染，以及 `111` / `iPad Pro (2)` 双设备流程。

### PR-IOS-04 Volunteer Flow

- 实现志愿者资料、身份证上传、人脸核验、管理员审核状态、可服务开关、系统派单工作台、30 秒派单弹窗和服务操作。
- iOS 使用真实定位计算距离并排序。
- 接单前隐藏敏感信息，接单后显示完整联系电话。

Acceptance:

- 不可服务、未认证、管理员未通过或无定位权限时不能接单。
- `DRIVER_ARRIVED` 必须显示志愿者端"开始服务"动作并调用 `/api/orders/{id}/start-service`；结束服务必须二次确认，并且只能在 `IN_PROGRESS` 调用 `/api/orders/{id}/finish`。

### PR-IOS-05 Map, Voice and Accessibility

- 从本地忽略配置读取 AMap key。
- 展示地图、当前位置和订单标记；志愿者前往出发地点可跳转外部地图 App 步行导航，不实现 App 内路线规划或实时轨迹。
- 使用 `AVSpeechSynthesizer`、Speech framework 和 VoiceOver 标注。

Acceptance:

- 模拟器与真机可使用模拟坐标或真实定位。
- 语音识别失败时允许键盘输入。

## 2. Cloud Integration Tasks

### PR-CLOUD-01 Contract Integration

- 以 `docs/07-api-contract.openapi.yaml` 实现请求和 DTO。
- 以 `docs/websocket-protocol.md` 实现实时消息。
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

## 3. Roadmap Capabilities

Android、完整管理员端、真实短信、真实身份审核、实时轨迹共享、自动电话/短信、AI 助手、自然语言时间解析、App 内路线导航、完整积分商城、支付、库存、App 内聊天、复杂风控、摔倒检测、电子围栏、即时呼叫或多人活动报名不再是硬性禁止项。接入前必须补充产品规则、后端/API 契约、隐私/安全说明和验收测试。志愿者端本期仅允许跳转已安装的外部地图 App 做步行导航。
