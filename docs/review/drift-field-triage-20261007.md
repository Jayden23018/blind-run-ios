# 漂移探测器新报字段分流（#284，2026-10-07）

> 范围：PR #283 补齐 `filter.paths` 后 `report-drift-fields.mjs` 报的 ❌ 44 条与 ❓ 391 条。**本文只分流，不接字段。**
> 基点：iOS `origin/main`（含 #357），契约 = 后端 `origin/main` 的 `docs/api_spec.yaml`（2026-10-07 取）。
> 判档口径：skill `aidrun-contract-sync` 三档 —— 触及盲人端红线（单独开变更 + 测试）/ 纯展示（并入相关 PR）/ 前端用不上（写明理由）。

## 一、❌ 真字段（14 个）

| 契约模型 · 字段 | 契约说了什么 | iOS 现状 | 分档 · 去向 |
|---|---|---|---|
| `AvailableOrderResponse.blindUserPhone` | 「盲人手机号，已掩码」 | 未接（`OrderModels.swift:838`） | **前端用不上，且不许接**：`AGENTS.md` §8 接单前隐藏盲人联系方式；掩码号也不进接单前界面 |
| `AvailableOrderResponse.distanceKm` | 志愿者到起点距离（1 位小数） | 未接；邀请卡读的是推送 `WSNewOrder.distanceKm`（`VolunteerInviteSheet.swift:417`） | **纯展示**。只影响冷启动恢复出来的邀请卡；恢复路径正由在途 #344 改成 `pending-invites`，**#344 合并后复核**，仍缺再并入邀请卡 PR（#339 同批） |
| `AvailableOrderResponse.hasGuideDogThisRun` | 可空布尔（派单硬过滤） | 未接；推送侧是 `WSNewOrder.hasGuideDog`，`VolunteerInviteQueue.swift:138` 注明导盲犬行另走推送 | **纯展示**，同上并入邀请卡 PR。⚠️ 接的时候三态（true / false / null）不能压成 false（`RunnerExtraNeedsVoiceTests` 的同一条理由） |
| `AvailableOrderResponse.paceMaxSecondsPerKm` | 配速区间上限 | 未接；推送侧 `WSNewOrder.paceMaxSecondsPerKm` 有 | **纯展示**，同上 |
| `RunView.distanceKm` / `paceSecondsPerKm` / `startedAt` / `targetKm` | 跑步中实时距离、配速、开跑时刻、目标距离，与跑后记录同口径 | 未接（`OrderModels.swift:601` 只有 `paused / lastSignal / lastSignalAt / runnerBatteryLow / elapsedSeconds`）；跑步页的距离配速走 `GET /api/orders/{id}/track` 的 `blindStats` | **纯展示**。现有来源可用，换源能省一次请求、口径与跑后记录一致 ⇒ 并入下一个跑步页 PR，不单独动 |
| `RunView.pausedSeconds` | 手动暂停累计（志愿时长扣它） | 未接 | **纯展示**，同上（暂停态头卡可显示「已暂停 x 分钟」，非必需） |
| `RunView.turnaroundKm` | **恒为 null**（V12） | 未接 | **前端用不上**：契约自己写恒 null，DECISIONS-v2 V12 不画折返线 |
| `RhythmSignalResponse.orderId / signal / signalAt / success` | 回执 | 只读 `delivered`（`OrderModels.swift:671`） | **前端用不上**：发出方已知自己发了什么、发给哪一单；`signalAt` 与详情 `run.lastSignalAt` 同值，页面以详情为准 |
| `RunnerMessageResponse.orderId / success` | 回执 | 只读 `messageToVolunteer`（`OrderModels.swift:773`） | **前端用不上**：同上 |
| `VolunteerDispatchSummaryResponse.online / withinServiceTime` | 与 `isOnline` / `isWithinServiceTime` 同义（契约里两组键都在，Jackson 布尔字段的重复导出） | 读的是 `isOnline` / `isWithinServiceTime` | **前端用不上**：同义重复键，已有一组在用 |
| `VolunteerNextBadgeDto.blockedBy` | 多条件勋章卡在哪一维（`RATING` / `RATINGS_COUNT`），只有 `HIGH_RATED` 会给；没有它时「20 条评价、均分 4.0」看到**满格进度条 + 未解锁** | 未接（`VolunteerAchievements.swift:115`） | **纯展示，已单独开 #366**：满格却不解锁会让志愿者以为坏了。接的时候按开放枚举处理（未知值忽略），文案只说「评分还差一点」（契约刻意不下发阈值） |

## 二、❌ 枚举取值（26 条）

仓库约定封闭枚举不投运行时（记忆 `openapi-generated-code-is-drift-detector-only`）。逐个核手写侧遇未知值会不会整条崩：

| 手写类型 | 位置 | 遇未知值 |
|---|---|---|
| `String?`：`AvailableOrderResponse.chatPreference`、`PointTransactionResponse.reason`、`SetRoleResponse.role`、`VolunteerBadgeDto.code`、`VolunteerNextBadgeDto.code` | 各模型 | 不崩（字符串） |
| `RunRhythmSignal`（`RunView.lastSignal`） | `OrderModels.swift` | 有 `unknown` + 自定义解码 ✅ |
| `RunRecordRole`（history.role / message.fromRole / record.viewerRole） | `RunRecordModels.swift` | 有 `unknown` + 自定义解码 ✅ |
| `RunRecordStatus`（record.status） | `RunRecordModels.swift` | 有 `unknown` + 自定义解码 ✅ |
| `PacePreference`（`VolunteerProfileResponse.paceRange`） | `OrderModels.swift` | 有 `unknown` + 自定义解码 ✅ |
| `RunEventType`（`RunEvent.type`）、`RunRecordMessageType`（message.type） | `RunRecordModels.swift:46` / `:55` | **没有** `unknown`，但两个数组都包在 `@SkippingUndecodable` 里（`:105` / `:110`）⇒ 未知类型那一条被跳过，整份记录照常解出。源码 `:54` 注释写明是有意设计 ✅ |

⇒ **26 条没有一条违反「枚举解码遇未知值不许整条崩」**。唯一的边：`POST /api/orders/{id}/run-record/messages` 的单条响应若回一个未知 `type` 会解码失败——发的是 `TEXT`、回的也是 `TEXT`，不构成风险。

## 三、❓ 391 条

按 #284 原文，绝大多数是 `ApiResponse<Xxx>` 信封顶层字段（手写侧是通用 `APIEnvelopeResponse<T>`）。本轮**没有**逐条复现（需要先造出未提交的生成 diff），结论沿用 issue 原判；要查时按报告的归属路径手查那一个模型，别按字段名全局 grep。

## 四、后续

1. 已开 #366：`VolunteerNextBadgeDto.blockedBy`（满格不解锁）。
2. #344 合并后复核邀请卡冷启动恢复是否还缺 `distanceKm` / 导盲犬 / 配速上限；缺的并入 #339 的 PR。
3. `RunView` 四个展示字段并入下一个跑步页 PR，不单独动。

## 复核触发条件

`report-drift-fields.mjs` 报出新的 ❌；后端给上述模型加字段或改枚举；#344 合并（第 1 节邀请卡三行）。
