# STATE — 盲人跑者首页重构（2026-08-03）

## 总体决策（已与产品负责人逐条确认，不要重新讨论）

原始诉求是「首页做成滴滴那样：地图在上、中间一个大按钮、右下角小红 SOS 连点三次」。调研与读码后调整为四条，**用户已确认**：

1. **地图**：视觉上铺满上半屏（像滴滴），但读屏遍历顺序仍是操作优先。技术支点是 `accessibilitySortPriority` —— 视觉顺序与 VoiceOver 顺序解耦。
2. **SOS**：底部全宽 ≥64pt 红按钮 + VoiceOver Magic Tap（双指双击，全屏生效）。**不做**右下角小按钮，**不做**连点三次，**保留**现有二次确认。
3. **无活跃订单时的 SOS**：降级为本地拨号（110 / 主紧急联系人），不走后端。后端 `EmergencyTriggerRequest` 必须带 `orderId` 且仅 `IN_PROGRESS`。
4. **一键约跑**：语音复述默认值 → 说「确认」即提交。

调研结论摘要（不必重查）：Aira / Be My Eyes / Seeing AI / Soundscape / BlindSquare / RunGo 无一把地图放首屏顶部；滴滴的「一键报警」实为 4 次点击、官方称刻意折叠防误报；「重复当前状态」不冗余（系统 Speak Screen 读不到一次性 announcement），但可降视觉权重。

完整方案：`/Users/mac/.claude/plans/snazzy-wobbling-floyd.md`

---

## 批次 1（已完成代码，未跑真机）

openspec 变更：`openspec/changes/enable-one-utterance-booking/`（`validate --strict` 通过）

**改了什么**
- `SpeechInputService.clearRecognitionStartState` 缺陷修复：原本清空 `completionHandler` 而不调用它，导致授权被拒时 `VoiceOrderWizard` 无限静默等待。已改为清空前送出一次 `.error` 终局完成。
- 新增 `SpeechInputService.isSpeechPathUnavailable`，让向导跳过无意义的三轮重问。
- `VoiceOrderWizard` 的首步是 **`.freeform`（整句说完 → 读回整单 → 说「确认」）**，不是 `.confirmDefaults`。
  ⚠️ 本文件此前写的是 `.confirmDefaults`（先念默认值再逐项追问），**那个形态从未落地**；
  2026-08-04 已同步订正 `openspec/.../tasks.md` 第 2 节与 `proposal.md`/`design.md`。
  默认值对首次下单的用户几乎总是错的（起点=当前位置、时间=系统默认），先听一遍必错的默认值比直接说一句慢。
- `isAffirmative(_:)` 本地保守白名单（整串匹配，19 条肯定词，刻意不收「嗯」）保留，用在 `.confirm` 轮。
- `BlindBookingView`：向导步骤 → 表单段落的映射；`onReceive(voiceWizard.$createdOrder)` 复用既有 `onOrderCreated` 出口。
- 文档：`docs/05-page-specs.md`、`docs/09-accessibility-and-voice-guidelines.md`。

**2026-08-04 追加（批次 1 的延伸，见 openspec tasks 第 2A 节）**
- 整句解析改走 `POST /api/orders/voice/parse`：两路并发 `parse-slot` → 一次请求，删除常闭开关
  `resolvesPlaceFromFullUtterance`，**整句里说的出发地点第一次可用**。
- `String.backendLocalDate`：后端 `LocalDateTime` 取自 `now()` 时带小数秒（`2026-08-04T11:40:42.644571`），
  原解析器解不出、`displayDateTime` 会把 ISO 串原样念给盲人。带时区偏移的串不截，退回 ISO8601 分支。
- 整句轮补上时长取整播报，与定点修改轮共用一个函数。
- 删除 `WSEmergencyContactNotified` 顶层通道 5 处死代码（后端从未实现，与 `SEPARATION_ALERT` 同类）。
- 紧急联系人表单短信文案按 `isEditing` 分支（编辑换号后端不发短信，原文案是假承诺）。
- 新增 `scripts/validate-spec-coverage.mjs`。

**验证到哪一步**
- `TEST BUILD SUCCEEDED`（`CODE_SIGNING_ALLOWED=NO`）
- 独立 Swift 脚本实跑：`/tmp/clearstate_check.swift`、`/tmp/affirmative_check.swift`、
  `/tmp/fracsec_check.swift`、`/tmp/voiceparse_check.swift` 全 PASS
