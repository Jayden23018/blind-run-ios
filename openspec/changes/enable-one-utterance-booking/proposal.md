## Why

下单成本过高。今天盲人下一单最少要说三轮话（出发地点 → 时间 → 时长），或者在四步表单里翻。但客户端的默认值其实已经足够成单：`resolvedStartPlace` 在有定位时**永远非 nil**，默认即当前位置（`BlindBookingView.swift:352`）；`appointmentTime` 在 `configure` 里被设为「最早可约时间 +60 秒」（`:382`）；跑步需求全部选填。**也就是说进入预约页那一刻 `canSubmit` 就已经是 `true`。** 用户被要求提供的三项信息，其中两项他大概率只会复述系统已有的默认值。

同时，本次评估发现一个既有缺陷：`SpeechInputService.clearRecognitionStartState(marking:)`（`:325`）把 `completionHandler = nil` **清空而不调用它**。语音识别授权被拒（`:201`）、麦克风授权被拒（`:211`）、recognizer 不可用（`:335`）、音频会话或麦克风输入不可用（`:353` / `:360` / `:366`）这五条路径全部经过它，因此 `VoiceOrderWizard.handle(_:)` 永不触发——向导停在 `isRunning = true`、`fallbackMessage = nil`，界面显示「停止语音下单」，然后无限静默等待。看不见屏幕的人得不到任何「语音这条路已经断了」的信号。

这个缺陷今天被掩盖，是因为语音是用户主动点的、且只影响一次尝试。后续变更会把语音提升为下单的默认路径，届时这将成为每一个拒绝麦克风权限的用户的首次体验。因此在同一批次内修复。

## What Changes

- 语音下单改为**一次说完 → 读回整单 → 说「确认」成单**。同一句转录抽出多少算多少，抽不出的保留默认值，不重问、不失败。
- **地点也从整句抽（2026-08-04 起）**。原文写的是「地点不从整句抽」，依据是后端 `VoiceOrderService.resolveAddress` 把整个 transcript 原样丢给高德正向地理编码、整句喂进去必然「没听清地点」——那条依据在 2026-08-04 失效：后端的 `POST /api/orders/voice/parse` 先抽地名 span 再查高德，三个槽位一次拿到，常闭开关 `resolvesPlaceFromFullUtterance` 随之删除，两路并发 `parse-slot` 收敛成一次请求。要单独改地点仍可说「改地点」，那一轮走 `resolve-address`（纯地名，geocode 可靠）。
  - ⚠️ 遗留：`missing` 里的 `ADDRESS` 分不出「用户没说地点」和「说了但抽不出」，后者静默用当前位置会把人约到错误起点。已提给后端，暂靠读回念出实际起点兜底。
- 读回之后支持**定点修改**：说「改地点 / 改时间 / 改时长」跳到对应那一项，改完回读回把整单再念一遍。指令用本地保守白名单整串匹配，不新增后端调用。
- **首页下单入口收敛为一个**。删除首页「语音下单」按钮与 `.booking` 路由，「开始约跑」直接进语音；预约页里的「语音下单」按钮也去掉，改为「改用表单」。表单没有消失，只是不再要求用户在首页先做一次「点哪个」的判断。
- **录音状态改为可被非视觉感知**：起止各一次系统提示音（`begin_record` / `end_record`）+ 触觉反馈；实时识别文本只写屏不播报；整块内容区都是「说完了」的点击区；录音指示动画响应「减弱动态效果」且脉冲频率远低于 WCAG 2.3.1 的每秒 3 次红线。
- **整句那一轮的静音阈值单独设定**（尾静音 2 秒、首句静音 8 秒，字段听写仍是 3 秒 / 8 秒）。字段听写的 3 秒是给「说一个地名」定的，组织一整句话时中途一停顿就会被截断。两个方向都会翻车：太短切断说话人，太长让看不见屏幕的人以为死机 —— 一度取到的 12 秒就在后一边（2026-08-05 下调，依据见 tasks 2.2）。
- **缺陷修复**：`clearRecognitionStartState` 在清空前先以 `.error` 回调 `completionHandler`，使全部启动失败路径都能落到向导既有的 `handle → reask → fallBack`；`start()` 在语音链路已知不可用时直接进表单并播报原因，不让用户空等三轮重问。

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`: 引导式下单序列改为「整句一次说完 → 读回整单 → 一句肯定词成单」，逐项追问降级为定点修改；并明确要求每一次语音下单尝试都必须抵达一个可听见的终局。

## Impact

- iOS 语音/下单：`VoiceOrderWizard`、`SpeechInputService`、`BlindBookingView` 的步骤映射。
- 契约：无。不新增、不修改任何后端端点；`POST /api/orders` 请求体不变。
- 风险面：「修改」被误识为「确认」会产生非预期订单。缓解为保守白名单（仅明确肯定词提交，其余一律进逐项流程）、提交后播报、以及订单本身可由盲人取消（`canBlindRunnerCancel`）。
- 文档：`docs/05-page-specs.md` 创建预约页、`docs/09-accessibility-and-voice-guidelines.md` 的必播报节点。
