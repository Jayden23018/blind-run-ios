# 前后端对齐与前端全量 review — 2026-08-12

**分支** `chore/research-log-index`（领先工作线 `origin/integrate/swift-migration` 15 个提交）
**范围** 前后端契约对齐 / 未适配的后端能力 / UI 与无障碍 / 「列了但没做」的功能
**方法** 全部只读核查。后端事实取自 `/Users/mac/Downloads/demo` 的 `docs/api_spec.yaml`
与 `src/main/java/**`，前端事实取自本仓库源码，每条都给了可复核的 `文件:行号`。

> ⚠️ **方法上的一个坑，读本文时要知道**：核查当时后端工作区停在特性分支
> `feat/voice-query-intent`（领先 `origin/main` 2 个提交），所以**工作区的 `api_spec.yaml`
> 比 `origin/main` 多东西**。凡是判断「后端有没有某能力」，都要用
> `git show origin/main:docs/api_spec.yaml` 而不是直接读文件 ——
> A3 初稿就是踩了这个坑（已订正）。本文其余各条已复核过取自 `origin/main`。

> 本文件是**代码 review 报告**，不是联网调研。按 `AGENTS.md` §12，`docs/research/` 只收联网调研，
> 不要把本文件登记进 `docs/research/INDEX.md`。

---

## 结论先行

**没有完全对齐。** 契约层有 2 个会在真机上静默失效的缺陷，4 类后端已交付而前端零接入的能力。

无障碍**架构**做得好——遍历顺序解耦、地图隐藏、「重复当前状态」全覆盖、二次确认文案逐字锁定。
但颜色对比度、横屏/iPad、Dynamic Type 上限三块基本空白，且**三者精确落在同一个用户段：低视力用户**。

「列了没做」高度集中在一处：**真机端到端验证一次都没跑过。**

---

## A. 前后端契约对齐

### A1 · 高 · `blindName` / `blindPhone` 是前端凭空声明的字段，真机上恒 nil

前端 `blindRun/Core/Models/OrderModels.swift:318-319` 声明 `blindName: String?` / `blindPhone: String?`。

后端两处独立证据都说它们不在该 DTO：

- `demo/src/main/java/com/example/demo/dto/OrderDetailResponse.java` —— 26 个字段里没有这两个
- `demo/docs/api_spec.yaml` —— `blindPhone` 全仓 **0 命中**；`blindName` 只出现在**另一个** schema
  （`:4337`，志愿者派单摘要用的 ActiveOrder），且那里配的是 `blindPhoneMasked`（`138****0001`，脱敏、不可拨）

已核对 `demo/src/main/java/com/example/demo/controller/OrderController.java:187-192`：
`GET /api/orders/{id}` 返回的确实是 `OrderDetailResponse`。
`blindName` 在后端只存在于 `VolunteerDispatchActiveOrder.java` / `VolunteerDispatchRecentOrder.java`。

因为是 Optional，解码不会失败，只是解出 nil。后果分两档，**第二档是硬失效**：

**`blindName` —— 时有时无（取决于这个 `OrderDetailResponse` 是解码来的还是转换来的）**

| 位置 | 数据来源 | 行为 |
|---|---|---|
| `VolunteerHomeView.swift:1370` `VolunteerCurrentOrderCard` | `:528` 派单摘要转换 `active.orderDetail` | **有名字**（`VolunteerDispatchSummaryModels.swift:151` 透传）|
| 同上 | `:206/:214` 来自 `GET /api/orders/{id}` | **nil** → 同一张卡刷新前后名字会闪 |
| `VolunteerHomeView.swift:1538` `VolunteerRecentOrderCard` | `VolunteerDispatchSummaryRecentOrder` | **有名字**，契约支持 ✅ |
| `VolunteerOrderFlowViews.swift:2241/:2501` 接单后详情 | `GET /api/orders/{id}` | **恒 nil** → 恒回退成「盲人跑者」|
| `blindRun/Map/MapViewModel.swift:96` | 同上 | 地图标注副标题恒 nil |

