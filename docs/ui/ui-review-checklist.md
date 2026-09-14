# UI Review Checklist

每个包含 UI 变更的 iOS PR 必须逐项检查本清单。本清单基于 `AGENTS.md`、`docs/05-page-specs.md`、`docs/09-accessibility-and-voice-guidelines.md` 和 `docs/ui/ui-handoff-ios.md` 整理。

> 🔴 **本清单是派生文档，与 `AGENTS.md` 冲突时一律以 `AGENTS.md` 为准**（源真相优先级第 1 位，见 `AGENTS.md` §2）。
> 派生文档必然滞后：源改了、抄件没跟，而抄件上写着「必须逐项检查」——照着一条过期的勾去改代码，
> 就是把已经修过的缺陷重新写回去。2026-09-14 的核对里，本清单有 6 条已被 `AGENTS.md` 推翻，
> 其中 2 条（展示完整手机号、token 存 `UserDefaults`）照做就是隐私与安全回退。
> 发现本清单与 `AGENTS.md` 不一致时，改的是本清单，不是代码。

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
- [ ] 状态变化时播报：PENDING_MATCH → PENDING_INTRO_CALL → PENDING_ACCEPT → DRIVER_EN_ROUTE → DRIVER_ARRIVED → IN_PROGRESS → COMPLETED；跨天预约另有 PENDING_MATCH / PENDING_INTRO_CALL / REMATCHING → SCHEDULED_CONFIRMED → PENDING_ACCEPT

> 2026-09-14 订正。原文的播报链缺 `PENDING_INTRO_CALL` 与 `SCHEDULED_CONFIRMED`，与下面 §6 的状态清单同源同错
> （`AGENTS.md` §5 的正常流转与跨天预约两张图）。少播的后果对盲人端不是「少一句」：
> 通话磨合与远期预约恰恰是最需要解释「现在轮到我做什么」的两态。
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
- [ ] **求助入口**（两端均在 `IN_PROGRESS` 开放）→ 确认弹窗，使用固定文案："是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
  - 志愿者侧**追加**一句（不是改写）："本次求助只有跑者本人或客服能撤销。" ——`EmergencySafetyCopy.confirmationMessage(for:)`（`blindRun/Safety/SafetyModule.swift:60`）

> 2026-09-14 订正。原文写的是「**未来恢复**求助入口」，那是求助入口关闭时期的措辞 ——
> 志愿者侧自 2026-07-31 起已开放（`AGENTS.md` §6），本文件 §3 早在同一天就给同一件事打了
> 「~~当前 release 不显示求助入口~~ 自 2026-07-31 起失效」的删除线，这里漏改了。
> 追加句是后补的：`AGENTS.md` §6 写着志愿者没有撤销权（后端恒 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`），
> 而原文案对志愿者漏掉了这个动作最不可逆的那一半后果。
> ⚠️ 固定文案那一句本身**一个字都不能动**（两条用例逐字钉着），志愿者侧走追加。
- [ ] **结束服务**（志愿者）→ 确认弹窗 + 可选服务小结
- [ ] **退出登录** → 确认弹窗

---

## 6. 订单状态机合规

- [ ] 仅使用当前后端状态（共 11 个）：`PENDING_MATCH` / `PENDING_INTRO_CALL` / `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `IN_PROGRESS` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `COMPLETED` / `CANCELLED` / `REMATCHING` / `NO_VOLUNTEER`

> 2026-09-14 订正。原文只列了 9 个，漏掉 `PENDING_INTRO_CALL`（接单前通话磨合，后端迁移 `0031`）
> 与 `SCHEDULED_CONFIRMED`（跨天预约，后端迁移 `0041`）。`AGENTS.md` §5 的允许清单是 11 个。
> 漏列不是少写两个词：拿这份清单去 review，会把已经落地的两态判成「用了非法状态」。
- [ ] 无旧状态名（`submitted`、`contacted`、`expired`、`matching`、`accepted`、`arrived`、`in_progress`、`emergency` 作为订单状态）
- [ ] 状态中文显示按 `ui-handoff-ios.md` 映射表（不显示英文状态名）
- [ ] 状态流转符合 `docs/04-user-flows-and-state-machine.md`

---

## 7. 隐私与数据规则

- [ ] 志愿者接单前：完全隐藏盲人联系电话、紧急联系人、敏感健康信息；自由文本备注一律接单后才可见（枚举 / 布尔字段可以提前给，判据是取值空间封不封闭，见 `AGENTS.md` §8）
- [ ] 志愿者接单后：显示**掩码**手机号（`EmergencyContactResponse.maskPhone`，`blindRun/Core/Models/ProfileModels.swift:384`）。全号**只进 `tel:`**，不上屏、不进 `accessibilityLabel`；拨号统一走 `EmergencyDialer.telURL/dial`
  - `PENDING_INTRO_CALL` 是单向的：盲人拿明文号可直拨，志愿者只拿掩码串用于认人。**掩码串绝不能拼 `tel:`**（`138****1234` 会拨成空号且界面看不出异常）

