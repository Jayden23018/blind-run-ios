# 志愿者端「我」首屏：Strava 式个人页 + 志愿影响力面板的可抄部分

**核实日期**：2026-09-14（所有联网结论均为该日核实）

**调研问题**：把志愿者首屏从「地图 + 派单面板」改成「个人身份 / 影响力」优先时，
①Strava 的 profile / 统计 / 奖杯柜 / 活动流各自的版式怎么组织？②志愿者类产品的影响力面板长什么样？
③底部「滑动开始」这类 sliding button 有没有权威规格与禁用条件？

**为什么开这一轮**：`volunteer-home-incentive-layer-20260914.md` 覆盖了**激励层在现有版式里放哪一档**
（滴滴车主端三档卡片、Uber 顶部 chrome、三条反面做法），它的复核触发条件里逐字写着
「本仓库志愿者端首页改掉『地图铺满 + 底部面板』这个叠层结构」—— 本轮正是那个触发。
上一轮**没有**覆盖：个人页的信息层级、统计排版、奖杯柜、活动流、以及 sliding button 的规格。
按 §12 规则 2 只补这一段，机制层（motivation crowding、不得折算金额、一屏一主指标）直接沿用未重跑。

> 本报告只做外部事实收集。落到 AidRun 的设计决策见同分支的设计稿与 PR。

---

## 1. 视觉参考板：本轮实际看过的 15 组界面

⚠️ **全部是真实上架产品的截图或厂商自published 的产品图**，无 Dribbble 稿、无 AI 生成图。
「看过」= 在浏览器里渲染出来逐张看，不是读文字描述。

### 1.1 Strava（真实上架，Google Play 商店页 2026-09-14 抓取）

| # | 界面 | 该抄的一件事 |
|---|---|---|
| S1 | **You → Progress**（`Total Distance / 384.6 mi ↑12% / 292.1 mi`） | 小灰标签在**上**、巨大数字在**下**；本期 vs 上期并置 + 涨跌 chip；底部一张「Your progress at a glance」解读卡 |
| S2 | 成绩分享图（`Distance 14.7 mi / Elev Gain 512 ft / Time 1h 30m`） | 三个指标纵向堆叠，标签极小、数值极大 —— 「大数字 + 极短标签」的纯粹形态 |
| S3 | Record / 运动选择 | 主操作页与个人页完全分离，个人页不承担开始动作 |
| S4 | 活动详情（地图 + 统计） | 地图**不在**个人首屏，只在单次活动详情里 |
| S5 | 底部 5 tab（Home / Maps / Record / Groups / **You**） | 个人页是一个**平级 tab**，不是设置里的二级页 |

### 1.2 Strava 帮助中心（官方，版式仍在用，图为 2018–2022 版）

| # | 界面 | 该抄的一件事 |
|---|---|---|
| S6 | Profile 日历挂件（`Last 4 Weeks / 27 / Total Activities`） | 「区间限定词 + 巨大数字 + 小标签」三行结构 |
| S7 | **Trophy Case** | 4 列一排的徽章网格，每枚下面**三行**：名称 / 日期 / 该次成绩；页面顶部用 tab 切 Overview / Trophy Case / Following |
| S8 | Overview 里的 Trophies 行 + `View more` | 首屏只放一排，其余进二级页 —— 徽章不铺满首屏 |

### 1.3 Nike Run Club（真实上架，Google Play）

| # | 界面 | 该抄的一件事 |
|---|---|---|
| N1 | Activity（`20.6` 巨大 + 下方 `5'14" / 1:48:04` 小行 + 柱状图） | 一个主数字 + 一排次级数字，**主次用字号差而不是用卡片框**拉开 |
| N2 | `300 MILES / CONGRATS!` | 里程碑达成是**一张单独的庆祝卡**，不是首屏常驻 |

### 1.4 志愿者类产品

