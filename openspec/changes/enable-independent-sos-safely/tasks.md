> **交付范围**：盲人侧 `IN_PROGRESS` SOS 已交付；志愿者侧入口继续隐藏（后端按触发者而非订单参与方路由事件，
> 见 `proposal.md` 顶部）。凡与志愿者触发相关的子项均标注为「后端阻塞」并说明阻塞点，不空勾。

## 1. Safety Preconditions And Contract Confirmation

- [x] 1.1 依赖已就绪：`complete-realtime-fallback-and-notifications`（`AppRealtimeCoordinator.swift`）与 `enable-live-escort-location-and-track-summary`（`LiveEscortSessionCoordinator.swift`、`Map/CoordinateSystem.swift` 的单点 GCJ-02 边界）均已合入并被本变更直接复用。
- [x] 1.2 GPS 门槛与文案：严格门槛落为 `EmergencyCoordinator.allowsSubmissionWithoutLocation = false`（`blindRun/Safety/EmergencyCoordinator.swift`），降级路径存在但需产品/安全拍板，翻转一个常量即可；pending/failure/retry/resolved 文案集中在 `EmergencySafetyCopy`（`blindRun/Safety/SafetyModule.swift`）。**产品/安全的书面批准仍未收到**，已再次投递 `demo/docs/handoff.md`。
- [x] 1.3 契约已按后端**实现**对齐（不是按文档）：成功体 `{success,eventId,status}`（`EmergencyController.java:34-38`）→ `EmergencyTriggerResponse`；`EmergencyStatus` 全集（`entity/EmergencyStatus.java`）→ `EmergencyEventStatus`；冷却 429 `TOO_MANY_REQUESTS` + `retryAfterSeconds`（`GlobalExceptionHandler.java:218-231`）→ `APIError.rateLimited`；非参与方 403 `NOT_ORDER_PARTICIPANT`、订单不存在 400 `BAD_REQUEST`。三项无法由代码回答的（志愿者路由、恢复端点、法务文案口径）已在 handoff 标为待答。
- [x] 1.4 志愿者入口保持关闭：`RunOrderStatus.canVolunteerTriggerEmergency` 恒 `false`（`OrderModels.swift`），由 `testVolunteerEmergencyStaysHiddenInEveryStatus` 锁定。

## 2. Canonical Documentation And Contracts

- [x] 2.1 `AGENTS.md` 第 3/6/10 节：隐藏规则替换为盲人 `IN_PROGRESS` 专属流程，二次确认原文逐字保留，新增「绝不宣称短信已送达」硬约束与触发端点的完整错误码。
- [x] 2.2 `plan.md` 与 `docs/01`–`docs/10` 已同步资格、GPS、事件/短信状态、失败行为、责任边界与发布风险。
- [ ] 2.3 `docs/07-api-contract.openapi.yaml` —— **不适用**。API 契约自 2026-07-28 起唯一来源是后端仓库 `demo/docs/api_spec.yaml`（`AGENTS.md` 第 7 节），本仓库不再维护该文件。已改为向后端投递：`api_spec.yaml:1024-1030` 目前只写 `type: object`，缺成功/错误/冷却 schema 与 `EmergencyStatus` 枚举。
- [ ] 2.4 `docs/websocket-protocol.md` —— **同上，属后端仓库**。已投递一条**契约与实现不一致**：文档 `:222-234` 写 `EMERGENCY_CONTACT_NOTIFIED` 是顶层类型且带 `eventId`，实现走 `buildEnvelope("APP_NOTIFICATION")` 且无 `eventId`/`orderId`。

## 3. Models And Mock Safety State

