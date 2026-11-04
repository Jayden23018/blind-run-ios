## 1. 实现

- [x] 1.1 `AppUpdateGate.dispatchPause`（idle / paused / failed），弹窗回到 `.none` 时复位。
- [x] 1.2 `VolunteerHomeViewModel+RequiredUpdate.swift`：`pauseDispatchForRequiredUpdate(appState:)`，成功才翻开关并同步档案。
- [x] 1.3 `AppUpdateCopy` 两句文案；`AppUpdateGateModifier` 把 gate 放进环境并追加正文。
- [x] 1.4 `VolunteerTabView` 触发并朗读。

## 2. 验证

- [x] 1.5 弹窗正文是系统弹窗、弹出后不更新：关完开关后收起再弹一次，让新那句真的上屏（收起时不记「已关闭」）。
- [x] 2.1 单测：开着 → 关掉并翻开关；关失败 → 开关不动；已关 → 不发请求；弹窗落回 `.none` 复位。
- [x] 2.2 真机跑 `AppUpdateGateTests`、`VolunteerRequiredUpdatePauseTests`（共 21 条）与两条 UI 用例，passed=28 failed=0（见 PR）。
