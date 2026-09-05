# AGENTS.md

AidRun / 助盲跑 的最高优先级工作契约。**不是产品头脑风暴，是硬约束。**

**仓库边界**：这是 AidRun 原生 iOS 前端仓库。它不包含、不维护、不构建、不部署后端代码。后端是外部服务，当前真实集成端点是 `http://47.114.113.171`。除非项目负责人在单独的变更里显式改变边界，否则不得加入服务端源码、数据库配置、服务端构建脚本或可本地运行的后端。

## 0. 按需加载的规则（不在本文件，用到再读）

| Skill | 什么时候读 |
|---|---|
| `aidrun-auth` | 登录、验证码、JWT、角色、下单前置条件 |
| `aidrun-a11y-voice` | 盲人端 UI、VoiceOver、语音输入/播报、高德地图、定位与坐标系 |
| `aidrun-error-codes` | 处理 API 错误、写 TTS 错误播报、新增错误分支 |
| `aidrun-ship-check` | 实现完成、准备提交、准备宣称「做完了 / 测试通过」。**全部验证命令、「跑多大范围」判据、读后端那 5 条门禁在哪跑，都在这里** |
| `aidrun-contract-sync` | 后端契约变了、pre-push 报「生成代码与契约不同步」、判契约新字段要不要接入 |
| `aidrun-hooks-and-guards` | 被钩子或守卫拦住、要改构建相关文件、要改钩子本身、要落一份成体系的 review |

**`CONTEXT.md`（仓库根）—— 领域词 ↔ 模块名对照表。在写下「这个功能仓库里没有」之前必读一次，
换一组同义词再搜。** 它是 §1.4 的语义认知归档（配套记忆 `synonym-mismatch-fakes-a-missing-feature`）：
「注销」vs「删除账户」这一次错开，让一个功能齐全的模块被判成「需从头做」，checklist 作者与模型先后中招两次。
抓不成静态守卫 —— 机器分不出「搜不到」和「不存在」。

## 1. 事故复盘规则（最重要的一条）

任何一个**已经犯过第二次**的错误，**或单次就耗掉三次以上尝试才对**的东西，必须落到下面四者之一，**不许只写进文档**：

1. 能被静态检查抓到 → `scripts/hooks/guard.mjs` 加一条守卫
2. 能被运行时检查抓到 → 加一条测试（优先 `blindRunTests/Fixtures/` 的真实响应回归）
3. 能被「该做没做」抓到 → 加进 Stop 钩子 `scripts/hooks/stop-checklist.mjs`
4. 三者都不能（纯语义认知）→ 写进项目记忆，并在本文件留一行索引

只写文档不算完成。文档挡不住重复犯错，这条规则的存在就是因为它已经被证明挡不住。

**「卡了很久」不必等到第二次。** 触发条件原本只有「犯过第二次」，于是第一次就试了六遍才对的东西
没人管 —— 代价已经付了，不落地下个会话从头再踩。Stop 钩子每会话问一次这件事
（`stop-checklist.mjs`，只在已有欠账时附带，不做独立触发条件）。

**「反复查」和「反复错」同等对待。** 同一个事实如果第二次还要重新 grep / 重读文件才能确定
（某个函数在哪、某个脚本叫什么、某个字段的真实类型），那不是记性问题，是事实没落地：
就地把它写进本文件或对应 skill，带上 `文件路径:行号`。上面 §1.1 那条 `guard.sh` → `guard.mjs`
就是例子 —— 文件早改名了，规则里没跟，于是每次都要重查一遍才发现引用是错的。

**已归档的语义认知（§1.4）索引** —— 全文在项目记忆里，**这里只留「什么时候该去读它」**。
（正文曾在这里抄过第二份，共 60 行；那正是 §9 说的「制造一个必然过期的第二源」。）

