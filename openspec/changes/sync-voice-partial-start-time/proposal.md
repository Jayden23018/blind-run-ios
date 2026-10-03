## Why

后端 2026-10-03 上线了 #501（`77ca7411`）：用户只说半句开始时间（「明天早上」「后天」「下午」）时，不再回「没听清开始时间，请再说一次」，改为反问缺的那部分（「明天早上几点？」）。后端不存对话状态，用户**只答一个词**（「九点」）能拼回完整时间，全靠客户端把响应里的 `partialStartTime` 原样放进下一轮 `current.partialStartTime`。

**iOS 侧一行没接**（后端 issue Jayden23018/blind-run-backend#508）。不接的后果是**静默的**：用户答「九点」会被读成今天（已过则明天）9 点，而不是「后天 9 点」。读回会念出日期，但盲人得自己听出那不是他说的那天 —— 与「`plannedStartTime` 被丢」同一类缺陷。

同一批后端改动还修了一个语音日期 bug（语料 `_period_note`）：「凌晨」此前不在时段词里，「后天凌晨三点」的「后天」被断开，日期当没说 → 滚到明天 03:00，差一天；中午一~四点要 +12；凌晨十二点是 0 点。后端黄金语料因此新增 10 条，前端镜像没跟上，`pre-push` 与 CI 的语料门禁对**所有**前端分支报红。前端 Mock 解析器要对齐同一套时段换算，否则镜像用例过不去。

## What Changes

- **接入 `partialStartTime`**：`ParseVoiceOrderResponse` 与 `VoiceSlotSnapshot` 各加该字段，`slotSnapshot` 把它带进下一轮 `current`。
  - `period` 是响应方向的开放枚举，契约要求「未知值原样回传或置空，不要报错」⇒ **存成字符串，不做枚举**（枚举的 `.unknown` 兜底会吞掉原值，回传就不再「原样」）。
  - 两个子字段都空的壳子**不回传**（契约：「至少一个非 null」）。
  - 确认轮 `confirmRoundSnapshot` 有一处**手工拼快照**的代码（起点回落设备位置时），必须把它一起带上 —— 「明天早上」这类半句话通常没说起点，正好走进这一支。
- **Mock 对齐后端时段换算**：`timeLikeRegex` 加「凌晨」；中午一~四点 +12；凌晨十二点 = 0 点。
- **黄金语料镜像补 10 条**（START_TIME/regex 9 条、ADDRESS/llm 1 条）。
- 契约漂移：重新生成 `Packages/AidRunAPI`（只含后端新增的 `VoicePartialStartTime` 与注释），生成代码不进运行时。

## Non-goals

- **Mock 不产出 `partialStartTime`**，也不模拟「半句 → 反问 → 一个词补全」。开发期 Mock 路径下这一段走不到，真实行为只能在连云端时验；要让 demo 环境走到再补（Mock 的解析器当前对「明天早上」会整句认输，与后端新行为不同）。
- **不改 `parseFreeform` 的 `ttsText` 播报条件。** 后端 #508 顺带指出：整句轮只在 `missing` 含 `START_TIME` 时才念 `ttsText`，而 `ttsText` 永远是**第一个阻断项**的追问，向导里 ADDRESS 在前，所以用户只说「明天早上」时这一轮念的是起点追问、紧接着读回又念「使用设备当前位置」。这是播报文案的产品判断（盲人端红线），**留给负责人拍板**：客户端在 `missing.first != .startTime` 时不念 `ttsText`，还是要后端单独给出开始时间那一句（多一个契约字段）。
- 不动任何后端端点，不改 `POST /api/orders` 请求体。

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`：新增一条要求 —— 只听到半句开始时间时，客户端把后端给的那半句原样带进下一轮。用 ADDED 而不是 MODIFIED：`Booking uses a guided voice-first sequence` 已被多个未归档变更 MODIFY，再改会让归档顺序互相卡死。

## Impact

- iOS：`blindRun/Core/Models/VoiceOrderModels.swift`、`blindRun/Voice/VoiceOrderWizard.swift`（`confirmRoundSnapshot`）、`blindRun/Core/MockAPIClient+Voice.swift`、`Packages/AidRunAPI/`（重新生成）、`blindRunTests/VoiceOrderWizardTests.swift`。
- 契约：**只消费**。`docs/api_spec.yaml` 的 `VoicePartialStartTime`、`docs/frontend-guide.md`「开始时间只说了半句」。
- 风险面：回传多一个对象，体积可忽略；`plannedStartTime` 非 null 时后端忽略它，带了也无害。
