# Review 索引

本仓库**所有**成体系的 review（前后端对齐、功能缺口、无障碍审计、发布前复核）的唯一落脚点。
规则与 `docs/research/INDEX.md` 同构，只有三条：

1. **开新 review 前整份读这个文件**，不要 `ls | grep` —— `ls` 只匹配文件名，搜「无障碍」命中不了
   `frontend-backend-alignment-review-20260812.md`；能搜到的词在下面「范围」和「一句话结论」两列里。
2. 上一份的结论还作不作数，看「复核触发条件」那列。**没触发就直接引用，不要重新审一遍。**
   触发了、或表里没有这个范围、或有但缺你要的那一段 —— 才开新一轮。
3. review 完落盘到 `docs/review/{topic}-{YYYYMMDD}.md`，**并回写下面一行**。
   不回写等于没做：下次找不到，同一份 review 会被原样重跑。

**与 `docs/research/` 的分工**：research 记「外面是怎么做的」（联网事实，带来源与核实日期）；
review 记「我们做成了什么样」（对着代码与契约的判断，带 `文件:行号`）。一次 review 引用一次 research 是常态，
反过来不成立 —— 不要把竞品事实写进 review，会漂移。

> 与 research 不同，这里**没有 hook 强制**。`scripts/hooks/research-log.mjs` 只管联网调研。
> 若这条规则被漏过第二次，按 `AGENTS.md` §1 把它落成守卫，别再加一段文档。