- `node scripts/validate-docs.mjs`、`node scripts/validate-spec-coverage.mjs` 通过
- **✅ 真机 XCTest 已跑（2026-08-04 14:36，iPhone 16 Pro）：`TEST SUCCEEDED`，
  483 单测 + 33 UI 用例、0 失败、首跑零陈旧断言**（1 条 skip 是 `testCloudBackendBlindRunnerBookingSmoke`，
  需 Demo 构建通道）。本轮新增/改写的 14 条用例逐条核过，都真的执行并通过，不是「套件绿就算跑了」。
  命令（设备名会变，用 id）：
  `xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,id=00008140-000161D62112801C' -allowProvisioningUpdates DEVELOPMENT_TEAM=ZW39BS8NXT`
  ⚠️ **跑之前先解锁并保持屏幕常亮**，否则会静默等在 `Run Destination Preflight: Unlock ... to Continue` 上，
  不报错也不退出（本轮先踩了一次，输出文件 0 字节看着像在跑）。
  ⚠️ 日志里是 `Test case '...' passed`（小写 c），按 `Test Case` 去 grep 会全部计成 0。

**批次 2 开始前必须先做**
1. 真机跑批次 1 的 `tasks.md` 5.4 / 5.5，尤其 1.7（新增回调是否波及地点搜索、备注、评价等其他 `SpeechInputField` 使用方）
2. 补 `tasks.md` 3.4 / 3.5 两条未写的用例
3. ~~`GET /api/misc/legal-links` 前端从未请求过~~ **已修（2026-08-04）**：实情比记录的更糟 ——
   不只是没发请求，**设置页那两个入口本身也不存在**，整个功能只有 model 层。
   现已补齐：`AppState.loadLegalLinksIfNeeded()`（免鉴权、只拉一次、失败静默）+
   `LegalDocumentsSection` / `LegalFallbackDocumentView`（新文件 `blindRun/Core/LegalDocumentsView.swift`）
   挂在 `AboutAidRunView` 上，盲人端与志愿者端共用。顺带修掉内置用户协议里
   「一个手机号可以同时拥有两个身份」那句 —— 与「角色一经设定不可更改」相反，且会被审核员读到。

---

## 批次 2（未开始）

### openspec 的前置障碍（重要）

`in-run-dual-role-sos` **不在 `openspec/specs/` 里** —— 它只存在于未归档的变更 `enable-independent-sos-safely`。两个未归档变更 delta 同一个能力会打架。开始前先决定：

- (a) 先归档 `enable-independent-sos-safely`（它有 6 条未完成任务，其中 6.4 云端探针、6.6 真机批跑是真的没做），再新建变更；或
- (b) 把首页 SOS 条的 delta 直接加进 `enable-independent-sos-safely`

~~另：该变更的 spec `:11-13` 仍写「志愿者 SOS 恒隐藏」~~ **✅ 2026-08-04 已修**（见文末「工作流加固」一节）。
现在 (a) 只剩「6 条未完成任务里 6.6 真机批跑是真的没做」这一个前置。

### 要动的规格

- `openspec/specs/blind-runner-voice-first-experience/spec.md:9` 现文 **「in both visual order and VoiceOver traversal order」直接禁止本方案的视觉布局**，必须改为「读屏遍历顺序操作优先；视觉顺序不受此限，但地图不得可交互、不得承载任何必要信息」。
- `docs/05-page-specs.md:181,194,226` 首页布局
- `AGENTS.md` 第 8 节 / `:237`：补「首页 SOS 条在非 `IN_PROGRESS` 时是本地拨号，不调 `POST /api/emergency/trigger`」

### 要动的代码

`blindRun/BlindRunner/BlindRunnerHomeView.swift`（741 行）
- `ZStack`：地图背景层 `.accessibilitySortPriority(-1)` + 内容层 `.accessibilitySortPriority(100)`
- 内容层 ScrollView **必须保留 `blindRunnerHomeScrollView` 标识符**（UI 测试 `:85` 依赖）
- 删除「语音下单」按钮与 `BlindRunnerRoute.booking`（`:575-603`、`:403-409`），首页收敛为一个主按钮，走 `.voiceBooking`
- 「重复当前状态」保留但降视觉权重（`AGENTS.md:222` 硬性要求每个关键盲人页面都有它）
- 设置齿轮从 header 的 `HStack` 移出，别再排在遍历第 2 位
- `.safeAreaInset(edge: .bottom)` 挂 SOS 条；`.accessibilityAction(.magicTap)`

