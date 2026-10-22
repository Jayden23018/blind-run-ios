# AGENTS.md

AidRun / 助盲跑 的最高优先级工作契约。**不是产品头脑风暴，是硬约束。**

**仓库边界**：这是 AidRun 原生 iOS 前端仓库。它不包含、不维护、不构建、不部署后端代码。后端是外部服务，当前真实集成端点是 `https://47.114.113.171`。除非项目负责人在单独的变更里显式改变边界，否则不得加入服务端源码、数据库配置、服务端构建脚本或可本地运行的后端。

体积闸 `scripts/validate-agents-size.mjs`（≤ 16KB / 200 行）：细节进 skill，由来写块级 HTML 注释（不注入）。

<!--
2026-10-20（#482）从 51.9KB / 568 行压到闸门以内。去向表与实测见 docs/specs/482-agents-md-slimming.md。
节号 §0–§13 不变：guard.mjs、validate-guard.mjs、stop-checklist.mjs 与记忆文件都按「AGENTS.md 第 N 节」引用。
-->
## 0. 按需加载的规则（不在本文件，用到再读）

| Skill | 什么时候读 |
|---|---|
| `aidrun-auth` | 登录、验证码、JWT、角色、下单前置条件 |
| `aidrun-a11y-voice` | 盲人端 UI、VoiceOver、语音输入/播报、高德地图、定位与坐标系 |
| `aidrun-error-codes` | 处理 API 错误、写 TTS 错误播报、新增错误分支 |
| `aidrun-ship-check` | 实现完成、准备提交、准备宣称「做完了 / 测试通过」 |
| `aidrun-device-test` | 真机跑单测 / UI 测试、`device-test.sh` 报错（签名、code 74、证书、免费 App 上限等），或换团队 / Mac / 设备 |
| `aidrun-contract-sync` | 后端契约变了、pre-push 报「生成代码与契约不同步」、判契约新字段要不要接入 |
| `openspec-propose` | 要动的功能**行为会变**，而 `openspec/changes/` 下还没有对应变更时 |
| `openspec-archive-change` | 某个变更的 `tasks.md` 全打勾了 —— 归档是闭环终点，**别停在最后一步** |
| `swiftui-pro` | 写 / 审 SwiftUI 代码时（第三方，`.claude/skills/swiftui-pro/`） |
| `aidrun-order-and-sos` | 改订单状态流转、取消入口、派单 `respond`、通话磨合（`PENDING_INTRO_CALL`）页，或新增 / 改动任何求助 / SOS 入口与降级拨号 |

⚠️ `swiftui-pro` 说的「iOS 26 默认部署目标」「Swift 6.2+」不适用（本仓库 **iOS 16**）。**别改那个第三方文件**。

<!--
| `swiftui-pro` | 写 / 审 SwiftUI 代码时。**第三方**（Paul Hudson，MIT，`.claude/skills/swiftui-pro/`），装在 2026-09-02，见 `docs/research/claude-code-setup-for-ios-a11y-20260902.md` |

⚠️ `swiftui-pro` 的 `SKILL.md` 里写着「iOS 26 是新 App 的默认部署目标」「Target Swift 6.2 or later」——
**本仓库部署目标是 iOS 16**，那两句不适用，照它建议的新 API 写会编译不过。
它的 `references/accessibility.md` 自己是版本感知的（明确区分 iOS 18 及以前用 `@ScaledMetric`），
可以直接用。**不要改那个第三方文件**去迁就我们 —— 改了下次更新就冲突，约束写在这里。
-->
改界面前读 `docs/ui/design-direction.md`；实现界面或「按设计稿来」前读 `docs/ui/mockups/INDEX.md`（设计包放 `docs/ui/mockups/<主题>[-vN]/` 并加一行；「待确认」行先问）。写下「这个功能仓库里没有」之前读 `GLOSSARY.md`（领域词 ↔ 模块名），换同义词再搜。

<!--
**`docs/ui/design-direction.md` —— 改任何界面之前读一次。** 它回答「它该长什么样、为什么」
（`ui-handoff-ios.md` 回答「这页要有什么」，`ui-review-checklist.md` 回答「改完查什么」，三份不重叠）。
定死的几条：两端**跟随系统明暗**（盲人端不强制深色）、配色只用 `AppColors` **不新增强调色**、
两端差异只走密度/层级/文案语气三个轴**不分叉组件**、安全相关界面（进行中 / SOS / 位置上报）
在两端都退回最克制的一档。

