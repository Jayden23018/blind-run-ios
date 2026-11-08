# 前端全仓审查第 3 轮：架构（浅模块与并发写法）2026-11-08

Issue #857。方法照 `mattpocock-skills:improve-codebase-architecture` 1.3.2：用 git 历史找常改处，找接口和实现差不多复杂的「浅模块」，提议合成「深模块」（接口小、背后行为多）。

- 读的代码：`origin/main` c962d379 的快照。#816（删旧四步约跑表单）在本报告写完后合并，旧表单不算进候选。
- 热点：近 120 次提交里改得最多的是两端订单页（各 17 次）、约跑页（17）、陪跑员首页（15）、`ContentView`（15）、`MockAPIClient`（13）、盲人首页（13）。
- 走查：3 个只读子代理分三块（订单页与实时推送 / 约跑语音与 App 外壳 / 跑后记录与资料页），约 30 万 token。我抽查了 4 条关键说法。
- 只读代码，没有构建，也没有运行。

术语：module = 有接口有实现的任何东西；interface = 调用方必须知道的一切（签名、不变量、顺序、错误方式）；deep = 接口小而背后行为多；shallow = 接口几乎和实现一样复杂；seam = 不改那处代码就能换行为的位置；adapter = 填进 seam 的具体实现。

## 结论

| # | 候选 | 推荐 | 改动量 | 风险 | 红线 | 状态 |
|---|---|---|---|---|---|---|
| 1 | 两端首页「同一时间只跑一个刷新」合成 `SingleFlightRefresh` | 强 | 中（3 处，约 200 行） | 中（并发） | 否，但首页订单决定求助入口模式 | 已合并：#859 → PR #861（11-08）。新用例 12 条，已写，未执行 |
| 2 | 远端数据「加载 / 失败 / 已加载」只留一种 module | 强 | 大（约 25 个 ViewModel） | 低 | 否 | 已合并：模块 `blindRun/Shared/RemoteContent.swift`，#863 → PR #867、#864 → PR #868、#866 → PR #869、#865 → PR #871（均 11-08）。用例已写，未执行。`CompletedTrackSummaryView` 属订单页红线，没迁 |
| 3 | 两端跑后记录页共用页面骨架（第 2 轮 D9） | 值得探 | 中 | 低 | 否 | 已合并：#879 → PR #880（11-08），三态部分早先由 PR #867 做掉。新用例 3 条，已写，未执行；画面不变只读代码确认，没有装机截图对比 |
| 4 | 401 处理收进 APIClient 的 seam | 值得探 | 中（65 处 / 41 文件） | 中（认证） | 否，要过 security-reviewer | 已合并：OpenSpec 变更 `centralize-session-expiry-handling`（PR #874），第 1 批 #872 → PR #876（security-reviewer 无 CRITICAL / HIGH），第 2 批 #873 → PR #877（均 11-08）。用例已写，未执行；真机跑（tasks 3.1）与归档（3.2）未做 |
| 5 | 订单实时跟踪：两端订单页订阅、对方位置过期、轮询合成一个 module | 强 | 大 | 高 | **是，只报告** | 方案待批：OpenSpec 变更 `unify-order-live-tracking`，#881 → 草稿 PR #884（11-08）。批准前不改 Swift 文件 |
| 6 | ViewModel 构造时注入窄依赖，不再 `configure(with: AppState)` + weak | 设想 | 大 | 中 | 否 | 待选，先挑一页试 |
| 7 | Mock 后端里复制的业务规则拆开、与后端对照 | 设想 | 中 | 低 | 部分（通话磨合） | 已合并订单流转拆分：#895 → PR #PRNUM（11-08），只验编译。意图判定只出结论，待负责人定（见 §7.2） |

## 1. 首页单飞刷新（已选定）

- 现状：
  - 盲人首页 `blindRun/BlindRunner/BlindRunnerHomeView.swift:189-232` `loadActiveOrder`、`:234` `cancelLoading`、`:336` `cancelRequestIfCurrent`。
  - 陪跑员首页 `blindRun/Volunteer/VolunteerHomeViewModel+Loading.swift:12-84`。
  - 陪跑员派单摘要 `blindRun/Volunteer/VolunteerHomeViewModel+DispatchSummary.swift:124-157`，挂在 `activeLoadTask` 上等，另有一套 `summaryRefreshTask` / `summaryRefreshID`。
  - 前两处逐行相同：`activeLoadTask` + `activeRequestID` + `withTaskCancellationHandler` + 收尾 `guard`。
