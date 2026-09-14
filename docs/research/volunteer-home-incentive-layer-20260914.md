# 服务提供方主屏的「激励层」怎么摆：结构、反面做法、参考源

**核实日期**：2026-09-14（所有联网结论均为该日核实）

**调研问题**：志愿者端主屏（地图 + 底部面板 + 卡片流）要加一层激励展示。①同形产品把激励层
放在这个版式的哪个位置、什么视觉权重？②有哪些已被点名的反面做法？③后续改界面时，
去哪些站点找参考图？

**为什么开这一轮**：`INDEX.md` 里 `live-trip-sharing-and-volunteer-incentives-20260813.md` §2
覆盖了激励的**机制层**（分层阈值、徽章视觉差、进度常驻可见、避开排行榜），
`incentive-ui-blind-first-20260823.md` 覆盖了**播报层**（邀请码逐字念、零加分流水怎么解释）。
两者都没有回答**屏幕层**：这块东西在首页放第几个位置、和派单任务卡是什么关系、
视觉上能有多重。属「有但缺你要的那一段」，按 §12 规则 2 只补这一段，未重跑机制层。

> 本报告只做外部事实收集。落到 AidRun 的实现决策在
> `docs/ui/ui-review-checklist.md` 与对应 PR。

---

## 1. 结构原型：滴滴车主端 5.0 —— 同形，且解决的是同一个问题

这是本轮唯一一个**版式与我们同形**的公开设计复盘（全屏地图 + 底部任务面板 + 卡片流），
且它面对的问题和我们一样：信息来源多、类别杂，全盘呈现会导致信息超载。

它的做法是**按重要度把全部信息压进三种卡片**：

| 档 | 定义（原文口径） |
|---|---|
| 模态任务卡片 | 最高优且**不可跳过**，要求车主完成当下任务后才能继续其他操作 |
| 非模态任务卡片 | 高优但不紧急，需要第一时间注意到，但**可在当下跳过** |
| 普通信息卡片 | 非高优且不紧急，**用户关注时可见** |

三个设计关键词：**简单、高效、成就感**。成就感的来源被明确定位为
「任务完成、收入进账、得到奖励等贯穿全流程的**节点**细节设计」——
也就是说，激励不是一个常驻的大区块，是**事件发生那一刻**的表达。

另一条可直接用的：行车场景下「听」是车主浏览信息的惯用交互，
做首页卡片时要考虑**语音播报的可降级表达**。这与我们盲人端的要求同向，
但它是为**开车的人**提的 —— 说明「卡片要能被念出来」不是无障碍特供需求。

⚠️ **能抄的只有结构，不是像素**：文中唯一公布的具体数值是「字号基于 4 的整数倍进行推导」，
圆角、卡片间距、具体字号、首页布局坐标**一概没有**。谁要引用它写死一个数值都是编的。

### 映射到 AidRun

我们三档其实已经齐了，只是没人这么命名过：

| 档 | AidRun 对应 |
|---|---|
| 模态 | `VolunteerDispatchOverlay`（派单弹窗，带倒计时） |
| 非模态 | `VolunteerScheduledOrdersSection`（我的预约，带临期确认按钮） |
| 普通信息 | 派单状态卡、近期服务 —— **激励层属于这一档** |

⇒ **激励层不许升到前两档**：不做全屏、不做倒计时、不做「必须处理完才能继续」。

---

## 2. Uber Driver：最能激励的那个数在顶部状态栏，不在卡片里

公开可见的 4 张 iOS 截图（AppShots，未登录可见的全部）显示司机端首页是：

- 全屏地图（深色）
- **顶部中间一枚药丸，里面是累计收入**（实测两张分别是 `$8.31` 和 `$100.77`）
- 左上角汉堡菜单、右上角搜索
- 底部中间 `GO` 圆形主按钮

即：**单个最强激励数字被提到了全局常驻的顶部 chrome 里**，而不是做成一张卡。

真正的激励**卡片流**在另一处 —— Uber 官方工程博客描述的 Real-time Earnings Tracker
是一套卡片架构，分 Status / Browse / Bulletin 三种 mode，卡片种类包括
last trip、daily summary、consecutive trips progress、**Quest progress**、
new driver guarantees progress、loyalty progress，以及各自的 error state。
后来 Uber Pro 也被并进这个 tracker「to celebrate driver accomplishments」。

另一条实测：未登录状态下 AppShots 只放出 4 张图，其余要登录 ——
把它当参考源时别指望能白嫖整套流程。

---

## 3. 🔴 必须点名拒绝的反面做法（本轮最重要的一节）

### 3.1 「下线挽留」

Uber 在司机点击停止接单时，弹出当日收入目标劝其继续，并把「继续开」做成更易选的那个。
它利用的是人天然的 income targeting（给自己定当日收入目标）倾向。
《纽约时报》把这套归入 Uber 的「psychological tricks / video game-like motivational tools」。

⚠️ **这条在业界是有争议而非定论**：也有评论者认为灰掉的选项仍然清晰可见、
点击热区一样大，属于常规游戏化，「neither good nor bad」。