**`docs/ui/mockups/INDEX.md` —— 实现某个界面、或用户说「按设计稿来」之前读一次。** 它回答「哪一版设计是
现行的、多份材料冲突时听谁的、实现落在哪、已知哪里没做到位」。**设计包不放 `~/Downloads`，放
`docs/ui/mockups/<主题>[-vN]/` 并在 INDEX 加一行**；状态为「待确认」的行不许自己挑一份就做，先问。
-->
<!--
**`GLOSSARY.md`（仓库根）—— 领域词 ↔ 模块名对照表。在写下「这个功能仓库里没有」之前必读一次，
换一组同义词再搜。** 它是 §1.4 的语义认知归档（配套记忆 `synonym-mismatch-fakes-a-missing-feature`）：
「注销」vs「删除账户」这一次错开，让一个功能齐全的模块被判成「需从头做」，checklist 作者与模型先后中招两次。
抓不成静态守卫 —— 机器分不出「搜不到」和「不存在」。
-->
## 1. 事故复盘规则（最重要的一条）

任何一个**已经犯过第二次**的错误，**或单次就耗掉三次以上尝试才对**的东西，必须落到下面四者之一，**不许只写进文档**：

1. 能被静态检查抓到 → `scripts/hooks/guard.mjs` 加一条守卫
2. 能被运行时检查抓到 → 加一条测试（优先 `blindRunTests/Fixtures/` 的真实响应回归）
3. 能被「该做没做」抓到 → 加进 Stop 钩子 `scripts/hooks/stop-checklist.mjs`
4. 三者都不能（纯语义认知）→ 写进项目记忆，并在本文件留一行索引

**「卡了很久」不必等到第二次**。**「反复查」和「反复错」同等对待**：同一事实第二次还要重查，就地写进本文件或对应 skill，带 `文件路径:行号`。

<!--
只写文档不算完成。文档挡不住重复犯错，这条规则的存在就是因为它已经被证明挡不住。

**「卡了很久」不必等到第二次。** 触发条件原本只有「犯过第二次」，于是第一次就试了六遍才对的东西
没人管 —— 代价已经付了，不落地下个会话从头再踩。Stop 钩子每会话问一次这件事
（`stop-checklist.mjs`，只在已有欠账时附带，不做独立触发条件）。

**「反复查」和「反复错」同等对待。** 同一个事实如果第二次还要重新 grep / 重读文件才能确定
（某个函数在哪、某个脚本叫什么、某个字段的真实类型），那不是记性问题，是事实没落地：
就地把它写进本文件或对应 skill，带上 `文件路径:行号`。上面 §1.1 那条 `guard.sh` → `guard.mjs`
就是例子 —— 文件早改名了，规则里没跟，于是每次都要重查一遍才发现引用是错的。
-->
**§1.4 症状 → 记忆**（正文只在记忆里）：

| 症状 | 记忆 |
|---|---|
| 单测构造硬件服务当「无定位」，真机竞态 | `location-service-test-seam-and-weak-viewmodel-deps` |
| 改盲人端 UI（低视力通道从没验收） | `low-vision-visual-channel-unaudited` |
| 崩在 `finishedPlaying:` `unrecognized selector` | `finishedplaying-crash-means-player-freed-not-delegate` |
| XCUITest `Failed to get matching snapshots: Timed out` | `snapshot-timeout-means-a-system-app-took-over` |
| 真机 `Test crashed with signal kill` | `ui-test-runner-needs-usb-not-wifi` |
| 写「失败时 `List` 末尾多一行字」的分支 | `claimed-fallback-may-not-exist-in-release` |
| 用 `tap()` 触发 `accessibilityRepresentation` 里的按钮 | `xcuitest-cannot-invoke-accessibility-actions` |
| overlay 背后的 `TabView` 仍在无障碍树里 | `hide-uikit-hosted-tree-from-accessibility` |
| `List` 行判「改不了字号」而截图里字放大了 | `list-rows-false-dynamic-type-audit` |
| 绕开既有红灯另写用例 / 安全控件只在长链中段断言 | `routed-around-red-light-must-be-filed` |
| UI 用例报 App 不在前台 / 面板高度 0 | `ui-test-device-orientation-is-not-fixed` |
| 审计报 `Contrast failed`（元素被屏幕边缘切掉一截）/ `Text clipped` 而颜色够、字完整 | `text-clipped-audit-trailing-fullwidth-paren` |
| 失败现场弹出「紧急呼叫」单 / 全屏遮罩没出来 | `ui-test-tap-lands-on-persistent-sos-bar` |
| 单测绿、真机 `EXC_BAD_ACCESS`，栈里有 `Builtin.ImplicitActor` thunk | `unannotated-async-closure-property-crashes-on-device` |
| 一行「改 padding 修不动」、文字不在任何对齐位置 | `flexible-spacer-steals-half-the-row` |
| 想照外部「AI 界面设计」建议改 UI | `web-design-advice-is-mostly-not-for-swiftui` |

