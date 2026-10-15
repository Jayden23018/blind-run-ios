## 1. 实现

- [ ] 1.1 `SafetyModule.swift`：新增 `EmergencyCallContext.volunteerSessionExpired` 与陪跑员版读屏提示；`appendsNoContactHint` 改穷举
- [ ] 1.2 `VolunteerRunningCompanion.swift`：新增 `VolunteerRunEmergencyMode`，面板加 `isSessionExpired` 入参，暂缓时紧急按钮换成「紧急呼叫」并在面板内弹本地拨号框
- [ ] 1.3 宿主 `VolunteerOrderFlowViews.swift` 传入 `appState.isSessionExpiryDeferred`

## 2. 验证

- [ ] 2.1 单测：两档模式判定、文案（含「App 不会代你发送求助」、不含「不在跑步中」、不追加联系人提示）
- [ ] 2.2 UI 用例：陪跑员跑步中 401 → 打开求助面板 → 「紧急呼叫」→ 拨号框只有 120 / 110，没有云端确认框
- [ ] 2.3 编译门禁 + 真机跑覆盖的 suite
