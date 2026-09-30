# 02 · 订单页各状态（iOS）

## 总体结构

订单页是**一个** `OrderPageView`，由后端返回的 `OrderView.state`（见 06）驱动，状态变化时原地切换，不 push 新页面。v3 的"原地变化不跳页"原则不变。

```
NavBar                      // 固定在顶部
ScrollView {                // 内容可滚动：小屏和大字体下不能裁切
  HeroCard
  其余卡片（按状态）
}
.safeAreaInset(edge: .bottom) { BottomActions }   // 主按钮区固定在底部
```

- 页面底色 `ground`，左右 20，卡片间距 12，NavBar 下方 12 开始第一张卡片。
- `BottomActions`：上边缘加一条 `ground` 到透明的渐变（高 16），内容为提示句（可选）+ 主按钮 / 次要按钮 + 文字按钮，底部留安全区。
- 所有时间、距离、姓名都来自接口。示例值只用于 Preview。

```swift
enum OrderPhase {
    case invited
    case agreedEarly      // now < suggestedDepartAt - 30min
    case agreedSoon       // suggestedDepartAt - 30min <= now，且尚未点"出发"
    case departed(late: Bool)
    case arrived(waitedSeconds: Int)   // 满 900 秒进入"等待满 15 分钟"
    case running(paused: Bool)   // v2 新增设计，见 08-running.md
    case completed
    case runnerCancelled
    case closed(reason: CloseReason)   // 过期 / 被抢先 / 已拒绝 / 陪跑员取消 / 结束等待
}
```

`agreedEarly` 与 `agreedSoon` 的切换由客户端按服务端返回的 `primaryActionUnlockAt` 计时触发；App 在后台时，下次回到前台重新计算。

---

## ① 邀请 `invited`

画板：`Invite.dc.html`

**NavBar**：返回 · 「陪跑邀请」· 求助

**头卡（`.light`，白底）**
1. 一行：左「新的陪跑邀请」14 bold `blue`；右「还剩 52 分钟回复」14 `inkSecondary`
2. 3pt 进度条（底 `blueTint`，填充 `blue`）；剩余 <15 分钟时进度条和剩余时间变 `urgent`（沿用 v3）
3. `RopeView(state: .invited)`
4. 「周六 7:00」`heroNumberS`
5. 「深圳湾公园 3 号入口」16 `inkSecondary`
6. 三宫格（底 `surfaceSubtle`，圆角 16）：3.2 公里 / 离你；5 公里 / 跑多远；7'00" / 配速。数字 22 heavy，单位 13 semibold，标签 13
7. 时钟图标 +「在你周六早上的空闲时间里」14 `inkSecondary`

**`RunnerCard`**：「李先生」，说明「全盲 · 用引导绳」，「他写给陪跑员」+ 原话。接单前只显示姓氏（v3 规则不变），不显示标签和留言。

**底部**：锁图标 +「接下后显示李先生的全名和电话」14 `inkSecondary` 居中 → `PrimaryButton`「接下这次陪跑」→ `TextButton(.neutral)`「这次去不了」

**读屏顺序**：邀请，第 1 步，共 4 步，还没约好 → 新的陪跑邀请，还剩 52 分钟回复 → 周六 7:00，深圳湾公园 3 号入口 → 离你 3.2 公里，跑 5 公里，配速 7 分左右 → 在你周六早上的空闲时间里 → 跑者李先生，全盲，用引导绳 → 他写给陪跑员：…… → 接下这次陪跑 → 这次去不了

**转移**：接下 → `agreedEarly` 或 `agreedSoon`（播放"绳子接上"动画，见 03）；这次去不了 → 沿用 v3 B10（Toast + 撤销）。

---

## ② 约好 · 前一晚 `agreedEarly`

画板：`Main.dc.html`

**NavBar**：返回 · 「陪跑订单」· 求助

**头卡（`stateAgreed` 藏青）**
1. 「已约好 · 明天早上」14 semibold `onNavyEyebrow`。"明天早上 / 今天早上 / 周六早上"由客户端按开始时间和当前日期生成
2. `RopeView(state: .agreed)`
3. 「6:35」`heroNumberM` + 「出发」`heroUnit`
4. 两行 15 `onNavyBody`：「骑车约 20 分钟，7:00 在 3 号入口见李明」/「6:30 会提醒你出发」（提醒时间 = `departReminderAt`，即建议出发前 5 分钟，**不是**画板上的 6:25）

