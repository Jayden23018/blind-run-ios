# 接单前通话磨合（`PENDING_INTRO_CALL`）现状审查：两端界面、等待、聊后信息、后端改期能力

- 日期：2026-10-15
- 基点：iOS `origin/main`（`aa2c149`）与在途 PR #400（`origin/feat/intro-call-restyle`，v6 外观重做，草稿）；后端 `Jayden23018/blind-run-backend` 的 `origin/main`
- 缩写：B = `blindRun/BlindRunner`，V = `blindRun/Volunteer`，M = `blindRun/Core/Models`；后端 S = `src/main/java/com/example/demo/`
- 配套：调研 `docs/research/intro-call-post-call-coordination-20261015.md`；设计 `docs/design/2026-10-15-intro-call-meetup-plan-design.md`

## 一句话结论

负责人提的三件事里：**界面**已有 v6 定稿与 PR #400，但它只换外观、行为漏洞全部还在；**等待界面**有四段，其中三段 App 根本没有数据可画；**聊后补充 / 修改见面信息**是真漏洞 —— 契约里没有任何字段，后端没有任何下单后改时间或地点的路径。

## 1. 两端屏幕

### 盲人端（`B/BlindIntroCallView.swift`）

订单进入 `PENDING_INTRO_CALL` 时由订单页 `fullScreenCover` 自动弹出（`B/BlindOrderStatusView.swift:2336`）；关掉后订单页留入口「和这位志愿者通话确认」（`:2800-2815`）。

| 子状态 | main | PR #400 |
|---|---|---|
| 加载中 / 失败 | 「正在获取…」/「暂时拿不到通话信息」+ 重新加载、换一位 | 同文案，换成底栏样式 |
| 未拨号 | 「X想陪你跑」+ 出发地、时间、剩余分钟；「打电话给这位志愿者」「换一位」 | 头卡 + 进度绳；新增底栏「求助与安全」 |
| 拨号后回到前台 | 「和X聊得怎么样」；「聊过了，合适」「再打一次」「换一位」 | 同 |
| 已表态等对方 | 「已经告诉系统你觉得合适…」；「再打一次」「换一位」 | 同 |

### 陪跑员端（`V/VolunteerIntroCallView.swift`）

| 子状态 | main | PR #400 |
|---|---|---|
| 等来电 | 「通话确认」+ 掩码号 + 截止日期时间；「合适，接这一单」「不合适」「一直没接到电话」 | 「等X打电话给你」+「HH:mm 前聊完」 |
| 已表态 | **界面不变**，三个按钮仍在，无播报 | 标题改为已说合适，只剩「不合适」，仍无播报 |
| 约好 | 「已约好，这一单是你的。」+「进入服务流程」 | 原地换成订单页 |
| 没约成 | 「这一单已经安排好了…」+「返回首页」 | 中性文案，3 秒后自动关页，无按钮（`V/VolunteerIntroCallView.swift:237-246`，PR） |

## 2. 四段等待：系统知道什么

| 等待 | 现状 | 缺口 |
|---|---|---|
| 通话中 | 盲人端只靠 `scenePhase == .active && didDial` 判断「回来了」（`B/BlindIntroCallView.swift:135-138`）；陪跑员端无任何感知，只有 5 秒轮询 | 解锁、权限弹窗、拨号确认框点取消都会被当成「聊过了」；分不出没打通与打完了 |
| 一方表态等另一方 | 盲人有一句播报；陪跑员 main 无任何反馈 | 陪跑员可重复点「合适」 |
| 窗口快到点 | 盲人分钟级「还剩 N 分钟」，不足 1 分钟整行消失（`M/IntroCallModels.swift:245-250`）；陪跑员只有截止时刻 | 无临期提醒，无「已超时」说法 |
| 约好后过渡 | 状态变化后通话页关闭并播报（`M/OrderDisplayHelpers.swift` 约 437-450 行） | 盲人仍在通话中时，优先级低于 alert 的播报会被丢弃（`blindRun/Voice/AnnouncementQueue.swift:75-76,108-110`） |

后端发的 `INTRO_CALL_READY / INCOMING / CONTINUE / CLOSED` 四种事件，iOS 都没有专门处理，只当普通通知朗读（`blindRun/Core/AppRealtimeCoordinator.swift:893-931`）。推送点击不深链到通话页。

## 3. 聊后补充 / 修改见面信息

- iOS 唯一入口：盲人 `PUT /runner-message`（≤40 字，`B/RunnerMessage.swift`），只在 `SCHEDULED_CONFIRMED / PENDING_ACCEPT / DRIVER_EN_ROUTE / DRIVER_ARRIVED` 可用，通话阶段不可用。
- 陪跑员快捷消息只有三条预设（「我到入口了」「再等我5分钟」「我快到了」），只在出发后可发（后端 `QuickMessageCode:14-20`）。
- 契约中搜「见面地点 / 穿着 / meetingPoint / clothing」0 命中。
- 后端：出发地与开跑时间**只在建单时写**（`S/OrderCreationService.java:194-207`）；`OrderController` 的 PUT/PATCH 只有 `runner-message`、`keep-waiting`、`keep-rematching`。
- 衣着颜色字段：后端 issue Jayden23018/blind-run-backend#363 于 2026-09-25 暂缓，卡在「全盲用户不一定清楚自己当天衣服颜色、入口放哪一步要产品定」。

