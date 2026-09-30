## 1. 实现

- [x] 1.1 `VolunteerAchievementsResponse` 新增 `totalDistanceMeters: Int64?`
- [x] 1.2 `VolunteerProfileHeadline` 带 `distanceKm`（向下取整，不足 1 公里为 nil）；`heroSpoken` / `heroRunsDetail` 文案
- [x] 1.3 首屏 `hero()` 有里程时显示公里 + 「共 N 次陪跑」；Mock 补 `totalDistanceMeters`

## 2. 测试

- [x] 2.1 `VolunteerProfileFirstScreenTests`：向下取整 / 回落次数 / 新人无视里程 / 读屏文案 / 解码有值与缺字段
- [ ] 2.2 真机跑 `VolunteerProfileFirstScreenTests` 与 `IncentiveServiceTests`，并验红

## 3. 文档

- [x] 3.1 `docs/ui/mockups/INDEX.md` 首屏一行的偏差列