**`RunnerCard`**：「李明」（接单后显示全名），「全盲 · 引导绳 · 跑 5 公里」，标签「一起跑过 3 次」（为 0 时隐藏），跑者留言气泡（`runner.messageToVolunteer` 为空时隐藏），「他写给陪跑员」+ 原话（为空时回退到 v3 的结构化引导习惯："陪跑员在左侧 · 过台阶提前说一声"）。

**`PlaceRow`**：「深圳湾公园 3 号入口」/「石牌左边的空地」（`meetingPoint.landmark` 为空时只显示一行），右侧「地图 ↗」。

**底部**：`SecondaryButton`「我已经出发了」→ `TextButton(.neutral)`「修改或取消」（→ v3 D1）

**读屏**：已约好，第 2 步，共 4 步 → 明天早上 6 点 35 分出发，骑车约 20 分钟，7 点在 3 号入口见李明，6 点 30 分会提醒你 → 李明，全盲，引导绳，跑 5 公里，你们一起跑过 3 次 → 李明说：明天见，谢谢你陪我跑 → 他写给陪跑员：…… → 集合点，深圳湾公园 3 号入口，石牌左边的空地，双击在地图中打开 → 我已经出发了 → 修改或取消

## ②b 约好 · 出发前 30 分钟 `agreedSoon`

画板：`MainSoon.dc.html`

与 ② 相同，差异如下：
- 小标题「已约好 · 今天早上」
- 主角区：「15」`heroNumberL` + 「分钟后出发」`heroUnit`；数字每分钟更新（`contentTransition(.numericText())`）。距建议出发时间 ≤0 时显示「现在出发」`heroNumberM`，若已过点则显示「已过建议出发时间 N 分钟」，数字颜色改为 `gold`
- 副文一行：「6:35 出发，骑车约 20 分钟到 3 号入口」
- `RunnerCard` 不显示留言气泡（已在前一晚看过；保持卡片更短）
- 底部：`PrimaryButton`「我出发了」→「修改或取消」
- 从 ② 切到 ②b 时播放"主按钮升级"动画（见 03）

**转移**：我出发了 → `departed`，跑者端同步为"张伟正在赶来"（v3 不变）。

---

## ③ 出发 `departed(late: false)`

画板：`Depart.dc.html`

**头卡（`stateDeparted` 主蓝）**
1. 「正在赶去 · 骑车」（交通方式来自"我的"设置）
2. `RopeView(state: .departed, progress: p)`，p 来自 `eta.progress`
3. 「8」`heroNumberXL` + 「分钟后到」`heroUnit`；实时更新
4. 「预计 6:57 到，比约定早 3 分钟」15 `onNavyBody`。按 `eta.deltaVsStartMinutes`：<0 显示「比约定早 N 分钟」，0 到 3 显示「刚好赶上」，>3 进入快迟到
5. `PresencePill`「李明已到 3 号入口附近」。仅当 `runnerPresence.nearMeetingPoint == true` 时显示；跑者关闭了位置共享时整个胶囊隐藏，不显示任何替代文字

**`QuickReplyGrid`**：「我快到了」「再等我 5 分钟」。点击后该按钮原地变成「✓ 已发送」1.5 秒，轻触感；同一条 60 秒内不能重复发送。

**`PlaceRow`**：导航图标，「导航去集合点」/「3 号入口 · 石牌左边的空地」，右侧 ↗。跳系统地图（v3 不做 App 内地图）。

**底部**：`PrimaryButton`「我已到达集合点」→「修改或取消」

**不变的 v3 规则**：进入 100 米推送询问「到了吗」，不自动切换；按下主按钮 → `arrived`。

## ③b 快迟到 `departed(late: true)`（v3 D2，本期用新视觉）

