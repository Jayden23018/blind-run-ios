# AGENTS.md

AidRun / 助盲跑 的最高优先级工作契约。**不是产品头脑风暴，是硬约束。**

**仓库边界**：这是 AidRun 原生 iOS 前端仓库。它不包含、不维护、不构建、不部署后端代码。后端是外部服务，当前真实集成端点是 `https://47.114.113.171`。除非项目负责人在单独的变更里显式改变边界，否则不得加入服务端源码、数据库配置、服务端构建脚本或可本地运行的后端。

## 0. 按需加载的规则（不在本文件，用到再读）

| Skill | 什么时候读 |
|---|---|
| `aidrun-auth` | 登录、验证码、JWT、角色、下单前置条件 |
| `aidrun-a11y-voice` | 盲人端 UI、VoiceOver、语音输入/播报、高德地图、定位与坐标系 |
| `aidrun-error-codes` | 处理 API 错误、写 TTS 错误播报、新增错误分支 |
| `aidrun-ship-check` | 实现完成、准备提交、准备宣称「做完了 / 测试通过」 |
| `aidrun-contract-sync` | 后端契约变了、pre-push 报「生成代码与契约不同步」、判契约新字段要不要接入 |
| `openspec-propose` | 要动的功能**行为会变**，而 `openspec/changes/` 下还没有对应变更时 |
| `openspec-archive-change` | 某个变更的 `tasks.md` 全打勾了 —— 归档是闭环终点，**别停在最后一步** |
| `swiftui-pro` | 写 / 审 SwiftUI 代码时。**第三方**（Paul Hudson，MIT，`.claude/skills/swiftui-pro/`），装在 2026-09-02，见 `docs/research/claude-code-setup-for-ios-a11y-20260902.md` |

⚠️ `swiftui-pro` 的 `SKILL.md` 里写着「iOS 26 是新 App 的默认部署目标」「Target Swift 6.2 or later」——
**本仓库部署目标是 iOS 16**，那两句不适用，照它建议的新 API 写会编译不过。
它的 `references/accessibility.md` 自己是版本感知的（明确区分 iOS 18 及以前用 `@ScaledMetric`），
可以直接用。**不要改那个第三方文件**去迁就我们 —— 改了下次更新就冲突，约束写在这里。

**`docs/ui/design-direction.md` —— 改任何界面之前读一次。** 它回答「它该长什么样、为什么」
（`ui-handoff-ios.md` 回答「这页要有什么」，`ui-review-checklist.md` 回答「改完查什么」，三份不重叠）。
定死的几条：两端**跟随系统明暗**（盲人端不强制深色）、配色只用 `AppColors` **不新增强调色**、
两端差异只走密度/层级/文案语气三个轴**不分叉组件**、安全相关界面（进行中 / SOS / 位置上报）
在两端都退回最克制的一档。

⚠️ 外面讲「AI 界面设计」的资料**绝大多数是 Web 语境，对本仓库有害**。最典型的一条：
Anthropic 官方 cookbook 的 `<frontend_aesthetics>` 块逐字要求避开
`Overused font families (Inter, Roboto, Arial, system fonts)` —— 在 iOS 上系统字体就是
**San Francisco**，Dynamic Type 的整张字号表是为它设计的，`AppFonts` 全部基于它，
照做等于在盲人 App 上主动破坏 Dynamic Type。判据见记忆
`web-design-advice-is-mostly-not-for-swiftui` 与 `docs/research/ai-ui-design-workflow-for-swiftui-20260907.md`。
提醒已落成钩子 `scripts/hooks/design-direction-reminder.mjs`（PreToolUse，动 SwiftUI 视图时每会话响一次；
自测 `scripts/validate-design-reminder.mjs`，CI 与 pre-push 都跑），走的是 §1.3。

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

**已归档的语义认知（§1.4）—— 查找表，正文在项目记忆里。**

正文**不在这里留第二份**（§9 的教训：写「以 X 为准」再抄一份 X = 制造必然过期的第二源）。
记忆索引 `MEMORY.md` 每个会话自动注入，下表只负责「症状 → 该查哪条」：

