## Why

陌生人线下见面的产品必须能举报人、能不再和某人匹配：这是 App Store 审核指南 1.2 的送审要求，也是人身安全底线（#524）。后端举报与拉黑接口（backend#909）和订单详情的 `counterpartUserId`（backend#916）已合入，iOS 还没有任何入口；后端新增的 `ACCOUNT_SUSPENDED` 现在会被念成未知错误文案。

## What Changes

- 两端在留言旁、已完成订单的评价区、订单详情、跑后记录详情、通话页、固定搭档页加「举报」。原因只用后端枚举，举报目标只取后端下发的 id。
- 同样的位置（留言除外）加「不再匹配此人」，要二次确认，确认后立即生效。
- 「我的」页加「已拉黑的人」列表，可以解除，解除也要二次确认。
- 「我的」页加「上报问题」。账号停用的提示要说清谁能帮，而跑者端此前没有任何联系客服的入口。
- 新错误码：`ACCOUNT_SUSPENDED`、`SUPPORT_TICKET_LIMIT_EXCEEDED` 映射并朗读后端 message；`FAVORITE_VOLUNTEER_NOT_ELIGIBLE` 改念后端 message，这样「你已拉黑对方，请先解除」才念得出来。
- 陪跑员派单摘要识别 `ACCOUNT_SUSPENDED`，首页滑块不许滑开并说清原因。
- 对象不符合条件的 404 一律同一句通用文案，不区分原因。

## Capabilities

### New Capabilities

- `user-report-and-block`：举报、不再匹配此人、已拉黑的人，以及入口的显示判定。

### Modified Capabilities

- 无（既有 spec 的需求不变，错误码映射写进上面的新能力）。

## Impact

- 模型：`OrderDetailResponse`、`IntroCallView` 加 `counterpartUserId`（宽容解码）；`ErrorCode`、`VolunteerDispatchNotAvailableReason`、`VolunteerAvailabilityStatus` 加值。
- 服务：`SafetyServing` 加四个方法，新端点 `POST /api/reports`、`POST|DELETE /api/users/{userId}/block`、`GET /api/users/blocked`。
- 界面：`Shared/` 新增举报页、安全动作组件、已拉黑列表；两端订单页、记录详情、通话页、固定搭档页、设置页接入。
- 不动求助判定，不新增求助入口。被拉黑方的任何界面都不变。