> 🔴 2026-09-14 订正。原文写的是「显示盲人**完整**电话号码」——照做就是隐私回退。
> `AGENTS.md` §8 已于 2026-08-22 改口径：VoiceOver 是外放的，念全号等于把盲人的号码广播给周围所有人
> （commit `f404de2` / 审计 F10）。实测渲染侧 6 处调用全部走 `maskPhone`，本清单是唯一还在说「完整」的地方。
> 同批订正了接单前那条：原文只列了三类字段，漏掉「自由文本一律接单后」这条判据
> （实现闸 `RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`）。

- [ ] 紧急联系人在云端 SOS 触发后会收到短信，但 **App 永远不得宣称短信已发出、已送达或家属已被通知**；一律用本地进行时文案覆盖后端的完成时态 body（`AGENTS.md` §6，守卫规则 `sos-copy` 会拦）

> 2026-09-14 订正。原文写的是「紧急联系人**当前仅存储**；若接入通知，需有用户授权、后端契约和测试记录」
> ——通知早就接入了（后端 `EmergencyContactNotifier`）。这条过期得很危险：它把一条「还没做」的待办
> 写在了一条**已经在线上发短信**的链路上，于是真正该检查的那件事（不许宣称已送达）在清单里一个字都没有。
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
- [ ] 订单卡**不显示任何写死的积分数字**。后端从来没在订单上发过积分：`pointsDelta` 实际恒为 nil（`blindRun/Core/Models/VolunteerDispatchSummaryModels.swift:197-201`），只在它真的有值时才渲染那一行。真实积分走 `GET /api/volunteer/points`
- [ ] 评分为 **1-5 星**（非旧版三档：非常满意/基本满意/需要改进）

> 🔴 2026-09-14 订正。原文是「积分为 **+100**（非旧版 +50）」，§11 那条「志愿者完成服务 → +100 积分」同错同源。
> 这两条不是把数字写错了，是**整个字段不存在**：此前那个「nil 就返回 100」的兜底让每张完成的订单卡
> 都印着一个凭空生成的 `+100`，已随 commit `be4e030` 删掉。把 +100 留在清单里，下一个人会照着把兜底加回来。
- [ ] 无 Riverpod / go_router / Flutter AMap plugin 模式残留
- [ ] 无"AI语音助手"按钮

---

## 10. 地图与定位

- [ ] 高德地图 Key 来自本地配置文件（`.xcconfig` 或 plist），非硬编码
- [ ] 不在代码中提交真实高德 Key
- [ ] 定位权限被拒后：
  - 盲人端：阻止创建预约，显示引导
  - 志愿者端：隐藏距离、阻止接单，可浏览列表
- [ ] 支持真机 `111` 定位测试。**发布验证要两台**：`111` 与 `iPad Pro (2)`（`AGENTS.md` §3，脚本 `scripts/dual-device-validation.sh`）—— `scripts/device-test.sh` 默认只跑单台，布局几何类改动光跑它不算验过
- [ ] 有默认测试坐标 fallback（标注清楚仅供开发测试）
  - ⚠️ **云端 SOS 这条路径除外**：必须带新鲜的真实 GCJ-02 坐标，拿不到就不发，Mock / demo 坐标绝不上传（`AGENTS.md` §6）

> 2026-09-14 补。原文只写了 `111` 一台。「真机验过」默认只验了 iPhone 那一台，iPad 上的
> 无障碍审计长期无人看见（记忆 `verified-on-one-device-is-not-verified`）；坐标 fallback 那条
> 原本没有例外说明，而它与 §6 的 SOS 红线正面相撞。

---

## 11. 订单业务规则

