## Context

- 面板 `VolunteerRunHelpPanel` 由宿主 `VolunteerOrderFlowViews.swift` 以 sheet 弹出；紧急按钮走 `safetyLongPress`
  （长按直发、轻点弹确认框），回调 `onEmergency` → `enterEmergency` → `EmergencyCoordinator`。
- #376 让协调器在暂缓期间拒发云端求助（`blockCloudSOSForExpiredSession`），所以云端那条路本来就发不出去，
  缺的只是入口直接给拨号。
- 跑者端同一件事的做法：`BlindHomeSOSMode.localCallSessionExpired` + `EmergencyCallContext.runnerSessionExpired`。

## Goals / Non-Goals

**Goals:** 暂缓期间面板紧急按钮直接给本地拨号；文案说清登录已过期、App 不会代你发送求助；非暂缓零变化。

**Non-Goals:** 不改面板其余三行（暂停 / 响铃 / 客服工单在暂缓期间同样会 401，另记 issue）；不改宿主的 `onEmergency`；
不动 `VolunteerOrderSOSMode`（右上角胶囊在跑步中仍打开面板，入口不变）。

## Decisions

1. **拨号框挂在面板内部，不在宿主里「关 sheet 再弹拨号框」。** 后者要在 sheet 收起动画和 `confirmationDialog`
   之间排时序，#376 时就因此没做；在 sheet 内弹 `confirmationDialog` 没有这个问题，宿主也只需多传一个 Bool，
   与并行中的 #358（同一宿主文件）冲突面最小。
2. **判定落成纯函数 `VolunteerRunEmergencyMode.resolve(isSessionExpired:)`**，标题 / 副标题 / 读屏标签都按模式取，
   单测能直接钉住两档的差别。
3. **本地拨号这一档没有长按、不经 §6 确认框。** 确认框那句锁定文案说的是「进入求助状态」，而这里什么状态都不会进入；
   拨号框本身就是一次确认（要选号码）。与跑者端求助条 `.localCallSessionExpired` 一致。
4. **这一档不因 `coordinator.state.isBusy` 置灰。** 本地拨号与协调器无关，协调器卡在忙态时拨号更不能被挡住。
5. **新语境 `volunteerSessionExpired` 弹窗正文复用 `sessionExpiredCallDialogMessage`**（那句不提联系人，对两端都成立），
   读屏提示另写一句只列 120 / 110；`appendsNoContactHint` 改成穷举 switch，陪跑员两档都不追加「尚未设置主紧急联系人」。

## Risks / Trade-offs

- 暂缓期间面板里另外三行仍可按且会失败（401 被限频补念接住），本变更不处理 —— 已在 Non-Goals 写明并另记 issue。
- 真机验证依赖设备在线；离线时 PR 保持草稿。
