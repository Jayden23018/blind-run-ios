## 决策

**D1 信号到达从 `run.lastSignalAt` 的变化推出来，不解析推送载荷。** 推送（`RUN_RHYTHM` 等四个 `eventType`）只当「刷新订单」信号，进 `orderRefreshingEventTypes`；VM 在 `apply` 里比较新旧 `lastSignalAt`。理由：推送载荷形状后端还没定（V18「后端定」），而 `run.lastSignal*` 是 V14 明写的冷启动恢复字段，两条路都要读它。首次加载、以及 `lastSignalAt` 已超过 30 秒的「新值」只更新卡片、不震不念（切回前台时补拉到的旧信号不是「刚刚」）。
代价：信号到达的延迟 = 推送 + 一次 `GET /api/orders/{id}`；推送缺 `orderId` 时退化到 5 秒轮询。

**D2 `RUN_RHYTHM` 不进前台横幅。** 设计原文「不另外弹横幅，同一时刻这个信号只在一处出现」。代价：陪跑员不在跑步页时看不到这条（跑步中他几乎总在这一页，且后台时有 APNs）。其余三个照常横幅 + 朗读（跑者听到暂停/继续靠的就是它）。

**D3 走散提示条的出现与消失沿用现有告警。** 现有告警是一次性事件，没有「已恢复」事件（V7 不做 `separation_cleared`）。所以提示条显示「最近一次 `ESCORT_DISTANCE_ALERT` 之后 60 秒内」——与前台横幅同一次事件、同一段时间，不自己算距离。`ESCORT_SIGNAL_LOST` 不进提示条（它说的是「读不到坐标」，已有三数字卡的「位置共享」行）。

**D4 求助面板的紧急按钮：长按 3 秒直接发，轻点 / 读屏双击走锁定文案确认框。** 与跑者端求助中心 `EmergencySOSLongPressButton` 同一套手势（`safetyLongPress`）与同一种取舍（「轻点走二次确认、长按 3 秒跳过它」）。陪跑员侧不走倒计时：倒计时里的「取消」对陪跑员等价于误触撤销，而 `AGENTS.md` §6 规定陪跑员不得有撤销入口。面板不给读屏「立即求助」自定义动作：V6 要求读屏走确认框。

**D5 「联系客服」一键提交固定文案工单，不弹输入表单。** 跑步中陪跑员一只手握引导绳，填表不现实。内容固定「跑步中，陪跑员请求客服联系。」，分类 `ORDER_SERVICE`，带订单号。同一单提交成功后按钮变「已提交」不可重复点。

**D6 暂停后的副文不写「客服已收到通知」。** 暂停通知客服是后端的事（V8），客户端拿不到送达结果；与 §6「不知道的事不许说」同一条。副文写「暂停期间不计志愿时长」（V9 口径，确定为真）。

**D7 颜色。** 新增 `AppColors.Flow.statePaused`（`#4B5263`，V13 允许的状态色，只用于暂停灰条）。信号卡黄色复用 `cta` / `ctaStroke` / `onCTA`（与交付包 `yellow` / `yellowBorder` 同值或近值）；节奏卡圆点用现有 `accent`，过期灰用 `decorMutedInk`（此时信息由「上次反馈」四个字承担，颜色只是冗余）。**不新增** `stateRunning` / `runningTint`：V13 把新状态色限在头卡与锁屏卡。

## 待后端确认的推定（BE-1 / BE-2 合并后逐条对）

| 推定 | 依据 |
|---|---|
| `POST /api/orders/{id}/rhythm` 体 `{"signal":"SLOWER"\|"OK"\|"FASTER"}`，429 = 同一信号 10 秒内 | V14 + 08 §七 |
| `POST /api/orders/{id}/pause`、`/resume` 无请求体 | V15 |
| `OrderDetailResponse.run.{paused,lastSignal,lastSignalAt,runnerBatteryLow}` | V10、08 §七的形状 |
| `OrderDetailResponse.blindSurname` / `volunteerSurname` | V11（字段名后端定） |
| `LOCATION_UPDATE.batteryLevel`（0–1） | V16 |
| `eventType` = `RUN_RHYTHM` / `RUN_PAUSED` / `RUN_RESUMED` / `RUNNER_BATTERY_LOW`，信封带 `orderId` | V18 建议名 |

全部按可选解码：字段缺失时节奏卡显示「还没有发来节奏」、暂停态为否、电量条不出现、称呼退回「跑者」——不会整页空白。
