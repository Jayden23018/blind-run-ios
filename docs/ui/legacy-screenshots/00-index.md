# Legacy Screenshots Index

旧 Flutter Demo 截图索引。本目录下的截图**仅作为 AidRun / 助盲跑 iOS SwiftUI MVP 的 UI 行为和视觉参考**，不是 source of truth。

当截图内容与以下文档冲突时，必须以文档为准（优先级从高到低）：

1. `AGENTS.md`
2. `docs/01-10`
3. `openspec/changes/remove-local-backend-use-cloud-only/`
4. `docs/ui/ui-handoff-ios.md`
5. 本目录截图（最低优先级）

完整 SwiftUI 页面规格见：[ui-handoff-ios.md](../ui-handoff-ios.md)

---

## 覆盖概览

| MVP 页面 | 截图覆盖 | 备注 |
|----------|----------|------|
| P1 登录页 | ❌ 无 | 以 ui-handoff-ios.md §1 为准 |
| P2 角色选择页 | ❌ 无 | 以 ui-handoff-ios.md §2 为准 |
| P3 盲人资料页 | ❌ 无 | 以 ui-handoff-ios.md §3 为准 |
| P4 盲人首页 | ✅ 有 | blind-runner/01 |
| P5 创建预约页 | ✅ 有 | blind-runner/02-05 (4张) |
| P5a 地点搜索子流程 | ⚠️ 部分 | 02 中含简单地点入口 |
| P6 盲人订单状态页 | ✅ 有 | blind-runner/06-10 (5张) |
| P7 盲人服务中页 | ❌ 无 | 旧版合并在 BlindActiveRunPage，无独立截图 |
| P8 盲人完成/评分页 | ✅ 有 | blind-runner/11-12 |
| P9 志愿者认证页 | ✅ 有 | volunteer/02 |
| P10 志愿者首页 | ✅ 有 | volunteer/01 |
| P11 志愿者订单列表页 | ✅ 有 | volunteer/03 |
| P12 志愿者订单详情页 | ✅ 有 | volunteer/04 |
| P13 志愿者服务中页 | ✅ 有 | volunteer/05-07 (3张) |
| P14 志愿者服务记录页 | ✅ 有 | volunteer/08 |
| P15 志愿者积分/商城占位页 | ✅ 有 | volunteer/09 |
| P16 设置页 | ✅ 有 | volunteer/10 |
| 求助确认弹窗 | ❌ 无 | 以 ui-handoff-ios.md 共享组件为准 |
| 定位权限提示 | ❌ 无 | 以 ui-handoff-ios.md 共享组件为准 |

---

## 盲人端截图 (blind-runner/)

| # | 文件名 | 对应页面 | 角色 | MVP 模块 | 可参考 UI 元素 | SwiftUI 保留 | 需重设计 |
|---|--------|----------|------|----------|---------------|-------------|---------|
| 01 | 01-blind-home.png | P4 盲人首页 | blind_runner | BlindRunner | 黑底高对比度配色、超大黄色主按钮"发起预约"、状态提示文案、单列布局 | ⚠️ 部分 | 是：必须添加地图、"重复当前状态"按钮；必须移除"AI语音助手"；按钮文案改为"开始约跑" |
| 02 | 02-create-booking-1.png | P5 创建预约页 | blind_runner | Orders | 黑底分步表单、黄色地点选择区域、出发时间卡片布局、语音输入按钮样式 | ⚠️ 部分 | 是：时间选择改用 DatePicker；移除语音输入时间；移除"AI语音助手"；表单字段按新规格调整 |
| 03 | 03-create-booking-2.png | P5 创建预约页 | blind_runner | Orders | 时间选择器样式、步骤进度提示 | ⚠️ 部分 | 是：必须使用系统 DatePicker（≥当前+30分钟）|
| 04 | 04-create-booking-3.png | P5a 地点搜索 | blind_runner | Map | POI 搜索输入框、搜索结果列表布局、语音搜索按钮 | ✅ 大部分 | 否：搜索+语音输入模式可保留，需添加 accessibilityLabel |
| 05 | 05-create-booking-4.png | P5 创建预约页 | blind_runner | Orders | 预约确认/提交前总览 | ⚠️ 部分 | 是：字段需按新规格包含目的地、预计时长、配速等可选项 |
| 06 | 06-order-matching-1.png | P6 订单状态等待页 | blind_runner | Orders | 橙色状态卡片"正在匹配志愿者"、地址+时间展示、跑步图标动画提示 | ✅ 大部分 | 否：状态卡片布局和高对比配色可保留；需移除"AI语音助手"；需添加"取消订单"和"重复当前状态"按钮 |
| 07 | 07-order-matching-2.png | P6 订单状态等待页 | blind_runner | Orders | 匹配中另一状态截图 | ✅ 大部分 | 同 06 |
| 08 | 08-order-matching-3.png | P6 订单状态等待页 | blind_runner | Orders | 匹配中第三状态截图 | ✅ 大部分 | 同 06 |
| 09 | 09-order-accepted.png | P6 订单状态等待页 (accepted) | blind_runner | Orders | 志愿者接单后信息卡片、志愿者姓名展示 | ✅ 大部分 | 否：需添加"一键求助"按钮和志愿者联系电话 |
| 10 | 10-volunteer-arrived.png | P6 订单状态等待页 (arrived) | blind_runner | Orders | 志愿者到达状态展示、操作引导文案 | ⚠️ 部分 | 是：盲人端不提供开始服务按钮，仅被动提示"等待志愿者开始服务" |
| 11 | 11-service-completed-rating.png | P8 完成/评分页 | blind_runner | Orders | 大面积色块评价按钮、黑底高对比 | ❌ 重设计 | 是：旧版是三档评价（非常满意/基本满意/需要改进），新版必须改为 1-5 星评分；移除"AI语音助手" |
| 12 | 12-service-completed-result.png | P8 完成/评分页 | blind_runner | Orders | 完成结果展示布局 | ⚠️ 部分 | 是：需增加服务摘要（时长、志愿者、地点）和"返回首页"按钮 |