`blindRun/Safety/SafetyModule.swift`
- 新增首页 SOS 条：`IN_PROGRESS` 复用现有 `EmergencyActionButton` + `emergencyConfirmationAlert`（确认文案 `AGENTS.md` 第 10 节逐字锁定，不改）；其余状态走 `confirmationDialog` → `UIApplication.shared.open(URL(string:"tel://110")!)`
- 主联系人取 `appState.emergencyContacts` + `EmergencyContactResponse.singlePrimary(in:)`。**后端自 v1.5.0 返回明文手机号**（`ProfileModels.swift:369`），`maskedPhone` 只是展示层，`phone` 可直接拨
- 新文案一律加进 `EmergencySafetyCopy` —— 既有的 `EmergencySOSTests.testNoEmergencyCopyClaimsAnSMSWasDelivered` 会自动守住「不得宣称已送达」红线
- 文案必须说清这是**打电话**，不是 App 求助

`blindRun/BlindRunner/BlindOrderStatusView.swift`：加 Magic Tap（`IN_PROGRESS` 期间 SOS 真正生效的地方，价值最高）

### 要改的既有测试

`blindRunUITests/blindRunUITests.swift:44-48` `testMockBlindRunnerHomePlacesPrimaryActionBeforeAuxiliaryMap` 现在断言 `startButton.frame.minY < auxiliaryMap.frame.minY`，即**视觉**顺序。新方案下这个前提反转。改为断言**无障碍遍历顺序**：在 `app.descendants(matching: .any).allElementsBoundByAccessibilityElement` 里主按钮下标 < 地图下标。测试名也要改。

其余引用：`:37,65,1338,1399`（「开始约跑」label 不变）、`:85`（scrollView 标识符）、`:88,228,896`（地图标识符）。

---

## 环境事实（别重新踩）

- **真机是唯一 XCTest 通道**，模拟器因高德无 arm64-sim slice 永久不可用。**不要改 Podfile / EXCLUDED_ARCHS。**
- 无真机时的编译上限：`xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing`
- 真机命令需 `-allowProvisioningUpdates DEVELOPMENT_TEAM=ZW39BS8NXT`（工程里写死的 `R6PH2TFB3Q` 是原开发者的团队，命令行覆盖，**不要改 pbxproj**）
- 设备 `mac's iPhone` 会掉线，`xcrun devicectl list devices` 显示 `unavailable` 时先查设备状态
- 纯逻辑改动先用独立 Swift 脚本实跑，秒级出结果
- **编译通过不等于测试通过。永远不许把没执行过的测试写成通过。**

## 两个硬约束（产品已知悉）

- **没有「现在就跑」**：`minimumBookingLeadMinutes = 30`（`EnvironmentConfig.swift:99`），后端回 `APPOINTMENT_TOO_SOON`。滴滴式即时叫车属派单模型变更。
- **SOS 必须带 orderId 且仅 `IN_PROGRESS`**（`OrderModels.swift:125`）。

---

## 工作流加固（2026-08-04，本轮全部落地）

起因：审计发现「规范层写得好，但执行层零机器强制」—— AGENTS.md/OpenSpec/handoff 都靠自觉遵守，
7 起契约事故里 6 起是字段/语义级，而唯一的漂移检测只查路径级。

### 新增的机器强制点（7 个）

| 文件 | 拦什么 |
|---|---|
| `scripts/hooks/guard.mjs` | 订单禁用词、SOS 完成时态文案、非法服务端地址、高德 key 硬编码、读归档契约、改冻结文件 |
| `scripts/validate-error-codes.mjs` | 前端 `ErrorCode` 枚举 vs 后端 `ErrorCode.java`，抓「映射了不存在的码」 |
| `scripts/validate-golden-corpus.mjs` | 语音黄金语料 vs `VoiceOrderWizardTests` 里的人工抄件 |
| `blindRunTests/ContractFixtureTests.swift` | 真实响应字节跑生产解码路径（fixture 待采集） |
| `blindRunUITests/AccessibilityAuditTests.swift` | `performAccessibilityAudit` + 64pt + 「重复当前状态」 |
| `.github/workflows/verify.yml` | 编译门禁 + 全部规格校验（此前**零 CI**） |
| `scripts/install-git-hooks.sh` → pre-push | 五条 node/openspec 校验钉在 push 前 |

