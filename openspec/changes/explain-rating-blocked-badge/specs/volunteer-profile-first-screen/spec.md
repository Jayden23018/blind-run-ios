## ADDED Requirements

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
