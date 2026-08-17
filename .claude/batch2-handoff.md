# 批次 2 交接：盲人首页布局重构 + 首页 SOS 条

把下面整段粘进新 session。所有 `文件:行号` 都是 2026-08-07 在分支
`feat/blind-home-layout-and-sos-bar` 上**实测核对过**的，不是从旧文档抄的。

---

## 任务

按 `.claude/state.md` 的「批次 2」实施盲人首页改造。分支和 draft PR 已开好：

- 分支 `feat/blind-home-layout-and-sos-bar`（base `integrate/swift-migration`，已推）
- draft PR https://github.com/JerryZhao-1/blind-run-ios/pull/7

先 `git checkout feat/blind-home-layout-and-sos-bar`，工作树是干净的。

## 已经做完的（不要重做）

**commit `refactor: 取新鲜求助坐标的逻辑提到 EmergencyCoordinator`**

`EmergencyCoordinator.freshEmergencyCoordinate(using:)` 静态方法
（`blindRun/Safety/EmergencyCoordinator.swift`，紧跟在 `locationWaitTimeout` 常量后面）。
原来是 `BlindOrderStatusViewModel` 的私有方法，因为首页 SOS 条是第二个求助入口，
照抄一份等于把三条安全约束守两遍。`BlindOrderStatusViewModel.freshEmergencyCoordinate()`
已改为委派，行为不变。编译已验。

## ⚠️ `.claude/state.md` 里的行号已经过时，别照抄

实测对照（`state.md` 写 → 实际）：

- `BlindRunnerHomeView.swift` 741 行 → **722 行**，里面所有 `:NNN` 全部偏移
- **「删除『语音下单』按钮与 `BlindRunnerRoute.booking`」这一项早就做完了** ——
  `BlindRunnerRoute`（`:7-14`）现在只有 `.voiceBooking` / `.orderStatus` / `.settings`，
  首页只有一个「开始约跑」按钮。**不要再去删它**

## 现状（已核对，可直接用）

### `blindRun/BlindRunner/BlindRunnerHomeView.swift`（722 行）

| 位置 | 内容 | 批次 2 要做什么 |
|---|---|---|
| `:347-442` | `body`：`NavigationStack` → `ScrollView` → `VStack(spacing:24)` | 改成 `ZStack`：地图背景层 + 内容层 |
| `:397` | `.accessibilityIdentifier("blindRunnerHomeScrollView")` | **必须保留**，UI 测试依赖 |
| `:444-470` | `header`：`HStack` 里 标题+状态摘要 / `Spacer` / 设置齿轮 | 齿轮移出，别再排遍历第 2 位 |
| `:491-511` | `auxiliaryMapSection`：`MapViewWrapper` + 标题「辅助地图」 | 转成 ZStack 背景层 |
| `:509` | `.accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")` | **必须保留**，UI 测试依赖 |
| `:504` | 地图已有 `.allowsHitTesting(false)` | 已满足「地图不得可交互」 |
| `:560-602` | `newBookingSection`：单个「开始约跑」，两个分支带不同 identifier | 不动 |
| `:584` | `blindRunnerHomeStartBookingButton` | **必须保留** |
| `:599` | `blindRunnerHomeStartBookingGuardButton` | **必须保留** |
| `:604-610` | `repeatStatusButton`：`PrimaryButton("重复当前状态")` | 降视觉权重（改 `.bordered` 一类），**不许删** |
| `:377-381` | `activeOrder` 有无的分支 | SOS 条要读 `viewModel.activeOrder?.status` |

### `blindRun/Safety/SafetyModule.swift`（179 行）

- `EmergencySafetyCopy`（`:22-133`）：**所有面向用户的求助文案必须加在这里**。
  测试 `EmergencySOSTests.testNoEmergencyCopyClaimsAnSMSWasDelivered` 按这个枚举扫红线文案
- `EmergencyActionButton`（`:135-149`）：`PrimaryButton(isDestructive:true)`，`IN_PROGRESS` 分支直接复用
- `emergencyConfirmationAlert(isPresented:onConfirm:)`（`:167-179`）：二次确认弹窗，
  文案 `EmergencySafetyCopy.confirmationMessage` 由 `AGENTS.md` 第 10 节**逐字锁定，一个字都不能改**
- `EmergencyStatusNotice`（`:153-165`）：结果展示

### 求助触发链路（`IN_PROGRESS` 分支复用这条）

`BlindOrderStatusView.swift:149-167` 的 `enterEmergency()` 是范本：

```swift
let outcome = await appState.emergencyCoordinator.trigger(
    order: order,                       // OrderDetailResponse
    role: appState.activeRole,
    userID: appState.userId,
    apiClient: appState.apiClient,
    locate: { await EmergencyCoordinator.freshEmergencyCoordinate(using: locationService) }
)
if outcome.isFailure { speechService?.speakError(outcome.message) }
else { speechService?.speak(outcome.message) }
```

`EmergencyCoordinator.allowsSubmissionWithoutLocation = false`
（`EmergencyCoordinator.swift:106`）—— 拿不到真实坐标就不发，**保持 false**。

