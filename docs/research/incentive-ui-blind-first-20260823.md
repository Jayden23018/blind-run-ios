# 激励体系的**前端呈现层**：火花断裂告知 / 零加分流水 / 邀请码只靠听 / 朗读脚本（2026-08-23）

> **本报告是差量补充，不是重做。** 后端 `demo/docs/research/incentive-gamification-20260822.md`
> 已经查完「该不该做、合不合规、有没有实证」，本仓库 `live-trip-sharing-and-volunteer-incentives-20260813.md`
> 已经查完「激励分层怎么设」。这两份的结论本轮**一条都没重查**，直接当前提用。
>
> 本轮只查它们没覆盖的那一段：**这些数字与关系，在一个读屏用户的耳朵里长什么样。**
> 后端那份第 5 节自己写着「盲人一侧的激励形式，只有你们能定 —— 这是整份调研里最大的空白」。
>
> **档位：C（完整选型），不开 subagent** —— 本 session 禁用 Agent 工具，三线由主会话自跑。

## 0. 来源分级与本轮核验记录

| 等级 | 含义 |
|---|---|
| 🟢 **[高]** | 官方文档 / 官方帮助页原文 / **本机 SDK 头文件**，且已逐字取到 |
| 🟡 **[中]** | 单一可靠来源、社区技术文章 |
| 🟠 **[低]** | 搜索结果转述、未取到原文 |

本轮做过的核验（不是口头声称）：

1. **6 个页面用 headless Chrome 真实渲染并截图存档**（`assets/incentive-ui-20260823/`），
   逐张打开看过内容，不是只存了个文件名。
2. **版本敏感的 API 不查网页，查本机 SDK `.swiftinterface`** —— 这是本仓库
   `tts-rate-follows-voiceover-20260814.md` 立下的规矩（那次 WebSearch 把 iOS 14 转述成了 iOS 16）。
3. **一条搜索转述与官方页矛盾时，两个页面都打开** —— Uber 邀请码那条（§3.2），
   转述说「15 天可补」、官方帮助页写「不能补」，结果是**两条都对，分属两个页面**。
   只信任其中一条会得出反向结论。
4. **后端配置当场核**：任务简报里写的「四个开关默认全关」**是错的**，见 §5.1。

---

## 1. 🔴 先说三条会直接改设计的发现

### 1.1 `speechSpellsOutCharacters` 存在、iOS 15+、我们的部署目标够（本机 SDK 实证）

邀请码要被口头念给人听，字符集已排除 `0 O 1 I L`。读屏必须**逐字念**，
不能把 `AK37PQR9` 念成一个词。这件事**不需要自己拼字符串加顿号** —— SwiftUI 有原生 API。

本机 SDK（`iPhoneOS26.2.sdk` 的 `SwiftUI.swiftinterface`）逐字：

```
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension SwiftUICore.Text {
  public func speechSpellsOutCharacters(_ value: Swift.Bool = true) -> SwiftUICore.Text
}
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
extension SwiftUICore.View {
  nonisolated public func speechSpellsOutCharacters(_ value: Swift.Bool = true) -> some SwiftUICore.View
}
```

