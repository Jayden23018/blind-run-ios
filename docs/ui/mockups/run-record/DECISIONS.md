# 跑后运动记录 · 已定决策与现状事实

> 2026-09-24 第 0 步会话产出。**与 HANDOFF.md 冲突时以本文件为准**（本文件记录的是对 HANDOFF 的有意偏离）。
> 每个阶段一个新 session、一个分支、一个 PR；阶段结束时把新定的事项追加到本文件末尾「变更记录」。

## 一、项目负责人已拍板（2026-09-24）

| # | 决策 |
|---|---|
| D1 | **坐标沿用 GCJ-02**（全系统契约 `demo/docs/api_spec.yaml:7`）。不新增 WGS-84 存储；iOS 上报前已在 `LocationService` 单点转换，渲染直接交给高德，不二次转换。示例 JSON 的 `coordSystem` 改为 `GCJ02`。距离直接用 GCJ-02 点算 |
| D2 | **地图用高德**（不是 MapKit）。HANDOFF 里的 MapKit API 换成高德等价能力；高德渐变折线/快照的具体 API 在阶段 4 开工前查官方文档确认，不凭记忆 |
| D3 | **步数/步频/相对海拔：两台手机各自采集、各自上报、分别计算**。陪跑员手机也申请「运动与健身」权限。界面上**各自显示自己手机采集的数据**（跑者页显示跑者的，陪跑员页显示陪跑员的） |
| D4 | **服务时长口径 = 开始服务（进入 `IN_PROGRESS`，取 `order_status_logs`）→ 订单完成**，与 `GET /api/volunteer/achievements` 的 `totalServiceMinutes` 同口径。HANDOFF 的「会合确认 → 完成」作废 |
| D5 | **不显示确认状态**：本版不出现「待确认」标签，也不写「组织确认后计入志愿时长」—— 后端没有确认流程，不承诺做不到的事 |
| D6 | 跑者**可以看到这位陪跑员的累计服务时长**（新暴露字段，后端下发）；陪跑员**看不到跑者的历史记录** |
| D7 | 现有评价里跑者的文字评论对陪跑员隐藏（`commentWithheld`）**维持不变**；跑后留言是独立通道，双方可见 |
| D8 | 新颜色**加进 `AppColors`**（盲道黄 `#F7BE00`、陪跑绳橙 `#FF6A13`、配速快 `#3558F0` / 中 `#19B3A6` / 慢 `#F5B100`），深色变体实现时补并验对比度 |
| D9 | 记录 tab 采用合并方案：上方为 HANDOFF 新列表（月度汇总、每行公里数、陪跑员行带路线缩略图）；已取消 / 无人接单的订单收进底部「未完成的预约」分组，保留现有「已完成的跑步」转子 |
| D10 | **扩充上报**：`LOCATION_UPDATE` 增加可选 `hAcc`、`speed`、`alt`、`steps`、`cadence`；轨迹表加对应可空列。旧客户端不受影响 |
| D11 | 点击区域按仓库 64pt（`FlowMetrics.actionButtonMinHeight`），不是 HANDOFF 的 44pt |
| D12 | 记录读取权限先与 `/track` 一致（仅订单双方）；管理员读取暂不做 |
| D13 | 新陪跑员详情页**替换** `OrderRouteReplayView`；订单详情里的 `CompletedTrackSummaryView` 保留，改为新详情页的入口 |
| D14 | 接口命名服从后端现有风格，建议 `GET /api/orders/{id}/run-record`、`GET /api/orders/mine/run-records?month=YYYY-MM`、`POST /api/orders/{id}/run-record/messages`；`orderId` 用 `Long` |
| D15 | 用户要求**每个阶段跑全部测试**：后端完整 `./gradlew test`；iOS 用 `scripts/device-test-all.sh` 真机分批全量。每阶段三组截图（浅色 / 深色 / 最大字号），真机拍（模拟器因高德永久不可用） |
| D16 | 后端和 iOS 在**同一 session 双挂载**做契约相关工作；一次改两端时**后端 PR 先合**，iOS 才推得上去 |

## 二、后端现状（`demo` origin/main `ee11d20`，2026-09-24 调研）