<!--

> 2026-09-17 从长条目压成表。原因：这 7 条各自**存了三份**（本文件长版 + `MEMORY.md` 一行版 +
> 记忆文件全文），而本文件每个会话常驻、每一轮按 cache read 价重读一遍。
> 官方 context engineering 指南对这种形态的原话是
> "A common myth is that CLAUDE.md should be a central repository for every practice"。
> 依据与实测见 `docs/research/claude-code-token-optimization-20260917.md`。
-->
## 2. 源真相优先级

冲突时按此顺序：`AGENTS.md` → `plan.md` → `docs/` 下 `01` → `02` → `03` → `04` → `05` → `06` → `08` → `09` → `10`（产品需求 → … → AI 编码任务） → `openspec/changes/` 下的 OpenSpec 变更 → 遗留 Flutter 代码（只能当 UI / 行为参考，**不是**源真相）。

`docs/_archive-*.bak` 是已知有错的旧契约副本，**不得读取或复制**。

<!--
冲突时按此顺序：

1. `AGENTS.md`
2. `plan.md`
3. `docs/01-product-requirements.md` → `02-mvp-scope` → `03-user-stories` → `04-user-flows-and-state-machine` → `05-page-specs` → `06-data-model` → `08-ios-architecture` → `09-accessibility-and-voice-guidelines` → `10-ai-coding-tasks`
4. `openspec/changes/` 下的 OpenSpec 变更
5. 遗留 Flutter 代码只能当 UI / 行为参考，**不是**源真相
-->
## 3. 生产方向

- 本仓库只有 iOS 原生 App；后端是仓库外的云服务。
- Swift + SwiftUI 优先，必要时才桥接 UIKit；iOS 16+；MVVM。
- 所有真实 HTTP 走 `https://47.114.113.171`，所有真实 WebSocket 走 `wss://47.114.113.171`。**地址在 App 内不可配置，不得加入本地或占位的真实服务端地址。**
- REST + WebSocket 提供通知、派单、状态更新与位置上报；JWT Bearer Auth。
- 用高德地图与真机定位；TTS 用 `AVSpeechSynthesizer`，STT 用 iOS `Speech`。
- Mock 是**进程内**的前端测试设施，不发网络请求，且**永远不足以作为发布签核依据**。
- 上架包**只支持 iPhone**（`TARGETED_DEVICE_FAMILY = 1`）。发布验证必须在真机 `111`（iPhone）上跑。

生产短信、实名认证、管理员工具、路线导航、支付等能力不再被全局禁止，但仍必须先有需求、API 契约、实现计划与验收测试才能写代码。

<!--
  > 2026-09-08 从 `http` / `ws` 改过来。服务端 443 自 08-14 就绪（Let's Encrypt **IP 证书**，不需要域名、不需要备案），客户端此前一直没跟，实时位置与 SOS 全程明文。scheme 只有 `EnvironmentConfig.DemoCloud.baseURL` 一处，WS 由它推导；`Info.plist` 的 ATS 例外已随之删除，**别再加回来**。
-->
<!--
- 上架包**只支持 iPhone**（2026-09-30 负责人拍板，`TARGETED_DEVICE_FAMILY = 1`，仅主 App 与 LiveActivity 两个 target；测试 target 仍是 `1,2`，iPad 继续能当第二台开发机跑双机 E2E）。发布验证必须在真机 `111`（iPhone）上跑；`iPad Pro (2)` 不再是发布验证对象。
-->
## 4. 范围规则

一次只实现一个内聚模块；不得静默扩大范围；不得一次重写整个项目。新的生产能力必须记录文档、API 契约影响、测试计划与发布风险。若某能力需要后端改动，写下 `需要人工确认` 并把缺失的 API/行为说清楚，iOS 侧实现留在明确的契约后面。

## 5. 订单状态机

**只允许**这些状态：

```
PENDING_MATCH  PENDING_INTRO_CALL  SCHEDULED_CONFIRMED  PENDING_ACCEPT  IN_PROGRESS
DRIVER_EN_ROUTE  DRIVER_ARRIVED  COMPLETED  CANCELLED  REMATCHING  NO_VOLUNTEER
```

**禁用的遗留词汇**（`scripts/hooks/guard.mjs` 会拦）：

`submitted` · `contacted` · `expired` · `matching`（用 `PENDING_MATCH`） · `accepted`（用 `PENDING_ACCEPT`） · `arrived`（用 `DRIVER_ARRIVED`） · `emergency`（求助是独立事件，不是订单状态）

细节见 skill `aidrun-order-and-sos`，常驻的几条：