没有单独的画板，在 ③ 的基础上修改：
- 主角数字和单位颜色改为 `gold`，副文改成「7:06 左右到，比约定晚约 6 分钟」
- 头卡下方插入一条提醒条：底 `warmCard`、字 `warmCardTitle` 15 semibold，「已自动告诉李明你会晚到约 6 分钟」（v3 文案，不用红色）
- 其他完全不变，页面结构不跳动；追回时间后提醒条自动消失（高度动画 0.25 秒）

---

## ④ 汇合 `arrived`

画板：`Meet.dc.html`

**头卡（`stateArrived` 琥珀）**
1. 「已到集合点」
2. `RopeView(state: .arrived)`
3. 「李明就在附近」`title` 白色
4. 「在你右前方，大约 50 米以内」15 `onNavyBody`

标题和副文按 `meet.distanceBucket` 和客户端算出的方位描述生成：

| distanceBucket | 标题 | 副文 |
|---|---|---|
| `WITHIN_10` | 李明就在你身边 | 在你{方位}，10 米以内 |
| `WITHIN_50` | 李明就在附近 | 在你{方位}，大约 50 米以内 |
| `WITHIN_100` | 李明就在附近 | 在你{方位}，大约 100 米以内 |
| `FAR` | 李明还没到集合点 | 他的手机在 {N} 公里外 |
| `UNKNOWN` | 暂时看不到李明的位置 | 可以让他的手机响起来，或给他打电话 |

方位描述由相对角度 θ（跑者方位角减去手机朝向，取 −180 到 180）得出：|θ|≤22.5 前方；22.5–67.5 右前方或左前方；67.5–112.5 右边或左边；112.5–157.5 右后方或左后方；其余为身后。**两边各留 5° 的滞回**，避免描述来回跳。

**`DirectionDial`**（头卡下方，居中，直径 180）
- 白色圆盘，外投影 `stateArrived` 14% 不透明度 / y 12 / 模糊 30
- 顶部一个 8pt 的 `ink` 短刻度，表示"你面朝的方向"
- 以 θ 为中心、宽 60° 的扇形（`stateArrived` 16% 不透明度），扇形外缘是一个 `stateArrived` 三角箭头（v2：随状态色）
- 圆心是 40pt `stateArrived` 圆，写白色"你"
- 扇形宽度随位置精度变化：`max(60°, 2·atan(精度 / 距离))`，上限 120°
- `UNKNOWN` 或 `FAR` 时隐藏扇形和箭头，只保留圆盘和"你"，透明度降到 50%
- 读屏：整个圆盘 `accessibilityHidden(true)`，方位只由标题和副文朗读

**`ClothingSwatches`**：「认准他」+ 深蓝色块「深蓝上衣」+ 白色色块「白色帽子」。数据来自 `clothing[]`；跑者没填写时整张卡片隐藏。

**响铃按钮**：高 56，圆角 17，底 `arrivedTint`，1.5pt `arrivedTintBorder` 描边，字 `arrivedInk` 16 bold（v2：藏青现在代表"约好"，这里改用汇合的暖色），`speaker.wave.2` 图标，「让李明的手机响起来」。点击后变成「正在响铃…」，图标做 `symbolEffect(.variableColor.iterative)`，持续到服务端返回的 `ringingUntil`（约 10 秒）；期间按钮不可再点。读屏提示：「李明的手机会响铃，并播报你的陪跑员到了」。

**两列白色按钮**（高 48）：「打电话」（显示全名和号码，v3 规则不变）/「找不到对方」（沿用 v3 的现有流程）。

**底部**：提示「见面并握好引导绳后再按」14 `inkSecondary` → `PrimaryButton`「开始跑步」。没有"修改或取消"。

**读屏节流**：方位描述变化时用 `AccessibilityNotification.Announcement` 播报，至少间隔 3 秒，而且只在描述文字（前方 / 右前方……）或距离档位变化时播报（v3 规则加强）。

**触感**：distanceBucket 首次进入 `WITHIN_10` 时轻震一次（v3）。

## ④b 等待满 15 分钟 `arrived(waitedSeconds ≥ 900)`（v3 D3，本期用新视觉）

