# 陪跑员订单页 v2 · 审计后的决定（2026-09-26，项目负责人逐条确认）

本文件是 v2 交付包落地的**决定源**。与交付包其余文件冲突时以本文件为准；与仓库 `AGENTS.md` 的硬规则冲突时以 `AGENTS.md` 为准并回来改本文件。
v1 的名字映射（交付包路径/字段 → 现有后端）以后端分支 `origin/docs/order-page-v2-ios-handoff` 的
`docs/volunteer-order-page-v2-ios-handoff.md` §2 为准（读法：`git -C /Users/mac/Downloads/demo show c8d0fcd:docs/volunteer-order-page-v2-ios-handoff.md`）。
⚠️ 那份说明**还没合进后端 main**，BE-1 顺手把它合掉。

审计基线：iOS `origin/main` `a8e77d4`，后端 `origin/main` `0de474f`。

## 一、范围决定

| # | 决定 |
|---|---|
| V1 | 后端已声明本期不做的 v1 项**全部接受**：邀请阶段 INVITED/TAKEN（SPEC #393）、衣着、集合点地标、全名与称谓、`newBadge`、0.1 小时口径、迁移接口返回完整 OrderView、按订单订阅 WS、3 秒节流、敏感词（#430） |
| V2 | iOS v1 欠账要做：①出发/汇合锁屏实时活动 ③失败 `.error` 触感 ④ `03-motion-and-haptics.md` 动画与触感总表逐条对齐 ⑤每个状态一张 Preview。**② APNs 能力文件（仓库无 `.entitlements`、pbxproj 无 `CODE_SIGN_ENTITLEMENTS`）本期不做** —— 但见 V3 的依赖说明 |
| V3 | 实时活动：**两类卡并存**（后端说明 §5）。出发/汇合卡新建，按状态换色：出发与快迟到 `stateDeparted`、汇合 `stateArrived`。锁屏**跑步卡**（现有 `RunLiveActivityAttributes`，本地更新）按 `04-live-activity.md` 最后一节改：底色 `stateRunning`、暂停 `statePaused`、第 1 行带节奏信号（5 分钟未更新只写「陪跑中」）、`/ 目标公里`、进度条；**继续本地更新，不走服务端推送**；无按钮。⚠️ 出发/汇合卡要服务端推送更新（`pushType: .token`），依赖 APNs 能力 —— 实现者先在真机验证能否拿到 push token，拿不到就先做本地起卡 + App 在前台时本地更新，并回报负责人 |
| V4 | **【2026-09-30 作废，见 V19】** ~~App 内跑步中页面布局不动（深蓝三数字、长按 2 秒结束，C13/C14/C20 不做）。新功能加进旧页面：节奏卡 + 信号卡（C15）、耳机语音播报开关（C16）、提示条（C19）、暂停中状态（C18）、右上角「求助」改为打开求助面板（C17）~~ |
| V5 | 求助面板三行变两行 + 紧急按钮：「李需要停下来」→ 暂停；~~「我们走散了 / 响铃」~~**删掉**（跑步中响铃不做）；「联系客服」→ 提交一条带订单号的客服工单（现有 `/api/support/tickets`），页面说「客服会尽快联系你」，不暗示马上接通；「长按 3 秒，紧急求助」→ 现有云端 SOS 链路 |
| V6 | 求助文案取最保险的：VoiceOver 双击后的确认框**用 `AGENTS.md` §6 锁定文案原文**，不用交付包的「发出紧急求助？」。紧急按钮副标题**不承诺任何人已收到**：用「求助会附带你们的当前位置」一类措辞，禁止「发给组织和紧急联系人」 |
| V7 | 走散：**阈值不改**，沿用现有 `ESCORT_DISTANCE_ALERT`（100 米、连续 2 次采样、并行升级客服）与 `ESCORT_SIGNAL_LOST`。不做 `run.separation` / `run.separation_cleared` / 20 米规则。提示条的「走散」一档由现有告警驱动，出现/消失沿用现有告警的展示逻辑；提示条上**不放**响铃按钮 |
| V8 | 「组织值班」一律改为**客服**。暂停时通知客服走**非紧急**通道（不进 `/api/cs/emergency-events` 紧急队列；后端自定落点，工单或客服通知均可） |
| V9 | 志愿时长**按分钟**。暂停时长扣除（08 口径）：服务时长 = 结束 − 开始 − 手动暂停总时长。跑后记录已有的自动暂停（速度 < 0.5 m/s ≥ 10 秒）只影响运动时间与配速，不影响服务时长 |
| V10 | 跑步中距离/用时/配速**以服务端为准**，按**跑者手机**的轨迹实时累计（与跑后记录 D1 同口径，清洗规则复用：hAcc > 30 m 丢、相邻速度 > 7 m/s 丢）。`OrderDetailResponse` 追加 `run` 对象（08 第七节形状，`turnaroundKm` 恒 null）；推送节流由后端定，建议每 0.01 公里或 5 秒取慢者。客户端两次推送之间可本地插值，收到即校正 |
| V11 | 称呼：后端**新增姓氏字段**（接单后给对方：陪跑员看跑者姓氏、跑者看陪跑员姓氏），不下发全名、不念掩码。姓氏用于标题和短标签（「李」），整句用「跑者」「陪跑员」「对方」。锁屏只用姓氏；没有性别字段，**不加「先生/女士」** |
| V12 | 不做：音量键映射、跑步中响铃（C25 不做，`ring-runner` 仍只允许 `DRIVER_ARRIVED`）、折返点（C28：没有数据来源，`turnaroundKm` 恒 null，不画折返线、不显示「x 折返」） |
| V13 | **允许新增状态色**（C01 的藏青/主蓝/琥珀/青绿/灰/完成绿），限头卡与锁屏卡。这条覆盖 `docs/ui/design-direction.md`「不新增强调色」，实现者同 PR 改那份文档 |
| V14 | 节奏信号：跑者端跑步中**屏幕上三个大按钮**（稍慢一点 / 刚刚好 / 可以快一点，文案固定 C33），成功后 TTS「已告诉陪跑员：稍慢一点」；后端 `POST /api/orders/{id}/rhythm`（跑者 token，仅 `IN_PROGRESS`，同一信号 10 秒内 429），推陪跑员（WS `APP_NOTIFICATION` + 后台时 APNs time-sensitive，锁屏只写姓氏），`run.lastSignal/lastSignalAt` 冷启动可恢复 |
| V15 | 暂停/继续：`POST /api/orders/{id}/pause`、`/resume`（陪跑员 token，`IN_PROGRESS`），暂停区间入库，推跑者（TTS）与客服（V8） |
| V16 | 跑者电量：跑者端在 WS `LOCATION_UPDATE` 追加可选 `batteryLevel`（0–1），每 60 秒至少一次；后端 ≤ 20% 时给陪跑员推一次（同一订单只推一次），`run.runnerBatteryLow` |
| V17 | 紧急求助复用现有链路（后端对订单状态无限制，iOS `IN_PROGRESS` 已开云端）。后端补一条：**事件同时存跑者最新位置快照**（Redis `blind:loc:`），短信/客服台用跑者位置优先 |
| V18 | 命名一律沿用现有体系：路径 `/api/orders/{id}/…`、状态名 `IN_PROGRESS` 等、推送走 `APP_NOTIFICATION` + `eventType`（建议 `RUN_RHYTHM` / `RUN_PAUSED` / `RUN_RESUMED` / `RUNNER_BATTERY_LOW` / `RUN_PROGRESS` 或独立 WS type，后端定）。时间沿用无时区本地串 |
| V19 | **跑步中页保持主线现状**（#227 独立新页 + #232 节奏/暂停/提示条/求助面板），**V4 作废**：V4 的审计基线 `a8e77d4`（09-26）早于 #227（09-27），描述的是被 #227 换掉的旧页。**头卡启用青绿 `#0A6B72`**（C01；暂停仍 `statePaused`），覆盖 #227 决策 3 的藏青。`running-state/` 里陪跑员端 6 屏（禁暂停、黄色结束按钮、底部通栏求助）不采用。2026-09-30 项目负责人拍板；实现见 OpenSpec `running-hero-green` |