**`blindPhone` —— 全路径恒 nil，无一例外**

派单摘要那条**显式传 `nil`**（`VolunteerDispatchSummaryModels.swift:152`，因为后端只给
`blindPhoneMasked` 脱敏值）；`GET /api/orders/{id}` 那条解码得 nil。
于是 `VolunteerOrderFlowViews.swift:402` 的 `canShowPhone` 恒 `false`，
`:2638` 传进 `VolunteerBlindRunnerInfoCard` 的 `showPhone` 也恒 `false` ——
**志愿者接单后一次都打不了盲人电话。**

**违反 `AGENTS.md` §8「接单后展示完整手机号」。** 对一对一陪跑，志愿者在集合点找不到人
却没有任何方式打电话，是**安全相关**的失效，不只是体验问题。

**Mock 把它完全盖住了**：`blindRun/Core/MockAPIClient.swift:2424-2425` 写死了「李明 / 13800001001」，
所以每一条 Mock 测试都是绿的 —— 正是 `AGENTS.md` §1 说的「制造假信心」。

方向性事实：后端**从设计上就不打算**给未脱敏号码。真正的通道是
`POST /api/orders/{orderId}/call/initiate`（隐私号中转，
`CallInitiateRequest { callerRole: BLIND_USER | VOLUNTEER }` 双向对称）。前端对该端点 **0 命中**。

### A2 · 高 · `addressShort` / `endAddressShort` 没接，语音读回念的是完整门牌地址

后端 `api_spec.yaml:2949-2960`（2026-08-09 新增）在字段描述里逐字写着：

> `address` 的**朗读形态** —— 只有 POI 名，不含门牌号与步行指引。
> **自己拼读回文案时念这个，不要念 `address`。**

前端对 `addressShort` / `endAddressShort` **0 命中**
（`blindRun/Core/Models/VoiceOrderModels.swift` 的 `ParseVoiceOrderResponse` 未声明）。

于是读回念的是后端举的那个反例原文
`五角场市场监督管理所 国定路335号1号楼4层(国权路地铁站4号口步行110米)`，
而不是 `五角场市场监督管理所`。

读回存在的唯一意义是让盲人听出「这不是我说的地方」，他能靠听分辨的是**名字**。
这个字段就是为了修这件事加的。

### A3 · 中 · 「问一句」的后端第 2 档 —— **后端还在做，没合并，现在不能接**

> ⚠️ **本条初稿写错过，已订正。** 初稿说「后端已交付、前端零接入」，
> 依据是工作区 `api_spec.yaml` 里有 `/api/orders/voice/classify-query`（`:922-937`）。
> 但那份 spec 取自后端**特性分支** `feat/voice-query-intent` 的工作区，**不是 `origin/main`**：
>
> ```bash
> git show origin/main:docs/api_spec.yaml | grep -c "classify-query"   # → 0
> ```
>
> 这正是记忆 `verify-facts-on-the-work-line-not-the-feature-branch` 说的那类错。

事实：

- 两个提交都**未合并**（`origin/main..HEAD`）：
  `e747206`「加后端意图分类兜底」、`0bf8cd8`「C 档改占位符 —— 模型只生成句式，真值不出后端」。
- **契约今天还在变形。** `0bf8cd8`（2026-08-12 16:36）把 `ClassifyQueryResponse` 从 1 个字段
  改成 2 个：除 `intent` 外新增 `template`（nullable，**只有 `intent=DISTANCE` 才可能有值**，
  其余四类恒 `null`），形如 `{{VOLUNTEER}}离你还有{{DISTANCE}}，预计{{ETA}}到`，
  三个占位符由客户端用本地数据填 —— 也就是说**真值不出后端，模型只出句式**。
  同批把校验从「数字查白名单」收紧成「输出里一个数字都不许有」。
