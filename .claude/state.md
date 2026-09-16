# STATE — 视障跑者端首页 + 单页订单流程（2026-09-16）

分支 `feat/blind-runner-home-and-single-page-order-flow` · **PR #141（draft）** · 6 个 commit

设计稿在 `/Users/mac/Downloads/zhumangpao-ios-order-flow-handoff/design-reference/order-flow/`
（**精确数值以 `home.html` / `prototype.html` 的 CSS 为准**，截图只是它们的渲染）。
原始需求在同目录上一层的 `PROMPT.md`。

---

## 总体决策（已与项目负责人逐条确认，**不要重新讨论**）

1. **首页底部常驻求助条删除**，紧急入口改由「我的」tab 底部兜底。`AGENTS.md` §6 与
   `docs/05-page-specs.md` 已改口径**并写明代价**：不开读屏的低视力用户在首页够不到它。
   magic tap 手势保留并上移到标签栏容器（三个 tab 都生效），两个确认弹窗随之上移 ——
   挂在单个 tab 里会让手势在别的 tab 上「听到确认音、然后什么都没发生」。
2. **「重复当前状态」** 首页 = 问候行右侧一枚 64pt 图标；订单页 = 导航栏右侧同款图标
   （设计稿的导航栏右侧本来是空的，零冲突）。**必须是可见按钮**，不许做成
   accessibility custom action（不开读屏的人够不到，XCUITest 也按不到）。
3. **「继续等待」** `PENDING_MATCH` 删、`REMATCHING` 保留。前者后端每轮超时自己就把
   窗口往后推（`OrderLifecycleService.handleMatchTimeout:578`），客户端一次不调订单寿命相同；
   后者是**真延长**（N62 把 `rematchNotifyAt` 计进 `dispatchDeadline`），删了只剩一个
   30 分钟窗口就转 `NO_VOLUNTEER` 终态，而重新下单又要求 ≥30 分钟提前量。
4. **底部标签栏本轮做**（首页 / 记录 / 我的），三个 tab 全挂已有页面。本仓库此前全仓
   `TabView` 命中 0 处。设置页里的「我的历史订单」入口已删（一个顶级 tab 加一条列表行
   = 同一个页面两条路）。
5. **暗色槽位按现有体系推导并跑用例验证**，不加 `.preferredColorScheme(.light)`。

---

## 阶段进度

- [x] **阶段 1** 设计 token + 通用组件 — `abe4cd6`，真机 `passed=23 failed=0`
- [x] **阶段 2** 首页 + 标签栏 — `2112a72`，真机 UI `passed=21 failed=3`（剩 3 条为既有）
- [x] review 修复 11 条 A 档 — `5f4557d`
- [x] 引导页 fixedSize + 三跑实测记录 — `12f41ca`
- [x] **阶段 3a** 订单页四态骨架（静态布局）— `5e404e3`，**真机零执行**
- [ ] **阶段 3b**（下一件，见下）
- [ ] 阶段 4 过渡动画
- [ ] 阶段 5 VoiceOver / 动态字体 / 减弱动态效果 / 触感

---

## ⏭ 下一件：阶段 3a 的真机验证（代码已写完，一条都没跑）

**必须插 USB 线**（无线跑不了 XCTest，code 70）。iPhone 16 Pro UDID
`00008140-000161D62112801C` 就是 `scripts/device-test.sh` 的默认设备，不用传 `AIDRUN_DEVICE_ID`。
iPad Air 5 是 `00008103-001C71490E62201E`，但它**还没点过「信任证书」**
（设置 → 通用 → VPN 与设备管理），首次会以 `Developer App Certificate is not trusted` 失败。

```bash
scripts/device-test.sh \
  -only-testing:blindRunTests/BlindOrderFlowPresentationTests \
  -only-testing:blindRunUITests/AccessibilityAuditTests
```

**预期会红，且不是回归** —— UI 套件里有 4 条按**旧的滚动列表结构**断言，而订单页现在是骨架：