- [x] 3.1 `EmergencyTriggerResponse`、`EmergencyEventStatus`（含 `unknown` 兜底与 `isTerminal`）落在 `blindRun/Core/Models/OrderModels.swift`；`ActiveEmergencyEvent`、`EmergencySOSState` 落在 `blindRun/Safety/EmergencyCoordinator.swift`。冷却复用既有 `RateLimitInfo`，未新增错误码——`NOT_ORDER_PARTICIPANT` / `TOO_MANY_REQUESTS` / `BAD_REQUEST` 在 `ErrorModels.swift` 已存在且 rawValue 与后端 `ErrorCode.java` 一致。
- [x] 3.2 复用 `LocatedCoordinate` + `CoordinateSystem`：`EmergencyCoordinator.trigger` 只接受 `.gcj02Backend`，`.wgs84Device` 一律按「无定位」处理（`testUnconvertedDeviceCoordinateIsTreatedAsNoLocation`）。取样走 `LocationService.latestBackendSample()`，Demo/UI-test 定位路径不产生设备样本，兜底坐标无法进入云端请求。
- [x] 3.3 `MockAPIClient.handleEmergencyTrigger` 按 `EmergencyService.handleEmergencyTriggered` 复刻：有志愿者 → `VOLUNTEER_NOTIFIED`，无 → `CONTACT_NOTIFIED`；非 `IN_PROGRESS` → `NOT_ORDER_PARTICIPANT`；订单不存在 → `BAD_REQUEST`；订单状态不变。
- [ ] 3.3a Mock 的联系人通知 / 解除 / 恢复回放 —— **未做**。恢复通道后端不存在（见 4.6），Mock 里造一条会让离线测试通过而真机没有，属于制造假信心。

## 4. Emergency Coordination

- [x] 4.1 `EmergencyCoordinator`（`blindRun/Safety/EmergencyCoordinator.swift`）由 `AppState` 持有，`observe(realtimeCoordinator)` 订阅 `$latestSafetyEvent`；不持有也不修改 `RunOrderStatus`。
- [x] 4.2 发送前重新校验：`trigger` 内 `order.status.canTriggerEmergency(as: role)` 用的是 REST 权威订单状态，WS/界面陈旧状态无法放宽（`testTriggerIsRejectedOutsideInProgress`）。
- [x] 4.3 定位取自 `LocationService.latestBackendSample()`，取不到则 `requestOneTimeLocation()` + 有界等待 `EmergencyCoordinator.locationWaitTimeout`（5s）；仍取不到则不发请求并明确播报（`BlindOrderStatusViewModel.freshEmergencyCoordinate`）。
- [x] 4.4 只有 `success == true` 的结构化响应进入已受理态；解码失败、网络失败、后端拒绝、429 冷却各自停在可见可听的「未发出」态；`state.isBusy` 拦重复提交（`testConcurrentTapsSendOnlyOneRequest`）。
- [x] 4.5 事件按订单归属过滤（`EmergencyCoordinator.apply`）：带 `orderId` 且不匹配 → 丢弃；无活跃事件 → 丢弃。**按 `eventId` 匹配做不到**，后端该消息不带 `eventId`（`NotificationService:93-99`），代码注释已写明这一降级为何可接受（文案本身不承诺送达）。
- [x] 4.6 不持久化任何事件元数据（后端无恢复端点/重放），`reset()` 挂在 `accessToken` / `userId` / `activeRole` 三个 `didSet` 上，覆盖登出、注销、过期、换号、切角色（`AppState.swift`）。

## 5. Blind-Runner IN_PROGRESS Experience

- [x] 5.1 盲人服务页在且仅在 `IN_PROGRESS` 展示 `EmergencyActionButton`（`BlindOrderStatusView.swift` `actionSection`），复用 `PrimaryButton` 的 `minHeight: 64`。志愿者侧的三处入口与配套 `emergency()` 桩已删除（`VolunteerOrderFlowViews.swift`），不留 `if false` 死代码。
- [x] 5.2 复用既有 `emergencyConfirmationAlert`，文案与 `AGENTS.md` 第 10 节逐字一致（`testConfirmationCopyMatchesTheMandatedTextExactly`）；取消不发请求；提交中禁止重复确认。
- [x] 5.3 locating / submitting / unsent / failure / cooldown / contact-notified / resolved 七态均有可见文案（`EmergencyStatusNotice`）与 TTS（`enterEmergency` 分支走 `speak` 或 `speakError`），文案集中在 `EmergencySafetyCopy`。
- [x] 5.4 「联系人已收到短信」**永不展示**——不是「等匹配后再展示」。后端该事件先于短信发出且失败不回告（`EmergencyService.java:370-373` vs `EmergencyContactNotifier.java:60-62,126-135`），任何时刻都不成立。`AppRealtimeCoordinator.emergencyCopy` 用本地进行时文案覆盖后端 body/ttsText，由 `testNoEmergencyCopyClaimsAnSMSWasDelivered` 等三条测试锁定。
- [x] 5.5 `repeatStatus()` 先播权威订单状态，再追加 `emergencyCoordinator.repeatStatusSuffix`，不替换、不改变结束/取消权限。

