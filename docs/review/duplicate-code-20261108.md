# 重复代码审查（前端全仓审查第 2 轮，2026-11-08）

范围：`blindRun/` 下的 Swift 文件，不含 Mock 文件、`Pods/`、`Packages/AidRunAPI`（生成代码）。代码基点：`origin/main` 0f311413（#837 已合并）。
issue：Jayden23018/blind-run-ios#838。第 1 轮报告：[old-ui-leftovers-20261108.md](./old-ui-leftovers-20261108.md)。

本轮只出报告，不改代码。负责人挑完条目后，每批合并单独开一个 PR。

## 怎么查的

1. **jscpd 5.4.2 找「长得一样」的代码**：
   ```bash
   jscpd blindRun --format swift --min-tokens 50 --ignore "**/*Mock*/**,**/*Mock*.swift,**/Pods/**,**/AidRunAPI/**" --reporters json --output <out>
   ```
   扫了 444 个文件，找到 **67 段完全相同的克隆，共 766 行，占 0.78%**。50 token 已经够低（一段大约 7 行），所以不再往下降阈值。
2. **两路只读子代理找「意思一样、写法不同」的重复**：一路看界面（按钮、卡片、空状态与失败重试、设置行），一路看逻辑（日期格式化、距离 / 时长格式化、电话掩码、错误文案、语音播报）。下面每条「把握高」的结论，主会话都读过源码或全仓数过次数。
3. **Periphery 3.8.0 复扫**：命令同第 1 轮报告。真机 `build-for-testing` 通过后扫描，**共 195 处**，和第 1 轮删完后的数字一致。分诊见后文「Periphery 195 处分诊」。

## 风险档

- **低**：只动界面样式或纯函数，输出不变，编译就能验。
- **中**：输出文字或播报可能变，或者改的是网络 / 解码 / 账号这类公共路径。要查有没有单测逐字钉着文字。
- **红线，只报告**：SOS、订单状态机、通话磨合、掩码号码、派单（AGENTS §5 §6 §8）。按 #838 的规定不改。
- **大档**：涉及隐私权限，按 AGENTS §10 第 5 步要先建 OpenSpec 变更。

## 结论

**完全相同的重复很少（0.78%）**，多半是盲人端和陪跑员端成对的页面。**更大的问题是同一种东西有好几套公共组件**：白色圆角卡片有 4 个组件，内容几乎一样；「错误文案 + 重试」有 7 种写法；「几小时几分钟」有 5 份实现；「M月d日」格式器有 6 个。

建议按下表分批，每批单独一个 PR。编号前面的字母表示来源：`D` = 重复，`P` = Periphery。

| 批 | 内容 | 涉及 | 估计少掉的行 | 风险 |
|---|---|---|---|---|
| D1 | 陪跑员二级页的卡片、卡头、小节标题合成一套 | 4 个组件 → 1 套，约 40 处调用 | 约 50 | 低 |
| D2 | `TrainingCapsuleButtonStyle` 换成 `PrimaryButtonStyle` | 1 个样式 | 约 20 | 低 |
| D3 | 失败重试统一用 `IncentiveFailureSection` | 3–4 处 | 约 40 | 低（会多一句失败播报，见正文） |
| D4 | 日期、时长格式化只留一份 | 约 13 处 | 约 60 | 中 |
| D5 | 两端账号页的「删除账户」三连弹窗抽成一个修饰器 | 2 个文件 | 约 25 | 中 |
| D6 | `APIClient` 两处状态码处理合成一个函数 | 1 个文件 | 约 20 | 中 |
| D7 | 「未知值降级」的枚举解码改成共用协议 | 10 个枚举（`RunOrderStatus` 除外） | 约 50 | 中 |
| P1 | Periphery 报的、不在红线里的未使用常量和方法 | 38 处（App 36 + 测试 2） | 约 120 | 低 |

以下几条只报告，不建议在本轮改：D8 距离格式（小数位数要先定）、D9 跑后记录两端页面（牵涉设计）、D10 首页刷新的「同一时间只跑一个请求」写法（并发，留到第 3 轮）、D11 三个隐私同意弹窗（大档）、R1–R5 红线。

