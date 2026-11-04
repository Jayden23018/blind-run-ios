## Why

11-09 受控公开前的审计（#656，F-2、B-17、V-13、V-36）发现：App 里多处文案叫用户「联系客服」，但入口要么叫「上报问题」，要么根本没有；提交工单之后看不到回复；陪跑员端没有使用帮助。

- 「我的」页（两端共用的 `AccountSafetySettingsRows`）已有一行「上报问题」，但文案都写「联系客服」，名字对不上。
- 提交后只调 `POST /api/support/tickets`，没有「我的工单」。后端 `GET /api/support/tickets` 已经返回状态与客服回复（`csReply`）。
- 工单页写「不会立刻有人联系你」，跑步中的面板写「客服会尽快联系你」，两处口径不一致，后一句还是没人兑现的承诺。
- 陪跑员端没有使用帮助。盲人端有帮助页，陪跑员端的确认、出发、到达、开跑、结束、求助只能边用边猜。

负责人 2026-11-04 定口径：不承诺回复时限；写「会有工作人员查看，不是即时通道；紧急情况请拨 120 或 110」。

## What Changes

- 「我的」页入口改名「联系客服」，旁边加「我的工单」。两端共用同一组行，盲人端和陪跑员端同时得到。
- 新增「我的工单」页：列出自己提交过的工单，显示状态（等待查看 / 已回复 / 已关闭）和客服回复；读取失败时说清并给重试。
- 工单页、跑步中面板、派单规则说明页的文案统一为不承诺时限，并指向真实存在的入口。
- 新增陪跑员使用帮助页：一单怎么走完，出事找哪里。设置页加入口；第一次进入订单页时自动打开一次，本机记住。
- 指向「上报问题」的账号停用提示改指「联系客服」。

## Capabilities

### New Capabilities

- `support-tickets-and-volunteer-help`: 联系客服入口、我的工单、不承诺时限的文案、陪跑员使用帮助。

### Modified Capabilities

- `user-report-and-block`: 账号停用提示里指向的入口名由「上报问题」改为「联系客服」。举报流程本身不动。

## Impact

- iOS：`Shared/SupportTicketView.swift`、`Shared/UserReportView.swift`（入口行）、`Core/Models/SupportTicketModels.swift`、`Core/Services/SafetyService.swift`（加读取）、`Core/MockAPIClient.swift`；新建工单列表页与 `Volunteer/VolunteerHelpView.swift`。
- 契约：只用已有的 `GET /api/support/tickets`（`listMine`），不改。
- 后端依赖（不等）：blind-run-backend#899 定谁来看工单。没定时入口照样能提交，只是可能没人回，所以文案不承诺回复。
- 不改 `BlindRunnerHelpView.swift`（#657）和错误提示文案（#659）。