| # | 来源 | 该抄 / 该避开的一件事 |
|---|---|---|
| V1 | **HelpUnity** Profile（`Anuj Jadhav` / `Volunteered: 55 hrs` / `🥇 50-Hour Badge` / Followers·Following / 6 条设置行） | 🔴 **反面参考**：身份 + 一行小字时长 + 一枚文字徽章，随即塌成设置列表 —— 正是用户这次要求避开的「无聊账号页」。影响力用 13px 蓝字承载，视觉权重比下面的「Account Settings」还低 |
| V2 | HelpUnity Explore / 筛选 | 机会发现是**另一个 tab**，不挤进个人页 |
| V3 | **Rosterfy** 志愿者 App 官方产品图（Find Opportunities / Onboarding / Communications） | 官方口径是 "discover opportunities, manage shifts, and **track their impact**" —— impact 与 discover 并列为一等能力；但公开图里**没有**影响力面板本身 |
| V4–V8 | **Lasagna Love**（Yeti 案例研究 5 张：Get ready to spread kindness / Donate to help / Sign-up / Communication preferences / Food safety onboarding） | 可抄的是**语气与色彩**：奶油底 + 暖橙、真人照片、手写感标题、零企业感。⚠️ 公开图**全是 onboarding**，没有任务历史页 —— 用户给它派的「task history」用途在公开材料里查不到 |
| V9 | **Be My Eyes**（真实上架，4 张） | 同领域（视障）产品的主操作是一枚巨大的 `Call a volunteer`，个人统计完全不在首屏 |

### 1.5 中文跑步产品（仓库既有 `docs/ui/reference-screenshots/run-tracking/`）

| # | 来源 | 该抄的一件事 |
|---|---|---|
| C1 | **悦跑圈** 路段页（`10.44 km 路段全长 / 71 m 累计爬升 / 70 m 累计下降`，下面第二排三个） | 中文跑步产品的统计网格是**数值在上、小标签在下**，与 Strava 的标签在上**方向相反**。中文语境按这条走 |
| C2 | 咕咚 赛事页 / Keep 课程页 | 中文运动 App 的分区标题是小号灰字 + 右侧「更多 ›」，与 Strava `View more` 同构 |

### 1.6 交互规格（文字，非截图）

| # | 来源 | 内容 |
|---|---|---|
| U1 | **Uber Base Design System — Sliding button**（官方设计系统，原文见 §3） | 唯一拿到的 sliding button 权威规格：用途判据、两档阈值的具体百分比、无障碍告警、颜色与尺寸的 do/don't |

---

## 2. 反复出现的 8 条版式模式

按「在几个参考里同时出现」排序，前 6 条是本轮真正值得复用的：

1. **一个主数字压全场**（S2 / S6 / N1 / U-Uber 顶部 chrome）——
   主指标与次级指标的差距靠**字号**（约 3×）拉开，不是靠卡片边框。
2. **统计网格 3 列、数值大标签小**（S2 / C1 / 本仓库 `run-track-replay-20260812` 已有结论）。
   ⚠️ 与 `claude-code-setup-for-ios-a11y-20260902` 记的「三列网格是 AI 界面指纹」不冲突 ——
   上一轮已判过：用在**同质的统计数字**上是对的，用在关系 / 进度 / 状态上才是那枚指纹。
3. **紧凑身份行，不做居中大头像**（S1 顶部 `‹ You  Progress  ⓘ`）——
   身份占一行就够，省下的高度全给影响力。V1 的居中大头像是反例。
4. **徽章 = 首屏一排 + 「全部 ›」**（S7 / S8）。每枚徽章带**名称与达成时的数值**，不是光一个图标。
5. **活动流是日期 + 一行主语 + 一行副信息**（S4 / C2），行高压得很紧，靠分隔线不靠卡片。
6. **主操作与个人页分离**（S3 / S5 / V2 / V9）——
   个人页负责「我是谁、我做过什么」，「现在去做」是另一个模式的入口。
7. 里程碑用**一次性庆祝卡**而非常驻区块（N2）—— 与上一轮滴滴「成就感是事件节点」结论同向。
8. 本期 vs 上期并置 + 涨跌 chip（S1）—— **本轮判定不可用**，见 §4.2。

---

## 3. Uber Base「Sliding button」原文规格（本轮唯一权威交互依据）

以下为 <https://base.uber.com/6d2425e9f/p/3800ec-sliding-button/b/46994b> 原文逐字摘录：

> "Sliding buttons are a variation of our known and loved primary rectangular buttons.
> Leveraging a different gesture to confirm an action, they help reduce accidental actions
> and reinforce intent."

**用途判据**：

> "Use sliding buttons to let users take important actions. They should be used as the last step
> in a multi-step flow (like requesting or completing a trip) or to introduce friction to confirm
> a user's intent and prevent button mashing (like calling 911)."