| 遇到这个症状 | 查这条记忆 |
|---|---|
| 单测里构造硬件服务当「无定位」，真机上是竞态 | `location-service-test-seam-and-weak-viewmodel-deps` |
| 改盲人端 UI —— 低视力的视觉通道（对比度/横屏/AX5）从没验收过 | `low-vision-visual-channel-unaudited` |
| 崩在 `finishedPlaying:` `unrecognized selector`（接收者类名随机） | `finishedplaying-crash-means-player-freed-not-delegate` |
| XCUITest `Failed to get matching snapshots: Timed out` | `snapshot-timeout-means-a-system-app-took-over` |
| 真机跑测 `Test crashed with signal kill`，跑了大半随机死几条 | `ui-test-runner-needs-usb-not-wifi`（第七种） |
| 写了「失败时在 `List` 末尾多一行字」的分支 | `claimed-fallback-may-not-exist-in-release` |
| 想用 `tap()` 触发 `accessibilityRepresentation` 里的按钮 | `xcuitest-cannot-invoke-accessibility-actions` |

> 2026-09-17 从长条目压成表。原因：这 7 条各自**存了三份**（本文件长版 + `MEMORY.md` 一行版 +
> 记忆文件全文），而本文件每个会话常驻、每一轮按 cache read 价重读一遍。
> 官方 context engineering 指南对这种形态的原话是
> "A common myth is that CLAUDE.md should be a central repository for every practice"。
> 依据与实测见 `docs/research/claude-code-token-optimization-20260917.md`。

- **「看着怪但说不出哪儿怪」= 同一个 `HStack` 里有两个无限可伸缩的子视图在对半分剩余宽度。**
  2026-09-18 项目负责人报的是接单主页「暂停接单」那一行，根因在共用组件
  `FlowInfoRow.rowContent`：它无条件先放 `Spacer(minLength: 8)` 再放 value，
  而 `label == nil` 那一支的调用方自己写了 `.frame(maxWidth: .infinity, alignment: .leading)`
  —— 两边都想要那块空间，于是文字停在一个**不是任何一种对齐**的位置。
  判据：一行「改 padding 也修不动」时，**数这一层有几个弹性子视图，超过一个就是它**。
  **报上来一处就去数调用点** —— 那次实际有 5 处，另外 4 处他根本没路过，
  其中陪跑员端订单页那处自己写着「label 为 nil 就左对齐」、意图被共用组件抵消。
  抓不成守卫也抓不成用例：可点行是 `accessibilityElement(children: .ignore)`，
  内部 `Text` 不进无障碍树，两种行的 `Button` frame 完全相同 ——
  判据是「文字左边缘在哪」，那是渲染几何。只能真机目视，**且要在有对比行的那一屏上看**。
  修复见 PR #162。详见记忆 `flexible-spacer-steals-half-the-row`。

- **「看着怪但说不出哪儿怪」= 同一个 `HStack` 里有两个无限可伸缩的子视图在对半分剩余宽度。**
  2026-09-18 项目负责人报的是接单主页「暂停接单」那一行，根因在共用组件
  `FlowInfoRow.rowContent`：它无条件先放 `Spacer(minLength: 8)` 再放 value，
  而 `label == nil` 那一支的调用方自己写了 `.frame(maxWidth: .infinity, alignment: .leading)`
  —— 两边都想要那块空间，于是文字停在一个**不是任何一种对齐**的位置。
  判据：一行「改 padding 也修不动」时，**数这一层有几个弹性子视图，超过一个就是它**。
  **报上来一处就去数调用点** —— 那次实际有 5 处，另外 4 处他根本没路过，
  其中陪跑员端订单页那处自己写着「label 为 nil 就左对齐」、意图被共用组件抵消。
  抓不成守卫也抓不成用例：可点行是 `accessibilityElement(children: .ignore)`，
  内部 `Text` 不进无障碍树，两种行的 `Button` frame 完全相同 ——
  判据是「文字左边缘在哪」，那是渲染几何。只能真机目视，**且要在有对比行的那一屏上看**。
  修复见 PR #162。详见记忆 `flexible-spacer-steals-half-the-row`。

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
- 所有真实 HTTP 走 `https://47.114.113.171`，所有真实 WebSocket 走 `wss://47.114.113.171`。**地址在 App 内不可配置，不得加入本地或占位的真实服务端地址。**
  > 2026-09-08 从 `http` / `ws` 改过来。服务端 443 自 08-14 就绪（Let's Encrypt **IP 证书**，不需要域名、不需要备案），客户端此前一直没跟，实时位置与 SOS 全程明文。scheme 只有 `EnvironmentConfig.DemoCloud.baseURL` 一处，WS 由它推导；`Info.plist` 的 ATS 例外已随之删除，**别再加回来**。
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
PENDING_MATCH  PENDING_INTRO_CALL  SCHEDULED_CONFIRMED  PENDING_ACCEPT  IN_PROGRESS
DRIVER_EN_ROUTE  DRIVER_ARRIVED  COMPLETED  CANCELLED  REMATCHING  NO_VOLUNTEER
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