`scripts/device-test.sh`：把真机跑测的两个陷阱固化 —— 锁屏静默挂起会主动检出并失败；
用例统计**只认 `-resultBundlePath` 产出的 result bundle，不再 grep 日志**。
（日志不可信：xcodebuild 进度、XCTest runner stdout、设备 os_log 三路并发写同一 fd，
统计行会被拦腰截断。2026-08-07 实测真实 539 条只数出 530、535 只数出 528。
判定逻辑在 `scripts/xcresult-verdict.mjs`，自测 `scripts/validate-xcresult-verdict.mjs`。）

### Claude Code 配置

- `CLAUDE.md` 改成 `@AGENTS.md` —— **此前 AGENTS.md 328 行硬约束根本没被自动加载**，
  Claude Code 只自动读 CLAUDE.md，原来那句「Read and follow AGENTS.md」只是自然语言请求。
- `AGENTS.md` 328 → 148 行，§5/§9/§7错误码/§11-13 拆进 `.claude/skills/aidrun-{auth,a11y-voice,error-codes,ship-check}/`
- `.mcp.json` 装 XcodeBuildMCP，`XCODEBUILDMCP_ENABLED_WORKFLOWS=device,project-discovery`
  （**注意**：博客上常见的 `XCODEBUILDMCP_DYNAMIC_TOOLS` 在当前版本里不存在；workflow 名是
  `ui-automation` 不是 `ui-testing`；simulator workflow 对本项目永久无用）
- `.claude/settings.json`（团队层，入库）挂 guard + session-context hook

### 顺带抓出的两个真实问题

1. **`EmergencySafetyCopy.closedFalseAlarm` 违反 SOS 红线** —— 写着「紧急联系人已收到解除通知」，
   但解除短信走的是和求助短信同一条异步路径，**没有运营商回执**。它比触发路径晚加，
   一直没被收进 `testNoEmergencyCopyClaimsAnSMSWasDelivered` 的清单。已改进行时 + 补进清单。
   （唯一允许完成时的是 `contactSmsDelivered`，有 `EMERGENCY_CONTACT_SMS_DELIVERED` 回执支撑。）
2. **AGENTS.md 错误码表里三个码名是错的** —— 真名是 `ORDER_STATUS_NOT_ALLOWED`（非 `INVALID_ORDER_STATUS`）、
   `VOLUNTEER_NOT_VERIFIED`（非 `VOLUNTEER_NOT_APPROVED`）；`LOCATION_PERMISSION_REQUIRED` 后端根本没有。
   代码里映射的是对的，只有文档错 —— 「文档不是真相源」的标本。

### 仓库卫生

`.CLAUDE.md.swp` 曾被 git 跟踪（已 `git rm --cached`）；两个 28MB 僵尸 worktree 已移除（释放 56MB）；
`.gitignore` 补 `*.swp` / `.claude/worktrees/` / `.claude/settings.local.json`。

### 验证到哪一步

- ✅ `xcodebuild build-for-testing -destination 'generic/platform=iOS'` → `TEST BUILD SUCCEEDED`
- ✅ guard.mjs 全仓库 82 个 Swift 文件零误报；6 条违规逐个实测被拦
- ✅ 五条 node/openspec 校验全通过（pre-push 实跑）
- ✅ golden-corpus / error-codes 两个新脚本做过反向自测（故意改错必须报错）
- ⬜ **真机 XCTest 未跑** —— 设备锁屏，`device-test.sh` 秒级检出并失败（日志原文
  `Unlock mac's iPhone to Continue`）。**这本身验证了脚本有效**：以前会在这里无限静默挂起。
  解锁常亮后重跑：`scripts/device-test.sh`
- ⬜ **fixture 未采集** —— 卡在后端短信限流。`/api/auth/send-code` 先回 429 `TOO_MANY_REQUESTS`
  （`retryAfterSeconds: 60`，脚本已自动重试 2 次），重试后升级为 429 `SMS_SEND_LIMIT_EXCEEDED`
  （**按手机号的更长窗口**）。说明这条链路真的会消耗短信配额。
  绕开方式（已内置）：拿到 token 后
  `AIDRUN_FIXTURE_BLIND_TOKEN=<jwt> AIDRUN_FIXTURE_VOLUNTEER_TOKEN=<jwt> node scripts/capture-fixtures.mjs --write`
  —— 复用 token 直接跳过 send-code，不烧配额。
  在 fixture 到位前 `ContractFixtureTests` 会 XCTSkip 并打印指引，**不会假绿**。

