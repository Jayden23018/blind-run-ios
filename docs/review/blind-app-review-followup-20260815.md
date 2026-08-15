# 盲人端 review 复核：2026-08-12 那份的必须项现在做到哪了

**日期**：2026-08-15
**范围**：只复核 [`blind-app-full-review-20260812.md`](./blind-app-full-review-20260812.md) §6 的清单，逐条对着 `origin/main` 重测。不重新走查、不新增结论。
**基线**：那份 review 的结论是「必须项 20 条达成 9 条」。
**方法**：`git grep` / `git ls-tree` 全部打在 `origin/main` 上（不是当前分支 —— 记忆 `verify-facts-on-the-work-line-not-the-feature-branch`）。

---

## 0. 一句话

**必须项 9 → 16 条。** 三天里主线合了 20+ 个 PR，把 review 第一批「纯前端、端点都在」的活基本做完了。

但复核本身挖出一个更值得记的东西：**review 里记成「已有在途 PR，别重复造」的那条，主线上根本没有 PR**。
下面 §2 单独说。

---

## 1. 必须项逐条

「M」编号沿用原 review §6 的表。证据一律是 `origin/main` 上的位置。

### 已解决

| # | 项 | 证据 |
|---|---|---|
| 8 | 文字放大至 AX5 不裁切 | `HighContrastText.swift:66` —— AX3 封顶已去掉，原处留了注释说明 |
| 9 | 对比度 ≥ 4.5:1 | `AppColors` 亮色模式重算；`blindRunTests/LowVisionChannelTests.swift` 按 WCAG 相对亮度公式验，含一条**验红**用例（把换掉之前的系统色喂进同一公式必须算出不达标） |
| 10 | 颜色不作唯一指示 | `differentiateWithoutColor` 0 → **10 处 / 4 文件** |
| 22 | 首次使用引导 | `BlindRunnerOnboardingView.swift` + `BlindRunnerHelpView.swift` |
| 27 | 常用 / 收藏地址 | `FavoritePlaceStore.swift`（纯本地 `UserDefaults`），接进 `BlindBookingView.swift:869`，排在搜索框**之前** |
| 28（部分） | 读评价 | `BlindOrderStatusView.swift:346` 接了 `GET /api/orders/{id}/reviews` |
| 30 | 行程可分享给家属 | `RunPlanLiveShare.swift` + `POST /api/orders/{id}/share`；同意书、停止分享、链接失效都在。测试 4 个文件 |

原 A 类「后端接口已就绪、前端零调用点」的 8 条里，`GET /reviews`、`GET /status-logs` 两条已接
（`BlindOrderStatusView.swift:346` / `:368`）。

### 应该项里也落了几条

| # | 项 | 证据 |
|---|---|---|
| 16 | 关键状态有触觉 | `blindRun/Core/HapticFeedback.swift`；`UINotificationFeedbackGenerator` 4 处 / 2 文件 |
| 18 | TTS 语速跟随读屏 | 走 `AVSpeechUtterance.prefersAssistiveTechnologySettings`（调研 `tts-rate-follows-voiceover-20260814.md`） |
| 31 | 约定结束时间 + 超时告警 | `plannedEnd` / 逾期相关 65 处 |
| 35 | 志愿者激励 | `VolunteerAchievements.swift`（服务次数 / 评分 / 称号）。原先那版「积分 +100/次」是客户端拿完成单数乘 100 显示的，后端从未下发过，已移除（`VolunteerHomeView.swift:1429`） |
| 36（一半） | 配速 | 采集有了（`BlindBookingView.swift:402` 配速偏好），**匹配算法仍是后端的事** |

### 仍未解决

| # | 项 | 现状 | 归属 |
|---|---|---|---|
| 26 | 历史订单可回看 | ❌ **主线零实现**，详见 §2 | 前端（PR #27 在办） |
| 29 | 通话不暴露真实号码 | ❌ `call/initiate` 前端 0 引用，**这是对的** —— 后端 `aliyun.private-number.enabled=false`，该端点返回 `NOT_AVAILABLE` 且响应体无号码 | **后端**（开通隐私号，运营动作） |
| 11 | 横屏与 iPad | ⚠️ `horizontalSizeClass` 仍 **0 命中**。只修了「横屏时装饰地图 300→140pt」（`verticalSizeClass` 4 处 / 1 文件）。iPad Pro 是发布验证两台设备之一 | 前端 |
| 28 | 对方身份可核验 | ⚠️ 接的是**本单**评价。志愿者的过往服务次数 / 评分只在志愿者**自己端**可见（`VolunteerHomeView.swift:1269`），盲人接单时看不到对方任何过往信息 | 两边（后端要给「按志愿者查」的聚合） |
| 6 | 内容变化后移动焦点 | ⚠️ `accessibilityFocused` 集中在 `BlindBookingView`（5 处）+ `SpeechService`（1 处），其余页面 0 | 前端 |
| 14 | 尊重 Reduce Motion | ⚠️ 3 个文件（`LoginView` / `BlindBookingView` / `ContentView`） | 前端 |
| 17 / 19 / 20 | 转子 / 盲文键盘 / Switch Control | ❌ 转子 0 命中；后两项从未验证 | 前端（后两项要真机） |
| 32 / 33 / 34 | 平台内消息 / 客服申诉 C 端 / 固定搭档 | ❌ 全部 0 | 前两个**后端先加端点** |