- `intent` 用 `anyOf [enum, string]` 建模成**开放枚举**，符合本仓库「未知枚举值不许整条崩」那条红线。

**结论：现在接入 = 原样重演 N48 那次的错。** handoff 2026-08-10 前端自己写过
「我们这一批是照着你们还没合并的分支写的……你们合并前如果改了任何一处，告诉我们一声」——
而这次后端**已经**改了（1 字段 → 2 字段 + 设计方向从「模型组合问答」转向「占位符」）。
**接入应当等 `feat/voice-query-intent` 合进 `origin/main` 之后再开工。**

仍然成立、且与合并无关的一条：前端 `blindRun/Voice/VoiceStatusQuery.swift:10-11`
拒绝后端 NLU 的理由是

> 后端 `/api/orders/voice/parse` 在生产上恒 404 …… 按它写完，盲人拿到手的是一个恒报错的按钮。

这条理由针对的是**另一个端点**。留着会误导下一个人，无论 classify-query 何时合并都该改掉。

### A4 · 中高 · `NO_VOLUNTEER` / `PENDING_MATCH` 的「继续等」没有出口

后端两个对称端点（spec `:235-293`）：

- `PUT /api/orders/{id}/keep-waiting` —— `PENDING_MATCH` 下刷新匹配超时窗口，避免兜底取消
- `PUT /api/orders/{id}/keep-rematching` —— `REMATCHING` 下同理

前端对两者 **0 命中**。`.noVolunteer` 在 15 处都与 `.cancelled` / `.completed` 归为同一组当终态
（`blindRun/Core/Models/OrderDisplayHelpers.swift:15`、`blindRun/Core/Models/OrderModels.swift:69`、
`blindRun/Core/Models/OrderTrackModels.swift:57` 等）。

后端会推 `ORDER_CANCELLATION_WARNING`，前端 `blindRun/Core/AppRealtimeCoordinator.swift:1075-1076`
明确把它划为「不改订单状态」→ 走通用分支念出来，**但没有任何可操作的出口**。
盲人听到「订单即将被取消」，唯一能做的是重新下单。

**前端自己知道少了这块的证据**：`blindRun/Core/Models/ErrorModels.swift:20` 映射了
`KEEP_WAITING_LIMIT_REACHED` —— 而这个错误码只有调上面两个端点才可能收到。

### A5 · 中 · 位置上报只有 WebSocket 一条路，REST 兜底端点没接

真实上报全部走 `WebSocketService.sendLocationUpdate`
（`blindRun/Core/LiveEscortSessionCoordinator.swift:253`、
`blindRun/Volunteer/VolunteerLocationReporter.swift:16`、`blindRun/ContentView.swift:411`）。

`/api/blind/location` 只在 `blindRun/Core/MockAPIClient.swift:372` 出现；
`/api/volunteer/location` 生产代码 0 命中。

有 generation 隔离的重连逻辑，但没有 REST 降级。`IN_PROGRESS` 期间 WS 长时间起不来
（后台、弱网），位置流就完全断了 —— 而 `ESCORT_SIGNAL_LOST` 正是后端为这个状态准备的告警。
**值不值得接是产品判断，但目前没人记录过为什么不接。**

### A6 · 中 · `CreateOrderRequest` 少三个字段

后端有、前端 `blindRun/Core/Models/OrderModels.swift` 没有：
`paceMinSecondsPerKm`、`paceMaxSecondsPerKm`、`plannedDistanceMeters`。

后果是**按距离的预约表达不出来** —— 「陪我跑 5 公里」只能折成「跑多少分钟」。
语音向导抽的三个槽位也只有起点 / 时间 / 时长。

---

## B. 工作树与门禁状态（本轮已处理）

### B1 · 高 · **五道后端契约门禁默认对着「后端当前签出的那个分支」验，不是契约** ⚠️

**这条是本轮最值得落地的发现，而且我自己先踩了一次，过程留在这里当证据。**