---

## 志愿者端截图 (volunteer/)

| # | 文件名 | 对应页面 | 角色 | MVP 模块 | 可参考 UI 元素 | SwiftUI 保留 | 需重设计 |
|---|--------|----------|------|----------|---------------|-------------|---------|
| 01 | 01-volunteer-home.png | P10 志愿者首页 | volunteer | Volunteer | 浅色主题、高德地图半屏、"在线"开关+状态文案、附近需求列表、空状态文案、4Tab 结构 | ✅ 大部分 | 否：地图+列表布局和在线开关可保留；开关文案从"接收附近订单"调整为"可服务状态"；Tab 可参考 |
| 02 | 02-volunteer-profile-verification.png | P9 志愿者认证页 | volunteer | Profile | 认证流程 UI、状态显示 | ⚠️ 部分 | 是：需单独认证页面，Mock 一键认证按钮，状态显示改为中文（非英文 APPROVED）|
| 03 | 03-available-orders.png | P11 志愿者订单列表页 | volunteer | Orders | 订单卡片（地点、时间、部分遮掩电话）、"立即接单"按钮、地图+列表混合布局 | ⚠️ 部分 | 是：接单前必须完全隐藏电话（非部分遮掩）；需添加距离排序信息；"立即接单"改为进入详情页后再接单 |
| 04 | 04-order-detail-after-accept.png | P12 志愿者订单详情页 | volunteer | Orders | 接单后详情布局、联系信息展示 | ✅ 大部分 | 否：接单后显示完整电话可保留；需补充地图显示和"我已到达"按钮 |
| 05 | 05-arrived-confirmation.png | P13 志愿者服务中页 (arrived) | volunteer | Orders | 到达确认页布局 | ⚠️ 部分 | 是：到达后旧确认状态已过时，当前应显示志愿者端"开始服务"按钮 |
| 06 | 06-service-in-progress.png | P13 志愿者服务中页 (in_progress) | volunteer | Orders | 全屏地图+底部信息卡、"已到达集合点"状态文字、盲人信息卡（含备注）、红色"结束行程"按钮 | ⚠️ 部分 | 是：按钮文案改为"结束服务"；需添加"一键求助"按钮；电话显示需按接单后规则完整展示 |
| 07 | 07-complete-service-summary.png | P13 志愿者服务中页 (complete) | volunteer | Orders | 完成结算展示 | ⚠️ 部分 | 是：需显示 +100 积分（非旧版积分数）；可选服务小结输入 |
| 08 | 08-service-records.png | P14 志愿者服务记录页 | volunteer | Volunteer | 历史列表布局、时间+状态标签 | ✅ 大部分 | 否：列表结构可保留；需添加积分显示和下拉刷新 |
| 09 | 09-points-shop-placeholder.png | P15 志愿者积分/商城占位页 | volunteer | Volunteer | 积分余额大字展示、商品网格卡片、积分数 | ❌ 重设计 | 是：旧版有真实"兑换"按钮，新版必须改为"敬请期待"占位；移除真实兑换交互 |
| 10 | 10-settings.png | P16 设置页 | volunteer | Core | 资料编辑卡片、认证状态显示、推送开关、保存/退出按钮 | ⚠️ 部分 | 是：认证状态改中文；开关改为"可服务状态"；退出需二次确认；需添加角色切换和环境切换入口 |

