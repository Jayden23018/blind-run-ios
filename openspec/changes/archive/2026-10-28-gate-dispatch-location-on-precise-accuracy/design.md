## Decisions

1. **两条上报路径各加一道同样的闸**：`VolunteerLocationReporter.reportIfNeeded(appState:)` 与 `ContentView.reportWebSocketLocationIfNeeded` 都读 `LocationService.isPreciseLocationOff`。与 #407 一样，闸只看这一个判定，不另造。
2. **告知挂在陪跑员端根容器**（`VolunteerTabView`），不挂在首页：开着接单开关时人可能在任何一个标签页；首页文件已到 SwiftLint 棘轮上限。
3. **临时精确位置在条件成立的那一刻申请一次**（开开关、或开着时把精确位置关掉），系统可能不弹，所以文案写「如果弹出提示」。
4. 不改后端契约。

## Risks / Trade-offs

- 拒绝临时精确位置的陪跑员开着开关也收不到附近的邀请 → 顶部常驻原因与出路，比被派错单更诚实。
