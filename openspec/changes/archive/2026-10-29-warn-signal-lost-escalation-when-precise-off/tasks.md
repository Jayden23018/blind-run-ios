## 1. 实现

- [x] 1.1 `LiveEscortHealthState.preciseLocationOff` 带上 `running`；进 `IN_PROGRESS` 时档位变化
- [x] 1.2 新文件 `EscortPreciseLocationCopy`：两端、跑步前后四句，去掉「走散提醒用不了」，时长只说「几分钟后」
- [x] 1.3 更正 `2026-10-28-gate-escort-sharing-on-precise-accuracy/design.md` 的风险说法

## 2. 验证

- [x] 2.1 单测：四句文案不含「已发出」「已通知」「短信」与具体时长；进 `IN_PROGRESS` 且精确位置关着时档位变化、根视图的朗读闸会再放行一次；出发到汇合不重复
- [x] 2.2 编译门禁、SwiftLint 棘轮、`openspec validate --strict`
- [x] 2.3 真机（iPhone 16 Pro 有线，2026-10-28，5055ec49）：`EscortPreciseLocationEscalationTests` `EscortPreciseLocationGateTests` `EscortBackgroundLocationTests` `LiveEscortTrackTests` `passed=40 failed=0`；验红（进跑步档位不变 + 跑步中那句写死时长并说已通知）→ 预期的 2 条红（`failed=2`）。
  人工确认进跑步时听得到这一句，挪到人工验收 issue #410