- Spring Boot 3.5.16 / Java 17 / Gradle / MySQL。**无 Flyway**：手写 SQL 在 `migrations/`（最新 `0046`），`deploy.sh` 有迁移登记闸门。测试 H2（MySQL 模式，Hibernate 自建表，不读 migrations）+ Testcontainers Redis；`@Test`+`@ParameterizedTest` 共 1099 处（HANDOFF 的「116」过期）。`SpecDriftTest` 只比 METHOD+path。
- 轨迹：`entity/RunOrderTrackPoint.java`（order_id, user_id, role, latitude, longitude, recorded_at），**只在 `IN_PROGRESS` 落库**（`BlindLocationService.java:97-103`，志愿者侧 `VolunteerLocationService` 同构），`RunOrderTrackService.recordIfDue` 用 Redis SETNX 每 10 秒抽稀（`app.track.sample-interval-seconds`），Redis 不可用时本次不落。
- `GET /api/orders/{id}/track`：`OrderController.java:326-341`。⚠️ `getTrack` 只取**最近 500 点**（`app.track.max-points-per-query`），长单丢前段 —— 跑后记录计算**必须读全量**（`statsHardCap` 5000）。
- 完赛快照：`RunOrder.actualDistanceMeters / actualDurationSeconds / actualAvgPaceSecPerKm`，`RunOrderTrackService.snapshotCompletionStats()`（:185）在 COMPLETED 时写一次 —— 可用于「与上次比较」。
- 时间点：`acceptedAt`、`blindStartConfirmedAt`（可空）、`finishedAt`；en-route / arrived / start-service 只在 `order_status_logs`（`GET /api/orders/{id}/status-logs`）。
- 服务时长：`dto/volunteer/VolunteerAchievementsResponse.java` 的 `totalServiceMinutes`，无确认流程。
- 留言：不存在。评价 `OrderReview` 每单一条、盲人→志愿者、志愿者侧 `commentWithheld`。
- 紧急求助按订单查：`EmergencyEventRepository.findByOrderId`（:54）无调用方、无端点 → 记录里的 `sosTriggered` 由后端计算。
- 文件：`OssFileStorageService`（`app.storage.type=oss`），客户端 multipart 传后端，不直连 OSS。
- 按月汇总：无；历史只有 `GET /api/orders/mine`（分页）。
- 休息点、配速分段：均无。
- 本地网络：Gradle 必须带代理 `GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897"`。

## 三、iOS 现状（`blind-run-ios` main `11551af`）

- SwiftUI + MVVM，iOS 16。端点 `enum XxxEndpoint` → Service → `transport.send`（例：`Core/Services/SafetyService.swift:44-45, 147-149`）；Mock 进程内（`Core/MockAPIClient.swift:509, 735-762`）。
- 坐标：`Map/CoordinateSystem.swift`（`BackendCoordinateNormalizer`）；`TrackPoint.backendCoordinate` 按 GCJ-02 原样通过。
- 地图：`Map/AMapContainer.swift`（UIViewRepresentable，外包 `MapViewWrapper`）。折线只有固定色宽（`isPrimary` systemBlue 7pt），**无渐变/描边**；已跟随系统明暗（`.standardNight`）。
- 已有跑后界面：`Shared/CompletedTrackSummaryView.swift`（调用点 `Volunteer/VolunteerOrderFlowViews.swift:855/2005/3814`、`BlindRunner/BlindOrderStatusView.swift:2334`）、`Shared/OrderRouteReplayView.swift`（`TrackRouteMap`、`TrackStatsRow`）。模型 `Core/Models/OrderTrackModels.swift`。
- 记录 tab：跑者 `BlindRunner/BlindRunHistoryView.swift`；陪跑员 `VolunteerServiceRecordsView`（`Volunteer/VolunteerOrderFlowViews.swift:2097`）。
- 设计 token：`Core/DesignSystem/AppColors.swift`、`FlowMetrics.swift`（`FlowFonts`）。
- 语音：TTS 出口 `Voice/SpeechService.swift` 的 `VoiceService`；音频会话 `Voice/SpeechInputService.swift`（`SystemSpeechAudioSession`，改它 = 全量测试）。无 Charts / CMPedometer / CMAltimeter / AVAudioRecorder。
- 测试：只能真机；fixture 在 `blindRunTests/Fixtures/`（`scripts/capture-fixtures.mjs` 采真实后端）+ `ContractFixtureTests`；UI 测试 `blindRunUITests/`（含 `AccessibilityAuditTests`）。深色模式截图目前**无启动参数开关**，需加 DEBUG-only 启动参数；最大字号可用 `-UIPreferredContentSizeCategoryName`。
- 行为变更需 OpenSpec 变更（iOS 仓库 `openspec/changes/`）；相邻变更 `enable-live-escort-location-and-track-summary` 触及同一能力，别让两边规格打架。

## 四、阶段

| 阶段 | 仓库 | 内容 |
|---|---|---|
| 1 | demo | 迁移 0047、上报扩充字段落库、`RunRecordService` 计算、3 个接口、契约测试、`api_spec.yaml` / `websocket-protocol.md` |
| 2 | ios | OpenSpec 变更 `add-post-run-record`、DTO、Endpoint、Service、Mock、fixture、上报扩充字段、两端计步/海拔采集 |
| 3 | ios | 记录 tab（D9） |
| 4 | ios | 陪跑员详情（P0 部分） |
| 5 | ios | 视障跑者详情（讲述、声音路线） |
| 6 | ios | 文字留言两端 |
| 7 | ios | 第 7 节无障碍走查 |
| 8 | 两端 | P1 |

## 变更记录

