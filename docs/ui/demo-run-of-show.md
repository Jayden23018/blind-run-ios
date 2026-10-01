# 真机演示脚本（下单之后的流程）

**这份文件回答：现场演示「下单之后」那一段时，两台真机每一步做什么、屏幕上应该是什么、对应哪份设计稿、哪里有时间闸和红线。**
（设计稿哪版现行看 [`mockups/INDEX.md`](./mockups/INDEX.md)；为什么选这种演示形态看 [`../research/real-device-demo-walkthrough-20260930.md`](../research/real-device-demo-walkthrough-20260930.md)。）

状态：**草稿，没有实跑过。** 下面标「未核」的是没验证的事实，实跑前逐条清掉。

## 已定的决定（项目负责人 2026-10-01）

- **全程实时**，不预置订单。服务开始之前有一段空等，用来对着「设计稿 | 真机」讲对照，不空场。
- 盲人端用 iPhone，陪跑员端用现有的 iPad Air。
- **语音下单不在本脚本里**，由负责人另行真机录屏（录完用 `/tmp/audio-check/check-recording-audio.sh` 判有没有声，脚本未入库）。
- 走 Demo Cloud（真后端），不走 Mock：Mock 下志愿者端没有派单推送（`AppState.swift:945`）。

## 时间闸（决定了节奏，来源：后端 `docs/api_spec.yaml` 的接口描述，数值是**默认值，生产实际配置未核**）

| 闸 | 规则 | 对演示的影响 |
|---|---|---|
| 下单提前量 | 开跑时间 ≥ 当前 + 30 分钟（`APPOINTMENT_TOO_SOON`） | 没有「现在就跑」；开跑时间 P 取下单后约 32 分钟 |
| 出发 | 最早 P − 60 分钟（`DEPARTURE_TOO_EARLY`） | P 取 +32 分钟时，下单后立刻可点 |
| 服务开始 | 最早 P − 15 分钟（`SERVICE_START_TOO_EARLY`），盲人还要点「可以开始」（`BLIND_CONFIRMATION_PENDING`） | **约等 15 分钟**，这就是讲对照的空档 |
| 志愿者临期确认 | 仅跨天预约（`SCHEDULED_CONFIRMED`，开跑前 120 分钟内才能确认） | 30 分钟后的单走不到，**「约好·前一晚」画板现场演不了**，用渲染出的设计稿 PNG 展示 |
| 通话磨合 | 窗口 20 分钟，两边各点一次「合适」才进约好 | 开跑时间离得太近会跳过磨合直接接单（`AGENTS.md` §5） |
| 派单 | 志愿者在线、WebSocket 连着、位置 5km 内；每人一轮 30 秒 | iPad 必须真的在上报位置 |

## 演示流程

T0 = 盲人点「确认下单」的时刻。P = 开跑时间（T0 + 约 32 分钟）。

| # | 时刻 | 设备 | 操作 | 订单状态 | 设计稿对照 | 注意 |
|---|---|---|---|---|---|---|
| 1 | T0 | iPhone | 下单，开跑时间选 P | `PENDING_MATCH` | `blind-order-flow/.../screens/02-matching.png` | 下单页自己没有找到对应设计稿 |
| 2 | T0 + 1~3 分钟 | iPad | 收到派单，点「有意向，想先聊聊」 | `PENDING_INTRO_CALL` | 志愿者 `Invite` 画板；磨合页**没找到专门画板** | 推送里 `requiresIntroCall` 决定发哪个动作，客户端不自己算 |
| 3 | 约 T0 + 4 分钟 | 两台 | 两边各点「合适」 | `PENDING_ACCEPT` | 盲人 `03-booked.png`；志愿者 `Main` / `MainSoon`（按距开跑时间，**未核哪张**） | 盲人侧「约好」页同时覆盖 `SCHEDULED_CONFIRMED` 与 `PENDING_ACCEPT`（`BlindOrderFlowStep.swift:48`） |
| 4 | 随后 | iPad | 点「我出发了」 | `DRIVER_EN_ROUTE` | 盲人 `04-on-the-way.png`；志愿者 `Depart` | 这一步起位置双向互推 |
| 5 | 随后 | iPad | 点「到了」 | `DRIVER_ARRIVED` | 盲人 `05-arrived.png`；志愿者 `Meet` | 接口描述里未见到达的时间闸 |
| 6 | 到 P − 15 分钟之前 | — | **空档：对着设计稿 PNG 与真机并排讲** | 不变 | 见下「空档可用素材」 | 约 10~12 分钟，别在这里点任何会推进状态的按钮 |
| 7 | P − 15 分钟起 | iPhone → iPad | 盲人点「可以开始」，志愿者点「开始服务」 | `IN_PROGRESS` | 盲人 `running-state/screens/A-跑者端主故事板.png`；志愿者 `Run` | 两道闸分开处理，别在第一道前反复点 |
| 8 | 随后 | iPad | 展示「李明想慢一点」等状态 | 不变 | `RunSignal`、`RunStates` | 需要盲人端先发信号，**怎么触发未核** |
| 9 | 随后 | 两台 | 展示求助入口：**只轻点到确认框，点取消** | 不变 | 盲人 `B-跑者端异常与求助中心.png`；志愿者 `RunHelp` | ⛔ 见下「红线」，不要长按 3 秒 |
| 10 | 随后 | iPhone | 锁屏，展示实时活动卡 | 不变 | `D-锁屏实时活动.png`；`LiveRun` 画板 | 只在 `IN_PROGRESS` 才起（`LiveEscortSessionCoordinator.swift:364`）；iPad 是否显示**未核**，锁屏卡在 iPhone 上展示 |
| 11 | 随后 | iPad | 长按 2 秒结束陪跑 | `COMPLETED` | 志愿者 `Done` | 接口文档只写了**盲人**结束有闸（陪跑员掉线才放行），志愿者侧未见闸，**实跑确认** |
| 12 | 随后 | 两台 | 打开记录 tab，看跑后记录 | — | `run-record/prototype.html` | 设计稿只有 HTML，要渲染成 PNG（依赖 `support.js`，见研究报告 §11） |