跨天预约（接单时距开跑还很远，后端迁移 `0041`）：

```
PENDING_MATCH / PENDING_INTRO_CALL / REMATCHING → SCHEDULED_CONFIRMED（接了一张远期单）
SCHEDULED_CONFIRMED → PENDING_ACCEPT（志愿者临期确认还去，进即时链路）
SCHEDULED_CONFIRMED → REMATCHING（闸门到点未确认 / 志愿者取消）
SCHEDULED_CONFIRMED → CANCELLED（盲人取消）
```

**没有 `SCHEDULED_CONFIRMED → NO_VOLUNTEER`** —— 人已经定下来了，「无人接单」在这一态不是可能的结局。

取消流转：

```
PENDING_MATCH / PENDING_INTRO_CALL / SCHEDULED_CONFIRMED / PENDING_ACCEPT → CANCELLED（盲人 token）
SCHEDULED_CONFIRMED / PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS → REMATCHING（志愿者 token）
REMATCHING → CANCELLED（只能盲人 token）
```

- 取消端点 `POST /api/orders/{orderId}/cancel`，无需请求体。
- 盲人只能取消 `PENDING_MATCH` / `PENDING_INTRO_CALL` / `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `REMATCHING`；`IN_PROGRESS` 期间**不得**展示取消入口。
- 志愿者只能取消 `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`。**`PENDING_INTRO_CALL` 不在内** —— 那一态他还没接单，退出的方式是表态「不合适」，不是取消订单。
- `REMATCHING` 是已接单志愿者取消后进入的状态，此后只能盲人用自己的 token 取消 —— 那个志愿者已不是订单参与者。
- 状态流转端点统一 `POST /api/orders/{orderId}/{action}`：`respond`（体带 `action = ACCEPT|DECLINE|INTERESTED`）、`confirm-departure`、`en-route`、`arrived`、`start-service`、`finish`。
  🚩 **`confirm-departure` 与 `en-route` 不是一回事，别合并**：前者只回答「你还去吗」，人可能还在家里；后者是真的动身、开始双向推位置。合并会让位置互推提前几小时打开。
- 下单起始时间距今不足 30 分钟必须返回 `APPOINTMENT_TOO_SOON`（`EnvironmentConfig.minimumBookingLeadMinutes = 30`）。**没有「现在就跑」。**
- 下单还有三道**上限**（后端 N134 与迁移 `0041`，2026-09-05）：最远 7 天（`APPOINTMENT_TOO_FAR`）、单次不超过 300 分钟（`APPOINTMENT_TOO_LONG`）、整段行程不得与夜间窗口 `[22:00, 05:00)` 相交（`APPOINTMENT_IN_NIGHT_WINDOW`）。**夜间那条的判据是整段不是开始时刻**：`21:00–22:30` 拒、`21:00–22:00` 放行。同时最多 3 张未完成预约（`TOO_MANY_SCHEDULED_ORDERS`）。
  ⚠️ `DUPLICATE_ORDER` 自 2026-09-05 起只拦**时段冲突**，不再是「有任何未走完的单」—— 文案别再写「您有进行中的订单」。
- 订单列表用分页响应 `PagedOrderResponse`；盲人订单详情每 5 秒轮询作为 WebSocket 兜底。
- WebSocket 端点：`/ws/blind?token={jwt}` 与 `/ws/volunteer?token={jwt}`。

### PENDING_INTRO_CALL（接单前通话磨合，后端迁移 `0031`）

志愿者对派单选「有意向，想先聊聊」后进入。订单锁给这个候选人，双方打完电话各自表态，都说合适才转 `PENDING_ACCEPT`。

- **这一态还没有志愿者接单**。后端 `order.volunteer` 恒为 null，候选人只存在于 `dispatchCurrentVolunteerId`。直接后果：志愿者调 `GET /api/orders/{orderId}` 会被判 403，他这一刻**拿不到订单详情**，通话页只能吃派单推送 + `GET /api/orders/{orderId}/intro-call`。`IntroCallView` 里的 `startAddress` / `plannedStartTime` 就是为这个冷启动恢复存在的，别当冗余字段删掉。
- 专用端点四条：`GET /intro-call`（通话页数据）、`POST /intro-call/decision`（表态 `ACCEPT|DECLINE`）、`POST /intro-call/unreachable`（志愿者报「没打通」，**盲人侧没有对应端点**）、`POST /intro-call/notify-incoming`（盲人拨号前提醒志愿者）。
- **号码单向**：盲人拿到明文号可直拨，志愿者只拿到掩码串用于认人。掩码串**绝不能拼 `tel:`**（2026-08-11 的真实缺陷）。唯一允许拼 `tel:` 的来源是 `IntroCallView.dialableCounterpartPhone`。
  > 🔄 **2026-09-16 订正一处事实 + 补上机器守卫。** 原文写着「`138****1234` 会拨成**空号**」——
  > **那句话是错的**，而错得有代价：它让人以为 `telURL` 只取数字位就已经兜住了这件事。
  > 实际拼出来的是 `tel://1381234`，一个**七位的、可能真打给别人**的号码。
  > 现在 `EmergencyDialer.telURL` 显式拦掩码标记（`*` / `＊`，见 `redactionMarkers`），
  > 用例 `EmergencySOSTests.testDialerRefusesMaskedNumbersButKeepsFormattedPlainOnes` 双向钉住
  > （拒掩码 / 放行带空格横线的明文号与三位急救号 —— 后者是这道闸唯一的误报面）。
  > provenance 那道防线保留：两道管的不是一件事，一道管「该不该用这个字段拨号」、
  > 一道管「这个值长得能不能拨」。
  > **这条是第一次真机执行 `BlindOrderFlowPresentationTests` 时红出来的** ——
  > 那条用例照着上面那句错话写注释，于是断言靠一个不成立的理由碰巧成立了三周。

  > 契约侧的对应不变量（`demo/docs/api_spec.yaml:6421`，逐字）：
  > 「要么是能直接拨通的号码，要么是 `null`，永远不会是掩码串」——
  > 所以 `OrderDetailResponse.volunteerPhone` 上那道闸是**纵深防御**，不是日常路径。
