# 行程实时分享与志愿者激励：同类产品怎么做的

**核实日期**：2026-08-13（所有联网结论均为该日核实）
**调研问题**：① 「把行程实时分享给紧急联系人」这件事，同类产品的 UI 与架构是怎么做的？②「志愿者激励体系」的具体形态与已知陷阱是什么？③ iOS 侧把行程发给联系人有哪些平台约束？
**为什么开这一轮**：`INDEX.md` 里 `blind-app-feature-landscape-20260812.md` 覆盖了竞品**功能集**，但对这两项只有一句话结论（「滴滴无障碍勋章激励」「UIS 出发前四要素」），缺**机制层**——链接怎么生成、谁能看、什么时候失效、发送动作在哪一端。属于「有但缺你要的那一段」，按 §12 规则 2 只补这一段，未重跑功能全景。

> 本报告只做外部事实收集。落到 AidRun 自身的差距判断与实施决策在
> [`docs/review/blind-app-full-review-20260812.md`](../review/blind-app-full-review-20260812.md) 与后续 OpenSpec 变更。

---

## 1. 行程实时分享：Strava Beacon 是最贴近 AidRun 的一个

Beacon 面向的正是「一个人在户外跑步，家里人想知道他在哪」，与 AidRun 的场景同构。逐条机制：

| 机制 | Beacon 的做法 |
|---|---|
| 联系人数量 | 最多 **3 个** safety contacts，选一次长期保存，直到用户主动改 |
| 链接形态 | 每次活动生成一个**唯一 URL** |
| 谁能看 | 联系人在**手机浏览器**打开，**不需要 Strava 账号、不需要订阅** |
| 怎么送达 | App 生成一条**预填短信**，用户可先编辑，**由用户自己点发送** |
| 关键闸门 | **Beacon 开着 ≠ 联系人能看到**——不发那条短信，联系人什么也收不到 |
| 看到什么 | 当前位置、历史轨迹点、起点、录制状态、最后更新时间；展开还有开始时间、已活动时长、**剩余电量百分比** |
| 更新频率 | 约 **15 秒**一次，取决于蜂窝信号 |
| 失效 | **没有固定倒计时**，绑定在活动上：活动一结束，联系人就看不到当前位置了；活动保存上传后，链接页变成已完成活动页 |

**Uber Share My Trip** 的差异点（作为第二个样本）：最多 **5 人**；入口是行程中地图上的**盾牌图标**，只在行程进行中可用；收件人看到司机名字、车辆信息和实时地图；同样不需要装 App；用户可**随时手动停止**，一停所有已发出的链接立即失效。Uber 另有 **Trusted Contacts** 设置项：预存最多 5 人，App 会在行程开始时**提醒**用户去分享。

**两个样本的共同架构**（这是本轮最重要的一条）：

```
[App 内] 用户按「分享行程」
   → [服务端] 生成一次性 token + 公网可访问的只读页面 URL
   → [App 内] 把 URL 塞进预填短信，用户手动点发送     ← 这一段在客户端
   → [联系人] 浏览器打开，无账号只读
   → [服务端] 行程结束 / 用户手动停止 → token 失效
```

**分享链接必须由服务端生成、并由服务端托管一个不需要登录的只读页**。这一段客户端做不了——客户端没有公网可达的地址，也没法让一个没有账号的人来读订单数据。客户端能独立完成的只有「把一段文本交给系统短信」这一步。

**没有固定 TTL 是主流做法**：两家都把有效期绑在行程生命周期上，而不是「24 小时后过期」。Uber 额外提供了手动 kill 开关。

---

## 2. 志愿者激励：可抄的和会踩的

**分层的具体数字**（唯一一条直接可用的推荐）：按服务小时数分层 **25 / 50 / 100 / 250 / 500**，配合任期徽章、单场活动徽章与团队成就。命名沿用 bronze / silver / gold 这类既有认知。

**积分口径要透明可预测**——一个生产中的简单比例样例：每服务 1 小时得 1 分，3 分兑 1 美元。要点不是这个汇率，是「用户能自己算出来」。

**徽章 UI 的四条具体建议**：

1. **视觉差异本身承担留存作用**。新用户一眼看到全部层级，就知道路还很长；低层与高层的**美术质量差**制造牵引力——徽章得看起来值得挣。
2. **稀有度encode 在徽章本体上，不要藏在 tooltip 里**。Stack Overflow 用铜/银/金的颜色达成这一点。
3. **分组并解释**。按事件/学习/志愿/领导力分组，每个徽章说清怎么拿到、代表什么。
4. **进度要常驻可见**，放在个人主页；告诉志愿者「走了多远、还剩多远」。

**已知陷阱**（这段比上面更重要）：过度的积分追逐或排行榜竞争会**把动机从利他挪到游戏机制上**，志愿者开始挑「分高的任务」而不是有意义的任务。推荐的护栏：避免制造压力的竞争、避免让工作显得廉价、避免没有实质的表彰；排行榜要**可选择退出**。

**留存数据点（需谨慎引用）**：有来源称 Volunteer Canada 的合作方在 12 个月内把志愿者留存提升了 34%。这是厂商博客口径，无原始研究链接，**不足以作为决策依据**，仅作方向参考。