- 通话磨合没成**退回 `PENDING_MATCH`，不是 `REMATCHING`**。
- 盲人在 `DRIVER_EN_ROUTE` / `IN_PROGRESS` **不得**出现取消入口（后端 403 `ORDER_IN_PROGRESS`）；`DRIVER_ARRIVED` 的取消门槛只认 `earliestBlindCancelAt`，**客户端不自己拿到达时间加**。
- 🚩 `confirm-departure` 与 `en-route` **别合并**（会让位置互推提前几小时打开）。
- `DUPLICATE_ORDER` 只拦**时段冲突**，文案别再写「您有进行中的订单」。
- 发 `ACCEPT` 还是 `INTERESTED` **只认推送里的 `requiresIntroCall`**，客户端不许自己算；缺键降级发 `INTERESTED`。
- 掩码号码串**绝不能拼 `tel:`**；通话磨合页唯一允许拼 `tel:` 的来源是 `IntroCallView.dialableCounterpartPhone`。
- 磨合轮次与对方表态**客户端不许自己算、不许显示**（无声拒绝是设计）。

## 6. 求助 / SOS 红线

- 求助**不是**订单状态。`POST /api/emergency/trigger` 只记录事件，订单状态不变。
- **两端云端求助只在 `IN_PROGRESS` 开放**（产品决策，不是技术约束）。其余任何状态的入口一律降级为**本地拨号**（主紧急联系人 / **120** / 110），**绝不调 `/api/emergency/trigger`**；文案说清「App 不会代你发送求助」，弹窗标题叫「紧急呼叫」。
- **新增求助入口必须读那一端的判定，不许自己判状态**：`BlindHomeSOSMode.resolve` / `VolunteerOrderSOSMode.resolve`（现有三处入口见 skill）。
- **志愿者不得拥有「误触」按钮**（他可能就是威胁来源，后端 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`）；撤销权只在受助者本人（`PUT /api/emergency/{id}/cancel`）和客服。
- **App 永远不得宣称短信已发出、已送达，或家属/联系人已被通知**（短信事务后异步发，失败不回告）；用进行时文案覆盖后端 body，`联系人已收到短信` 不得进发布产物。
- 云端 SOS 必须带**新鲜的真实 GCJ-02 坐标**，拿不到就不发并**可见且可听**地告知；Mock / demo 坐标绝不上传；`allowsSubmissionWithoutLocation` 在产品/安全批准前保持 `false`。
- `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST` 只是高优先级的**信息性**提示，不改状态、不开求助 UI、不证明救援已派出。
- 求助必须二次确认，文案**逐字锁定**：

```text
是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。
```

<!--
- 志愿者端入口自 2026-07-31 起**已开放**。此前长期关闭的理由是「后端把事件挂在触发者身上，志愿者按下只会惊动自己、升级到自己的联系人」；后端 commit `a5ba523`（SOS-1）已把 `event.userId` 改为取订单的盲人方，用 `TriggerType.VOLUNTEER_BUTTON` 区分来源，该理由不再成立。
- **志愿者不得拥有「误触」按钮**：一对一陪跑里志愿者可能就是威胁来源，后端一律回 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`。撤销权只在受助者本人（`PUT /api/emergency/{id}/cancel`）和客服手里。
- **App 永远不得宣称短信已发出、已送达，或家属/联系人已被通知。** `EMERGENCY_CONTACT_NOTIFIED` 是在触发事务内同步推送的（`EmergencyService.java:370-373`），而短信是事务提交后异步发的（`EmergencyContactNotifier.java:60-62`）；短信失败只播给客服（`:126-135`），**从不回告盲人**。iOS 必须用自己的进行时文案覆盖后端的完成时态 body。字符串 `联系人已收到短信` 不得出现在发布产物中。
- 云端 SOS 请求必须带**新鲜的真实 GCJ-02 坐标**。拿不到就不发，并且**可见且可听**地告知用户。Mock / demo 坐标绝不上传。后端技术上接受的无 GPS 降级提交被 `EmergencyCoordinator.allowsSubmissionWithoutLocation` 关着，在产品/安全批准前保持 `false`。
- 后端的 `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST` 只是高优先级的**信息性**安全提示，不改订单状态、不启用求助 UI、不证明救援已派出。
-->
## 7. 外部 API 契约

