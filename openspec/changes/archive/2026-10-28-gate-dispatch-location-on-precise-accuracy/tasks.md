## 1. 实现

- [x] 1.1 两条派单上报路径加精确位置闸
- [x] 1.2 陪跑员端顶部告知 + 朗读 + 临时精确位置（新用途键）
- [x] 1.3 `PreciseLocationPurpose` 改 `CaseIterable`，plist 用例改逐个核对

## 2. 验证

- [x] 2.1 单测：关闭不报、开启照报、文案四要素
- [x] 2.2 编译门禁、SwiftLint 棘轮
- [x] 2.3 真机（iPhone 16 Pro 有线，2026-10-28）：`DispatchPreciseLocationGateTests` 等 4 个 suite `passed=50 failed=0`；验红让 `isBlockedByPreciseLocation` 恒返回 false → 预期的 2 条红（`failed=2`）。
  人工部分（关精确位置开接单开关，顶部出现并念、弹临时精确位置）挪到人工验收 issue #410
