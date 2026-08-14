# 设计

## D1. 为什么是删掉，不是留着等后端

留着的成本被低估了。`pointsBalance ?? (totalCompleted * 100)` 这种写法有一个隐蔽性质：
**后端哪天真加了 `pointsBalance`，前端不会有任何信号**——数字会安静地从「完成数×100」
变成另一个值，没有人会去核对那一天发生了什么。而如果后端加的字段口径与
「完成数×100」不同（大概率不同），志愿者会看到积分**莫名其妙地跳变或倒退**。

反过来，删掉之后后端真做积分时，前端是「加一个新字段」——一次显式的、会被 review 的改动。

**`??` 兜底在这里制造的是一个不可观测的状态**，这与仓库既有的那条教训同族
（`docs/review/` 记过的「宽容解码器把 available 订单解成空列表，零报错，四个月没人发现」）：
兜底本身不是问题，**兜底之后无法区分「真值」和「兜底值」**才是。

## D2. 分层门槛：按完成单数，不按调研给的小时数

调研推荐的 25 / 50 / 100 / 250 / 500 是**服务小时数**
（`docs/research/live-trip-sharing-and-volunteer-incentives-20260813.md` §2）。
我们没有时长数据（`dispatch-summary` 只有 `totalCompleted`），**不能把小时数的阈值直接套到单数上**——
那会让「50 单」和「50 小时」看起来是同一件事。

本变更的门槛是我们自己的口径：

| 档位 | 完成单数 | 为什么是这个数 |
|---|---|---|
| 首次陪跑 | 1 | 首单完成是留存曲线上最陡的一段，必须当场有反馈 |
| 熟练陪跑员 | 10 | UIS 的结论是每位盲人跑者需要 6–8 名固定陪跑员；10 单意味着这个人已经能撑起一个人的固定供给 |
| 资深陪跑员 | 25 | |
| 金牌陪跑员 | 50 | |
| 荣誉陪跑员 | 100 | 高层要看起来值得挣，间距刻意拉开 |

规则**写在页面上**（「再完成 N 单解锁下一档」），符合调研那条「积分口径要透明可预测，
用户能自己算出来」。后端补上时长字段后可以再加一条并行的时长维度，不需要推翻这套。

## D3. 徽章不能只靠颜色区分

WCAG 1.4.1：颜色不得作为唯一指示。志愿者端同样有低视力用户
（记忆 `low-vision-visual-channel-unaudited`：本仓库的视觉通道从没被系统性检查过，
而这次是新写的页面，不该再欠一笔）。

每一档必须同时具备：**不同的档位名称文字** + **不同的 SF Symbol** + 颜色。
已解锁 / 未解锁的区别也不能只靠灰度——未解锁的档位文案直接写「还差 N 单」。

`accessibilityLabel` 给完整语义：「金牌陪跑员，已解锁」/「荣誉陪跑员，还差 43 单解锁」。

## D4. 替换页面而不是新增页面

首页 `VolunteerHomeView.swift:1266` 那个 `gift` 图标入口、导航路由、
`VolunteerPointsPlaceholderView` 的位置全部沿用。改的是页面**内容**：

| 删 | 留/换 |
|---|---|
| `--` 的 48pt 假数字 | 换成完成单数（真值） |
| 「积分商城即将上线」 | 删 |
| 4 个硬编码商品的 `LazyVGrid` | 换成 5 档成就的列表 |
| `VolunteerPointsViewModel`（只有一个从不赋值的 `errorMessage`，是死代码） | 删掉整个类；页面纯渲染 `VolunteerDispatchSummaryResponse`，无自己的状态 |
| 入口 `gift` 图标 + 「积分」标题 | 换成 `rosette` + 「服务成就」 |

页面没有自己的网络请求——数据来自首页已经加载好的 `dispatchSummary`，通过参数传入。
因此**不新增 `Task`，也不新增 `AnyCancellable`**（`AGENTS.md` 的并发单一模型约束在这里的
正确姿势是：这条数据流一个都不要）。

## D5. 首页那四格：只换一格

`VolunteerHomeView.swift:1431` 现在是 `("积分", resolvedPointsBalance)` /
`("完成", completedCount)` / `("评分", ratingText)` / `("接单率", acceptanceRateText)`。

删掉「积分」那格之后剩三格。**不补第四格凑数**——`totalDispatched` / `totalDeclined` /
`totalTimeout` 在下面本来就有一行专门展示（`:1467-1470`），挪上来只是重复。

`:1481` 那条 `accessibilityLabel` 里的「积分 N」同步删掉。这一条容易漏：
数字从视觉上消失了，但读屏用户还在听。

## D6. 兼容性：`pointsBalance` 字段本身要不要从模型里删

**删**。它是 `Codable` 的可选字段，删掉不影响解码（多余的 JSON 键本来就被忽略），
而留着会让下一个人以为后端有这个字段。

同理删 `VolunteerDispatchSummaryRecentOrder.pointsDelta` 的 `+100` 兜底
（`VolunteerDispatchSummaryModels.swift:177-182`）与 `VolunteerOrderFlowViews.swift:11` 的
`"+100 积分"`、`:65` 与 `:2375` 的「服务完成，获得 +100 积分」、`:2458` 的
`accessibilityLabel("服务完成，获得一百积分")`。

**`pointsDelta` 字段本身保留**——它在 `recentOrders` 里，若后端将来真发积分，
这是它的落点；但**不再给它编造兜底值**，为 `nil` 时那一格就不显示积分行。
这与 D1 不矛盾：D1 反对的是「兜底之后无法区分真值和兜底值」，`nil` 时什么都不显示恰恰是可区分的。
