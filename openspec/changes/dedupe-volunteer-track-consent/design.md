## Context

两张同意页的来源（见 proposal.md）：

- 同行态：`LiveEscortSessionCoordinator.pendingTrackConsent` → 根部 `EscortTrackConsentOverlay`。协调器在 `updateOwnedOrder` 之后的下一拍（`scheduleReconcile`）才把 `pendingTrackConsent` 置上。
- 恢复待命 / 接单开关：`VolunteerHomeViewModel.trackConsentRequest` → `VolunteerTabView` 的 `fullScreenCover`。`configure` 时就用缓存的个人资料判一次，此时首份接单摘要还没到，手上有没有同行态的单还不知道。

已有的一半联动：`AppState.recordLocationTrackConsent` 会调 `trackConsentDidChange()`，在首页那张同意时根部那张会收起。反方向和拒绝都没有联动。

协调器在登录时（`AppState.webSocketService` 的 didSet，Mock 下由 `connectWebSocketIfNeeded` 补配）就拿到身份与角色，所以首页拿到摘要、把订单交给协调器之后，协调器可以**同步**回答「这一单要不要问」。

## Goals / Non-Goals

**Goals:**
- 任何时刻界面上至多一张陪跑员位置轨迹同意页。
- 同行态那张上的回答对恢复待命同样生效。

**Non-Goals:**
- 不改盲人端（盲人的预约前同意由用户主动点按钮触发，不会与同行态同时自动弹出）。
- 不改同意页本身的文案、布局与 `PresenterAccessibilityHider`。

## Decisions

1. **同行态优先，由首页让开，而不是反过来。** 根部那张盖在整个界面上、而且这一单的位置共享在回答前一直停着，更急；它的拒绝文案也说的是这一单的后果。备选「恢复待命那张优先」要再补一句同行态横幅，被负责人否掉。

2. **恢复待命那一问等首份摘要到了再判，且放在把订单交给协调器之后。** 首页在 `apply(summary:)` 里先 `updateOwnedOrder`，再问协调器同步谓词 `needsTrackConsentForActiveOrder`（同行态、有身份、没同意、这一单没拒绝过）。备选「先弹、等协调器问了再收」会在冷启动时闪一张再收，读屏会先念半句，UI 用例「任何时刻只有一张」也会偶发红。

3. **协调器用一个回调把「开始问」「拒绝了」告诉首页**（`onVolunteerTrackConsentQuestion`，`@MainActor` 闭包，首页在 `configure` 里挂上）。
   - 「开始问」：首页收起自己手上的请求（兜住 WS 推送把单推进同行态、而首页那张已经弹着的情况）。
   - 「拒绝了」：首页记 `declinedResumeTrackConsent`，开关开着就关掉并留下不念的说明。
   - 备选：首页订阅 `pendingTrackConsent` 的 Combine publisher —— 首页 view model 已经同时持有 `AnyCancellable` 和 `Task`（历史遗留），AGENTS.md 要求新代码不再加深混用；且 publisher 区分不了「拒绝」和「订单结束」。备选：视图层 `onChange` 桥接 —— 单测够不着，且依赖视图在屏上。
   - 同意不需要事件：同意记录是同一条，首页那一问的守卫自然不成立。

4. **拒绝说明不念。** 根部横幅在 `healthState` 变化时念同行态那一句；首页再 `speak` 一句会切断它（记忆 `later-speak-silently-cuts-the-earlier-one`）。

## Risks / Trade-offs

- [协调器还没配身份时摘要先到，同步谓词答 false，首页先弹] → 「开始问」事件随后把首页那张收起；只在身份晚于摘要时出现，登录流程里不发生。
- [单一闭包属性，后挂的覆盖先挂的] → 只有陪跑员首页 view model 挂；每次登录一个实例。
- [拒绝同行态位置共享会顺带让他下线接单] → 负责人选定的取舍，滑块上方留说明，想接单再滑开关会重新问。
