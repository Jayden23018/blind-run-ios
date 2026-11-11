## 1. 实现

- [x] 1.1 新增 `BookingStartGate.swift`（判定、提示文案）
- [x] 1.2 `BlindMatchFirstBookingView`：标题下开放范围一行
- [x] 1.3 `BlindMatchFirstBookingView`：卡底小字随定位状态变化
- [x] 1.4 `BlindMatchFirstBookingView`：提交前请求临时精确位置；被拒 / 权限被拒弹短提示
- [x] 1.5 进页开场播报：定位用不了时不说「从当前位置」，有开放范围就附一句

## 2. 检查

- [x] 2.1 `BookingStartGateTests`（判定、文案）；编译通过
- [x] 2.2 UI 用例：精确位置关闭时点提交出现短提示（只编译，由负责人真机验）
- [x] 2.3 `build-for-testing` 编译门禁通过
- [x] 2.4 同步 `openspec/specs/blind-precise-location-gate/spec.md`（归档时合入）
