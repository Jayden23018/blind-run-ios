## Why

`add-running-rhythm-pause-and-help-panel`（FE-3）按 DECISIONS-v2 V4「旧跑步页布局不动」把节奏卡、提示条、暂停、求助面板、语音开关加在旧的地图页上。与此同时 #227（`restyle-volunteer-running-page-v2`，负责人 2026-09-26 定）把陪跑员跑步中整页换成 v2 的 `VolunteerRunningPage`，旧页上的挂点全部删除。两者合并时必须把 FE-3 的陪跑员端能力移植到新页面，并改掉两份规格里互相冲突的条文。

## What Changes

- 新页面右上角求助胶囊（云端模式）改为**打开跑步中求助面板**，读屏标签改为「求助与安全」，identifier 仍为 `volunteerServiceSOSButton`；面板里紧急按钮的确认框与云端链路不变。
- 头卡下方「最多一条提示」合并两边的来源：跑者求助已确认 > 走散 > 收不到跑者位置 > 跑者电量低 > 本机定位弱。
- 暂停：头卡底色换成 `statePaused`，小标题「已暂停 · 计时停在 mm:ss」（读 `run.elapsedSeconds`）；「继续陪跑」放进底部栏、在长按结束之上。结束按钮本来就是白底（#227），不再需要「暂停时改白底」。
- 节奏卡与耳机语音播报开关放在提示条之后、求助结果区之前。

## Capabilities

### Modified Capabilities
- `volunteer-running-page`: 求助胶囊的去向与读屏标签；提示条的来源与优先级。
- `running-rhythm-and-help`: 提示条的位置与优先级；暂停的呈现。

## Impact

- 代码：`VolunteerOrderFlowPage.swift`（`VolunteerRunningPage` 新增入参）、`FlowV2Components.swift`（`FlowHelpPill` 云端模式读屏文案）、`VolunteerOrderFlowViews.swift`（宿主接线）、`VolunteerRunningCompanion.swift`（`VolunteerRunningNotice`，删 `VolunteerRunPausedStrip`）。
- 契约：无变化。
