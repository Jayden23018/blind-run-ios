## Why

**App 正在向志愿者展示一套不存在的积分体系。**

现状不是「忘了做」，是一个**已经过期的临时降级**。`openspec/specs/system-dispatch-flow/spec.md:56-67`
明确写着：

> The iOS volunteer home screen ... SHALL use a temporary client-side points placeholder
> **until a real points API exists**
> - **WHEN** dispatch summary does not contain a real `pointsBalance`
> - **THEN** the app SHALL display temporary points as `totalCompleted * 100`

那个 `until` 从未到来。核过后端 `origin/main`：

- `docs/api_spec.yaml` 的 `VolunteerDispatchSummaryResponse` **没有 `pointsBalance` 字段**
- 后端源码 `git grep -i 'pointsBalance|points_balance|积分' -- src/` **零命中**

于是 `VolunteerDispatchSummaryModels.swift:82-83` 的 `??` 永远走右边：

```swift
var resolvedPointsBalance: Int { pointsBalance ?? ((totalCompleted ?? 0) * 100) }
```

志愿者在首页听到的「积分 700」，实际含义就是「完成 7 单」——**同一个数字换了个说法，
却被命名成一种可累积、可兑换的东西**。

比数字更大的问题是它背后那整页承诺。`VolunteerOrderFlowViews.swift:1700-1788`
是一个完整的**假商城**：积分数字写死 `--`，4 个商品（运动腰包 / 水壶 / 毛巾 / 腰灯）
硬编码在数组里，每个都标「敬请期待」，`VolunteerPointsViewModel` 只有一个从不被赋值的
`errorMessage`。`docs/review/frontend-backend-alignment-review-20260812.md:252` 已经记过这处。

调研结论正对着这件事：志愿者激励最该避开的陷阱就是**没有实质的表彰**
（`docs/research/live-trip-sharing-and-volunteer-incentives-20260813.md` §2）。
一个永远兑换不了的积分商城，比没有激励更伤——它每次都在提醒志愿者「这个平台承诺过什么，
但没兑现」。

**而真实数据后端全都有**：`totalCompleted`、`totalAccepted`、`avgRating`、`totalRatings`、
`acceptanceRate` 都在 `dispatch-summary` 里，全部可追溯、可解释、志愿者能自己核对。
用它们做服务成就，零后端改动。

## What Changes

- **删除**假积分：`pointsBalance` 字段、`resolvedPointsBalance` 的 `??` 兜底、
  `pointsDelta` 的 `+100` 兜底，以及所有「+100 积分」「每完成一次服务 +100 积分」文案。
- **替换**（不是新增页面）`VolunteerPointsPlaceholderView` 为服务成就页：
  沿用首页已有的入口与路由，页面内容换成按 `totalCompleted` 分层的成就 + 真实统计。
- 分层门槛按**完成单数** 1 / 10 / 25 / 50 / 100，规则在页面上写明，志愿者能自己算出下一档还差几单。
- 首页那四格里的「积分」换成「完成」，其余三格（完成 / 评分 / 接单率）本来就是真数据，不动。
- MODIFIED `system-dispatch-flow` 里那条 Requirement，把 temporary points 那两个 Scenario 撤掉。

## 非目标（明确不做）

- **不做排行榜**。调研里这是首要陷阱：排行榜竞争会把动机从利他挪到游戏机制上，
  且必须可选择退出——做一个还要配一套退出机制，收益不抵。
- **不做优先派单权重**。滴滴「点亮勋章后接单概率增加」在后端派单算法里，前端做不了。
  已投 handoff。
- **不做服务时长证明 / 证书**。调研本轮**没搜到**可用材料（PDF 版式、可验证凭证、
  第三方核验流程都缺），且我们只有单数没有时长。单独立项，先补调研。
- **不动评分与接单率的口径**。它们已经是后端真值，本变更只是把它们从「积分」旁边挪出来。

## 需要后端确认的

1. **是否要做真的积分体系**？若要，请给出：积分产生规则（按单 / 按时长 / 按评分加权）、
   有没有兑换出口、会不会过期。本变更把前端的假实现撤掉，**不阻塞**后端将来做真的——
   届时前端把成就页的数据源换成后端字段即可。
2. **优先派单权重**：完成单数多的志愿者要不要在派单里加权？这是后端算法问题，
   但它决定成就体系到底是「荣誉」还是「有实际收益」，会影响前端文案措辞。
3. `dispatch-summary` 能否补 **累计服务时长**？现在只有单数。按服务小时数分层是行业通行做法
   （调研 §2），我们缺这一维，只能退而用单数。