`blindRunTests/VoiceOrderWizardTests.swift` 有一份 +25/-1 未提交改动，新增 7 条冒号形语料镜像。
`node scripts/validate-golden-corpus.mjs` 报「7 条在后端语料里已不存在」，
`git log -S"_asr_date_rendering_note"` 也查不到它引用的 note key ——
**两个信号都指向「这份改动是编的」。两个信号都是假的。**

真相：

- `scripts/validate-golden-corpus.mjs:26` 读的是 `../demo/docs/voice-golden-corpus.json`，
  即后端仓库的**工作区文件**。当时后端签出在特性分支 `feat/voice-query-intent`，
  该分支从 PR #55 合并**之前**切出，工作区语料 **96 条**，
  而 `origin/main` 已经是 **101 条**。
- 多出来的 5 条正是那份改动加的：`8月10号早上8:00跑步`、`下周三早上8:00跑步`、
  `这个月底下午3:00`、`第三天早上8:00`、`隔天8:00`。**它是对的。**
- `_asr_date_rendering_note` 确实存在于 `origin/main`（commit `9c92568`），
  `_crosscheck_note` 见 `9aef7df`。我先前的 `git log -S` **没带 `--all`**，
  只走了那条陈旧特性分支的历史，所以查不到。

对着真契约重验才是准的：

```bash
git -C ../demo show origin/main:docs/voice-golden-corpus.json > /tmp/corpus-main.json
node scripts/validate-golden-corpus.mjs /tmp/corpus-main.json
```

→ `通过：101 条全部与前端镜像一致`（保留 5 条、移除下面那 2 条之后）。

**7 条里真正没有契约支撑的只有 2 条**：`下月10号早上8:00`、`三天后早上8:00`
（非 null 期望值那一对）。`origin/main` 语料里查无此条，已移除并投 handoff 请后端补。

**为什么这不是「注意一下」而是要落地的缺陷**：

- 受影响的是**全部五道读后端仓库的门禁**（spec-coverage / golden-corpus / error-codes /
  voice-intent-words / 生成代码比对），它们统一读工作区路径，
  **后端同事切到任何分支，我们的门禁结论就跟着变，而且不报警**。
- 唯一的防线是 pre-push 里的漂移检查（`scripts/install-git-hooks.sh:71-91`，
  `git -C "$BACKEND_DIR" diff --quiet origin/main -- "$f"`），
  但它**只在 push 时跑**。日常直接 `node scripts/validate-*.mjs` 完全不经过它 ——
  于是「我跑了门禁，绿的」这句话在日常开发里是没有保证的。
- 它制造的是**方向最坏的那种错误**：把正确的改动判成伪造。本轮我据此 revert 掉了一份对的改动
  （靠事先存了 `git diff` 才救回来）。

**建议**（走 `AGENTS.md` §1.1，本轮只记录不实现）：让这五个脚本默认就从
`git show origin/main:<path>` 取，工作区路径退化成显式 opt-in（对应 PR #16 的方向）。
在那之前，**手动跑门禁时要自己导出 `origin/main` 的副本再传进去**。

> 记忆 `prepush-contract-gate-reads-backend-worktree` 说「PR #16 已修掉，3 份契约统一
> `git show origin/main` 取」—— **PR #16 至今仍是 open 状态**（见 B2），工作线上的钩子
> 还是漂移检测那一版。该记忆已按本轮事实订正。

### B2 · 中 · 7 个 PR 挂着没合，最老的开了 11 天

| PR | 开启日 | 分支 |
|---|---|---|
| #2 | 08-01 | `integrate/swift-migration`（SOS 交付 + 解除志愿者注册死锁）|
| #3 | 08-06 | `integrate/swift-migration`（语音下单真机手测五轮缺陷修复）|
| #14 #15 #16 #17 | 08-09 | 各自特性分支 |
| #18 | 08-10 | `feat/voice-cross-turn-correction` |

