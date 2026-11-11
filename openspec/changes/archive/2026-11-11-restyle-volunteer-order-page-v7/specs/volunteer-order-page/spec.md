## ADDED Requirements

### Requirement: 陪跑员订单页与盲人端订单页 v7 同一套版式
陪跑员订单页 SHALL 使用盲人端订单页 v7 的版式（#945）：邀请详情、通话磨合、已约好、跑者已取消为顶栏 + 深色头 + 五步竖线（只展开当前一步）+ 底部一枚深色主按钮；出发、汇合、完成为地图常驻 + 抽屉。五步为「接下陪跑 → 商量见面安排 → 等出发 → 去集合点汇合 → 开跑」。「我去不了」SHALL 在顶栏「···」里。页面动效 SHALL 只用淡入淡出、当前步圆点与竖线生长。

#### Scenario: 跑者取消
- **WHEN** 跑者在已约好之后取消
- **THEN** 竖线五步全部画出，「等出发」那一步打叉并写「跑者在这一步取消了」，读屏念「等出发，在这一步取消了」

#### Scenario: 出发后
- **WHEN** 订单变成 `DRIVER_EN_ROUTE`
- **THEN** 页面换成地图 + 抽屉，抽屉里有快捷回复与「导航去集合点」，竖线拉起抽屉才显示

## REMOVED Requirements

### Requirement: Rope is a single accessible element and motion respects Reduce Motion
**Reason**: v7（#945）陪跑员订单页不再画引导绳；动效规则并入「陪跑员订单页与盲人端订单页 v7 同一套版式」。
**Migration**: 无数据迁移；进度改由竖线表达，竖线读屏规则同盲人端。

### Requirement: Hero card colour follows the order state
**Reason**: v7（#945）不再有按状态着色的头卡，①–④ 统一深色头，⑤–⑧ 为地图。
**Migration**: 无数据迁移。
