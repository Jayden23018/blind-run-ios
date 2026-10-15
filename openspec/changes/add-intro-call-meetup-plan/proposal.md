## Why

接单前通话（`PENDING_INTRO_CALL`）现在只有「合适 / 不合适」两个表态：电话里商量好的改时间、换集合点、在哪儿见、穿什么颜色，都没有地方记，盲人也无从核对。负责人 2026-10-15 批准了「见面安排单」设计（`docs/design/2026-10-15-intro-call-meetup-plan-design.md`）与视觉稿 v2（`docs/ui/mockups/intro-call-meetup-plan-20261015/`）：陪跑员把电话里说好的写下来，盲人听完朗读、确认后才生效。

## What Changes

- 新增「见面安排单」：挂在本轮通话上，可改开跑时间、集合地点，可补具体见面位置与双方上衣颜色；每次提交版本 +1，并清掉盲人之前的确认。
- 通话步骤拆成子状态：盲人端 B1 待通话 / B2 等安排 / B3 听安排做确认，陪跑员端 V1 等来电 / V2 填安排 / V3 等跑者确认 / V4 结局。订单状态白名单**不加新值**。
- 盲人端 B3 逐项朗读安排单：只有变更项念「由 X 改为 Y」，地点另念离原地点多远，不认识的颜色那一行不念。
- 「打完电话回来」只认 App 从**后台**回到前台；拨号确认框取消、权限弹窗造成的短暂失活不算。
- 通话窗口倒计时常驻显示，平时静默，只在剩 5 分钟、剩 1 分钟各主动播报一次；不足 1 分钟显示「不到 1 分钟」而不是消失。
- 陪跑员主按钮从「合适，接这一单」改为「填写见面安排」；盲人端去掉 v6 的「聊过了，合适」。
- 依赖后端新端点 `PUT /api/orders/{id}/intro-call/plan` 与 `decision` / `GET /intro-call` 的改动（Jayden23018/blind-run-backend#755），新增错误码 `INTRO_CALL_PLAN_STALE` / `INTRO_CALL_PLAN_REQUIRED`。

## Capabilities

### New Capabilities
- `intro-call-meetup-plan`: 接单前通话之后，陪跑员提交见面安排单、盲人听完确认才生效的整套行为，含子状态、朗读、回前台判据、倒计时与异常处理。

### Modified Capabilities
<!-- 现有规格没有覆盖接单前通话这一步（blind-order-page / volunteer-order-page 只管约好之后的四步），不改它们。 -->

## Impact

- 代码：`blindRun/Core/Models/`（新增安排单类型与纯函数）、`blindRun/BlindRunner/` 与 `blindRun/Volunteer/` 的通话页、`APIClient` 端点、`MockAPIClient`、错误码映射。
- 契约：后端 Jayden23018/blind-run-backend#755 合并前，iOS 只能做本地类型与纯逻辑（pre-push 契约门禁会拦未在契约中的路径）。
- 分批落地：Jayden23018/blind-run-ios#436（本地类型与纯逻辑）→ #432（端点、解码、Mock、错误码）→ #433（陪跑员端界面）/ #434（盲人端界面）。
- 安全：改集合点 = 陌生人能指挥盲人去哪。实现端点与地点变更时必须叫 security-reviewer。