| 用例 | 为什么会红 |
|---|---|
| `testBlindOrderStatusOffersKeepWaitingWhileWaitingForAMatch` | 断 `blindOrderStatusKeepWaitingButton` 在 `PENDING_MATCH` 存在，而那个按钮按决策 3 已删（`REMATCHING` 才有） |
| `testBlindOrderStatusKeepsEmergencyReachableWithoutScrolling` | 断旧底栏的求助区块，现在是骨架的两个版位 |
| `testSafetyHubPutsEmergencyFirstInTheAccessibilityOrder` | 从首页订单卡进去之后按旧结构找元素 |
| `testBlindOrderStatusInLandscapePassesAccessibilityAudit` | 等 `blindOrderStatusKeepWaitingButton` 判「页面起来了」 |

🔴 **改之前先看真机上到底哪几条红、红在哪一行**（按失败签名判，不按红绿判 ——
记忆 `regression-baseline-must-match-suite-set`）。从 result bundle 取明细，别只看汇总行：

```bash
xcrun xcresulttool get test-results tests --path <bundle> --format json
xcrun xcresulttool export attachments --path <bundle> --output-path /tmp/att
```

**已知既有 3 条红**（iPhone 16 Pro，与本 PR 无关，`BlindBookingView` 本轮一字未动）：
`testBlindBookingPassesAccessibilityAudit`（Text clipped ×1）、
`testBlindBookingInLandscapePassesAccessibilityAudit`（Contrast ×1）、
`testBlindFirstRunHelpPassesAccessibilityAudit`（Text clipped ×2）。
最后一条已分出独立任务判「真缺陷还是误报」——见下面「已分出去的任务」。

---

## 阶段 3b 要做的（都不依赖真机，可以先写码）

1. **求助中心加「重复当前状态」格子** + **非 `IN_PROGRESS` 时底部红胶囊降级为本地拨号**。
   `AGENTS.md` §6：云端求助只在 `IN_PROGRESS` 开放。现成判据是
   `BlindHomeSOSMode.resolve`（已被 `EmergencySOSTests` 逐状态钉住），**复用它，别新造**。
   要改的是 `BlindActiveRunSafetyHubOption`（加 case + symbol + title + subtitle +
   逐条字面量 identifier + handler；穷举 switch 会逼你每处都给）与
   `BlindSafetyHubView`（加 `mode` 参数 + `onLocalCall` 回调）。
2. **覆盖后端 `ORDER_CANCELLATION_WARNING` 的正文。** 模板逐字是
   「您的订单即将因长时间无人接单被取消，**点击继续等待可延长**」
   （后端 `src/main/resources/data.sql:146`，HIGH 优先级走 WebSocket），
   而 `PENDING_MATCH` 那个按钮已按决策 3 删除 ⇒ 会念一句指向不存在控件的话。
   客户端覆盖成「系统仍在继续为你匹配；如果不想再等，可以取消订单后重新预约」之类，
   **不要提任何按钮**。落点在 `AppRealtimeCoordinator` 的通知文案那一层。
3. 「分享实时位置」「匹配规则说明」两处迁移（设计稿 §3.5）。
4. 上面那 4 条 UI 用例跟改。
5. **一次投完后端 handoff**（见下）。

---

## 需要后端补的 4 个字段（**还没投**，阶段 3b 一次投完）

投递通道是后端仓库 `/Users/mac/Downloads/demo/docs/handoff.md` 的「待后端确认」，
每条带日期 / 提问方 / 具体到端点或文件行号 / 明确的问题。

| 字段 | 设计稿用处 | 客户端当前降级 |
|---|---|---|
| 引导绳经验年数 | 陪跑员经验行「引导绳经验 2 年」 | 只显示「陪跑 N 次」 |
| 陪跑员认证状态 | 「张伟，已认证」 | **整段不显示**（无字段却印「已认证」是伪造信任标识） |
| 附近在线陪跑员人数 | 匹配态副标题「附近 6 位在线」 | 只留「已等待 mm:ss」 |
| 预计到达时间（分钟） | 出发态标题「8 分钟后到」 | 改用直线距离；`VoiceStatusQuery.swift:21` 逐字「不做 ETA / 路线规划」 |

顺带要在 handoff 里说一句：`ORDER_CANCELLATION_WARNING` 的模板正文建议去掉
「点击继续等待可延长」那半句（客户端已覆盖，但模板留着会让下一个客户端再踩一次）。

