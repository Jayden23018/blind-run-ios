# 旧界面残留审查（前端全仓审查第 1 轮，2026-11-08）

范围：`blindRun/` 全部 472 个 Swift 文件。代码基点：`origin/main` 142b2234。
「旧界面」的定义由负责人在 2026-11-07 定下：新设计上线后被替代、但还留在代码里的界面。分两类：

- **A 类**：还挂着入口，但同一功能已经有新页面。
- **B 类**：已经没有入口能走到。

Mock、`#Preview`、`#if DEBUG` 调试页不算旧界面。

本轮只出报告，不删代码。负责人挑完要删的条目后，每批删除单独开一个 PR。

## 怎么查的

1. **Periphery 3.8.0**：先跑 `build-for-testing`，目标为真机、不签名，生成索引库。再执行 `periphery scan --skip-build --index-store-path … --retain-codable-properties`。共报 211 处没用到的声明：其中 152 处没被引用，59 处只写不读的属性。按种类分：38 个类型级（struct / enum / protocol / extension / 全局函数），其余是属性与方法。
2. **三路只读子代理**，分别查盲人端、陪跑员端、共用模块。每个页面级 View 都从 `blindRunApp` → `ContentView` 顺着跳转查能不能走到，再用 `git log -S` 找出最后一处调用是被哪个提交删掉的。
3. **主会话复核**：下表每条「高」把握的结论，都用全仓精确搜索重新数过引用条数，并用 `git show` 看过删除调用的那一行。

## 结论

**没有找到 A 类。** 新旧两套页面同时挂着入口的情况不存在：改版都是在原类型上直接改，或者旧页已经删掉。B 类有 4 组，可以直接删的有 899 行（含第 1 组的 ViewModel 366 行）；另外 2 组共 202 行，要负责人先决定。

### 可以删（B 类，把握高）

| # | 删什么 | 行数 | 为什么走不到 | 被谁替代 | 证据 |
|---|---|---|---|---|---|
| 1 | `VolunteerOrderDetailView`（`blindRun/Volunteer/VolunteerOrderDetailView.swift:3`），只服务它的 `VolunteerOrderMap`（`VolunteerOrderMap.swift:3`）和 `VolunteerCertificateUploadEntryLink`（`VolunteerCertificateEntryLink.swift:13`） | 221 + 28 + 114 | 全仓库没有构造它的地方，只剩 `VolunteerOrderInfoSection.swift:10` 一条注释 | 首页「最近陪跑」改进 `VolunteerRunRecordView`（入口 `VolunteerProfileFirstScreenView+Recent.swift:29`） | daa0c8d1「陪跑员首页 v3」删掉了最后一处调用 `VolunteerOrderDetailView(orderId: order.orderId)` |
| 2 | `VolunteerBadgeMedallionRow`（`VolunteerProfileFirstScreenView+Badges.swift:157`） | 26 | 0 处引用 | `VolunteerBadgeSummaryCard`、`VolunteerBadgeWallView` | 21728659「陪跑员二级页照健康 App 重做」（#702） |
| 3 | `IncentiveCard`、`IncentiveHeroCard`（`blindRun/Shared/IncentiveUI.swift:39`、`:65`） | 53 | 只剩注释提到它们；同文件的 `AdaptiveHStack`、`IncentiveFailureSection` 还在用，要保留 | 积分、固定搭档、邀请码三页已按新稿重做 | ffb93c1d（#707）删掉了最后一处调用 |
| 4 | `FlowStepper`（`blindRun/Core/DesignSystem/FlowComponents.swift:104`） | 91 | 只有组件画廊 `FlowComponentGallery` 和 `FlowDesignSystemTests.swift:516-538` 的 4 条断言在用 | 引导绳 `RopeView` 用读屏标签报「第 N 步」 | 0d0a8e94（#350）删掉了最后一处调用；设计稿 INDEX：「四格进度条去掉」 |

删第 1 组时要连带处理：它的 `VolunteerOrderDetailViewModel`（366 行）在 App 里只被这一页用，但有 3 条单测直接构造它（`VolunteerRematchingAnnouncementTests.swift:71`、`RuleParamsAndLateCancelTests.swift:164`、`:187`）。这几条测的是「重新匹配播报」和「晚取消规则」。已核实：这 3 条都是「详情页也一样」的附带用例。例如 `testDetailPageDoesNotCutTheBannerEither` 的注释原文是「「我的」里的订单详情页（`VolunteerOrderDetailViewModel`）共用同一个判定」。同一个测试文件里另有用例守着首页和订单页的主路径，所以删页面时连 ViewModel 和这 3 条用例一起删就行，规则仍有测试保护。删之前再跑一次 `scripts/device-test.sh` 覆盖这两个测试文件，确认剩下的用例是绿的。

删第 4 组时，要同时删掉 `FlowDesignSystemTests` 里那 4 条断言，并改正 `VolunteerOrderFlowStep.swift:9` 那条已经不对的注释。

### 没有入口，但要负责人先定（B 类，替代关系不明）

| # | 是什么 | 情况 |
|---|---|---|
| 5 | `LocationPermissionGuard`、`DemoLocationBanner`（`blindRun/Map/LocationPermissionGuard.swift:7`、`:64`），共 97 行 | 自从 9b541c87（调试面板）加进来，就从没有页面调用过，只在 `#Preview` 里出现。它不是被新设计替代的，是一直没接上：定位权限的引导现在散在各页面里做。**要问：删掉，还是接回去当统一的定位权限引导？** |
| 6 | `MapViewModel`（`blindRun/Map/MapViewModel.swift:10`），105 行 | 0 处引用，同样来自 9b541c87。地图状态现在由 `AMapContainer` 自己管。建议和第 5 条一起处理 |

