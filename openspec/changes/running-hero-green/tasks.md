## 1. 色与取色

- [x] 1.1 `FlowPalette.swift`：新增 `stateRunningTone` / `stateRunning`（`#0A6B72`，亮暗同值），更新头卡状态色一节里「跑步中青绿本 PR 不加」的过时注释
- [x] 1.2 `VolunteerOrderFlowPage.swift`：`VolunteerRunningPage.heroCard` 取色由 `stateAgreed` 改 `stateRunning`（暂停仍 `statePaused`）

## 2. 测试

- [x] 2.1 `FlowDesignSystemTests`：`heroStates` 加「跑步中」一项，更新其过时的注释
- [x] 2.2 新增用例：`stateRunning` 亮暗都是 `0x0A6B72` 且不等于 `stateAgreed` / `statePaused`（只钉色值，不管 `heroCard` 是否取用）

## 3. 文档同步

- [x] 3.1 `docs/ui/design-direction.md` §6.1：跑步中头卡改为青绿，去掉「青绿未启用」
- [x] 3.2 `docs/ui/mockups/INDEX.md`：跑步中一行「待确认」→「Current」，删「冲突 1」，改写「已知偏差」
- [x] 3.3 `docs/ui/mockups/volunteer-order-page-v2/DECISIONS-v2.md`：V4 标作废（保留原文），新增 V19

## 4. 验证

- [x] 4.1 `build-for-testing` 编译通过
- [x] 4.2 `openspec validate --all --strict --no-interactive` 与 `node scripts/validate-docs.mjs` 通过
- [ ] 4.3 真机跑 `FlowDesignSystemTests`（2026-09-30 两台真机均 unavailable，**未跑**；设备可用后补跑并归档本变更）
