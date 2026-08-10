# Tasks

## 1. 定位（N48 根因的第一环）

- [x] 1.1 `BlindBookingView` 启动语音时 `locationService.requestOneTimeLocation()` —— **正面修法**。`onAppear` 的 `startUpdating()` 是持续定位，而非陪跑模式 `distanceFilter = 10` 意味着站着不动 Core Location 不推新样本；`requestLocation()` 绕过它直接要一次新 fix，而用户接下来要说 10~20 秒，新坐标早在请求发出前就到了。
- [x] 1.2 语音那一处的 `latestBackendSample(freshness: 300)` —— 兜底。**只改这一处、不动方法默认值**：另外三个调用点（`ContentView:406`、`EmergencyCoordinator:119/126`、`VolunteerOrderFlowViews:1504`）各有各的新鲜度要求。
- [ ] 1.3 新鲜度回归用例：60 秒前的样本下 `/parse` 请求仍带 `latitude`/`longitude`，且 `requestOneTimeLocation()` 真的被调到。**（分工归对方）**

## 2. 模型层

- [x] 2.1 `AddressCandidate`：`name` / `address` / `adname` / `business` / `distanceMeters` / 坐标。
- [x] 2.2 `readbackAddress` 计算属性 —— **镜像后端 `VoiceOrderService.readback`**（POI 名 + 空格 + 街道地址）。后端平铺 `address` 就是这么拼的，挑第二个必须拼出同样的形态，否则下游按空格切 POI 名的 `spokenAddress` 会切错。
- [x] 2.3 `ParseVoiceOrderResponse` 加 `candidates` / `addressUnresolved`，一律可选。
- [x] 2.4 `startCandidatesToDisambiguate` —— 判据只看**数量 ≥2**，不看 `needReask`：后端在这一轮同时可能报 `missing`，两者混在一起分不出「该消歧」还是「该追问」。
- [x] 2.5 `replacingStartPlace(with:)` —— 挑定后换掉快照，**并清空 `candidates`**。不清空的话下一轮又被 `startCandidatesToDisambiguate` 读到，用户为同一批候选被问第二遍。

## 3. 向导

- [x] 3.1 `Step` 新增 `.disambiguateStart(candidates:prompt:)`。**唯一一个由后端文案驱动的轮次** —— 候选的名称/行政区/距离只有后端知道。
- [x] 3.2 `speechField` 复用既有的 `.voiceOrderStartPlace`（逐项追问删掉后一直空着），不新增枚举值 —— 新增要同步 `isAllowlisted` 白名单，白拿一处可能漏改的地方。
- [x] 3.3 `parseFreeform` 里消歧**排在读回之前**。读回念的是最佳猜测，用户听完多半就说「确认」。
- [x] 3.4 `ordinalIndex(in:count:)`：汉字 + 阿拉伯数字两种写法；`count` 是护栏，只念了 2 个不许认「第三个」。
- [x] 3.5 三次挑不出来 → 取第一条 + **说出「按第一个来」**，不丢回表单。
- [x] 3.6 消歧轮里「重说」随时能退出去，复用确认轮的 `restartWords`。
- [x] 3.7 接 `addressUnresolved`：听见了地名却没查到时，读回前先说出来，且**与时长夹取提示一起说**，不是二选一。

## 4. 已知坑（踩过，别再踩）

- [x] 4.1 🔴 **消歧轮不能用 `promptAndListen`** —— 它开头 `reaskCount = 0`（那是给定向追问用的「不计入重问上限」路径），用在这里 3.5 那个上限**永远数不到**，挑不出来的用户被永远关在候选列表里。真机 XCTest 抓到的，已改成 `speak` + `listen`。
- [x] 4.2 `BlindBookingView` 的 `onChange(of: voiceWizard.step)` 是 exhaustive switch，加 Step 值要同步。消歧轮同样停在确认页 —— 换页会把用户从他刚听到的内容上挪开。

## 5. 配套

- [x] 5.1 Mock 产 `candidates`，播报文案逐字照抄后端 `buildCandidateTts`（含「距您 X 米」与超 1 公里换单位）。不做的话开发期与 demo 环境永远走不到消歧轮。
- [ ] 5.2 Mock 候选的断言 —— 目前一条都没有。**（分工归对方）**
- [x] 5.3 词表门禁加第 4 张表，**方向与前三张相反**：前三张查「本地认的词后端会不会判成别的」，这张查「后端念给用户的词本地认不认得」，读后端 `VoiceOrderService.ORDINALS`。
- [x] 5.4 pre-push 后端新鲜度清单补上词表门禁读的两个 `.java`。

## 6. 验证

- [x] 6.1 真机 XCTest：`Executed 85 tests, with 0 failures` — **TEST SUCCEEDED**。9 条新用例逐条确认执行（`Test Case '...' passed` 逐条 grep），不是「套件绿就算跑了」。
- [x] 6.2 pre-push 全门禁通过（含新增序数覆盖检查、golden-corpus 96 条、codegen 比对）。
  ⚠️ 后端 N48 **已合入 `origin/main`**（`08466c2`），所以**不需要** `AIDRUN_ALLOW_BACKEND_DRIFT=1`。跨端顺序是「后端契约先合，再推前端」。
- [ ] 6.3 真机手测：站着说「明天早上八点从万象城出发跑一个小时」，确认听到序号播报、说「第二个」能选中。

## 7. 归档顺序（⚠️ 别搞错）

- [ ] 7.1 本变更 MODIFY 的 `blind-runner-voice-first-experience`，`enable-one-utterance-booking` 与 `enable-cross-turn-voice-correction` 两个未归档变更也 MODIFY 过。**本变更必须最后归档**，且上面的 MODIFIED 块已基于 `enable-cross-turn-voice-correction` 那一版写 —— 否则会把跨轮修正那批的 Scenario 覆盖回去。