没有单独的画板，在 ④ 的基础上修改：
- 小标题「你已等了 15 分钟」，标题按 distanceBucket 显示（通常是 `FAR`：「李明还没到集合点」/「他的手机在 1.8 公里外」）
- 圆盘区域换成一个 180pt 的等待环：从到达开始计时，环以 `gold` 缓慢填满，中心显示已等待的分钟数。**等待期间（<15 分钟）也要显示这个环**，放在圆盘下方一行小字「已等 11 分钟」，让用户知道 15 分钟这条线在哪里
- 先引导打电话：两列按钮里「打电话」排在第一个，并改成 `stateArrived` 底白字
- 提示句「结束后不算你的取消，时长不计入」→ `PrimaryButton`「结束等待」（替换「开始跑步」）

---

## ⑤ 完成 `completed`

画板：`Done.dc.html`

**NavBar**：（无返回）·「陪跑完成」· 求助

**头卡（`stateDone` 绿，居中）**
1. 并肩插图：陪跑员头像（60，白色实心，姓氏用 `stateDone`）与跑者头像（60，`runnerFill` + 2pt 白描边，外面再套一圈 2pt `stateDone` 做分隔）重叠 18pt，下方一条 `gold` 3.5pt 的弧形绳
2. 「你和李明第 4 次一起跑」`title2` 白色。第 1 次时改为「你和李明第一次一起跑」
3. 「5.12 公里 · 39 分 20 秒 · 深圳湾公园」15 `onNavyBody`。**不显示配速**

**跑者留言卡**（仅 `completion.runnerNote` 非空时显示，排在头卡正下方）：底 `warmCard`，圆角 24，内边距 18 / 20；「李明给你留了话」14 bold `warmCardTitle`；原文 17 / 1.6 `warmCardBody`，加中文引号。

**时长卡**：白色，时钟图标；「志愿服务时长 0.7 小时」16 bold + 标签「待认证」（13 bold，底 `blueTint`，字 `bluePressed`）；下方「从开始跑步算到结束陪跑。组织会在 10 个工作日内确认。」14 `inkSecondary`。

**文字按钮行**：「查看跑步记录」(`.link`) ·「上报问题」(`.neutral`)

**奖章**：只在本次真正解锁新奖章时，在时长卡上方插一行「解锁奖章 · {名称}」（绿色图标底 `successBg`）。没有新奖章时不显示。

**底部**：
- 有留言：`PrimaryButton`「回复李明」→ 打开一个底部输入面板（最多 60 字，提供 3 个快捷短句，如「谢谢你，下次见」）→ 发送后按钮变成「已回复」灰色不可点
- 没有留言：`PrimaryButton`「完成」
- 两种情况下，最下方都有 `TextButton(.neutral)`「完成」或「回到首页」→ 首页 A2

**读屏**：陪跑完成 → 你和李明第 4 次一起跑，5.12 公里，39 分 20 秒 → 李明给你留了话：…… → 志愿服务时长 0.7 小时，待认证，从开始跑步算到结束陪跑 → 查看跑步记录 → 上报问题 → 回复李明

---

## 跑者取消 `runnerCancelled`（v3 D4）

结构和文案沿用 v3，只替换视觉：
- NavBar 带求助（v3 这一屏没有求助入口；陪跑员可能已经在户外，本期加上，与全局规则一致）
- 头卡用 `stateAgreed`，`RopeView(state: .cancelled)`（见 03：绳子断开、跑者头像变灰）
- 标题「李明取消了这次陪跑」，副文「不算你的取消，不需要做什么」
- 如果陪跑员已经出发，副文后加一句「谢谢你特地赶过来。」，不承诺时长
- 主按钮「回到首页」

## 其他终止状态

过期、被抢先、已拒绝、陪跑员取消、结束等待：沿用 v3 现有页面，只替换设计常量和 NavBar。

---

## 动态字体与小屏

- 所有内容在 `ScrollView` 里，底部按钮区固定；在 iPhone SE（375×667）和 AX5 字号下都不能裁切任何按钮。
- AX 级字号下：主角数字最多放大到 1.4 倍（`.dynamicTypeSize(...DynamicTypeSize.accessibility2)` 作用在主角数字上）；三宫格和两列按钮改成竖排（`ViewThatFits` 或 `AnyLayout`）；引导绳保持原比例、宽度占满。
- 每个状态都要有 SE 尺寸 + AX3 字号的 Preview。