---

## 2. 复核挖出来的：被孤儿化的分支

原 review §3.2 的订正框写着「**已有在途实现，不要重复造**：PR #24（`feat/run-track-replay`）已加
`BlindRunHistoryView`，当前仍 open」。

复核发现这句今天不成立：

- `BlindRunHistoryView` 在 `origin/main` 上**不存在**，只存在于 `origin/feat/run-track-replay`
- 那条分支在主线仓库 `Jayden23018/blind-run-ios` 上**一个 PR 都没有**（`gh pr list --search` 空），
  且落后 `main` **88 个提交**
- 原因：那条 PR 开在**旧上游** `JerryZhao-1` 的 `integrate/swift-migration` 上。
  2026-08-12 主线切到 `Jayden23018` 之后（见 `AGENTS.md` §11「读后端仓库的那 5 条门禁在哪跑」），
  它就没人认领了。主线的 #24 是另一件事（`fix/block-tel-dial-in-ui-tests`）

**代价不止漏一个功能**：`docs/pre-launch-checklist.md:81` 把「跑后轨迹总结与历史记录」连同
「PR #24 已合」一起列进了演示视频**「可以放心拍」**的表；`AppState.swift:267` 的注释也指着这个 PR。
照着拍会拍到不存在的页面。

同一批被孤儿化的还有 4 条远端分支，本轮逐条判活：

| 分支 | 领先/落后 | 判定 |
|---|---|---|
| `feat/run-track-replay` | +2 / −88 | **活** → PR #27（合入主线，唯一冲突是研究索引并行加行） |
| `docs/user-manual-and-technical-overview` | +3 / −103 | **活** → PR #29。⚠️ 合之前发现文档本身陈旧且有一处**写错**（§5.6 写「+100 积分、积分商城即将上线」），同 PR 一并修 |
| `docs/demo-runbook-research` | +5 / −74 | **活** → PR #28（腾讯会议双真机同屏演示调研，与主线已有的 `demo-video-production-20260814.md` 不重叠） |
| `chore/sync-backend-contract-drift` | +1 / −117 | **死** —— 其核心内容（Mock 语音日期「认输」守卫）已由后来的提交重新落在主线（`MockAPIClient.swift:2208/2320`），合回去只会产生重复与冲突 |
| `chore/dedupe-verify-commands-into-skill` | +2 / −140 | **死** —— 三处冲突里主线版本全是更新的口径（`guard.mjs` 死引用已修、Stop 钩子已从「工作树脏」改成「本轮写过的文件」、§11 已从命令清单长成含判据的一节）。前提不成立了，要做得重做而不是合 |

**已落成机器检查**（`AGENTS.md` §1.3）：SessionStart 钩子新增一条「有独有提交却长期没跟进的远端分支」
（领先 `origin/main` 且落后 >30），只用 git 不打网络。见 PR #30。

---

## 3. 另一类欠账：openspec 变更不归档

未归档变更 9 → **12** 个。新增的 3 个正是本轮上线的功能：

| 变更 | 未完成 |
|---|---|
| `share-run-plan-with-emergency-contacts` | 9 |
| `replace-placeholder-points-with-service-recognition` | 6 |
| `surface-planned-end-and-overdue-alert` | 2 |

功能已经在主线跑了，tasks 没勾、没归档。最落后的仍是 `capture-and-gate-runner-extra-needs`（22 项未完成）。

---

## 4. 本次复核没做的（诚实标注）

- **没跑任何真机测试**。设备锁屏，`scripts/device-test.sh` 硬失败退出（这是 `deviceprep -3`，不是代码问题）。
  PR #27 合入前必须补 `blindRunTests/LiveEscortTrackTests`
- **没重测对比度数值**，沿用 `LowVisionChannelTests` 的断言，未用 Accessibility Audit 实测
- **横屏 / iPad 仍是 grep 计数推论**，与原 review 同一局限
- **志愿者端没有走查**，与原 review 同一局限
