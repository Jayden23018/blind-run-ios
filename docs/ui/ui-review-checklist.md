# UI Review Checklist

每个包含 UI 变更的 iOS PR 必须逐项检查本清单。本清单基于 `AGENTS.md`、`docs/05-page-specs.md`、`docs/09-accessibility-and-voice-guidelines.md` 和 `docs/ui/ui-handoff-ios.md` 整理。

---

## 1. 截图参考与规格对照

- [ ] 已查阅 `docs/ui/legacy-screenshots/00-index.md` 确认该页面对应的旧截图
- [ ] 已对照 `docs/ui/ui-handoff-ios.md` 对应章节实现
- [ ] 已符合 `docs/05-page-specs.md` 对应页面规格
- [ ] 旧截图中的可保留元素已合理参考
- [ ] 旧截图中标记为"需重设计"的部分已按新规格重新设计

---

## 2. 无障碍（Accessibility）

### 2.1 基本要求

- [ ] 所有交互控件有 `accessibilityLabel`
- [ ] 需要额外说明的控件有 `accessibilityHint`
- [ ] 符合 `docs/09-accessibility-and-voice-guidelines.md` 要求

### 2.2 盲人端特殊要求

- [ ] 关键主按钮高度 ≥ **64pt**
- [ ] 每个关键盲人端页面有"重复当前状态"按钮
- [ ] 每屏只有一个主任务（避免嵌套导航和过多选择）
- [ ] 深色背景 + 高对比度文字 + 大字号（≥20pt body）
- [ ] 盲人端状态、下一步主操作和"重复当前状态"先于辅助地图出现在视觉和 VoiceOver 顺序中
- [ ] 盲人端地图有等价文字/TTS 摘要，不把原始经纬度作为普通用户文本读出

### 2.3 颜色与对比度

- [ ] 不存在只靠颜色传达状态的问题（必须有文字或图标辅助）
- [ ] 支持系统明暗模式切换后仍可读
- [ ] 按钮在不同状态下（正常/禁用/加载中）有清晰视觉区分

---

## 3. TTS 语音播报

- [ ] 进入盲人首页时播报（有/无订单两种文案）
- [ ] 订单提交成功时播报
- [ ] 状态变化时播报：PENDING_MATCH → PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED → IN_PROGRESS → COMPLETED
- [ ] `IN_PROGRESS` 显示求助入口，且每一种求助状态（定位中 / 提交中 / 未发出 / 失败 / 冷却 / 联系中 / 已解除）都同时更新可见文案与 TTS（~~当前 release 不显示求助入口~~ 自 2026-07-31 起失效）
- [ ] 错误提示时播报
- [ ] 不重复播报已播报过的状态（ViewModel 跟踪 lastSpokenStatus）
- [ ] TTS 文案与 `ui-handoff-ios.md` 中定义的文案一致

---

## 4. 语音输入

- [ ] 文本字段（地点描述、路线备注、备注、小结）支持语音输入
- [ ] 时间选择使用 DatePicker（不使用语音输入时间）
- [ ] 语音识别失败时显示错误并允许键盘输入
- [ ] 仅在用户点击麦克风按钮时请求语音权限

---

## 5. 危险操作二次确认

- [ ] **取消订单** → 确认弹窗；当前取消接口不需要请求体
- [ ] **未来恢复求助入口** → 确认弹窗，使用固定文案："是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
- [ ] **结束服务**（志愿者）→ 确认弹窗 + 可选服务小结
- [ ] **退出登录** → 确认弹窗

---

## 6. 订单状态机合规

- [ ] 仅使用当前后端状态：`PENDING_MATCH` / `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` / `COMPLETED` / `CANCELLED` / `REMATCHING` / `NO_VOLUNTEER`
- [ ] 无旧状态名（`submitted`、`contacted`、`expired`、`matching`、`accepted`、`arrived`、`in_progress`、`emergency` 作为订单状态）
- [ ] 状态中文显示按 `ui-handoff-ios.md` 映射表（不显示英文状态名）
- [ ] 状态流转符合 `docs/04-user-flows-and-state-machine.md`

---

## 7. 隐私与数据规则

- [ ] 志愿者接单前：完全隐藏盲人联系电话、紧急联系人、敏感健康信息
- [ ] 志愿者接单后：显示盲人完整电话号码
- [ ] 紧急联系人当前仅存储；若接入通知，需有用户授权、后端契约和测试记录
- [ ] 真实 SMS 接入必须有后端验证码策略、限流、错误码和测试账号机制

