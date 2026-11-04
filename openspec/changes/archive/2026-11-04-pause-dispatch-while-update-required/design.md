## 数据流

`AppUpdateGate`（弹窗的判定，已存在）新增 `dispatchPause`：`idle` / `paused` / `failed`。弹窗落回 `.none`（已更新、订单进行中让路、请求失败不拦）时复位成 `idle`。

`AppUpdateGateModifier` 把 gate 放进环境（`environmentObject`），弹窗正文按 `dispatchPause` 追加一句。

`VolunteerTabView` 读 gate：`.task(id: 必须更新 × 接单开关)` 里，必须更新、`dispatchPause == .idle`、开关开着、没有别的开关请求在途时，调 `VolunteerHomeViewModel.pauseDispatchForRequiredUpdate(appState:)`，把结果写回 gate 并朗读。

`pauseDispatchForRequiredUpdate` 与「隐私与授权」撤回位置同意（`VolunteerLocationConsentRevocation`）同一做法：先等 `setDispatchStatus(wantsDispatch: false)` 成功，再把 `isAvailable` 置 false、同步 `AppState.volunteerProfile`；失败则开关不动。

## 为什么用 `.task(id:)` 而不是事件

弹窗可能先于首页 view model 读到服务端的开关状态出现（冷启动）。用「必须更新 × 开关」当 id，开关后来变成开着也会触发。id 里不放 `dispatchPause`，否则自己写状态会取消自己的请求。