**本轮的调研缺口（诚实标注）**：「服务时长证明 / 证书」的生成 UI（PDF 版式、可验证凭证、LinkedIn「添加到档案」流程）**没搜到有价值的材料**。若要做证书，需要单独一轮，方向是 Open Badges 3.0 / verifiable credentials。

---

## 3. iOS 侧的平台约束（决定文案能怎么写）

用 `MFMessageComposeViewController` 把行程发给联系人，有四条硬约束：

1. **`.sent` 不等于送达**。delegate 回调 `didFinishWithResult:` 只有 sent / cancelled / failed 三种，`sent` **不保证消息真的到了收件人**。——这与 `AGENTS.md` §6 那条 SOS 红线是同一类问题：**UI 不得据此宣称联系人已经知道了**。
2. **预填只是建议**。用户可以在系统界面里改掉收件人和正文，改完之后内容不再由 App 掌控。
3. **必须先查能力**。呈现前调 `canSendText`，返回 false 就不要往下走——系统 composer **没有存草稿这一步**。设备后来具备发送能力时可观察 `MFMessageComposeViewControllerTextMessageAvailabilityDidChangeNotification`。
4. **收件人数量有实测上限**。有开发者报告 iOS 14.2 上约 10 个收件人就会出现收件人 chip 与输入框渲染错乱（iOS 12 时约 100 个）。多紧急联系人时要注意。

**无障碍边界**：系统 composer 是 **out-of-process** 的，App **无法**往里注入 `accessibilityLabel`、traits 或自定义转子——那棵无障碍树归 Apple。因此我们的无障碍工作只能落在自己这一侧：分享按钮的 label 与 hint（说清将要发出什么）、以及 composer 关闭后由 `didFinishWithResult:` 驱动的一次主动播报——**盲人用户看不到弹窗关闭，也看不到结果**，不播就等于没有反馈。

> ⚠️ 本轮**没有**找到 Apple 关于系统 composer 内 VoiceOver 行为的权威文档。上面这条是从「out-of-process 无法注入」这一事实推出的工程结论，不是 Apple 的明文要求。

---

## 4. 一句话结论

行程实时分享在 Strava Beacon 和 Uber 上是同一套架构——**服务端发 token 与免登录只读页，客户端只负责把链接塞进预填短信让用户手动发**，有效期绑行程生命周期而非固定 TTL，联系人上限 3–5 人；这意味着 AidRun 的实时分享**必须先有后端契约**，纯前端最多做到「静态行程告知短信」。志愿者激励可直接抄的是**按服务量分层 + 徽章视觉差 + 进度常驻可见**，必须避开的是排行榜竞争与不可选择退出；「服务时长证书」这一段没搜到可用材料。iOS 侧最硬的一条约束是 `MFMessageComposeViewController` 的 `.sent` **不保证送达**，UI 文案必须按「已交给系统短信」写，不能按「对方已知悉」写。

---

## 来源

均为 2026-08-13 核实。

- [Strava Beacon（Strava Help Center）](https://support.strava.com/hc/en-us/articles/224357527-Strava-Beacon) · [Strava Beacon for Garmin](https://support.strava.com/hc/en-us/articles/206470124-Strava-Beacon-for-Garmin) · [The Ultimate Guide to Strava Beacon（Strava Community Hub）](https://communityhub.strava.com/insider-journal-9/the-ultimate-guide-to-strava-beacon-1486)
- [Use Strava Beacon to share your live location while solo traveling（WhistleOut）](https://www.whistleout.com/CellPhones/Guides/use-strava-beacon-to-share-your-live-location-while-solo-traveling)
- [Riders — Share Your Trip Status（Uber）](https://www.uber.com/us/en/ride/how-it-works/share-status/) · [Sharing your trip status FAQ（Uber Help）](https://help.uber.com/en/riders/article/sharing-your-trip-status-faq?nodeId=e1f8ed2b-c0e5-4456-9c73-552cf11c5581) · [Share your ride status with friends（Uber Blog）](https://www.uber.com/pl/en/blog/share-your-ride/)
- [Add Gamification to Your Volunteer Recognition Program（VolunteerHub）](https://volunteerhub.com/blog/volunteer-gamification) · [Gamification Done Right（myTRS）](https://my-trs.com/blog/gamification-volunteer-engagement/) · [10 Examples of Badges Used in Gamification（Trophy）](https://trophy.so/blog/badges-feature-gamification-examples) · [What Is Gamification in Volunteering?（Ribi Volunteers）](https://www.ribi.org/what-is-gamification-in-volunteering/)
- [MFMessageComposeViewController（Apple Developer Documentation）](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller) · [MFMessageComposeViewControllerDelegate](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontrollerdelegate) · [Sending an SMS Message（Apple, 已归档）](https://developer.apple.com/library/ios/documentation/UserExperience/Conceptual/SystemMessaging_TopicsForIOS/Articles/SendinganSMSMessage.html)
- [MFMessageComposeViewController can't send TextMessage if multiple receipts（Apple Developer Forums）](https://developer.apple.com/forums/thread/670872)
