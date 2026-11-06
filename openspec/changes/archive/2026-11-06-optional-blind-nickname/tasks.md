## 1. 实现

- [x] 1.1 `BlindBookingGate` 去掉 `.basicProfile`；`AppState` 去掉 `isBlindBasicProfileComplete`，`isBlindBookingReady` 只看紧急联系人
- [x] 1.2 「约跑前还差 N 项」卡去掉「昵称」一行
- [x] 1.3 语音向导与进页播报的注释和文案跟着改

## 2. 验证

- [x] 2.1 单测跟着改：门槛枚举、卡片、语音向导、`isBlindBookingReady` 各有一条「没昵称不拦」
- [x] 2.2 编译检查（`build-for-testing`）通过；`openspec validate --all --strict` 通过
