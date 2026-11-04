## Why

负责人 2026-11-05 在真机上看到：没学完培训时，陪跑员首页顶部一直挂着「需要你处理」，里面是培训卡、资质入口或「请等待管理员审核通过」一类的句子。而底部胶囊已经写着「暂不能接单 · 还没完成必修培训，点这里看进度」，点进去的接单前进度页列出实名、人脸、证书、审核、培训五步并各有入口。同一件事说了两遍，还挡住首页的视野。负责人原话：「下面的按钮暂不能接单就已经显示了他需要做的东西了」，决定去掉这三类提醒（#706）。

## What Changes

- 首页「需要你处理」不再显示必修培训卡、资质上传入口、接不了单的原因句。
- 保留：进行中的订单、跨天预约确认（有 60 分钟期限，仍在首屏最上方）、定位异常与「重新定位」、加载出错与「重试加载」。
- 接不了单的原因改由底部胶囊（「暂不能接单」+ 点按去接单前进度页）说。接单页的派单状态卡不再省略培训、资质两条原因：作业区已经不说它们了。

## Capabilities

### New Capabilities

无。

### Modified Capabilities

- `volunteer-profile-first-screen`: 新增「作业区只放有时限或要当场处理的事」一条要求。

## Impact

- `blindRun/Volunteer/VolunteerProfileFirstScreenView+Todo.swift`、`VolunteerProfileFirstScreen.swift`（删作业区两道闸与培训卡文案）、`VolunteerHomeCards.swift`（派单状态卡不再省原因）、`VolunteerHomeView.swift`、`VolunteerModule.swift`（删只给作业区用的拦截句与参数）。
- 单测与两条 UI 用例跟着改。不涉及后端契约。
