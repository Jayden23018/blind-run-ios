## Context

跑者端的精确位置闸在 `EmergencyCoordinator.freshEmergencyCoordinate`（#373 / `gate-blind-location-on-precise-accuracy`）。
陪跑员端的两处求助入口绕过了它，直接取 `latestBackendSample()`。

## Goals / Non-Goals

**Goals:** 陪跑员代发求助与跑者端同一道闸；精确位置关着时给一次补救机会（临时精确位置）；仍不行就降级本地拨号，原因可听可见。

**Non-Goals:** 不改陪跑中每 5 秒的同行位置上报（#407 第 2 项）；不改语音下单消歧（第 3 项）；不改跑者端「求助时不弹系统窗」的取舍。

## Decisions

1. **复用闸，不另写一份**：新增 `freshEmergencyCoordinateAskingForPrecision` 只多做「先问一次、等回答」，然后调 `freshEmergencyCoordinate`。
   两份实现意味着这条安全约束要守两遍。
2. **陪跑员端问、跑者端不问**：跑者端不问的理由是系统弹窗会和「求助未发出」的播报抢读屏焦点；陪跑员一般看得见屏幕，弹窗是最快的出路。
   用途键用陪跑员自己的 `escortVolunteer`（#534 起两端分开；`escortRun` 那条写的是「陪跑志愿者也能看到你在哪」，对陪跑员说不通），
   它的系统文案末尾补了一句「陪跑中代发的紧急求助也才能带上你的准确位置」。
3. **等 15 秒**：`LocationService.requestTemporaryPreciseLocation(for:)` 用的是不带回调的 SDK 接口，只能轮询 `isPreciseLocationOff`（SDK 有带 completion 的版本，改 LocationService 记在 #547）。求助等不起一个没人点的弹窗；超时按仍关着处理，降级出来的本地拨号此刻就能打。
4. **只在「确定没发出去」时弹本地拨号**：`failed` / `cooldown` 都可能是请求到了服务端、回程丢了（见 `reconcile`），
   这时说「求助没有发出去」是假话。只有 `unsentNoLocation` / `unsentSessionExpired` 能如实这么说。
5. **新语境而不是复用 `cloudFailed`**：那一档按跑者写，提示里说「紧急联系人」，无联系人时还追加设置提醒；陪跑员这边只列 120 / 110。

## Risks / Trade-offs

- 弹窗出现后 15 秒内陪跑员没点：求助不发，弹本地拨号。代价是多等 15 秒；替代方案（立刻降级）会让点了「允许」的人白白错过云端求助。
- 系统可能不弹临时精确位置窗（App 不在前台等），或用户点了「保持关闭」：现在都要等满 15 秒才降级（#547 跟进）。
- 等的时间变长，等待期间会话结束或登录过期的窗口随之变大：`trigger` 取完坐标后复查会话代号与登录过期（这个任务不是倒计时任务，`reset()` 取消不到它）。
- 立刻失败（没同意共享位置、登录过期）时，确认框 / 面板还在收起动画里：弹窗等 400 毫秒再出，否则 iOS 16 会丢掉其中一个。