## 4. 后端：若要改期 / 改地点，会碰到什么

- **下单五道门槛内联在 `createOrder`**（`S/OrderCreationService.java:91-181`），除 `overlapsNightWindow`（`:250-262`，static）外没有抽方法。
- **盲人时段冲突检查不排除本单**（`existsBlindTimeConflict`，`RunOrderRepository:98-104`）；陪跑员侧 `hasTimeConflict`（`DispatchService:608-615`）已排除自身，可照抄。
- **提醒标记只升不降**：`markScheduledNotifyStage` 条件是 `scheduledNotifyStage < :stage`（`RunOrderRepository:840-842`），`markDepartReminded` 用 `IS NULL` 占位（`:897`）⇒ 约好后改期，已发提醒不会重发。
- **临期闸门**：`departure-gate-lead` 60 分钟，未确认则 `handleDepartureGateMissed` 退回 `REMATCHING` 并记陪跑员爽约（`OrderLifecycleService:1116-1148`）。
- **远期 / 即时分流只在成单时算一次**（`DispatchService:778-780`，阈值 240 分钟）。
- 动作时间窗（`earliestDepartureAt` 等）按 `plannedStartTime` 实时算，会自动跟随（`RunOrder:90-93,137`）。
- 集合点到达判定 `MeetingPointService:65-72`，已推通知的去重 key 24 小时不重置。
- ⇒ **在成单之前改（通话态之内）可以绕开以上全部问题**；约好之后再改，要处理提醒重置、分流重算、闸门误判三件事。

## 5. 通话窗口生命周期（后端）

- 开始：志愿者 `INTERESTED` → `IntroCallService.java:193,212`；窗口 20 分钟（`application.properties:357`）。
- 到期：`TimeoutScheduler.java:319-321` 每 10 秒扫一次；`handleWindowTimeout`（`IntroCallService.java:397-412`）**不看谁已表态**，一律按 TIMEOUT 结束。
- 未满 3 轮退回 `PENDING_MATCH` / `REMATCHING` 并重新派单；满轮转 `NO_VOLUNTEER`。
- 后端**不知道电话是否接通**：`/call/initiate` 是隐私号残留，`aliyun.private-number.enabled=false`，且要求订单已有志愿者，通话期调不通（`CallController.java:67-69`）。

## 6. 漏洞清单

| # | 版本 | 问题 | 严重度 | 处理 |
|---|---|---|---|---|
| 1 | main + PR | 陪跑员 `load()` 把 `networkError`、429、解码失败都当「本轮结束」，弱网一次就停止轮询、播报已结束 | 高 | 已开 Jayden23018/blind-run-ios#428 |
| 2 | main | 盲人通话页没有求助入口 | 中 | PR #400 已加 |
| 3 | main + PR | 盲人表态失败只有语音，屏幕上不显示 | 中 | 设计第 5 节 |
| 4 | main + PR | `returnedFromDialer` 是页面本地状态，关页重进就回到拨号前 | 中 | 设计第 3 节（子状态改由服务端安排单决定） |
| 5 | main | 陪跑员点「合适」后无任何反馈，可重复点 | 中 | 设计第 2 节 |
| 6 | main + PR | 已说合适后副标题仍是「先打个电话聊聊」 | 低 | 设计第 3 节 |
| 7 | main + PR | 无临期提醒；最后 1 分钟倒计时消失；无「已超时」 | 中 | 设计第 4 节 |
| 8 | main + PR | 「回到前台」误判（拨号确认框取消、权限弹窗、解锁） | 中 | 设计第 3 节 |
| 9 | main + PR | 盲人拨号后志愿者没接，盲人页面无任何提示 | 中 | 设计第 4 节（B2 保留「再打一次」） |
| 10 | main + PR | 每次「再打一次」都发 `notify-incoming`，无节流 | 低 | 设计第 4 节 |
| 11 | main + PR | 已说合适后「换一位」仍在，无「改回合适」 | 低 | 方案 A 下由安排单版本处理 |
| 12 | main + PR | 「重复当前状态」只念订单级文案，不知道子状态 | 低 | 设计第 3 节 |
| 13 | main + PR | 通话中约好的播报可能被丢 | 中 | 方案 A 下盲人在 App 内点确认成单，不在通话中 |
| 14 | main | 陪跑员没约成文案「已经安排好了」对多数情况是错的 | 低 | PR #400 已改 |
| 15 | main + PR | 推送不深链；盲人冷启动要手点订单卡 | 低 | 未纳入本设计 |
| 16 | main + PR | 双方同时表态无客户端处理，依赖后端 | 低 | 方案 A 下由版本号 409 处理 |
| 17 | PR | 陪跑员出错后标题回到「等X打电话」且无重试按钮 | 低 | 设计第 5 节 |

## 7. 测试覆盖

`blindRunTests/IntroCallTests.swift`（main，1319 行）覆盖状态机解码、号码单向、文案红线、端点角色、弹出规则、冷启动恢复。**未覆盖**：scenePhase 驱动的阶段切换、陪跑员 `load()` 在网络错误下的行为、盲人表态失败时的可见错误、陪跑员点合适后的界面变化。PR #400 的真机单测与截图都还没跑。

## 复核触发条件

PR #400 合并或关闭；后端通话或订单修改相关端点变化；#428 修复后重核第 6 节 #1。
