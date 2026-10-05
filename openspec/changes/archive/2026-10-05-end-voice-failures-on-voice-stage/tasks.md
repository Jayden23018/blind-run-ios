# Tasks

- [x] 1.1 `VoiceOrderWizard` 新增结束态 `endedMessage` / `endedAfterFailure`；取消（本地取消词、后端 CANCEL）与连续没听清 / 连续两轮无时间改走结束态，文案按 proposal；权限被拒、端点不存在仍走 `fallBack`。
- [x] 1.2 `BlindBookingView`：结束态仍显示语音面板（标题、轻点重启、底栏两键）；没听清结束且门槛满足时在面板里给出「不用填，直接下单」。
- [x] 1.3 改写三个未归档变更里「repeated failures SHALL fall back to the form」那一句。
- [x] 2.1 单测：取消 / 没听清两种结束态的播报、`isRunning`、`fallbackMessage == nil`；端点不存在仍切表单；`start()` 清掉结束态。验红。
- [x] 2.2 `openspec validate --all --strict`；`build-for-testing`；真机跑 `VoiceOrderWizardTests`。

> 2026-10-05：真机 iPhone 16 Pro `VoiceOrderWizardTests` → `passed=115 failed=0`（含新增 3 条）。
> 验红两次：撤掉 review 修复（识别起不来分流、门槛分支清结束态）→ 新增 2 条红；`endSession` 退回 `fallBack` → 取消 / 没听清相关 5 条红。均已还原。
