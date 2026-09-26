## 1. 兜底视图

- [x] 1.1 新增 `VolunteerOrderFallback.resolve(status:errorMessage:)` 并补单测（加载中 / 失败 / 未知状态 / `REMATCHING`）
- [x] 1.2 `VolunteerInServiceView` 的第三路换成 `FlowOrderNavBar` + `EmptyStateView` / `ProgressView`，求助走本地拨号；系统导航栏统一隐藏

## 2. 删除旧路径

- [x] 2.1 删除 `legacyMapContent`、`VolunteerServiceMapBackdrop`、`VolunteerMapLegend`、`VolunteerServiceMapPresentation`、`VolunteerServiceMapLayout`
- [x] 2.2 删除 `VolunteerServiceBottomPanel`、`VolunteerServiceStageHeader`、`VolunteerServiceRunnerCard`、`VolunteerServiceOrderEssentials`、`VolunteerServiceActions`；`VolunteerServiceActionKind` 收窄到 3 个 case
- [x] 2.3 删除 / 改写引用它们的单测与 UI 测试断言

## 3. 文档与验证

- [x] 3.1 `docs/05-page-specs.md` 页面 13 删除地图背景相关几行
- [x] 3.2 编译门禁 `build-for-testing` 通过
- [x] 3.3 真机跑覆盖改动的 suite，按 result bundle 核对每个 suite 都执行了
