## 1. 同行位置发送闸

- [x] 1.1 `LiveEscortSessionCoordinator.sendLatestLocation` 在精确位置关闭时不发，两端一致
- [x] 1.2 健康判定的「精确位置已关闭」一档去掉「只限盲人」，带上角色，文案按角色分

## 2. 临时精确位置

- [x] 2.1 `PreciseLocationPurpose` 加陪跑员用途，`Info.plist` 加 `AidRunEscortVolunteer` 说明
- [x] 2.2 协调器两端都在出发 / 跑步两阶段各申请一次，陪跑员用自己的用途键

## 3. 文档对齐

- [x] 3.1 `gate-blind-location-on-precise-accuracy` 里「陪跑员端不变、不停发同行位置」两处改为指向本变更
- [x] 3.2 `LocationError.preciseLocationOff` 注释改为「同行位置在精确位置关闭时不共享」

## 4. 验证

- [x] 4.1 单测：两端发送闸（关闭不发、恢复后发）、两端横幅文案、陪跑员用途的申请与去重
- [x] 4.2 编译门禁 `build-for-testing`、SwiftLint 棘轮、`openspec validate --strict` 通过
- [ ] 4.3 真机跑覆盖到的 suite，`passed=N failed=0`，并做一次验红
