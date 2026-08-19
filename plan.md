# AidRun 上线版执行计划

## 当前项目状态

AidRun 当前仓库是原生 iOS 客户端，采用 SwiftUI + MVVM，后端为仓库外云端服务 `http://47.114.113.171`，WebSocket 使用 `ws://47.114.113.171`，地图能力来自高德 iOS SDK。Mock 仍保留为离线 UI 和单元测试设施，但不能作为上线验收依据。

已经具备的上线基础：

- 手机号验证码登录、JWT 会话（Token 存 Keychain）、`/api/auth/me` 启动校验、服务端撤销登出、两阶段自助删除账户、角色选择与切换。
- 盲人预约、志愿者接单、出发、到达、开始服务、完成、取消等核心订单流程。**一键求助（SOS）本版交付，两端都仅限 `IN_PROGRESS`**：门槛为 `OrderModels.swift:128` `canBlindRunnerTriggerEmergency` / `:140` `canVolunteerTriggerEmergency` / `:144` `canTriggerEmergency(as:)`，触发走真实 `POST /api/emergency/trigger`，状态由 `blindRun/Safety/EmergencyCoordinator.swift` 承接。~~志愿者侧求助入口全状态隐藏~~ —— 后端 commit `a5ba523`（SOS-1，2026-07-31）把 `event.userId` 改为取订单的盲人方、用 `TriggerType.VOLUNTEER_BUTTON` 区分来源后已开放；志愿者**没有**撤销入口（后端恒 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`）。求助事件不是订单状态，不改变 `RunOrderStatus`。见 `openspec/changes/enable-independent-sos-safely/`（2026-07-31 已重启，双角色交付）。
- 盲人实名认证与 1–5 位紧急联系人管理，二者均为 `POST /api/orders` 的硬门槛（服务端 403 `IDENTITY_NOT_VERIFIED` / `EMERGENCY_CONTACT_REQUIRED`）。
- 志愿者两步注册（身份证 + 阿里云 CloudAuth 原生活体），培训/答题环节已彻底移除。
- 高德地图桥接、定位、POI 搜索、逆地理编码、地图 marker。
- WebSocket 服务、志愿者位置上报、订单状态轮询降级；`AppRealtimeCoordinator` 统一承接 App 生命周期内的实时事件与前台通知优先级队列。
- VoiceOver 标注、TTS 播报、语音输入入口。
- 云端后端 E2E 脚本 `scripts/cloud-e2e.mjs`、账户生命周期探针 `scripts/auth-account-lifecycle-probe.mjs`、派单就绪探针 `scripts/volunteer-dispatch-readiness-probe.mjs`。

## 上线阻塞项

以下事项必须在对真实用户发布前处理或由项目负责人书面接受风险：

- ~~Token 当前存储在 `UserDefaults`，需要迁移到 Keychain。~~ **已完成**：Token 现存于 Keychain（`blindRun/Core/KeychainTokenStore.swift`，`kSecClassGenericPassword` + `kSecAttrAccessibleAfterFirstUnlock`，写入前先删再写）。`blindRun/Core/AppState.swift:674-685` 的 `restoredToken()` 只在命中旧版本遗留值时做一次性迁移并清除 `UserDefaults` 旧键。覆盖见 `blindRunTests/KeychainTokenStoreTests.swift`。
- `AppStatePersistence` 已隔离正常 App、单元测试和 UI 测试的 UserDefaults 域；Keychain 已使用独立测试 service/access group。真机自动化需执行会话哈希保护、终止测试宿主并恢复 DemoRelease。
- **APNs 在当前签名配置下不可能工作**：全仓无任何 `.entitlements` 文件，`blindRun.xcodeproj/project.pbxproj` 里 `CODE_SIGN_ENTITLEMENTS` 出现 0 次，但 `blindRun/Info.plist:33-37` 已声明 `UIBackgroundModes = remote-notification`。`blindRun/Core/PushNotificationsManager.swift:76-78` 的注册失败分支只记一条诊断日志、静默吞掉，所以线上不会有任何可见报错。根因是免费个人开发者团队没有 Push Notifications capability，**需要付费开发者账号**才能配 entitlement 与 APNs 证书。在此之前推送兜底通道等于不存在，离线通知只能靠 WebSocket 重连补拉。
- **隐私政策 / 用户协议没有任何 UI 入口**：`blindRun/Core/Models/LegalLinksModels.swift`（模型 + 回退文案）、`blindRun/Core/MockAPIClient.swift:351`（mock）、`blindRunTests/LegalLinksTests.swift`（测试）三处齐备，但全仓 grep 只命中这 3 个文件——**没有任何 View / ViewModel 消费它**，真实 `blindRun/Core/APIClient.swift` 里 `legal` 零命中。App Store 审核指南 5.1.1 要求隐私政策在 App 内可访问，上架前必须补一个入口。
- 真实服务地址当前允许使用 HTTP 明文 IP；发布说明需如实记录。
- 固定验证码 `000000` 当前允许用于长期测试账号和上线验收。
- 志愿者身份证、人脸核验和管理员审核已按后端 OpenAPI 契约接入，仍需双真机走查。
- 真实高德地图、真实定位、真实后端、WebSocket 派单必须在真机 `111` 和 `iPad Pro (2)` 上完成验收。
- App Store 隐私说明、定位/语音权限说明、无障碍验收需要确认。紧急事件责任边界本版涉及盲人端 `IN_PROGRESS` 求助：发布说明可以说明 App 会记录求助并联系紧急联系人，但**不得声称短信已送达或联系人已被联系上**，也不得把 App 描述为救援服务；所有对外文案须与 `EmergencySafetyCopy`（`blindRun/Safety/SafetyModule.swift`）一致并保留「若情况危急请立即拨打110」。
- 盲人实名 / 紧急联系人链路仍缺两项验收：云端探针 `scripts/blind-identity-and-contacts-probe.mjs` 尚未入库，以及引导落点 / 实名三态 / 联系人全动作的 UI 无障碍测试（`blindRunUITests` 目前零处引用 `blindOnboarding.*` 标识）。见 `openspec/changes/complete-blind-profile-and-contacts/tasks.md` 6.2 / 6.3。
- 实时同行位置与完成轨迹必须完成 GCJ-02 单次转换、后台定位披露、电量测量、告警去重和锁屏双真机验收；后端已确认现有历史坐标均来自高德/腾讯定位链路，可按 GCJ-02 使用。

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
# 全量校验（当前 13 项：3 个活跃 change + 10 个已归档 specs），推荐日常用这条
openspec validate --all --strict --no-interactive
# 单个活跃 change（2026-07-31 起活跃的只有这三个）
openspec validate complete-blind-profile-and-contacts --strict --no-interactive
openspec validate enable-live-escort-location-and-track-summary --strict --no-interactive
openspec validate enable-independent-sos-safely --strict --no-interactive
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
3. ~~Token Keychain 迁移。~~ **已完成**，见「上线阻塞项」首条。
4. 补隐私政策 / 用户协议的 App 内入口（App Store 5.1.1 硬要求），消费已有的 `LegalLinksModels`。
5. 付费开发者账号 + `.entitlements` + APNs 证书，让推送兜底通道真正可用。
6. HTTPS 域名与 ATS 策略收敛。
7. 志愿者认证、管理员审核、真实短信能力持续联调与异常处理完善；管理员审核页后续作为独立 Web 管理端实现。
8. 积分商城、支付、聊天、App 内路线规划、公共实时轨迹分享、复杂风险控制等扩展能力；已批准的订单双方实时同行位置和完成后盲人轨迹总结按 `enable-live-escort-location-and-track-summary` 实施。
9. 求助（SOS）能力：`enable-independent-sos-safely` 已于 2026-07-31 重启并交付盲人端 `IN_PROGRESS` 入口；剩余工作是志愿者端（等后端按订单参与方而非触发人路由升级）和无 GPS 降级提交（等产品/安全批准后翻 `EmergencyCoordinator.allowsSubmissionWithoutLocation`）。

## 人工确认项

- 是否已有高德生产 key、Bundle ID 白名单和隐私合规材料。
- **待后端确认（自 `remove-volunteer-registration-training/design.md:53` 转记，该 change 已于 2026-07-31 归档为 `openspec/changes/archive/2026-07-31-remove-volunteer-registration-training/`）**：外部后端把「活体通过 → `STEP_4_COMPLETED` + `canAcceptOrders = true`」原子写入的**部署时间**，以及遗留账号（`STEP_4_TRAINING`）能否通过真实派单接口开启服务。iOS 侧已按兼容归一化实现（`ProfileModels.swift:277`、`VolunteerRegistrationModels.swift:80`、`VolunteerRegistrationFlowView.swift:657,690` 把 `STEP_4_TRAINING` 视为注册完成且保持 availability 关闭——这是提案明文要求保留的兼容逻辑，**不是残留待清理代码**），但该确认项未闭合前无法签署真实派单结论。原因记录：2026-07-18 实测账号 `13360846885` 走 `send-code` 后用 `000000` 仍返回 `INVALID_VERIFICATION_CODE`，读不到该账号的权威派单字段。
- **待后端确认（`complete-blind-profile-and-contacts/tasks.md` 1.2 未闭合项）**：主联系人切换的原子性，以及新增联系人触发短信后是否需要在 iOS 展示投递状态。
- **待后端确认（`enable-independent-sos-safely/design.md` 的 `需要人工确认` 项）**：`EMERGENCY_CONTACT_NOTIFIED` 到底代表短信被服务商受理、已投递到手机还是仅入队，仍未答复。这一项不再阻塞发版：后端在触发事务内同步推送该通知（`service/EmergencyService.java:370-373`），短信在 `@TransactionalEventListener(AFTER_COMMIT)` + `@Async` 之后才发（`service/EmergencyContactNotifier.java:60-62`），失败只广播给客服（`:126-135`）且不会回纠给盲人，因此 iOS 一律用自己的进行时文案替换后端完成时文案，永不宣称短信已送达。后端答复后可评估是否新增更强的确认态。
- 管理员审核页后续做成独立 Web 管理端；当前 iOS 用户端仅保留脚本级审核联调，不增加管理员入口。
- 云端已确认志愿者接受派单后按正式流转推进：`PENDING_MATCH -> PENDING_ACCEPT -> DRIVER_EN_ROUTE -> DRIVER_ARRIVED -> IN_PROGRESS`，其中 `DRIVER_ARRIVED -> IN_PROGRESS` 由志愿者端调用 `POST /api/orders/{id}/start-service` 触发；iOS 真机验收需确认接单后不会直接进入 `IN_PROGRESS`。
- 云端已确认不会因已接单订单尚未立即开始服务而自动进入 `REMATCHING`；若盲人端看到 `REMATCHING`，优先排查是否志愿者接单后主动取消。
- 云端已确认 `POST /api/orders/{id}/cancel` 接受 `REMATCHING` 状态；iOS 必须使用盲人 token 调用该接口，志愿者 token 不应成功。
- 志愿者端负责在 `DRIVER_ARRIVED` 后调用 `POST /api/orders/{id}/start-service` 将订单推进到 `IN_PROGRESS`；iOS 不会从 `DRIVER_ARRIVED` 直接调用完成服务。若真机验证卡在 `DRIVER_ARRIVED`，优先检查志愿者端 start-service 请求和后端状态推进日志。
- 百度地图 `baidumap://map/direction` 跳转已按 GCJ-02 步行参数接入，发布前需在安装百度地图的真机上 smoke 验证。
- 当前 release **两端**都在 `IN_PROGRESS` 显示求助入口，二次确认后调用 `POST /api/emergency/trigger`（`EmergencyTriggerRequest(orderId, gpsLat, gpsLng)`，三个字段一律上送）。严格 GPS 门槛：拿不到新鲜的真实 GCJ-02 样本就**不发请求**，界面与 TTS 明确说"求助未发出"并指向设置/重试和 110；Mock/Demo 坐标永不上送。无 GPS 降级提交由常量 `EmergencyCoordinator.allowsSubmissionWithoutLocation`（当前 `false`）单点控制，翻开需产品/安全书面批准。~~志愿者端求助入口全状态隐藏，等后端按订单参与方路由后再开~~ —— 后端已按订单参与方路由（`a5ba523`），志愿者端入口同样在 `IN_PROGRESS` 开放，形态是地图右上角的悬浮盾牌（远离拇指区：误触在这一侧撤不回来）。
- 后端所有当前坐标约定为 GCJ-02。数据库虽无来源字段或迁移机制，但后端确认现有写入路径仅来自高德/腾讯定位链路，历史数据按干净 GCJ-02 处理；未来新增 WGS-84 来源须在写入边界转换。
- 后端 100 米/连续 2 次仅为运行时告警工程参数，未获产品批准为完成轨迹异常结论；iOS 只展示服务端即时告警，不比较双方轨迹得出异常。
- 轨迹接口保留 0/1/多个原始点；iOS 少于 2 点不绘制，角色统计固定为 `0 / 0 / null`。非 403/404 响应保证包含 `status`。