**全部 `MERGEABLE`，没有冲突。** #2 / #3 的 head 就是工作线本身。做完的东西没落地，等于没做。

### B3 · 中 · 8 个 openspec 变更未归档，46 条任务未完成

`enable-independent-sos-safely` 与首页 SOS 条 delta 同一个能力的冲突，
`.claude/state.md` 2026-08-04 就记了，至今未决。

---

## C. 「列出来了但没有实际执行」

这一类高度集中，根因只有一个：**真机验证通道一直没打通。**

- **C1 · 真机端到端语音联调，一次都没做过。** handoff 原话：「上面全部走 Mock 与 stub，
  验的是状态机和文案，**不是识别质量**」。未勾条目：
  `enable-one-utterance-booking` 1B.7 / 5.5；
  `enable-cross-turn-voice-correction` 5.4 / 7.5 / 7.6 / 7.7；
  `disambiguate-same-name-start-place` 6.3（「第二个」这三个字能不能被 `SFSpeechRecognizer`
  稳定渲染成汉字，只有真人说了才知道）；
  `capture-order-end-location` 6.6（起终点会不会被抽反）；
  `capture-and-gate-runner-extra-needs` 5.6。
- **C2 · UI 测试本轮从未跑成。** `capture-order-end-location` 6.5 与
  `enable-independent-sos-safely` 8.8 都记着同一原因：设备走网络配对，runner bootstrap 时
  `Lost connection to testmanagerd`（记忆 `ui-test-runner-needs-usb-not-wifi` 里 code 74 的签名，插 USB 可解）。
- **C3 · SOS 云端链路在真实环境里一次都没端到端验过。** `enable-independent-sos-safely` 6.4：
  「触发真实 SOS 会给紧急联系人发真短信并惊动客服，不能拿测试账号随便打；需要与后端约定演练时间窗」。
  6.2a（后台/锁屏触发）、6.6（真机批跑）同样未做。
  **这是全 App 风险最高的路径，验证等级停在「编译通过 + Mock 绿」。**
- **C4 · `capture-and-gate-runner-extra-needs` 实质停摆。** 33 条任务里 22 条未完成，
  且卡在最前面：1.1「投 handoff 问自由文本需要一个接单后才下发的通道」——**这条投递本身就没做**。
  3.1~3.5 的实现全部未开始，`blindRun/Core/MockAPIClient.swift:1317` 的
  `mockVoiceSpecialNotes` 至今恒返 `nil`。
- **C5 · 生产水位线从未核实。** 见 §F.1。
- **C6 · 积分商城是硬编码占位。** `blindRun/Volunteer/VolunteerOrderFlowViews.swift:1713-1750`：
  积分显示 `Text("--")`，4 个商品写死在数组里，`VolunteerPointsViewModel` 只有一个 `errorMessage`
  和一个空的 `configure`，没有任何数据获取。入口在
  `blindRun/Volunteer/VolunteerHomeView.swift:1264`。文案「即将上线」是诚实的，列出只为清单完整。

---

## D. UI 与无障碍

**先说做到位的**（不然这份报告会给出错误印象）：盲人端遍历顺序与视觉顺序解耦、
地图 `accessibilityHidden(true)` + `allowsHitTesting(false)`
（`blindRun/BlindRunner/BlindOrderStatusView.swift:771-772`）、「重复当前状态」四个盲人页全覆盖、
Magic Tap 全屏 SOS、二次确认文案逐字锁定、主按钮用 `@ScaledMetric` 而非固定值 ——
这些都是对的，而且注释写清了为什么。

**贯穿三块空白的一件事**：它们精确落在同一个用户段 —— **低视力用户**，
而这个段在数据模型里是一等公民：`VisionLevel.lowVision = "LOW_VISION" / "低视力"`
（`blindRun/Core/Models/ProfileModels.swift:397/402`），还挂在订单上传给志愿者
（`blindRun/Core/Models/OrderModels.swift:329`）。