---

## UI 测试通道故障（2026-08-06，未解决，别重新诊断）

**现象**：真机单测 489 条全过，**UI test runner 起不来**，零执行，稳定复现：
`blindRunUITests-Runner encountered an error (Early unexpected exit ... exited with code 74 before establishing connection)`

**失败点已定位到握手，不是编译/签名/链接/测试代码**：runner 正常安装、正常启动、打印
`Running tests...`，恰好 30.8 秒后它申请的控制通道被对端拒绝：

```
[DTXConnection] Connection peer refused channel request for
"dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface"; channel canceled
[Default] Exiting due to IDE disconnection.
```
IDE 侧日志显示已在 listen、会话 id 匹配，**从头到尾没收到 test bundle 的 proxy 连接请求**。

**已用证据排除的（别再查）**：
- `e83cf61`（接入 Swift OpenAPI Generator）—— pbxproj 的 22 行改动全部落在 `blindRun` app target，
  `blindRunUITests` 一个字没动；UI bundle 的 `otool -L` 里没有任何 AidRunAPI/OpenAPIRuntime；
  `PackageFrameworks/` 为空（静态链接，无动态库要 embed）；失败时 `blindRun.app` 进程根本没起
- 签名/entitlements/provisioning —— `TeamIdentifier=ZW39BS8NXT`、`get-task-allow=true`、
  日志明确 `Successfully installed` + `Successfully launched`
- 缺动态库 / dyld / crash —— 框架齐全，无 crash log
- Developer Mode / DDI —— `developerModeStatus: enabled`、`ddiServicesAvailable: true`
- 新增的 `AccessibilityAuditTests.swift` —— 符号确实在 bundle 里，但失败发生在任何用例被枚举之前；
  且 08-04 那次「33 条 UI 全过」= 29 + 4，说明它当时已经在里面且是过的

**两个未证实的嫌疑（缺对照实验，因为设备中途锁屏）**：
1. **设备上有一个陈旧的 `DTServiceHub`（pid 22262）**，pid 小于所有失败的 runner，且在 Mac 上
   零 Xcode/xcodebuild 进程的情况下存活半小时以上。一个悬挂的会话占着 testmanagerd 的自动化槽位，
   正好能解释「新 runner 申请 IDE 通道被拒」。尝试 `devicectl device process terminate` 失败
   （设备锁屏 + 链路抖动）。
2. **真机只走 Wi-Fi，没插 USB**（`transportType: localNetwork`，`ioreg -p IOUSB` 查不到 iPhone）。
   UI 测试要双向 DTX 握手，单测只需单向下发 —— 这正好解释「489 单测全过、UI runner 起不来」的分裂。
   同一条链路半小时内还抖出另两种故障：`Lost pending connection to the test runner before launch`、
   `Device is busy (Connecting to mac's iPhone)`。

**下次要做的（按顺序，每步看实际输出）**：
1. **重启 iPhone**（一次同时清掉残留 DTServiceHub 和锁屏状态），解锁 + 自动锁定设「永不」
2. **插 USB 线**，确认 `xcrun devicectl device info details` 的 `transportType` 不再是 `localNetwork`
3. `scripts/device-test.sh -only-testing:blindRunUITests/blindRunUITestsLaunchTests` 先跑 1 条
4. 仍是 code 74 → 上面两个嫌疑都不对，需要：① hello-world 工程在同一设备跑一条 UI 测试做对照
   （唯一能分开「本仓库问题」与「这台 Mac+设备问题」的实验）；② 失败那 30 秒窗口内的
   `xcrun devicectl device sysdiagnose`（本次 `devicectl diagnose` 全程失败，拿不到设备侧日志，
   这是最大的信息缺口）

**`scripts/device-test.sh` 对这两种故障的处理是正确的**：锁屏被 `grep 'Unlock .* to Continue'` 抓到
立即失败；code 74 走 `TOTAL -eq 0` 分支报「一条用例都没执行」。没有假装通过的漏洞。