🚩 **同页的 Caution 是本轮最该记住的一句**：

> "If the action is not critical, a sliding button may be unnecessary and may add unnecessary
> complexity to the interface."

**阈值两档**（原文表格）：

| Threshold | Value |
|---|---|
| Low (Easy) | "Complete more than 20%" |
| High (Hard) | "Complete more than 80%" |

**无障碍告警**（原文）：

> "Demanding a high degree of interaction precision to complete an action proves difficult to users
> with physical and motor disabilities, as well as seniors. When choosing which threshold to use,
> think about who your users are and whether they'd find it difficult to interact with the component
> in the 'Hard' slide mode."

**其余硬规则**：

- 图标只允许单个箭头：> "The component does not support any other icons."
- 仅限移动端：> "We discourage using sliding buttons in a desktop environment."
- 颜色：> "Distinguish the swipe affordance from the surrounding UI by using a primary, high-contrast
  background." / 反面：> "Do not inverse the button styles or use secondary styling on the swipe affordance."
- 尺寸：> "Keep the sliding button height and the base button height the same." /
  > "Avoid resizing elements inside the button, like the icon or sliding button affordance."

**配套无障碍事实**（Apple Developer Forums 线程 729098）：VoiceOver / Switch Control / Voice Control
会彻底改变用户的物理交互方式，很多人根本不触碰屏幕 ⇒ 滑动控件必须同时提供一个可被辅助技术激活的
标准 action，不能只有裸拖拽手势。

---

## 4. 三条「查到了但判定不能用」

留档理由同 §12：被否掉的方案和选中的一样值钱。

### 4.1 累计里程 / 「陪伴总距离」—— 后端**刻意**没有，不是漏了

后端 `docs/api_spec.yaml` 的 `VolunteerAchievementsResponse` 描述原文：

> 志愿者成就页数据。**刻意没有**：累计里程（要先在订单上落完成时的统计快照，
> 否则跨订单求和会把 OOM 风险搬进成就页）、积分/兑换（运营决策）、
> 勋章解锁时间（库里没有痕迹，宁可不给也不编）。

⇒ Strava 式「86 km 陪伴距离」这一格**做不出来**，且不该提需求让后端加（理由后端已写明）。
单次订单的 `TrackStats.distanceMeters` 存在（`blindRun/Core/Models/OrderTrackModels.swift:17`），
但那是**单单粒度**，只在完成后的轨迹摘要页可用，跨订单求和正是后端拒绝的那件事。

### 4.2 「本月 8/10 次」式月度目标 —— 撞上一轮已立的红线

上一轮 `volunteer-home-incentive-layer-20260914.md` §3.2 的三条硬规则里有两条正面挡住它：
「激励层不得有倒计时、不得有会变的门槛」「首页不得出现『还差 1 单就…』这类压力句式」。
月度目标是典型的 Moving Target（印度 CCPA dark pattern 分类法点名项）。
S1 的「本期 vs 上期 ↑12%」同理 —— 它把**自己的上个月**变成要超越的门槛。

可用的替代物是**外部固定门槛**：后端已有 `VolunteerStarLevelDto`
（`blindRun/Volunteer/VolunteerAchievements.swift:172-178`，`current` / `currentHours` / `nextTarget`），
国标星级的小时门槛由标准定、不由我们定、也不随用户表现漂移。

### 4.3 服务时长折算金额 —— 上一轮已否，本轮在 Rosterfy 同类材料里再次出现，维持否

依据不变：网信办 2026-06-19 通知第 2 条 + `VolunteerPointsCopy.disclaimer`。

另**新增一条同源约束**（本轮从后端 spec 读到，此前未归档）：`/api/volunteer/achievements` 的
description 原文 ——

> ⚠️ **这不是「志愿服务时长证明」。**（民政部令第 67 号）……
> **客户端展示时不要用「证明」「证书」这类措辞**。

⇒ 首屏出现「服务证明 / 时长证书」字样即违规，星级与时长只能作为**展示**。

---

## 5. 参考源可用性订正

- 🔴 **`uxarchive.com` 本轮打不开**：Cloudflare `Error 1000 DNS points to prohibited IP`
  （2026-09-14 14:24 UTC 实测）。上一轮 `volunteer-home-incentive-layer-20260914.md` §4.1
  把它列为「免费」且「能跨版本对比」，该行需标注暂不可用。