印度 CCPA 对 dark pattern 的定义（被一份 gig 平台设计分类法采用）是：
**通过破坏或损害消费者的自主性、决策或选择，误导用户去做他本来不打算做的事**。
该分类法里与我们相关的两条是 **Moving Targets**（不透明地改动绩效目标或激励门槛）
与 **Unpredictable Scheduling**。

### 3.2 为什么这条对我们比对 Uber 更硬：Motivation Crowding Theory

Frey & Jegen (2001) 的框架：外在激励（金钱或非金钱）既可能 crowd-in 也可能 crowd-out
内在动机，**分野在于个体把它感知为 controlling 还是 supportive**。

证据两边都有，且分歧正好落在人群上：

- Hua et al. (2020)：金钱奖励**提升**了网约车司机的工作投入（crowd-in）
- Osterloh & Rota (2007)：外在激励**挤出**了自愿的软件与知识分享（crowd-out）
- PLOS One (2025)，企业志愿者中的公民科学项目：游戏化与竞争元素**用对了**能强化
  对项目目标的投入，用不对则通过 crowding out 削弱内在动机
- 社区问答平台研究（"the double-edged sword of inflated help"）给出的处方是：
  游戏化机制应围绕**内在动机与更高层需求**重新设计，而不是简单加大奖励力度

调和变量是 Self-Determination Theory：外在动机要能被内化，需要**自主性、胜任感、归属感**
三者的环境支持。

⇒ **判据落地**：AidRun 的志愿者是**无偿**的，即纯内在动机人群，落在 crowd-out 风险最高的一侧。
而「下线挽留」是 controlling 型奖励结构的教科书形态。三条硬规则：

1. **关「可服务」开关时，不得弹任何激励挽留**
2. 激励层**不得有倒计时、不得有会变的门槛**
3. 首页**不得出现「还差 1 单就…」这类压力句式**（陈述已完成多少可以，催促不行）

这同时给 `live-trip-sharing-and-volunteer-incentives-20260813.md` §2 那句
「要避开排行榜竞争」补上了机制解释 —— 原文只给了结论和「志愿者会挑分高的任务」这个现象。

### 3.3 服务时长折算成金额 —— 业界通行，我们绝对不能做

志愿者管理平台的通行做法是在影响力面板上把累计服务时长**折算成美元金额**展示
（用 Independent Sector 的全国费率，约 \$33/小时），理由是便于向资助方证明成效。

**AidRun 禁止**，两条各自独立成立：

- 中央网信办 2026-06-19《关于开展网络平台涉志愿服务违规信息专项整治的通知》第 2 条
  点名整治「宣传可以获得志愿服务时长」类表述
- `VolunteerPointsCopy.disclaimer` 已对外声明积分不能提现、转让、兑换现金

### 3.4 一屏只强调一个主指标

志愿者 App 的设计复盘给的具体做法：被强调的信息需要**字号更大、字重更粗、颜色不同、
留白更多**；**把好几处信息用同样的方式强调是错误的**。图标要么全描边要么全填充，不能混。

徽章侧的两条注意：不要给每个元素都挂徽章（会稀释意义）；需要详细解释才能懂的内容
不要做成徽章，用标签或说明文字。

---

## 4. 界面参考源：去哪儿找图

### 4.1 真实上架 App 的截图与流程（做 UX 决策用这一类）