| 撞上这个 | 去读这条记忆 |
|---|---|
| 单测要构造「拿不到定位」的状态（裸 `LocationService()` 是竞态，真机几毫秒就回调） | `location-service-test-seam-and-weak-viewmodel-deps` |
| 改盲人端 UI —— **要问两遍**：VoiceOver 用户怎么样？不开读屏、AX5 字号、横屏、户外的低视力用户怎么样？ | `low-vision-visual-channel-unaudited` |
| 崩在 `finishedPlaying:`，或互不相关的用例随机崩 | `finishedplaying-crash-means-player-freed-not-delegate` |
| XCUITest 报 `Failed to get matching snapshots` | `snapshot-timeout-means-a-system-app-took-over` |
| 真机报 `Test crashed with signal kill` | `ui-test-runner-needs-usb-not-wifi`（第七种） |
| 写「失败时在列表末尾多一行字」的分支 —— 那一行可能根本不在第一屏，等于没有反馈 | `claimed-fallback-may-not-exist-in-release` |

## 2. 源真相优先级

冲突时按此顺序：

1. `AGENTS.md`
2. `plan.md`
3. `docs/01-product-requirements.md` → `02-mvp-scope` → `03-user-stories` → `04-user-flows-and-state-machine` → `05-page-specs` → `06-data-model` → `08-ios-architecture` → `09-accessibility-and-voice-guidelines` → `10-ai-coding-tasks`
4. `openspec/changes/` 下的 OpenSpec 变更
5. 遗留 Flutter 代码只能当 UI / 行为参考，**不是**源真相

`docs/_archive-*.bak` 是已知有错的旧契约副本，**不得读取或复制**。

## 3. 生产方向

- 本仓库只有 iOS 原生 App；后端是仓库外的云服务。
- Swift + SwiftUI 优先，必要时才桥接 UIKit；iOS 16+；MVVM。
- 所有真实 HTTP 走 `http://47.114.113.171`，所有真实 WebSocket 走 `ws://47.114.113.171`。**地址在 App 内不可配置，不得加入本地或占位的真实服务端地址。**
- REST + WebSocket 提供通知、派单、状态更新与位置上报；JWT Bearer Auth。
- 用高德地图与真机定位；TTS 用 `AVSpeechSynthesizer`，STT 用 iOS `Speech`。
- Mock 是**进程内**的前端测试设施，不发网络请求，且**永远不足以作为发布签核依据**。
- 发布验证必须在真机 `111` 与 `iPad Pro (2)` 上跑。

生产短信、实名认证、管理员工具、路线导航、支付等能力不再被全局禁止，但仍必须先有需求、API 契约、实现计划与验收测试才能写代码。

## 4. 范围规则

一次只实现一个内聚模块；不得静默扩大范围；不得一次重写整个项目。新的生产能力必须记录文档、API 契约影响、测试计划与发布风险。若某能力需要后端改动，写下 `需要人工确认` 并把缺失的 API/行为说清楚，iOS 侧实现留在明确的契约后面。

## 5. 订单状态机

**只允许**这些状态：

```
PENDING_MATCH  PENDING_INTRO_CALL  PENDING_ACCEPT  IN_PROGRESS  DRIVER_EN_ROUTE
DRIVER_ARRIVED  COMPLETED  CANCELLED  REMATCHING  NO_VOLUNTEER
```

**禁用的遗留词汇**（`scripts/hooks/guard.mjs` 会拦）：

`submitted` · `contacted` · `expired` · `matching`（用 `PENDING_MATCH`） · `accepted`（用 `PENDING_ACCEPT`） · `arrived`（用 `DRIVER_ARRIVED`） · `emergency`（求助是独立事件，不是订单状态）

正常流转：

```
PENDING_MATCH → PENDING_INTRO_CALL → PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED → IN_PROGRESS → COMPLETED
```

通话磨合没成时**退回 `PENDING_MATCH`，不是 `REMATCHING`**：

