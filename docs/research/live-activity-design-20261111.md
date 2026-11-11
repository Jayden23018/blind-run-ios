# 实时活动（锁屏卡 + 灵动岛）怎么排版、何时起收、读屏怎么做（#914）

核实日期 2026-11-11。前两份相关调研不重复：`ios-live-activity-lock-screen-20260916.md`（锁屏按钮发声、未认证不响应）、`live-activity-ended-style-and-push-token-20260926.md`（结束样式按 `isStale` 画、免费团队拿不到推送 token）。

## 结论

1. **好看的卡都是同一个版式**（8 张真实截图逐张看过）：左上不加底框的小标志 → 一行粗标题 → 一行副标题，右侧一个圆形头像，底部至多一个进度图形；只强调一个数字；卡高约 120–140pt，不顶满 160。我们 v1 稿在卡里列「当前一步 + 下一步」两行字，五层信息，被负责人否为「拥挤」。
2. **尺寸**（HIG）：393 宽屏幕锁屏卡与展开态 371 × 84–160pt，430 宽屏幕 408 × 84–160pt；紧凑态左右各 52.33 × 36.67（430 屏 62.33）；最小态 36.67–45 × 36.67；窄宽度（两个活动同时显示）要能缩进直径 28pt 的圆。锁屏标准边距 14pt。圆角不给数值，用 `ContainerRelativeShape`。超过 160pt 系统可能截断（ActivityKit 原文）。
3. **颜色**：灵动岛底色固定为黑，不能改；锁屏卡可以自定义底色。深色模式下灵动岛有一圈外框线（keyline），可着色，应与卡内主色一致。
4. **生命周期**：一张卡最多活跃 8 小时，到点系统结束并从灵动岛移除，锁屏再留至多 4 小时（合计 12 小时）。结束后默认 4 小时内清掉，可设更早；Apple 建议 15–30 分钟，打车例子是 30 分钟。iOS 17.2 起可由后端远程起卡（push-to-start），不需要 App 先开；广播推送不能起卡。
5. **更新与提醒**：只在内容真变时更新；只有需要人注意的更新才带提醒（亮屏 + 声音），且**别同时再发普通通知报同一件事**。推送有每小时预算，优先级 5 不计预算。
6. **互动**：建议一张卡只放一个可点元素，免得点错；CarPlay 上按钮失效。
7. **多个活动并存**：灵动岛最多显示 3 个最小态；用 `relevanceScore` 决定谁占主位，也决定锁屏排序。
8. **其他位置**：Mac 菜单栏、Apple Watch 智能叠放、CarPlay 会自动用紧凑态左右两块拼默认视图 ⇒ 紧凑态左右两块要能读成一句话。
9. **读屏**：Apple 要求每种形态都加 `accessibilityLabel`，状态变了标签同步变。盲人记者 2023 实测：VoiceOver 能读灵动岛，但**不会主动播报**；最小态的计时器读不出剩余时间。开发者论坛有人反映每次更新会重复朗读（未打开原帖，二手）。锁屏卡内的读屏顺序没找到官方说明。

## 设计上据此做的事（落在 `docs/ui/mockups/live-activity-v7-20261111/`）

- 卡片版式改为三层 + 右侧陪跑员 / 跑者姓氏圆章 + 底部 5 段条（= v7 五步）；有按钮的卡不放 5 段条。
- 灵动岛紧凑态左边是进度圆环（照 Flighty），右边一个数；最小态放圆环。
- 已完成锁屏留 30 分钟，第一段收卡留 15 分钟。
- 陪跑员出发 / 汇合卡的两个快捷按钮建议各砍成一个（待负责人定）。

## 真实产品版式（截图在本机，未入库：媒体文章配图有版权）

| 产品 | 锁屏 / 展开态版式 | 进度表示 | 出处 |
|---|---|---|---|
| Uber 等车 | 字标 → 「Pickup in 2 min」→ 车牌车型；右侧司机头像 + 车图 | 底部一条线，小车沿线走向终点 | macrumors.com/2023/02/22/uber-live-activities-support-worldwide/ ；engadget.com/uber-ride-tracker-iphone-lock-screen-060908235.html |
| Uber Eats | 字标 → 「Heading your way...」→ 预计送达时刻；右侧店铺圆图 | 底部 5 段分段条 | macrumors.com/2023/05/02/uber-eats-live-activities/ |
| DoorDash | 红色标 → 「Preparing your order」→ 送达时间区间；右侧商家圆 logo；底部整行「Track your order ›」 | 无 | 9to5mac.com/2023/12/04/doordash-live-activities-and-dynamic-island-order-tracking/ |
| 美团外卖（2023 测试版） | 店铺圆图 + 「预计 12:31–12:46 送达」（时间标黄）→ 进行状态；右上袋鼠标 | 底部一条槽，左店右家 | ithome.com/0/681/716.htm |
| 饿了么（宣传图） | 餐品图 + 「骑士已接单」→ 距离与时刻（数字标蓝） | 线 + 骑手图标沿线走 | ithome.com/0/651/014.htm |
| Flighty | 展开态：起降两端时刻（绿）+ 中间进度条；紧凑态：左环形图标、右倒计时 | 环形（紧凑）/ 线（展开） | 9to5mac.com/2022/10/24/flighty-dynamic-island-iphone-live-activities/ |
| United | 航班号 → 登机倒计时 → 起降两端；右上「ON TIME」胶囊 | 细线 + 两端节点 | macrumors.com/2023/05/25/united-airlines-live-activities/ |
| Gentler Streak（跑步） | 展开态：用时 → 心率 / 配速 / 距离三个大数字 | 心率区间条 | 9to5mac.com/2023/01/19/gentler-streak-live-activities/ |

Strava 帮助页：实时活动只显示用时、距离、配速，点卡片回 App（support.strava.com/en-us/articles/15401559）。

## 官方来源

- HIG Live Activities：developer.apple.com/design/human-interface-guidelines/live-activities（JSON：`developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json`，页面 2026-10-13 更新）
- ActivityKit：`.../tutorials/data/documentation/activitykit/displaying-live-data-with-live-activities.json`、`.../starting-and-updating-live-activities-with-activitykit-push-notifications.json`、`.../activitykit/activity/pushtostarttoken.json`、`.../activitykit/adding-accessible-descriptions-to-widgets-and-live-activities.json`
- 读屏实测：sixcolors.com/member/2023/02/checking-in-on-the-accessibility-of-the-dynamic-island/

## 没查到

滴滴、Nike Run Club、Apple 自带计时器 / 地图的实时活动截图；外卖与打车 App 的灵动岛紧凑态截图；锁屏卡读屏顺序的官方说明；盲人 / 低视力用户使用实时活动的研究；HIG 圆角数值；频繁更新的 Info.plist 键名与每小时预算数字。截图多为 2022–2023 版本，现行样式可能已变。