- 可疑问题（读代码推出来，我核过，未运行）：`onCancel` 把 `cancelRequestIfCurrent` 放进另一个 `Task` 排队，`await workTask.value` 先返回，外层 `guard activeRequestID == requestID` 照样通过。被取消的请求走完收尾：盲人端写 `.loaded(activeOrder)`（可能 nil），陪跑员端写 `.loaded(summary)` 或 `.failed("派单状态加载失败，请重试。")`。
- 现有用例 `blindRunTests/HomeLoadDeadlineTests.swift:34` 只断言 `isLoading` 与 `errorMessage`，不看内容状态。陪跑员端 `VolunteerHomeDispatchTests.swift:50-66` 调了 `cancel()` 但不断言取消后的状态。
- 已有的近亲 `CoalescedRerun`（`blindRun/Core/AppState+PendingInvites.swift:50`）语义不同：后到者触发补跑、不处理取消、没有请求号。不扩展它。
- 超时竞速 `HomeLoadCoordinator.run`（`blindRun/Shared/HomeRecoverySupport.swift:55`）按单个请求算，留在加载闭包里。
- 接口与 12 条决定：见 #859。

## 2. 远端数据三态

- 6 种写法：
  - 带消息的 `Phase`：`blindRun/Shared/RunRecordPresentation.swift:12`。
  - 不带消息的 `Phase`：`blindRun/Shared/MySupportTicketsView.swift:8`、`blindRun/Shared/BlockedUsersView.swift:8`。
  - `loaded` 不带数据：`blindRun/Volunteer/VolunteerRunDataModel.swift:17`。
  - `State` 枚举：`blindRun/Volunteer/VolunteerHomeSummaryCards.swift:186`。
  - `isLoading` + `errorMessage` 两个字段：约 20 个 ViewModel（`isLoading = true` 全仓 25 处），例 `blindRun/Shared/RunRecordHistoryView.swift:34-35` 由 View 在 `:351` 拼出第三态。
  - `loadFailed` 布尔：`blindRun/Volunteer/VolunteerHomeIncentiveView.swift:40`。
- 统一类型已经有：`AsyncLoadState`（`blindRun/Core/APIClient.swift:8`，带请求号防迟到），只有两个首页在用。
- 失败视图 3 套：`IncentiveFailureSection`（`blindRun/Shared/IncentiveUI.swift:36`，会播报，11 个文件在用）；`RunRecordFailedView`（`blindRun/Volunteer/VolunteerRunRecordView.swift:578`，**不播报**，盲人端也用）；历史页内联「重试」（`RunRecordHistoryView.swift:336`）。
- 建议接口：`AsyncLoadState` + 一个视图修饰（加载中 / 失败可重试 / 内容），失败必播报、重试按钮 64pt。
- 测试：`FailureAnnouncementTests.swift` 只测 `IncentiveFailureSection`。

## 3. 跑后记录页骨架（第 2 轮 D9）

- `blindRun/BlindRunner/RunnerRunRecordView.swift:373-388` 与 `blindRun/Volunteer/VolunteerRunRecordView.swift:252-261`、`:401-404`：三态 `switch`、`retry()`、`@State retryTask`、导航栏修饰逐字相同。
- `RunRecordViewModel`（`blindRun/Shared/RunRecordPresentation.swift:11`）已共用，View 层没有。
- 共用的 `RunRecordFailedView`、`RunRecordRetryButton`（`:630`）、`RunRecordLoadingPlaceholder` 放在陪跑员文件里，跑者页反向依赖它。
- 建议：骨架进 `Shared/`，两页只交小节。先做候选 2 会更小。要先问负责人版式。

## 4. 401 收进 APIClient 的 seam

- `handleAuthenticatedAPIError`（`blindRun/Core/AppState+Session.swift:213`）全仓 65 处调用，散在 41 个文件。漏调一处，401 就不登出，没有任何东西会报错。
- `APIClientProtocol`（`blindRun/Core/APIClient.swift:134`）只有 `request` / `upload`，3 个生产 adapter（`URLSessionAPIClient`、`MockAPIClient`、`DisabledAPIClient`）+ 10 余个测试替身，是真 seam。
- 建议：加一个会话感知 adapter 统一转交 401。要先核：返回的 `Bool` 在各调用方决定不同提示文案，`:215` 有「陪跑中推迟登出」分支；adapter 只接管转交，不接管提示。

