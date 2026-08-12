# Tasks

## 1. 模型层

- [x] 1.1 `blindRun/Core/Models/VoiceOrderModels.swift` 新增 `ParseVoiceOrderRequest`（transcript + 可选坐标 + `current`），**不再复用** `ResolveAddressRequest` —— 在没有 `current` 的世界里两个端点请求体确实逐字相同，复用是对的，现在不成立了。
- [x] 1.2 新增 `VoiceSlotSnapshot`。口径按 `api_spec.yaml` 2026-08-09 放宽后的版本：起点与终点**同一档规则**，允许「有地址无坐标」，只有坐标没地址一律整组丢弃。
  ⚠️ `demo/docs/frontend-guide.md` 里那句「起点三项必须同时提供或同时缺省」是放宽前的旧文，与 `api_spec.yaml` 矛盾；契约唯一源是 `api_spec.yaml`（AGENTS §7），已按放宽版写并写进 handoff 请后端订正。
- [x] 1.3 新增 `VoiceUserIntent` / `VoiceCorrectionTarget` 两个**开放枚举**，未知值退化成 `.unknown` 而不抛 —— 与 `VoiceOrderMissingSlot` 逐字同一套写法（本仓库红线：后端加枚举值不许让整条响应解不出来）。
- [x] 1.4 `ParseVoiceOrderResponse` 加 `userIntent` / `correctionTarget` / `correctionUnclear`，一律可选（线上偶发缺字段要退化，不许整条炸掉）。
- [x] 1.5 加 `slotSnapshot` 计算属性 —— **快照唯一从响应派生**。

## 2. 向导

- [x] 2.1 把 `parseFreeform` 里落槽位那一段抽成 `apply(_:)`，两轮共用一份。三个可选槽位曾经被静默丢掉，成因就是「两处各写一遍」。
- [x] 2.2 新增 `lastParsed`，`start()` 与 `restartFromFreeform()` 里一并清空。
- [x] 2.3 `didCaptureStartTime` 改为跟随响应（`plannedStartTime != nil`），不再只置真不置假 —— 跨轮继承下第 2 轮响应里时间还在，标志位就该还是真。
- [x] 2.4 `handleConfirmCommand` 改成两档：本地整串直通 → 其余发 `/parse` + `current`，按 `userIntent` / `correctionTarget` / `correctionUnclear` 分流。
- [x] 2.5 `promptAndListen(_:)`（不计重问）与 `reask(_:)`（计重问）分开，定向追问走前者、消歧问句走后者。
- [x] 2.6 网络失败不再回「没听懂」，改播 `confirmRoundNetworkFailureNotice`，并把本地仍可用的两条出路念出来。
- [x] 2.7 读回结尾（`Step.confirmOutroText`）与缺时间那句都改成先教「直接说要改的那一项」。
- [x] 2.8 词表三处修正：「再说一次」移到重播表、「再说一遍」补进重播表、「开始约跑」删掉。

## 3. Mock

- [x] 3.1 `handleVoiceParseOrder` 解 `ParseVoiceOrderRequest`，按「本轮 > `current`」合并。起点三元组整体覆盖或整体继承；终点抽到地名但查不到坐标时**不许继承旧坐标**（会拼出「新地名 + 旧坐标」，名字对位置错，而读回只念名字）。
- [x] 3.2 `mockVoiceUserIntent` **逐字转写**后端 `VoiceSlotParser.java` 的 5 条正则与判定顺序。Mock 不许比线上松。
- [x] 3.3 `mockVoiceCorrectionTarget` 是**刻意的粗近似**（线上纯靠大模型，没有可转写的正则），注释已写明。
- [x] 3.4 修掉 `needReask: !missing.isEmpty` —— 注释里挂了很久的「接 `current` 时要一起改」，现在有三个反例。

## 4. 门禁

- [x] 4.1 新建 `scripts/validate-voice-intent-words.mjs`：逐词把本地三张表过一遍后端 5 条 `INTENT_*` 正则。判成**别的**意图硬失败；后端返 empty 的只列出来（本地是超集不造成分歧）。
- [x] 4.2 **证明它真的会红**：对着一份把「再说一次」塞回 `restartWords` 的副本跑，exit=1 且报出那一处分叉；对着当前代码跑 exit=0。（一个从没红过的守卫和没有守卫是一回事，所以脚本的 Swift 路径做成可覆盖的。）
- [x] 4.3 接进 `scripts/install-git-hooks.sh` 与 `.github/workflows/verify.yml` 的 `specs` job，抄 `validate-error-codes.mjs` 的接法。
- [x] 4.4 `AGENTS.md` 第 11 节：命令清单加一条，「读后端仓库的那 4 条门禁」改成 5 条并写明加它的起因。

## 5. 测试

- [x] 5.1 新增 12 条用例：跨轮修正保住未提及的槽位、`current` 真的发出去了、快照不许带用户没说过的时间、后端四个 `userIntent` 各一条、`correctionTarget` 定向追问不计重问、`correctionUnclear` 计重问、网络失败不说「没听懂」且本地确认仍能下单、未知枚举值解码不抛、快照的「有地址无坐标」口径、读回教了定点修改。
- [x] 5.2 stub 增加 `parseRequests` 捕获 —— 只看 `paths` 验不出 `current` 有没有真的发出去，而那正是 08-09 之前的状态（后端做完一整批，iOS 全部不可达）。
- [x] 5.3 改既有三条：删「开始约跑」、`testUnrecognizedConfirmCommand…` 改成「交后端而不是就地放弃」、「再说一次」改判重播。
- [ ] 5.4 真机跑 `blindRunTests/VoiceOrderWizardTests` —— **未执行**：iPhone `111` 未连接，iPad Air 处于锁屏。等设备可用后补跑。

## 6. 文档与交接

- [x] 6.1 `docs/05-page-specs.md` 预约页语音小节。
- [x] 6.2 `docs/09-accessibility-and-voice-guidelines.md` 必播报节点。
- [x] 6.3 `demo/docs/handoff.md`：答掉 N45 的 ⓓ（词表已直接对撞源码，不用后端再贴一遍）、通报三处词表差异与 `重说` 未进 `INTENT_RESTART`、通报 `frontend-guide.md` 与 `api_spec.yaml` 的起点快照口径矛盾、更新 08-09 那条「前端不发 `current`」的结论。

## 7. 验收

- [x] 7.1 `xcodebuild … build-for-testing` → `TEST BUILD SUCCEEDED`（无签名）。
- [x] 7.2 `node scripts/validate-voice-intent-words.mjs` 通过；故意造错的副本 exit=1。
- [x] 7.3 `node scripts/validate-docs.mjs`、`node scripts/validate-guard.mjs`（28 条）通过。
- [ ] 7.4 `openspec validate --all --strict --no-interactive`。
- [ ] 7.5 真机单测（见 5.4）。
- [ ] 7.6 **真机手测（唯一能验的一条）**：开 VoiceOver → 说一整句 → 听完读回 → 说「把时间改成明天早上九点」→ 确认只有时间变、其余没被清空 → 说「确认」下单。再验「我想改终点」（定向追问）与「算了不下了」（取消）。这三条走的是真实大模型，单测与 Mock 证明不了。
- [ ] 7.7 **先验生产是否已部署 08-09 那批**：08-09 后端代码确认全在 `origin/main`，但生产水位线最后一次核实是 08-06。上真机第一件事就是说一句「时间改成九点」看它是不是真的只改了时间。
