# volunteer-profile-first-screen Specification

## Purpose
TBD - created by archiving change show-volunteer-total-distance. Update Purpose after archive.
## Requirements
### Requirement: 首屏主指标优先显示累计公里
志愿者「我」首屏的主指标 SHALL 在累计里程向下取整不少于 1 公里时显示公里数，并在其下显示完成次数；否则 SHALL 显示完成次数。系统 SHALL NOT 显示「0 公里」。缺少里程字段 SHALL NOT 导致响应解码失败。

#### Scenario: 有里程
- **WHEN** 志愿者已完成 24 次陪跑且 `totalDistanceMeters` 为 12999
- **THEN** 主指标显示「12 公里」，其下显示「共 24 次陪跑」，读屏念「累计陪跑 12 公里，共 24 次陪跑」

#### Scenario: 缺字段或不足 1 公里
- **WHEN** 志愿者已完成 24 次陪跑且 `totalDistanceMeters` 缺失或为 999
- **THEN** 主指标显示「24 次陪跑」，与改动前一致

#### Scenario: 新人
- **WHEN** `totalCompleted` 为 0 或缺失
- **THEN** 仍显示新人态文案，不显示公里

