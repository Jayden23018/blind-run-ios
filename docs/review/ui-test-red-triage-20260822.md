# 7 条真机 UI 测试长红的归因（2026-08-22）

**结论先说**：这 7 条**都不是** `feat/intro-call-ui`（PR #67）改红的。
7 条在 `origin/main` 上同样红、失败文案逐字相同。它们分别由 5 个**已合入 main** 的提交造成，
最早的一条已经红了 9 天。

本仓库 CI 跑不了 XCTest（高德无 arm64-sim slice，runner 只有模拟器），
所以「CI 全绿」只是编译信号 —— 这 5 个提交全都是带着红用例进 main 的。
同类事故已有记录：`docs/review/` 与项目记忆 `merged-prs-whose-tests-never-ran`。

## 0. 证据：三次真机跑，两条代码线，同一组 `-only-testing`

| 跑法 | HEAD | 结果 |
|---|---|---|
| 全量 | `feat/intro-call-ui` `cfcf4a8` | `passed=939 failed=12 skipped=1 (total=952)` —— 其中 5 条是 intro-call 自己的，已修 |
| 只跑这 7 条 | `origin/main` `4c119f5`（worktree） | `passed=0 failed=7 skipped=0 (total=7)` |
| 只跑这 7 条 | `feat/intro-call-ui` `cfcf4a8` | `passed=0 failed=7 skipped=0 (total=7)` |

后两次的 `-only-testing` 集合逐字相同（记忆 `regression-baseline-must-match-suite-set`），
7 条失败文案逐字相同。**基线红 ⇒ 不是本 PR 的锅。**

设备：iPhone 16 Pro / iOS 26.6 / USB，`scripts/device-test.sh`（统计只认 result bundle）。

## 1. 归因表

| # | 用例 | 基线 | 本分支 | 首次变红的提交 | 性质 |
|---|---|---|---|---|---|
| 1 | `testMockVolunteerOrderFlowSmoke` | 红 | 红 | `f404de2`（#60，08-21） | 用例陈旧：App 已刻意改成掩码 |
| 2 | `testMockVolunteerServiceArrivedWaitingScreenshots` | 红 | 红 | `f404de2`（#60，08-21） | 同上（同一处 helper） |
| 3 | `testMockVolunteerHomeMapAndControlsScreenshot` | 红 | 红 | `be4e030`（08-13） | 用例陈旧：被断言的 UI 已删除 |
| 4 | `testMockVolunteerLegacyTrainingCompletes…` | 红 | 红 | `c46da3c`（08-15） | 用例陈旧：流程中间插了一道同意门 |
| 5 | `testAuthLifecycleBlindAccountDeletionIsTwoStage…` | 红 | 红 | `9f9cede`（08-15） | 用例陈旧：文案改了一个字 |
| 6 | `testBlindHomeRemainsInteractiveWhileInitialRequestNeverReturns` | 红 | 红 | `c3e692a`（#22 / `30b0770`，08-14） | **真缺陷**：盲人首页误触求助条 |
| 7 | `testRealAMapEnabledSmoke` | 红 | 红 | `30b0770`（08-14） | 用例陈旧：identifier 被刻意删除 |

用例都在 `blindRunUITests/blindRunUITests.swift`。

## 2. 逐条根因

### 1 & 2 —— 号码被掩码了，用例还在等全号

断言在 `blindRunUITests/blindRunUITests.swift:1355-1356`（`openCurrentVolunteerService`
的 `requirePhone` 分支）：等 `app.staticTexts["13800001001"]`。

失败时刻的 App UI hierarchy 里那个元素长这样：

```
Button, label: '拨打盲人电话'
  StaticText, label: '138****1001'
```

`blindRun/Volunteer/VolunteerOrderFlowViews.swift:2581` 现在渲染的是
`EmergencyContactResponse.maskPhone(phone) ?? phone`。改动来自 `f404de2`（审计 F10），
理由写得很清楚且成立：**VoiceOver 是外放的，念全号等于把盲人的号码广播给周围所有人**；
「要真号去订单详情页按拨号键，那条路不经过朗读」。