- 2026-09-24：初版（第 0 步会话）。
- 2026-09-24：**阶段 1（后端）**，分支 `feat/run-record-backend`（demo 仓库）。新定事项：
  - **留存（负责人本会话拍板）**：记录缓存里的坐标（路线、休息点坐标、列表缩略图）跟 `app.track.retention-days`（90 天）一起清，统计数字永久保留。超过 90 天的记录 `status` 仍是 `READY`，但 `track`、`stops[].lat/lng`、`thumbnail` 为 null
  - **生成时机**：订单完成事件 → `AFTER_COMMIT + @Async` 监听器生成（仓库既有模式）。读取时发现没有记录 / `FAILED` / `GENERATING` 超过 2 分钟 → 当场同步补算；`READY` / `INSUFFICIENT_TRACK` 永不重算（否则 90 天后原始点被清，重算会冲掉统计）。`INSUFFICIENT_TRACK` = 清洗后不足 2 个点
  - **算法细节**（HANDOFF 3.3 没写死的部分）：自动暂停段**时间和距离都不计**；`restSec = elapsedSec − movingSec`（包含 10–29 秒的短暂停）；最快段只在满 1 公里的段之间比，且至少两段满公里才有；配速点取 ±100 米窗口；爬升用 1 米死区折线滤波（一段坡计「坡顶 − 谷底」整段）；首个点对第 2 点超速、而第 2 点对第 3 点正常时，丢掉首个点；步数取这一单的最大累计值；步频 = 步数 ÷ 运动分钟，没有步数时退回上报步频的平均值
  - **与上次比较**：同一跑者上一张 `actualDistanceMeters` 非空的已完成订单，两边都用完赛快照（与 `summary.distanceM` 可能差几十米）。**只给跑者**（按 D6 推出：陪跑员看不到跑者的历史）
  - **途中事件类型**：`ARRIVED` / `RUN_STARTED`（第一次进入 IN_PROGRESS）/ `REST` / `RUN_ENDED` / `ORDER_COMPLETED`；`inferred=true` 的只有 REST 和 RUN_ENDED
  - **字段命名服从后端**：`blindName` / `volunteerName`、`fromRole: BLIND|VOLUNTEER`、`previousOrderId`；`events` 没有 `text`；`service` 没有 `meetAt` / `status`。样例 JSON 与契约的逐条映射写在 `api_spec.yaml` 的 `RunRecordResponse` 说明里
  - **月度列表**：按 `finishedAt` 归月，只含 COMPLETED；`thumbnail` 和 `serviceMin` 只给陪跑员；`partnerName` 用 `NameMaskUtils.mask`（订单详情对已完成订单的姓名规则，注销为 null）
  - **留言**：1–200 字，去掉首尾空白；本期不推送通知；随发送者注销删除；另一方给注销者的留言保留。**留言的留存期未定**（尚无自由文本表的留存口径，等隐私批次一起定）
  - **注销**：删该用户参与订单的 `run_record` 行（另一方下次打开时按剩下的原始点重算，注销者那一侧的数据变 null）
  - **上报字段**：`cadence` 单位是步/分钟（iOS 上报前 ×60）；`steps` 必须是累计值；越界字段单独丢弃，不拒整条消息
  - **契约形状**：响应走 `ApiResponse` 信封；嵌套 schema 用 `Run*` 前缀（避免 springdoc 同名覆盖）
  - ⚠️ 迁移号 `0047` 与开着的 demo PR #292 撞号，后合的改号
- 2026-09-24：**阶段 1 已上线**。demo PR #301 合并（`3dd1e05`），与 #292 一起部署到生产（jar `dee2b0a`，12:48）；迁移 `0047_run_record.sql` 已在生产执行并登记。
  ⇒ **阶段 2 的 fixture 可以直接从生产采真实响应**（生产测试号见 demo 仓库 `docs/test-accounts.md`），不必手写；采之前该账号至少要有一张已完成订单。
  审查补的一条：月度列表一次请求最多同步补算 5 张没有缓存的单，其余这一次先用订单完赛快照（`thumbnail` 为 null），下次打开再补。
