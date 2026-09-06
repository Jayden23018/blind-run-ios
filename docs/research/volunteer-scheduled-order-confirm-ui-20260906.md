# 服务提供方端「已接的远期预约单」怎么设计：入口在哪、临期确认怎么做

**日期**：2026-09-06
**触发**：后端迁移 `0041` 上线跨天预约（`SCHEDULED_CONFIRMED` + `POST /api/orders/{id}/confirm-departure`
+ `SCHEDULED_DEPARTURE_CONFIRM_REQUIRED`）。后端逐字警告：「收到那条通知却没有确认入口 ⇒ 志愿者会在
60 分钟后被判未确认、这一单自动转给别人，**而他并没有拒绝过**」。要决定 iOS 志愿者端把这个入口放哪。

**通道**：内置 `WebSearch`（4 次）。**全部是小模型转述，本轮没有抓任何原文** ——
按 `web-research-toolchain-20260813` 的判据，本题产出物是「怎么设计」的结论而不是要引用的原话与数字，
转述够用。⚠️ 因此本文所有引号内的英文短语是搜索结果里的转述用词，**不得当作厂商原文引用**。

---

## 一句话结论

打车业两家（Uber / Lyft）**根本没有「确认」这个动作** —— 他们的闸门是「按时上线」，
而我们的无偿志愿者没有「上线抢单」这个持续状态，**这条抄不了**。真正对口的先例在
**志愿者排班软件**：`confirm-or-release`（一次点击，要么确认要么释放名额），
且确认与释放**并置**。入口一律**独立于「当前进行中」的位**，三家（Uber / Lyft / Rover）无一例外。

---

## 一、对标：四类产品各怎么做

| 产品 | 远期单的入口 | 临期动作 | 对我们的可用性 |
|---|---|---|---|
| Uber Driver（Reserve） | Menu → **Opportunities Center**，与当前行程分开；可见未来一周 | **无确认按钮**。闸门是 pickup 前 30 分钟（经济型）/ 45 分钟（高端）必须在线，否则可能丢单；不遵守政策会收到 in-app 提醒，累计 3 次失去 Reserve 资格 | ⛔ 闸门抄不了，✅ 入口位置可抄 |
| Lyft Driver | 头像 → **Scheduled pickups** tab，卡片显示日期/大致地点/预估收入，点 View Details → **Confirm Pickup**（这是**抢单**不是临期确认） | 同样无临期确认：提前 30 分钟上线、pickup 前 ≥15 分钟收到派单再 accept；不在线就转给别人 | ⛔ 同上，✅ 入口位置可抄 |
| Rover（sitter） | Inbox → **Upcoming** → Details | 改期走三点溢出菜单 → Modify booking；**接受修改发生在会话线程里而不是详情页** | ⚠️ **反面教材**：搜索结果直接把它点成 "a notable context switch" |
| 志愿者排班软件（VolunteerHub / Communal / Volunteer Matrix / ZoomShift） | 排班列表 | **confirm-or-release**：提前 1–3 天一条提醒，带**单击确认或释放**；系统记录谁确认了、谁没有 | ✅ 最对口 |

## 二、能直接用的三条

1. **确认与「去不了」必须并置成一对**，不是主按钮 + 角落里的取消。
   来源是志愿者排班那类产品的 `confirm-or-release`。理由在搜索结果里被讲得很清楚：
   易取消**是特性不是漏洞**（"volunteers who can cancel easily come back"），
   而把释放做得难只会把 no-show 从「提前告知」变成「当天失联」。
   我们已经有志愿者取消（→ `REMATCHING`），正好凑成这一对。

2. **远期单必须有独立于「当前订单」的位。** 三家全都这么做，没有一家把预约单塞进
   「进行中」那个 slot。对我们尤其硬：`activeVolunteerOrder` 按 `createdAt` 降序取第一个
   （`VolunteerHomeView.swift:113-118`），新接的即时单 `createdAt` 总是更晚 ⇒
   共用一个 slot 时跨天单会被顶掉，而 60 分钟的闸门不会因为他在忙就暂停。

3. **确认动作不进溢出菜单、不进另一个页面。** Rover 的做法被搜索结果点名批评。
   我们把两个按钮直接摆在预约卡上。

## 三、被否决的方案（留着，比结论更容易被忘）

- ⛔ **抄 Uber/Lyft 的「靠在线状态代替确认」**。他们的司机有「上线抢单」这一持续状态，
  丢单对全职司机是收入损失、有自然的注意力。我们的志愿者是无偿的，`isAvailable` 的语义是
  「愿不愿意收派单」而不是「此刻在岗」，拿它当闸门等于让所有关掉接单开关的人自动丢掉已答应的预约。
- ⛔ **客户端算 T-120 分钟才显示确认按钮**。120 是后端配置 `app.order.departure-confirm-window-minutes`。
  客户端写死就是第二个源：后端调大它 ⇒ 通知到了、按钮还没出现 ⇒ 正是后端标 🚨 的那条灾难。
  同一条理由已经写在 `KeepWaitingCopy`（不许出现具体时长）上。
- ⛔ **收到 `SCHEDULED_DEPARTURE_CONFIRM_REQUIRED` 才显示按钮**。`WSAppNotification` **不带 `orderId`**
  （`WebSocketModels.swift:74-83`），且 App 被杀过就没了。拿一条易失推送当唯一 UI 前提，
  等于把那条灾难换个形式保留。
- ⛔ **全屏拦截式确认 sheet**。同类产品无一如此；推送不到时完全失效；且会抢占正在进行的服务界面。

## 四、不可引用的数字

搜索结果里出现「提前 24–48 小时提醒可降低 no-show 30–40%」。**不要引用**：
搜索结果自己标注了它是 vendor-published 且 uncited（"treat this figure cautiously"）。
本仓库没有自己的基线数据，也不该拿它写进任何对外材料。

## 五、本轮没查到的

- **中文语境的同类产品**（滴滴司机端预约单、顺风车主端行程确认）在英文搜索里没有可用结果。
  `blind-app-feature-landscape-20260812` §滴滴那节覆盖的是三节点提醒，不是预约单确认。
  真要补，得走中文搜索或直接看 App，本轮没做。
- **Wag（遛狗员侧）**的 booking details 页：搜索返回的全是 Rover 文档，唯一的设计站结果是无关内容。

---

## 来源

- [Uber Help — Reserve FAQ（司机侧）](https://help.uber.com/en/driving-and-delivering/article/reserve-faq?nodeId=edd655fe-d600-44bf-97cf-e917fbd6cc72)
- [Lyft Help — Scheduled pickups for drivers](https://help.lyft.com/hc/en-us/all/articles/115012924387-Scheduled-pickups-for-drivers)
- [Rover Help — How do I modify a booked service?](https://support.rover.com/hc/en-us/articles/115005120443-How-do-I-modify-a-booked-service)
- [VolunteerHub — When volunteers don't show up](https://volunteerhub.com/blog/when-volunteers-dont-show-up-the-real-cost-of-short-staffed-shifts)
- [Communal — Volunteer scheduling software guide](https://getcommunal.com/guides/volunteers/volunteer-scheduling-software)
- [Volunteer Matrix — Volunteer scheduling](https://volunteermatrix.com/product/volunteer-scheduling)
- [ZoomShift — Volunteer scheduling](https://www.zoomshift.com/volunteer)

⚠️ 全部经 `WebSearch` 转述获得，**未抓原文**。要引用其中任何一句话之前先自己打开核对
（`url-check-false-flags-trailing-paren`：结尾带 `)` 的链接不要用正则截，直接整条打开）。
