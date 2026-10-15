## Why

「口碑之星」（`HIGH_RATED`）要均分 ≥ 4.8 **且** ≥ 10 条评价，而「下一枚勋章」的进度只跟条数一维。一位 20 条评价、均分 4.0 的志愿者会看到满格进度（`10/10`）加一枚没解锁的勋章，没有任何线索说明卡在哪（iOS #366，来源 #284 分流）。后端已在 `VolunteerNextBadgeDto.blockedBy` 下发「卡在哪一维」，iOS 一直没接。

## What Changes

- `VolunteerNextBadgeDto` 解码 `blockedBy`，按开放枚举处理：只认 `RATING`，`RATINGS_COUNT`、null 与不认识的值一律按原样显示进度，不影响整份解码。
- `blockedBy = RATING` 时，进度那一行在条数后面补一句「评分还差一点」（成就页、读屏同句）；「我」首屏徽章格的小字由 `10/10` 换成「评分还差一点」。不显示阈值 4.8（后端刻意不下发）。
- 条数照常保留：后端在评分与条数**都不够**时报 `RATING`（`VolunteerBadge.blockedBy`），只说评分会把条数也不够这件事藏起来。
- `VolunteerHomeIncentiveSummary.hero` 在 `RATING` 时不拿勋章进度当主角（满格的大数字正是要避免的误导），落到下面那一行。

## Capabilities

### New Capabilities

### Modified Capabilities
- `volunteer-profile-first-screen`: 新增「下一枚勋章卡在评分时说清楚」。

## Impact

- 代码：`blindRun/Volunteer/VolunteerAchievements.swift`（模型与文案）、`blindRun/Volunteer/VolunteerProfileFirstScreen.swift`（徽章格小字）、`blindRun/Volunteer/VolunteerHomeIncentive.swift`（`hero`）。视图文件不改。
- 契约：只读既有 `GET /api/volunteer/achievements` 的 `nextBadge.blockedBy`，不改。