⚠️ 这一条同时是个**文档与实现的冲突，需要人拍板**：`AGENTS.md` §8 写着
「接单后展示完整手机号」。`f404de2` 之后，全号在任何界面上都不再**显示**，只用于拨号动作。
两者只能留一个。倾向保留 `f404de2` 的行为（隐私理由更硬）并改 §8 的措辞，但这是产品决定。

修法（拍板后）：把 `:1355` 改成等 `138****1001`，并在真正该露全号的地方（若还有）单独断言。

### 3 —— 「积分」这一格已经被删掉了

断言在 `:524`：`app.staticTexts["积分"]`。

`be4e030`（08-13，「志愿者服务成就取代假积分与永远兑换不了的商城」）把派单汇总卡从四格改成三格，
`blindRun/Volunteer/VolunteerHomeView.swift:1575` 的注释就写着这件事：
「三格，不是四格。此前第一格是「积分」，值是 `totalCompleted * 100`」——
后端从来没有积分字段，那个数字是编的。失败时刻的 hierarchy 里是「完成 / 评分 / 接单率」。

`be4e030` **没有改动 `blindRunUITests/`**。

修法：`:524` 改成断言三格中真实存在的一格（例如「接单率」），或直接删掉这一条。

### 4 —— 提交实名信息前插进了一道同意门

失败在 `:451`：点完「提交身份信息」后等「开始活体认证」按钮，等不到。

失败时刻的 hierarchy 显示，挡在前面的是一张新的同意页：

```
ScrollView #volunteerIdentityConsentView
  StaticText «提交实名信息前，请先确认»
  Button #volunteerIdentityConsentAgreeButton «同意并提交»
  Button #volunteerIdentityConsentDeclineButton «先不提交»
```

来自 `c46da3c`（08-15，「上架合规——首次启动的告知同意门，身份证号与人脸单独同意」），
闸门在 `blindRun/Volunteer/VolunteerRegistrationFlowView.swift:1162`
（`guard consentStore.hasConsented(to: .volunteerIdentity, …)`），
identifier 由 `blindRun/Core/PrivacyConsentGateView.swift:31` 的
`identifierPrefix: "\(purpose.rawValue)Consent"` 拼出。

`c46da3c` 确实动了 `blindRunUITests/`（+37 行），但加的是**启动同意门**的新用例和它的绕过开关
（`AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT`）；**实名同意门是流程内的一步，没有绕过开关**，
而这条老用例没跟着补点击。

修法：在 `:448` 之后补一次 `volunteerIdentityConsentAgreeButton` 的点击。

### 5 —— 文案从「会失效」改成了「立即失效」

失败在 `:914`：断言最终确认弹窗的 message `CONTAINS "所有登录令牌会失效"`。

`blindRun/Core/AppState.swift:71` 现在写的是「所有登录令牌**立即**失效」。
改动来自 `9f9cede`（08-15，「删除账户的最终确认逐项说清删什么、留什么」）——
该提交加了单测 `testAccountDeletionCopyStatesWhatIsDeletedAndWhatIsKept`，
**没有改 `blindRunUITests/`**，而且它自己的提交说明就写着「真机单测因设备锁屏未执行，
新增的这一条都还没跑过」。

修法：`:914` 的期望串改成「所有登录令牌立即失效」（或截短到「登录令牌」这种不随措辞漂移的片段）。

### 6 —— 这条是真缺陷，不是用例陈旧

失败在 `:134-137`：

```
XCTAssertFalse(app.buttons["拨打110"].firstMatch.exists,
               "本地操作的触点落到了常驻求助条上，弹出了本地拨号确认单")
```

这是 `a68bed4`（08-14）钉下的回归断言。那次事故的链路（当时从屏幕录像逐帧还原）：
「重复当前状态」排在 280pt 的「开始约跑」下面，无订单态里整段落在首屏之外；不滚就点，
XCUITest 仍报 `isHittable == true`，但触点被钳到屏幕底部常驻的「紧急呼叫」条上，
弹出本地拨号确认单，紧接着的 swipe 在确认单上拖拽选中了「拨打110」。
**真机上这一步是真的要拨出去的，当时只有双卡选号单挡了一下。**

