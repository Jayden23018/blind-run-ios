## 1. 设计常量与通用组件（PR 1）

- [x] 1.1 `FlowPalette` 补齐 v2 颜色（含深色 / 增强对比度），navy 改 `#1B2657`，列出引用面
- [x] 1.2 `FlowMetrics` / `FlowFonts` 补 v2 间距、圆角、高度与字号（主角数字封顶 AX2）
- [x] 1.3 `FlowV2Components.swift`：主 / 次 / 文字按钮、求助胶囊、导航栏、头卡、跑者卡、地点行、快捷回复、在场胶囊、提醒条，各带 Preview
- [x] 1.4 `HapticFeedback.Kind` 加 `.medium`
- [x] 1.5 `design-direction.md` 记录陪跑员订单页例外
- [x] 1.6 `FlowDesignSystemTests` 覆盖新颜色的对比度

## 2. 引导绳与方位盘（PR 2）

- [x] 2.1 `RopeGeometry` + `RopeShape` + `RopeView`（六个状态、亮 / 暗主题）
- [x] 2.2 状态切换动画、循环动效、减弱动态效果降级
- [x] 2.3 `DirectionSector` 纯函数（八方位 + 滞回）与 `DirectionDial`
- [x] 2.4 单测：几何、p 截断、滞回边界

## 3. 数据层（PR 3）

- [ ] 3.1 `sync-api-client.sh` 同步生成代码
- [ ] 3.2 `OrderDetailResponse` 新字段 + `EtaView` / `MeetView` / 开放枚举 `DistanceBucket`
- [ ] 3.3 端点 `end-waiting` / `quick-message` / `ring-runner` + Mock
- [ ] 3.4 错误码 `DEPARTURE_TOO_EARLY` / `END_WAIT_TOO_EARLY` + `docs/error-codes.json`
- [ ] 3.5 WS `ORDER_ETA_UPDATED` / `MEET_DISTANCE_BUCKET` / `accuracyM`，新 eventType 触发重拉
- [ ] 3.6 `OrderDetailResponse.preview` 支持新字段；解码测试（真实形状 fixture）

## 4. 各状态接入（PR 4）

- [ ] 4.1 `VolunteerOrderPhase.resolve(order:now:)` 纯函数 + 单测
- [ ] 4.2 订单页骨架换成导航栏 + 头卡 + 底部动作区
- [ ] 4.3 约好（前一晚 / 出发前 30 分钟）
- [ ] 4.4 出发 / 快迟到 + 快捷回复
- [ ] 4.5 汇合（五档）+ 方位盘 + 响铃 + 打电话 / 找不到对方
- [ ] 4.6 等待满 15 分钟 + 结束等待
- [ ] 4.7 完成页 + 跑者取消 + 其余终止态换常量
- [ ] 4.8 求助胶囊 `VolunteerOrderSOSMode` + 本地拨号 sheet + `AGENTS.md` §6 同步
- [ ] 4.9 每个状态的 Preview（含 SE + AX3）
- [ ] 4.10 真机跑覆盖的 suite，截图对照画板
