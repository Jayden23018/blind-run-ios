## 1. 定位服务

- [x] 1.1 `LocationService` 发布 `accuracyAuthorization`，加 `isPreciseLocationOff`、`requestTemporaryPreciseLocation(for:)` 与 DEBUG 接缝
- [x] 1.2 新增 `LocationAccuracyPolicy.weakAccuracyMeters = 50`，单测钉住与陪跑员端阈值相等
- [x] 1.3 `Info.plist` 加 `NSLocationTemporaryUsageDescriptionDictionary`（下单起点、陪跑安全两条）

## 2. 云端求助

- [x] 2.1 `LocationError.preciseLocationOff` 与对应「求助未发出」文案（含 110、120）
- [x] 2.2 `freshEmergencyCoordinate(using:)` 在精确位置关闭时返回 nil；新增 `locationFailureReason(using:)`，盲人端三处调用点改用它
- [x] 2.3 协调器记录所发坐标的低精度，`statusMessage` 附加误差说明；界面渲染点与首句播报改读它

## 3. 下单起点

- [x] 3.1 降级告知增加「精确位置已关闭」一档，视图显示两个按钮并朗读
- [x] 3.2 精确位置关闭时不把当前位置当出发点，进页申请一次临时精确位置
- [x] 3.3 精度差于 50 米时当前位置卡片显示并朗读一次核对提示

## 4. 陪跑中

- [x] 4.1 `LiveEscortHealthState.preciseLocationOff`（仅盲人端），出发阶段与跑步阶段各申请一次临时精确位置

## 5. 验证

- [ ] 5.1 单测覆盖求助、下单、陪跑健康三条新分支，并在已提交的基线上验红
- [ ] 5.2 编译门禁 `build-for-testing` 通过；真机跑覆盖到的 suite，`passed=N failed=0`
- [ ] 5.3 真机：系统设置关掉精确位置后走一次下单页与求助入口（不真的发出云端求助），结果写进 PR
