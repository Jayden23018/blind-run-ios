# 等待中的进度提示：别家用浮层还是写在页面里（2026-11-11，#949）

## 问题

盲人下单后，后端推 `DISPATCH_STARTED` 和 `DISPATCH_EXPANDING`（「正在为您扩大搜索范围（第N轮）」）。
App 以前把它们放进顶部浮层队列。附近没人时三条几乎同时到，浮层挡住订单页，点「关闭」又冒出下一条。
要回答：成熟产品怎么呈现**等待期间、不需要用户操作的进度更新**（不是最终结果）？

本次只补 `matching-wait-screen-20261111.md` 没覆盖的一段。那份已定：长等待不放循环动画，结果靠通知。

## 结论

没有查到任何一手来源支持「顶部浮层播等待中的进度」。来源一致指向：进度写进页面里的一行，原位替换；读屏用一条不抢话的播报。

| 来源 | 说了什么 | 对我们 |
|---|---|---|
| Apple HIG《Notifications》 | 前台时不弹通知，要「discoverable but not distracting」，例如把新数据加进当前视图；同一件事不要多发 | 进度写进订单页 ① 那一行 |
| Apple HIG《Alerts》 | 只有信息、用户没有可做的事，不用 alert，改用情境内的轻量提示 | 不用浮层 |
| Material Components Android《Snackbar》 | 同一时刻只显示一个，新的先关掉旧的，不排队 | 原位替换，不排队 |
| Atlassian Flag | 自动消失的 flag 不能放关键信息；多条会堆叠 | 进度不靠计时消失 |
| W3C WCAG 2.2 SC 4.1.3 | 进度、等待属于状态消息，辅助技术要读得到，但不抢焦点；不重要的内容用 alert 算失败 | 念一次，不抢焦点 |
| WWDC23 10036 | `AccessibilityNotification.Announcement` 有三档优先级；低档排队、有新的就丢掉旧的 | 一连串只念最后一条 |

## 来源（2026-11-11 核实）

- https://developer.apple.com/tutorials/data/design/human-interface-guidelines/notifications.json
- https://developer.apple.com/tutorials/data/design/human-interface-guidelines/alerts.json
- https://raw.githubusercontent.com/material-components/material-components-android/master/docs/components/Snackbar.md
- https://atlassian.design/components/flag/usage
- https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html
- https://developer.apple.com/videos/play/wwdc2023/10036/

## 没查到

- Uber、Lyft、滴滴、美团、高德打车「找司机 / 扩大范围」那一页的官方截图和措辞。没有下载到任何真机截图。
- Apple 系统胶囊提示（AirPods 连接、静音）的尺寸和时长，没有一手来源。
- 一手来源里没有「几条同时到该怎么合并」的规范。「只念最后一条」是从 Snackbar 和 WWDC23 低档优先级推出来的。

## 采纳（负责人 2026-11-11）

1. 派单进度不弹浮层，写进订单页 ①「已等 N 分钟」那一行：「正在扩大范围找 · 已等 3 分钟」。
2. 不说「第 N 轮」。
3. 读屏只念一连串里的最后一条（静下来 1 秒再念）。
4. 后端把瞬时连发合成一条、信封带 `orderId`，另开后端 issue。

被否：保留浮层但缩成小胶囊（仍会短暂挡住顶部）；整个不显示（盲人在等待期没有任何声音反馈）。