```
PENDING_INTRO_CALL → PENDING_MATCH（本轮没成，换下一位候选人）
PENDING_INTRO_CALL → NO_VOLUNTEER（已满 3 轮 app.intro-call.max-rounds）
```

取消流转：

```
PENDING_MATCH / PENDING_INTRO_CALL / PENDING_ACCEPT → CANCELLED（盲人 token）
PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS → REMATCHING（志愿者 token）
REMATCHING → CANCELLED（只能盲人 token）
```

- 取消端点 `POST /api/orders/{orderId}/cancel`，无需请求体。
- 盲人只能取消 `PENDING_MATCH` / `PENDING_INTRO_CALL` / `PENDING_ACCEPT` / `REMATCHING`；`IN_PROGRESS` 期间**不得**展示取消入口。
- 志愿者只能取消 `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`。**`PENDING_INTRO_CALL` 不在内** —— 那一态他还没接单，退出的方式是表态「不合适」，不是取消订单。
- `REMATCHING` 是已接单志愿者取消后进入的状态，此后只能盲人用自己的 token 取消 —— 那个志愿者已不是订单参与者。
- 状态流转端点统一 `POST /api/orders/{orderId}/{action}`：`respond`（体带 `action = ACCEPT|DECLINE|INTERESTED`）、`en-route`、`arrived`、`start-service`、`finish`。
- 下单起始时间距今不足 30 分钟必须返回 `APPOINTMENT_TOO_SOON`（`EnvironmentConfig.minimumBookingLeadMinutes = 30`）。**没有「现在就跑」。**
- 订单列表用分页响应 `PagedOrderResponse`；盲人订单详情每 5 秒轮询作为 WebSocket 兜底。
- WebSocket 端点：`/ws/blind?token={jwt}` 与 `/ws/volunteer?token={jwt}`。

### PENDING_INTRO_CALL（接单前通话磨合，后端迁移 `0031`）

志愿者对派单选「有意向，想先聊聊」后进入。订单锁给这个候选人，双方打完电话各自表态，都说合适才转 `PENDING_ACCEPT`。

- **这一态还没有志愿者接单**。后端 `order.volunteer` 恒为 null，候选人只存在于 `dispatchCurrentVolunteerId`。直接后果：志愿者调 `GET /api/orders/{orderId}` 会被判 403，他这一刻**拿不到订单详情**，通话页只能吃派单推送 + `GET /api/orders/{orderId}/intro-call`。`IntroCallView` 里的 `startAddress` / `plannedStartTime` 就是为这个冷启动恢复存在的，别当冗余字段删掉。
- 专用端点四条：`GET /intro-call`（通话页数据）、`POST /intro-call/decision`（表态 `ACCEPT|DECLINE`）、`POST /intro-call/unreachable`（志愿者报「没打通」，**盲人侧没有对应端点**）、`POST /intro-call/notify-incoming`（盲人拨号前提醒志愿者）。
- **号码单向**：盲人拿到明文号可直拨，志愿者只拿到掩码串用于认人。掩码串**绝不能拼 `tel:`** —— `EmergencyDialer` 只取数字位，`138****1234` 会拨成空号且界面看不出异常（2026-08-11 的真实缺陷）。唯一允许拼 `tel:` 的来源是 `IntroCallView.dialableCounterpartPhone`。
- **无声拒绝**：响应体不含对方的表态、也不含轮次进度，这不是后端漏字段。只有一方表态时后端**不通知**对方；「这是第 3 位志愿者」本身就是在告诉盲人前两位没成。客户端**也不许自己算**轮次再显示（例如按收到几次 `INTRO_CALL_CONTINUE` 计数）。
- 盲人的自由文本在这一态**不可见**（`disclosesBlindRunnerNotesToVolunteer` 判 false，见 §8）：一单最多聊 3 位候选人，展示等于交给这一单碰到的每一个人。
- 窗口 20 分钟（`app.intro-call.window-minutes`，**别硬编码**）；退回时轮次 +1，满 3 轮（`max-rounds`）转 `NO_VOLUNTEER`。
- ⚠️ **客户端目前对陌生人一律发 `INTERESTED`**：判据字段 `requiresIntroCall` 只挂在 `AvailableOrderResponse` 上，而本 App 不调 `GET /api/orders/available`，唯一派单通道 `NEW_ORDER` 推送里没有它。自己算也不行（「这两人磨合成功过没有」客户端无从得知）。代价是熟人也要多聊一次。**已投 `demo/docs/handoff.md`，字段搬到推送上之前不要自作主张加 `.accept` 分支。**
- 反过来也不能假设「陌生人必然被拦」：距开跑时间已塞不下一轮通话窗口时后端**刻意放行** `ACCEPT`（退化成直接接单）。