## 6. Tests And Validation

- [x] 6.1 `blindRunTests/EmergencySOSTests.swift`：角色/状态资格、精确确认文案、取消不发请求、GCJ-02 编码、结构化成功门槛、重复点击、冷却、事件匹配、会话隔离、状态枚举与后端对齐；`blindRunTests.swift` 的 `testBlindRunnerEmergencyIsAvailableOnlyInProgress` / `testVolunteerEmergencyStaysHiddenInEveryStatus` / `testUnsetRoleCannotTriggerEmergency` 覆盖全 9 个状态 × 3 个角色。
- [x] 6.2 无定位、未转换的 WGS-84 样本、解码失败、网络失败、429 冷却均有用例；禁止 Demo 坐标由「只接受 `.gcj02Backend`」+「取样只走 `latestBackendSample()`」双重保证。
- [ ] 6.2a 后台/锁屏下触发的用例 —— **未做**，需真机，见 6.6。
- [x] 6.3 `blindRunUITests`：`testMockBlindOrderHidesEmergencyActionInAcceptedStates` 扩到 `IN_PROGRESS` 显示 + 64pt + 弹窗原文 + 取消不提交；新增 `testBlindEmergencyCopyNeverClaimsSmsDelivery`；志愿者全流程仍断言入口不存在。`AppRealtimeCoordinatorTests` 新增两条文案替换的端到端用例。
- [ ] 6.4 云端探针 —— **未做**。触发真实 SOS 会给紧急联系人发真短信并惊动客服，不能拿测试账号随便打；需要与后端约定演练时间窗后再补。
- [x] 6.5 `openspec validate enable-independent-sos-safely --strict --no-interactive` 通过；`node scripts/validate-docs.mjs` 通过。
- [ ] 6.6 真机批跑 —— **未执行**。设备 `111`（`00008140-000161D62112801C`）本轮全程离线，`iPad Pro (2)` 未连接；模拟器因高德无 arm64-sim slice 永久不可用。已完成的是 `xcodebuild build-for-testing -destination 'generic/platform=IOS'`，输出 `** TEST BUILD SUCCEEDED **`（app + 单测 + UI 测试三个 target 全部编译通过）。**编译通过不等于测试通过**，真机可用后必须补跑，且需含锁屏/后台监督验收。

## 8. 2026-08-07 盲人首页常驻求助条（批次 2）

放进本变更而不是另开一个：首页求助条 delta 的是 `in-run-dual-role-sos`，而该能力**不在
`openspec/specs/` 里**，只存在于本变更。另开变更会有两个未归档变更 delta 同一个能力，规格必打架。

- [x] 8.1 `BlindHomeSOSBar` + `BlindHomeSOSMode`（`blindRun/Safety/SafetyModule.swift`）。
  模式由订单状态决定、用户不可选：`IN_PROGRESS` 走云端（复用 `EmergencyCoordinator.trigger`
  与逐字锁定的二次确认），其余状态一律本地拨号，**不碰任何求助端点**。
  判定抽成 `BlindHomeSOSMode.resolve(order:role:)` 而不是留在 View 里 —— 真机 UI 测试通道
  当前起不来（code 74），只放在 UI 断言里等于零覆盖。