- **契约唯一源在后端仓库** `/Users/mac/Downloads/demo`（`docs/api_spec.yaml`、`docs/websocket-protocol.md`），本仓库**不留副本**；`claude --add-dir` 挂载，**读它的 origin/main**（`git -C /Users/mac/Downloads/demo show origin/main:docs/api_spec.yaml`），别读工作区；契约错了去后端改。
- 需要后端拍板：`gh issue create --repo Jayden23018/blind-run-backend --label 待后端确认 --label handoff`；后端问我们的标 `待前端确认`。`demo/docs/handoff.md` 已冻结。
- 错误码语义见 skill `aidrun-error-codes`（机器可读 `docs/error-codes.json`）。

## 8. iOS 硬规则

- 原生 Swift + SwiftUI + MVVM，iOS 16+，网络用 `URLSession`。
- 网络请求集中在 `APIClient`；token / `currentUser` / `activeRole` 集中在 `AppState`。
- Token 存 Keychain（`blindRun/Core/KeychainTokenStore.swift`，`kSecAttrAccessibleAfterFirstUnlock`）。**不要把 access token 写进 `UserDefaults`。**
- View 只负责渲染与交互；ViewModel 持有状态并发起 API 调用。
- 开发期支持 Mock / Demo Cloud 切换；Demo 与 Production 构建锁定 Demo Cloud。
- **高德 key 只能来自本地配置文件，不得硬编码，不得提交真实 key**，并提供示例配置文件。
- 志愿者默认 `isAvailable = false`，必须手动打开才开始接单；关闭不影响当前订单。
- 接单前隐藏盲人联系方式、紧急联系人与敏感健康信息；**接单后展示掩码号码并给出拨号入口**。全号只进 `tel:`，不上屏、不进 `accessibilityLabel`（VoiceOver 外放）。渲染走 `maskPhone`，拨号走 `EmergencyDialer`。
- 接单前能给志愿者看什么，判据是**取值空间封不封闭**：枚举 / 布尔逐值判，**自由文本一律接单后**（闸 `disclosesBlindRunnerNotesToVolunteer`）。

<!--
- 接单前隐藏盲人联系方式、紧急联系人与敏感健康信息；**接单后展示掩码号码并给出拨号入口**。
  全号只进 `tel:`，不上屏、不进 `accessibilityLabel` —— VoiceOver 是外放的，念全号等于把盲人的
  号码广播给周围所有人（`f404de2` / 审计 F10）。渲染走 `EmergencyContactResponse.maskPhone`，
  拨号统一走 `EmergencyDialer.telURL/dial`。
  > 2026-08-22 改口径。原文是「接单后展示完整手机号」，与 `f404de2` 之后的实现直接冲突，
  > 而那次改动的隐私理由更硬 —— 保留掩码、改这句话。同批改了
  > `docs/technical-design-overview.md` 与 `docs/user-manual.md` 的同一条描述。
  **判据是字段的取值空间封不封闭，不是字段名听起来敏不敏感** —— 枚举 / 布尔（导盲犬、配速、
  引导方式）可以逐个判定「这个值给陌生人看行不行」，所以能留在接单前；**自由文本一律接单后**，
  因为同一个输入框里写「沿湖边跑道」和「我住院刚出来只能走平路」都自然，展示前分不出是哪一种。
  用途会漂移，类型不会。新增字段照这条判，不必每次重新讨论。
  实现闸：`RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`（穷举 switch，后端加状态时编译器会逼一次决策）。
-->
## 9. 冻结文件

**整文件冻结**：`Podfile` —— 架构排除设置与 pod 列表都在里面，没有安全的局部改法。`project.pbxproj` **不再冻结**（2026-10-03，#302）；团队号不写进文档，用时当场查（skill `aidrun-device-test`）。Bundle ID 为 `com.culiu-tech.blindrun`。

**任何构建相关文件都不得写入 `EXCLUDED_ARCHS`** —— 真机是唯一 XCTest 通道，模拟器因高德无 arm64-sim slice **永久不可用**，那条设置是这个事实的载体。确需在代码或注释里提及，行尾加 `guard:allow excluded-archs`。守卫规则 id 不抄进文档，取法见 `aidrun-ship-check` §八。

<!--
> 2026-08-06 从整文件冻结改为行级，2026-10-03 pbxproj 整体解冻（见上）。以下是当时行级冻结的由来：核对后发现原先给的两条理由只有一条落在 pbxproj 上（`DEVELOPMENT_TEAM`，12 处）；`EXCLUDED_ARCHS` 在 pbxproj 里出现 **0 次**，它只存在于 `Podfile:36`。整文件冻结的代价是连加一个 SPM 依赖都做不到，而「临时解锁、改完加回来」依赖人记得加回来 —— 第 1 节说的就是这种挡不住重复犯错的做法。
>
> 守卫在 `scripts/hooks/guard.mjs`，自测在 `scripts/validate-guard.mjs`（CI 与 pre-push 都跑）。
-->
## 10. 工作流

**开工前**

