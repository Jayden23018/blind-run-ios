## Why

盲人在一次陪跑里最需要传达给志愿者的，恰恰是今天**没有实际采集通道**的那一类信息：身体状况（低血糖、心脏问题、易疲劳）、以及随身体状况而来的可执行指令（「如果我说头晕，请马上停下来扶我坐下」）。表单里有「特殊说明」多行输入框（`BlindBookingView.swift:1346`），但对盲人打字是成本最高的交互；语音是这条信息**唯一实际可用**的通道。

基础设施其实已经就绪，缺的只有一根线：

- 契约里 `POST /api/orders/voice/parse` 的响应**已经返回** `specialNotes` / `hasGuideDog` / `pacePreference`（后端 `docs/api_spec.yaml:2835-2843`，客户端 DTO 在 `blindRun/Core/Models/VoiceOrderModels.swift:113-122`，2026-08-04 已落地）。
- `CreateOrderRequest` 已收这三个字段（`OrderModels.swift:320-324`），订单详情已展示（`BlindOrderStatusView.swift:886-895`、`VolunteerOrderFlowViews.swift:2794-2811`）。
- **唯一没接的是 `VoiceOrderWizard.parseFreeform`**（`blindRun/Voice/VoiceOrderWizard.swift:403`）：它只把时间 / 地点 / 时长写回 `bookingViewModel`，那三个额外槽位解出来就丢了。

但把这根线直接接上会踩红线，而且是踩在一个**今天就已经在漏的口子**上。

### 阻塞问题：`specialNotes` 在接单前就广播给所有候选志愿者

`AGENTS.md §8` 明写「接单前隐藏盲人联系方式、紧急联系人与敏感健康信息」。而现状是：

- 后端派单推送 `NEW_ORDER` 的载荷里带 `specialNotes`（后端 `docs/websocket-protocol.md:359,376`），客户端 DTO 是 `WSNewOrder.specialNotes`（`WebSocketModels.swift:204`）。
- iOS 派单弹窗**原样渲染**它（`VolunteerHomeView.swift:1685`），那段紧挨着倒计时（`:1694`）和「接单 / 拒绝」按钮（`:1700-1709`）—— 也就是**接单前**。

派单是串行轮询的，一单会依次推给多个候选志愿者。「我有低血糖」写进 `specialNotes`，等于把一条健康信息广播给这一单碰到过的**每一个**志愿者，包括最后拒单的那些。

**这不是本变更引入的缺陷，是既有缺陷。** 表单的「特殊说明」输入框今天就在往同一个字段写、走同一条推送。语音只是把它从「少数愿意打字的人会填」变成「每个人张嘴就填」，把一个存量小口子变成默认路径。所以本变更**必须先把可见性问题解决掉**，否则等于给漏斗接了一根水管。

## What Changes

### 1. 额外需求原文照录，不做摘要

用户在 `.freeform` 那一轮说的原话已经存在 `VoiceOrderWizard.lastUtterance`（`:113`）—— 原文照录不需要任何新的采集机制，只需要决定这段文本**去哪个字段、什么时候可见**。

不摘要的三条理由（决策已定，见 `design.md`）：

- 摘要会丢掉可执行指令。「如果我说头晕请马上停下来」摘成「有低血糖」，正好把志愿者真正需要的那半句丢了。
- ASR 已经引入一层错误，再叠一层模型改写，用户**无从核对**——他听不到屏幕上最终存了什么。
- 仓库已有同源先例：时长静默取整被判定为「对听不见屏幕的人等于篡改」，所以改成必须播报（`VoiceOrderWizard` 的 `pendingNotice` 机制）。摘要是同一类问题的更严重版本。

后端在契约里也已经站在这一侧：`specialNotes` 非空时**保证是用户原话的子串**，模型改写过的备注在后端就被丢弃（`VoiceOrderModels.swift:118-122`）。本变更把这条从「后端的实现细节」提升为**客户端也必须遵守的规格**。

### 2. 把「额外需求」拆成两类，可见性不同

