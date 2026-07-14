# AidRun 上线版执行计划

## 当前项目状态

AidRun 当前仓库是原生 iOS 客户端，采用 SwiftUI + MVVM，后端为仓库外云端服务 `http://47.114.113.171`，WebSocket 使用 `ws://47.114.113.171`，地图能力来自高德 iOS SDK。Mock 仍保留为离线 UI 和单元测试设施，但不能作为上线验收依据。

已经具备的上线基础：

- 手机号验证码登录、JWT 会话、角色选择与切换。
- 盲人预约、志愿者接单、出发、到达、完成、取消、紧急事件等核心订单流程。
- 高德地图桥接、定位、POI 搜索、逆地理编码、地图 marker。
- WebSocket 服务、志愿者位置上报、订单状态轮询降级。
- VoiceOver 标注、TTS 播报、语音输入入口。
- 云端后端 E2E 脚本 `scripts/cloud-e2e.mjs`。

## 上线阻塞项

以下事项必须在对真实用户发布前处理或由项目负责人书面接受风险：

- Token 当前存储在 `UserDefaults`，需要迁移到 Keychain。
- 真实服务地址当前允许使用 HTTP 明文 IP；发布说明需如实记录。
- 固定验证码 `000000` 当前允许用于长期测试账号和上线验收。
- 志愿者身份证、人脸核验和管理员审核已按后端 OpenAPI 契约接入，仍需双真机走查。
- 真实高德地图、真实定位、真实后端、WebSocket 派单必须在真机 `111` 和 `iPad Pro (2)` 上完成验收。
- App Store 隐私说明、定位/语音权限说明、无障碍验收和紧急事件责任边界需要确认。

## 真实联调测试

上线验收必须覆盖三类测试：

- **基础真机回归**：在设备 `111` 和 `iPad Pro (2)` 上运行完整 XCTest，验证 Mock 单元/界面流程仍稳定。
- **真实高德 smoke**：不设置 `AIDRUN_UI_TEST_DISABLE_MAP`，确认高德地图容器渲染且不会回退到 API Key 缺失占位。
- **真实后端 smoke/E2E**：使用 Demo Cloud 构建登录真实账号、创建并取消订单；使用 `scripts/cloud-e2e.mjs` 覆盖登录、资料、WebSocket、位置、派单、接单、状态流转、紧急事件。

推荐一键命令：

```bash
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/production-readiness-check.sh
scripts/dual-device-validation.sh
```

单项命令：

```bash
node scripts/validate-docs.mjs
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111'
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=iPad Pro (2)'
AIDRUN_UI_TEST_REAL_AMAP=1 xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111' -only-testing:blindRunUITests/blindRunUITests/testRealAMapEnabledSmoke
AIDRUN_UI_TEST_RUN_CLOUD_SMOKE=1 xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun-Demo -destination 'platform=iOS,name=111' -only-testing:blindRunUITests/blindRunUITests/testCloudBackendBlindRunnerBookingSmoke
node scripts/cloud-e2e.mjs
```

## 功能完善路线

优先级按上线风险排序：

1. 真实后端联调失败项修复：接口字段、错误码、WebSocket 消息、订单状态流转。
2. 高德地图真机渲染与定位权限异常处理。
3. Token Keychain 迁移。
4. HTTPS 域名与 ATS 策略收敛。
5. 志愿者认证、管理员审核、真实短信能力持续联调与异常处理完善；管理员审核页后续作为独立 Web 管理端实现。
6. 积分商城、支付、聊天、App 内路线规划、实时轨迹、风险控制等扩展能力；志愿者前往出发地点阶段已允许跳转外部地图 App 做步行导航。

## 人工确认项

- 是否已有高德生产 key、Bundle ID 白名单和隐私合规材料。
- 管理员审核页后续做成独立 Web 管理端；当前 iOS 用户端仅保留脚本级审核联调，不增加管理员入口。
- 云端已确认志愿者接受派单后按正式流转推进：`PENDING_MATCH -> PENDING_ACCEPT -> DRIVER_EN_ROUTE -> DRIVER_ARRIVED -> IN_PROGRESS`，其中 `DRIVER_ARRIVED -> IN_PROGRESS` 由志愿者端调用 `POST /api/orders/{id}/start-service` 触发；iOS 真机验收需确认接单后不会直接进入 `IN_PROGRESS`。
- 云端已确认不会因已接单订单尚未立即开始服务而自动进入 `REMATCHING`；若盲人端看到 `REMATCHING`，优先排查是否志愿者接单后主动取消。
- 云端已确认 `POST /api/orders/{id}/cancel` 接受 `REMATCHING` 状态；iOS 必须使用盲人 token 调用该接口，志愿者 token 不应成功。
- 志愿者端负责在 `DRIVER_ARRIVED` 后调用 `POST /api/orders/{id}/start-service` 将订单推进到 `IN_PROGRESS`；iOS 不会从 `DRIVER_ARRIVED` 直接调用完成服务。若真机验证卡在 `DRIVER_ARRIVED`，优先检查志愿者端 start-service 请求和后端状态推进日志。
- 百度地图 `baidumap://map/direction` 跳转已按 GCJ-02 步行参数接入，发布前需在安装百度地图的真机上 smoke 验证。
- 当前 release 隐藏求助入口，不宣称真实求助能力；`POST /api/emergency/trigger` 仅作为后端合同探针保留。若发布前恢复真实 emergency event UI，需要单独安全变更确认接口、GPS、通知、失败提示、合规文案和验收测试。
## 账户生命周期加固（harden-auth-account-lifecycle）

- 启动会话以 `/api/auth/me` 校验结果为准，角色有效后才连接 WebSocket。
- 所有退出入口改用服务端撤销；失败保留会话并提供带风险说明的本机退出。
- 两角色设置页增加两阶段自助删除，活动订单由客户端预检、服务端裁决。
- 统一处理 429 权威倒计时并完成 Mock、单元/UI、云端探针和双真机验证。