1. 先读 `AGENTS.md`
2. 再读相关 docs 与 OpenSpec
3. 判一次要不要派 subagent（判定表在全局 `~/.claude/CLAUDE.md`「委派」节）：定位/摘要/读日志外包，设计与编辑自己干

<!--
> 开场不用手查的那几条事实由 SessionStart 钩子 `scripts/hooks/session-context.mjs` 自动注入：
> 分支与脏文件数、未归档 OpenSpec 变更、后端契约可读性、pre-push 钩子装没装，以及
> **有独有提交却长期没跟进的远端分支**（领先 main 且落后 >30）。
> 全绿时不输出 —— 每轮都响的提醒会被无视，报缺口才有信息量。
> 自测 `scripts/validate-session-context.mjs`（CI 与 pre-push 都跑，条数当场看输出别写在这）：
> 配齐的机器永远走不到告警分支，坏了只会安静地不再提醒。
>
> 最后那条 2026-08-15 立：08-12 主线从旧上游切过来时，一批在途 PR 被孤儿化 ——
> **分支还在 `origin` 上，但主线没有对应的 PR**。于是「已有在途 PR #24」这类记录集体作废，
> 而没人会发现：`BlindRunHistoryView` 因此在 review 里挂着「已实现」三天，
> 连上线前检查单都把它列进了演示视频「可以放心拍」。判活口径见 PR #27。
> 同一次删掉了这里原有的 `fork` remote / 双推两条告警 —— §11 在 08-12 已改口径，
> 而 `install-git-hooks.sh` 末尾「推送目标：只推 origin」那段现在会主动清掉双推配置：照着那两条做会被安装脚本撤销。
-->
**实现中**

4. 一次只实现一个内聚模块
5. **行为有变时，实现前 `openspec/changes/` 下必须有对应变更**（先 `openspec list` 找，没有就用 `openspec-propose` 建，做完一项勾一项）；修 bug / 文案 / 重构不需要。
6. **改任何文件前，自己把要改的那部分读一遍** —— 探索可以外包，编辑不行。≥ 500 行别整读，用 `codegraph node <符号>` 再 `Read` 前后一屏。

<!--
   第一次改 App 源码时 `scripts/hooks/openspec-reminder.mjs` 会自动提醒一次（非阻断）。
6. **改任何文件前，自己把要改的那部分读一遍** —— 探索可以外包，编辑不行。
   「读一遍」按文件大小分两种，别对 3000 行的 View 整读：

   | 文件 | 怎么读 |
   |---|---|
   | < 500 行 | 直接 `Read` 整读 |
   | ≥ 500 行 | `codegraph node <符号>` 取那个函数体（带 `路径:行号` 的原文，可直接 Edit），再 `Read` 该行号前后一屏 |
   | 不知道符号叫什么 | 先 `codegraph explore "<问题>"` 或 `rg -n`，拿到符号名再 `node` |

   > 2026-09-17 实测 `BlindOrderStatusView.swift`（2912 行）：整读 **53712 tok** /
   > `explore` 8905 / `node` **1669** —— **32×**。而读进来的内容此后每一轮都按 cache read
   > 价重读，所以整读一次大文件的代价随会话长度累积，不是一次性的。
   > `node` 还会一次列出全部同名定义（实测 `keepWaiting` 6 处跨 4 文件），比 grep 更全。
   > ⚠️ 索引会在 codegraph 升级后**静默失效**（`status` 照显 ✓ 而 `Nodes: 0`）——
   > 怀疑时用一个真实 Swift 符号验收，别只看那行绿字。
-->
**收尾：三件事，缺一件都不算做完**

7. 跑测试、更新必要文档，按 `aidrun-ship-check` 输出；**变更任务全打勾就在同一 PR 里 `openspec archive <name> -y`**
8. **交接**走后端 issue：答掉的 `待前端确认` 评论后 close；新问题按 §7 开，一个问题一个，带文件行号或端点。契约变更直接改后端 spec
9. **commit**：`type: 描述`（feat/fix/refactor/docs/test/chore/perf/ci）。**不带 `Co-Authored-By`**
10. **push**（OpenSpec 闭环与第 9–10 步由钩子强制；用户说「先不提交」时回一句说明再停）