---

## 覆盖缺口

### 不存在的截图目录

| 预期目录 | 状态 | 说明 |
|----------|------|------|
| `auth/` | 不存在 | 旧 Flutter demo 录屏中未单独截取登录和角色选择页面 |
| `shared/` | 不存在 | 旧 Flutter demo 中无独立的共享组件截图（弹窗、权限提示等）|

### 无截图覆盖的 MVP 页面

| 页面 | 原因 | 设计来源 |
|------|------|----------|
| P1 登录页 | 旧 demo 无独立截图 | `ui-handoff-ios.md` §1 + `docs/05-page-specs.md` |
| P2 角色选择页 | 旧 demo 无独立截图 | `ui-handoff-ios.md` §2 + `docs/05-page-specs.md` |
| P3 盲人资料页 | 旧版在设置页内，无独立截图 | `ui-handoff-ios.md` §3 + `docs/05-page-specs.md` |
| P7 盲人服务中页 | 旧版合并在 BlindActiveRunPage | `ui-handoff-ios.md` §7 + `docs/05-page-specs.md` |
| 求助确认弹窗 | 无独立截图 | `ui-handoff-ios.md` 共享组件 + `AGENTS.md` §12 固定文案 |
| 取消原因 Sheet | 无独立截图 | `ui-handoff-ios.md` 共享组件 + `AGENTS.md` §6 固定原因 |
| 定位权限提示 | 无独立截图 | `ui-handoff-ios.md` 共享组件 |

---

## 截图→Handoff 交叉引用

| 截图路径 | ui-handoff-ios.md 章节 |
|----------|------------------------|
| blind-runner/01-blind-home.png | §4 盲人首页 |
| blind-runner/02-create-booking-1.png | §5 创建预约页 |
| blind-runner/03-create-booking-2.png | §5 创建预约页 |
| blind-runner/04-create-booking-3.png | §5a 地点搜索子流程 |
| blind-runner/05-create-booking-4.png | §5 创建预约页 |
| blind-runner/06-order-matching-1.png | §6 盲人订单状态等待页 |
| blind-runner/07-order-matching-2.png | §6 盲人订单状态等待页 |
| blind-runner/08-order-matching-3.png | §6 盲人订单状态等待页 |
| blind-runner/09-order-accepted.png | §6 盲人订单状态等待页 |
| blind-runner/10-volunteer-arrived.png | §6 盲人订单状态等待页 |
| blind-runner/11-service-completed-rating.png | §8 盲人完成/评分页 |
| blind-runner/12-service-completed-result.png | §8 盲人完成/评分页 |
| volunteer/01-volunteer-home.png | §10 志愿者首页 |
| volunteer/02-volunteer-profile-verification.png | §9 志愿者资料/认证页 |
| volunteer/03-available-orders.png | §11 志愿者订单列表页 |
| volunteer/04-order-detail-after-accept.png | §12 志愿者订单详情页 |
| volunteer/05-arrived-confirmation.png | §13 志愿者服务中页 |
| volunteer/06-service-in-progress.png | §13 志愿者服务中页 |
| volunteer/07-complete-service-summary.png | §13 志愿者服务中页 |
| volunteer/08-service-records.png | §14 志愿者服务记录页 |
| volunteer/09-points-shop-placeholder.png | §15 志愿者积分/商城占位页 |
| volunteer/10-settings.png | §16 设置页 |

---

## 截图与当前规格的冲突点

以下冲突点已在截图表"需重设计"列标注，以当前文档为准：

| 截图 | 冲突内容 | 当前规格要求 |
|------|----------|-------------|
| blind-runner/01, 02, 06, 11 | 底部有"AI语音助手"按钮 | AGENTS.md §4 明确禁止 AI 助手 |
| blind-runner/01 | 无地图、无"重复当前状态"按钮 | docs/05 P4 要求地图 + "重复当前状态" |
| blind-runner/02 | 语音输入时间 | AGENTS.md §10 时间仍用 DatePicker |
| blind-runner/11 | 三档评价（非常满意/基本满意/需要改进）| docs/05 P8 要求 1-5 星评分 |
| volunteer/03 | 接单前显示部分遮掩电话 | AGENTS.md §11 接单前完全隐藏联系信息 |
| volunteer/09 | 积分商城有真实"兑换"按钮 | AGENTS.md §4 积分商城仅占位 |
| volunteer/10 | 认证状态显示英文"APPROVED" | 新版应显示中文状态 |
| volunteer/06 | 按钮文案"结束行程" | docs/05 P13 使用"结束服务" |