- [ ] 预约时间 ≥ 当前时间 + 30 分钟（否则 `APPOINTMENT_TOO_SOON`）。另有三道上限：最远 7 天（`APPOINTMENT_TOO_FAR`）、单次 ≤ 300 分钟（`APPOINTMENT_TOO_LONG`）、整段行程不得与夜间窗口 `[22:00, 05:00)` 相交（`APPOINTMENT_IN_NIGHT_WINDOW`，判据是**整段**不是开始时刻）；同时最多 3 张未完成预约（`TOO_MANY_SCHEDULED_ORDERS`）
- [ ] 盲人取消仅在 `PENDING_MATCH` / `PENDING_INTRO_CALL` / `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `REMATCHING` 允许；`IN_PROGRESS` 期间**不得**展示取消入口
- [ ] 志愿者取消仅在 `SCHEDULED_CONFIRMED` / `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` 允许，成功后进入 `REMATCHING`。**`PENDING_INTRO_CALL` 不在内** —— 那一态他还没接单，退出方式是表态「不合适」，不是取消订单
- [ ] emergency 是独立事件，不作为订单状态
- [ ] 记录 `cancelledBy`（`BLIND` / `VOLUNTEER` / `SYSTEM`）；渲染要翻译，不能对盲人念出「取消方=BLIND」（`blindRun/Core/Models/OrderModels.swift:657-668`）
- [ ] 志愿者完成服务后**不展示写死的积分**（见 §9 那条订正）

> 2026-09-14 订正，四处：
> ① 预约规则原文只有 30 分钟一条，`AGENTS.md` §5 自 2026-09-05 起还有三道上限 + 一条并发上限（后端 N134 / 迁移 `0041`）。
> ② / ③ 两条取消规则都缺 `PENDING_INTRO_CALL` 与 `SCHEDULED_CONFIRMED`，且这两态在两侧的归属**不对称**
> （`PENDING_INTRO_CALL` 只在盲人侧）——照原文实现会给志愿者一个后端必然拒绝的取消按钮。
> ④ `cancelledBy` 的取值是后端枚举 `BLIND` / `VOLUNTEER` / `SYSTEM`，不是原文写的 `blind_runner` / `volunteer`，且漏了 `SYSTEM`（匹配超时自动取消走它）。
> 另：`DUPLICATE_ORDER` 自 2026-09-05 起只拦**时段冲突**，文案别再写「您有进行中的订单」。
- [ ] WebSocket 断开时 5 秒轮询订单状态
- [ ] 并发接单：只有 `PENDING_MATCH` 状态订单可接，后到者返回 `ORDER_ALREADY_ACCEPTED`

---

## 12. 角色与登录规则

- [ ] 一个账号可同时拥有 `blind_runner` 和 `volunteer` 身份
- [ ] **当前没有角色切换功能，不要为它加 UI。** `POST /api/user/role` 是一次性设角色（角色非 UNSET 直接 409 `ROLE_ALREADY_SET`），后端没有切换端点，App 内入口已删除；`ACTIVE_ORDER_ROLE_SWITCH_BLOCKED` 属于未实现，**不要在前端映射它**
  - 后端哪天真加了切换端点，规则才是：存在 `PENDING_ACCEPT` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS` 订单时阻断
- [ ] 首次登录无 `activeRole` 时路由到角色选择页

> 2026-09-14 订正。原文把「活跃订单阻止角色切换」写成了一条**现在就该检查的**项，
> 而角色切换整个功能不存在 —— `ROLE_ALREADY_SET` 只会出现在首次选角色的并发场景，
> 「有进行中订单挡住了切换」是本仓库的历史误映射，已删除（`blindRun/Core/Models/ErrorModels.swift:10-13`，skill `aidrun-auth`）。
> 把未实现的规则写成待检查项的代价：review 时找不到对应 UI，于是有人去把它「补上」。
- [ ] 退出登录清除 JWT → 跳转登录页

---

## 13. MVVM 架构合规

- [ ] View 只负责渲染和交互转发
- [ ] ViewModel 拥有状态、API 调用、轮询逻辑、TTS 触发
- [ ] API 请求集中在 `APIClient`
- [ ] Token / currentUser / activeRole 集中在 `AppState`
- [ ] token 存 **Keychain**（`blindRun/Core/KeychainTokenStore.swift`，`kSecAttrAccessibleAfterFirstUnlock`）。**不要把 access token 写进 `UserDefaults`**

> 🔴 2026-09-14 订正。原文是「当前 token 存 UserDefaults 且有注释说明生产需迁移 Keychain」——迁移早就做完了，
> 照原文改就是安全回退（`UserDefaults` 是 App 容器里的明文 plist）。`AGENTS.md` §8 逐字写着这条禁令。
> 唯一残留的 `UserDefaults` 访问是 `AppState.restoredToken()`（`AppState.swift:967-978`）对历史值的一次性
> **读取 + 删除**迁移，它不写入。这条已于同日落成守卫规则 `token-in-userdefaults`。

---

## 14. 环境切换

- [ ] Debug 支持 Mock / Demo Cloud，环境切换入口不干扰主流程
- [ ] Demo 和 Production 构建隐藏切换入口并固定使用 `https://47.114.113.171`（WebSocket 对应 `wss://`，由 scheme 推导，不单独配）
- [ ] Mock 不发起网络请求，真实 API 地址不可配置
- [ ] `Info.plist` 里**没有** `NSAppTransportSecurity` 例外

> 🔴 2026-09-14 订正。原文写的是 `http://`。2026-09-08 已切 https
> （`blindRun/Core/EnvironmentConfig.swift:151`），ATS 例外已随之删除，`AGENTS.md` §3 写明「别再加回来」。
> 此前实时位置与 SOS 全程明文 —— 这是这个 App 最不能明文传的两样东西。
> 守卫规则 `server-addr` 原先只查主机名不查 scheme，`http://47.114.113.171` 能直接穿过去；同日已补。

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
