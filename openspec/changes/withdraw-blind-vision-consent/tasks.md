## 1. 实现

- [x] 1.1 拒绝时导盲犬显式传 `false`（2026-10-19 起改发 `guideDog = NOT_SPECIFIED`，见变更 `accept-guide-dog-and-tether-not-specified`，iOS #472）
- [x] 1.2 `PrivacyConsentStore.revokeConsent`
- [x] 1.3 view model：撤回待保存状态、立即保存、成功后删记录、失败提示、重新同意作废
- [x] 1.4 视力区块：撤回按钮（逐字文案）、成功提示上屏、保存中禁用「填写视力状况」
- [x] 1.5 迁移指南 §9 红线加例外说明

## 2. 验证

- [x] 2.1 单测：拒绝传 `false`（#472 起断言改为 `guideDog = NOT_SPECIFIED`）、撤回成功 / 失败 / 重新同意作废（`BlindEscortPreferencesTests`）真机执行并验红 —— 2026-10-14 iPhone 16 Pro：passed=35 failed=0；三处打回红 4 条（含新增「表单无效时撤回」）
- [ ] 2.2 真机目视：撤回按钮在 AX5 下不截断、成功提示上屏 —— 转 #410