⚠️ **投递前先看后端仓库在哪条分支上。** 2026-09-16 当时停在
`fix/streak-switch-semantics`（领先 `origin/main` 4 个提交，含一笔别人的后端修复
`028a9b3` + 2 个未跟踪文件）。共享 checkout，别在别人的分支上乱切。

---

## 已分出去的任务（别重复做）

- **PR #142（OPEN）**：掩码姓名不再被读屏念成「张星号」—— 修既有的四五处调用点。
  新代码里的正解是 `OrderDetailResponse.volunteerNameForSpeech`（本 PR 已加）。
- **未开始的 chip**：判引导页 `textClipped` 是真缺陷还是误报。已查清 `fixedSize` 修不了
  （真因是 `.accessibilityElement(children: .combine)` 合成元素的几何），三跑实测表写在
  `BlindRunnerHelpView.swift` 的代码注释里。出路是拆 `.combine`（读屏从 3 次划动变 6 次）
  或在 AX5 上实测确认误报后显式豁免。

---

## 本轮已经做完、**不要重做**的

- 设计稿色板的 WCAG 复算（40 组 + 6 条验红，全部钉在 `FlowDesignSystemTests`）。
  三处原值算不过已换：`textTertiary #8C93A3`（3.08:1）、`helpStroke #F4C3BE`（1.37:1）、
  主按钮文字不能用 `textPrimary`（暗色档白字压黄底 1.64:1）。
- 尺寸两处刻意偏离设计稿：按钮 58 → 64pt、信息列表**可点**行 52 → 64pt。
  由 `testEveryTappableMetricClearsTheSixtyFourPointFloor` 钉住，有人改回去会红。
- 设计稿四处做不到/不成立已按契约改，各配验红：汇合态「开始跑步」（后端只接受志愿者
  token）、出发态「8 分钟后到」（无 ETA）、末行「修改或取消预约」（无改单端点 + 该态
  盲人不可取消）、副标题不许写死提前量（那是后端配置）。
- `volunteerTotalCompleted` 后端已有、客户端此前漏解码，已补（含 `replacingStatus`
  带字段的回归用例 —— 漏带会让「陪跑 32 次」每 5 秒轮询后静默消失）。
- 标签栏未选中标签用 `#6B7385`（4.76:1）而不是 **iOS 默认的 `#8E8E93`（3.26:1）**；
  标签栏底必须 `configureWithOpaqueBackground()`，半透明会让 13pt 标签的有效对比度掉到 3 以下。
- 5 份文档已随口径同步：`AGENTS.md` §6、`docs/05-page-specs.md`、
  `09-accessibility-and-voice-guidelines.md`、`03-user-stories.md`、
  `technical-design-overview.md`、`user-manual.md`。

---

## 环境事实（别重新踩）

- **真机是唯一 XCTest 通道**，模拟器因高德无 arm64-sim slice 永久不可用；CI 只跑编译门禁 + 规格校验。
- **无线跑不了 XCTest**（code 70）。判有线看 `devicectl list devices --json-output` 的
  `connectionProperties.transportType`，文本输出不含这一列。
  ✅ **2026-08-06 那条「UI test runner 起不来（code 74）」已结** —— 当时两个嫌疑里
  「只走 Wi-Fi 没插 USB」是对的。今天有线 iPhone 上 UI 套件正常跑出 `passed=21 failed=3`。
  这条已在记忆 `ui-test-runner-needs-usb-not-wifi`，不必再诊断。
- `passed=0 failed=0` **一律当失败查**（零执行）。脚本对此有硬失败，别绕。
- 跑测前设备要解锁 + 自动锁定设「永不」。
- `gh` 必须显式带 `--repo Jayden23018/blind-run-ios`，裸跑会打到 upstream（JerryZhao-1）。
- 提交要**显式列路径**：`shared-checkout-guard` 会拦 `git add -A`（这是共享 checkout，
  `.git/index` 与同事共用）。用内联 python 改过的文件不在钩子按 transcript 统计的
  「本轮写过」清单里，所以那几个必须手写路径。
