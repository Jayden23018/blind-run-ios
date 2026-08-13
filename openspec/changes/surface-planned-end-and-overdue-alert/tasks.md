# Tasks

## 1. 约定结束时间

- [x] 1.1 `blindRun/Core/Models/OrderDisplayHelpers.swift`：`plannedEndForAnnouncement`
      与 `plannedStartForAnnouncement` 同族，注释里写死「不许用开始时间加时长推」的理由。
- [x] 1.2 同文件 `blindRunnerAnnouncement(distanceText:)` 加 `.inProgress` 分支，
      在状态句之后追加「预计 X 结束」。缺失时原样退回状态句，不留半句「预计 结束」。
- [x] 1.3 `blindRun/BlindRunner/BlindOrderStatusView.swift`：
      `plannedEndHeaderText` 一处产出，状态卡的可见 `Text` 与 `statusHeaderAnnouncement`
      共用它（两处各拼一遍必然漂移，而漂移的那一侧没人看得见）；
      「预约信息」折叠区加 `infoRow("预计结束时间", …)`。
- [x] 1.4 `blindRun/Volunteer/VolunteerOrderFlowViews.swift`：服务卡 `serviceRow` 与
      订单信息卡 `infoRow` 各加一行。

## 2. 超时告警

- [x] 2.1 `blindRun/Core/AppRealtimeCoordinator.swift`：新增
      `clientPriority(forEventType:serverPriority:)`，只对 `ORDER_OVERDUE` 抬到 `.high`，
      其余照后端模板。实时推送与 `ingestCatchUp` 补读走同一条规则。
- [x] 2.2 函数注释里写死「抬的是展示不是送达」：APNs 补发判据是**模板**优先级
      （`NotificationService.java:134`），客户端抬了也不会让 App 不在前台时收到。
- [x] 2.3 **确认无本地时间推断**（后端点名要查的第二件事）：全仓 `plannedEnd` 未与当前时间
      比较过，位置上报 / WS 订阅 / 进行中卡片收起全部以服务端 `status` 为准。**代码零改动。**

## 3. 测试

- [x] 3.1 `blindRunTests/PlannedEndAndOverdueTests.swift`（10 条）：结束时间取 `plannedEnd`
      不是推的（用一个两者明显对不上的订单）、缺失时不猜、`IN_PROGRESS` 进主播报、
      缺失时播报干净退回、其余状态穷举不念、`ORDER_OVERDUE` 抬优先级、
      只抬这一条、未知 eventType 照后端走、`ORDER_OVERDUE` 不被生命周期抑制闸吞掉。
- [x] 3.2 改既有用例 `blindRunTests.testBlindRunnerRepeatStatusSpeaksInServiceState`：
      它与状态级定值逐字比较，而定值不含时间。改成断言「状态句仍在前 + 念到了结束时间」，
      并在注释里写清为什么改。**这是行为变更导致的预期失败，不是把测试改松。**
- [x] 3.3 真机跑（范围按符号搜定；`blindRunTests` 进来是因为改了它里面一条既有用例，
      不是全量）：
      ```bash
      scripts/device-test.sh -only-testing:blindRunTests/PlannedEndAndOverdueTests \
                             -only-testing:blindRunTests/NotificationCatchUpTests \
                             -only-testing:blindRunTests/KeepWaitingTests \
                             -only-testing:blindRunTests/blindRunTests
      ```
      **`passed=323 failed=0 skipped=0 result=Passed`**（iPhone 16 Pro）。
      逐 suite 核过日志确认不是零执行：`PlannedEndAndOverdueTests` **10** 条（不是 12，
      首版本文件写错了数，已改）、`NotificationCatchUpTests` 15 条、`KeepWaitingTests` 15 条、
      `blindRunTests` 275 条。改名后的
      `testBlindRunnerRepeatStatusSpeaksInServiceStateWithTheAgreedEndTime` 单独核过已执行。
- [x] 3.4 编译门禁 `build-for-testing` —— **TEST BUILD SUCCEEDED**。
- [x] 3.5 `validate-guard`（28 条）/ `validate-docs` / `validate-spec-coverage` /
      `openspec validate --strict`（22 项）全过。`validate-error-codes` 本变更未动 `ErrorCode`，
      由 pre-push 统一跑。

## 4. 契约投递（后端仓库 `demo/docs/handoff.md`）

已投：后端仓库分支 `docs/handoff-ios-share-and-overdue-20260813`（commit `219733b`）。

- [x] 4.1 答问题①：`ORDER_OVERDUE` 收到会怎么表现（通用通知通道 → 前台横幅 + TTS，
      未被生命周期闸抑制；本变更抬为高优先级，只抬这一条，补读走同一规则）。
- [x] 4.2 答问题②：**没有**按 `plannedEndTime` 本地推断订单已结束的代码，全仓核过。
- [x] 4.3 🔴 提问：盲人侧 `ORDER_OVERDUE` 模板是 `NORMAL`（`websocket-protocol.md:158`），
      而 APNs 只补发 `HIGH`（`NotificationService.java:134`）—— App 不在前台时盲人**收不到**
      超时告警，而志愿者侧是 `HIGH` 收得到。「跑者可能失联」唯一收不到的是跑者本人。
      请把盲人侧模板提到 `HIGH`。
- [x] 4.4 ~~提问：志愿者侧文案还写「订单已超过结束时间 1 小时」~~ —— **撤销，投递前复核发现
      后端 `4e4b10d`（#88）已经修成 15 分钟**。落盘前先拿 `origin/main` 复核了一遍要提的每条，
      避免投一个已经被修掉的问题。
- [x] 4.5 提问：盲人侧文案「志愿者会尽快结束服务」把最坏情况说成了最好情况 ——
      真出事时这句会让盲人以为一切正常只是慢了点，而这正是这条告警想避免的。
      不自己覆盖后端文案（那只在 SOS 那条红线上做过），请后端改。

## 5. 收尾

- [ ] 5.1 真机开 VoiceOver：`IN_PROGRESS` 时按「重复当前状态」听得到结束时间；
      状态卡的合并朗读里也有。**（人工，未做）**
- [ ] 5.2 低视力档位（AX3 以上字号）看一眼状态卡多这一行不裁切。**（人工，未做）**
- [x] 5.3 按 skill `aidrun-ship-check` 输出验证结论，贴真实测试输出（见 3.3）。
