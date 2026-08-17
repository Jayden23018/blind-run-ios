# AidRun 上线测试报告 - 2026-07-06

## 1. 测试结论

本次按完整发布门禁执行了文档校验、OpenSpec 校验、单真机发布门禁、双真机门禁、真实高德地图 smoke、Demo Cloud UI smoke、真实云端 REST/WebSocket E2E。除真实盲人用户人工验收外，可自动化项目均已执行并通过。

结论：当前工程自动化门禁通过，可以进入真实盲人用户验收与上线前风险确认阶段。不能把本报告视为真实盲人用户在真实出行、安全场景中的验收结论。

修复更新：本轮已按产品确认将当前 release 的求助入口隐藏，不宣称真实求助能力；`POST /api/emergency/trigger` 仅作为后端合同探针保留。相关 `AGENTS.md`、维护文档、OpenSpec、UI copy、E2E 命名和 UI 测试已同步到该口径。

## 2. 测试环境

| 项 | 值 |
| --- | --- |
| 日期 | 2026-07-06 |
| 分支 | `feature/swift-migration` |
| Commit | `b55c45d` |
| 工作区初始状态 | `## feature/swift-migration...origin/feature/swift-migration` |
| iPhone 设备 | `111`，iPhone 14 Pro，id `4B5B01EA-66B1-5FA6-BA79-B5C797FB6082` |
| iPad 设备 | `iPad Pro (2)`，iPad Pro 11-inch 4th gen，id `68F30361-577E-5E7C-BCF5-7EDEAA425CD4` |
| 云端 HTTP | `http://47.114.113.171` |
| 云端 WebSocket | `ws://47.114.113.171` |
| 高德配置 | `LocalConfig.xcconfig` 存在；未输出真实 Key |
| 测试账号 | 盲人端 `13800000001`，志愿者端 `13800000002`，验证码 `000000` |

说明：第一次运行单设备发布门禁时，沙箱内 `xcodebuild` 访问真机/CoreSimulator 失败；随后按权限要求以已批准的真机测试方式重新运行，结果通过。

## 3. 命令与结果

| 步骤 | 命令摘要 | 结果 |
| --- | --- | --- |
| 预检 | `git status --short --branch` | 通过，测试前无 repo-tracked 变更 |
| 预检 | 检查 `LocalConfig.xcconfig` | 通过，文件存在，未输出 Key |
| 预检 | `xcrun devicectl list devices` | 通过，`111` 与 `iPad Pro (2)` 均已连接 |
| 文档 | `node scripts/validate-docs.mjs` | 通过，`[validate-docs] maintained docs passed` |
| OpenSpec | `openspec validate remove-local-backend-use-cloud-only --strict --no-interactive` | 通过，change valid |
| 单真机发布门禁 | `AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/production-readiness-check.sh` | 通过 |
| 双真机门禁 | `AIDRUN_BLIND_DEVICE_NAME=111 AIDRUN_VOLUNTEER_DEVICE_NAME='iPad Pro (2)' AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/dual-device-validation.sh` | 通过 |

### 3.1 单真机发布门禁明细

- 设备：`111`
- 基础 XCTest：通过。观察到单元/UI 测试共覆盖核心 ViewModel、Mock API、订单状态、TTS/VoiceOver 辅助逻辑、启动测试等；真实设备日志中有 1 个 docs-sandbox 相关跳过项，文档校验已由 Node 脚本覆盖。
- 真实高德 smoke：通过，`testRealAMapEnabledSmoke` 找到 `volunteerHomeMap`，未进入缺 Key/地图不可用占位。
- Demo Cloud UI smoke：通过，`testCloudBackendBlindRunnerBookingSmoke` 完成登录、盲人资料补齐检查、创建预约、进入 `系统派单中`、二次确认取消、进入 `已取消`。
- 云端 E2E：通过。

相关 xcresult：

- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-2026.07.06_15-33-13-+0800.xcresult`
- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-2026.07.06_15-35-30-+0800.xcresult`
- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-Demo-2026.07.06_15-35-47-+0800.xcresult`

### 3.2 双真机门禁明细

- 盲人端设备：`111`
- 志愿者端设备：`iPad Pro (2)`
- 两台设备基础 XCTest：通过。
- 两台设备真实高德 smoke：通过。
- 两台设备 Demo Cloud UI smoke：通过。
- 后端云端 REST/WebSocket E2E：通过。

相关 xcresult：

- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-2026.07.06_15-37-21-+0800.xcresult`
- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-2026.07.06_15-39-23-+0800.xcresult`
- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-2026.07.06_15-41-28-+0800.xcresult`
- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-2026.07.06_15-41-44-+0800.xcresult`
- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-Demo-2026.07.06_15-41-58-+0800.xcresult`
- `/Users/jerry/Library/Developer/Xcode/DerivedData/blindRun-efdofwdhnrqmojegblbewotpkzok/Logs/Test/Test-blindRun-Demo-2026.07.06_15-42-55-+0800.xcresult`

## 4. 云端 E2E 摘要

### 4.1 单真机发布门禁 E2E

| 项 | 值 |
| --- | --- |
| blindUserId | `4` |
| volunteerUserId | `6` |
| 主流程订单 | `75` |
| 求助合同探针订单 | `76` |
| 求助合同事件 | `24` |
| 主流程最终状态 | `COMPLETED` |
| WebSocket | 盲人端 connected，志愿者端 connected，志愿者收到 `NEW_ORDER` |
| Dispatch readiness | `NEW_ORDER` |
| 可用订单轮询 | `status=200 count=0 containsOrder=false`，但 WebSocket `NEW_ORDER` 已派发 |

覆盖链路：

`send-code -> verify-code -> set-role -> profile/contact/availability -> ws/blind + ws/volunteer -> volunteer LOCATION_UPDATE -> create order -> NEW_ORDER -> ACCEPT -> en-route -> arrived -> start-service -> finish -> COMPLETED`

后端 emergency 合同探针链路：

`create emergency order -> ACCEPT -> en-route -> POST /api/emergency/trigger -> emergencyEventId=24 -> arrived/start-service/finish 均返回 OK`

### 4.2 双真机门禁 E2E

| 项 | 值 |
| --- | --- |
| blindUserId | `4` |
| volunteerUserId | `6` |
| 主流程订单 | `79` |
| 求助合同探针订单 | `80` |
| 求助合同事件 | `25` |
| 主流程最终状态 | `COMPLETED` |
| WebSocket | 盲人端 connected，志愿者端 connected，志愿者收到 `NEW_ORDER` |
| Dispatch readiness | `NEW_ORDER` |
| 可用订单轮询 | `status=200 count=0 containsOrder=false`，但 WebSocket `NEW_ORDER` 已派发 |

盲人端 WebSocket 收到的关键通知包括（其中紧急求助通知来自后端合同探针，不代表当前 iOS UI 暴露求助入口）：

- 已收到订单，正在呼叫志愿者
- 志愿者已出发
- 志愿者已到达附近
- 服务已开始
- 订单已完成
- 紧急求助已发出，系统正在通知志愿者

志愿者端 WebSocket 收到的关键通知包括（其中 `EMERGENCY_VOLUNTEER_ALERT` 来自后端合同探针）：

- `NEW_ORDER` for order `79`
- `NEW_ORDER` for order `80`
- `EMERGENCY_VOLUNTEER_ALERT` for emergency event `25`

## 5. 代理式人工 / UX 走查记录

本次没有真实盲人用户参与，也没有在真实户外环境中验证触控、读屏、听觉提示、定位漂移、安全求助和陪跑过程。代理式走查基于真机 XCUITest 可访问性层级、真实高德 smoke 截图附件、Demo Cloud UI smoke、REST/WebSocket E2E 输出和文档/代码对照，不能替代真实盲人用户验收。

