## Why

陪跑员订单页 v2（#210–#216）把邀请到完成都换成了新页面，唯独跑步中（`IN_PROGRESS`）还是旧的地图 + 系统导航栏「服务中」+ 白底大面板：从汇合页按「开始跑步」后整套视觉切回旧风格（#218）。旧页面横屏时底部面板只剩 60pt，「长按结束」挤在一个小滚动区里。项目负责人 2026-09-26 定：按 v2 设计画布的「⑤ 跑步中」做，范围只到数据现成的部分。

## What Changes

- 跑步中改走 v2 页面：自带导航栏（返回 + 「陪跑中」+ 右上求助胶囊）、藏青头卡（「陪跑中 · 集合点」、里程主角数字、目标进度、用时、配速）、底部白色次要按钮「长按 2 秒，结束陪跑」。
- **BEHAVIOR CHANGE**：跑步中不再显示地图。
- 长按结束的外观换成画布样式：按住时从左往右填成黄色，文案「继续按住，还剩 X 秒」。时长、渐强震动、松手即取消、读屏自定义动作全部不变。
- 长按结束下方保留灰色文字按钮「取消订单」（旧页面就有；画布 ⑤ 没画，但删了唯一的退出就只剩「结束陪跑」）。
- 头卡下方最多一条提示条：跑者的求助已确认（客服处理中）优先，其次「暂时收不到跑者的位置」。
- 右上求助胶囊在跑步中走现有云端链路（二次确认 → 服务端倒计时），读屏标签仍是「一键求助，遇到紧急情况时点击」，发送中禁用。
- 删除旧的三数字卡 `VolunteerEscortStatsCard` 与导航栏求助按钮 `VolunteerSOSNavButton`（本变更后无调用方）。
- 不做（后端没有数据，另开后端 issue）：跑者节奏信号、暂停、跑步中让跑者手机响、组织值班电话、跑者电量、求助单 ⑤c。也不做「耳机语音播报」开关（陪跑员端没有播报可开）。

## Capabilities

### New Capabilities
- `volunteer-running-page`: 陪跑员跑步中页面的内容、求助入口、结束方式与提示条

### Modified Capabilities

## Impact

- 代码：`blindRun/Volunteer/VolunteerOrderFlowViews.swift`（宿主路由、长按按钮外观）、`VolunteerOrderFlowPage.swift`（新页面与纯类型）、`Core/DesignSystem/FlowV2Components.swift`（求助胶囊支持云端模式）、`Safety/VolunteerEscortViews.swift` 与 `Safety/SafetyModule.swift`（删死代码）。
- 测试：`VolunteerFinishLongPressTests`、新增跑步中纯类型单测；UI 用例改认新 identifier（`AccessibilityAuditTests` 两条、`blindRunUITests` 三条）。
- 接口：无新增，沿用 `GET /api/orders/{id}` 的 `plannedDistanceMeters` 与 `/track` 的 `blindStats`。
