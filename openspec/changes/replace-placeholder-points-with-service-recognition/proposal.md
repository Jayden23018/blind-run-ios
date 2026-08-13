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

## 2026-08-13 追加：改用真端点，并对齐国标星级（后端 SPEC-D D1）

上面「用 `dispatch-summary` 做成就页，零后端改动」的判断**只对了一半** ——
后端一直就有 `GET /api/volunteer/achievements`，里面有 `totalServiceMinutes` 与
**后端自己派生的 `badges`**（`VolunteerBadge` 七个码）。所以下面这条待确认项当场作废：

> 3. `dispatch-summary` 能否补**累计服务时长**？

**答：不用补，`/api/volunteer/achievements` 已经有 `totalServiceMinutes`。**
后端刻意把它和 dispatch-summary 分开：扫全部已完成订单的代价不该压在首页最热的端点上。

于是这次把成就页改成读真端点，并撤掉客户端自己编的那五档称号
（熟练 / 资深 / 金牌 / 荣誉陪跑员，阈值 1/10/25/50/100 单）—— 后端没有这些名字，
一页上并排放两套勋章体系比少一套更让人看不懂自己拿到了什么。

**新增国标星级栏，与平台勋章分两栏，不合并。** 阈值取 GB/T 40143—2021
的 100 / 300 / 600 / 1000 / 1500 小时。分栏不是排版选择：平台最高的时长勋章是
`HOURS_50`（50 小时），够不着一星的 100 小时；合并展示会让志愿者以为拿了最高勋章就能评星，
去学校申报时才发现一星都评不上。

两个后端字段（`nextBadge` / `starLevel`）在写这份提案时还没发布，本次的处理方式刻意不同：

| 字段 | 缺失时怎么办 | 为什么 |
|---|---|---|
| `starLevel` | 由 `totalServiceMinutes` 本地推算 | 门槛是**公开的国家标准**，不随平台业务代码变，两边算出同一个数 |
| `nextBadge` | 整段不显示 | 阈值住在后端 `VolunteerBadge.isUnlockedBy` 的穷举 switch 里（注释写明「要改阈值时改这里一行」），且 `HIGH_RATED` 是「均分 ≥ 4.8 **且** 评价 ≥ 10 条」的双条件，单一阈值表达不了 —— 镜像必然漂移 |

**同日后端就发布了 D1（`9f8606d`）**，两个字段都已上线，于是上面这张表退成防御路径。
真正上线后才知道、且原方案会踩的一条：

🔴 **`nextBadge.current` / `target` 的单位随 `code` 变，`HOURS_*` 给的是「分钟」不是「小时」。**
原方案「不拼单位、只渲染 `已完成 37 / 50` 分数形式」在 `HOURS_10` 上会显示
「已完成 360 / 600」—— 分母确实是对的，但用户看着勋章名叫「累计服务 10 小时」，
读出来的就是 360 小时。已改成按 `code` 查表选量词并把分钟换算成小时。

🔴 **`HIGH_RATED` 的进度条会满格但勋章不解锁**（双条件，进度只跟评价条数）。
所以这一栏的文案一律不写「还差 N 就解锁」—— 那是一个只在少数志愿者身上翻车、
且极难被发现的假承诺。

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
