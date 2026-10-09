## 1. 同意与文案

- [ ] 1.1 `PrivacyConsentPurpose` 新增 `voiceOrderThirdPartyLLM`（标题、逐条告知、同意/拒绝按钮、拒绝反馈），`appLaunch` 告知加一条并 `disclosureVersion` 3 → 4，首启摘要点名
- [ ] 1.2 `LegalFallbackCopy` 隐私政策「麦克风与语音内容」「第三方 SDK」各补一句

## 2. 闸门

- [ ] 2.1 `ConsentGatedVoiceOrderService` 装饰器与 `VoiceOrderConsentError`，`AppState.voiceOrder` 返回它
- [ ] 2.2 `BlindBookingView.startVoiceWizard()` 先判同意，未同意弹全屏同意页；同意后启动、拒绝后退到表单并念反馈

## 3. 验证

- [ ] 3.1 单测：未同意不发 `/parse`、同意后正常发、换账号不继承；文案指纹与关键词
- [ ] 3.2 验红：拿掉闸门，对应用例必须变红
- [ ] 3.3 真机只跑覆盖本次改动的 suite
- [ ] 3.4 `openspec validate --all --strict`、`node scripts/validate-docs.mjs`、编译门禁