- 2026-09-24：**阶段 2（iOS 数据层）**，分支 `feat/run-record-data-layer`（blind-run-ios），OpenSpec 变更 `add-post-run-record`。新定事项：
  - **「运动与健身」权限的申请时机（负责人本会话拍板）**：两台手机都在订单进入 `DRIVER_EN_ROUTE`（陪跑会话开始）时申请，不在开跑时申请。这时离起跑还远，系统弹框不会在起跑那一刻抢走 VoiceOver 焦点。本期不加说明页，只靠 `NSMotionUsageDescription` 的文案；拒绝后照常陪跑，也不会反复弹框
  - **跑步起点锚**：取本机第一次看到这张单进入 `IN_PROGRESS` 的时刻，按订单号存进 `UserDefaults`。`CMPedometer.startUpdates(from: 起点)` 返回的是累计值，App 重启后沿用同一个起点，步数不会归零（依据：本机 SDK 头文件）。没按「开始服务」的那台手机会晚几秒起算。没有用后端 `/status-logs` 的时刻，因为那要多一个请求，也多一条失败路径
  - **海拔续接**：气压计的相对海拔每次启动都从 0 开始，所以上报的是「上次报过的值 + 本次相对值」，避免重启造成的假爬升
  - **字段带的范围**：`alt` / `steps` / `cadence` 只在 `IN_PROGRESS` 带；`hAcc` / `speed` 在整个陪跑会话里都带（后端只在 `IN_PROGRESS` 落库）。空闲时的志愿者上报、接单时的上报仍然只有 `lat` / `lng`。`cadence` 取整数（步/分钟）
  - **与相邻 OpenSpec 变更 `enable-live-escort-location-and-track-summary` 的分工**：本变更只往它的 `LOCATION_UPDATE` 里加可选字段，并新增记录读取。上报节奏、后台定位、GCJ-02 转换仍归它管。`/track` 完成页在阶段 4 之前仍然是用户看到的跑后页面；阶段 4 按 D13 替换时，要在那个变更归档之后，对它的「Completed summary uses the blind track」这条要求显式写 MODIFIED
  - **开放枚举的落法**：标量字段（`status` / `viewerRole` / `fromRole` / `role`）遇到不认识的值落到 `.unknown`；`events` / `messages` 里不认识的类型、或整条格式坏掉的元素，逐条跳过。`ContractFixtureTests` 用原始 JSON 的元素个数对账，保证真实数据里一条都没被静默丢掉
  - **fixture**：来自生产订单 #131（READY、10 公里、跑者侧有 comparison，两个角色各采一份）、#139（INSUFFICIENT_TRACK）和 2026-08 的月度列表（两个角色各一份）。目前生产上所有订单的 `steps` 都是 null，因为还没有客户端上报过；留言没有真实样本（采集脚本只打只读端点），由手写用例覆盖
  - **service 暂时没有生产调用点**：这是刻意的，调用点在阶段 3–6 接上，哪个阶段做完还没接上就删掉对应方法
- 2026-09-24：**D15 作废（负责人原话「每次只跑改了的部分，不要跑全量的测试」）**。之后每个阶段只跑改动覆盖的 suite（先用符号搜调用方，再定 `-only-testing` 的范围），不跑 `scripts/device-test-all.sh`；真觉得非全量不可，先问。截图要求不变。已写进项目记忆 `scope-test-runs-to-what-changed`
- 2026-09-24：**阶段 3（记录 tab）**，分支 `feat/run-record-history-tab`（blind-run-ios），OpenSpec 变更 `add-run-record-history-tab`（新能力 `run-record-history`，读 `post-run-record` 的 `monthlyRecords`，不改它的规格）。新定事项：
  - **PR 叠在 #189 上（负责人本会话拍板）**：开工时核实 #189 仍是 OPEN（任务书写的是「已合并」），阶段 3 的 PR base 设为 `feat/run-record-data-layer`，#189 合并后改 base 为 `main`
  - **缩略图用纯 SwiftUI `Path`，不用高德截图（负责人拍板）**：高德没有 `MKMapSnapshotter` 那样的独立截图器，`takeSnapshotInRect` 与 `MAMapSnapshot` 都要一个已显示的 `MAMapView`（官方指南原话「只有内容先显示在地图上，才能进行截屏」）。依据 `blind-run-ios/docs/research/amap-snapshot-for-list-thumbnail-20260924.md`。经度乘 cos(纬度)、北在上、等比居中；描线 `paceFast`；没有点时只画底块
  - **一次只显示一个月，用「上个月 / 下个月」切换（负责人拍板）**：两行整行竖排（`design-direction.md` §4 次级操作不并排）；当月不给「下个月」；跨年时标题带年份（「2025年12月」）。「未完成的预约」**不按月过滤**
  - **测试只跑改动覆盖的 suite（负责人本会话再次确认）**：任务书里「device-test-all.sh 真机全量」那条不执行，以 D15 作废为准
  - **D8 深色变体**：只有 `paceFast` 换值（`#3558F0` → `#5B7CFA`，压 `#1C1C1E` 从 3.08 到 4.63）；其余四个压深色底都已 ≥ 3:1，亮暗同值。⚠️ **浅色下 `ropeOrange` 2.87、`paceMid` 2.61、`paceSlow` 1.88 压白底都不到 3:1**（WCAG 1.4.11），这是 D8 的取值、本阶段未改；阶段 4 画地图路线时要对着白色描边与底图判，且配速必须有数字冗余。`tactileYellow` 只当底色压黑字（12.32:1）。检查在 `LowVisionChannelTests.testRunRecordPaletteClearsTheThresholdForHowEachColorIsUsed`
  - **空状态分两种**：本月空但以前完成过 → 汇总句说「X月还没有跑步记录 / 陪跑记录」；`/api/orders/mine`（第一页）里一张已完成都没有 → HANDOFF 6.4 的首用文案。陪跑员首用文案 = 跑者那句 + 原有的「开启可服务状态后，系统会自动派单。」（HANDOFF 只写了「对应文案」，沿用旧页面的提示）。订单没读到时不给首用文案
  - **标题**：跑者「跑步记录」、陪跑员「陪跑记录」（原「我的历史订单」「服务记录」）；陪跑员「我的」首屏那个入口的读屏名同步改为「我的陪跑记录」
  - **点进去仍落到现有详情页**（阶段 4/5 再换）：跑者 → `BlindOrderStatusView`；陪跑员已完成的 → 按单号 `GET /api/orders/{id}` 取一次再进 `VolunteerReadOnlyOrderView`（月度列表只给 `orderId`）
  - **读屏**：行读成一句话（跑者「9月20日周六，深圳湾公园，和林，5.21公里」/ 陪跑员「9月6日周六，陪陈，深圳湾公园，5公里」），朗读去掉姓名的掩码星号、公里数去尾零；跑者端加载完播报汇总句 +「另有 N 条未完成的预约」，陪跑员端保持静默；「已完成的跑步」转子只念日期，条目与本月列表同源
  - **null**：距离、服务时长、搭档、地点为 null 时对应片段整段不出现，不显示 0
  - **UI 测试开关（DEBUG only）**：`AIDRUN_UI_TEST_COLOR_SCHEME=light|dark`（根视图 `.preferredColorScheme`，发布构建恒为 nil）；`AIDRUN_UI_TEST_SEED_HISTORY=1`（Mock 多一张已取消单，给「未完成的预约」截图用）。Mock 月度列表的缩略图改成 8 个点绕一圈
  - **service**：`record` / `postMessage` 仍无调用点，按阶段 2 的约定留给阶段 4–6
  - **真机审计两条带红合入（负责人本会话拍板）**：`AccessibilityAuditTests.testRunnerRecordsTab…` / `testVolunteerRecordsTab…` 只剩「未完成的预约」那一组被判「改不了字号」（跑者 4 个元素、陪跑员 5 个），而同一轮 AX-XXXL 真机截图里这些字全部放大 ⇒ 审计误报。不加白名单、不改容器，**阶段 7 无障碍走查时查根因**。排查过程与已排除的说法在项目记忆 `list-rows-false-dynamic-type-audit`。同一轮修掉了两条真的：组标题换 `AppColors.textSecondary`（系统色浅色 3.26:1 被报对比度）、读屏标签里数字与单位之间留空格（「1.04公里」被报标签不可读）
  - 截图：`run-record-handoff/screenshots/stage3/`（12 张，iPhone 16 Pro，Mock 构建）。⚠️ `records-runner-light-top.png` 顶部截到了一条真机上的微信通知横幅，外发前裁掉
