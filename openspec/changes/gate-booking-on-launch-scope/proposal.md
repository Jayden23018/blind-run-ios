## Why

2026-11-09 受控公开只开放部分城市，只在有人值守的时段接受预约，也可能整个暂不接受预约（#667）。
后端已在建单时拦截（blind-run-backend#896 / #910），并经 `GET /api/config/rules` 的 `launchScope` 下发范围。
iOS 不知道这些限制：盲人填完整张表（或说完一整句、听完读回）才被拒，而三个新 422 只被当成「不认识的码」念一遍后端原文，
不会把用户带回该改的那一步。对看不见屏幕的人，这等于白走一遍下单流程。

## What Changes

- `RuleParamsResponse` 解码可选的 `launchScope`（开放与否、开放城市、值守时段、两句后端拼好的提示）。旧后端没有它，解不出时当作没有。
- 规则参数**按账号**读：登出 / 换账号时清掉，进行中的请求回来时账号已变就丢弃；进入下单入口时强制重读一次。
- 首页预约入口（表单与语音共用）外包一层闸门：`acceptingOrders == false` 时显示并播报 `areaHint`，只给「返回首页」，
  不进表单，也不启动语音下单向导。
- 有限制时，表单「出发地点」一步显示 `areaHint`，「预约时间」一步显示 `dutyHoursHint`；
  当前出发点不在任何 `openAreas` 矩形里、或开跑时刻不在任何 `dutyWindows` 里时，同一处改成「不在开放范围 / 可预约时段内」再接后端那句。
  只提示不阻断，能不能下单以 `POST /api/orders` 为准。没有限制时一个字不提。
- `POST /api/orders` 三个新 422：
  - `ORDER_SERVICE_NOT_OPEN`：下单入口当场换成「暂未开放」告知页，念后端 `message`。不引导改地点或时间。
  - `ORDER_OUTSIDE_OPEN_AREA`：念后端 `message`，表单回到「出发地点」一步。
  - `APPOINTMENT_OUTSIDE_DUTY_HOURS`：念后端 `message`，表单回到「预约时间」一步。
  - 三者都原样显示并播报后端 `message`（`prefersServerMessage`），表单内容不清空。
- 陪跑员见面安排单 `PUT /intro-call/plan`：`APPOINTMENT_OUTSIDE_DUTY_HOURS` 显示在时间那一块下面，
  `ORDER_OUTSIDE_OPEN_AREA` 显示在集合地点那一块下面，都念后端 `message`，已填内容保留。

**不做**：语音下单在开放期间不单独处理（`/parse` 自己把城市外、时段外放进追问，iOS 照常念 `ttsText`）。
首页卡片本身不加提示（入口闸门已在填表之前告知）。客户端不拼城市名、不写死城市、不自己拼时段句子。

## Capabilities

### New Capabilities
- `booking-launch-scope`: 下单前按后端下发的开放范围与值守时段告知盲人，暂未开放时不让进下单流程，并对三个建单拒绝码给出原样播报与回退位置。

### Modified Capabilities

## Impact

- 模型：`blindRun/Core/Models/RuleParamsModels.swift`（新增 `LaunchScopeResponse` 等，可选、宽容解码）。
- 会话：`blindRun/Core/AppState.swift`（规则参数按账号清理、强制重读）。
- 错误码：`blindRun/Core/Models/ErrorModels.swift` 加三个码进 `prefersServerMessage`，本地兜底文案放扩展文件（依赖 #677 先合）。
- 盲人下单：首页入口闸门（新文件）、`BlindBookingView.swift` 两步提示与提交失败回退（提交逻辑搬进扩展文件，冻结文件只变短）。
- 陪跑员见面安排单：`blindRun/Volunteer/VolunteerMeetupPlan.swift` 错误落位。
- Mock：`/api/config/rules` 返回 `launchScope`（默认无限制）。
- 后端契约无改动（已有）。