- [x] 8.2 降级分支文案进 `EmergencySafetyCopy`（`homeCall*` 一族），并补进
  `testNoEmergencyCopyClaimsAnSMSWasDelivered` 的清单。刻意**不叫**「一键求助」——
  那四个字在本 App 里专指云端求助，本地拨号复用会让盲人以为求助已发出。
- [x] 8.3 拨号 URL 唯一构造点 `EmergencyDialer.telURL`，只取数字：号码带空格/横线会拼出无效
  `tel://`，而无效 URL 的表现是「点了没反应」。
- [x] 8.4 首页布局改 `ZStack`：地图背景层 `allowsHitTesting(false)` + 对读屏
  `accessibilityHidden(true)`；设置齿轮移出标题行并排到遍历最后（靠 ZStack 里的声明顺序，
  遍历顺序 = 绘制顺序）。
  ~~地图背景层 `accessibilitySortPriority(-1)` + 内容层 `100`~~ —— 2026-08-14 真机实测
  该修饰符在叠放层上是**空操作**，已移除，见 8.8。
  「重复当前状态」降视觉权重但保留 64pt 触达区。求助条挂 `.safeAreaInset(edge:.bottom)`
  并注册 `.accessibilityAction(.magicTap)`。
- [x] 8.5 规格：`openspec/specs/blind-runner-voice-first-experience/spec.md` 放宽视觉顺序约束
  （改为只约束 VoiceOver 遍历顺序，并写明放宽的两个前提）；本变更 delta 补「首页常驻求助条」
  requirement，并把原「非 IN_PROGRESS 时隐藏 SOS」澄清为**隐藏的是订单关联的云端求助**。
- [x] 8.6 单测：逐状态钉住 `resolve`（只有 `IN_PROGRESS` 走云端）、拨号号码净化、
  降级文案必须含「不会代你发送求助」。
- [ ] 8.7 真机批跑本轮改动 —— 与 6.6 同一个阻塞项，见那里。
- [x] 8.8 UI 测试已在真机执行并通过（2026-08-14，`passed=12 failed=0`）。
  用例更名为 `testMockBlindRunnerHomeKeepsAuxiliaryMapOutOfVoiceOverSoPrimaryActionComesFirst`：
  原断言（主操作下标 < 地图下标）**从来就没有可通过的实现** —— `allElementsBoundByAccessibilityElement`
  是逐层枚举的，地图是深度 1、按钮是深度 3，27 vs 16 差的是深度不是顺序。
  且 `accessibilitySortPriority` 在叠放层上是空操作（四种排法真机实测，见
  `docs/research/swiftui-voiceover-traversal-order-20260814.md`），装饰地图已改为
  `accessibilityHidden(true)`。code 74 是无线连接掉链，插稳/重连后可复现地跑通。

## 7. 2026-08-04 规格订正（归档前置）

- [x] 7.1 **本变更的 spec 落后于实现一周，已修正。** `specs/in-run-dual-role-sos/spec.md` 与
  `specs/backend-api-contract/spec.md` 原文都写「志愿者入口恒隐藏」，理由是后端把紧急事件挂在
  **触发者**身上。后端 commit `a5ba523`（2026-07-31，SOS-1）已把 `event.userId` 改为取订单的
  盲人方、用 `TriggerType.VOLUNTEER_BUTTON` 区分来源，该理由自那天起就不成立；
  代码（`RunOrderStatus.canVolunteerTriggerEmergency == (self == .inProgress)`）也早已开放。
  规格、`AGENTS.md` 第 6 节、项目记忆三处同时陈旧 —— 已一并订正。
- [x] 7.2 补入「志愿者不得拥有『误触』按钮」（后端 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`，
  一对一陪跑里志愿者可能就是威胁来源）。原 spec 完全没有这条。
- [x] 7.3 `openspec validate enable-independent-sos-safely --strict --no-interactive` 重跑通过。

**归档仍被 6.6 阻塞**：真机批跑没跑过就归档，等于把「编译通过」当成「测试通过」入库。
6.4（云端探针）需与后端约定演练时间窗；6.2a 依赖 6.6。