- 2026-09-24：**#189 已 squash 合并进 main（`133b082`）**；#191 已变基到新 main（只剩阶段 3 的 5 个提交，diff 的 patch-id 与变基前一致），base 改为 `main`，CI 两项通过。远端分支 `feat/run-record-data-layer` 没删
- 2026-09-24：**#191 已 squash 合并进 main（`fdcae4a`）**。阶段 4 从 `main` 切分支即可，不用再叠 PR。两条带红的记录页审计用例随之进了 main，留给阶段 7
- 2026-09-24：**阶段 4（陪跑员详情，P0）**，分支 `feat/volunteer-run-record-detail`（blind-run-ios），OpenSpec 变更 `add-volunteer-run-record-detail`（新能力 `volunteer-run-record-detail`，对 `live-escort-location-and-track-summary` 的「Completed summary uses the blind track」写 MODIFIED）。新定事项：
  - **PR 直接从 main 切**：开工时核实 #189 已合并；#191 在本会话开工后几分钟内合并（`fdcae4a`），所以没叠 PR。**最终 base 是 `origin/main` `7776ade`**：写到一半，共享 checkout 被别的 session 切到了 `chore/auto-build-number`，我的未提交改动被一起带走（没落错提交）；已改到 `/tmp/aidrun-stage4` worktree 里，从最新 main 重打补丁（`AMapContainer.swift` 与 #184 星火页重做冲突，手工重放），重跑测试。下个阶段开工就在 `/tmp` worktree 里做⚠️ 上一条变更记录写「#191 已合并」时它其实还是 OPEN，本会话第一次 `gh pr view` 还是 OPEN —— 下个阶段照样先核实
  - **归档顺序（负责人本会话拍板）**：`enable-live-escort-location-and-track-summary` 还没归档（卡在 6.6 双机真机验证），本变更照样写 MODIFIED，但**必须在它之后归档**；本 PR 不归档本变更，`tasks.md` 的 3.5 留着没勾
  - **路线描边改近黑 `#1C1C1E`，不是 HANDOFF 的白色（负责人本会话拍板）**：配速线的边缘贴着描边，压白色「中」2.61、「慢」1.88，亮暗两种外观都一样不到 3:1；压近黑三档都 ≥ 3.81（快浅色 3.81 / 快深色 5.71 / 中 8.04 / 慢 11.17）。**D8 取值没动**。`LowVisionChannelTests.testRunRoutePaceLineClearsItsOutlineInBothAppearances` 按 21 个插值点逐个验，并验红「换回白色必须不过」
  - **高德 API（D2 核实）**：渐变 = `MAMultiPolyline` + `MAMultiColoredPolylineRenderer`（`gradient = YES`）；**没有描边属性**，描边是垫在下面的第二条线；高亮带用 `insert(_:below:)` 压在配速线下面。索引点不抽稀，所以配速量化成 8 档、只在换档处放索引；连续重复点必须去掉。依据 `blind-run-ios/docs/research/amap-gradient-polyline-and-outline-20260924.md`
  - **阈值与口径（HANDOFF 没写死的）**：起终点相距 ≤ 50 米合并为「起终点」；每个轨迹点取距离最近的配速采样；分段条长 = 最快一段配速 ÷ 本段配速；`GENERATING` 每 2 秒重读（契约「1–2 秒后重试」），页面关掉就停；由轨迹推算的时刻（`inferred`）在时间轴上标「约」；`sosTriggered` 为 true 时写「这一单触发过紧急求助」（不说「已通知」之类，§6 红线）
  - **范围**：只有陪跑员的入口换到新详情（记录 tab 的行 + 三个订单页里 `CompletedTrackSummaryView` 那条链接，文案改「查看跑后详情」）。**跑者那条链接仍进 `OrderRouteReplayView`，阶段 5 换掉时删它**。`VolunteerOrderDetailLoader` 已删
  - **没做**：地图视差与导航栏渐变（HANDOFF 6.2 布局里写了，但任务书没列，按打磨项留到后面）、轨迹回放、夜跑样式、配速图拖动与地图联动（P1）、留言输入（阶段 6）。`postMessage` 仍无调用点
  - **读屏**：地图不进无障碍树（`isDecorative`），整体描述挂在正好盖住地图的透明区上；数字与单位之间留空格（「最后 0.2 公里」，不留会被审计判「标签不可读」，阶段 3 同一条）
  - **二级页藏标签栏**：详情页 `.toolbar(.hidden, for: .tabBar)`（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`，首轮审计 3 处 Contrast failed 就是它）
  - **审计只在页顶做**：滚动之后总有一行压在半透明导航栏 / Home 条下，两轮真机都被判 Contrast failed；守卫 `a11y-audit-types` 不许减审计项，下半页靠最大字号截图目检
  - **UI 测试能看真地图**：本机 `LocalConfig.xcconfig` 带 key，占位图只是因为 `launchVolunteerHome` 默认设了 `AIDRUN_UI_TEST_DISABLE_MAP=1`；截图用例传 `"0"` 覆盖掉。⇒ 「UI 测试构建没有高德 key」这句话在本机不成立
  - **基线红（`origin/main` `06f3a4e` 上逐字复现，非本次引入）**：`testMockVolunteerOrderFlowSmoke` 挂在冷启动「服务中」那一步 → 开了 blind-run-ios #193；它死在开头，所以订单页那条「查看跑后详情」链接目前只有编译覆盖。记录 tab 陪跑员审计那 5 个「Dynamic Type 部分不支持」同阶段 3
  - **测试（最终一轮，合并后的代码，iPhone 16 Pro）**：`VolunteerRunRecordTests`、`LowVisionChannelTests`、`RunRecordTests`、`RunRecordHistoryTests`、`LiveEscortTrackTests`、`XinghuoSnapshotTests`、`blindRunTests`（后三个直接用到地图容器类型）+ 详情页两条 UI 用例，`passed=425 failed=0`
  - 截图：`run-record-handoff/screenshots/stage4/`（19 张，iPhone 16 Pro，Mock 数据 + **真实高德底图**，含三张点分段后的高亮图）。开了勿扰，没截到通知横幅
- 2026-09-25：**#194 已 squash 合并进 main（`1f26205`）**（负责人同意后合并；CI 两项通过）。阶段 5 从 `main` 切分支即可，不用叠 PR。`add-volunteer-run-record-detail` 仍未归档（等 `enable-live-escort-location-and-track-summary` 先归档）
- 2026-09-25：**阶段 5（视障跑者详情，P0）**，分支 `feat/runner-run-record-detail`（blind-run-ios，从 `main` `1f26205` 切，worktree `/tmp/aidrun-stage5`），OpenSpec 变更 `add-runner-run-record-detail`（新能力 `runner-run-record-detail`，对 `live-escort-location-and-track-summary` 的同一条要求写 MODIFIED）。新定事项：
  - **归档顺序**：`enable-live-escort-location-and-track-summary` → `add-volunteer-run-record-detail` → 本变更（三者 MODIFIED 同一条要求）。`tasks.md` 3.5 留着没勾
  - **声音路线（负责人本会话拍板）**：离线合成双声道 16-bit WAV（22.05 kHz，复用 `ToneSynthesizer.container`）+ 常驻 `AVAudioPlayer`，**不用 `AVAudioEngine`、不改音频会话**（启动时已是 `.playback` / `.spokenAudio` / `.duckOthers`）。每 100 米 0.45 秒，**总长封顶 45 秒**（超过就压速率）；三角波 380–760 Hz 按对数映射 p5–p95 配速（快 = 高）；声像按路线经度西→东映射到 −0.9…+0.9；第 N 公里 N 声 1250 Hz；休息淡出 + 一声 190 Hz + 1.1 秒后淡入；结尾 880→1320 Hz。播放时只在屏幕上写「第 N 公里 / 休息」，不发 VoiceOver 通告。没有配速采样时整节隐藏
  - **入口（负责人本会话拍板）**：记录 tab 跑者的行与订单页「查看跑后详情」都进新页；**补评价仍在订单页**，新页最后一行「订单详情与评价」进 `BlindOrderStatusView`。`OrderRouteReplayView` 已删，`TrackRouteMap` / `TrackStatsRow` 并入 `CompletedTrackSummaryView.swift`（`CompletedTrackSummaryView` 改为 `recordOrderId` + `role`）
  - **VoiceOver 关时地图在页顶（负责人本会话拍板）**：用阶段 4 那张配速地图，P1 换高对比样式；开时放进「路线」一节且 `accessibilityHidden`，读的是下面那段文字描述。`voiceOverStatusDidChangeNotification` 实时切换。进页 0.6 秒后焦点落在头部（单元素），下一个元素就是「听这次跑步」
  - **讲述用页面自己的 `AVSpeechSynthesizer`**（`prefersAssistiveTechnologySettings`），不走 `VoiceService.speak`：那条会同时发 VoiceOver 通告，35 秒的讲述会念两遍。开始前 `VoiceService.stop()`。讲述与声音路线互斥；VoiceOver 焦点落到别的元素上就暂停，按钮变「继续…」，再点从暂停处接着放；离开页面全停
  - **HANDOFF 没写死、本会话按默认定的**：讲述只说「最慢 / 最快的一公里」不说「热身」（满公里 ≥2 段且不同段才说）；各段步频极差 ≤ 5 步/分说「全程步频很稳」；休息 >3 次只报次数与总时长；时段 0–5 凌晨 / 5–9 早上 / 9–12 上午 / 12–14 中午 / 14–18 下午 / 18–24 晚上；讲述末尾读**最新一条陪跑员留言**（6.3 第 2 条列在 P0；留言一节、朗读留言、回复仍归阶段 6）；路线描述 = 全程、起终点是否同处、「最远跑到起点{八方位}约 X 公里处」、休息次数
  - **D6 落点**：陪跑员累计服务时长只在「更多数据」最后一行（「林*累计陪跑 21 小时」，读屏去星号）；不进头部、不进讲述。null（注销）整行不出现
  - **view model 两端共用**：`VolunteerRunRecordViewModel` → `RunRecordViewModel`（移到 `RunRecordPresentation.swift`）；加载 / 失败 / 状态提示 / 重试抽成 `RunRecordLoadingPlaceholder` 等共用组件，陪跑员页行为不变
  - **Mock**：跑者视角的记录默认带一条陪跑员留言（有人真发过就换成真发的）
  - **测试（iPhone 16 Pro，USB）**：单测 `RunnerRunRecordTests` 16 + `VolunteerRunRecordTests`、`RunRecordTests`、`RunRecordHistoryTests`、`LiveEscortTrackTests`、`blindRunTests` 两条音频用例 `passed=98 failed=1`（唯一失败是新用例写错：留言里也含「很稳」，改断言后该类 16/16）；UI `passed=2 failed=2`，两条失败在 origin/main `f5f01bb` 上逐字复现（记录 tab 跑者审计 4 条 Dynamic Type、`testMockVolunteerOrderFlowSmoke` 冷启动 #193）；截图用例 1/1。⚠️ 第一次跑 UI 时 iPhone 走 Wi-Fi，runner code 74 起不来，插线后才过
  - **没做**：高对比大地图、分享给家人、休息点地名（P1）；留言一节与回复（阶段 6）；`postMessage` 仍无调用点
  - **范围外**：pre-push 探测到后端契约新增 6 个 SOS 字段（倒计时、幂等键、客服字段），生成代码已同步，手写模型未接 → blind-run-ios #196（关联后端 #388）
  - 截图：`run-record-handoff/screenshots/stage5/`（28 张，iPhone 16 Pro，Mock + 真实高德底图，开了勿扰）。顶部黄条是 Mock 构建自带的「Mock 本地模拟」提示，不是通知
- 2026-09-25：**阶段 6（文字留言两端，P0）**，分支 `feat/run-record-messages`（blind-run-ios PR #203，**叠在 #197 `feat/runner-run-record-detail` 上**，开工时核实 #197 仍 OPEN；worktree `/tmp/aidrun-stage6`），OpenSpec 变更 `add-run-record-messages`（对 `volunteer-run-record-detail` 写 MODIFIED：删掉「只读、无输入框」那个 Scenario；输入框与跑者留言一节各 ADDED 一条）。新定事项：
  - **归档顺序**：`enable-live-escort-location-and-track-summary` → `add-volunteer-run-record-detail` → `add-runner-run-record-detail` → 本变更。`tasks.md` 3.5 留着没勾
  - **跑者端 P0 不放回复按钮（负责人本会话拍板）**：语音回复是 P1；后端虽允许跑者发文字，P0 不做跑者的文字输入
  - **确认句改文案不改行为（负责人本会话拍板）**：原型「老陈打开这条记录时会听到这句话」不成立（阶段 5 进页不自动念），改为「已发送。X在这条跑步记录里可以听到这句话。」（屏幕带掩码名，读屏去星号）
  - **同一单可以发多条（负责人本会话拍板）**：发送后输入框清空但保留，发出的并进「留言」列表（按 `id` 去重，`GENERATING` 重读不会重复）
  - **对方已注销（负责人本会话拍板）**：判据 `blindName` 为 null 或空串 → 不给输入框，写「对方已注销账号，留言无法送达。」，已有留言照常显示。后端此时照样 201 → blind-run-backend #405 问要不要拦
  - **字数口径**：与后端 `@Size` 同口径 = 去首尾空白后按 **UTF-16 码元**数 1–200（101 个 emoji = 202，拒）。客户端发去过空白的文本；Mock 同步改成对原串按 UTF-16 校验
  - **HANDOFF 没写死、本会话按默认定的**：三个快捷短语照原型（节奏很稳 / 下次试试再快一点 / 折返配合得很好），点一下把输入框**换成**「短语。」（原型行为）；空白 →「先写一句话再发送。」，超长 →「留言最多 200 个字，现在是 N 个字。」；失败一律「留言没有发出。」+ 原因（网络 / 409 / 403 / 404 各一句，其余用错误码自带文案），草稿保留，`speakError` 念出；成功走 VoiceOver 通告；发送途中改过草稿就不清空。跑者端「X的留言」列**全部**陪跑员留言，「朗读留言」按先后连读（没句末标点的补句号），走 `RunRecordAudioController` 的 `.message` 源；没有陪跑员留言整节不出现；讲述末尾仍只读最新一条
  - **留存期**：界面不写任何保存多久的说法 → blind-run-backend #404
  - **不推送**：iOS 不造任何通知
  - **范围外**：tab 容器 tint = `tabSelected`（深色纯白），`.borderedProminent` 按钮在深色下白底白字，全 App 存量问题（本阶段的发送按钮已改显式配色）→ 另开任务
  - **测试（iPhone 16 Pro，USB）**：单测 `VolunteerRunRecordTests`、`RunnerRunRecordTests`、`RunRecordTests`、`RunRecordHistoryTests` `passed=72 failed=0`（新增 8 条逐条确认执行）；UI 两条新用例 + 两个详情页原有用例，首轮 `passed=3 failed=1`（新用例把 Mock 姓名写死成「陈」，改为只钉句式后 1/1）；修深色按钮与最大字号溢出后重跑 `VolunteerRunRecordTests` + 两条留言用例 + 陪跑员详情审计 `passed=25 failed=0`
  - 截图：`run-record-handoff/screenshots/stage6/`（15 张，iPhone 16 Pro，Mock + 真实高德底图，开了勿扰）。第一轮截图查出深色「发送」白底白字、最大字号下输入区撑出屏幕，均已修并重截
  - **只能人耳验、没验**：「朗读留言」的音色 / 语速 / 两条之间的停顿；朗读中 VoiceOver 焦点移开是否真停；朗读留言与讲述互相切换时有没有残音；发送失败时 `speakError` 是否念出、有没有被 VoiceOver 打断
- 2026-09-25：**#197 已 squash 合并进 main（`a956e54`）**（CI 两项通过）。阶段 6 从 `main` 切分支即可，不用叠 PR。`add-runner-run-record-detail` 仍未归档（等 `enable-live-escort-location-and-track-summary`、`add-volunteer-run-record-detail` 先归档）
- 2026-09-25：**#197 与 #203 已 squash 合并进 main**（负责人要求；#197 → `a956e54`，#203 → `93b2a98`，中间夹着别人合的 #195 契约同步）。#203 原先叠在 #197 上：#197 squash 后把 #203 rebase 到新 main（`--onto`，与 rebase 前只差一份无关调研文档）、force-push、改 base 为 `main`。force-push 后 GitHub 没自动触发 CI，用 `workflow_dispatch` 手动跑，两项通过；合并后 main 的 CI 两项通过。阶段 7 从 `main` 切分支即可，不用叠 PR。⚠️ 过程中 `/tmp/aidrun-stage6` 被外部清掉，一条 `cd … ; git rebase` 落到了主 checkout 上，已 `rebase --abort` 并切回原分支 `chore/auto-build-number`，无提交丢失