---

## 可以合（按批）

### D1 陪跑员二级页的卡片、卡头、小节标题（低）

同一套「白底 + 圆角 22 + 内边距 (14,16,16,16)」写了 4 遍：

| 组件 | 位置 | 和谁重复 | 调用次数 |
|---|---|---|---|
| `VolunteerHomeCard` | `Volunteer/VolunteerProfileFirstScreenView.swift:195` | `VolunteerSecondaryCard`（`Volunteer/VolunteerSecondaryStyle.swift:70`）逐行相同，只是圆角常量的名字不同，取值都是 22 | 12 处 vs 28 处 |
| `VolunteerHomeCardHeader` | `Volunteer/VolunteerProfileFirstScreenView.swift:215`（jscpd #9，19 行） | `VolunteerSecondaryCardHeader`（`VolunteerSecondaryStyle.swift:93`）；它的图标参数是枚举，还多一种 `.route`，能覆盖前者 | 3 处 vs 13 处 |
| `VolunteerAccountSectionTitle` | `Volunteer/VolunteerAccountPagesStyle.swift:101`（jscpd #19，12 行） | `VolunteerSecondarySectionTitle`（`VolunteerSecondaryStyle.swift:137`）逐行相同 | 1 处 vs 8 处 |
| `RunRecordCard` | `Shared/RunRecordFitnessComponents.swift:148` | 同样的白底 + `GroupedCardMetrics.cardRadius`（22），内边距是 16 | — |

建议：留 `VolunteerSecondary*` 三个，`VolunteerHome*` 和 `VolunteerAccountSectionTitle` 改成调用它们，然后删掉。`RunRecordCard` 内边距不同、外面还包了一层 `VStack`，可以留着，也可以改成 `VolunteerSecondaryCard(padding: 16)`，看负责人的意思。

### D2 `TrainingCapsuleButtonStyle`（低）

`Volunteer/VolunteerTrainingComponents.swift:179`，约 20 行。它自己的注释写着：「这里与 `PrimaryButtonStyle` 外形、配色、尺寸一致……保留这个类型只是为了不动调用处。」建议把调用处改成 `PrimaryButtonStyle`，然后删掉它。

### D3 失败 + 重试（低）

已有公共组件 `IncentiveFailureSection`（`Shared/IncentiveUI.swift:36`），它会念出失败原因（`.announcesFailure`）。和它写法相同、但没调用它的：

- `Volunteer/VolunteerServiceRecognitionView.swift:189` `errorSection`，15 行，逐行相同，**只少了失败播报**。
- `Volunteer/VolunteerRunRecordView.swift:637` `RunRecordRetryButton` 和 `Shared/RunRecordHistoryView.swift:335-350`：同一个「重试」按钮写了两遍。
- `Volunteer/VolunteerProfileFirstScreenView+Todo.swift:76-88`：同类，按钮样式是 `OutlineSecondaryButtonStyle`。

⚠️ 合并后，服务成就页加载失败时会多念一句失败原因。这是行为变化，但符合「点了没反应对盲人是事故」那条要求。这一页是陪跑员端的。

不建议合的：`ContentView.swift` 的「恢复失败」整页和 `VolunteerInServiceView+Fallback.swift:125` 是整页降级，版式不同。

### D4 日期和时长格式化（中）

公共格式器在 `Core/Models/OrderDisplayHelpers.swift:1145` 起（`aidRunDisplayMonthDay` 等 5 个）。

**「M月d日」有 6 个**（全仓 `dateFormat = "M月d日"` 共 6 处，已数过）：公共的 `aidRunDisplayMonthDay`，加上 `Volunteer/VolunteerPoints.swift:176`、`Volunteer/VolunteerHomeSummaryCards.swift:176`、`Volunteer/VolunteerSecondaryPagesCopy.swift:137`、`BlindRunner/BlindFavoritePlaceAddPage.swift:347`、`Shared/RunRecordHistoryRows.swift:112`。另外 `Volunteer/VolunteerRunDataCopy.swift:39-40` 不用格式器，手拼出同样的字符串。