### 紧急联系人（非 `IN_PROGRESS` 分支拨号用）

- `AppState.emergencyContacts: [EmergencyContactResponse]`（`AppState.swift:123`）
- `EmergencyContactResponse.singlePrimary(in:)`（`ProfileModels.swift:383-386`）——
  恰好一个主联系人才返回它，**0 个或多个都返回 nil**，调用方要处理 nil
- `EmergencyContactResponse.phone` 是 `String?` 且是**明文**（`ProfileModels.swift:354`；
  `:369` 注释：后端自 v1.5.0 返回明文，`maskedPhone` 只是展示层）→ 可直接拼 `tel://`

## 硬约束（违反会被拦或造成事故）

1. **非 `IN_PROGRESS` 时绝不调 `POST /api/emergency/trigger`**。那条端点两端都只在
   `IN_PROGRESS` 开放（`AGENTS.md` §6），且 `EmergencyTriggerRequest` 必须带 `orderId`。
   首页在没有进行中订单时是**本地拨号**，文案必须说清「这是打电话」，不能让盲人以为
   App 已经发出了求助
2. **App 永远不得宣称短信已发出/已送达/家属已被通知**。字符串「联系人已收到短信」
   不得出现在发布产物里。`scripts/hooks/guard.mjs` 有 `sos-copy` 规则会拦
3. **二次确认文案逐字锁定**：`是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。`
4. openspec：**不要新建变更**。首页 SOS 条的 delta 加进已有的
   `openspec/changes/enable-independent-sos-safely`。`in-run-dual-role-sos` 这个能力
   不在 `openspec/specs/` 里，只存在于那个未归档变更 —— 另开变更会 delta 同一能力，规格打架
5. **改文件前自己完整读一遍**。`BlindRunnerHomeView.swift` 722 行超过 500 行的读取限制，
   用 `offset`+`limit` 分两次读（`1-400` / `400-722`），ranged read 是允许的

## 还要动的规格

- `openspec/specs/blind-runner-voice-first-experience/spec.md:9` 现文
  「in both visual order and VoiceOver traversal order」**直接禁止本方案的视觉布局**，
  必须改为「读屏遍历顺序操作优先；视觉顺序不受此限，但地图不得可交互、不得承载任何必要信息」
- `docs/05-page-specs.md` 首页布局那几段
- `AGENTS.md` §8：补一句「首页 SOS 条在非 `IN_PROGRESS` 时是本地拨号，不调 `POST /api/emergency/trigger`」

## 要改的既有测试

`blindRunUITests/blindRunUITests.swift:44-48`
`testMockBlindRunnerHomePlacesPrimaryActionBeforeAuxiliaryMap` 现在断言
`startButton.frame.minY < auxiliaryMap.frame.minY`，即**视觉**顺序 —— 新方案下这个前提反转。
改为断言无障碍遍历顺序：在
`app.descendants(matching: .any).allElementsBoundByAccessibilityElement` 里
主按钮下标 < 地图下标。测试名也要改。

其余引用（**不要动**）：`:37,65,1338,1399`（「开始约跑」label 不变）、
`:85`（scrollView 标识符）、`:88,228,896`（地图标识符）。

## 验证

```bash
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

真机是唯一 XCTest 通道。**先解锁设备并把自动锁定设为「永不」**，否则脚本判定锁屏直接失败：

```bash
DEVELOPMENT_TEAM=ZW39BS8NXT scripts/device-test.sh -only-testing:blindRunTests/EmergencySOSTests
```

- 全量约 10 分钟、会超 Bash 600s 上限 → 用后台跑
- **`passed=0 failed=0` 一律当失败查**，零执行不是通过
- UI 测试断言前先滚动：SwiftUI `List` 不渲染屏幕外的行
- 本次改动**碰了 `EmergencySafetyCopy` 与首页布局**，`EmergencySOSTests` 与
  `blindRunUITests` 都要跑；改了共享出口（`EmergencyCoordinator`）则按 AGENTS §11 跑全量

## 本机环境（已验，省得重查）

- 设备名带弯引号：`mac’s iPhone`（iPhone 16 Pro，iOS 26.6）、`子轩王’s iPad`（iPad Air 5，iOS 26.5.2）
- **`DEVELOPMENT_TEAM` 必须作为构建设置参数传，当环境变量前缀不生效** ——
  报错是 `No Account for Team "R6PH2TFB3Q"`，字面上不提团队号从哪来
- 真机跑不起来按错误码分诊：code 74 查 USB / 残留 DTServiceHub；
  code 70「DDI 挂不上」= iPhone 刚升 iOS，必须插 USB；`deviceprep -3` 才是锁屏
- 后端契约在 `/Users/mac/Downloads/demo`，用 `claude --add-dir /Users/mac/Downloads/demo` 挂载

## 与本轮无关但开着的事

- 后端 PR #21：`GET /api/volunteer/dispatch-summary` 对 `13823594196` 返 500 +
  订单卡在 `PENDING_MATCH` 疑似被 `@Async` 吞异常。**是后端的活，别在 iOS 仓库里修**
- iOS PR #3（`integrate/swift-migration` → `main`）长期开着，与本轮无关
