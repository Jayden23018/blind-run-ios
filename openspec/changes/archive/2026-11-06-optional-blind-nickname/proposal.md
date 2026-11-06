## Why

#781 之后昵称已经不挡进首页，但约跑时仍是门槛。负责人 2026-11-06 决定「昵称也改成可选」。App Store 审核指南 5.1.1(x) 要求姓名类信息可选、功能不以它为条件（调研见 `docs/research/blind-first-launch-onboarding-20261106.md`）。Issue：#789。

## What Changes

- 约跑前置条件去掉昵称，只剩紧急联系人、出发地点、预约时间。
- 「约跑前还差 N 项」卡去掉「昵称」一行。
- 进页播报与语音向导不再说「还要填一个昵称」。
- 昵称仍可在个人资料里填，不填不影响任何功能。

## Impact

- 代码：`BlindBookingGate`、`BlindBookingMissingSetupCard`、`AppState+Onboarding`、`VoiceOrderWizard` 的注释，及对应单测。
- 后端：没有昵称的跑者，求助短信称呼与跑后记录姓名要有兜底（Jayden23018/blind-run-backend#929），本变更合并前它先合。