**其他重复的格式器**：
- 「M月d日 EEE」：`Shared/RunRecordHistoryRows.swift:105` 和 `BlindRunner/RunnerRunRecordView.swift:307`。
- 「HH:mm」：`Shared/RunRecordFitnessComponents.swift:97` 和 `Volunteer/VolunteerRunRecordView.swift:196`。公共的 `aidRunDisplayClock` 是 「H:mm」，小时不补零，**不能直接换**。
- 「yyyy年M月d日」：`Shared/RunRecordFitnessComponents.swift:90`，和 `aidRunDisplayDay` 一样。

**「X 小时 X 分钟」有 5 份**：`Shared/RunRecordHistoryView.swift:301` `serviceDuration` 和 `BlindRunner/BlindBookingViewModel+Summaries.swift:144` `durationText` 逐行相同（已读过）。另 3 份写法不同：`Volunteer/VolunteerMeetupPlan.swift:398`、`Volunteer/VolunteerServiceTrend.swift:82`（拆成数值和单位两段）、`Volunteer/VolunteerRunDataView+Sections.swift:194`。

建议：输出完全相同的直接换成公共格式器；输出不同的（「H:mm」和「HH:mm」）单列出来，让负责人定。
风险：文字是播报和测试钉的对象。改之前要全仓搜测试里的期望字符串。

### D5 两端账号页的「删除账户」弹窗（中）

`BlindRunner/BlindAccountView.swift:49-75` 和 `Volunteer/VolunteerAccountView.swift:47-73`（jscpd #2），27 行几乎相同：预检被拦、初次确认、最终确认三个弹窗，只差 `.blind` / `.volunteer`。同一对文件里还有 jscpd #3（27 行，退出登录分组）、#23（10 行）。
建议：抽成 `.accountDeletionFlow(viewModel:role:)` 修饰器，放在已有的 `AccountDeletionFailureAlertModifier.swift` 旁边。
风险：账号删除属于 skill `aidrun-auth` 管的账号生命周期。弹窗文案要逐字不变。

### D6 `APIClient` 状态码处理（中）

`Core/APIClient.swift:450-468` 和 `:543-561`（jscpd #8，19 行），`:375-383` 和 `:479-487`（jscpd #39，9 行）。普通请求和上传请求各写了一遍「2xx 解码 / 401 / 429 / 其余错误体」。
**两边已经不一样了**：上传那份解码失败时不调用 `recordDiagnostic`，普通请求会调用。合成一个函数后，上传也会留诊断记录。
风险：所有请求都走这里。只改分支结构，不改错误映射。

### D7 「未知值降级」的枚举解码（中）

同一段 `init(from:)` + `encode(to:)` 写了 10 遍，每遍 13 行左右：解码不认识的值就落到 `.unknown`，`.unknown` 编码成 `nil`（AGENTS「枚举解码遇未知值不许整条崩」）。

`Core/Models/OrderModels.swift:59` `RunOrderStatus`、`:312` `PacePreference`、`:354` `RoutePreference`、`:1077` `ReviewLevel`；`Core/Models/RunRecordModels.swift:24` `RunRecordStatus`、`:38` `RunRecordRole`；`Core/Models/VoiceOrderModels.swift:70`、`:93`、`:116`；`Core/Models/VolunteerDispatchSummaryModels.swift:54`。

建议：建一个协议 `UnknownTolerantStringEnum`，默认实现这两个方法，各枚举只声明遵循。**`RunOrderStatus` 是订单状态机，本轮不动**，其余 9 个可以改。
风险：这是解码路径。`blindRunTests/Fixtures/` 的真实响应回归能守住，但 11-05 起不跑真机测试，只能靠编译和读代码。

### P1 Periphery：不在红线里的未使用声明（低）

38 处，大部分是设计常量和文案，删了不会改变行为。完整清单见附录 A。比较大的几块：