- **无声拒绝**：响应体不含对方的表态、也不含轮次进度，这不是后端漏字段。只有一方表态时后端**不通知**对方；「这是第 3 位志愿者」本身就是在告诉盲人前两位没成。客户端**也不许自己算**轮次再显示（例如按收到几次 `INTRO_CALL_CONTINUE` 计数）。
- 盲人的自由文本在这一态**不可见**（`disclosesBlindRunnerNotesToVolunteer` 判 false，见 §8）：一单最多聊 3 位候选人，展示等于交给这一单碰到的每一个人。
- 窗口 20 分钟（`app.intro-call.window-minutes`，**别硬编码**）；退回时轮次 +1，满 3 轮（`max-rounds`）转 `NO_VOLUNTEER`。
- ⚠️ **发 `ACCEPT` 还是 `INTERESTED` 只认推送里的 `requiresIntroCall`，客户端不许自己算。** 该字段自后端迁移 `0031`（2026-08-22，commit `aea3fc9`）起挂在 `NEW_ORDER` 上并标为**必填**（`websocket-protocol.md`：「客户端按它决定 `/respond` 发哪个 `action`」）；iOS 侧走 `WSNewOrder.dispatchRespondAction`。自己算不出来 —— 「这两人磨合成功过没有」在后端库里，通话窗口长度是后端配置 `app.intro-call.window-minutes`。缺这个键时**降级发 `INTERESTED`**（两种开关状态下后端都放行），不是崩掉整条推送。
  > 2026-09-06 改口径。原文写着「唯一派单通道 `NEW_ORDER` 推送里没有它」—— 那句自 08-22 起就不成立了，而它是一条**禁令**（「不要另起 `.accept` 分支」），过期的禁令比过期的描述更贵：照它做等于让熟人永远多打一通电话。
- 🚩 **事先分流之外，两个方向的 409 都要兜** —— 推送是快照，发出之后磨合记录或 `app.intro-call.enabled` 都可能变，两边都会过时。`VolunteerHomeViewModel.respondToDispatch` 各自只改发一次：
  - `ACCEPT` → 409 `INTRO_CALL_REQUIRED` → 就地改发 `INTERESTED`（`.interested` 没有额外前置闸，就地重发是安全的）
  - `INTERESTED` → 409 `INTRO_CALL_NOT_REQUIRED` → **递归重走同一个函数**（带 `allowsIntroCallUpgrade: false`），不许就地补一个 API 调用 —— `.accept` 有 `.interested` 没有的定位权限闸与 `VolunteerLocationReporter.reportIfNeeded`，绕过去会让人在没给定位权限的情况下把单接下来

  必须自动改发的理由是界面事实：派单弹窗只有「有意向」和「拒绝」两个按钮，只弹一句文案 = 志愿者卡在一个本该能接的单上。两条错误码的用户文案因此都写成「再试一次」而不是「请改选某个按钮」—— 它们只在**自动改发也失败**时才会被念到，那时叫用户去选一个客户端已经替他选过的按钮，只会让人以为按钮坏了。
