## Context

- 派单资格的权威来源是 `GET /api/volunteer/dispatch-summary` 的 `canDispatch` 与 `notAvailableReasons`。
  后端按 `NOT_VERIFIED` > `TRAINING_INCOMPLETE` > `DISPATCH_DISABLED` > `OFFLINE` 给引导优先级，前两者可以同时出现。
- 滑块此前的 `isEnabled` 是 `AppState.isVolunteerProfileApproved`。它有注册状态时只看 `isRegistrationComplete`，
  与「能不能派单」不是一回事。
- 注册完成态刻意不立刻发布给 `AppState`（发布会让根路由拆掉注册流），所以注册结束页不能读 `AppState`。
- 后端 `reviewCertificate` 把 `rejectionReason` 只放进 `CERT_REJECTED` 通知，不入库；
  `VerificationStatusResponse` 只有 `status`。`CERT_APPROVED` 的优先级是 NORMAL，不走 APNs。
- 真机离线，高德没有模拟器 slice。

## Goals / Non-Goals

**Goals:**

- 判定写成纯函数，覆盖每种不可派单原因，能在没有真机时运行。
- 一页总进度，注册结束页与首页共用同一份内容。
- 一束光相关文案集中一处，以后拿到联系方式只改一行。

**Non-Goals:**

- 不改接单机制与后台定位（#654）。已开启且被挡住的人，定位行为照旧。
- 不改谁来审核、审核排班。
- 不在客户端解析通知正文里的原因。

## Decisions

### D1. 判定收进 `VolunteerAvailabilityStatus.resolve`，只吃派单摘要的三个字段

输入是 `isAvailable`、`canDispatch`、`reasons`，加一个「摘要到了没有」。滑块和接单主页胶囊都读它。

- `NOT_VERIFIED`、`TRAINING_INCOMPLETE` 先判，且不看开关：这两条靠滑动解决不了。
- 关着时其余一律可滑开：`DISPATCH_DISABLED` 正是滑开要解决的，`OFFLINE` 要开了才上报位置。
- 开着时只有 `canDispatch == true` 才算接单中。
- 开着而原因里还有 `DISPATCH_DISABLED`：是开启之前的旧摘要，显示确认中，不当成不可派单。

被否方案：让 `isVolunteerProfileApproved` 带上资质判定。它决定根路由，改它会把人锁出首页。

### D2. 被挡住时点按去总进度，而不是直接去证书页或培训页

两条原因可以同时成立。总进度一页说全，还能看到审核状态。首屏原有的证书与培训入口不动。

### D3. 总进度的状态用「注册状态 + 证书状态 + 派单摘要」三路拼

注册结束页把 `VolunteerRegistrationViewModel` 手上的最新状态传进来，不读 `AppState`。
培训状态只认摘要里有没有 `TRAINING_INCOMPLETE`；摘要拿不到时是未知，不是未完成。

### D4. 预先解码 `rejectionReason`，缺失时走兜底

字段名写进后端 issue。它是可选字段，现在永远缺失，线上跑的是兜底文案。
这样后端上线后不用等 App 审核。Mock 不伪造这个字段（记忆 `mock-fabricates-fields-the-backend-never-sends`）。

被否方案：解析 `CERT_REJECTED` 通知正文。通知只在 24 小时内可补读，且正文是模板，改一个字就解析错。

### D5. UI 测试基线改成显式声明培训已完成

Mock 默认未完成培训是有意的（`MockAPIClient+Training.swift`）。新增开关 `AIDRUN_MOCK_VOLUNTEER_TRAINING_COMPLETED`，
由 `launchVolunteerHome` 与 `ScreenTourTests.launchVolunteer` 默认打开；要测培训态的用例走自己的启动路径。

## Risks / Trade-offs

- 新人此前能滑开，现在不能 → 这是目的；点按有去处，读屏有按钮。
- 派单摘要滞后时滑块会多挡几秒 → 首页每 10 秒刷新一次摘要。
- UI 用例改了基线但真机离线没跑 → PR 写明未验证，用 `Refs` 不用 `Fixes`。
- 替代路径的人传的是身份材料，不是一束光证书，而后端只有一个槽位 → 需负责人定这条路径是否也要证书，写进 PR 交接。