`a68bed4` 当时验过：修前 `passed=0 failed=1`（连跑两次），修后 `passed=1 failed=0`。
它现在又红了 —— 说明 `scrollElementIntoView` 已经不再能把「重复当前状态」滚进可视区。

**二分结果（真机，逐个 checkout 只跑这一条）：**

| commit | 日期 | 这条断言 |
|---|---|---|
| `f2e8a04`（#18 首次使用引导） | 08-14 | **过**（2 次执行到该行，2 次都过） |
| `c3e692a`（#22 / `30b0770` 装饰地图对读屏隐藏） | 08-14 | **红** |
| `5d339ef`（#24） | 08-14 | 红 |
| `4c119f5`（main） | 08-22 | 红 |

⇒ **首次变红于 `c3e692a`（PR #22，提交 `30b0770`）**。

机理说得通：`30b0770` 把装饰地图 `accessibilityHidden(true)`
（`blindRun/Map/AMapContainer.swift:352` / `:372` 一带），提交说明自己写着
「代价：`blindRunnerHomeAuxiliaryMap` 不再出现在无障碍树里，XCUITest 也就看不见它」。
XCUITest 只看无障碍树，`scrollElementIntoView`（`blindRunUITests/blindRunUITests.swift:1225`）
的滚动量因此算错，按钮没被滚进来，触点又被钳回底部的求助条。

⚠️ **`30b0770` 当时判断错了一次，值得记一笔**：它的提交说明写
「`testBlindHomeRemainsInteractive…` 红，但 stash 掉本改动跑同一条用例报同样的错，是既有缺陷」。
它的分支是在 `a68bed4` 落地**之前**切出来的，所以 stash 后的基线本来就还没修 ——
对照的是错误的基线，于是把自己引入的回归判成了「既有缺陷」。
（记忆 `regression-baseline-must-match-suite-set` 说的是同一件事的另一半：
基线不只要 suite 集合一致，**代码基点也要是修复之后的那个点**。）

**这条要修，而且优先级最高**：它不是断言写歪了，是盲人首页上一个能真的拨出 110 的误触。

附带一个观察：这条用例在 `f2e8a04` 上**不稳**（4 次跑出 1 过 3 红，三种互不相同的失败：
设备横屏、SpringBoard 抢焦点、加载状态在断言前就跳过了「正在后台同步」阶段）。
判定用的是「误触断言这一行本身是过是红」，不是整条用例的红绿 —— 3 次里有 2 次执行到了该行且都过。
稳定性本身也该单独修（`:107` 那条对启动耗时敏感）。

### 7 —— 断言了一个被刻意删掉的 identifier

失败在 `:961`：等 `blindRunnerHomeAuxiliaryMap`。

`30b0770`（08-14）把这个 `.accessibilityIdentifier` 从盲人首页装饰地图上删掉了 ——
这是「装饰底层只能 `accessibilityHidden`」那条结论的直接后果（见
`docs/research/swiftui-voiceover-traversal-order-20260814.md`）。全仓 App 源码里现在
**零命中**这个字符串，只剩 `AMapContainer.swift:352/:372` 的 `accessibilityLabel`。

`30b0770` 改了 `blindRunUITests/`（58 行），把 `:54` 那条改成断言 `count == 0` —— 但**漏了 `:961`**。
（`blindRunUITests/AccessibilityAuditTests.swift:708` 里也还留着它，那只是白名单里的一条死条目，不会失败。）

修法：`:961` 改成按 label 找（`地图，显示当前位置和订单地点`），或删掉这一条断言 ——
`testRealAMapEnabledSmoke` 的其余断言（不得回落到缺 key 占位图）才是它的价值所在。

## 3. 建议的处置顺序

1. **`#6` 先修**，它是真缺陷（盲人首页误触 → 拨 110）。修 `scrollElementIntoView` 对
   `accessibilityHidden` 容器的滚动量计算，或改用 label 定位后 `swipeUp` 到位再点。
