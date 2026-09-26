## Context

`VolunteerInServiceView` 按 `VolunteerOrderPhase.resolve` 分两条路：能解析出阶段的走 v2 `VolunteerOrderFlowPage`，`IN_PROGRESS` 解析为 nil，落回 `legacyMapContent`（地图 + `VolunteerEscortStatsCard` + `VolunteerServiceBottomPanel`，求助在系统导航栏的 `VolunteerSOSNavButton`，#219）。设计源冲突时以 v2 画布 ⑤ 为准（项目负责人 2026-09-26）。

## Goals / Non-Goals

**Goals:** 跑步中与其他 v2 页同一套外壳；横屏底部按钮保持 64pt；求助入口位置规格（`docs/05-page-specs.md:871`）不退化。

**Non-Goals:** 节奏信号、暂停、跑步中响铃、值班电话、电量、⑤c 求助单、语音播报开关（后端或功能不存在）；删除整条 `legacyMapContent`（加载中与认不出的状态仍在用，另开清理）。

## Decisions

1. **独立页面 `VolunteerRunningPage`，不塞进 `VolunteerOrderFlowPresentation`。** 那套是「信息行 + 引导绳 + 主按钮」的形状，跑步中一样都没有。共享的是 `FlowOrderNavBar`、`FlowHeroCard(.navy)`、`FlowNoticeBar` 与页面底色。
2. **文案与进度放进纯类型 `VolunteerRunningHero`。** 进度、目标文案、提示条优先级都是分支逻辑，本仓库 XCTest 只能真机跑，纯类型的用例最便宜。
3. **头卡用藏青（`stateAgreed`），不用画布的青绿。** 项目负责人 09-26 选定藏青；之后合入的 #229 把头卡改成按状态着色（约好 / 出发 / 汇合 / 完成），但没给跑步中定色，`AppColors.Flow` 仍没有青绿，`design-direction.md` 不许顺手新增强调色。要换青绿需另行拍板。
4. **不标「折返」。** 画布的「2.50 折返」默认原路往返，契约里没有路线形状字段；只显示剩余与目标。
5. **保留返回箭头。** 画布跑步中没有返回，但这一页藏了标签栏，代码里的不变量是「每一屏都有出口」。
6. **求助胶囊加云端模式**：`FlowHelpPill` 接受 `isCloud` / `isBusy`，云端时读屏标签用 `EmergencySafetyCopy.accessibilityLabel`、identifier 沿用 `volunteerServiceSOSButton`，守着 #219 的两条用例不用换判据。宿主用一个 `@ObservedObject` 包装读 `coordinator.state.isBusy`（嵌套 ObservableObject 不重新发布）。
7. **长按按钮只换外观**：环形换成填充，`VolunteerFinishLongPress` 的时长、震动表、读秒算法不动；`ringProgress` 改名 `fillProgress`，删掉不再用的环形尺寸常量。
8. **保留「取消订单」**：画布没画，但旧页面有、`AGENTS.md` §5 允许志愿者在 `IN_PROGRESS` 取消（→ `REMATCHING`）；只剩「结束陪跑」会把没跑完的单记成完成。做成灰色文字按钮，不抢长按结束的视觉重量。

## Risks / Trade-offs

- [去掉地图后陪跑员看不到跑者在哪] → 位置不新鲜时有提示条；跑步中两人并肩，地图本来就少用（画布与《跑步中与跑后》规格都禁止地图）。
- [提示条在刚进页、第一条位置还没到时会闪一下「暂时收不到」] → 与旧卡片行为一致，接受。
- [`legacyMapContent` 里的跑步中分支变成死代码] → 保留到清理任务，不在本变更扩大范围。
