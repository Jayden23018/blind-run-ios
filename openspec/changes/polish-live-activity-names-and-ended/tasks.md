## 1. 锁屏卡姓氏（PR-A）

- [x] 1.1 `GuideRunActivityContentBuilder.attributes` 的 `runnerSurname` 取 `blindSurname?.nilIfBlank`
- [x] 1.2 `liveActivityPlan` 对 `.volunteer` 也带 `partnerName`；`VolunteerInServiceViewModel.order` 的 `didSet` 传 `blindSurname`
- [x] 1.3 跑者端 `BlindOrderStatusView.apply` 改传 `volunteerSurname`
- [x] 1.4 用例：`GuideRunActivityTests` / `RunLiveActivityTests` 改写并验红

## 2. 朗读用姓氏（PR-B）

- [ ] 2.1 `volunteerNameForSpeech` 优先 `volunteerSurname`
- [ ] 2.2 用例：有姓氏 / 无姓氏 / 同时存在，并验红

## 3. 已结束样式（PR-C）

- [ ] 3.1 `GuideRunActivityPresentation` 加 `isEnded`；widget 两处传 `context.activityState == .ended`，ended 不画绳子
- [ ] 3.2 用例：ended 的按钮、背景、文案、读屏标签；既有用例不变
- [ ] 3.3 归档本变更
