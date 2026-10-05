## Why

负责人 2026-10-02 拍板、2026-10-05 确认文案（后端 issue Jayden23018/blind-run-backend#502）：**全盲用户基本不可能用表单下单，语音失败时不该把人送去表单。** 表单页本身保留（低视力用户、家人代填、语音权限被拒时仍要用），但不再作为语音失败的兜底。

现状 `VoiceOrderWizard.fallBack` 在四种情况下都把页面切到表单，并播「……已切回表单填写，你可以用屏幕上的输入框继续预约」：
- 同一项连续 `maximumReasksPerSlot`（3）次没听清；
- 连续 `maximumRoundsWithoutStartTime`（2）轮没拿到开始时间；
- 用户说「算了」（本地取消词）或后端判 `CANCEL` —— 用户是想退出，不是想填表。

## What Changes

- 向导新增**结束态**：语音会话停止、`isRunning = false`，但页面仍是语音面板（新状态 `endedMessage`，不再借用 `fallbackMessage`）。
  - 取消：播「已取消这次语音下单。」，不提表单。
  - 连续没听清 / 连续两轮没拿到时间：播「暂时没听清，你可以稍后再试，或者让身边的人帮忙。」
- 结束态的语音面板：大标题「语音下单已结束」，轻点整块重新开始说话；底栏「重复一遍」重念结束语，「改用表单」照常可用。
- 没听清结束时，若下单门槛都已满足，「不用填，直接下单」（当前位置 + 最早可约时间，两步确认）出现在结束态的语音面板里 —— 原本它只在切到表单之后才出现，不切表单就要把它挪过来，否则失败后最省力的出路跟着消失。取消结束时不提供（用户刚说了不要）。
- **不变**：语音权限被拒 / 识别器不可用（`:221`）、解析端点不存在（`:494` 与 `:843` 的端点不可用一支）仍切表单 —— 重说多少遍都不会好。阈值 3 次 / 2 轮不变。

## Non-goals

- 不调阈值（负责人 10-05 只确认了文案与「不切表单」）。
- 不做「转客服代下单」—— 后端没有该接口（#502 正文 2026-10-02 核实）。

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`：新增一条要求（ADDED），理由同 `sync-voice-partial-start-time`：该能力已被多个未归档变更 MODIFY。
  三个未归档变更里「repeated failures SHALL fall back to the form」那一句与本变更冲突，本变更同时改写那三处（`enable-one-utterance-booking`、`disambiguate-same-name-start-place`、`enable-cross-turn-voice-correction`），让它们归档时不再写回相反的要求。