<!--
8. **交接**（后端仓库 GitHub Issues，2026-09-24 起替代 `demo/docs/handoff.md`）：
   - 本轮答掉的 `待前端确认` issue：`gh issue comment <n> --repo Jayden23018/blind-run-backend --body-file a.md` 写答复，再 `gh issue close`
   - 本轮新产生的、需要后端拍板的问题：`gh issue create --repo Jayden23018/blind-run-backend --label 待后端确认 --label handoff --body-file q.md`，
     一个问题一个 issue，正文带具体到文件行号或端点的上下文 + 明确的问题
   - 契约本身的变更不写这里 —— 直接改后端 `docs/api_spec.yaml`
   > 为什么换：handoff.md 涨到 15,630 行，6 个后端 PR 因「同一批答复做了两遍、要解 1000+ 行冲突」被关掉，
   > 09-16 后的 44 条待答项还落在「已归档」之后没人看见。冻结时 74 条未答项已迁成 issue #306–#379。
   > 详见后端 `docs/research/workflow-review-20260924.md` A6
9. **commit**：`type: 描述`（type 取 feat/fix/refactor/docs/test/chore/perf/ci）。**不带 `Co-Authored-By`**（`~/.claude/settings.json` 的 `includeCoAuthoredBy: false` 已全局关闭，不要手动加回来）
10. **push**

> OpenSpec 闭环（2026-09-23 立，项目负责人要求「提议 → 实现 → 归档」每次自动走完）也在同一个钩子里：
> 任务全打勾却没归档 → 硬拦；本轮改了 App 源码却没碰 `openspec/changes/` → 拦一次，
> 回一句「不改变行为」即可放行。判据只在 `openspec-reminder.mjs` 一处，本文件不抄。
>
> 第 9–10 步由 Stop 钩子 `scripts/hooks/stop-checklist.mjs` 强制：**本轮写过的文件没提交**或
> **领先 origin** 时拦住本次停止并列出欠账。一次停止只拦一次，用户说「先不提交」时
> 回一句说明再停即可，不会死循环。
-->
**这个仓库是共享 checkout**（`.git` 共用，**index 和 HEAD 都是**；`shared-checkout-guard.mjs` 会拦）。日常写法三条：

1. **暂存永远带显式路径** —— 不写 `git add -A` / `git commit -a` / `git commit --amend` / `git stash`。
2. **串联 git 命令永远用 `&&`，不用 `;`** —— 本仓库常年挂着十几二十个 worktree，`git checkout <被占着的分支>` **必然失败**，用 `;` 接的下一条会照常落在你当前分支上、零报错。腾开的办法：`git -C <占着它的 worktree> checkout --detach`。
3. **用某个版本覆盖工作区之前，目标路径必须没有未提交改动** —— `git checkout [<rev>] -- <path>` / `git checkout .` / `git restore` 不看工作区，覆盖掉就是真没了（工作区改动不进 reflog）。先 commit，或 `cp` 备份后在命令前加 `AIDRUN_ALLOW_DISCARD=1 `。09-16、09-27 各丢过一次（记忆 `red-check-on-an-uncommitted-baseline-destroys-the-work`）。

<!--
**这个仓库是共享 checkout**：前后端两个工作区都可能有同事在同时编辑，而 `.git` 整个是共用的
（**index 和 HEAD 都是**，记忆 `shared-checkout-concurrent-colleague-edits`）。
2026-08-16 因此把一笔编译不过的 WIP 推进了 PR，还改写掉了同事的一条提交，全程零报错。
`scripts/hooks/shared-checkout-guard.mjs`（PreToolUse / Bash）拦四类，
**当且仅当**它们会波及别人的东西或丢掉未提交的改动 —— 自己分支上 amend、暂存区里全是自己写的文件、
还原一个干净的文件，都放行。
-->
<!--
> 三条判据各自为什么长这样、两次误报怎么修的，写在两个钩子文件自己的头注释里
> （改它们的人才需要）。自测 `scripts/validate-stop-checklist.mjs` 与
> `scripts/validate-shared-checkout-guard.mjs`，CI 与 pre-push 都跑；**条数当场看输出，
> 别写在这**（理由同 §9：09-02 核对时这里写的 9 条实际已是 11 条）。
-->
## 11. 验证命令

- 命令、跑多大范围、读后端的 5 条门禁见 skill `aidrun-ship-check`（§二 / §六 / §七）；装一次 `scripts/install-git-hooks.sh`。
- **CI 跑不了任何 XCTest**，单测与 UI 测试一律真机 `scripts/device-test.sh`。**默认只跑覆盖本次改动的 suite**，不是全量。
- **零执行不是通过**：`passed=0 failed=0` 一律当失败查。**编译通过不等于测试通过，永远不许把没执行过的测试写成通过。**
- 🔴 **一次同时改两端的功能，必须后端先合，iOS 才推得上去**。⛔ 别用 `AIDRUN_SKIP_PREPUSH=1` 绕 —— 那一次跳过全部 5 道门禁。

## 12. 联网调研只落一个地方

唯一位置 `docs/research/`，唯一索引 `docs/research/INDEX.md`：