| Severity | 角色 | 页面 | 问题 | 对盲人用户影响 | 证据 | 建议 | 是否阻塞上线 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P0 | 盲人/志愿者 | 求助 | 已按当前 release 隐藏求助入口收敛；后端 `/api/emergency/trigger` 仅作为合同探针。 | 避免用户误以为真实救援流程已经触发。 | 本轮同步 `AGENTS.md`、docs、OpenSpec、UI 行为和 E2E 命名；UI 测试增加“不显示一键求助”断言。 | 后续若恢复真实求助，必须单独安全专项补 GPS、通知、失败提示、合规文案和真实盲人验收。 | 否，当前版本不宣称真实求助能力 |
| P1 | 盲人 | 全流程 | 自动化只能证明元素存在和接口状态，未验证真实 VoiceOver 读屏顺序、焦点移动、音频 TTS 是否清晰、是否与系统读屏冲突。 | 盲人用户可能在关键状态变化、表单输入、危险确认时迷失。 | 本次为 XCUITest/脚本验证，无真实盲人用户现场验收。 | 安排真实盲人用户使用 VoiceOver 完成登录、预约、等待、取消、完成/评分，并记录焦点与播报。 | 是，若面向真实用户上线 |
| P1 | 盲人/志愿者 | 安全与账号 | 当前允许固定验证码 `000000`、HTTP 明文 IP、WebSocket 明文 IP、token 存 `UserDefaults`。 | 账号与位置/订单数据存在上线安全争议；盲人用户属于高敏安全场景。 | `AGENTS.md` 明示现状，并将 Keychain 迁移列为 hardening；测试命令使用真实明文云端地址。 | 产品/安全负责人书面确认是否可作为 Demo/灰度上线条件；正式生产建议 HTTPS/WSS、Keychain、真实短信策略。 | 需人工确认 |
| P1 | 盲人 | 地图/定位 | 地图 smoke 证明地图渲染，但地图本身是视觉信息；本次未验证非视觉定位摘要是否足以替代地图。 | 盲人用户无法直接理解地图标记、距离、志愿者移动方向。 | `testRealAMapEnabledSmoke` 只验证 map container 和未降级。 | 每个含地图页面提供可读当前位置、起点、志愿者距离/方向、更新时间；真实读屏验收。 | 需人工确认 |
| P2 | 盲人 | 登录/表单 | 本轮已修复手机号输入框可显示超过 11 位的问题，并让验证码满 6 位时收起输入焦点；表单步骤仍需真实 VoiceOver 验收。 | VoiceOver 用户登录负担降低，但仍需确认读屏焦点和键盘路径。 | 新增 UI 测试输入 `13800138000999` 后断言输入框 value 为 `13800138000`，并确认"获取验证码"可用。 | 将新增 UI 测试结果纳入正式发布验收记录；真实盲人用户仍需确认登录流程。 | 否，但影响流畅度 |
| P2 | 盲人 | 预约/等待 | Demo Cloud UI smoke 覆盖创建与取消，但未覆盖 UI 上志愿者接单、出发、到达、开始服务、完成、评分的双端真实界面闭环。 | 关键等待和完成状态的 UI/TTS 可能仍有未发现的焦点或文案问题。 | 完整状态机由 `scripts/cloud-e2e.mjs` 的 REST/WebSocket 覆盖，不是两端 UI 操作覆盖。 | 增加双端 UI 自动化或人工脚本：盲人端下单，志愿者端接单并推进，盲人端完成评分。 | 建议上线前补测 |
| P2 | 盲人 | 危险操作 | 当前 release 已隐藏求助入口；取消订单二次确认已在 UI smoke 覆盖，完成服务与退出登录已补充 UI 测试用例。 | 危险操作误触风险需继续实测，尤其退出和志愿者完成服务。 | 本轮新增 Mock UI 覆盖：志愿者完成服务确认、盲人退出登录确认、求助入口隐藏。 | 将新增 UI 测试结果纳入正式发布验收记录；真实用户验收仍需覆盖危险确认。 | 建议上线前补测 |
| P2 | 盲人/志愿者 | 稳定性 | Xcode 真机日志多次出现诊断收集失败、`AXCommon`、音频 buffer、短暂 hang、AMap `EAGLDrawable` 绑定失败等噪声。 | 当前未导致测试失败，但可能掩盖真实设备上的偶发卡顿、音频或地图问题。 | xcodebuild 输出包含 `CoreDeviceCLISupport.DiagnoseError`、`AVAudioBuffer mDataByteSize (0)`、`Hang detected`、`Failed to bind EAGLDrawable`。 | 发布前抽样冷启动、后台恢复、弱网、定位权限切换、长时间等待。 | 否，但需跟踪 |
| P2 | iPad 用户 | 启动/适配 | iPad 设备测试出现 Launch screen 将被要求的 UIKit 配置警告。 | 未来 SDK/App Store 要求变化时可能影响提审或启动体验。 | `iPad Pro (2)` xcodebuild 日志出现 `[UIKit App Config] Update the Info.plist: Launch screens will soon be required.` | 检查 launch screen 配置并纳入上线 hardening。 | 否，当前测试未失败 |
| P3 | 志愿者 | 服务流 | 志愿者完整接单/推进主要由 API E2E 覆盖，UI smoke 在志愿者设备上仍执行盲人 booking smoke，而非志愿者操作流。 | 志愿者端真实接单按钮、状态推进、联系方式展示可能仍需人工确认。 | `dual-device-validation.sh` 两台设备均运行同一个 `testCloudBackendBlindRunnerBookingSmoke`。 | 增加志愿者端 UI smoke：登录志愿者、开可接单、看到 `NEW_ORDER`、接受、出发、到达、开始、完成。 | 建议补测 |