| 站点 | 特点 | 免费度 |
|---|---|---|
| [Mobbin](https://mobbin.com) | 该领域基准，人工策展的真实 App 界面与完整流程库，可搜 | 多数内容付费 |
| [Page Flows](https://pageflows.com) | 以**录屏**呈现交互流程 | 部分免费 |
| [Refero](https://refero.design) | 大体量 UI 库 + 完整流程 + AI 搜索 | 部分免费 |
| [Pttrns](https://pttrns.com) | 老牌移动端 UI 模式库 | 部分免费 |
| [UXArchive](https://uxarchive.com) | **能跨版本对比同一个 App 的历史变化**，别处少见 | 免费 |
| [AppShots](https://appshots.design) | 按 App 收录截图，本轮的 Uber Driver 图就出自这里 | 未登录只放几张 |
| [Banani](https://www.banani.co/references) | Tinder / Duolingo / Airbnb 等的界面参考 | 全免费，但库小 |

⚠️ **Screenlane 已经没了** —— `screenlane.com` 现在重定向到 Page Flows，别再按旧笔记去找它。

### 4.2 视觉方向（**不要**拿来做 UX 决策）

Behance、Dribbble、Muzli、[Collect UI](https://collectui.com)（14,000+ 条，但底料是
Dribbble 稿而**不是真实上架产品**）。

一份代理商的工作流描述说得很准：先用 Mobbin / Pttrns 做模式调研 → 再用 Page Flows / Refero
看流程与页序 → 最后才去 Behance / Dribbble / Muzli 找视觉方向，**但不要把它当 UX 决策的终审来源**，
因为「一个界面可以看起来很精致，同时是个很差的 onboarding / 导航 / 转化参考」。

### 4.3 中文设计复盘（讲「为什么这么定」，本项目更需要这一类）

- [优设网 uisdc.com](https://www.uisdc.com) —— 本轮的滴滴车主端 5.0 复盘在这儿
- [站酷 zcool.com.cn](https://www.zcool.com.cn) —— 同一篇也有，常有原厂设计团队直发

### 4.4 讲机制而不只是给图

[Growth.Design](https://growth.design/case-studies) —— 拆的是**模式背后的理由**，
适合「要不要做这个激励」而不是「这个卡长什么样」这类问题。

### 4.5 🚩 用这些站点时的一条自家约束

`claude-code-setup-for-ios-a11y-20260902.md` 已记录：AI 生成的界面有可识别的「指纹」——
同款 teal 强调色、会闪的状态点、**三列网格**、每张卡左侧一条竖线；
反制办法是**逐条点名拒绝**，而不是说「好看一点」。

⚠️ 其中「三列网格」与 `run-track-replay-ui-20260812.md` 的结论（跑步统计的通行版式
**就是** 3 列网格、数字大标签小在下）表面冲突。两者可以并存：
**问题不是三列网格本身，是不加区分地到处用它**。用在统计数字上是对的，
用在「关系 / 进度 / 状态」这类非同质信息上就是那枚指纹。

---

## 5. 一句话结论

同形产品（滴滴车主端 5.0）把首页全部信息按重要度压进**模态 / 非模态 / 普通信息**三种卡片，
**激励属于第三档**，且「成就感」被定位成事件节点而非常驻大区块；
Uber Driver 则把单个最强激励数字提到**顶部常驻 chrome**、把激励卡片流放进单独的 Earnings Tracker。
必须反着做的有三条：**不得在用户退出/下线时用目标挽留**（Motivation Crowding Theory 指出
controlling 型奖励会挤出内在动机，而无偿志愿者是纯内在动机人群，风险高于网约车司机）、
**不得把服务时长折算成金额**（网信办 2026-06-19 通知第 2 条）、**一屏只强调一个主指标**。
两家的具体圆角/间距/字号**均未公开**，抄结构不抄像素。参考图优先 Mobbin / Page Flows /
UXArchive 这类真实上架产品库，Dribbble / Behance 只看视觉方向；`screenlane.com` 已停运。

---

## 来源

均为 2026-09-14 核实。

- [高手的设计流程！滴滴车主端5.0全新升级背后的设计思考（优设网）](https://www.uisdc.com/didi-driver-app-design) · [同文（站酷）](https://www.zcool.com.cn/article/ZNTEwMDQ0.html)
- [Building a Real-time Earnings Tracker into Uber's New Driver App（Uber 官方工程博客）](https://www.uber.com/en-IN/blog/real-time-earnings-tracker/) · [Introducing a new app, built together with drivers（Uber）](https://www.uber.com/us/en/blog/introducing-the-new-driver-app/) · [Quest Goals（Uber）](https://www.uber.com/us/en/blog/quest-goals/)
- [Uber - Driver | UI & UX App Screenshots（AppShots）](https://appshots.design/apps/make-money-driving-start-now-app-shot-uber_driver_/)
- [The Algorithmic-Human Manager: AI, Apps, and Workers in the Indian Gig Economy（arXiv 2606.19975）](https://arxiv.org/pdf/2606.19975)
- [Gamifying the gig: transitioning the dark side to bright side of online engagement（AJIS）](https://ajis.aaisnet.org/index.php/ajis/article/download/2979/1063/11363)
- [Motivation crowding effects on the intention for continued use of gamified fitness apps（Frontiers in Psychology 2023）](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2023.1286463/full)
- [The role of intrinsic motivation in sustaining citizen science participation among diverse participants in a corporate volunteer program（PLOS One 2025）](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0331221)
- [“The double-edged sword of inflated help”: Unravelling the motivation crowding in community question-answering platforms（PMC）](https://pmc.ncbi.nlm.nih.gov/articles/PMC10936805/)
- [Case study: Tips from designing a volunteer app for students（Bootcamp / Medium）](https://medium.com/design-bootcamp/case-study-tips-from-designing-a-volunteer-app-for-students-5d2f11d6ef38)
- [How to Build a Volunteer Management App for Nonprofits（Kanopy）](https://kanopylabs.com/blog/how-to-build-a-volunteer-management-app)
- [Badge UI Design: Best practices, Design variants & Examples（Mobbin Glossary）](https://mobbin.com/glossary/badge)
- [Best Mobbin Alternative for UI Design Inspiration 2026（The App Launchpad）](https://theapplaunchpad.com/blog/best-mobbin-alternatives/) · [10 Mobbin Alternatives 2026（Toolworthy）](https://www.toolworthy.ai/blog/mobbin-alternatives) · [15 Best Sources for Mobile App Design Inspiration in 2026（ProCreator）](https://procreator.design/blog/sources-mobile-web-app-design-inspiration/)
