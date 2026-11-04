## Context

- 无声拒绝（`AGENTS.md` §5）：客户端不许计算或显示磨合轮次与对方表态。
- `BlindIntroCallView`、`VolunteerIntroCallView`、`IntroCallModels.swift`、`VolunteerOrderFlowStep.swift`、`VolunteerOrderFlowViews.swift`、`VolunteerOrderV2.swift`、`BlindOrderFlowStep.swift` 都在 SwiftLint baseline 里，类型体与文件长度只许变短。
- 订单详情带 `tetherPreference`（`TETHER_ROPE` / `ARM_HOLD` / `VERBAL_ONLY` / `NOT_SPECIFIED`），两端都能读到。
- 派单摘要 `GET /api/volunteer/dispatch-summary` 带 `totalCompleted`。陪跑员订单页的 view model 此前只在完成时拉它。
- #656 已有「使用帮助」，第一次打开约好那两态的订单页时自动弹一次。

## Goals / Non-Goals

**Goals:**

- 误触的三个退出动作都多一步确认。
- 提醒和说明都放在用户做那件事的那一页。
- 判定写成纯函数，能单测。

**Non-Goals:**

- 一次性见面暗号（要后端生成并下发两端，开后端 issue）。
- 改派单规则、改通话窗口长度。
- 改 `PUT /intro-call/plan` 的提交与错误处理（#667）。

## Decisions

### D1. 确认挂在按钮自己身上，按钮抽成独立视图

`BlindIntroCallDeclineButton`、`VolunteerIntroCallDeclineButton`、`VolunteerIntroCallUnreachableButton` 各自持有 `@State` 与 `.alert`。原视图的类型体因此变短，过得了棘轮。确认按钮不标 `.destructive`：「更换陪跑员」是平权的退出，红色在本 App 专指求助。

### D2. 「未接到来电」按本次启动里第一次看到通话页的时刻计时

后端没有窗口开始时刻，窗口长度是后端配置。按订单号记在内存里：退出再进不重新计时；杀掉 App 后重新计时，宁可多等也不提前。常量 `IntroCallCopy.volunteerUnreachableDelayMinutes = 5`，理由写在常量上。

### D3. 手机号说明拦在邀请卡的唯一出口

邀请卡的「接下这次陪跑」「有意向」都走 `VolunteerTabView` 的 `onRespond`。没说过就先弹说明，按「知道了，继续」才发。锁屏通知上的「接受」没法弹说明，第一次只打开邀请卡。按账号记（键里带 userId），UI 用例默认跳过，专门的用例设 `AIDRUN_UI_TEST_FORCE_PHONE_SHARE_DISCLOSURE=1`。

### D4. 带绳提醒按 `tetherPreference` 判，没给就照常提醒

`GuideRopeReminder.remindsToBringRope`：只有 `ARM_HOLD` 与 `VERBAL_ONLY` 不提醒。多带一根绳没有代价，到现场没绳就开不了跑。只在 `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` 给。

### D5. 首单要点并进「使用帮助」，不另弹

「使用帮助」本来就在第一次打开订单页时自动弹。同一刻再弹提示框，两层会抢。首单标签判据是 `totalCompleted == 0`，拉不到就不显示。

## Risks / Trade-offs

- 首单标签依赖一次额外的派单摘要请求。失败只是少一个标签。
- 「使用帮助」按设备记「看过」，不按首单。看过帮助的老陪跑员换号后的首单不会再弹要点，但标签还在。
- 姓氏谁都能说，核对姓氏只是第一步。暗号等后端。