全盲用户走 VoiceOver 通道，那条做得很好。低视力用户走视觉通道，**那条从没被系统性验收过**。
代码自己也这么说 —— `blindRun/BlindRunner/BlindRunnerHomeView.swift:421-422`：
「这块面积对全盲用户没有点击收益 …… 它服务的是低视力用户和没开读屏的用户。」

**所以这不是三笔零散 UI 债，是一整条用户通道没人管。**

### D1 · 高 · `HighContrastText` 名不副实，且 `.status` 用的是四色里对比度最低的

`blindRun/Core/DesignSystem/HighContrastText.swift` 的 docstring 写
「高对比度文本组件，确保在深色/浅色模式下可读性」，实际只做两件事：
挑一个系统语义色 + **把** Dynamic Type **封顶**。没有任何对比度增强逻辑。

更要紧的是 `:30`：`.status` 这一档（订单状态文字，低视力用户最需要看清的那一行）
用的是 `AppColors.primary` = systemBlue，浅色模式对白底 **≈4.02:1**，低于 WCAG AA 正文的 4.5:1。

### D2 · 高 · 语义色当正文前景色用，三个明显不达标

浅色模式对 `systemBackground`（白）的对比度，按 WCAG 相对亮度公式算。
**处数只计可读文本（Text / Label），已剔除 `accessibilityHidden` 的装饰图标**：

| 色 | 值 | 对比度 | 文本处数 |
|---|---|---|---|
| `AppColors.warning` | systemOrange `#FF9500` | **≈2.20:1** | 9 |
| `AppColors.success` | systemGreen `#34C759` | **≈2.22:1** | 1 |
| `AppColors.destructive` | systemRed `#FF3B30` | **≈3.55:1** | 29 |
| `AppColors.primary` | systemBlue `#007AFF` | **≈4.02:1** | 3 + `HighContrastText.status` 全局 |

AA 正文要 4.5:1，大字（≥18pt bold）要 3:1。

`warning` 最差，而它标的恰好全是**阻断类提示**：

| 位置 | 文案 |
|---|---|
| `blindRun/BlindRunner/BlindBookingView.swift:1546` | 「需要开启定位权限才能创建预约。」 |
| `blindRun/BlindRunner/BlindBookingView.swift:1152` | `voiceWizard.fallbackMessage` —— 「语音下单服务暂时不可用」「连续两次没听到预约时间」 |
| `blindRun/BlindRunner/BlindOrderStatusView.swift:778` | 「同行位置暂时不可用」 |

第三条旁边的注释自己写着「盲人据此决定要不要打电话，**这是状态信息不是装饰**」，
然后用了全 App 对比度最低的颜色。

产品影响是**用户卡住且不知道为什么** —— 他看得见「开始约跑」按钮点了没反应，
看不见旁边那行解释；而这些都是一次性的、TTS 播完就过的信息，**视觉是唯一的持久通道**。
`destructive` 的 29 处 Text 是错误提示，同理。

**本 App 特有的放大因素**：陪跑是**户外**活动。阳光下屏幕有效对比度会进一步塌，
2.2:1 在室内勉强能认，在户外等于消失 —— 而户外正是使用场景。

**合规面**：无障碍类应用申请补贴、接政府 / 公益项目时通常要过 WCAG 2.1 AA 或 GB/T 37668，
2.2:1 是硬性不达标。

`blindRun/Core/DesignSystem/AppColors.swift` 一共只有 14 行，改动面很小；
深色模式本身没问题（系统色自带两套）。

### D3 · 中高 · Dynamic Type 被封顶在 accessibility3，没有理由说明

`blindRun/Core/DesignSystem/HighContrastText.swift:45`
`.dynamicTypeSize(...DynamicTypeSize.accessibility3)`。iOS 有 AX1~AX5 五档，这里砍掉最大两档 ——
而 AX4 / AX5 正是低视力用户实际会用的档位。

