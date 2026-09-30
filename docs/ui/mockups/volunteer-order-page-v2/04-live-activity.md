# 04 · 锁屏实时活动与灵动岛

画板：`LiveActivity.dc.html`。本期给陪跑员端做（v3 待确认项，本期确定）。需要 iOS 16.1+；按钮交互需要 iOS 17+（App Intents），iOS 16 上隐藏按钮。

## 生命周期

| 时机 | 动作 |
|---|---|
| 按下「我出发了」 | 本地 `Activity.request` 开启，上传 push token 给后端 |
| 出发前 30 分钟（`agreedSoon`）且 App 在前台 | 可选：提前开启，显示"15 分钟后出发"。**默认关闭**，留开关 |
| ETA 变化 ≥1 分钟、状态变化、跑者到达状态变化 | 后端通过 APNs（`apns-push-type: liveactivity`）推送更新 |
| 汇合 | 更新为汇合样式（见下） |
| 开始跑步 | 同一个 Activity 更新为跑步中样式（v2，见本文件最后一节） |
| 完成、取消、结束等待 | 后端推送 `end`，`dismissal-date` = 现在 + 5 分钟 |

## ContentState

```swift
struct GuideRunAttributes: ActivityAttributes {
    let orderId: String
    let runnerSurname: String        // 锁屏只放姓氏（隐私，沿用 v3 锁屏规则）
    let meetingPointName: String

    struct ContentState: Codable, Hashable {
        var phase: Phase             // .departed / .late / .arrived
        var etaMinutes: Int?
        var arriveAt: Date?
        var progress: Double         // 0.1–0.85，同 RopeView
        var runnerNearMeetingPoint: Bool
        var distanceBucket: String?  // 汇合时
    }
    enum Phase: String, Codable { case departed, late, arrived }
}
```

锁屏上的姓名只用姓氏：「李明已到入口附近」→ **「李先生已到 3 号入口附近」**。画板上写的是全名，以本条为准。

## 锁屏样式

卡片底色跟随状态色（v2）：出发 `stateDeparted`、快迟到仍为 `stateDeparted`、汇合 `stateArrived`、跑步中 `stateRunning`。圆角由系统决定，内边距 18：
1. 小图标（22pt，圆角 6，底 `yellow`，跑步图标 `onYellow`）+「助盲跑 · 正在赶去」14 semibold `onNavyEyebrow`
2. 「8 分钟后到」32 heavy 白色 + 「6:57」15 `onNavyEyebrow`（到达时间只出现这一次）
3. 深色主题的 `RopeView(state: .departed, progress:)`，宽度占满
4. 绿点 +「李先生已到 3 号入口附近」15 semibold `onNavyStrong`（仅 `runnerNearMeetingPoint` 为 true 时显示）
5. 两个按钮（iOS 17+）：「我快到了」「再等我 5 分钟」，底为白色 12% 不透明度，高 44，圆角 14。按钮通过 `LiveActivityIntent` 调用快捷回复接口，不打开 App

快迟到：第 2 行颜色变为 `gold`，文案「约 11 分钟后到 · 晚到约 6 分钟」。

汇合：第 2 行改为「已到集合点」，第 4 行按 distanceBucket 显示「李先生就在附近」；按钮换成「让他的手机响起来」「打电话」。

## 灵动岛

- 紧凑态左侧：迷你引导绳（两个 7pt 圆点 + 一段短线，陪跑员 `volunteerDot`，跑者 `runnerDot`）
- 紧凑态右侧：「8 分钟」14 heavy 白色，数字等宽；汇合时为「已到」
- 最小态：迷你引导绳
- 展开态：与锁屏相同的第 2–4 行，不放按钮

## 可访问性

锁屏实时活动的读屏文案：「助盲跑，正在赶去，8 分钟后到，6 点 57 分，李先生已到 3 号入口附近」。数字更新时不主动播报。

## v2 新增：跑步中样式

画板：`LiveRun.dc.html`。卡片底 `stateRunning`，内边距 16 / 18，**不放任何按钮**（避免口袋误触结束陪跑）。锁屏卡片高度须 ≤160pt，真机量一下。

1. 白色小图标（跑步图标用 `stateRunning`）+「陪跑中 · 李先生：刚刚好」14 bold `onHeroEyebrow`。节奏信号超过 5 分钟没更新时只写「陪跑中」
2. 「2.40」40 heavy +「/ 5.00 公里」16 bold `onHeroBody`，右侧「18:32 · 7'43"」17 heavy
3. 8pt 进度条（底 `onHeroTrack`，填充白色），有折返点时在对应位置画 2pt 宽的 `gold` 竖线

灵动岛：紧凑态左侧为并肩的两个小圆点 + 金色短绳，右侧「2.40 公里」；最小态只有并肩圆点。

ContentState 增加：`distanceKm`、`targetKm`、`elapsedSeconds`、`paceSecondsPerKm`、`turnaroundKm?`、`lastSignal?`（`SLOWER | OK | FASTER`）、`lastSignalAt?`、`paused`。每 0.1 公里或每 30 秒更新一次，取先到者。暂停时卡片底色改为 `statePaused`，第 1 行写「已暂停」。