## 6. 求助 / SOS 红线

- 求助**不是**订单状态。`POST /api/emergency/trigger` 只记录事件，订单状态不变。
- **两端入口都只在 `IN_PROGRESS` 开放**（`EmergencyTriggerRequest` 必须带 `orderId`）。
- 盲人首页那条常驻求助条是**唯一的例外形态，且它不是例外**：`IN_PROGRESS` 时走上面这条云端链路，
  其余任何状态一律降级为**本地拨号**（主紧急联系人 / 110），**绝不调 `POST /api/emergency/trigger`**。
  降级分支的文案必须说清「App 不会代你发送求助」—— 按下去只有拨号音，不说清等同于让盲人以为求助已发出。
  判定在 `BlindHomeSOSMode.resolve`（`blindRun/Safety/SafetyModule.swift`），
  用例 `EmergencySOSTests.testHomeSOSBarOnlyUsesTheCloudPathDuringInProgress` 逐状态钉住。
- 志愿者端入口自 2026-07-31 起**已开放**。此前长期关闭的理由是「后端把事件挂在触发者身上，志愿者按下只会惊动自己、升级到自己的联系人」；后端 commit `a5ba523`（SOS-1）已把 `event.userId` 改为取订单的盲人方，用 `TriggerType.VOLUNTEER_BUTTON` 区分来源，该理由不再成立。
- **志愿者不得拥有「误触」按钮**：一对一陪跑里志愿者可能就是威胁来源，后端一律回 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`。撤销权只在受助者本人（`PUT /api/emergency/{id}/cancel`）和客服手里。
- **App 永远不得宣称短信已发出、已送达，或家属/联系人已被通知。** `EMERGENCY_CONTACT_NOTIFIED` 是在触发事务内同步推送的（`EmergencyService.java:370-373`），而短信是事务提交后异步发的（`EmergencyContactNotifier.java:60-62`）；短信失败只播给客服（`:126-135`），**从不回告盲人**。iOS 必须用自己的进行时文案覆盖后端的完成时态 body。字符串 `联系人已收到短信` 不得出现在发布产物中。
- 云端 SOS 请求必须带**新鲜的真实 GCJ-02 坐标**。拿不到就不发，并且**可见且可听**地告知用户。Mock / demo 坐标绝不上传。后端技术上接受的无 GPS 降级提交被 `EmergencyCoordinator.allowsSubmissionWithoutLocation` 关着，在产品/安全批准前保持 `false`。
- 后端的 `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST` 只是高优先级的**信息性**安全提示，不改订单状态、不启用求助 UI、不证明救援已派出。
- 求助必须二次确认，文案**逐字锁定**：

```text
是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。
```

## 7. 外部 API 契约

- **契约唯一源在后端仓库** `/Users/mac/Downloads/demo`：REST 看 `docs/api_spec.yaml`，WebSocket 看 `docs/websocket-protocol.md`。本仓库**不留副本**。
- 契约工作用 `claude --add-dir /Users/mac/Downloads/demo` 挂载。契约文档本身错了就去后端仓库改，不要在这里存第二份。
- 需要后端拍板的问题写进 `demo/docs/handoff.md` 的「待后端确认」。
- 错误码语义见 skill `aidrun-error-codes`；机器可读版本是 `docs/error-codes.json`。

## 8. iOS 硬规则

- 原生 Swift + SwiftUI + MVVM，iOS 16+，网络用 `URLSession`。
- 网络请求集中在 `APIClient`；token / `currentUser` / `activeRole` 集中在 `AppState`。
- Token 存 Keychain（`blindRun/Core/KeychainTokenStore.swift`，`kSecAttrAccessibleAfterFirstUnlock`）。**不要把 access token 写进 `UserDefaults`。**
- View 只负责渲染与交互；ViewModel 持有状态并发起 API 调用。
- 开发期支持 Mock / Demo Cloud 切换；Demo 与 Production 构建锁定 Demo Cloud。
- **高德 key 只能来自本地配置文件，不得硬编码，不得提交真实 key**，并提供示例配置文件。
- 志愿者默认 `isAvailable = false`，必须手动打开才开始接单；关闭不影响当前订单。
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

## 9. 冻结文件

- **`Podfile` 整文件冻结** —— 架构排除设置与 pod 列表都在里面，没有安全的局部改法。
- **`blindRun.xcodeproj/project.pbxproj` 行级冻结** —— 文件可以改（例如加 SPM 依赖），
  但**不得触及 `DEVELOPMENT_TEAM`**。写死的 `R6PH2TFB3Q` 是原开发者的团队号，
  命令行传 `DEVELOPMENT_TEAM=ZW39BS8NXT` 覆盖。
- **任何构建相关文件都不得写入 `EXCLUDED_ARCHS`** —— 真机是唯一 XCTest 通道，模拟器因高德无
  arm64-sim slice **永久不可用**，那条设置是这个事实的载体。确需在代码或注释里提及，
  行尾加 `guard:allow excluded-archs`。

守卫 `scripts/hooks/guard.mjs` 管的不止这三条。**规则清单与用例数一律不写在文档里，当场取** ——
取法、判据来历、以及 2026-08-11 那次「写『以 X 为准』又抄了一份 X，结果漏三条」的教训，
见 skill `aidrun-hooks-and-guards`。

## 10. 工作流

**开工前**

1. 先读 `AGENTS.md`
2. 再读相关 docs 与 OpenSpec
3. 判一次这活要不要派 subagent —— 判定表在全局 `~/.claude/CLAUDE.md` 的「委派」节，**本文件不留副本**（理由同 §7：两份会漂移）。一句话版：定位/摘要/读日志外包，设计与编辑自己干

**实现中**

4. 一次只实现一个内聚模块
5. 行为有变时，实现前先确认对应 spec
6. **改任何文件前，自己完整读一遍那个文件** —— 探索可以外包，编辑不行

**收尾：三件事，缺一件都不算做完**

7. 跑测试、更新必要文档，按 skill `aidrun-ship-check` 的格式输出
8. **同步 handoff**（`demo/docs/handoff.md`）：本轮答掉的 `- [ ]` 改 `- [x]`，答案写在 `答：` 后面，
   **不删除已答条目**（历史是决策记录）；新产生的待拍板问题追加到「待后端确认」，
   每条带日期 / 提问方 / 具体到 `文件:行号` 或端点的上下文 / 明确的问题。
   契约本身的变更不写这里 —— 直接改后端 `docs/api_spec.yaml`。
   ⚠️ 全文 9800+ 行，**只读末尾最新几条**（`tail -80`）或 `grep -n "^- \[ \]"` 定位未答项，**不要整读**。
9. **commit**：`type: 描述`（type 取 feat/fix/refactor/docs/test/chore/perf/ci）。**不带 `Co-Authored-By`**
10. **push**

> 本仓库有 6 个钩子兜着这套流程：`session-context`（开场注入事实）、`stop-checklist`（第 9–10 步强制）、
> `shared-checkout-guard`（拦住会捎带同事改动的暂存命令）、`research-log`（调研落盘）、
> `guard`（静态守卫）、`transcript`（供其余钩子取本轮写过的路径）。
> **被哪个拦住了、它的判据为什么长这样、怎么自测 → skill `aidrun-hooks-and-guards`。**

## 11. 验证命令

**完整清单、「跑多大范围」的判据、读后端那 5 条门禁在哪跑 → skill `aidrun-ship-check`。**
每天真正要记住的只有三条命令和三条判据：

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
# 真机（唯一 XCTest 通道），默认只跑覆盖改动的 suite
scripts/device-test.sh -only-testing:blindRunTests/<你改的那个 suite>
# 每台机器装一次，把读后端契约的 5 条门禁钉在 push 前
scripts/install-git-hooks.sh
```

