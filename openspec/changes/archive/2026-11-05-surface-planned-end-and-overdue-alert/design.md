# 设计

## D1. 为什么结束时间不能自己推

`OrderDetailResponse` 同时给了 `plannedEnd` 和 `expectedDurationMinutes`，看起来
`plannedStart + expectedDurationMinutes` 也能得到同一个数。**不行。**

`expectedDurationMinutes` 是用户在下单页选的档位（`BookingDurationOption`），
`plannedEnd` 是后端算并落库的约定。两者的口径不保证一致，而**后端所有的超时判定都用
`plannedEndTime`**：`plannedEnd + 15min` 发 `ORDER_OVERDUE`、`+60min` 自动完成。

自己推的后果不是「差几分钟」，是同一趟跑步在三个地方有三个结束时间（订单详情页一个、
家属分享页一个、告警触发时刻背后又一个），而没有任何一处会报错。
`PlannedEndAndOverdueTests.testPlannedEndComesFromTheBackendFieldNotFromDuration`
用一个两者明显对不上的订单（时长 30 分钟、`plannedEnd` 是 2 小时后）钉住这条。

缺失时**不显示这一行**，不另找一个数顶上。契约里它是 required，模型收成 optional 只是
解码宽容 —— 宽容的方向是「少一行」，不是「换一个来源」。

## D2. 放在哪：折叠区不够，必须进主播报

初版想法是往「预约信息」的 `DisclosureGroup` 里加一行就完事。那样等于没做：
读屏用户在跑步途中不会去展开一段标着「已确认的信息」的折叠区 —— 那一段的存在理由
恰恰是「下单时已经逐条确认过，服务中既不可改也无需再听」。

所以分三处，各自服务一条通道：

| 位置 | 服务谁 | 时机 |
|---|---|---|
| 状态卡首屏一行大字 | 低视力用户（看得到） | 仅 `IN_PROGRESS` |
| `blindRunnerAnnouncement` 主播报 | 读屏用户（「重复当前状态」按钮） | 仅 `IN_PROGRESS` |
| 「预约信息」折叠区一行 | 想主动核对的人 | 所有非空 |

**只在 `IN_PROGRESS` 进首屏与主播报。** 派单期、汇合期还没开始跑，念它没有用；
每多一句都是读屏用户在主路径上多等的时间。终态更不该摆一个「预计」。

状态卡的可见文字与朗读文本走**同一个函数** `plannedEndHeaderText`，不是两处各拼一遍 ——
`statusHeader` 是 `.accessibilityElement(children: .combine)` 且写死了 label，
两边分开写必然漂移，而漂移的那一侧（朗读）没人看得见。

拼接抽成独立函数而不是塞进 `Text(...)`：带可选拆包的字符串插值放在 view builder 里
会把 Swift 类型检查器拖到超时（`unable to type-check this expression in reasonable time`）。

## D3. 抬 `ORDER_OVERDUE` 的优先级：抬什么、抬不了什么

后端盲人侧模板给 `NORMAL`。`NORMAL` 在 `AppRealtimeCoordinator.enqueue` 里的后果是：
不抢占当前正在播的通知、排在队尾、蓝色铃铛、不带 `isHeader` trait。也就是说
「跑者可能失联」会排在派单进度那类通知后面。

后端 2026-08-13 的通报把这件事划成了我们的边界（原话：「播报文案和打断策略是你们的
设计边界，不自己改」），所以在客户端抬，不去改后端模板。

**只抬这一条。** 客户端把一堆通知都抬成 HIGH，等于把优先级这个机制作废 ——
真正的紧急事件（求助、走散）再也抢不到位置。`testNoOtherEventTypeIsElevated` 守这条。

⚠️ **抬的是展示，不是送达。** 后端只对模板 `priority == HIGH` 的通知补发 APNs
（`NotificationService.java:134`），判据是**模板值**不是客户端的展示值。所以：

- App 在前台 → WS 送到，客户端抬了优先级，横幅 + 抢占播报。✅
- App 不在前台 → **盲人侧根本收不到**（模板是 NORMAL，不补 APNs）。❌

第二行只能后端把模板提到 HIGH，已投 handoff。函数注释里写死了这句话，
避免下一个人看到「我们抬过了」就以为这一半也补上了。

补读路径（`ingestCatchUp`）走同一条规则：断线期间错过的 `ORDER_OVERDUE` 恰恰是最该被
听见的那条 —— 重连时它已经迟了，再排在派单进度后面就更迟。

## D4. 为什么不排本地通知

`UNUserNotificationCenter` 的**已排程**本地通知在 App 被用户强杀后仍会由系统投递，
所以「本地通知不可靠」这个说法对这个用法并不成立。不做的理由是另外三条：

1. **时间对不上。** 后端在 `plannedEnd + 15min` 告警。本地要么排在 `plannedEnd`（早 15 分钟，
   两条都会响、用户听到两次口径不同的话），要么复刻 `+15min` 这个后端配置项
   （`app.order.overdue-alert-minutes`）—— 复刻一个随时可能被后端改掉、而客户端收不到
   通知的常量，是把配置漂移做成静默缺陷。
2. **要记得撤销。** 订单提前结束、被取消、被重新匹配，都得撤掉已排的通知。
   漏一处就是「服务早就结束了，手机还是响了一句你的跑步超时了」。
3. **它盖住的是别人的缺口。** 盲人端收不到推送的真正原因是后端模板 priority，
   拿一条时间不对的本地通知去补，只会让那个缺口更难被发现。

要真正的兜底，正确的动作是后端改一行模板 —— 已投 handoff。

## D5. 什么都没做的那一条：本地时间推断

后端点名警告：自动完成的时间点从 `plannedEnd + 0min` 推后到了 `+60min`，
任何「过了 `plannedEndTime` 就本地当作已结束」的推断现在会和服务端差一小时
（收起进行中卡片、停止位置上报、停止 WS 订阅）。

核过全仓：`plannedEnd` 一处都没有与当前时间比较过。位置上报、WS 订阅、进行中卡片的收起
全部以服务端 `status` 为准。**所以这是一次确认，不是一次修复**，代码零改动。
写在这里是因为「查过了、没有」这个结论本身有价值 —— 下一次同类通报来时不必重查。
