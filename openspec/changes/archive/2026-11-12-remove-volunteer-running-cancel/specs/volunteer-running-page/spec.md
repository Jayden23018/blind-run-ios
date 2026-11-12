## MODIFIED Requirements

### Requirement: 跑步中使用 v7 地图页
订单状态为 `IN_PROGRESS` 时，陪跑员订单页 SHALL 显示 v7 页面（#945）：上半屏地图（跑者位置、集合点、跑者已跑的实时轨迹）、下半屏抽屉（标题「和{姓}一起跑步中」、距离 / 用时 / 配速、目标进度）、顶栏（返回、右上求助胶囊）。实时轨迹 SHALL 取同一次 `GET /api/orders/{id}/track` 的主路线坐标，不足两个点时不画。页面 SHALL NOT 显示系统导航栏。最大字号或横屏时 SHALL 不画地图、抽屉占满。

#### Scenario: 从汇合页开始跑步
- **WHEN** 订单从 `DRIVER_ARRIVED` 变成 `IN_PROGRESS`
- **THEN** 抽屉内容原地换成跑步数据，地图不重建，右上求助胶囊为红底白字

#### Scenario: 暂停时标题换暂停文案
- **WHEN** 跑步中订单进入暂停
- **THEN** 抽屉标题换成「已暂停 · 计时停在 mm:ss」并显示「暂停期间不计志愿时长」，底部出现「继续陪跑」

#### Scenario: 跑步中画实时轨迹
- **WHEN** 跑步中 `/track` 返回的主路线有两个以上坐标
- **THEN** 地图画出这段路线；拉取失败时保留上一次的路线，不清空

## REMOVED Requirements

### Requirement: 跑步中保留取消入口
**Reason**: 负责人 2026-11-12 批准 #962 补齐稿时定「跑步中取消陪跑的按钮不要」，并选「整个删掉」而不是收进「···」（`docs/ui/mockups/volunteer-order-v7-parity-20261112/DECISION.md` 第 3 条）。
**Migration**: 跑步中要离开，走右上角求助面板（暂停 / 联系客服 / 紧急求助）或长按 2 秒结束陪跑。跑步前各态的取消入口不变。
