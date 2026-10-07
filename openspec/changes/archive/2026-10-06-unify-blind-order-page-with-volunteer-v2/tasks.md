## 1. 实现

- [x] 1.1 `BlindOrderHero` 纯类型：由 `BlindOrderFlowPresentation` + 订单派生小标题、大字、副文、绳子状态；单测穷举。
- [x] 1.2 `RopeView` 加视角（陪跑员 / 跑者）：读屏标签、头像字、匹配态空心一侧、identifier。
- [x] 1.3 `FlowRunnerCard` 加占位字与读屏前缀参数，盲人端复用成陪跑员卡。
- [x] 1.4 `BlindOrderFlowView` 跑步前四屏与倒计时换成 v2 版式；跑步中 / 已完成原地变形保留；底部求助不动。
- [x] 1.5 设计稿索引回写偏差。

## 2. 验证

- [x] 2.1 `build-for-testing` 编译通过；`openspec validate --all --strict`。
- [x] 2.2 真机跑 `BlindOrderHeroTests`、`BlindOrderFlowPresentationTests`、`BlindRunPhaseTests` 与订单页相关 UI 用例（负责人：改完一起测）。
- [x] 2.3 真机目视四屏 + 倒计时 + 跑步中，含 AX5 与深色。
