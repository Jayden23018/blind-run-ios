## Context

- 同意按账号存在本机（`PrivacyConsentStore`，`revokeConsent` 已有）。语音同意由 `ConsentGatedVoiceOrderService` 每次调用现读，删掉记录闸门立刻生效。
- 视力同意的撤回（#352）要把服务端那两项改成「未提供」，靠资料页整表单保存；#474 已在真机验过（`passed=151 failed=0`）。
  契约 `BlindProfileUpdateRequest` 只写了 `guideDog` / `guidePreferenceText` 的「不带键 = 保留原值」，其余字段缺省语义没写，所以不另造部分更新。
- 位置同意（#368）：`AppState.hasLocationTrackConsent` 现读；#425 起盲人角色的持续定位由 `syncRoleLocationIntents` 按同意现算。

## Goals / Non-Goals

**Goals:** 三项同意一处可见、一样的撤回交互；撤回即时生效；读屏可用；按钮 ≥ 64pt。

**Non-Goals:** 改同意页文案或告知版本；在本页重新同意（重新同意走各自原来的入口，下次用到时自然会问）。

## Decisions

1. **撤回不加二次确认。** 撤回可以随时重新同意，不在 `aidrun-a11y-voice` 列的危险操作里；资料页 #352 的撤回也是按下即生效（与安卓 #91 一致）。三项统一成同一种交互。
2. **视力那项复用资料页的 view model。** 本页建一份 `BlindRunnerProfileViewModel` 并调它的 `withdrawVisionConsent()`，成功 / 失败文案与资料页一字不差。
3. **陪跑进行中拒绝撤回位置同意。** 撤回会让同行会话立刻停发、同意页马上再弹出来，对正在跑的人只有干扰；真要停，系统设置关定位权限是即时的，文案指过去。
4. **撤回位置同意后马上重算定位意图**（`syncRoleLocationIntents`），并通知同行协调器（`trackConsentDidChange`），不等下一次换角色。

5. **陪跑员端（#530）复用同一个版式**（`PrivacyConsentRow`）。撤回时接单开关开着就先 `setAvailability(false)`（同步服务端），
   与同意页上「先不同意」的处理一致：否则服务端一直当他在线，却再也收不到他的位置。首页 view model 由 `VolunteerTabView` 注入。

## Risks / Trade-offs

- 资料还没加载时视力那项撤回会被表单校验挡下 → 显示资料页同一句校验错误；本页进入时若资料没加载，提示先打开「个人资料」。
- UI 用例默认跳过三项同意（环境变量），撤回后状态在 UI 用例里不会变 → 状态切换用单测守，UI 用例只守 64pt 与读屏标签。
