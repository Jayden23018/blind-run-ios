---
name: aidrun-order-and-sos
description: AidRun 订单状态机与求助 / SOS 入口的细节 —— 状态流转图、取消入口与权限、状态流转端点、下单上下限、派单 respond（ACCEPT / INTERESTED / 409 改发）、通话磨合（PENDING_INTRO_CALL）页、三处求助入口与降级本地拨号。改订单状态流转、取消入口、派单响应、通话磨合页，或新增 / 改动任何求助 / SOS 入口与降级拨号时读。
---

# AidRun 订单状态机与求助入口（细节）

红线在 `AGENTS.md` §5 / §6，本文件是细节；**两者冲突以 `AGENTS.md` 为准**。
2026-10-20 从 `AGENTS.md` §5 / §6 原文搬来（#482），引用块随段落原样搬，只删了与 AGENTS.md 留下部分逐字重复的句子。

## 订单状态机

允许的状态列表与禁用词见 `AGENTS.md` §5。

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
DRIVER_ARRIVED → CANCELLED（盲人 token，满 earliestBlindCancelAt 之后，后端 #682）
SCHEDULED_CONFIRMED / PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED / IN_PROGRESS → REMATCHING（志愿者 token）
REMATCHING → CANCELLED（只能盲人 token）
```

- 取消端点 `POST /api/orders/{orderId}/cancel`，无需请求体。
- 盲人只能取消 `PENDING_MATCH` / `PENDING_INTRO_CALL` / `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `REMATCHING`，以及**带时间门槛的 `DRIVER_ARRIVED`**；`DRIVER_EN_ROUTE` / `IN_PROGRESS` 期间**不得**展示取消入口（后端 403 `ORDER_IN_PROGRESS`）。
  - `DRIVER_ARRIVED`（后端 #682，iOS #395）：门槛是订单详情的 `earliestBlindCancelAt`（「这一次到达」与「计划开跑」中较晚的那个 + 后端配置分钟数，默认 10）。**客户端不自己拿到达时间加。** 为 `null` = 后端关了这条出口 ⇒ 不出现入口；没到点 ⇒ 汇合页「取消本单」置灰，读屏说出几点可以取消并建议先打电话；早于它调取消回 409 `BLIND_CANCEL_TOO_EARLY`，朗读后端 `message`（带时刻）。判定在 `BlindArrivalCancelGate`；`canBlindRunnerCancel` 只按状态判，**不含**这一态。
  - 取消成功后陪跑员收到 `ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL`（HIGH，`ttsText` 带「你可以离开集合点了」）。它**不许**进 `AppRealtimeCoordinator.lifecycleStatus` 那张表 —— 进了就会因「有活跃订单」被吞。
- 志愿者只能取消 `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`。**`PENDING_INTRO_CALL` 不在内** —— 那一态他还没接单，退出的方式是表态「不合适」，不是取消订单。
- `REMATCHING` 是已接单志愿者取消后进入的状态，此后只能盲人用自己的 token 取消 —— 那个志愿者已不是订单参与者。
- 状态流转端点统一 `POST /api/orders/{orderId}/{action}`：`respond`（体带 `action = ACCEPT|DECLINE|INTERESTED`）、`confirm-departure`、`en-route`、`arrived`、`start-service`、`finish`。
  🚩 **`confirm-departure` 与 `en-route` 不是一回事，别合并**：前者只回答「你还去吗」，人可能还在家里；后者是真的动身、开始双向推位置。合并会让位置互推提前几小时打开。
- 下单起始时间距今不足 30 分钟必须返回 `APPOINTMENT_TOO_SOON`（`EnvironmentConfig.minimumBookingLeadMinutes = 30`）。**没有「现在就跑」。**
- 下单还有三道**上限**（后端 N134 与迁移 `0041`，2026-09-05）：最远 7 天（`APPOINTMENT_TOO_FAR`）、单次不超过 300 分钟（`APPOINTMENT_TOO_LONG`）、整段行程不得与夜间窗口 `[22:00, 05:00)` 相交（`APPOINTMENT_IN_NIGHT_WINDOW`）。**夜间那条的判据是整段不是开始时刻**：`21:00–22:30` 拒、`21:00–22:00` 放行。同时最多 3 张未完成预约（`TOO_MANY_SCHEDULED_ORDERS`）。
  ⚠️ `DUPLICATE_ORDER` 自 2026-09-05 起只拦**时段冲突**，不再是「有任何未走完的单」—— 文案别再写「您有进行中的订单」。
- 订单列表用分页响应 `PagedOrderResponse`；盲人订单详情每 5 秒轮询作为 WebSocket 兜底。
- WebSocket 端点：`/ws/blind?token={jwt}` 与 `/ws/volunteer?token={jwt}`。

## PENDING_INTRO_CALL（接单前通话磨合，后端迁移 `0031`）

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

## 求助入口

判定、降级拨号与各入口的用例名。红线（只在 `IN_PROGRESS` 走云端、确认文案逐字锁定等）见 `AGENTS.md` §6。

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
- **有三处求助入口在非 `IN_PROGRESS` 也开着，它们都不是例外**：`IN_PROGRESS` 时走上面这条云端链路，
  其余任何状态一律降级为**本地拨号**（主紧急联系人 / **120** / 110），**绝不调 `POST /api/emergency/trigger`**。
  跑者端两处共用 `BlindHomeSOSMode.resolve`，陪跑员端那处用 `VolunteerOrderSOSMode.resolve`
  （两者判据都只有 `canBlindRunnerTriggerEmergency` / `canVolunteerTriggerEmergency`）。
  **新增任何求助入口都必须读对应那一端的判定，不许自己判状态**：
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
  3. **陪跑员订单页右上角的求助胶囊**（`VolunteerOrderFlowPage` → `FlowOrderNavBar`，2026-09-26 起）——
     项目负责人拍板「所有订单页都显示」：邀请 / 约好 / 出发 / 汇合 / 完成 / 跑者取消全部是本地拨号
     （`EmergencyCallContext.volunteerBeforeRun`：只列 120 / 110，不列联系人，第一句说清
     「App 不会代你发送求助」）；只有 `IN_PROGRESS` 交给宿主走现有云端链路。
     用例 `VolunteerOrderFlowPresentationTests.testHelpPillDialsLocallyInEveryStateBeforeTheRun` 逐状态钉住。
     **`IN_PROGRESS` 那一枚（v2 跑步页导航栏的 `FlowHelpPill` 云端模式，identifier `volunteerServiceSOSButton`）2026-09-27 起打开跑步中求助面板**
     （`VolunteerRunHelpPanel`，DECISIONS-v2 V5/V6）：暂停 / 一键提交客服工单 / 紧急求助。紧急按钮
     轻点与读屏双击弹本节锁定文案的确认框，长按 3 秒直发（与跑者端求助中心同一套 `safetyLongPress`），
     走的仍是同一条云端链路；副标题只说「求助会附带你的当前位置」。
     用例 `AccessibilityAuditTests.testVolunteerRunHelpPanelOffersPauseSupportAndConfirmedEmergency`。
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