### 和 #816 相关（等 #816 合并后再看）

#816 删的是旧的四步约跑表单，说明里写了负责人的决定：「语音功能保留，只删前端界面」。所以 `VoiceOrderWizard*` 和它的 14 个测试文件**不算残留**，本报告不列。

| # | 是什么 | 情况 |
|---|---|---|
| 7 | `BlindBookingMissingSetupCard`（`blindRun/BlindRunner/BlindBookingMissingSetupCard.swift:14`），61 行 | 唯一的调用点在旧表单 `BlindBookingView+FormStage.swift:19`，那个文件 #816 会删，但这张卡本身不在 #816 的文件清单里。#816 合并后，它只剩 `BlindReadinessAppStateTests.swift:66-74` 一个引用。新约跑页没有「约跑前还差 N 项」这张卡，而 `ContentView.swift:124` 的注释还说要靠它引导用户去补资料。**要问：新约跑页要不要接回这张卡（可以并进 #813「旧表单的规格要求接回新页」），还是删掉？** |
| 8 | `BlindMenuPicker`（`blindRun/Core/DesignSystem/BlindControls.swift:38`） | 只被 #816 要删的 `BlindBookingView+StepSections.swift` 用，`BlindControls.swift` 不在 #816 清单里。#816 合并后就是死代码，可以作为 #816 的补漏一起删 |

（`StepProgressDot` 只被旧表单使用。#816 会删 `HighContrastText.swift` 里 35 行，正好对应它，所以不另列。）

### 看过，不算残留

- `BlindOrderStatusView.trackingContent`（`BlindOrderStatusView+Flow.swift:210`）：这是改版前的只读滚动列表，现在只在「订单没加载出来」或「状态认不出」时显示。代码明确写了要保留（`+Flow.swift:58`：「这一条**不许删** —— 后端加状态时它是未知态唯一的落点」）。它符合 AGENTS「枚举未知值不许整条崩」的要求，保留。
- `VolunteerCertificationGateView`（`blindRun/Volunteer/VolunteerModule.swift:228`）：未审核的陪跑员登录后落在这一页（`ContentView.swift:328`）。它还是旧式的「昵称表单 + 提交 + 认证按钮」，但这个功能没有新页面接手，所以不算 A 类。**页面样式该不该照新稿重做，是另一件事，可以单独开 issue。**
- 已经核实「已删干净」的：常驻紧急红条（只剩 `SafetyHubView.swift:90`、`SafetyModule.swift:542`、`:965`、`EmergencyCallContext.swift:42` 几条过时注释）、一束光地图（原型提交 9f8e1054 从没进过 main）、盲人资料选择页 `BlindProfileChoicePage`（已删除）。
- 测试设施，保留：`FlowComponentGallery`、`FlowV2ComponentGallery`、`RopeGallery`、`RopeAnimationDemo`、各个 `*Preview` 结构体、`DebugTestingPanel`、`MockAPIClient*`。

### 顺带看到的过时注释（可以和删代码一起改）

- `BlindRunnerHomeView.swift:11`、`:784`、`:939`：路由名还叫 `voiceBooking`，实际指向新约跑页。注释说「删旧代码时（#810）一起改」，但 #816 没改。
- `Safety/BlindProfileEmergencyEntry.swift`：文件名是旧的，里面装的是现在仍在用的 `OrderSafetyRequestPresenter`。
- 上面「已删干净」那一条列出的红条注释。

## Periphery 其余结果

211 处里，除去上面列出的类型，其余约 170 处是没用到的属性和方法，以及只写不读的属性。另外 `Packages/AidRunAPI` 的 8 处按设计保留：生成代码只用来探测契约漂移，不在运行时使用（见记忆 `openapi-generated-code-is-drift-detector-only`）。这些不属于「旧界面」，留到第 2 轮（重复代码）和第 3 轮（架构）一起看。原始 JSON 不进仓库，要重新生成就照下面的命令跑：

```bash
xcodebuild build-for-testing -workspace blindRun.xcworkspace -scheme blindRun -destination 'generic/platform=iOS' -derivedDataPath <dd> CODE_SIGNING_ALLOWED=NO
periphery scan --project blindRun.xcworkspace --schemes blindRun --skip-build --index-store-path <dd>/Index.noindex/DataStore --retain-codable-properties --format json
```

## 怎么判删对了

- 删完以后 Periphery 再扫一次，报的条数要比 211 少，且减少的正好是删掉的那些类型和成员。
- `build-for-testing` 能编译通过。
- 删掉的类型名，全仓库搜不到。
- 第 1 组删完后，负责人在真机上点一遍陪跑员「首页 → 最近陪跑」，确认进的是跑后详情页。

## 没覆盖的

- 没跑真机测试（2026-11-05 起只编译）。
- 子代理没能用 CodeGraph，引用全靠文本搜索。用变量或闭包间接构造的页面可能漏掉。但 Periphery 读的是编译器索引，能补上这个盲区；两边结果是一致的。
- 没查 `Assets.xcassets` 里没用到的图片（FengNiao），留到删完代码以后再查，因为删页面会多出没用的图片。
