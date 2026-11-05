## 1. 数据与口径

- [x] 1.1 `VolunteerRunDataSummary` 纯函数：日历、四档里程、陪伴时长、提要、一起跑的人、个人纪录
- [x] 1.2 本周 ISO 周号与 `lastCreditedWeek` 比较
- [x] 1.3 单测：跨年周、空周、`distanceM` 为 null、最长连续、当前周未结束、注销搭档

## 2. 页面

- [x] 2.1 `VolunteerRunDataModel` 并发拉近 12 个月，先到先画，失败可重试
- [x] 2.2 `VolunteerRunDataView` 八块内容与读屏摘要；AX3 及以上日历换按月列表
- [x] 2.3 首页 `halfCard` 有连续周数时去数据页；摘要带上 `lastCreditedWeek`
- [x] 2.4 新增里程靛蓝与日历五档色，对比度用例

## 3. Mock 与验收

- [x] 3.1 Mock 近半年有起伏的样例数据（launch 环境变量打开）
- [x] 3.2 UI 用例：点连续陪跑卡进数据页、切里程档、`performAccessibilityAudit`
- [ ] 3.3 真机截图对照定稿打分；定稿进 `docs/ui/mockups/volunteer-run-data-20261105/` 并在 INDEX 加一行