## 5. 订单实时跟踪（红线，只报告）

- 一次状态变化经过 6 个文件：`WebSocketService.eventPublisher` → `blindRun/Core/AppRealtimeCoordinator.swift:201` `.sink` → `+Routing.swift:6` → `statusUpdatePublisher` → 两端 ViewModel → `apply()` → View。
- 两端逐行相同的订阅：`blindRun/BlindRunner/BlindOrderStatusViewModel+Realtime.swift:9-31` 与 `blindRun/Volunteer/VolunteerInServiceViewModel.swift:133-153`；第三份 `VolunteerHomeViewModel+Realtime.swift:5`。
- 对方位置过期两份：`BlindOrderStatusViewModel+VolunteerLocation.swift:5-22`、`:52-70` 与 `VolunteerInServiceViewModel+Nudges.swift:98-113`、`+OrderUpdates.swift:76-95`。15 秒阈值 `peerFreshness` 被 4 处各自引用。
- 并发混用：`VolunteerInServiceViewModel` 7 个 `AnyCancellable` + 4 个 `Task`；`.sink { Task { await load } }`（`:136-138`）。违反 CLAUDE.md「并发模型只用一种」。
- 难测：两个 ViewModel 无参构造，实时依赖注入不进去；测试里 `statusUpdatePublisher` 引用 0 处；`WebSocketService` 是具体类，0 个 adapter。
- 建议接口：`跟踪(订单号) → AsyncSequence`，状态更新 / 需刷新 / 已过期的对方位置 / 轮询兜底都在里面。
- 负责人 11-08 定：红线只出报告，要改先建大档 OpenSpec。

## 6. ViewModel 依赖注入

- 两步构造：View init 里 `ViewModel()`，`.task` 里 `configure(with: AppState)`，`appState` 是 weak（`blindRun/Shared/RunRecordPresentation.swift:30-48`；`blindRun/Profile/BlindRunnerProfileView.swift:13` + `hasConfigured`）。配好之前 `guard let appState else { return }` 静默不做事。
- 46 个测试文件调 `.configure(with:`，用例要自己持有 `AppState`。`AppState` 被 271 个文件引用。
- 牵涉记忆 `location-service-test-seam-and-weak-viewmodel-deps` 的 weak 约定。建议只在新写或重写的页面上试。

## 7. Mock 里的业务规则

- `blindRun/Core/MockAPIClient+IntroCall.swift`（635 行）`:149` `checkIntroCallPlanGate` 逐行抄契约两态表；`:350-480` 装着 accept / cancel / finish 整套订单流转，与 `+Order.swift` 分裂。
- `blindRun/Core/MockAPIClient+Voice.swift`（894 行）`:187` 意图关键词表；`:162` 说「镜像后端两条规则」，`:549` 说「启发式，不是契约镜像」，互相矛盾。
- `VoiceOrderWizardGoldenCorpusTests.swift:64-106` 直接测 Mock 的静态判定，与后端没有机械对照。
- 建议：先只把订单流转从 `+IntroCall` 拆到 `+Order`；意图判定去留由负责人定。

### 7.1 已做：订单流转拆回 `+Order`（#895 → PR #PRNUM，11-08）

