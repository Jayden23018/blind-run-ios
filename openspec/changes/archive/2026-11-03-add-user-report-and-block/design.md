## Context

后端契约写在 Jayden23018/blind-run-ios#524 的两条评论和 `docs/api_spec.yaml`。`SupportTicketView` 是现成的事后工单页，但只有陪跑员订单页在用，跑者端没有联系客服的入口。没有设计稿；按 `docs/ui/design-direction.md` 的安全场景走最克制的一档。

## Goals / Non-Goals

**Goals:**
- 两端能举报、能不再匹配、能解除，所有控件读屏可用、触达区 64pt。
- 显示判定、请求构造、错误处理都是纯逻辑或 view model，能单测。

**Non-Goals:**
- 不做工单列表与举报进度页（客服回复走既有通知）。
- 邀请卡片不放入口，它不下发对方 id。
- backend#915 列的几种够不到的人不在客户端猜，见 Risks。

## Decisions

1. **方法加进 `SafetyServing`，不开新 service。** 事后工单已经在这一片，少一个 `AppState` 属性，替身也现成。
2. **三个共享件放 `Shared/`：** `UserReportView`（举报页）、`CounterpartSafetyActions`（两枚按钮、确认与结果）、`BlockedUsersView`（列表）。各入口只传 `CounterpartSafetyTarget`，确认和文案只有一份。
3. **判定集中在 `CounterpartSafetyGate`：** 三个纯函数管「有没有目标」「这一态放不放」「这条留言能不能举报」。视图里不写条件。
4. **跑步中页不放入口。** `design-direction.md` §6 要求这一屏最克制，只留求助。跑步结束后订单页和记录页都能举报。这是对「订单详情加举报」的收窄，写进交接。
5. **`counterpartUserId` 用 `LenientOptionalInt64` 解码。** 它只决定入口出不出现，类型不对不值得让整张订单失败。
6. **记录详情额外读一次订单详情拿 id**（`appState.orders.orderDetail`）。读失败就不显示入口，不打断记录页。
7. **账号停用的文案：** 后端 message 原样在前，客户端补一句 `serverMessageSupplement`。后端那句没有说原因和客服入口，而任务要求四项齐全。
8. **「上报问题」加到两端的「我的」页，分类 `ACCOUNT`。** 否则「谁能帮」在跑者端是一句空话。这是为错误提示新增的最小入口。
9. **解除也做二次确认。** 读屏误触一次就恢复和这个人的匹配，代价在人身安全上。
10. **`FAVORITE_VOLUNTEER_NOT_ELIGIBLE` 进 `prefersServerMessage`。** 契约要求念「你已拉黑对方，请先解除」，本地文案说不出这句。

## Risks / Trade-offs

- backend#915：跑者只拿得到最后一位陪跑员的 id，陪跑员取消后拿不到跑者 id，邀请拒绝后也没有 id → 通话页与订单详情当场放入口，其余走「上报问题」，写进 PR 交接。
- 页面重进后不知道此人是否已拉黑 → 按钮仍在，再点幂等返回 204，文案仍然真实。不为此多打一次列表接口。
- 后端未部署时入口点了会失败 → 字段为空时入口本来就不显示，上线顺序看后端部署。

## Migration Plan

无数据迁移。后端部署后入口随 `counterpartUserId` 下发自动出现。

## Open Questions

无。
