## Why

陪跑员订单页 v2 的决定源（`~/Downloads/zhumangpao-handoff-v2/DECISIONS-v2.md` V4–V8、V11、V14–V17，任务 FE-3）要求：跑步中页面**布局不动**（三数字卡、长按 2 秒结束），但把新能力加进旧页；跑者端在跑步中能用三个大按钮告诉陪跑员节奏，并随位置上报电量。

今天陪跑员在跑步中只看得到三个数字，看不到跑者想快还是想慢；右上角「求助」只有一条路（直接云端求助），没有「先停一下」「找客服」这种不那么重的出口；走散告警只弹一次横幅就没了。

## What Changes

**陪跑员端（`IN_PROGRESS`，旧跑步页）**
- 节奏卡：显示跑者最近一次节奏（稍慢一点 / 刚刚好 / 可以快一点，文案固定）；从未收到时写「{称呼}还没有发来节奏」；超过 5 分钟变灰、标签改「上次反馈」。
- 新信号到达：非「刚刚好」时两次 `.medium` 触感（间隔 0.15 秒）、节奏卡原地变黄 8 秒、VoiceOver `announcement` 一次；「刚刚好」只震一次、不变黄。
- 耳机语音播报开关：默认关，存本地设置跨订单保留；开启后每满 1 公里播报「N 公里，用时 X 分 Y 秒」、收到信号播报「{称呼}说：稍慢一点」。走现有 `SpeechService`（音频会话沿用 `SystemSpeechAudioSession`，不另起会话）。
- 提示条（三数字卡下方，同一时刻只显示一条）：① 走散 —— 由现有 `ESCORT_DISTANCE_ALERT` 驱动，阈值不改，不放响铃按钮；② 跑者电量低 —— `run.runnerBatteryLow`；③ 本机定位精度差于 50 米持续 20 秒。
- 暂停：求助面板里「{称呼}需要停下来」调 `POST /api/orders/{id}/pause`；暂停中三数字卡上方出现 `statePaused` 灰条「已暂停 · 计时停在 mm:ss」，「继续陪跑」黄色主按钮调 `/resume`，是本屏唯一的黄色按钮（结束按钮暂停时改白底描边）。
- 右上角「求助」在跑步中改为打开求助面板：暂停 / 联系客服（一键提交带订单号的 `POST /api/support/tickets`，页面说「客服会尽快联系你」）/ 长按 3 秒紧急求助 → 现有云端链路。轻点与 VoiceOver 双击弹 `AGENTS.md` §6 锁定文案的确认框；副标题只说「求助会附带你的当前位置」，不承诺任何人已收到。
- 称呼（V11）：有 `blindSurname` 用姓氏，没有用「跑者」。

**跑者端（`IN_PROGRESS`）**
- 跑步卡下方三个 64pt 大按钮发 `POST /api/orders/{id}/rhythm`（`SLOWER` / `OK` / `FASTER`）；成功后 TTS「已告诉陪跑员：稍慢一点」；429 念「刚发过，稍等再按」。
- `LOCATION_UPDATE` 追加可选 `batteryLevel`（0–1，拿不到不传），跑者角色才带；上报周期 5 秒，满足「每 60 秒至少一次」。

## Capabilities

### New Capabilities
- `running-rhythm-and-help`: 跑步中两端的节奏信号、暂停/继续、提示条、语音播报开关、陪跑员求助面板与跑者电量上报。

### Modified Capabilities

## Impact

- 代码：`VolunteerOrderFlowViews.swift`（旧跑步页与 VM）、新增 `blindRun/Volunteer/VolunteerRunningCompanion.swift`、`blindRun/BlindRunner/RunnerRhythm.swift`；`OrderDetailResponse` 加 `run` / 姓氏；`OrderServing` 加 `sendRhythm` / `pauseRun` / `resumeRun`；`WSLocationUpdateMessage` 加 `batteryLevel`；`AppRealtimeCoordinator` 把四个新 `eventType` 当订单刷新信号；`VolunteerSOSNavButton` 允许换读屏文案。
- 契约：**依赖后端 BE-1 / BE-2，当前后端 `origin/main`（`0de474f`）一条都没有。** 路径、字段名、`eventType` 按 DECISIONS V14–V18 推定，全部可选解码、可降级；后端合并后按实际契约对一遍（见 design.md「待后端确认的推定」）。在那之前 pre-push 的 spec-coverage 门禁会拦住推送，**不绕**。
- 不在本变更：跑步页视觉改版（C13/C14/C20，V4 不做）、跑步中响铃（V12）、折返点（V12）、锁屏跑步卡（FE-2）、`run` 对象里的距离/用时（V10，三数字仍走 `track`）。
