## 1. 实现

- [x] 1.1 `LocationService` 改三档 `setEscortLocationMode`
- [x] 1.2 协调器按状态选档位；健康横幅「已开启」那句改写
- [x] 1.3 `plan.md`、`docs/04`、skill `aidrun-a11y-voice` 同步

## 2. 验证

- [x] 2.1 单测：出发即 `.sharing`、跑步 `.running`、终态与换身份 `.off`
- [x] 2.2 编译门禁、SwiftLint 棘轮、`openspec validate --strict`
- [x] 2.3 真机（iPhone 16 Pro 有线，2026-10-28）：`EscortBackgroundLocationTests` 等 6 个 suite `passed=91 failed=0`；验红把出发 / 汇合档位打回 `.off` → 预期的 1 条红（`failed=1`）。
  双真机人工验收（陪跑员出发后切到高德导航，盲人端持续看到位置移动）单台 iPhone 做不了，挪到人工验收 issue #410
