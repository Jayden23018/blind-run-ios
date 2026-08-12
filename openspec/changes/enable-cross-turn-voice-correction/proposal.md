## Why

读回整单之后，用户只有两条路：说「确认」，或者把整句重说一遍。想把时间从八点改成九点，就得连出发地、终点、时长一起重念 —— 每重说一次都是一次新的识别错误机会，而对听不见屏幕的人，错在哪一项只能靠听完整段 15~25 秒的读回去分辨。

**后端 2026-08-09 已经把这件事做完了，iOS 侧一行没接**（`61d5621`，含 `4e5f389` / PR #51）：

- `ParseVoiceOrderRequest.current` —— 客户端回传上一轮槽位快照，后端做「本轮新抽到的覆盖、没抽到的继承」
- `userIntent` —— `CONFIRM` / `CANCEL` / `RESTART` / `REPEAT`，确认轮的表态判定收回后端
- `correctionTarget` —— 用户点名要改哪一项但没给值（7 个取值），`ttsText` 是该项的定向追问语
- `correctionUnclear` —— 只说「不对」、没说改哪一项时的消歧问句

前端至今发的是 `ResolveAddressRequest`（`blindRun/Core/Models/VoiceOrderModels.swift`），这个类型里根本没有 `current` 字段；确认轮走的是纯本地整串词表。所以后端那一整批（N38/N39/N41/N42/N43/N45）**在 iOS 上全部不可达**，新字段恒为 null。这一条前端在 `demo/docs/handoff.md` 2026-08-09 那条里自己认过。

顺带修掉一处逐词对撞查出的**行为分叉**：「再说一次」前端判「重说」（清空用户刚说完的一整句），后端 `INTENT_REPEAT` 判「重播」（只重念一遍）。同一句话在有网和断网时走两条代价完全不同的路。

## What Changes

- **确认轮改成两档：本地整串直通 + 后端兜底。**
  - 第 1 档：命中本地 27 个整串词 → 零延迟直通，一个字节都不发。
  - 第 2 档：其余一律发 `POST /api/orders/voice/parse` 并带上 `current`，按 `userIntent` / `correctionTarget` / `correctionUnclear` 分流。方言、长句、「把时间改成九点」全在这一档。
  - **不按后端建议把本地表整个撤掉**（handoff N45 ④）：后端的确定性兜底跑在服务端，它挡不住网络。确认轮一次往返 3.4~4.3 秒（每次都调大模型）、客户端超时 12 秒 —— 让最高频最简单的那一句「确认」等 4 秒，网络一抖就下不了单，等于把一次已经解析成功的语音下单在最后一步丢掉。本地表是后端正则的子集时两者不可能给出不同结论，这个子集关系由新门禁钉住。
- **读回结尾必须教「可以只改一项」**。看不见屏幕的人不会自己发现这个能力，不教等于没做。缺时间那句也从「请说重说」改成「直接说时间就行」。
- **定点修改不新增向导步骤**。`correctionTarget` 的定向追问 = 「播一句 + 在同一个 field 上再收一次」，复用既有的播报—收音循环，屏幕不在用户说话的中途换成另一张表单（2026-08-06 用户报过这个）。定向追问**不计入重问上限**，`correctionUnclear` 计入 —— 前者是正常推进，后者确实是没听懂。
- **快照唯一从响应派生，绝不从 view model 派生**。`appointmentTime` 的初值是 `Date()`，从 view model 取会把一个用户从没说过的时刻当成「已确认槽位」发给后端，后端原样继承回来、读回念出来 —— 2026-08-06「他也没有经过我的同意」那条红线的等价物。
- **词表三处修正**：「再说一次」改判重播、「再说一遍」补进重播表、「开始约跑」删掉（后端正则不认，且读回从没教过它）。
- **新增第 5 条读后端源码的门禁** `scripts/validate-voice-intent-words.mjs`：逐词把本地三张表过一遍后端 `VoiceSlotParser` 的 5 条 `INTENT_*` 正则，判成别的意图就红。接进 pre-push 与 fork CI。

## Capabilities

### Modified Capabilities

- `blind-runner-voice-first-experience`: 读回之后不再是「确认 or 整句重说」二选一 —— 用户可以只说要改的那一项、可以点名某项再等追问、可以要求重听、可以取消，判定由后端负责，本地表退为断网直通。

## Impact

- iOS 语音/下单：`VoiceOrderWizard`（确认轮分流、槽位应用抽成共用一份）、`VoiceOrderModels`（新请求体与两个开放枚举）、`MockAPIClient`（`current` 合并与意图判定）。
- 契约：**只消费，不改动**。不新增、不修改任何后端端点；`POST /api/orders` 请求体不变。
- 风险面：
  - `/parse` 请求数从每单 1 次涨到 1+N，而 `/api/orders/voice/**` 已拆到独立限流桶 **20 次/分钟/IP**。正常使用远够，压测要注意。
  - 08-09 那批后端代码**是否已部署到生产未核实**（已确认全在后端 `origin/main`，生产水位线最后一次核实是 08-06）。未部署时 `current` 被忽略、新字段恒 null → 退化成「当作槽位更新重念整单」，本地 27 词仍可下单。降级安全，但功能不生效。
- 文档：`docs/05-page-specs.md` 预约页语音小节、`docs/09-accessibility-and-voice-guidelines.md` 必播报节点、`AGENTS.md` 第 11 节的门禁清单（4 条 → 5 条）。

## ⚠️ 归档顺序约束

本变更 MODIFY 的 `Booking uses a guided voice-first sequence` 也被**尚未归档**的 `enable-one-utterance-booking` MODIFY 过。两者的 delta 都是整条 requirement 的全量替换，所以：

**本变更必须在 `enable-one-utterance-booking` 之后归档。** 顺序反了会把这里对三条 Scenario 的修订覆盖回去，而 `openspec validate --strict` 只查结构不查语义，抓不到。