- 反过来也不能假设「陌生人必然被拦」：距开跑时间已塞不下一轮通话窗口时后端**刻意放行** `ACCEPT`（退化成直接接单）。

## 6. 求助 / SOS 红线

- 求助**不是**订单状态。`POST /api/emergency/trigger` 只记录事件，订单状态不变。
- **两端入口都只在 `IN_PROGRESS` 开放。这是产品决策，不是技术约束。**
  > 2026-09-15 改口径。原文的括号里写着「`EmergencyTriggerRequest` 必须带 `orderId`」，
  > 用它给前半句当理由 —— **那句已经不成立**。契约原文逐字是：
  > 「三个字段**全部可选**。不传 `orderId` 即独立 SOS（无进行中订单也能求救）」
  > （`demo/docs/api_spec.yaml:5471-5473`），participant 校验只在**传了** `orderId` 时才做。
  >
  > 闸门在客户端：`BlindHomeSOSMode.resolve` 的 `guard let order … else { return .localCall }`
  > （`blindRun/Safety/SafetyModule.swift:354-359`），判据 `canBlindRunnerTriggerEmergency`
  > / `canVolunteerTriggerEmergency` 都是 `self == .inProgress`
  > （`blindRun/Core/Models/OrderModels.swift:176-178`、`:189-191`）。
  >
  > **关着的真实理由只剩一条**，写在 `canBlindRunnerTriggerEmergency` 的注释里且仍然成立：
  > `IN_PROGRESS` 是唯一保证握着**新鲜真实 GCJ-02 坐标**的状态 —— 与下面「坐标拿不到就不发」
  > 那条是同一件事。注释里另一条理由「the one the backend's participant check accepts」
  > 已随契约作废。
  >
  > **为什么这条订正值钱**：把产品决策伪装成技术约束，会让任何读到它的人认为独立 SOS
  > **做不了**，于是根本不会拿它去问产品。实际状态是「能做，等批准」——
  > 与 `allowsSubmissionWithoutLocation` 完全同构，而那一条从一开始就诚实地这么写了。
  > 要打开闸门需要先回答：无订单时坐标从哪来、误触冷却 60 秒按触发者计的代价、
  > 以及 `enable-independent-sos-safely` 里 4 条真机验证欠账（设备长期离线，从没跑过）。
