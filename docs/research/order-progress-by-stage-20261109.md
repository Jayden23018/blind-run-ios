# 订单页的进度展示要不要每个阶段都留？打车 / 外卖 App 怎么做（2026-11-09，#909）

## 问题

盲人订单页改版稿（`docs/ui/mockups/blind-order-tracking-20261109/`）每个状态都放了竖向时间轴。负责人提出另一种结构：

| 阶段 | 负责人提议 |
|---|---|
| 预约（已约好） | 完整时间轴 |
| 匹配 | 简化时间轴，突出当前匹配状态和下一步 |
| 接送与会合 | 简化时间轴，地图、距离、陪跑员信息为重点 |
| 跑步 | 去掉时间轴，突出实时数据和安全状态 |
| 完成 | 去掉时间轴，突出本次成果 |

要回答：Uber 这类产品在各阶段怎么展示进度，这个结构有没有依据。

## 结论

**负责人的结构有依据，建议采用，只改一处**：「简化时间轴」做成一行横向阶段条（照 United 行程页的阶段胶囊：四段「匹配 · 约好 · 汇合 · 跑步」，当前段白底），不做缩短的竖向列表。理由在下面第 2、3 条。

1. **没有一家在所有阶段都放同一个完整步骤列表。** 查到的做法都是按阶段换重点：
   - Uber 打车（官方工程博客）：等车时信息优先级是 P0 到达时间、P1 车辆和司机（认人用）、P2 整体进度；进度只是一根横条，而且最后 20% 固定对应最后 2 分钟。
   - Deliveroo（官方设计博客）：餐厅备餐这段长时间少变化，用分段进度条，「瞥一眼就够」；骑手取餐后，**整屏切成以地图为主**。
   - Just Eat（官方设计博客）：把状态压成「几个核心步骤」，屏幕分三段：顶部到达时间 + 状态、中间地图或插画、底部其余信息。
   - Uber Eats（官方新闻稿 2019 + 报道）：五步跟踪条，覆盖从确认到送达。这是外卖的长等待场景，相当于我们的「已约好」。
2. **「匹配中」简化有官方原话支持。** Apple HIG《Live Activities》举的例子：打车 App 找司机时可以显示更紧凑、不带额外细节的样式。
3. **「接送与会合」的重点是时间和认人，不是步骤。** Uber 把认车认人排在进度前面；Deliveroo 在这一刻让地图占满屏幕。所以这一段步骤只需要一行告诉你「在第几步」，竖向列表会挤掉地图和陪跑员行。
4. **跑步中、已完成去掉时间轴有依据。** Uber 行程中只给到达时间（灵动岛各阶段图）；HIG 举例打车结束后 Live Activity 留 30 分钟给人看行程总结。完成页「只留绿色卡」（11-07 决定）本来就是这个方向。
5. **对读屏用户，步骤列表留在「已约好」最有用。** W3C 的多步流程教程建议：步数已知时用有序列表，标出当前步和已完成步。约好到开跑可能隔几小时到几天，这一屏是盲人了解「接下来会发生什么」的地方。其余阶段用一句「第 N 步，共 4 步：……」就够了，读屏念一遍即可。
6. **一个附带发现**：Deliveroo 把倒计时改成时间区间（如「18:00–18:05」），因为倒计时往上跳会让人紧张。这与负责人原稿「陈预计出发 1:05–1:10」的写法一致。但后端只有一个时刻（`suggestedDepartAt`），区间要后端给，客户端不能自己编；要不要向后端要区间，等负责人定。

## 对设计稿的改法

| 屏 | 改前（v1） | 改后（v3，照 Uber / United 截图） |
|---|---|---|
| ① 已约好 | 竖向完整时间轴 | 不变 |
| ② 出发 | 无时间轴 | 照 Uber 等车页；抽屉顶部一行阶段胶囊，当前「汇合」 |
| ③ 匹配中 | 竖向时间轴 | 照 United 行程页：大字状态 + 阶段胶囊 + 信息卡 |
| ④ 已到达 | 无时间轴 | 同②，当前「汇合」 |
| ⑤ 陪跑中 | 竖向时间轴（全打勾） | 去掉；照 United 三格小卡放数据，照 Uber「分享行程状态」放安全 |
| ⑥ 已完成 | 竖向时间轴 + 甲乙待选 | 去掉；只留成果卡，即 11-07「只留绿色卡」，甲乙问题取消 |

## 没查到的

- 滴滴、Lyft 页面内等车时刻的截图（App Store 截图里没有）。Uber 只有等车页与行程中分享页两张，匹配中、行程中主屏没有。
- 补充（同日）：App Store 截图核对——Uber 等车页（第 1 张）抽屉里没有步骤列表，只有标题、步行分钟数、司机与车牌、留言条；United 行程页（第 2、3 张）用一条横向阶段胶囊标当前阶段。两者都支持「接送阶段不放竖向步骤」。
- 滴滴预约单详情页的官方界面描述。搜索只找到用户向科普和开放平台目录。
- 美团外卖订单页的进度条拆解。
- 打车 / 外卖类页面上读屏用户如何使用进度条的研究。

## 来源（2026-11-09 核实）

- Uber Engineering，*Pickup in 3 minutes: Uber's implementation of Live Activity on iOS*：https://www.uber.com/blog/live-activity-on-ios/（原文已读）
- Deliveroo Design，*Our order tracker — designing a product that crosses the physical and digital divide*（2019-05-02）：https://medium.com/deliveroo-design/our-order-tracker-designing-a-product-that-crosses-the-physical-and-digital-divide-7cc773d84245（原文已读）
- Just Eat Takeaway UX，*Redesigning our global order tracking experience*（2023-12-11）：https://medium.com/jetux/redesigning-our-global-order-tracking-experience-1f0fd7c91418（原文已读）
- Uber Newsroom，*Refreshing the Eats experience*（2019-04-10）：https://www.uber.com/newsroom/eatsredesign（原文已读；「五步」来自报道 https://mobilemarketingmagazine.com/uber-eats-enhances-order-tracking-as-part-of-redesign/ ，未逐字核）
- Apple HIG，*Live Activities* 与 *Progress indicators*：`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json`、`.../progress-indicators.json`（JSON 原文已读）
- App Store 官方截图：Uber（id 368677368，v3.746.10001）、United（id 449945214，v4.2.102），2026-11-09 抓取，取法见 `docs/ui/mockups/blind-order-tracking-20261109/REFERENCES.md`
- W3C WAI，*Multi-page Forms — Indicating progress*：https://www.w3.org/WAI/tutorials/forms/multi-page/（原文已读）
- Uber Reserve 说明页：https://www.uber.com/ae/en/ride/how-it-works/reserve/（搜索摘要，未逐字核）
