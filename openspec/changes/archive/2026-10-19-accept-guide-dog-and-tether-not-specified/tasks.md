## 1. 模型

- [x] 1.1 `BlindProfileResponse` 加 `guideDog: String?`；新增 `GuideDogStatus`（YES / NO / NOT_SPECIFIED）与按档案解析的入口
- [x] 1.2 `BlindProfileUpdateRequest` 用 `guideDog` 替换 `hasGuideDog`；`TetherPreference` 加「未提供」的判定入口
- [x] 1.3 Mock 按新字段读写档案

## 2. 资料页

- [x] 2.1 导盲犬开关改为三选一菜单，64pt，读屏念当前选项
- [x] 2.2 请求体：同意 → 照选项发（认不出且没改 → 不带键）；拒绝 / 撤回 → `NOT_SPECIFIED`；从没被问过 → 不带键
- [x] 2.3 牵引方式选「还没决定」且档案原来有值 → 发 `NOT_SPECIFIED`
- [x] 2.4 撤回成功文案改成严格成立

## 3. 陪跑员端与下单页

- [x] 3.1 订单页陪跑要求：两项都未提供时只显示一句兜底
- [x] 3.2 邀请卡：两项都未提供时小字不出「请当面与跑者确认」
- [x] 3.3 下单页引导提示把 `NOT_SPECIFIED` 当没填

## 4. 验证

- [x] 4.1 单测：撤回发 `NOT_SPECIFIED`、保存不改写 `NOT_SPECIFIED`、牵引方式撤回、两项未填合成一句、邀请卡不重复，逐条验红 —— 2026-10-19 iPhone 16 Pro：passed=151 failed=0；两批打回 8 处实现，failed=11 / failed=5，每处都有对应用例变红
- [x] 4.2 编译门禁 `build-for-testing` 与规格校验通过 —— 2026-10-19 TEST BUILD SUCCEEDED；spec-coverage / error-codes / docs / openspec --strict 全过
- [x] 4.3 真机跑覆盖本次改动的 suite —— 单测见 4.1；UI 用例 `testBlindProfileGuideDogChoiceIsTallAndSpeaksTheCurrentValue` 2026-10-19 iPhone 16 Pro passed=1（首跑量到 63.99999999999994，按既有口径改 63.5）；验红：64pt 挪到 Menu 外后量到 20.3pt，变红
