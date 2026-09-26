## 1. 出发 / 汇合卡

- [x] 1.1 `GuideRunAttributes`（双 target 共享文件）：ContentState 与后端推送逐字段一致，`phase` 开放枚举
- [x] 1.2 `GuideRunActivityPresentation`：出发 / 快迟到 / 汇合每行文案与颜色，只用姓氏、整句用「跑者」
- [x] 1.3 锁屏视图 + 灵动岛（紧凑 / 最小 / 展开），iOS 17 按钮，iOS 16 不画
- [x] 1.4 `GuideRunActivityController`：起卡（`.token` 失败退回本地）、更新、结束、认回、XCTest / UI 测试不起卡
- [x] 1.5 `OrderServing.registerLiveActivityToken` + Mock + Fake；`AppState` 注入上传器
- [x] 1.6 `LiveActivityIntent` → `quick-message` / `ring-runner`（`blindRunApp.init` 挂处理器，不经 `AppState`）
- [x] 1.7 `VolunteerInServiceViewModel.order` 每次变化喂给控制器

## 2. 跑步卡 v2（陪跑员端）

- [x] 2.1 ContentState 追加可选字段：目标、进度、节奏信号、暂停
- [x] 2.2 构造器：目标公里与进度、5 分钟闸；协调器接订单计划距离
- [x] 2.3 陪跑员端卡片视图与灵动岛；跑者端不变

## 3. 验证

- [x] 3.1 真机验证 `pushType: .token`：本仓库无 APNs 能力 → 拒绝（`PermissionsError Code=3`），本地卡照常起
- [x] 3.2 单测：后端两段样例解码（null 与缺省）、订单映射、文案、5 分钟闸、进度、旧卡兼容
- [x] 3.3 真机只跑覆盖改动的 suite：8 个 suite passed=403 failed=0
- [x] 3.4 真机量锁屏卡高度 ≤160pt：出发（快迟到）156、汇合 156、跑步 v2 127（`LiveActivityCardHeightTests`；照稿排是 268 / 242，已压缩）
- [x] 3.5 `docs/ui/design-direction.md` 记下状态色例外（V13）