- `Core/DesignSystem/FlowMetrics.swift`：9 个常量和 2 个方法（`:67`、`:71`、`:72`、`:74`、`:76`、`:82`、`:84`、`:85`、`:206`、`:344`、`:370`）。
- `Core/DesignSystem/FlowPalette.swift:120-123`（雷达图 4 色）、`:360`。
- `Core/DesignSystem/BlindControls.swift:85` `secondaryFillButtonLabel`、`ButtonChrome.swift:101` `capsuleButtonsInRow`。
- `Core/APIClient.swift:188` `patch(_:body:requiresAuth:)`：全仓没有 PATCH 请求。
- `Voice/VoiceOrderWizard.swift:282`、`:294`：两个没人调的方法。语音下单逻辑本身要保留（#816 的决定），只删这两个方法。

---

## 只报告，不建议本轮改

### D8 距离格式（要先定小数位数）

公共的有 `Map/DistanceCalculator.swift:57` `formattedDistance`（「X.X 公里」或「XXX 米」）和 `Shared/RunRecordHistoryView.swift:293` `kilometres`（两位小数）。各处另有大约 10 个 `String(format:)`，**小数位数三种并存**：
- 两位：`Core/Models/OrderTrackModels.swift:24`、`Volunteer/VolunteerOrderFlowStep.swift:181`、`Volunteer/VolunteerOrderV2.swift`、`Core/RunLiveActivityController.swift:50`、`Volunteer/VolunteerOrderFlowPage.swift:652-663`（3 次）。
- 一位：`Core/Models/IntroCallModels.swift:475`、`Volunteer/VolunteerOrderFlowStep.swift:149`、`Volunteer/VolunteerRunDataCopy.swift:18`、`Xinghuo/XinghuoSnapshot.swift:66`、`Volunteer/VolunteerSecondaryPagesCopy.swift:41`。
- 整数省掉「.0」：`Core/Models/OrderDisplayHelpers.swift:1022`。

时长和配速也有同样的情况：「39 分 20 秒」带空格，「39分20秒」不带空格，两种并存（`Core/Models/OrderTrackModels.swift:33`、`Volunteer/VolunteerOrderFlowStep.swift:201`、`Shared/RunRecordPresentation.swift:205`）。

**要负责人定**：计划距离、实际距离、离你多远，各用几位小数。定了以后再合。不定就不改。

### D9 跑后记录两端页面（牵涉设计）

`BlindRunner/RunnerRunRecordView.swift`（623 行）和 `Volunteer/VolunteerRunRecordView.swift`（783 行）有 5 段克隆（jscpd #12、#37、#38、#62，以及 #59 `Shared/RunRecordFitnessMap.swift:285`），共约 50 行：加载 / 失败 / 已加载三态切换、数据小节、有地图和没地图两种滚动页。两页的小节顺序和内容不同（陪跑员页有评价、搭档）。合成一页要先定版式，这是第 3 轮（架构）的事。

### D10 首页刷新的「同一时间只跑一个请求」写法（并发，留到第 3 轮）

`BlindRunner/BlindRunnerHomeView.swift:211-228` 和 `Volunteer/VolunteerHomeViewModel+Loading.swift:43-60`（jscpd #10，18 行）：用 `Task` + `withTaskCancellationHandler` + 请求编号实现「同一时间只跑一个请求」。全仓用 `withTaskCancellationHandler` 的有 5 个文件。
抽成公共工具要动 `weak self` 和取消时序，真机偶现的问题编译查不出来（记忆 `unannotated-async-closure-property-crashes-on-device`）。留到第 3 轮。

### D11 三个隐私同意弹窗（大档）

`Core/PrivacyConsentGateView.swift`（235 行）、`Shared/ConsentDisclosureView.swift`（220 行）、`Shared/LocationTrackPreAlertView.swift`（172 行）的骨架相同：标题、摘要、展开详细说明、同意 / 拒绝。jscpd #13、#41、#42、#51、#52，共约 50 行。这属于隐私权限，按 AGENTS §10 是大档，要先建 OpenSpec 变更才能改。另外 Periphery 报 `ConsentDisclosureView.swift:204` 有一个没人用的 `init`。

### 红线（只报告，不改）