- **有两处求助入口在非 `IN_PROGRESS` 也开着，它们都不是例外**：`IN_PROGRESS` 时走上面这条云端链路，
  其余任何状态一律降级为**本地拨号**（主紧急联系人 / **120** / 110），**绝不调 `POST /api/emergency/trigger`**。
  判定两处共用 `BlindHomeSOSMode.resolve`，**新增任何求助入口都必须读它，不许自己判状态**：
  1. 「我的」tab 底部那条常驻求助条（`BlindHomeSOSBar`）；
  2. **求助与安全中心底部那条**（`BlindSafetyHubView.emergencyButton`，2026-09-16 起）——
     订单页四步骨架的底部有一枚「求助与安全」，而它覆盖的四态（匹配 / 约好 / 出发 / 汇合）
     一个都不是 `IN_PROGRESS`。
     > 🔴 这一条是**修出来的**，不是设计出来的。骨架刚落地时那一层的底部写死走云端，
     > 真实后果是：`beginCountdown` 在资格 guard 落 `.failed`、全屏倒计时不弹，
     > 而骨架那一屏没有 `EmergencyStatusNotice` 的渲染点 ⇒ **长按 3 秒之后屏幕零变化、
     > 一个字也不播**。用例 `AccessibilityAuditTests`
     > `testSafetyHubOutsideTheActiveRunOffersLocalDialInsteadOfCloudSOS` +
     > `EmergencySOSTests.testSafetyHubDowngradesToLocalCallOutsideOfTheActiveRun` 钉住。
     > 教训是可复用的：**给一个原本只在某一态可达的入口开放新的到达路径时，
     > 先问那一层里每个动作在新的状态下还成不成立** —— 加的是入口，坏的是别人。
  > 🔄 **2026-09-16 改口径：它现在挂在「我的」tab 的底部，不在首页。**
  > 首页按设计稿 `design-reference/order-flow/screens/01-home.png` 收成「问候 + 订单卡 + 预约块」
  > 三块，那张稿上没有求助条；项目负责人当日拍板删除首页那条、由「我的」tab 兜底。
  > 组件（`BlindHomeSOSBar`）、判据（`BlindHomeSOSMode.resolve`）、`safeAreaInset` 的挂法
  > 与「不滚动即可达」这条性质**全部未变**，变的只是它在哪个 tab 上。落点 `BlindRunnerTabView`。
  >
  > ⚠️ **代价必须写在这里而不是只写在代码里**：紧急入口从「打开 App 就在眼前」变成
  > 「先切到第三个 tab」。VoiceOver 用户仍有 magic tap 兜住（手势挂在 tab 容器上，三个 tab
  > 都能用），而**不开读屏的低视力用户在首页确实够不到它** —— 这是已知的产品取舍，不是疏漏。
  > 要翻回去只需把 `BlindRunnerTabView.sosBar` 挂回首页，判据一行不用改。
  > 机器守卫：`AccessibilityAuditTests.testBlindRunnerTabBarOffersHomeHistoryAndProfile`
  > 断言切到「我的」之后求助条真的在 —— 没有它，「三个 tab 上都摸不到求助」的表现
  > 只是「首页干净了」，不会有任何东西报警。
  > 2026-09-15 补 `120`。原文只写了「主紧急联系人 / 110」，而 2026-09-08 起 `120` 已是
  > 并列的可点入口（`EmergencySafetyCopy.homeCallMedicalTitle`）。理由写在 `SafetyModule.swift:203-206`：
  > 用户在**跑步**，摔倒、扭伤、心脏不适是最可能发生的紧急情况，而它们对应的是急救不是报警；
  > 那次改动之前「110或120」只作为文字出现在状态提示里 ——
  > **对看不见屏幕的人，念得出来而按不到等于没有。**
  > 降级分支那个弹窗的标题也不叫「求助」，叫 **「紧急呼叫」**（`homeCallTitle`）：
  > 「一键求助」在本 App 里专指云端链路，两者共用一个词会让人以为求助已经发出。
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

**整文件冻结**：`Podfile` —— 架构排除设置与 pod 列表都在里面，没有安全的局部改法。

**行级冻结**：`blindRun.xcodeproj/project.pbxproj` —— 文件可以改（例如加 SPM 依赖），但改动内容**不得触及 `DEVELOPMENT_TEAM`**。写死的 `R6PH2TFB3Q` 是原开发者的团队号，命令行传 `DEVELOPMENT_TEAM=ZW39BS8NXT` 覆盖。

**任何构建相关文件都不得写入 `EXCLUDED_ARCHS`** —— 真机是唯一 XCTest 通道，模拟器因高德无 arm64-sim slice **永久不可用**，那条设置是这个事实的载体。确需在代码或注释里提及，行尾加 `guard:allow excluded-archs`。

> 2026-08-06 从整文件冻结改为行级。核对后发现原先给的两条理由只有一条落在 pbxproj 上（`DEVELOPMENT_TEAM`，12 处）；`EXCLUDED_ARCHS` 在 pbxproj 里出现 **0 次**，它只存在于 `Podfile:36`。整文件冻结的代价是连加一个 SPM 依赖都做不到，而「临时解锁、改完加回来」依赖人记得加回来 —— 第 1 节说的就是这种挡不住重复犯错的做法。
>
> 守卫在 `scripts/hooks/guard.mjs`，自测在 `scripts/validate-guard.mjs`（CI 与 pre-push 都跑）。
> 守卫管的不止冻结文件。**规则清单和用例数这里一律不写** —— 要用就当场取，一条命令的事：
>
> ```bash
> # 规则 id（两处来源：rules 对象的键 + fail() 里硬编码的。少查一处就会漏掉三条）
> python3 -c "
> import re
> s=open('scripts/hooks/guard.mjs').read()
> ids=set(re.findall(r\"fail\(\s*'([a-z0-9-]+)'\",s))|set(re.findall(r\"^  '([a-z0-9-]+)':\",s,re.M))
> print('\n'.join(sorted(ids)));print('共',len(ids),'条')"
>
> node scripts/validate-guard.mjs | tail -1   # 用例数
> ```
>
> 别用 `grep` 抓规则 id —— `fail(` 后面常换行，逐行匹配一条都取不到（空结果比错结果更难发现）。
>
> 2026-08-11 立此条：原文写着「规则清单以 guard.mjs 为准，本文件不留副本」，紧接着**自己抄了一份**
> —— 抄的那份漏了 `blind-tap-center`、`missing-team`、`archived-contract` 三条，用例数也停在 21（实为 28）。
> 有人照它写进对外文档，发现对不上才返工。写「以 X 为准」再抄一份 X，等于制造一个必然过期的第二源。

