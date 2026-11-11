## Why

负责人 2026-11-11 反映两端订单页设计语言割裂：盲人端订单页已是 v7（深色头 + 竖线，出发起地图 + 抽屉，右上角求助胶囊），陪跑员端整条流程仍是 09 月 v2（彩色头卡 + 引导绳 + 卡片 + 底部动作区），动效也是两套。负责人定「陪跑员端整套换 v7」，看过九屏模拟图后同意（`docs/ui/mockups/volunteer-order-v7-20261111/`，issue #945）。求助入口的样子与「我去不了」入口位置都变了，按 AGENTS §10 第 5 步属大档。

## What Changes

- 邀请详情、通话磨合、已约好、跑者已取消：顶栏 + 深色头 + 白底抽屉（五步竖线，只展开当前一步）+ 底部一枚深色主按钮，外壳复用盲人端 `BlindOrderStageScaffold`。
- 出发、汇合、跑步中、完成：上半屏地图常驻（集合点、跑者位置、本机位置；完成画整条路线）+ 下半屏抽屉，外壳复用盲人端 `BlindOrderTrackingView`。快捷回复、外部导航、方位盘、响铃、走散 / 电量 / 定位提示、长按结束都进抽屉或底栏。
- 顶栏右上角「求助」胶囊样子同盲人端；走云端还是本地拨号仍只读 `VolunteerOrderSOSMode.resolve`（跑步页与通话页原先写死，改为读判定，行为不变）。求助面板、二次确认文案、长按时长都不变。
- 「我去不了」收进顶栏「···」，与举报 / 不再匹配此人同一个菜单。通话页的「不合适」「未接到来电」留在底部（两枚都自带确认与延时出现规则）。
- 动效只留淡入淡出、当前步圆点、竖线生长；去掉弹簧、缩放、滑入与绳子画出。
- 共用件只做加法：竖线加陪跑员措辞、中断那步的打叉与宽行距；外壳顶栏改为协议；地图图钉名可换。盲人端外观不变。

## Impact

- 代码：`blindRun/Volunteer/VolunteerOrderFlowPage.swift`、`VolunteerIntroCallView.swift`、`VolunteerInServiceView+Flow.swift`、`VolunteerInServiceView+Fallback.swift`、新 `VolunteerOrderTopBar.swift`；共用 `BlindOrderTimeline*.swift`、`BlindOrderStageView.swift`、`BlindOrderTopBar.swift`、`BlindOrderTracking*.swift`、`DirectionDial.swift`。
- 契约：无改动。
- 测试：UI 用例里「我去不了」的入口改为「···」，跑步页底栏 identifier 改为 `volunteerOrderFlowBottomBar`。负责人 11-05 定不跑真机测试，由负责人自己验。