## 实时同行位置与完成轨迹发布门槛

- 两角色 WebSocket 每 30 秒 PING；服务端 90 秒无消息以 `SESSION_NOT_RELIABLE` 关闭，客户端沿用 3/6/12/30 秒重连。
- WebSocket 以递增 generation 隔离旧连接回调且一代只调度一次重连；志愿者重连立即补报真实位置并刷新派单摘要。派单链路只保留不含 token/坐标/联系人/地址/正文的内存诊断，且不以 `/api/orders/available` 代替定向 `NEW_ORDER`。
- 订单双方在 `DRIVER_EN_ROUTE`、`DRIVER_ARRIVED`、`IN_PROGRESS` 每 5 秒上报真实 GCJ-02 位置；仅 `IN_PROGRESS` 开启锁屏/后台定位。
- 同行 marker 超过 15 秒未刷新即隐藏；同行会话在定位权限有效且 Core Location 未报告失败时按五秒 cadence 复用最近一次真实设备样本，静止不视为定位失效。权限撤销或明确定位失败时停止上传并显示/TTS 降级。
- `ESCORT_DISTANCE_ALERT` 与 `ESCORT_SIGNAL_LOST` 使用 `messageId` 去重，不改变订单或 SOS 状态。
- 所有模板 `APP_NOTIFICATION` 均在最外层下发模板 `eventType`；iOS 通过 `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST` 分流，`body`/`ttsText` 不参与识别。当前仍无 `orderId`，所以告警要求唯一关联 `IN_PROGRESS` 订单。
- `COMPLETED` 后双方可查看以盲人轨迹为主的“本次路线”与里程/时长/配速；空数据必须结合响应 `status` 如实说明。
## 账户生命周期加固（harden-auth-account-lifecycle）

- 启动会话以 `/api/auth/me` 校验结果为准，角色有效后才连接 WebSocket。
- 所有退出入口改用服务端撤销；失败保留会话并提供带风险说明的本机退出。
- 两角色设置页增加两阶段自助删除，活动订单由客户端预检、服务端裁决。
- 统一处理 429 权威倒计时并完成 Mock、单元/UI、云端探针和双真机验证。
