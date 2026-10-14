## Context

- 唯一的解析出口：`VoiceOrderWizard.parseOrderResponse` → `VoiceOrderServing.parseOrder`（`VoiceOrderService.swift`），整句轮与确认轮都走它。`AppState.voiceOrder` 每次现建一个 `VoiceOrderService`。
- 向导的启动入口都经过 `BlindBookingView.startVoiceWizard()`（首页「语音下单」进入、Magic Tap、「用语音重新说一次」）。
- 单独同意的现成做法：`PrivacyConsentPurpose` + `PrivacyConsentStore` + 全屏 `ConsentDisclosureView(purpose:)`，范例是 `blindVisionProfile`（`ProfileModule`）。
- 向导把解析错误当作「没听懂」吞掉并继续（`handle` 里 `parseFailed`），所以服务层拒绝本身不会给用户任何交代 —— 用户可见的出路必须由视图层在启动前给。

## Goals / Non-Goals

**Goals:**
- 未同意时，网络上一个 `/parse` 请求都不发，且这个保证有单测。
- 拒绝后有可用的出路（手动表单），用户听得到。

**Non-Goals:**
- 不做撤回同意的入口（范围外；有需要另开 issue）。
- 不改后端、不改契约、不碰 `VoiceTextField` 的逐字段听写（它走系统语音识别，不经过 `/parse`）。
- 不改原有语音向导的解析与播报逻辑。

## Decisions

1. **新增 `PrivacyConsentPurpose.voiceOrderThirdPartyLLM`，按账号记（`.user(String(userId))`）。** 复用现有存储与文案被指纹钉住的机制；键名只含用途、版本、userId，不含手机号和令牌。备选：给 `RunPlanShareConsentStore` 加第二个键 —— 否决，那是注释里标了要合并的旧形状。
2. **闸门做成 `VoiceOrderServing` 的装饰器 `ConsentGatedVoiceOrderService`，`AppState.voiceOrder` 返回它。** 出口只有一个，装饰器天然覆盖所有现在和将来的调用点；同意状态在每次调用时现读，换账号立刻生效。未同意抛 `VoiceOrderConsentError.notGranted`，内层服务不被调用。备选：只在视图拦 —— 否决，换个入口就绕过，且没法单测「不发请求」。
3. **视图层在 `startVoiceWizard()` 里先判同意，没有则弹 `fullScreenCover`。** 全屏是系统模态，背后的 `NavigationStack` 自动退出读屏树，不需要自定义 overlay 的置空手法；与 `ProfileModule` 一致。同意 → 记录后重走 `startVoiceWizard()`；拒绝 → 关闭，念 `declinedFeedback`，保持表单态。
4. **`appLaunch` 版本 3 → 4。** 新的接收方（通义千问），落在 `disclosureVersion` 注释的「必须 +1」一档。#365 把它升到 3，这里在其基础上再升，不抢同一个数。
5. **文案与安卓不逐字同步。** 安卓仓库没有对应 issue，不编造「逐字同步」。

## Risks / Trade-offs

- 老用户冷启动会再看一次首启告知（v3 → v4）；v3 未对外分发，实际影响为零。
- 拒绝后用户再点语音入口会再弹一次同意页。这是用户主动再次发起，不算劝返。
- 装饰器在内层抛错之外多了一种错误；向导会把它当解析失败吞掉，但视图层已先拦，正常路径走不到。