| 类别 | 字段 | 接单前可见？ | 理由 |
|---|---|---|---|
| 结构化匹配条件 | `hasGuideDog` · `pacePreference` | **可见（维持现状）** | 枚举/布尔，不是自由文本，不含健康细节；`hasGuideDog` 进派单硬过滤，`pacePreference` 是志愿者判断「我陪不陪得下来」的依据。接单前藏起来会制造「接了才发现做不到 → 取消 → `REMATCHING`」的浪费，成本落在盲人身上。 |
| 自由文本额外需求 | `specialNotes`（及其接单后专用的继任字段） | **不可见** | 自由文本无法预先判定敏感度。语音路径下它就是用户原话，必然混入健康信息。 |

### 3. 契约问题投给后端（**已结案，2026-08-24 更新**）

原文写的是「本变更的阻塞项」：需要后端提供「接单后才下发」的自由文本通道，两条候选路线在 `design.md`，倾向修 `specialNotes` 自身的下发时机而不是新增字段。

**结论已经全部拿到，本变更不再有契约阻塞项：**

- **2026-08-07 后端走路线 A**：`specialNotes` 已从接单前的两条下发路径（`NEW_ORDER` WS 载荷、`GET /api/orders/available` 响应）删除，是破坏性变更。客户端同期把 `routeNotes` 收进同一条闸。
- **2026-08-20 后端确认另外两条是「否掉了」不是「排期未到」**：`meetingPointHint` 不拆、`maxLength` 200 不放宽，重开条件已写死（见 `design.md` D3 的 08-24 结案小节）。

⚠️ 此前 `tasks.md` 里记着「真正的阻塞点是产品：语音路径要不要也承载 `meetingPointHint`」——**那个问题随字段一起作废了**，字段不存在就谈不上语音路径要不要承载它。

### 4. iOS 实现留在契约后面（**已完成**）

原则不变：契约拍板前不改 iOS 业务代码。契约在 08-07 拍板后，第 2、3 组任务已全部落地——存量泄露的两处展示端（派单弹窗 `VolunteerHomeView.swift`、可接订单详情 `VolunteerOrderInfoSection`）已修，判据集中到穷举 switch `RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`，`parseFreeform` 三个槽位已回写。

**本变更目前唯一未完成的是真机验证**（`tasks.md` 5.5 / 5.6 / 6.2），卡在两台设备 `unavailable`，与契约无关。

## Capabilities

### Added Capabilities

- `blind-runner-extra-needs`：一次陪跑的额外需求（身体状况自由文本、导盲犬、配速）的采集、保真与**分级可见性**。

> **与 `enable-one-utterance-booking` 的边界**：那个变更 delta 的是 `blind-runner-voice-first-experience`，规定的是「几轮、怎么问、怎么读回、怎么确认」——**流程形态**。本变更不碰那些 requirement 的任何一条文字，只新增一个正交能力，管的是「额外需求这类数据本身的保真与可见性」。两者唯一的交汇点是读回文案里要不要念额外需求，本变更把它写成对读回的**附加**约束，而不是重写读回那条 requirement。

## Impact

- **契约（阻塞）**：`NEW_ORDER` WS 载荷、以及任何接单前可见的订单视图，需要后端明确 `specialNotes` 的下发时机。后端 `docs/websocket-protocol.md:341-376`、`docs/api_spec.yaml` 的订单响应 schema。
- **iOS**：`VoiceOrderWizard.parseFreeform`（接三个槽位）、读回文案（`confirmPrompt`）、`VolunteerHomeView.swift:1685`（存量泄露展示端）、`MockAPIClient.mockVoiceSpecialNotes`（Mock 侧目前恒返 `nil`，`:1317`）。
- **既有约束**：`specialNotes` 有 `maxLength: 200`（`api_spec.yaml:2843`）。原文照录会撞上限，截断处理规则见 `design.md`。
- **风险面**：原文照录意味着 ASR 的错字会原样进备注并展示给志愿者。缓解是读回环节念原话（`VoiceOrderWizard.swift:260-261` 已有），用户能听出「它听错了」。
- **文档**：`docs/05-page-specs.md` 派单弹窗字段清单、`docs/09-accessibility-and-voice-guidelines.md` 必播报节点。
- **测试**：只跑覆盖本次改动的 suite（`AGENTS.md §11`），预计 `VoiceOrderWizardTests` + 志愿者派单相关 suite；不跑全量。
