## Context

- `GuideRunAttributes` 起卡后不可变；出发/汇合卡在 `DRIVER_EN_ROUTE` 起，此时订单已带 `blindSurname`。
- 跑步卡的名字住在 `ContentState.partnerName`（可后到）。陪跑员端 `liveActivityPlan` 此前恒传 `nil`（2026-09-16 旧决定，已被决定源 V11 取代）。
- 出发/汇合卡由后端 APNs `end`（`dismissal-date` +5 分钟）结束，`content-state` 沿用最后一帧；两个本地控制器 `end()` 都是 `.immediate`。

## Goals / Non-Goals

**Goals:** 锁屏卡与朗读通道不再出现掩码名；已结束的出发/汇合卡不再显示过期 ETA 与按钮。
**Non-Goals:** 改屏上可见的掩码名（`OrderDisplayHelpers` 注释写明「视觉保留掩码、朗读去掩码」，属设计决定）；跑步卡的 ended 样式（无 push token 且立即结束，没有可见场景）；完成页「第 N 次」。

## Decisions

- `runnerSurname` 取 `blindSurname?.nilIfBlank` 而非 `runnerShortName`：后者兜底「跑者」，引导绳圆点会写成「跑」。
- 跑者端锁屏顶行姓氏缺失时整行不出现（沿用 `partnerName == nil` 语义），不退回掩码名。
- `volunteerNameForSpeech` 一个咽喉点覆盖五处朗读：`volunteerSurname` → 现有去星号掩码名 → 「这位志愿者」。
- 已结束样式复用 `LiveActivityStatePalette.statePaused`，不新增色。
- **已结束靠 `ContentState.phase == .ended` 判，不靠 `activityState`**：iOS 26.2 SDK 的 WidgetKit swiftinterface 里 `ActivityViewContext` 只有 `activityID` / `attributes` / `state` / `isStale`，`activityState` 只在 app 侧的 `Activity<_>` 上。后端 `docs/live-activity.md` 与 #281 都写「按 `activityState == .ended` 画」，在 widget 里做不到。`Phase` 本来就是响应向开放枚举，加 `ended` 向前兼容。

## Risks / Trade-offs

- 升级前起的出发/汇合卡 `attributes` 不可变，认回后姓氏一直为空。
- 在后端 `end` 推送带 `phase:"ended"` 之前，已结束样式不会出现（iOS 侧是休眠的、无副作用）。
- 后端若迟迟不下发 `volunteerSurname`，跑者端锁屏顶行整行消失（比显示「张*」更安全）。