2. `#1/#2` 需要产品先拍板 `AGENTS.md` §8 与 `f404de2` 的冲突，再改用例。
3. `#3/#4/#5/#7` 是纯用例陈旧，一次 PR 改掉即可，逐条对着上面的「修法」。
4. `#6` 在 `f2e8a04` 上的不稳定性单独看一眼（`:107` 对启动耗时敏感）。

**不要在 `feat/intro-call-ui` 上顺手修** —— 一个 PR 只装一件事。

## 4. 这批事故的共同形态

5 个提交里，`be4e030` / `9f9cede` / `f404de2` **完全没动 UI 测试**，
`30b0770` / `c46da3c` 动了但各漏一处。全都通过了 CI，因为**本仓库 CI 跑不了 XCTest**。

`AGENTS.md` §1 的判据（「犯过第二次」）在这里成立：这已经是记忆
`merged-prs-whose-tests-never-ran` 记下的同一类事故的第二批。
可落地的机器归宿有两个方向，都不在本轮范围内，留给后续决策：

- 合并前的人工闸：PR 描述里必须有 `passed=N failed=0` 才允许合并（可做成 PR template + 一条 CI 检查）。
- 静态闸：`scripts/hooks/guard.mjs` 增加一条 —— 删除/改写带 `accessibilityIdentifier`
  的字符串或用户可见文案时，若 `blindRunUITests/` 里仍有同名字面量则拦住。
  这条能覆盖本批 7 条里的 `#3` `#5` `#7`（`#1/#2` 是渲染函数换了、`#4` 是插了一步，静态抓不到）。

## 5. 复现命令

```bash
# 基线（任选一个 sha 建 detached worktree；Pods 与 LocalConfig.xcconfig 软链到主 checkout）
git worktree add --detach /tmp/aidrun-baseline origin/main
ln -s "$PWD/Pods" /tmp/aidrun-baseline/Pods
ln -s "$PWD/LocalConfig.xcconfig" /tmp/aidrun-baseline/LocalConfig.xcconfig

cd /tmp/aidrun-baseline
AIDRUN_PREFLIGHT_TIMEOUT=900 scripts/device-test.sh \
  -only-testing:blindRunUITests/blindRunUITests/testMockVolunteerOrderFlowSmoke \
  -only-testing:blindRunUITests/blindRunUITests/testMockVolunteerServiceArrivedWaitingScreenshots \
  -only-testing:blindRunUITests/blindRunUITests/testMockVolunteerHomeMapAndControlsScreenshot \
  -only-testing:blindRunUITests/blindRunUITests/testMockVolunteerLegacyTrainingCompletesWithoutTrainingAndReturnsHomeUnavailable \
  -only-testing:blindRunUITests/blindRunUITests/testAuthLifecycleBlindAccountDeletionIsTwoStageAndCompletesOnce \
  -only-testing:blindRunUITests/blindRunUITests/testBlindHomeRemainsInteractiveWhileInitialRequestNeverReturns \
  -only-testing:blindRunUITests/blindRunUITests/testRealAMapEnabledSmoke
```

> ⚠️ 在 08-14 之前的提交上 checkout 时 `Podfile.lock` 会和已装的 Pods 对不上，
> xcodebuild 报 `The sandbox is not in sync with the Podfile.lock`（退出码 65，看着像工程配置错）。
> **不要在共享 Pods 的 worktree 里跑 `pod install`** —— 那会改到主 checkout 的 Pods。
> 差异只是 `AliyunCloudAuth` 的 checksum（`4c119f5` 删了 vendored 副本），
> 直接 `git checkout main -- Podfile.lock` 即可，不影响被测的界面代码。

失败详情（每条的屏幕录像 + App UI hierarchy 附件）都在全量那次的 result bundle 里，
读法：

```bash
xcrun xcresulttool export attachments --path <bundle>.xcresult \
  --test-id "blindRunUITests/<testName>()" --output-path /tmp/att
```
