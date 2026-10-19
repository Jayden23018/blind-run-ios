## Why

后端 #800（backend#773 #795，2026-10-19 已部署）让盲人档案的「导盲犬」和「牵引方式」能表示「还没决定 / 未提供」：新增必填的 `guideDog`（`YES` / `NO` / `NOT_SPECIFIED`），`tetherPreference` 加了 `NOT_SPECIFIED` 并成为新建档默认值。iOS 还只认布尔 `hasGuideDog`，后果有三条：撤回视力同意时发 `hasGuideDog: false`，后端存成「明确没有导盲犬」；同意后任何一次保存都把「未提供」改写成「没有」；牵引方式选回「还没决定」撤不回。陪跑员端与下单页也没认 `NOT_SPECIFIED`（iOS #472）。

## What Changes

- 资料页「平时使用导盲犬」由开关改为三选一「有 / 没有 / 不说」，请求改发 `guideDog`，不再发 `hasGuideDog`。读档案认 `guideDog`，新账号默认「不说」。
- 撤回或拒绝视力同意时发 `guideDog = NOT_SPECIFIED`；同意后保存时「不说」原样发 `NOT_SPECIFIED`，不改写成 `NO`。撤回成功文案改成严格成立的说法。
- 牵引方式选「还没决定」时，档案原来有值就发 `NOT_SPECIFIED`，让它能撤回。
- 陪跑员端：视力与牵引都是「未提供」时，订单页合成一句「跑者没有填写，出发前请当面问清楚怎么带」；邀请卡小字不再重复「请当面与跑者确认」。
- 下单页把 `tetherPreference = NOT_SPECIFIED` 当「没填」，引导提示对新账号恢复出现。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `blind-vision-profile`：拒绝 / 撤回时导盲犬的表达方式改为 `guideDog = NOT_SPECIFIED`；新增导盲犬三选一、牵引方式可撤回、陪跑员端「两项都未提供」合成一句、下单页提示认 `NOT_SPECIFIED` 五条要求。

## Impact

- 代码：`blindRun/Core/Models/ProfileModels.swift`、`blindRun/Profile/ProfileModule.swift`、`blindRun/Core/Models/OrderDisplayHelpers.swift`、`blindRun/Volunteer/VolunteerInviteQueue.swift`、`blindRun/BlindRunner/BlindBookingView.swift`、`blindRun/Core/MockAPIClient+Profile.swift`。
- 契约：只用后端 origin/main 已有字段，不改契约。
- 测试：`BlindEscortPreferencesTests`、`EscortNeedsTests`，以及邀请卡小字的用例。
- 发布风险：已被旧版 iOS 存成 `NO` 的老用户区分不出来（后端选择存量不回填），本变更修不回来。