Apple 官方文档同一条，Discussion 里举的例子正是我们的场景：
「An acronym that isn't a word, like APPL, spoken as "A-P-P-L".」
[Apple Developer](https://developer.apple.com/documentation/swiftui/view/speechspellsoutcharacters(_:)) [高]
（截图 `assets/incentive-ui-20260823/05-apple-speechspellsoutcharacters.png`，
可用性一行为 `iOS 15.0+ | iPadOS 15.0+ | ...`）

部署目标 iOS 16 ⇒ **不需要 `#available`**。

**还有一条同样在 SDK 里查实的**：`accessibilityLabel(_ label: Text)` 这个重载是
**iOS 14+** 就有的（`SwiftUI.swiftinterface:822`），而 `Text` 支持 `+` 拼接且保留每段自己的修饰符。
⇒ 可以写成

```swift
.accessibilityLabel(Text("我的邀请码 ") + Text(code).speechSpellsOutCharacters())
```

而**不必**退回到 iOS 18 才有的 `AttributedString` 重载（`:786-788` 全是 `iOS 18.0`）。
另有 `UIAccessibilitySpeechAttributeSpellOut`（`UIAccessibilityConstants.h:308`，iOS 13+）
是 UIKit 那条路，本仓库用不上。

⚠️ **这里有一条我没验到的**：`.speechSpellsOutCharacters()` 加在子 `Text` 上、
再被父容器的 `.accessibilityElement(children: .combine)` 合并时，属性是否保留。
社区教程说保留并给了示例 [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-make-voiceover-read-characters-individually) [中]，
但**这正是本仓库栽过跟头的形状** —— `swiftui-voiceover-traversal-order-20260814.md` 那次，
社区资料说「补 `.contain` 就生效」，真机实测四种排法全废。
⇒ **落地时必须真机开 VoiceOver 听一遍**，并且优先用「`accessibilityLabel(Text)` 拼接」
这条路（属性挂在 label 自己身上，不经过合并），把 `.combine` 那条当备选。

### 1.2 「断了」这个词本身就是伤害 —— 而且有官方实证支持不这么说

Duolingo 官方博客逐字：
> "If you lose a day and break your streak, it can have the opposite effect, and actually feel quite _de_motivating."

[Duolingo Blog](https://blog.duolingo.com/how-duolingo-streak-builds-habit/) [高]
（同页另两条：给用户一点「slack」比刚性规则更有激励；到 7 天的学习者完成课程的可能性是 3.6 倍。）

后端已经据此把 eventType 定成 `PARTNER_STREAK_RESTARTED` 而不是「已中断」，模板正文
（`demo/src/main/resources/data.sql:251,254`）逐字是：

> 标题「新的连续记录开始了，这是第 1 周」
> 正文「你们的新一段连续记录开始了，这是第一周。你们最好的成绩是连续 {bestWeeks} 周一起跑步。」

⇒ **客户端一个字都不用改，也一个字都不要改。** 这条 WS 通知走的是既有的
`APP_NOTIFICATION` 通用通道（`AppRealtimeCoordinator.swift:724` 起未知 `eventType` 一律照播），
所以**接入成本为零**。这是本轮最省事的一条结论，前提是不要多此一举去写本地文案覆盖它。

### 1.3 Strava 的一条反面教材：不可关闭的成就通知是已知痛点

Strava 帮助页逐字：
> "Streak banners are available for activities in weeks 2-5 and for major milestones such as 10, 15, 25, 1 year, 2 years, and 3 years. **There is no feature available to disable these notifications at this time.**"

[Strava Help Center](https://support.strava.com/en-us/articles/15401580-streaks-on-strava) [高]
（截图 `01-strava-streaks.png`；社区里已有用户明确要求关掉，见搜索结果里的 communityhub 帖 [低]）

⇒ 对明眼人是一条多余的推送；**对读屏用户是一段会打断当前朗读的语音**。
我们的 `PARTNER_STREAK_RESTARTED` 是 `NORMAL`、不补发 APNs、且只在这一对曾点亮过时才发，
已经比 Strava 克制。**但仍不要给它做 TTS 抢播**：它落在「刚跑完一单」这个时刻，
那时用户正在听订单完成播报。按普通通知排队即可（`speechAnnouncementsQueued` 的语义）。

---

## 2. 火花（streak）：判定规则可抄的部分与我们的差异

Strava 的判定规则与后端定的**完全同构**，这是好消息（说明后端没有自创口径）：

| 项 | Strava [高] | AidRun 后端 | 差异 |
|---|---|---|---|
| 周边界 | "A week starts on Monday and ends on Sunday." | ISO 自然周，周一–周日 | 无 |
| 一周算不算 | 上传 ≥1 次、≥60 秒的活动 | 该周内这一对 ≥1 单 `COMPLETED` | 无（我们是「一对」不是「一个人」） |
| 手动补录 | "including manual uploads" 都算 | **不看**手动完成还是超时自动完成 | 同向：都容忍「忘了记录」 |
| 断了能补 | ✅ 事后补传即可恢复 | ❌ 无补传，靠每季度 2 个自动暂停周 | **我们更严**，但用户感知不到暂停周 |
| 展示位置 | You → Progress 标签页（二级） | 待定（本报告 §4） | — |
| 未达成 | 未点亮不显示（08-22 报告已查实） | 未点亮**不在数组里** | 无 |

**对前端的直接含义**：`currentWeeks` / `bestWeeks` 两个数就够了，
`lastCreditedWeek` 是 ISO 周字符串（`2026-W34`），**只展示的话根本不用碰它**
（后端 handoff 第 2 步 ③ 明确警告：拿它做日期解析跨年必错，`2025-12-29` 属于 `2026-W01`）。

---

## 3. 邀请码：可抄的规则、以及一条只有打开原文才看得见的分裂

### 3.1 Uber 官方帮助页逐字（截图 `04-uber-invitation-code.png`）

> **Important**: They must use your code during their initial registration process for you to be eligible for the referral bonus.
> **Remember this** — We cannot offer retrospective referral bonuses if your friend forgets to use your invite code during sign-up.

[Uber Help – Invitation code](https://help.uber.com/en/driving-and-delivering/article/invitation-code?nodeId=f6ce0a5d-03cc-4bfc-bf71-3cefa04d1eab) [高]

⇒ 「只能在注册时填、事后不补」**是行业标准做法**，我们的后端口径不是自创。
更值得抄的是**它把这句话做成了给邀请人看的独立小标题**（"Remember this"），
而不是埋在细则里 —— 因为忘记填的成本落在**邀请人**身上。
⇒ **这句警告要出现在两处**：邀请码页（告诉邀请人「对方必须在选身份那一步填」）
和选身份屏（告诉被邀请人「只能填这一次」）。只写一处，另一头的人不知道。

### 3.2 ⚠️ 但另一个页面写着可以补 —— 两条都对

> "You and your referrer will remain eligible for a retroactive referral for **15 days** after signup."

[Uber Help – Signup invite code issue](https://help.uber.com/en/driving-and-delivering/article/signup-invite-code-issue?nodeId=3b34aca2-f286-4ebc-b04c-c928341afea7) [高]

⇒ Uber 的真实形态是「**对外说不能补，对内留 15 天人工补救**」。
我们目前**两样都没有**：既没有补填入口，也没有「我的邀请人是谁」这个端点
（后端 handoff 第 4 步 ② 自己写明了）。对盲人用户这尤其贵 ——
他填错了，请求照样成功，界面上没有任何差别，**他永远不会知道**。
⇒ 已写进 handoff 待后端确认（§6）。**前端本轮不做任何补救，只做诚实告知。**

### 3.3 积分不可转让：可抄的是「把这句话写进用户须知」这个做法

蚂蚁森林《用户使用须知》逐字（截图 `03-antforest-rules.png`）：
> 「森林中的绿色能量无法转让或继承。」
> 「若您存在购买或出售绿色能量或浇水服务，通过虚假种植、虚假绿色出行、虚假交易等违反诚信的方式获取绿色能量……我们将会扣除您因此获得的绿色能量（如有）」

[蚂蚁森林用户使用须知](https://render.alipay.com/p/f/antforest/license.html) [高]

⇒ 这是一个**已上线的中国产品把「不可转让」写在用户可见文案里**的先例。
后端的合规红线（积分不可转让/提现/兑换）不是只能写进法务文档，
按蚂蚁森林的做法就该**写在积分页上**，一句话，用户看得到。

---

## 4. 🚩 本报告的主要产出：朗读脚本（这部分没有先例，是推导）

学术线本轮**复核了后端说的空白，确认仍是空白**：OpenAlex 检索
`blind screen reader gamification achievement motivation`（548 命中）前 8 条里，
面向视障者的只有 2 篇印尼的**儿童学习** App 和 1 篇后端已引的实体交互研究（N=3）。
[OpenAlex API](https://api.openalex.org/works?search=blind%20screen%20reader%20gamification%20achievement%20motivation) [中]
⇒ **没有可抄的**，下面是按 Apple HIG 的通用原则 + 本仓库已验的遍历顺序规律推导的。

四条推导规则（每条都能落成断言）：

1. **一个卡片一个焦点。** 数字和它的单位、标签必须 `.combine` 成一句，
   否则「7」「周」「和张师傅」会被念成三下划动。本仓库既有代码已经是这个写法
   （`VolunteerServiceRecognitionView.header`，`VolunteerOrderFlowViews.swift:1857`）。
2. **屏幕上的占位符号不是给耳朵的。** `--`、`0 分` 的视觉写法在读屏里要换成人话。
   本仓库已经栽过一次：评分为空时念出「评分：破折号破折号」，被无障碍审计抓到
   （`VolunteerOrderFlowViews.swift:1869-1872`）。
3. **进度条对 VoiceOver 是空的**，进度必须另有一个真实文本节点
   （`VolunteerAchievementsCopy.starProgressText` 的注释就是这条）。
4. **顺序即优先级。** 后端已按 `currentWeeks` 倒序返回，因为「读屏是顺序播报的，
   排在后面等于不存在」。客户端**不要重排**。

### 4.1 逐屏朗读脚本

下面每一条是「VoiceOver 划到这个元素时念出的整句」，`→` 表示下一次划动。

**① 志愿者积分页（有流水）**
```
「积分，标题」
→「当前积分 130 分」
→「积分不能提现、不能转让、不能兑换现金。积分商城开发中。」
→「积分和志愿服务时长是两回事。累计服务时长在服务成就页查看。」
→「积分明细，标题」
→「8 月 22 日，加 10 分，完成陪跑服务」
→「8 月 21 日，加 0 分，已达同一对每周上限 30 分，本单不加分」   ← note 原样念
→「8 月 20 日，加 20 分，邀请奖励」
```
🔴 第 7 行是本页存在的理由。念成「0 分」而不念 note，等于把唯一的解释藏起来。

**② 志愿者积分页（空）**
```
→「还没有积分记录。完成一次陪跑服务后，这里会显示每一笔的加分和原因。」
```
⚠️ **不是**「功能未开启」—— 积分**没有开关**（§5.1）。

**③ 盲人端「我的固定搭档」（一条有火花、一条对方已退出）**
```
「我的固定搭档，标题」
→「张星，已经连续 7 周一起跑步，一起跑完过 12 次」
→「李明，一起跑完过 3 次，对方已退出固定搭档」        ← 没有火花那一句整段不念
→「取消收藏 张星，按钮」
```
🔴 「李明」那条**必须念出「对方已退出」**。只做灰色态 = 对我们的用户等于不存在，
而盲人会以为收藏丢了、重新收藏一次，把志愿者刚做的退出无声撤销掉（后端 handoff 第 3 步 ②）。
🔴 `streakWeeks == nil` 时**整句不念**，不要念「连续 0 周」。

**④ 志愿者端「固定搭档」+ 退出**
```
「固定搭档，标题」
→「有 2 位跑者把你设为固定搭档」
→「李明，2026 年 7 月 3 日设为固定搭档，已经连续 7 周一起跑步」
→「退出与李明的固定搭档，按钮」
     点击 → 弹二次确认：
     「退出固定搭档？退出后你将不再被优先派给这位跑者，且需要重新一起跑一单才能恢复。」
     →「确认退出，按钮」→「取消，按钮」
→「王强，2026 年 8 月 1 日设为固定搭档，你已退出」   ← optedOut=true 仍在列表里
```

**⑤ 邀请码页**
```
「我的邀请码，标题」
→「我的邀请码 A、K、3、7、P、Q、R、9」            ← speechSpellsOutCharacters
→「复制邀请码，按钮」
→「已经有 3 人使用了你的邀请码，其中 1 人已发放奖励。」
→「邀请志愿者加入，等他完成第一次陪跑，你们各得 20 积分。邀请视障跑者只记录关系，不发积分。」
→「对方必须在选择身份那一步填写你的邀请码，注册完成后无法补填。」
→「积分不能提现、不能转让、不能兑换现金。」
```
🔴 第 5 行**不能写成「邀请好友双方得积分」** —— 只有邀请**志愿者**且他完成首单才发分。

**⑥ 选身份屏（折叠态，推荐）**
```
「请选择您的角色，标题」
→「我是盲人跑者，预约志愿者陪我跑步，按钮」
→「我是志愿者，陪伴盲人跑者完成跑步，按钮」
→「我有邀请码，可选，按钮，收起状态」            ← 一次划动就跳过，不是一个输入框
→「身份一经选定不可更改，请谨慎选择」
```
展开后：
```
→「邀请码，文本框」
→「只能在这里填一次，设定身份后无法补填。填错不会影响身份设置，但不会建立邀请关系。」
```
🔴 最后那句是本仓库的诚实红线：**填错不会让请求失败**，所以界面绝不能在提交成功后
说「邀请码已生效」——我们无从得知。

---

## 5. 风险线：三条会让人接错的事实（都当场核过）

### 5.1 ⚠️ 积分**没有**开关 —— 「四个开关默认全关」这个说法是错的

后端 `application.properties` 里 `app.incentive.points.*` 全是数值参数
（`order-completed=10` / `order-auto-completed=3` / `daily-cap=20` / `pair-weekly-cap=30`
/ `rule-version=1` / `invite-inviter=20` / `invite-invitee=20`），
`PointService.java:44-65` 的 `@Value` 也只注入这几个，**没有任何 enabled 布尔**。

真正带开关的是三个：
`app.dispatch.favorite-round.enabled=false`（`:193`）、
`app.incentive.streak.enabled=false`（`:334`）、
`app.incentive.invitation.enabled=false`（`:351`）。

⇒ **联调时积分会真的动**（SPEC §1 决策 1 明写「流水从第一天记全」），
火花会拿到空数组，邀请关系会建立但不发分。
积分页的空态文案因此**不能**写「功能未开启」。

### 5.2 三个端点的「空」语义各不相同，写成同一个空态就是错的

| 端点 | 空是什么意思 | 该显示什么 |
|---|---|---|
| `/api/volunteer/points` | 真的还没跑过单 | 「还没有积分记录」 |
| `/api/*/partners/streaks` | 没有**已点亮**的火花（或开关关着） | 整块不显示，**不是**错误态、也不是「0 周」 |
| `/api/volunteer/favorites` | 没人收藏我 | 「还没有跑者把你设为固定搭档」 |

### 5.3 `GET /api/users/me/invite-code` **会写库**，且 UNSET 用户调它 403

契约 description 逐字：「本端点会写库：邀请码是惰性生成的，第一次调用时才落库。
别按纯读端点做缓存或预取。」「尚未设角色的 UNSET 用户拿不到邀请码，需先设角色。」
⇒ **不能**在设置页 `onAppear` 预取、不能在列表里逐用户调、不能放在选身份屏之前。
一次 `.task` 拉一次即可。

---

## 6. 共识 vs 争议

### 共识（多来源同向，直接当前提）

1. **「只能注册时填、不补」是行业标准**（Uber 官方帮助页原文），我们照做即可。
2. **周边界与「手动补录也算」的宽容口径**，Strava 与后端一致。
3. **邀请码要逐字念**，Apple 官方文档举的例子就是 acronym 逐字母（`A-P-P-L`）。
4. **不可转让要写进用户可见文案**，蚂蚁森林是已上线的中文先例。
5. **「断了」不该说出口**，Duolingo 官方博客有明确的 demotivating 表述。

### 争议

| 争点 | 一方 | 另一方 | 我的判断 |
|---|---|---|---|
| 成就类通知该不该能关 | Strava：不提供关闭，且社区在抱怨 [高/低] | 我们：`NORMAL` + 不补发 APNs + 只在曾点亮时发 | **我们已经更克制，本轮不加开关**；但不做 TTS 抢播 —— 它到达的时刻用户正在听订单完成播报 |
| 邀请码格填错要不要拦 | 后端：不拦，拦会打断盲人注册流程（灾难性） | 直觉：填了就该校验 | **后端对**。但代价是「用户永远不知道填错了」，这个代价必须**用文案显式说出来**，不能靠沉默 |
| 盲人侧要不要单独一屏火花 | 信息完整：`partners/streaks` 覆盖面 ⊋ 收藏列表 | 读屏成本：多一屏 = 多一层导航 | **一屏**（合进固定搭档列表），页脚一句说明覆盖面。理由见 §7 反对意见 1 |
| 选身份屏的邀请码默认展开还是折叠 | 展开：真被邀请的人不会错过（只有一次机会） | 折叠：每个新用户都要听一遍与自己无关的输入框 | **折叠 + 在进页面的 TTS 里提一句它存在** —— 两个坏处各消掉一半。⚠️ 这条是纯推导，无先例 |

---

## 7. 反对意见（什么情况下本报告是错的）

1. **如果盲人用户的固定搭档普遍超过 3 位，「合进一屏」就是错的。**
   本报告推荐盲人侧只做一屏，前提是列表短（后端上限 `app.favorite-volunteer.max-per-user=10`）。
   真有用户收藏满 10 位、其中 6 位有火花时，一屏顺序播报要听很久，
   那时应该拆成「有连续记录的」和「其余」两段。**这个前提没有真实数据支撑**，
   本轮零真实用户。⇒ 落地后要看真实分布再回来改。

2. **如果 `.speechSpellsOutCharacters()` 在真机上不生效，§4.1 的 ⑤ 整段作废。**
   本报告只在 SDK 头文件层面证明了它存在，**没有在真机上听过**。
   本仓库有先例：`swiftui-voiceover-traversal-order-20260814.md` 里社区说生效的写法真机全废。
   退路是自己拼「A、K、3、7」这样的顿号串塞进 `accessibilityLabel`
   —— 丑，但一定能念对，且不依赖任何 API 行为。

3. **如果「积分」这个词本身在志愿者那里就带着「能换东西」的预期，
   本报告所有关于文案的努力都是补丁。**
   §3.3 抄的蚂蚁森林先例里，绿色能量**是能换实物的**（真的种树），
   而我们的积分**当前什么都换不了**。一句「商城开发中」能不能撑住这个预期差，
   没有任何证据。⇒ 真正的解可能是**不叫「积分」**，但改名超出本轮范围，已记在 §8。

4. **如果后端把 `PARTNER_STREAK_RESTARTED` 的 priority 改成 `HIGH`，§1.3 的结论反转。**
   `HIGH` 会补发 APNs，那时它就成了一条会把人从口袋里叫出来的通知，
   「不做 TTS 抢播」这条克制就不够了，需要重新讨论要不要给开关。

---

## 8. 没查到的 / 本轮明确不做

| 缺口 | 影响 |
|---|---|
| **`.speechSpellsOutCharacters()` 在 `.combine` 容器里是否保留** | 只有社区教程 [中]，真机未验。落地必验，见反对意见 2 |
| **视障成人在服务类产品里的成就/进度呈现** | 复核了后端的空白结论，仍然空白（OpenAlex 548 命中里 0 条对口）。§4 全是推导 |
| **蚂蚁森林「本次未产生能量」的明细页原文文案** | 搜索只拿到第三方转述的上限数值 [低]，官方明细页文案未取到。我们的零分流水文案因此只能自己写（好在后端把 note 写好了） |
| **积分该不该改名** | 超出本轮范围，已在 §7-3 记一笔 |
| **榜单 / 积分商城 / 邀请深链接** | 后端第 5 步没做，本轮明确不做 |

---

## 9. URL 核验

```
$ grep -oE 'https?://[^)"< ]+' docs/research/incentive-ui-blind-first-20260823.md | sort -u | while read -r u; do
    c=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 12 -A 'Mozilla/5.0 ...' "$u"); echo "$c $u"; done

200 https://api.openalex.org/works?search=blind%20screen%20reader%20gamification%20achievement%20motivation
200 https://blog.duolingo.com/how-duolingo-streak-builds-habit/
404 https://developer.apple.com/documentation/swiftui/view/speechspellsoutcharacters(_:      ← grep 截断
404 https://help.uber.com/en/driving-and-delivering/article/invitation-code?nodeId=...
404 https://help.uber.com/en/driving-and-delivering/article/signup-invite-code-issue?nodeId=...
200 https://render.alipay.com/p/f/antforest/license.html
200 https://support.strava.com/en-us/articles/15401580-streaks-on-strava
200 https://www.hackingwithswift.com/quick-start/swiftui/how-to-make-voiceover-read-characters-individually
```

三条非 200 逐条处理过，**都不是假链**：

- **Apple 那条是 `grep` 的锅不是链接的锅** —— URL 本身以 `)` 结尾，
  而正则 `[^)"< ]+` 在 `)` 处停住，于是拿去 curl 的是个被截掉尾括号的残串。
  用完整 URL 复验：`GET 200 bytes=17606`。
- **两条 Uber 帮助页 curl 恒 404（9 字节），但 headless Chrome 在同一 URL 上渲染出了完整正文**
  —— 截图 `04-uber-invitation-code.png` 就是从这个 URL 拍的，「Invitation code」标题、
  「Remember this」小节、「We cannot offer retrospective referral bonuses...」逐字都在图里。
  ⇒ 判为**反爬**（它对不带 JS/不带会话的客户端一律回 404 壳），不是死链。
  这条比「手动打开确认一次」更硬：证据是一张从该 URL 渲染出来的存档图。

> 🚩 顺带一条给下次的教训：**这个核验脚本对结尾带 `)` 的 URL 会系统性误报。**
> Apple 的文档 URL（`func(_:)` 这种签名式路径）几乎全带括号，
> 照脚本输出直接删结论的话，会把一整类官方来源误杀。