## 6. 失败项、阻塞项、复测建议

### 6.1 自动化失败项

无。所有计划中的自动化门禁最终通过。

### 6.2 阻塞项

- 真实盲人用户人工验收未完成。本报告不能替代。
- 求助能力口径冲突已按“当前 release 隐藏入口、后端合同探针保留”收敛。若后续对外承诺真实求助，必须另起安全专项。

### 6.3 复测建议

- 对真实盲人用户执行 VoiceOver + TTS 人工验收：登录、资料、预约、等待、取消、完成/评分。
- 补齐双端 UI E2E：`111` 下单，`iPad Pro (2)` 接单并推进完整服务状态，盲人端完成评分。
- 针对未来求助能力做专项验收：确认 UI copy、二次确认、GPS 提交、志愿者通知、订单状态不变、失败提示。
- 进行弱网/断网/WebSocket 断开后 REST fallback 验证。
- 上线前确认 HTTP/WSS、Keychain、固定验证码、隐私合规、Launch screen warning 是否接受。

## 7. repo 变更记录

计划内 repo 输出不再仅限本报告。本轮同步修改了 iOS 业务代码、单元/UI 测试、维护文档、OpenSpec、OpenAPI 描述、云端 E2E 脚本、`Info.plist`、launch screen 颜色资产和本测试报告。

本次代码与文档变更包括：

- 隐藏当前 release 的盲人端/志愿者端求助入口，并将 `/api/emergency/trigger` 收敛为后端合同探针。
- 修正手机号/验证码输入规范化、地图可访问性文案、非视觉定位摘要、完成服务与退出登录确认相关 UI 测试。
- 更新 `AGENTS.md`、`plan.md`、`docs/01-10`、`docs/websocket-protocol.md`、OpenSpec 和 `scripts/cloud-e2e.mjs` 的求助能力口径。
- 为 launch screen 增加颜色资产和 `UILaunchScreen` 配置。

本次仍未修改：

- 后端代码、数据库配置或本地可运行后端
- 高德地图真实 Key 或本地配置内容
- 真实云端 HTTP/WebSocket 地址

OpenAPI 仅补充 emergency endpoint 的说明文字，未新增或变更路径、请求体、响应 schema。

## 8. docs/OpenSpec 与 AGENTS.md 冲突

修复后结论：

- `AGENTS.md`、维护文档和 OpenSpec 已同步：当前 iOS release 不显示求助入口，不宣称真实求助能力。
- `POST /api/emergency/trigger` 仍在 OpenAPI 中作为后端合同；`scripts/cloud-e2e.mjs` 将直调命名为 emergency contract probe。
- 本次云端 E2E 证明后端 emergency endpoint 可用，订单 `80` 产生 emergency event `25`，但该结果不代表当前 iOS UI 已上线求助。

后续若恢复真实求助 UI，必须单独安全专项处理接口、GPS、通知、失败提示、合规文案和验收测试。

## 9. 需要人工确认

- 未来是否恢复真实求助能力，以及恢复时的合规、通知和验收责任边界。
- 是否接受 HTTP 明文 IP、WebSocket 明文 IP、`UserDefaults` token、固定验证码作为当前发布条件。
- 是否已有正式隐私合规、定位权限、高德地图 Key 管理、App Store 提审材料。
- 是否安排真实盲人用户完成 VoiceOver/TTS/触控/安全场景验收。
- 是否在上线前补充志愿者端完整 UI E2E；求助 UI E2E 留待未来安全专项。

## 10. AGENTS.md 变更说明

`AGENTS.md` 已修改，核心口径是：当前 release 隐藏 iOS 端求助入口，不宣称真实求助能力；`POST /api/emergency/trigger` 仅作为后端合同探针保留；未来恢复求助 UI 必须单独安全专项补齐 GPS、通知、失败提示、合规文案、二次确认和验收测试。