## 二、任务拆分

| 任务 | 仓库 | 依赖 |
|---|---|---|
| BE-1 跑步中实时数据：`run` 对象（V10）+ 暂停/继续与服务时长（V9、V15、V8）+ 合并 v1 对接说明分支 | 后端 | — |
| BE-2 节奏信号（V14）+ 电量（V16）+ 姓氏字段（V11）+ SOS 位置快照（V17） | 后端 | `run` 对象里的 `lastSignal*` / `runnerBatteryLow` 与 BE-1 同一个 DTO，后合者 rebase |
| FE-1 A 类视觉（C01–C12，不含跑步中页）+ v1 欠账 ③④⑤ + D 类文案（C31–C33） | iOS | — |
| FE-2 锁屏实时活动（V3）：出发/汇合卡 + 跑步卡 v2 样式 | iOS | 跑步卡的节奏/暂停字段依赖 BE-1/BE-2；姓氏依赖 BE-2（先用可选字段兜底） |
| FE-3 跑步中新功能进旧页（V4–V7）+ 跑者端节奏按钮与电量上报 | iOS | BE-1、BE-2 合进后端 main 后才推得上去（`AGENTS.md` §11） |

## 三、审计里已核实的事实（开工不用重查）

- iOS 跑步中走旧页 `VolunteerInServiceView`（`VolunteerOrderFlowViews.swift:1662`），v2 页面在 `VolunteerOrderFlowStep.swift:593-596` 显式让位
- iOS 求助路由 `VolunteerOrderSOSMode.resolve`（`VolunteerOrderV2.swift:19-30`），旧页导航栏求助 `VolunteerOrderFlowViews.swift:1749`
- 现有跑步卡 `RunLiveActivityShared.swift:33-62`，`RunLiveActivityController.swift:163` `pushType: nil`；`GuideRunAttributes` 与 `live-activity-token` 调用在 iOS 为 0 处
- 位置上报 `WSLocationUpdateMessage`（`WebSocketModels.swift:32-47`）字段 `hAcc/speed/alt/steps/cadence`
- 后端求助：`EmergencyService.java:189-199` 只校验参与者不校验状态，`:226-227` 只存请求里那一组坐标
- 走散告警语义见后端 `docs/websocket-protocol.md:276-282`
- 契约里没有任何「组织 / 值班」概念，只有客服 `/api/cs/*` 与用户侧 `/api/support/tickets`
- App 用户没有昵称字段，只有真实姓名，对方拿到的一律掩码（`OrderDetailResponse.blindName` / `volunteerName`）
