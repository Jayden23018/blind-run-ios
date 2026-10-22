# 求助「已发出」之后那一屏：别的安全产品放了什么（2026-10-22）

**为什么查**：盲人端屏 3b（`EmergencyCountdownView`）在标题和一段字下面堆了 4 个一样大的通栏按钮，负责人 2026-10-22 评「按钮太多、不好看、不好用」（Jayden23018/blind-run-ios#506）。仓库里的设计包 `docs/ui/mockups/running-state/` 只画了求助中心，没画这一屏。

**怎么查的**：一个调研 subagent，WebSearch 每个产品 2–3 种说法（中英文），打开官方帮助页原文；WebFetch 打不开的（Life360、support.apple.com/102262）改用 firecrawl 抓原文。查阅日期全部 2026-10-22。

**先说限制**：7 个产品里，**没有一家的官方页面描述了「报警已发出」那一屏的版式**。能确认的是各家的**动作结构**（有哪些动作、取消怎么做、联系人怎么通知），不是像素。要像素只能装 App 实机截图。

## 结论

1. **按钮数**：能确认的最多 3 个动作 —— Google Safety Check 到点提醒（I'm OK / Start sharing now / Call 911）、Apple Watch 跌倒检测（Close / I'm OK / Emergency Call 滑块）。**没有一家资料显示有 5 个并列大按钮。**
2. **联系人由系统自动通知，不在这一屏逐个拨**：Apple（通话结束后自动短信）、Life360、Google、Uber（客服联系不上时找紧急联系人）、滴滴（自动短信给紧急联系人）。
3. **报警电话是一个明确的主按钮**：Uber「Call 911」、滴滴「呼叫110」（2018 年二手实测，红色主按钮）、Google「Call 911」。Apple 的这一屏本身就是通话。
4. **取消都要刻意**：Life360 滑块、Apple Emergency Call 滑块 / 松开按键、Noonlight 4 位 PIN。没有一家是和其他动作一样大的普通按钮（Apple Watch 倒计时里的 Cancel 除外）。已拨通的紧急通话都不能在 App 里「取消」，只能向接线员说明。
5. **取消后会补发「我安全了」**：Life360（20 分钟内）、Google（结束共享再发一条）、Apple（通话后问是否仍发短信）。与我们后端 `FALSE_ALARM` 补发解除短信一致。
6. **「求助进行中又按了一次」**：所有产品都**查不到文档**。我们的处理（#501：并入同一条、说清没有新建）是自己的设计。

## 各产品要点（详表见调研 agent 原文，下面只留可复核的）

| 产品 | 已发出后的动作 | 取消方式 | 这一屏有没有直拨 | 来源 |
|---|---|---|---|---|
| Noonlight | 未找到（官网图 alt：「help is on the way」） | 松手后输 4 位 PIN | 未找到；调度员先短信再来电 | help.noonlight.com/en/articles/2114600 |
| Life360 SOS | 倒计时屏只有一条滑块；之后未找到 | 向左滑；已发出 20 分钟内取消会补发「安全」 | 未找到 | support.life360.com/hc/en-us/articles/23053474049687 |
| Apple iPhone 紧急 SOS | 这一屏就是紧急通话 | 倒计时松开；通话中向接线员说明 | 屏幕即通话 | support.apple.com/guide/personal-safety/…ips4f0cd709b |
| Apple Watch 跌倒 / 车祸检测 | Close、I'm OK、Emergency Call 滑块 | I'm OK / Close；倒计时 Cancel | 用滑块拨出 | support.apple.com/en-us/108896、/104959 |
| Google Personal Safety | Safety Check：I'm OK / Start sharing now / Call 911 | I'm OK；共享中 Stop → Stop sharing | 有 Call 911 | support.google.com/android/answer/9319337 |
| Uber | 安全工具包里「Call 911」 | 未找到 | 有 | uber.com/us/en/newsroom/emergencybutton/（2019） |
| 滴滴（二手，2018） | 报警页红色「呼叫110」，下方小字说明发给紧急联系人 | 未找到 | 有 | nbd.com.cn/articles/2018-09-19/1256482.html |

无障碍规范：WCAG 4.1.3 状态消息（状态变化要能被读屏播报而不抢焦点）—— 我们的做法是 TTS 播报 + 标题元素带状态；Apple HIG 警示框（破坏性操作要有取消、按钮用具体动词）。**AppleVis 上盲人用户谈 SOS 的一手帖子：未找到。**

## 落到本仓库

负责人 2026-10-22 据此批准的新版（#506）：一个主按钮「拨打120」；110 与紧急联系人收进一个「打 110 或紧急联系人」；撤销降为底部弱化文字按钮（64pt、仍二次确认）；标题下显示发出时间；再按一次时加两行时间线。

## 复核触发条件

- 装了上述任一 App 拿到「已发出」屏的实机截图，且与上表矛盾。
- Apple / Google 的官方帮助页改了跌倒检测或 Safety Check 的动作集合。