1. **开搜前整份读 INDEX.md**，按「复核触发条件」判旧结论还作不作数，没触发就直接用。
2. 新一轮只搜**表里缺的那一段**。
3. 调研完落 `docs/research/{topic}-{YYYYMMDD}.md`，**并回写 INDEX.md 一行**（日期 / 问题 / 一句话结论 / 复核触发条件 / 报告）。被否掉的方案同样留一行。
4. 「上次 / 之前」或可能在别的仓库的，先用 `search_session_transcripts`（跨项目，🔴 **只有 30 天**；查询词用错误签名、具体数字这类只在对话里出现的）。

<!--

1. **开搜前整份读 INDEX.md**，按「复核触发条件」列判旧结论还作不作数。没触发就直接用，不要重搜。
2. 新一轮只搜**表里缺的那一段**，不是把整个问题重来一遍。
3. 调研完落 `docs/research/{topic}-{YYYYMMDD}.md`，**并回写 INDEX.md 一行**（日期 / 问题 /
   一句话结论 / 复核触发条件 / 报告，五列齐全）。不回写等于没做 —— 下次搜不到，原样重跑。

4. **索引只管本仓库落过盘的东西。** 用户说「上次 / 之前 / 我们讨论过 / 那个报错」，
   或要找的东西可能在**别的仓库**（契约类常在后端 `demo`），先用 `search_session_transcripts`
   —— 它跨项目，返回 `cwd` 可区分。两条判据缺一不可：
   - 🔴 **只有 30 天**（`cleanupPeriodDays` 默认值，静默清理）。过期的原始会话**彻底消失** ⇒
     长期记忆只可能在落盘产物里，这正是第 3 条存在的理由。
   - ⚠️ **查询词要用只可能出现在对话里的**：错误签名、具体数字、命令输出片段。
     用 `AGENTS.md` / `INDEX.md` / `MEMORY.md` 里有的词，搜回来的全是每会话注入的**回声**
     （实测搜 `MAMultiPointOverlay` 五条 snippet 逐字相同，搜
     `Test crashed with signal kill` 四条各不相同且精准）。

   2026-09-20 立此条，当轮即生效：靠它捞出后端仓库 09-19 那份
   `codebase-comprehension-for-defense-20260919.md`，省掉一轮重复调研。
   依据见 `docs/research/claude-code-memory-and-session-archival-20260920.md` §2。

被否掉的方案同样留一行：「试过 X 因为 Y 放弃」跟「选了 Z」一样值钱，且更容易被忘。

> 强制在 `scripts/hooks/research-log.mjs`（走 §1.1 + §1.3）：PreToolUse 在联网工具调用前把整份索引
> 灌回给模型（第 1 条）；Stop 钩子发现本轮联网过但 `docs/research/` 一个字节没动就拦（第 3 条）。
> 只是查一个 API 签名、不构成调研的，回一句说明再停。
> 自测 `scripts/validate-research-log.mjs`（CI 与 pre-push 都跑；条数当场看输出，别写在这 —— 理由同 §9，
> 09-02 核对时这里写的 7 条实际已是 10 条）。
> **第 4 条抓不成钩子**（机器分不出「该召回却没召回」），走 §1.4 的记忆归档：
> `cross-session-recall-channels-and-shelf-life`。
>
> 位置约定本来就写在 skill `tech-decision-research` 里，但 skill 不被显式调用就不生效 ——
> 于是 `docs/research/` 建了两份报告却一直没有索引。这条是把约定接上强制。
-->
## 13. 成体系的 review 也只落一个地方

唯一位置 `docs/review/`、索引 `docs/review/INDEX.md`，规则同 §12（开新 review 前整份读索引，落 `{topic}-{YYYYMMDD}.md` 并回写一行）。research 记「外面怎么做」，review 记「我们做成什么样」（带 `文件:行号`），竞品事实不写进 review。

<!--

与 §12 的分工：`docs/research/` 记「外面是怎么做的」（联网事实，带来源与核实日期）；
`docs/review/` 记「我们做成了什么样」（对着代码与契约的判断，带 `文件:行号`）。
一次 review 引用一次 research 是常态，反过来不成立 —— 竞品事实不要写进 review，两处都写会漂移。

> ⚠️ 这条**没有 hook 强制**，`research-log.mjs` 只管联网调研。漏过第二次就按 §1.1 落成守卫。
>
> 2026-08-12 立此条：`frontend-backend-alignment-review-20260812.md` 原本躺在 `docs/` 根目录，
> 与 20 个同级文档混在一起 —— 下一次 review 既不会先读它，也不会挨着它落盘。已迁入 `docs/review/`。
-->
