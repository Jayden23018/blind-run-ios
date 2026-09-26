## 1. 响铃

- [x] 1.1 `WSAppNotification` 解 `until`（类型不对时置空，不连累整条）
- [x] 1.2 `RunnerRingRequest.make`：服务端时钟算时长、夹到 30 秒、缺失/过期返回 nil
- [x] 1.3 协调器路由 `RUNNER_RING`：只给盲人角色、按 messageId 去重、不可响时回落普通通知
- [x] 1.4 `RunnerRingController`：先念后响、到点停、手动停、重复 id 不重响、新 id 重新计时
- [x] 1.5 专用提示音 `RunnerRingTone`（常驻播放器、测试接缝）
- [x] 1.6 `RunnerRingOverlay` 挂到 `BlindRunnerTabView`，magic tap / escape 停铃，背后树对读屏隐藏

## 2. 朗读

- [x] 2.1 测试钉住 `VOLUNTEER_LATE` / `VOLUNTEER_BACK_ON_TIME` / `QUICK_MESSAGE_*`（含未知预设）进朗读通道且不被抑制

## 3. 引导偏好

- [x] 3.1 `BlindProfileResponse` / `BlindProfileUpdateRequest` 加 `guidePreferenceText`
- [x] 3.2 资料页录入框 + 80 字（UTF-16）上限校验 + 「接单后才看得到」说明

## 4. 出发前留言

- [x] 4.1 `OrderServing.updateRunnerMessage`（`PUT /api/orders/{id}/runner-message`）+ Mock 与 Fake 实现
- [x] 4.2 `RunOrderStatus` 可写判据 + 订单页留言行与表单页 + 40 字上限

## 5. 验证

- [x] 5.1 单测：解析与降级、朗读文案、响铃起止与去重、请求体、长度上限
- [ ] 5.2 真机只跑覆盖改动的 suite，按 result bundle 核对执行数（单测 8 个 suite 123/123 已过；UI 3 条待设备开 UI Automation）
- [ ] 5.3 真机人耳验响铃音量与循环（交给用户）
