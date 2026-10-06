## Why

盲人端订单页的「匹配 / 约好 / 出发 / 汇合」四屏还是 v1 骨架（白卡片 + 四格进度条 + 124pt 头像视觉区 + 信息列表），
陪跑员端 2026-09-26 起已换成 v2 版式（头卡 + 引导绳 + 对方卡片 + 地点行）。项目负责人 2026-10-06 要求两端统一成陪跑员那一套（#349）。

## What Changes

- 盲人端四屏改为 v2 版式：浅色头卡（小标题 + 引导绳 + 大字 + 副文）→ 陪跑员卡 → 信息卡（时间、集合地点、留言、取消 / 遇到问题）。v2 的可点地点卡只在能打开地图时出现，而盲人端订单页目前恒传 `onOpenStartPlace: nil`（没有地图入口，那是另一个需求），所以真机上集合地点仍在信息卡里。四格进度条去掉，「第 N 步，共 4 步」改由引导绳的读屏标签承担。
- 引导绳与对方卡片按视角出文案与头像：盲人端跑者那一侧写「我」，匹配中空心的是陪跑员；读屏念「陪跑员正在赶来」而不是陪跑员口吻的「正在赶去」。
- 倒计时三秒改在头卡里显示大数字。
- **不变**：`BlindOrderFlowPresentation` 的标题、副标题、主按钮、最后一行与全部判定；底部「求助与安全」的位置；跑步中 / 已完成仍在同一页原地变形（焦点不跳顶）；头卡用浅色，不用陪跑员端的彩色状态底。
- 出发屏不显示「N 分钟后到」：后端只给本单陪跑员下发 `eta`（`OrderDetailAssembler.java:317-318`），盲人 token 恒为 null。

## Impact

- 代码：`BlindOrderFlowView.swift`、新增 `BlindOrderHero`（`BlindOrderV2.swift`）、`RopeView.swift`、`FlowV2Components.swift`（`FlowRunnerCard` 加视角参数）、`OrderFlowScaffold.swift`（间距对齐 v2）。
- 测试：新增 `BlindOrderHeroTests`；既有 UI 用例只断言 `blindOrderFlowStatusCard` 等标识存在，标识全部保留。
- 文档：`docs/ui/mockups/INDEX.md` 盲人端订单流程一行回写偏差。