| # | 位置 | 情况 |
|---|---|---|
| R1 | `Core/Models/OrderDisplayHelpers.swift:902-924` 和 `Volunteer/VolunteerInviteQueue.swift:165-184`（jscpd #5，23 行） | 接单前后展示给陪跑员的「视力情况 / 引导方式」。两份**故意不同**：邀请卡不出「跑者没有填写」那一行，注释写了原因，`EscortNeedsTests` 逐字守着。属于 AGENTS §8「接单前能给志愿者看什么」，不合 |
| R2 | `Volunteer/VolunteerProfileView.swift:50` | 自己切字符串打星号，绕开了 `maskPhone`（`Core/Models/ProfileModels.swift:307`），还多了一条「已经是掩码就原样用」的判断，公共函数里没有。属于掩码红线，只报告 |
| R3 | `BlindRunner/BlindOrderStatusViewModel+Realtime.swift:18-28` 和 `Volunteer/VolunteerInServiceViewModel.swift:142-152`（jscpd #20）；`+VolunteerLocation.swift:8-16、52-68` 和 `VolunteerInServiceViewModel+Nudges.swift:101-109`、`+OrderUpdates.swift:75-91`（jscpd #36、#11） | 两端订单页各写一遍「订阅实时状态推送 / 对方位置过期」。**两边都用 Combine `.sink` 存进 `cancellables`，回调里再起 `Task { await … }`**（`BlindOrderStatusViewModel+Realtime.swift` 4 处，`VolunteerInServiceViewModel.swift` 7 处）。这和 CLAUDE.md「并发模型只用一种」冲突，留给第 3 轮 |
| R4 | `Core/AppRealtimeCoordinator.swift:237-246` 和 `:262-271`（jscpd #25） | 派单队列的「清掉 / 撤回邀请」两段相同的匹配逻辑。派单，不改 |
| R5 | `Safety/EmergencyCountdownView.swift:257-266` 和 `Safety/VolunteerEscortViews.swift:218-227`（jscpd #27）；`EmergencyCountdownView.swift:167-175` 和 `Safety/SafetyModule.swift:177-185`（jscpd #44） | 求助页的界面片段。SOS，不改 |

另有一处死代码和重复叠在一起：`BlindRunner/BlindOrderStatusViewModel+Loading.swift:164` 的 `performAction` 和 `BlindRunnerHomeView.swift:447` 逐行相同（jscpd #4，26 行），**而 Periphery 报前者根本没人调用**。删掉它不改变行为，但文件在订单页里，放进附录 B 交给负责人定。

### jscpd 其余克隆

67 段里，上面没提到的大多是同一文件内部的相似片段（`Map/AMapContainer.swift` 4 段、`Map/AMapGeocodingService.swift`、`Auth/LoginViewModel.swift`、`Volunteer/RopeView.swift`、`Volunteer/VolunteerInviteSheet.swift` 各 1 段），每段 7–23 行。这些是同一个类型里的相近分支，合起来收益小，不列入批次。`BlindRunner/BlindBookingView+StepSections.swift` 的两段（#14、#15）在 #816 要删的文件里，会自然消失。

## 界面上的其他发现（不在批次里）

- 直接调 `UIAccessibility.post(notification: .announcement, …)`、不走 `VoiceService` 的有 3 处：`Volunteer/VolunteerTrainingQuizView.swift:60`、`Volunteer/VolunteerPartnerDetailView.swift:216`、`Volunteer/VolunteerFinishLongPress.swift:196`（全仓 4 处，另一处是 `VoiceService` 自己）。都在陪跑员端，播报会和 TTS 抢话。要不要收进 `VoiceService`，留到第 3 轮。
- `Shared/RunRecordAudio.swift:214` 自建了一个 `AVSpeechSynthesizer`。注释写明这是有意的（不想同时发 VoiceOver 通告），不算重复。
- 手写 `Image(systemName: "chevron.right")` 的地方约 20 处，各页自己写的行骨架约 7 个（子代理估计，没有逐处核实）。公共的 `SettingsChevron`、`SettingsRowLabel` 已经有了。收益分散，不单列批次。
- 盲人端和陪跑员端的固定搭档列表、搭档详情是两套（jscpd #18、#28、#54），注释写明盲人端「不跟着改」（`Volunteer/VolunteerPartnersView.swift:14`）。这是产品上有意分开的，不合。

## Periphery 195 处分诊