## 10. 工作流

**开工前**

1. 先读 `AGENTS.md`
2. 再读相关 docs 与 OpenSpec
3. 判一次这活要不要派 subagent —— 判定表在全局 `~/.claude/CLAUDE.md` 的「委派」节，**本文件不留副本**（理由同 §7：两份会漂移）。一句话版：定位/摘要/读日志外包，设计与编辑自己干

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
> 而 `install-git-hooks.sh:233-237` 现在会主动清掉双推配置：照着那两条做会被安装脚本撤销。

**实现中**

4. 一次只实现一个内聚模块
5. **行为有变时，实现前 `openspec/changes/` 下必须有对应变更** —— `openspec list` 找现成的，没有就用
   skill `openspec-propose` 建；实现中做完一项勾一项。不改变行为（修 bug / 文案 / 重构）不需要提议。
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

**收尾：三件事，缺一件都不算做完**

7. 跑测试、更新必要文档，按 skill `aidrun-ship-check` 的格式输出；**变更的任务全打勾就在同一个 PR 里
   `openspec archive <name> -y`**（skill `openspec-archive-change`）—— 归档才是闭环终点
8. **同步 handoff**（`demo/docs/handoff.md`）：
   - 全文近 3000 行，**只读末尾最新几条**（`tail -80`）或用 `grep -n "^- \[ \]"` 定位未答项，**不要整读**
   - 本轮答掉的问题：`- [ ]` 改 `- [x]`，答案写在 `答：` 后面；**不删除已答条目**，历史是决策记录
   - 本轮新产生的、需要后端拍板的问题：追加到「待后端确认」，每条带日期 / 提问方 / 具体到文件行号或端点的上下文 / 明确的问题
   - 契约本身的变更不写这里 —— 直接改后端 `docs/api_spec.yaml`
9. **commit**：`type: 描述`（type 取 feat/fix/refactor/docs/test/chore/perf/ci）。**不带 `Co-Authored-By`**（`~/.claude/settings.json` 的 `includeCoAuthoredBy: false` 已全局关闭，不要手动加回来）
10. **push**

> OpenSpec 闭环（2026-09-23 立，项目负责人要求「提议 → 实现 → 归档」每次自动走完）也在同一个钩子里：
> 任务全打勾却没归档 → 硬拦；本轮改了 App 源码却没碰 `openspec/changes/` → 拦一次，
> 回一句「不改变行为」即可放行。判据只在 `openspec-reminder.mjs` 一处，本文件不抄。
>
> 第 9–10 步由 Stop 钩子 `scripts/hooks/stop-checklist.mjs` 强制：**本轮写过的文件没提交**或
> **领先 origin** 时拦住本次停止并列出欠账。一次停止只拦一次，用户说「先不提交」时
> 回一句说明再停即可，不会死循环。

**这个仓库是共享 checkout**：前后端两个工作区都可能有同事在同时编辑，而 `.git` 整个是共用的
（**index 和 HEAD 都是**，记忆 `shared-checkout-concurrent-colleague-edits`）。
2026-08-16 因此把一笔编译不过的 WIP 推进了 PR，还改写掉了同事的一条提交，全程零报错。
`scripts/hooks/shared-checkout-guard.mjs`（PreToolUse / Bash）拦三类，
**当且仅当**它们会波及别人的东西 —— 自己分支上 amend、暂存区里全是自己写的文件，都放行。

落到日常写法上只有两条，记住这两条就不会撞它：

1. **暂存永远带显式路径** —— 不写 `git add -A` / `git commit -a` / `git commit --amend` / `git stash`。
2. **串联 git 命令永远用 `&&`，不用 `;`** —— 本仓库常年挂着十几二十个 worktree，
   `git checkout <被占着的分支>` **必然失败**，用 `;` 接的下一条会照常落在你当前分支上、零报错。
   腾开的办法：`git -C <占着它的 worktree> checkout --detach`。

> 三条判据各自为什么长这样、两次误报怎么修的，写在两个钩子文件自己的头注释里
> （改它们的人才需要）。自测 `scripts/validate-stop-checklist.mjs` 与
> `scripts/validate-shared-checkout-guard.mjs`，CI 与 pre-push 都跑；**条数当场看输出，
> 别写在这**（理由同 §9：09-02 核对时这里写的 9 条实际已是 11 条）。

