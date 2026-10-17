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

### Requirement: 下一枚勋章卡在评分时说清楚

当 `GET /api/volunteer/achievements` 的 `nextBadge.blockedBy` 为 `RATING` 时，「下一枚勋章」的进度文本 SHALL 在条数之后接「评分还差一点」，读屏朗读同一句；「我」首屏徽章格的进度小字 SHALL 显示「评分还差一点」。这些文案 MUST NOT 出现「解锁」字样，MUST NOT 显示评分阈值。`blockedBy` 为 `RATINGS_COUNT`、null 或客户端不认识的值时，SHALL 按原来的条数进度显示，且 MUST NOT 让整份响应解码失败。

#### Scenario: 条数满格但评分不够
- **WHEN** `nextBadge` 为 `{"code": "HIGH_RATED", "current": 10, "target": 10, "blockedBy": "RATING"}`
- **THEN** 成就页进度文本为「已完成 10 / 10 条评价，评分还差一点」，首屏徽章格小字为「评分还差一点」，均不含「解锁」

#### Scenario: 卡在条数
- **WHEN** `blockedBy` 为 `RATINGS_COUNT`，`current` 为 7、`target` 为 10
- **THEN** 进度文本仍为「已完成 7 / 10 条评价」

#### Scenario: 不认识的值
- **WHEN** `blockedBy` 为客户端不认识的字符串
- **THEN** 整份响应照常解码，进度按 `blockedBy` 为 null 时显示

### Requirement: Scheduled order card matches the order page's agreed screen
The volunteer home's scheduled order card SHALL use the same components as the order page v2 "agreed" screen: a raised primary action button for confirming departure and a neutral text button for releasing the order. Both buttons SHALL have a touch target of at least 64pt. Releasing the order SHALL require confirmation through the same bottom sheet the order page uses.

#### Scenario: Releasing from the home card
- **WHEN** the volunteer taps "我去不了" on a scheduled card
- **THEN** the order page's cancel confirmation sheet SHALL appear
- **AND** the order SHALL be released only after the volunteer chooses to cancel in that sheet

#### Scenario: Touch targets
- **WHEN** the scheduled card is shown at any Dynamic Type size
- **THEN** both the confirm button and the "我去不了" button SHALL be at least 64pt tall