| 类 | 条数 | 处理 |
|---|---|---|
| `Packages/AidRunAPI` 生成代码 | 8 | 保留。生成代码只用来探测契约漂移 |
| `#Preview` 结构体、组件画廊、动画演示 | 9 | 保留，测试设施 |
| 在 #816 要删的文件里 | 15 | #816 合并后自然消失 |
| 在 #816 要改的文件里（`BlindBookingViewModel+*` 等） | 30 | #816 合并后复扫再看，现在不动 |
| #839 的 3 个类型（`LocationPermissionGuard`、`DemoLocationBanner`、`MapViewModel`；`BlindMenuPicker` 算在 #816 那 45 条里） | 3 | 由 #839 删 |
| 测试 target 里只写不读的属性 | 23 | **大多保留**：`appState`、`retainedAppState` 这类是故意持有，防止被 `weak` 依赖提前释放（记忆 `location-service-test-seam-and-weak-viewmodel-deps`）；`Fake*Service.last*` 是没断言的探针，删不删都行 |
| 测试 target 里没用到的方法和属性 | 2 | `blindRunUITests+AssertionHelpers.swift:149` `leftPadded`、`blindRunUITests.swift:28` `shouldRunCloudSmoke`，可以并进 P1 |
| App 里只写不读的属性 | 34 | **基本是误报，保留**：抽查的 4 个都是 `Equatable` / `Hashable` 结构体的字段，用来判断「变了没有」，例如 `AppRealtimeCoordinator.swift:9` `OrderStatusEventFingerprint`、`AppUpdateGateModifier.swift:21` `RefreshKey`、`VolunteerTabView.swift:54` `RequiredUpdatePauseTrigger`、`VolunteerRunRecordView.swift:20` `SplitRow`（`Hashable`，用作 `ForEach` 的 id） |
| App 里没用到、且不在红线里 | 36 | 附录 A，即批次 P1 |
| App 里没用到、在红线或核心路径里 | 35 | 附录 B，只报告，逐条交给负责人 |

合计 8 + 9 + 15 + 30 + 3 + 23 + 2 + 34 + 36 + 35 = 195。

### 附录 A：可删（P1，低）

`BlindRunner/BlindActiveRunView.swift:178` `previewRunning` · `BlindRunner/BookingSlotPlanner.swift:234` `weekdayShortName(_:)` · `ContentView.swift:82` `cancel()` · `Core/APIClient.swift:188` `patch(_:body:requiresAuth:)` · `Core/DesignSystem/BlindControls.swift:85` `secondaryFillButtonLabel` · `Core/DesignSystem/ButtonChrome.swift:101` `capsuleButtonsInRow()` · `Core/DesignSystem/FlowMetrics.swift` `:67` `visualSide`、`:71` `successBadgeDiameter`、`:72` `successBadgeRingWidth`、`:74` `progressRingWidth`、`:76` `statusTitleTopSpacing`、`:82` `partnerAvatarDiameter`、`:84` `partnerRowVerticalPadding`、`:85` `partnerRowHorizontalPadding`、`:206` `v2CTAStrokeWidth`、`:344` `actionButtonHint()`、`:370` `partnerHeadline()` · `Core/DesignSystem/FlowPalette.swift` `:120-123` `radarOuter`/`radarOuterStroke`/`radarInner`/`radarInnerStroke`、`:360` `warmCardBody` · `Shared/HomeRecoverySupport.swift:35` `recordDuration` · `Shared/RunRecordHistoryRows.swift:85` 参数 `role` · `Shared/RunRecordHistoryView.swift:71` `previousMonthTitle`、`:72` `nextMonthTitle` · `Shared/SpokenNavigationTitle.swift:11` `spokenNavigationTitle(_:spoken:)` · `Shared/WeChatShareCard.swift:39` `thumbnailSide` · `Voice/VoiceOrderWizard.swift:282` `finishSpeaking()`、`:294` `finishSpeakingOrSkipPrompt()` · `Volunteer/PartnerStreakCopy+Volunteer.swift:65` `volunteerEmptyFootnote` · `Volunteer/VolunteerAchievements.swift:334` `summarySpeech(_:)` · `Volunteer/VolunteerHomeIncentive.swift:173` `empty` · `Volunteer/VolunteerHomeView.swift:35` `modal`、`:40` `tile` · `Volunteer/VolunteerHomeViewModel.swift:228` `statusColor` · 测试：`blindRunUITests/blindRunUITests+AssertionHelpers.swift:149`、`blindRunUITests/blindRunUITests.swift:28`