## 11. 验证命令

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机（唯一 XCTest 通道；脚本会先探活，统计只认 result bundle 不认日志）
# ⚠️ 默认**不要**这样裸跑全量，先看下面「跑多大范围」
scripts/device-test.sh

openspec validate --all --strict --no-interactive
node scripts/validate-docs.mjs
node scripts/validate-spec-coverage.mjs    # 路径级：前端调的每条路径都在契约里
node scripts/validate-golden-corpus.mjs    # 语音黄金语料 vs 前端镜像清单
node scripts/validate-error-codes.mjs      # 前端 ErrorCode 枚举 vs 后端 ErrorCode.java
node scripts/validate-voice-intent-words.mjs  # 确认轮本地直通表 vs 后端 VoiceSlotParser 的 INTENT_* 正则
scripts/production-readiness-check.sh      # 需 AIDRUN_* 环境变量，见 aidrun-ship-check
scripts/dual-device-validation.sh
```

中间四条（spec-coverage / golden-corpus / error-codes / voice-intent-words）要读后端仓库。
装一次本地 pre-push 钩子把它们钉在 push 前：`scripts/install-git-hooks.sh`。
CI（`.github/workflows/verify.yml`）跑编译门禁 + 规格校验，但**跑不了真机 XCTest**。

**默认只跑覆盖本次改动的 suite，不是全量。** 判据只有一条：改的东西是不是**全 App 唯一的出口 /
共享单例 / 全局配置**（`SystemSpeechAudioSession`、`APIClient`、`AppState`）—— 是才全量。
怎么按符号定范围、`-only-testing` 怎么写，见 skill `aidrun-ship-check` §六。

> **零执行不是通过。** `passed=0 failed=0` 一律当失败查——设备锁屏、`-only-testing` 名字打错、
> 测试目标没编出来都会长这样：命令回来了、看起来一切正常，但一条断言都没跑。
> 脚本对这种情况有硬失败，别绕过它。

### 读后端仓库的那 5 条门禁

中间四条（spec-coverage / golden-corpus / error-codes / voice-intent-words）加生成代码比对，
要读后端私有仓库。每台机器装一次钩子把它们钉在 push 前：`scripts/install-git-hooks.sh`。

三条**必须常驻**的事实（其余细节见 skill `aidrun-ship-check` §七）：

- 读的契约取自后端 **`origin/main`**，不是 `../demo` 工作区 ⇒ `../demo` 停在哪个分支、脏不脏都不影响结论。
- 🔴 **一次同时改两端的功能，必须后端先合，iOS 才推得上去**（两条路径分别撞不同的墙，都不是 bug，
  是设计使然的顺序约束）。⛔ 别用 `AIDRUN_SKIP_PREPUSH=1` 绕 —— 那一次跳过全部 5 道门禁。
- **`JerryZhao-1/blind-run-ios` 只是 `upstream`，不是投递目标**；它配不上 secret，
  **上游 CI 绿 ≠ 契约对过了**。

**编译通过不等于测试通过。永远不许把没执行过的测试写成通过。**

## 12. 联网调研只落一个地方

唯一位置 `docs/research/`，唯一索引 `docs/research/INDEX.md`。前三条管**怎么落**，第 4 条管**怎么找回**：

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

## 13. 成体系的 review 也只落一个地方

唯一位置 `docs/review/`，唯一索引 `docs/review/INDEX.md`，规则与 §12 同构：**开新 review 前整份读索引**，
按「复核触发条件」判旧结论作不作数；review 完落 `docs/review/{topic}-{YYYYMMDD}.md` 并回写索引一行。

与 §12 的分工：`docs/research/` 记「外面是怎么做的」（联网事实，带来源与核实日期）；
`docs/review/` 记「我们做成了什么样」（对着代码与契约的判断，带 `文件:行号`）。
一次 review 引用一次 research 是常态，反过来不成立 —— 竞品事实不要写进 review，两处都写会漂移。

> ⚠️ 这条**没有 hook 强制**，`research-log.mjs` 只管联网调研。漏过第二次就按 §1.1 落成守卫。
>
> 2026-08-12 立此条：`frontend-backend-alignment-review-20260812.md` 原本躺在 `docs/` 根目录，
> 与 20 个同级文档混在一起 —— 下一次 review 既不会先读它，也不会挨着它落盘。已迁入 `docs/review/`。
