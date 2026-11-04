# volunteer-profile-first-screen Specification

## Purpose
定义志愿者「我」首屏的主指标与三列统计怎么取值、怎么显示：陪伴时长满 1 小时才以小时为主指标，否则用完成次数；零值与缺字段显示 `--` 并让读屏念完整的话，不把「0」念给用户。
## Requirements
### Requirement: 首屏主指标优先显示陪伴时长
志愿者首页的陪伴时长卡 SHALL 在陪伴时长大于 0 时以「X 小时 Y 分钟」为主数字，并在其下显示完成次数；时长为 0 或缺字段时 SHALL 显示完成次数。系统 SHALL NOT 显示「0 小时」「0 分钟」。首页 SHALL NOT 再显示累计里程统计格；固定搭档为 0 时 SHALL 显示 `--`。

#### Scenario: 满 1 小时
- **WHEN** 志愿者已完成 16 次陪跑且 `totalServiceMinutes` 为 240
- **THEN** 主数字显示「4 小时」，其下显示「共 16 次陪跑」，读屏念「累计陪伴 4 小时，共 16 次陪跑」

#### Scenario: 缺字段或不足 1 小时
- **WHEN** 志愿者已完成 24 次陪跑且 `totalServiceMinutes` 缺失，或为 59
- **THEN** 缺失时主数字显示「24 次陪跑」；为 59 时主数字显示「59 分钟」，其下显示「共 24 次陪跑」

#### Scenario: 新人
- **WHEN** `totalCompleted` 为 0 或缺失
- **THEN** 陪伴时长卡显示新人态文案，不显示进度条，也不显示连续陪跑与评分两张半宽卡

#### Scenario: 零值不上屏
- **WHEN** 没有已点亮的连续陪跑，且没有跑者把志愿者设为固定搭档
- **THEN** 那张半宽卡显示「固定搭档 --」，读屏念一句完整的话，不念「0」也不念标点

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

### Requirement: 首页只放「我做过什么」，接单内容在接单页
志愿者首页 SHALL 按顺序显示：「需要你处理」（有事时）→ 陪伴时长卡 → 连续陪跑与评分两张半宽卡 → 最近陪跑 → 徽章，全部为白色圆角卡片。首页 SHALL NOT 显示派单状态与定位摘要；它们 SHALL 显示在接单页顶部的状态卡里。卡片 SHALL 只在有去处时画箭头：陪伴时长去服务成就，连续陪跑去固定搭档，最近陪跑去跑后详情；评分卡没有去处，SHALL NOT 画箭头。无障碍字号下两张半宽卡 SHALL 改为上下排。

#### Scenario: 首页没有派单状态
- **WHEN** 志愿者打开首页，派单摘要已加载
- **THEN** 首页上找不到派单状态卡；进入接单页后，状态卡显示接单状态、覆盖范围与「保持 App 开着」的说明

#### Scenario: 有待确认预约
- **WHEN** 有一张待确认的跨天预约
- **THEN** 它出现在首页标题下方、陪伴时长卡之前

### Requirement: 最近陪跑卡取跑后记录月度列表
最近陪跑卡 SHALL 取 `GET /api/orders/mine/run-records` 本月第一条记录；本月没有记录时 SHALL 取上月。卡上 SHALL 显示公里数（`distanceM` 为空时不显示）、对方脱敏姓名与地点；`thumbnail` 为空或点全部重合时 SHALL NOT 画路线图，也 SHALL NOT 画占位图。两个月都没有记录时 SHALL 显示一句说明并保留「全部记录」入口；加载失败时 SHALL 显示失败说明与重试按钮。系统 SHALL NOT 显示接口没有给出的数字（例如单次陪伴分钟数）。

#### Scenario: 有路线
- **WHEN** 本月第一条记录 `distanceM` 为 5000、`partnerName` 为「王*」、`thumbnail` 有 30 个分散的点
- **THEN** 卡上显示「5.00 公里」「和王*」与地点，右侧画路线；读屏念「王」而不念星号

#### Scenario: 没有路线
- **WHEN** `thumbnail` 为 null
- **THEN** 右侧不画任何图

#### Scenario: 本月没有
- **WHEN** 本月 `items` 为空、上月有一条
- **THEN** 卡上显示上月那一条

### Requirement: 首页底部入口是白色底座里的一枚胶囊
首页底部 SHALL 显示一个白色底座，里面一枚胶囊，滚动内容 SHALL NOT 被它盖住。没在接单时 SHALL 是带蓝色圆形滑块的轨道，向右滑过 20% 开启接单并进入接单页，读屏用户双击开启。接单中 SHALL 是浅绿底深绿字「接单中 · 进入接单」，点按进入接单页；读屏 SHALL 保留「停止接单」自定义动作。系统 SHALL NOT 再提供向左滑动停止接单的手势，停止接单走接单页的「暂停接单」。资质或培训没完成时，点按轨道 SHALL 打开接单前进度。

#### Scenario: 读屏开启
- **WHEN** VoiceOver 用户聚焦没在接单的轨道并双击
- **THEN** 开启接单并进入接单页

#### Scenario: 接单中点按
- **WHEN** 接单中，志愿者点按胶囊
- **THEN** 进入接单页，接单状态不变

#### Scenario: 浅绿胶囊对比度
- **WHEN** 系统为亮色或暗色外观
- **THEN** 胶囊文字与底色对比度都不低于 4.5:1