---

## 8. 路线图能力接入检查

- [ ] WebSocket 改动已覆盖真实云端联调和断线降级
- [ ] 实时轨迹分享有隐私授权、频率策略和验收用例
- [ ] AI 助手 / 语音助手有误识别兜底和无障碍验收
- [ ] App 内聊天有消息契约、审核和安全规则
- [ ] 路线导航有高德能力验证和位置权限兜底
- [ ] 真实短信服务有后端验证码策略、限流、错误码和测试账号机制
- [ ] 真实身份验证有隐私合规和审核状态机
- [ ] 自动拨打电话/短信有用户授权、二次确认和后端记录
- [ ] 自然语言时间解析有失败回退和 DatePicker 替代路径
- [ ] 积分商城、支付、库存有完整交易契约
- [ ] 跌倒检测 / 地理围栏 / 多人活动报名有独立产品规则和测试计划

---

## 9. Flutter 照搬防护

- [ ] 无旧 Flutter 状态名（`pendingMatch`、`pendingAccept`、`driverEnRoute` 等）
- [ ] 无旧 Flutter API 路径或路由模式
- [ ] 业务逻辑在 **ViewModel** 中，不在 **View** 中
- [ ] 积分为 **+100**（非旧版 +50）
- [ ] 评分为 **1-5 星**（非旧版三档：非常满意/基本满意/需要改进）
- [ ] 无 Riverpod / go_router / Flutter AMap plugin 模式残留
- [ ] 无"AI语音助手"按钮

---

## 10. 地图与定位

- [ ] 高德地图 Key 来自本地配置文件（`.xcconfig` 或 plist），非硬编码
- [ ] 不在代码中提交真实高德 Key
- [ ] 定位权限被拒后：
  - 盲人端：阻止创建预约，显示引导
  - 志愿者端：隐藏距离、阻止接单，可浏览列表
- [ ] 支持真机 `111` 定位测试
- [ ] 有默认测试坐标 fallback（标注清楚仅供开发测试）

---

## 11. 订单业务规则

- [ ] 预约时间 ≥ 当前时间 + 30 分钟（否则 `APPOINTMENT_TOO_SOON`）
- [ ] 盲人取消仅在 `PENDING_MATCH` / `PENDING_ACCEPT` / `REMATCHING` 允许
- [ ] 志愿者取消仅在 `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` 允许，成功后进入 `REMATCHING`
- [ ] emergency 是独立事件，不作为订单状态
- [ ] 记录 `cancelledBy`（`blind_runner` 或 `volunteer`）
- [ ] 志愿者完成服务 → +100 积分
- [ ] WebSocket 断开时 5 秒轮询订单状态
- [ ] 并发接单：只有 `PENDING_MATCH` 状态订单可接，后到者返回 `ORDER_ALREADY_ACCEPTED`

---

## 12. 角色与登录规则

- [ ] 一个账号可同时拥有 `blind_runner` 和 `volunteer` 身份
- [ ] 活跃订单（`PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`）时阻止角色切换
- [ ] 首次登录无 `activeRole` 时路由到角色选择页
- [ ] 退出登录清除 JWT → 跳转登录页

---

## 13. MVVM 架构合规

- [ ] View 只负责渲染和交互转发
- [ ] ViewModel 拥有状态、API 调用、轮询逻辑、TTS 触发
- [ ] API 请求集中在 `APIClient`
- [ ] Token / currentUser / activeRole 集中在 `AppState`
- [ ] 当前 token 存 UserDefaults 且有注释说明生产需迁移 Keychain

---

## 14. 环境切换

- [ ] Debug 支持 Mock / Demo Cloud，环境切换入口不干扰主流程
- [ ] Demo 和 Production 构建隐藏切换入口并固定使用 `http://47.114.113.171`
- [ ] Mock 不发起网络请求，真实 API 地址不可配置

---

## 快速自查表（PR 提交前）

| 检查项 | 通过 |
|--------|------|
| 对照 ui-handoff-ios.md 对应章节 | [ ] |
| 盲人端主按钮 ≥ 64pt | [ ] |
| 有 accessibilityLabel | [ ] |
| 有"重复当前状态"按钮（盲人端）| [ ] |
| 危险操作有二次确认 | [ ] |
| 路线图能力有需求、契约和测试计划 | [ ] |
| 无 Flutter 照搬 | [ ] |
| 业务逻辑在 ViewModel | [ ] |
| 高德 Key 非硬编码 | [ ] |
| 订单状态名正确 | [ ] |