- **默认只跑覆盖本次改动的 suite。** 全量只留给「全 App 唯一出口 / 共享单例 / 全局配置」
  （`SystemSpeechAudioSession`、`APIClient`、`AppState`）—— 这类影响面按符号搜不出来。
- **零执行不是通过。** `passed=0 failed=0` 一律当失败查 —— 设备锁屏、`-only-testing` 名字打错、
  测试目标没编出来，都长这样。
- **CI 跑不了任何 XCTest**（高德无 arm64-sim slice，模拟器通道永久不可用）。
  **编译通过不等于测试通过。永远不许把没执行过的测试写成通过。**

## 12. 联网调研只落一个地方

唯一位置 `docs/research/`，唯一索引 `docs/research/INDEX.md`。规则三条：

1. **开搜前整份读 INDEX.md**，按「复核触发条件」列判旧结论还作不作数。没触发就直接用，不要重搜。
2. 新一轮只搜**表里缺的那一段**，不是把整个问题重来一遍。
3. 调研完落 `docs/research/{topic}-{YYYYMMDD}.md`，**并回写 INDEX.md 一行**（日期 / 问题 /
   一句话结论 / 复核触发条件 / 报告，五列齐全）。不回写等于没做 —— 下次搜不到，原样重跑。

被否掉的方案同样留一行：「试过 X 因为 Y 放弃」跟「选了 Z」一样值钱，且更容易被忘。