低视力用户里，**放大字体比读屏更常用** —— 很多人根本不开 VoiceOver，只把系统字号拉到最大。
体验是：在系统设置里调到最大，回到 App 发现字停在中间档不动了，
没有任何线索知道这是 App 主动限制的，只会归因成「这个 App 不支持大字」。

全仓**唯一**一处 `dynamicTypeSize` 就是这个封顶 —— 说明团队从没把「放大字」当成要支持的能力，
只当成要防的布局风险。而它写在名叫 `HighContrastText` 的组件里：
专门为可读性造的组件，是限制可读性的那一个。

### D4 · 中高 · 横屏与 iPad 声明了但从未适配

`blindRun.xcodeproj/project.pbxproj` 里 iPhone 与 iPad 都声明了
`UIInterfaceOrientationLandscapeLeft` / `LandscapeRight`。
而全仓 `horizontalSizeClass` / `verticalSizeClass` **0 命中**，没有任何 size class 分支或 iPad 专属布局。

- **iPhone 横屏**：可用高度约 390pt，`blindRun/BlindRunner/BlindRunnerHomeView.swift:414`
  的 `mapVisualHeight: CGFloat = 300` 是**固定值**、不随屏高变，底部还有 `safeAreaInset` 的 SOS 条
  → 「开始约跑」被推出首屏，必须滚动才找得到。
  全盲用户不受影响（遍历顺序与视觉解耦、双击任意位置激活），**只打低视力用户**
  —— 与 D1 / D3 叠加在同一群人身上。
- 谁会横屏：低视力用户常主动用横屏配合大字（一行能放下的字更多）；
  手机架在支架 / 轮椅上的；跑步时装臂带被系统转屏的。
- **iPad**：280pt 主按钮在 12.9" 上占比很小，反而不像主按钮；
  「地图铺满上半屏 + 巨大主按钮」的整个视觉层次在 iPad 上不成立。
  `AGENTS.md` 要求发布验证必须在 `iPad Pro (2)` 上跑，但没有一行 iPad 专属布局代码。

### D5 · 中 · `AccessibilityAuditTests` 只覆盖 2 个页面

`blindRunUITests/AccessibilityAuditTests.swift` 的 6 条用例全部打在
`BlindRunnerHome` 和 `BlindBooking` 上。

**`BlindOrderStatusView` 没有任何无障碍审计** —— 那是盲人整场陪跑期间停留的页面，
还带地图、SOS、拨号、取消订单、评价。
`BlindRunnerOnboardingView` / `BlindRunnerSettingsView` / `BlindIdentityVerificationView` /
`EmergencyContactsView` 同样 0 覆盖。

### D6 · 中 · 「跳过评价并返回首页」只有 52pt，低于本项目自己的 64pt 线

`blindRun/BlindRunner/BlindOrderStatusView.swift:732` `.frame(minHeight: 52)`。
skill `aidrun-a11y-voice` 写的是「盲人端关键主按钮高度 ≥ 64pt」。

同一屏的评分控件用 `.pickerStyle(.segmented)`（`:708`），segmented control 实际高约 32pt，
是这一页最难点中的控件。

### D7 · 中 · 13 处 `.font(.system(size:))` 固定字号，不随 Dynamic Type 缩放

最扎眼的是 `blindRun/Volunteer/VolunteerOrderFlowViews.swift:1729`（积分数字 48pt）、
`:1746`（图标 42pt）；另有 `blindRun/ContentView.swift:265/315`、
`blindRun/BlindRunner/BlindOrderStatusView.swift:623` 等。
志愿者端是明眼人，优先级低于盲人端，但低视力志愿者同样存在。

### D8 · 低 · `BlindRunnerSettingsView` 没有「重复当前状态」

它是设置列表，没有「当前状态」可复述，倾向于这是合理豁免。
列出来是因为规则字面写的是「每个关键盲人页面必须有」——
要么补，要么在 skill `aidrun-a11y-voice` 里写清豁免条件，别让下一个人重新纠结一遍。