路径都相对于 `blindRun/`，测试那两条除外。删之前每条要全仓按完整单词再搜一次。Periphery 读的是编译器索引，但 `#if DEBUG` 外的字符串反射看不到。

### 附录 B：红线或核心路径（只报告）

- 订单页、SOS：`BlindRunner/BlindOrderStatusView.swift:241` `canShowEmergency`、`:260` `shouldPoll`、`:376` `isFinishedPhase` · `BlindRunner/BlindOrderStatusViewModel+Actions.swift:178` `enterEmergency()` · `BlindRunner/BlindOrderStatusViewModel+Loading.swift:164` `performAction`（见上文，和首页那份重复）· `BlindRunner/BlindOrderStatusView+VolunteerSections.swift:152` 参数 `order` · `BlindRunner/BlindOrderFlowStep.swift:154` `partnerSummaryLabel` · `Safety/SafetyModule.swift:327` `volunteerSafetyHubTitle`
- 通话磨合：`Core/Models/IntroCallModels.swift:224` `blindCallSectionAnnouncement`、`:289` `blindAfterCallSubtitle`、`:303` `blindStartAddressPrefix`、`:304` `blindPlannedTimePrefix` · `Core/MockAPIClient.swift:176` `simulateIntroCallDecisionForTesting`
- 订单模型与位置上报：`Core/Models/OrderModels.swift:671`、`:675`、`:679` 三个 `decode(_:forKey:)`，`:773` `sendable`，`:1333` `LocationPoint`，`:1353` `BlindLocationRequest`；`Map/MapModule.swift:42` `extension LocationPoint`
- 陪跑员订单页：`Volunteer/VolunteerOrderFlowStep.swift:18` `title`、`:27` `allTitles` · `Volunteer/VolunteerOrderV2.swift:71` `ropeState`
- 实时连接、推送、登录：`Core/RealtimeEventModels.swift:74` `remainingSeconds(at:)` · `Core/WebSocketService.swift:136` `connectionGenerationForTesting`、`:212` `decoder` · `Core/PushNotificationsManager.swift:141` 参数 `error`、`:233` `hasLocalTokenBindingForTesting` · `Core/SessionTokenRefresher.swift:108` `hasCredential` · `Auth/LoginView.swift:165` 枚举值 `phone`
- 实名认证：`Volunteer/VolunteerRegistrationFlowView.swift:243` `sdkUnavailable`、`:245` `internalError`、`:247` `deviceTimeError`、`:249` `unknown(code:)`
- 隐私：`Shared/ConsentDisclosureView.swift:204` `init(purpose:onAgree:onDecline:)`

`*ForTesting` 结尾的几个，Periphery 扫描时带了测试 target，仍报没用到，说明连测试都不调用它们了。

## 怎么判合对了

- 每批 `build-for-testing`（真机、不签名）编译通过。
- 每批合完，jscpd 用上面的命令复扫：克隆段数和重复行数下降（基线 67 段 / 766 行）。删代码的批次再用 Periphery 复扫（基线 195）。数字写进 PR。
- 合并后被删的类型名，全仓按完整单词搜，结果是 0。
- 改了文字输出的批次（D3、D4），列出前后字符串对照，写进 PR。

## 没覆盖的

- 没跑真机测试（2026-11-05 起只编译）。D4、D7 这种改输出或解码的批次，风险只能靠读代码和测试里的期望字符串来压。
- 子代理报的「约 20 处箭头」「约 7 个行骨架」「114 处 `RoundedRectangle`」是估计值，没有逐处核实。
- jscpd 只比 token，`--min-tokens 50` 以下的短重复（3–5 行）没统计。
- 没查 `Assets.xcassets` 里没用到的图片（FengNiao），留到删代码的批次合完以后再查。