⚠️ **本仓库的索引只盖本仓库。** 跨端的问题（模型与工具链用法、契约口径、发布流程）后端仓库
`demo/docs/research/` 也有一份索引，**开搜前两边都要扫**。2026-09-06 就因为只扫了这边，
「Opus 5 怎么用」被两边在同一天各查了一遍 —— 这正是本节第 1 条要防的事，只是它当时没跨仓库。
钩子已按 §1.1 改成两份索引都灌。

> 由 `scripts/hooks/research-log.mjs` 强制（第 1 条灌索引、第 3 条拦住不落盘的停止）。
> 细节与来历见 skill `aidrun-hooks-and-guards`。

## 13. 成体系的 review 也只落一个地方

唯一位置 `docs/review/`，唯一索引 `docs/review/INDEX.md`，规则与 §12 同构：开新 review 前整份读索引，
review 完落 `docs/review/{topic}-{YYYYMMDD}.md` 并回写索引一行。

分工：`docs/research/` 记「外面是怎么做的」（联网事实，带来源与核实日期）；
`docs/review/` 记「我们做成了什么样」（对着代码与契约的判断，带 `文件:行号`）。
一次 review 引用一次 research 是常态，反过来不成立 —— 竞品事实不要写进 review，两处都写会漂移。

> ⚠️ 这条**没有 hook 强制**，`research-log.mjs` 只管联网调研。漏过第二次就按 §1.1 落成守卫。
> 来历见 skill `aidrun-hooks-and-guards`。
