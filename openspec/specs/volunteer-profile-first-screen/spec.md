# volunteer-profile-first-screen Specification

## Purpose
定义志愿者「我」首屏的主指标与三列统计怎么取值、怎么显示：陪伴时长满 1 小时才以小时为主指标，否则用完成次数；零值与缺字段显示 `--` 并让读屏念完整的话，不把「0」念给用户。
## Requirements
### Requirement: 首屏主指标优先显示陪伴时长
志愿者「我」首屏的主指标 SHALL 在陪伴时长向下取整不少于 1 小时时显示小时数，并在其下显示完成次数；否则 SHALL 显示完成次数。系统 SHALL NOT 显示「0 小时」。三列统计第一格 SHALL 显示累计里程，不足 1 公里时 SHALL 显示 `--`；固定搭档为 0 时 SHALL 显示 `--`。

#### Scenario: 满 1 小时
- **WHEN** 志愿者已完成 16 次陪跑且 `totalServiceMinutes` 为 239
- **THEN** 主指标显示「3 小时」，其下显示「共 16 次陪跑」，读屏念「累计陪伴 3 小时，共 16 次陪跑」

#### Scenario: 缺字段或不足 1 小时
- **WHEN** 志愿者已完成 24 次陪跑且 `totalServiceMinutes` 缺失或为 59
- **THEN** 主指标显示「24 次陪跑」

#### Scenario: 新人
- **WHEN** `totalCompleted` 为 0 或缺失
- **THEN** 仍显示新人态文案，不显示小时

#### Scenario: 零值不上屏
- **WHEN** 累计里程不足 1 公里，或没有跑者把志愿者设为固定搭档
- **THEN** 对应格子显示 `--`，读屏念一句完整的话，不念「0」也不念标点

