## Why

负责人 2026-11-05 真机体验后定：新用户一登录就被拦在「完善信息」页，「这个应该是以后他们想填写再填写的，不要因为这个卡住他们」（Jayden23018/blind-run-ios#781）。
Apple HIG「Onboarding」：「Postpone nonessential setup flows or customization steps」。后端只在下单时要紧急联系人（403 `EMERGENCY_CONTACT_REQUIRED`），登录与浏览首页都不需要。

## What Changes

- 登录后不再有盲人引导流：删除 `BlindRunnerOnboardingView`、`RootRoute.blindProfile`、`AppState.blindOnboardingStep`。资料不全、甚至后端没有档案（404）都直接进首页。
- 根路由的刷新键不再含 `isBlindBookingReady`：否则在约跑页里补完紧急联系人时整棵根视图重建，人被踢出约跑页。
- 约跑页顶部新增「约跑前还差 N 项」卡（`BlindBookingMissingSetupCard`）：缺昵称列「昵称 · 未填写」→ 个人资料页；缺紧急联系人列「紧急联系人 · 未添加 / 未设主联系人」→ 紧急联系人页。补齐后卡片消失。
- 门槛文案改成指向这张卡；从补资料页回到约跑页时，补齐了的那一句撤掉。
- 下单门槛本身不变：昵称 + 至少 1 位且恰好 1 位主紧急联系人。

## Capabilities

### Modified Capabilities
- `blind-booking-prerequisites`: 新注册的视障跑者不再先走引导流；缺的前置项在约跑页补。

## Impact

- 代码：`ContentView.swift`、`AppState+Onboarding.swift`、`BlindBookingView*.swift`、`BlindBookingViewModel+StepNavigation.swift`，新增 `BlindBookingMissingSetupCard.swift`，删除 `BlindRunnerOnboardingView.swift`。
- 不动：`blindRun/Profile/ProfileModule.swift`（Jayden23018/blind-run-ios#750 在改个人资料页）。
- 后端：无契约改动。相关但独立：Jayden23018/blind-run-backend#926 让 `PUT /api/blind/profile` 的 `name` 可选，供 #750 在昵称为空时保存其他字段。
- 测试：负责人 11-05 定不跑测试，由负责人自己验；只做编译检查。