---

## E. 已核实为「非问题」的存疑点

写在这里是为了防止下一轮重新调查一遍。

| 项 | 结论 |
|---|---|
| `/api/orders/voice` 未接 | spec `:956` 标了 `deprecated: true`，明确让改用 `POST /api/orders`。**前端做对了** |
| `/api/orders/available` 未接 | 公开订单池链路已删，派单走 WS `NEW_ORDER`；多处文档与 handoff 一致 |
| `/api/orders/{id}/status-logs`、`/reviews`(GET) | `docs/backend-open-questions-2026-07-31.md:86` 已关闭 |
| `/api/cs/**`、`/api/admin/**`（10 条） | 客服 / 管理端，不属于本 App |
| `ORDER_SELF_DISPATCH_FORBIDDEN` 未映射 | 后端 spec `:2268` 明说「当前一号一身份模型下不可触发，客户端可暂不做专用分支」 |
| 静默解码降级 | **生产路径干净**：20 处 `try? decode` 里 19 处在 `MockAPIClient` 且都有 `else` 分支，1 处是 `blindRun/Core/Models/ErrorModels.swift:197` 的信封兜底策略。`APIClient` 解码失败会记 `.decodingFailure` 诊断并抛 `APIError.decodingError` |
| `WSNewOrder` 不解 `specialNotes` | 有意为之，`blindRun/Core/Models/WebSocketModels.swift:191-206` 写清了理由，有回归用例钉住 |
| 环境切换器暴露给盲人 | `#if DEBUG` + `AppBuildChannel.allowsEnvironmentSwitcher` 双重门（`blindRun/BlindRunner/BlindRunnerSettingsView.swift:35-44`）|
| 未知 `eventType` 处理 | 一律不抑制、走通用分支播 `ttsText ?? body`（`blindRun/Core/AppRealtimeCoordinator.swift:786`），方向正确 |

---

## F. 仍然存疑、只读范围内无法定论

1. **生产水位线（最重要）** —— `47.114.113.171` 上 08-09 / 08-10 两批到底部署了没有。
   handoff 原话：「我们至今没核实过；没部署的话 `candidates` 恒为空数组，消歧轮走不到，
   **看起来会像前端没做**」。
   需要带 BLIND 角色的 JWT 探测；**无鉴权探测定不了论** ——
   真假路径同返 401 同信封（`docs/voice-booking-manual-test-20260805.md:98` 已实测）。
   安全做法是用 `docs/test-accounts.md` 的白名单账号走 `scripts/cloud-e2e.mjs`，
   **会真实发短信并创建订单，需先取得授权**。

2. **`/api/orders/voice/parse` 现在还 404 吗** —— 整个语音降级设计
   （`blindRun/Voice/VoiceOrderWizard.swift:168`、`:458`、`:739`、`parseIsUnavailable` 整条分支）
   和 A3 里 VoiceStatusQuery 不接后端 NLU 的理由，
   **全部建立在 2026-08-06 那一次观测上**，至今未复核。

3. **`candidates` 消歧轮在生产上走不走得到** —— 取决于 1。

---

## 后续动作

| 项 | 去向 |
|---|---|
| A1 / A2 + 语料缺一格 | 已投后端 handoff（2026-08-12） |
| A3 + A4 | 独立变更实现，见各自 §A 描述 |
| B1 | 已 revert，等后端补语料后再镜像 |
| D1 / D2 / D3 / D4 | 低视力通道整体验收，建议单独立项，不要拆成零散修补 |

**建议加一条机器守卫**（`AGENTS.md` §1.1）：A1 那类「前端 `Codable` 声明了契约里不存在的字段」
是可以静态抓到的 —— 把前端模型字段与 `api_spec.yaml` 对应 schema 对撞即可。
这正是 `scripts/validate-spec-coverage.mjs` 现在够不着的一层（它只比路径，`:6` 自己写了这个边界）。
