## 1. 模型与服务

- [ ] 1.1 `OrderDetailResponse`、`IntroCallView` 加宽容解码的 `counterpartUserId`，`replacingStatus` 带上
- [ ] 1.2 新增举报原因、举报请求、举报响应、已拉黑项模型与 `CounterpartSafetyGate`
- [ ] 1.3 `SafetyServing` 加 `report`、`blockUser`、`unblockUser`、`blockedUsers`，同步替身与 Mock
- [ ] 1.4 `ErrorCode` 加 `accountSuspended`、`supportTicketLimitExceeded`，处理后端 message 与补充句
- [ ] 1.5 `VolunteerDispatchNotAvailableReason` 与滑块状态识别账号停用

## 2. 界面

- [ ] 2.1 新增 `UserReportView`、`CounterpartSafetyActions`、`BlockedUsersView`
- [ ] 2.2 接入两端订单页（含评价区、只读页）
- [ ] 2.3 接入两端记录详情与留言
- [ ] 2.4 接入两端通话页
- [ ] 2.5 接入固定搭档页
- [ ] 2.6 两端「我的」页加「已拉黑的人」「上报问题」

## 3. 验证

- [ ] 3.1 单测覆盖判定、解码、请求、错误文案、view model，并验红
- [ ] 3.2 真机跑覆盖本次改动的用例
- [ ] 3.3 `build-for-testing` 通过
- [ ] 3.4 改动界面的真机截图与读屏审计
- [ ] 3.5 PR 交接写明跑步中页的收窄与 backend#915 的缺口