- 🔴 **`apps.apple.com` 在本会话的浏览器策略下被拒**（`navigation denied`）⇒
  iOS 商店截图这条路本轮走不通。**替代路径已验证可用**：`play.google.com/store/apps/details?id=…`
  正常返回，截图 CDN 为 `play-lh.googleusercontent.com`，把尾巴的 `=w526-h296-rw` 换成 `=w360`
  可取到完整竖版原图（`=w900` 实测取不到，会返回空）。同一 App 的商店截图两端通常同一批素材。
- `base.uber.com` 是 zeroheight SPA，**`WebFetch` 只能拿到一个标题**；要原文必须用浏览器打开
  并点进 `Usage` 子页（URL 尾段 `/b/46994b`）再取页面文本。

---

## 6. 一句话结论

Strava 个人页可抄的是**结构**不是外观：紧凑身份行 → 一个 3× 于其他数字的主指标 → 3 列同质统计网格
→ 一排徽章加「全部 ›」→ 紧凑活动流，而**主操作不在个人页上**（Strava 的 Record 是独立 tab）。
中文跑步产品（悦跑圈）的统计网格是**数值在上标签在下**，与 Strava 相反，中文语境按中文的来。
志愿者类产品这边**没有可抄的影响力面板** —— HelpUnity 的 Profile 是反面教材（影响力用 13px 蓝字，
权重低于设置行），Rosterfy 把 "track their impact" 写进官方文案却没公开该界面，
Lasagna Love 公开图全是 onboarding，只能取其暖色人本语气。
底部滑动 CTA 有权威规格（Uber Base）：阈值 Low=20% / High=80%，
且官方 Caution 逐字提醒**动作不关键时用滑动只是徒增复杂度** —— 所以滑动必须绑在一个**真有后果**
的动作上才立得住。三条查到但不能用：累计里程（后端 spec 逐字写明「刻意没有」）、
月度目标与同比涨跌（撞 Moving Target 红线）、时长折算金额（网信办通知 + 民政部令 67 号，
且后端明令不得用「证明/证书」措辞）。`uxarchive.com` 已挂，`apps.apple.com` 被策略拒，
改用 Google Play 商店页取真实截图。

---

## 来源

均为 2026-09-14 核实。

- [Your Strava Profile Page（Strava 官方帮助中心）](https://support.strava.com/en-us/articles/15402175-your-strava-profile-page)
- [The Strava Trophy Case（Strava 官方帮助中心）](https://support.strava.com/en-us/articles/15402068-the-strava-trophy-case)
- [Strava: Run, Bike, Walk（Google Play 商店页，真实上架截图）](https://play.google.com/store/apps/details?id=com.strava)
- [Nike Run Club（Google Play 商店页）](https://play.google.com/store/apps/details?id=com.nike.plusgps)
- [Be My Eyes（Google Play 商店页）](https://play.google.com/store/apps/details?id=com.bemyeyes.bemyeyes)
- [Strava beta tests new app layout — You tab puts all your stats in one place（BikeRadar）](https://www.bikeradar.com/news/strava-beta-test-layout)
- [Volunteer App for Organisations（Rosterfy 官方）](https://www.rosterfy.com/platform/volunteer-app/)
- [Expanding the Reach of Kindness — Lasagna Love（Yeti 案例研究）](https://www.yeti.co/work/lasagna-love)
- [HelpUnity 官网（含 6 张 App 截图）](https://www.help-unity.com/)
- [Sliding button — Base design system（Uber 官方，Usage 子页）](https://base.uber.com/6d2425e9f/p/3800ec-sliding-button/b/46994b)
- [Swipe to confirm and accessibility（Apple Developer Forums thread 729098）](https://developer.apple.com/forums/thread/729098)
- 后端契约 `/Users/mac/Downloads/demo/docs/api_spec.yaml` — `VolunteerAchievementsResponse`
  与 `/api/volunteer/achievements` 的 description（本仓库外部源真相，见 `AGENTS.md` §7）
- 仓库既有参考图 `docs/ui/reference-screenshots/run-tracking/{strava,nike-run-club,joyrun-yuepaoquan,codoon-gudong,keep}/`
