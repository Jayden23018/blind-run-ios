## Why

负责人 2026-11-05 真机体验后定：「盲人需要实名才能用，这个需要取消这个功能，让盲人上手更简单。」（Jayden23018/blind-run-ios#767）
后端 Jayden23018/blind-run-backend#924 同时去掉 `POST /api/orders` 与 `/api/orders/voice/**` 上的 403 `IDENTITY_NOT_VERIFIED` 门槛。

## What Changes

- 首次引导不再有「实名认证」这一步，也不再有「稍后再说」和它的持久化标记。
- 首页卡片下方不再有「完成实名认证」入口行。
- 账户页不再有「实名认证」行；「我的」头像卡副标题不再提「实名」。
- 下单门槛去掉实名一档：`AppState.isBlindBookingReady` 只看基础资料与紧急联系人，`BlindBookingGate` 不再有 `identityVerification`。
- 语音下单不再特判 403 `IDENTITY_NOT_VERIFIED`；万一收到，按普通失败处理。`ErrorCode.identityNotVerified` 保留（错误码枚举要与后端对撞），文案改成不指向已删页面的通用句。
- 删除实名页（`blindRun/Profile/BlindIdentityVerification*.swift`）、`PrivacyConsentPurpose.blindIdentity`、`ProfileService.verifyBlindIdentity`、Mock 的实名提交与下单实名校验，以及只给它们用的模型。
- 首启告知与内置隐私政策、用户协议里「视障跑者预约前要先实名认证」改准为只有志愿者实名。按 `disclosureVersion` 判据，这是**少收集**，不 +1 版本，只更新指纹用例。

## Capabilities

### New Capabilities
- `blind-booking-prerequisites`: 视障跑者下单前要满足哪些条件。

### Modified Capabilities
- `blind-home-idle-state`: 删除未实名首页入口这条要求。
- `blind-settings-tab`: 账户页不再有实名认证行。
- `onboarding-audible-feedback`: 删除实名输入防丢失这条要求（实名页已删）。
- `auth-account-lifecycle`: 敏感信息单独同意不再有视障跑者实名这个收集点。

## Impact

- 代码：盲人端引导、首页、账户页、下单页、语音向导、`AppState`、Mock、`PrivacyConsent.swift`（只动 `blindIdentity` 与 `appLaunch` 文案）、`LegalLinksModels.swift` 两句。
- 不动：`blindRun/Volunteer/`（#768 在改）、`PrivacyConsent.swift` 其余部分（#769 在改）、生成代码 `Packages/AidRunAPI`。
- 接口：iOS 不再调用 `POST /api/blind/verify-identity`；`BlindProfileResponse.verifyStatus` 字段照常解码、不再使用。
- 测试：引用被删代码的单测与 UI 用例一并删改，只保证编译通过；负责人 11-05 定不跑真机测试，由负责人自己验。
- 依赖：Jayden23018/blind-run-backend#924 合并之前，盲人下单会被后端 403 拦住，本变更不能合。