### 空档可用素材（步骤 6）

- 盲人端：`blind-order-flow/design-reference/order-flow/screens/` 下 5 张 PNG，已有 PNG，可直接并排。
- 陪跑员端：`volunteer-order-page-v2/reference/artboards/*.dc.html` 只有 HTML，要先用 Chrome headless 渲染成 PNG（命令与 13 张均可渲染的结果见研究报告 §11）。
- **并排页本身还没做**；脚本里的「对照」暂指把设计 PNG 与真机并排摆给人看。

## 演示前就绪清单（逐条打勾，没打勾不开演）

- [ ] **服务端可达。** 2026-10-01 18:30 这台 Mac 直连 `47.114.113.171` 的 443 和 22 端口**都超时**（`nc -z -G 5` 与 `curl --noproxy '*'`），同时 `www.baidu.com` 可达 ⇒ 不是 Mac 断网。原因未查（服务器 / 安全组 / 网络均有可能）。**不解决就没有演示。**
- [ ] 两台设备装**同一个构建**：iPhone 现为 build 545，iPad 现为 build 521（`devicectl device info apps`）。
- [ ] 账号用**联调号**（盲人 / 志愿者各一，见后端 `docs/test-accounts.md` §2.2），**不得用 §2.3 的 TestFlight 审核号**（会撞审核员的 `DUPLICATE_ORDER`）。固定验证码 `000000`。
- [ ] 志愿者端：接单开关已开、定位权限已授予、WebSocket 已连、当前位置在下单地点 5km 内。**iPad 是否有 GPS（蜂窝款）未核**；仅 Wi-Fi 款靠 Wi-Fi 定位，精度够不够 5km 派单要实测。
- [ ] 盲人号已过门：实名、至少 1 个紧急联系人。**这个联调号的紧急联系人是不是本人未核**——云端 SOS 触发会真的给联系人发短信，所以步骤 9 只演到确认框。
- [ ] 两个号都没有未走完且时段冲突的订单（`DUPLICATE_ORDER` 只拦时段冲突；未完成预约最多 3 张）。
- [ ] 就绪探针 `scripts/volunteer-dispatch-readiness-probe.mjs` 可用来查「志愿者收不到派单」。⚠️ 它和 `scripts/cloud-e2e.mjs` 里的 `baseURL` 都写 `http://47.114.113.171`，而 `AGENTS.md` §3 已改为 `https`；**脚本是否仍可用未核**，探针失败时先分清是脚本过期还是服务端不可达。

## 红线（来自 `AGENTS.md` §5–§6，演示时照做）

- **不要长按 3 秒。** 跑者端求助中心与志愿者端 `FlowHelpPill` 的紧急按钮，长按 3 秒是**直发云端求助**，会真的通知联系人；轻点 / 读屏双击才是弹确认框，确认框文案逐字锁定。
- **不得说「短信已发出 / 联系人已被通知」**，也不得让屏幕上出现 `联系人已收到短信`。
- **志愿者端只显示掩码号**，不能把它拼进拨号；演示时不要点拨号。
- 盲人的自由文本在 `PENDING_INTRO_CALL` 对志愿者**不可见**，这是设计，别当缺陷讲。
- 这是 Demo Cloud 真后端：演示产生的订单与位置是真写入的。

## 这份脚本没覆盖的

- 语音下单（负责人另录）。
- 「约好·前一晚」「取消 / 迟到 / 爽约」等需要真实时间跨度的状态——用渲染出的设计稿 PNG 展示，不现场演。
- 对照结果的「偏差清单」——INDEX 多行仍写「未逐屏对照」，并排一摆就会暴露，开演前先决定怎么讲。