| 日期 | 范围 | 一句话结论 | 复核触发条件 | 报告 |
|------|------|-----------|-------------|------|
| 2026-08-12 | 前后端契约对齐：错误码、语音语料、坐标、枚举、字段级漂移 | 逐条对撞后端 `origin/main` 契约；期间因未 `git fetch` 误判两次（删过一份正确的语料镜像、报过一个不存在的 `blindPhone` 缺陷），§B1 记录了这个坑 | 后端契约有 breaking change；前端新增调用后端端点；`scripts/validate-*.mjs` 任一条红 | [frontend-backend-alignment-review-20260812.md](./frontend-backend-alignment-review-20260812.md) |
| 2026-08-15 | 复核上一行那份：必须项现在做到哪了 + 被孤儿化的分支 | 必须项 **9 → 16 条**（首次引导 / 常用地址 / 行程分享 / 读评价与状态流水 / 对比度 / Dynamic Type / 触觉 / TTS 语速 / 超时告警 / 服务认可都已落主线）。仍缺：历史订单入口（前端，PR #27 在办）、隐私号（阻断在**后端**开通）、iPad 横屏（`horizontalSizeClass` 仍 0）、志愿者过往评价对盲人不可见、转子 / Switch Control / 盲文键盘。⚠️ 复核挖出的更重要的事：**上一行里「已有在途 PR #24」是旧上游的编号，主线切换后那条 PR 被孤儿化了** —— `BlindRunHistoryView` 主线零实现却被上线检查单列进「可以放心拍」。同批 4 条分支已逐条判活（2 活 2 死），并落成 SessionStart 报警（PR #30） | PR #27 合入后（历史订单一节作废）；隐私号开通后；iPad / 横屏开工后；再有一次主线仓库迁移 | [blind-app-review-followup-20260815.md](./blind-app-review-followup-20260815.md) |
| 2026-08-12 | 盲人端完整 review：功能缺口（vs 同类产品）、无障碍适配、全流程顺畅度、前后端职责划分 | VoiceOver 通道做得比多数同类产品深（284 label / 遍历序刻意设计），但**必须项 20 条只达成 9 条**。⚠️ **报告含当天订正，引用前先读 §0 的订正框**：三条 P0/P1 的缺陷判断都成立，但① 拨号的修法写错了（隐私号端点今天返回 `NOT_AVAILABLE`、无可拨号码，阻断在后端开通）② 「AX3 够不到 200%」是错的（AX3≈235%）③ 历史订单已有在途 PR #24。低视力视觉通道那三项本轮已修其中三块（对比度、Dynamic Type 封顶、横屏地图 + 触觉）。**2026-08-15 起 §7「第一批」只剩隐私号一项**，其余六项均已落地（历史订单收全部终态、点击落到订单详情，见 §3.2 补记） | 隐私号开通后；`openspec/changes/` 有变更归档；盲人端信息架构改动 | [blind-app-full-review-20260812.md](./blind-app-full-review-20260812.md) |
| 2026-08-22 | 7 条长红真机 UI 测试的归因：是不是 `feat/intro-call-ui`（PR #67）改的、各自从哪个提交开始红 | **都不是 PR #67 的锅** —— 同一组 `-only-testing` 在 `origin/main` 上 7/7 同样红、文案逐字相同。由 5 个已合入 main 的提交造成（`be4e030` 08-13 / `30b0770`+`c3e692a` 08-14 / `c46da3c`+`9f9cede` 08-15 / `f404de2` 08-21），其中 3 个**完全没动 UI 测试**、2 个动了但各漏一处，全部通过 CI —— 因为本仓库 CI 跑不了 XCTest。6 条是用例陈旧（被断言的 UI/文案/identifier 已被刻意改掉），**第 7 条 `testBlindHomeRemainsInteractive…` 是真缺陷**：盲人首页「重复当前状态」滚不进可视区、触点被钳到常驻求助条上，真机会真的拨出 110；二分定位到 `c3e692a`（PR #22）。另记一个方法论坑：`30b0770` 当时用**修复前的基点** stash 对照，把自己引入的回归判成了「既有缺陷」 | 上述 7 条任一被修；`AGENTS.md` §8「接单后展示完整手机号」与 `f404de2` 的掩码行为拍板；CI 获得真机 XCTest 通道 | [ui-test-red-triage-20260822.md](./ui-test-red-triage-20260822.md) |
| 2026-08-26 | 近期变更（`1c9bc20`→`5bb8cd4`）的内容/决策/理由 + 下单全链路（表单 / 语音 / 零输入三条路径）逐层核查：静默失败、漏情况、硬编码占位 | 三条主线：`PENDING_INTRO_CALL` 接单前通话（PR #67）、派单推送带 `requiresIntroCall`（PR #77，**当前分支未合**）、SPEC-E 激励体系（PR #76）。下单三路径共用同一个 `submit()` 与同一份五道门槛，架构上是对的。**8 条新问题**（其中 §3.5 是写报告时被 pre-push 契约漂移闸抓出来的，不是读代码读出来的：后端已上线 `introCallOrderId` 解决「志愿者杀进程就回不到通话页、只能等 20 分钟窗口超时而盲人在等他」，而手写模型 `VolunteerDispatchSummaryResponse` 没这个字段，端点却一直在调 ⇒ 字段到了被静默丢弃；这正是 PR #77 正文里挂着「等后端答复」的那条）：P0 一条 —— 通话数据 `try?` 拉失败即 `introCall = nil`，而 `introCallSection` 靠 `let` 拆包卡住 ⇒ 整块操作区不渲染、无错误、而播报仍在叫盲人「可以打个电话聊聊」（`IntroCallCopy.loadFailed` 只在按下那个没渲染出来的按钮时才播）。P1 三条：② 没说时长时 `plannedEndTime` 静默写死 `+3600`，而复核页明说「未填写」，后端据它 `+15min` 发 `ORDER_OVERDUE`、`+60min` 自动完成，零输入路径最惨且该分支零测试；③「缺 `requiresIntroCall` 不是静默降级」这句话只在 DEBUG 成立（唯一渲染点在 `#if DEBUG` 里）；④ 401 在下单/接单/语音确认三处全静默，而同一个 `LoginViewModel` 里其余 5 条错误都 `speakError`。P2 两条：邀请码非法时静默丢弃且一次性不可补；「不得承诺优先派单」的红线自己破了一处**并被测试钉住**。另附 §4「查过了不是问题」五条（113 处 `try?` 逐条过、41 处「写死」全是解释性注释、`prefersServerMessage` 已不存在）。⚠️ **真机 XCTest 一条都没跑**（两台设备 `unavailable`），全部结论来自读代码 + 契约对撞 | §3 任一条被修；后端改 `requiresIntroCall` 必填性或 `PENDING_INTRO_CALL` 窗口语义；`plannedEndTime` 的 `+15min`/`+60min` 口径变化；下单三路径任一信息架构改动；CI 获得真机 XCTest 通道 | [booking-flow-and-recent-changes-20260826.md](./booking-flow-and-recent-changes-20260826.md) |
| 2026-08-20 | 前端全仓审计：传输安全、位置真实性、跑步中突发情况兜底、盲人与志愿者互信 | 12 条新问题，与前三份 review 零重叠。P0 三条：① 明文 HTTP/WS + JWT 放在 URL query + 24h 不刷新，同一 WiFi 抓一次包拿走整个账号；② 陪跑位置的「15 秒内」测的是**转发时刻**不是采样时刻，而发送端会无限重发陈旧样本，两端都不告警；③ `pausesLocationUpdatesAutomatically` 在 EN_ROUTE/ARRIVED 保持系统默认 true 且未实现 didPause 回调，in-use 授权下一次自动暂停即断到 App 重启（Apple 原文已核实）。P1 还有：登出不解绑 APNs（上一个人的求助推送会被念出来）、常用地址明文落 UserDefaults 且登出不清、401 即硬登出对进行中订单零保护、云端求助失败后没有可按的拨 110、盲人拿不到志愿者姓名/评分/认证（契约无 `volunteerName`）、到达后无方位信息。另附 §0「查过了不是问题」三条，防止下轮重提 | 后端上 TLS / 加 refresh token / 补 `capturedAt` 或 `volunteerName` 任一落地；`LocationService` 或 `LiveEscortSessionCoordinator` 有改动；登出流程有改动 | [frontend-audit-20260820.md](./frontend-audit-20260820.md) |