- 搬了什么：`+IntroCall.swift` 原 `:342-522` 整段搬到 `blindRun/Core/MockAPIClient+Order.swift:181-363`。包括 `mockScheduledAheadThresholdMinutes`、`handleAcceptOrder`、`isFarFuture`、`handleConfirmDeparture`、`handleDeclineOrder`、`handleEnRoute`、`handleArrived`、`handleFinish`、`handleStartService`、`handleCancel`、`seededBlindCancelAt`、`isWithinLateCancelWindow`、`handleKeepWaiting`、`actionResponse`。
- 为过 SwiftLint 棘轮（单文件 ≤ 400 行），`+Order` 里**不改订单状态**的陪跑员订单页 v2 动作（`handleQuickMessage`、`handleRingRunner`、`handleSetRunPaused`、`handleRunnerMessage`）原样挪到新文件 `blindRun/Core/MockAPIClient+OrderNudge.swift`。会改状态的 `handleEndWaiting` 留在 `+Order`。所以「改订单状态的 Mock 处理函数」除通话磨合外都在 `+Order` 一处（364 行）。
- 行为不变：搬动的行逐字相同（对 origin/main 的 diff 里增删行两两配对，多出的只有文件头、注释和新文件的 `import` / `extension` 框架）。通话磨合的判定（`handleIntroCallDecision`、`checkIntroCallPlanGate`、安排单）一行没动，仍在 `+IntroCall`。
- 跨文件依赖只剩一处：通话磨合成单 `+IntroCall.swift:89` 调 `Self.isFarFuture`，它现在在 `+Order`。这是原有调用，不是新加的。
- `+IntroCall.swift` 从 635 行降到 454 行。它后半段还装着评价、状态日志、分享链接（`handleReview` 起到文件尾）。这些也不属于通话磨合，本次没搬，以后要拆另开 issue。
- 验证：只跑了编译门禁 `build-for-testing`。没有新写用例，没跑真机。

### 7.2 意图判定：结论（不改代码）

- 原报告说 `:162` 与 `:549` 两处注释互相矛盾。核对后**不矛盾**：`:162` 说的是 `mockVoiceAddressShort`（起点短名，镜像契约两条规则），`:549` 说的是 `mockVoiceEndSpan`（终点抽取，启发式）。两个函数，各说各的。
- 真正的缺口在确认轮意图 `mockVoiceUserIntent`（`+Voice.swift:187`，关键词表 `:212-233`）：
  - 注释 `:182` 写「真正的对撞由 `scripts/validate-voice-intent-words.mjs` 直接读 Java 源码做」。但这个脚本只读 `blindRun/Voice/VoiceOrderWizard.swift` 的本地直通表，**不读 Mock 的表**。
  - 后端黄金语料 `docs/voice-golden-corpus.json`（origin/main）只有 START_TIME / DURATION / ADDRESS / PACE / GUIDE_DOG 五类，**没有确认轮意图**。`validate-golden-corpus.mjs` 和 `VoiceOrderWizardGoldenCorpusTests` 因此也守不到它。
  - 结论：Mock 的意图关键词表自称「逐字转写」后端 `VoiceSlotParser`，但现在没有任何机器检查守着这句话。后端改了正则，Mock 不会红。
- 通话磨合闸门 `checkIntroCallPlanGate`（`+IntroCall.swift:150`）照契约两态表手抄，同样没有机械对照。它属红线，本次不动。

**待负责人定**：

1. Mock 的确认轮意图判定保留为「启发式，只求开发期走得通」，还是和后端做机械对照？
   - 保留启发式：改 `:182` 的注释，删掉「逐字转写」「对撞由脚本做」的说法，免得误导。改动几行。
   - 机械对照：把 `validate-voice-intent-words.mjs` 扩成也读 `MockAPIClient+Voice.swift` 的 `mockVoiceIntent*` 表；或请后端在黄金语料加一类 `USER_INTENT`（要开后端 issue）。
   - 建议：选机械对照里的第一种。脚本已经会解析 Java 正则，只多读一个 Swift 文件，不用后端改。
2. `checkIntroCallPlanGate` 要不要也加对照？契约两态表是文字表格，机器不好读。建议暂不加，等契约改这张表时再看。

## 其他观察（不成候选）

- 约跑 / 语音下单链路跨 `SpeechInputService`（1048 行）→ `VoiceOrderWizard` 9 个扩展 → `VoiceOrderService` → `BlindBookingViewModel+Submit`。向导有 4 个 `…ForTesting` 入口（`blindRun/Voice/VoiceOrderWizard.swift:326-358`）。#816 合并后再看。
- `BlindBookingViewModel+Validation.swift:49` `overlapsNightWindow` 被陪跑员端 `VolunteerMeetupPlan.swift:198` 跨类型借用。
- 两端账户页骨架两份（`BlindRunner/BlindAccountView.swift:20-60`、`Volunteer/VolunteerAccountView.swift:21-65`），第 2 轮只合了删除账户弹窗。
- 卡片容器：`RunRecordCard` 与 `GroupedCard` 只差 `.padding(16)`；`RegistrationGroupCard` 没接设计系统。
