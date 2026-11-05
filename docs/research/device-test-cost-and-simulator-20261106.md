# 真机测试的成本、价值与能不能搬到模拟器（2026-11-06）

问题（负责人原话）：「真机器测试有必要吗，消耗很多 token 吗，真机器测试的流程是否可以优化，先做调研和弄清楚现状」。

一手素材：

- 本机全部 971 份会话记录（`~/.claude/projects/*blind-run-ios*/**/*.jsonl`，2026-07-30 到 11-06，含子代理）。
- 本机残留的 157 份 `device-test.sh` 日志（`$TMPDIR/aidrun-device-test.*`，2026-11-04 14:34 到 11-05 23:50）。更早的日志已被系统清掉。
- `main` 上 2026-07-01 以来的 755 个提交。
- 本机 `lipo` / `otool` / `xcrun simctl` / `xcodebuild -help` 的输出。

统计脚本没入库，算法写在下面，可以照着重算。

## 1. Token：真机测试直接占全部 token 的约 11%

口径：一轮助手回复里只要有一次工具调用碰到真机测试（启动 `device-test.sh`、`pgrep` 等进度、`tail` 日志、`xcresulttool`、`devicectl`），这一轮的用量就记给真机测试。
按价格折算成「等价输入 token」：输入 ×1，写缓存 ×1.25，读缓存 ×0.1，输出 ×5。

| 月份 | 全部（百万） | 真机测试（百万） | 占比 |
|---|---|---|---|
| 2026-07 | 69.5 | 4.7 | 6.8% |
| 2026-08 | 460.8 | 47.9 | 10.4% |
| 2026-09 | 710.2 | 79.3 | 11.2% |
| 2026-10 | 771.4 | 100.1 | 13.0% |
| 2026-11（到 06 日） | 387.1 | 40.4 | 10.4% |
| **合计** | **2399.0** | **272.4** | **11.4%** |

这是**下限**：修测试、读失败用例代码、改断言的轮次没算进去。

按动作拆（这里排掉了只读脚本源码的轮次，所以合计与上表略有不同）：

| 动作 | 轮次 | 等价 token（百万） | 每轮（千） |
|---|---|---|---|
| 等待 / 查进度（`pgrep`、`sleep`、`tail`、`devicectl`） | 2529 | 115.6 | 46 |
| 启动 `device-test.sh` | 2051 | 92.9 | 45 |
| 读结果（`xcresulttool`、附件） | 592 | 24.8 | 42 |
| 其他 | 851 | 38.7 | 45 |

每轮都贵，是因为这些轮次的上下文中位数是 **306k**：读缓存按 0.1 算也要约 3 万，再加输出。
测试结果本身不大（平均 729 字符）。**钱花在轮次数上，主要是「等」**。

## 2. 手机占用时间：九成九在 UI 测试，七成在无障碍审计

157 份日志（11-04 下午到 11-05 晚，32 个工作区）：

- 总墙钟 7.6 小时。编译加安装 1.1 小时（中位 0.4 分钟，多为增量编译）。跑用例 6.2 小时。
- 用例自己报的耗时：**UI 测试 5.33 小时（510 次），单测 0.03 小时（1834 次，约 2 分钟）**。
- 按类：`AccessibilityAuditTests` 3.69 小时（69%），`blindRunUITests` 0.95 小时，`ScreenTourTests` 0.24 小时。
- 2344 次用例执行里只有 1399 条不同用例，224 条跑了 3 次以上。
- 129 轮真跑起来的里 **65 轮有失败，其中 40 轮只挂在 `AccessibilityAuditTests`**。另有 16 轮编译失败、12 轮没跑起来、6 轮零执行。

10-28 到 10-31 的旧统计（记忆 `scope-test-runs-to-what-changed`）是 141 轮、3.9 小时，其中编译 2.1 小时。
现在编译已不是大头，因为 DerivedData 复用后多为增量编译。

## 3. 价值：真机确实抓到过只有真机能抓的缺陷

`main` 上 7 月以来 238 个 `fix:` 提交里，21 个与真机或审计有关。其中约 6 个修的是测试设施本身，其余是 App 缺陷，例如：

- 无障碍审计：对比度、大字号截字、空闲时间页 11 条（#466）、邀请卡 `ViewThatFits`（#181）、首启页三处红灯（#672）。
- 只在真机出现的崩溃：`VoiceService` 释放后 TTS 回调（#279），未标隔离的 async 闭包（记忆 `unannotated-async-closure-property-crashes-on-device`）。
- `.task` 挂在空视图上从不触发（#134），大字号盖住派单面板抓手（#75）。

同时，审计的误报模式在记忆里已有 6 条以上（全角括号、容器阴影、`List` 行、底栏遮挡、`ViewThatFits`、弹层工具栏按钮）。
「40 轮只挂审计」里有多少是真缺陷、多少是误报，**这次没逐条分**。

## 4. 「模拟器永久不可用」这个前提需要复核

仓库多处写着「高德没有 arm64 模拟器架构，模拟器永久不可用」。这次核到的事实：

1. 高德四个库和阿里云实人认证 10 个库都是 `x86_64 arm64` 胖包。`otool` 显示 x86_64 那一片是 `LC_VERSION_MIN_IPHONEOS`，也就是 Intel 模拟器片。
2. `Podfile:36` 早已把模拟器的 arm64 排除，工程本来就按「x86_64 模拟器 + Rosetta」设计。
3. 本机装有 Rosetta（`arch -x86_64 /usr/bin/true` 成功）。
4. 本机两个模拟器运行时 `iOS 26.1`、`iOS 26.2` 的 `supportedArchitectures` 都**只有 `arm64`**，`-showdestinations` 里没有 Rosetta 目标。**这才是跑不起来的直接原因。**
5. Xcode 26 安装运行时默认只下 arm64 版。本机 `xcodebuild -help` 列出 `-downloadPlatform iOS … -architectureVariant <universal|arm64>`，可以装带 x86_64 的通用版。
   第三方文章写明了这一点：iOS 26 之前的运行时是通用版，Xcode 26 改成默认只下 arm64，要 x86_64 就用 `-architectureVariant universal`。

6. **编译这一步已实测通过**（2026-11-06，Xcode 26.2）：
   `xcodebuild build-for-testing -workspace blindRun.xcworkspace -scheme blindRun -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
   输出 `** TEST BUILD SUCCEEDED **`。`blindRun.app/blindRun` 是 `x86_64`，`blindRunTests.xctest` 与 `blindRunUITests.xctest` 都生成了，高德与阿里云都链接上了。

⇒ 「永久不可用」是把「默认运行时只有 arm64」误当成「Xcode 26 去掉了 Rosetta 模拟器」。

7. **运行这一步实测失败（2026-11-06 同日）**：
   - `xcodebuild -downloadPlatform iOS -buildVersion 26.2 -architectureVariant universal` 退出码 70，没有报错文字。
     不指定版本、加 `-exportPath` 后成功，装上 `iOS 26.3.1 (23D8133)`，`supportedArchitectures` 为 `['x86_64', 'arm64']`。导出的 dmg 是 10.4 GB。
   - 在这个运行时上建 iPhone 17 Pro 模拟器，用上面编好的产物跑
     `xcodebuild test-without-building … -destination 'platform=iOS Simulator,id=<UDID>,arch=x86_64' -only-testing:blindRunTests`。
   - 几分钟内 App 进程崩了 14 次，每次都在 Mac 上弹「blindRun quit unexpectedly」，所以中途停掉，没拿到结果包。
   - 崩溃报告（`~/Library/Logs/DiagnosticReports/blindRun-2026-11-06-02*.ips`）都是 `EXC_CRASH (SIGABRT)`，栈一致：
     `malloc_report` ← `swift_task_deinitOnExecutorImpl` ← `swift_task_deinitOnExecutorMainActorBackDeploy` ← `UserDefaultsAppStatePersistence.__deallocating_deinit` ← `AppState.deinit` ← `AppState.__isolated_deallocating_deinit`。
     另 1 次落在 `LoginViewModel.__deallocating_deinit`（`OnboardingAudibleFeedbackTests.testLoggingInWithAShortCodeSaysHowManyDigitsWereTyped`）。
   - 来源：工程设了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（`project.pbxproj:718`），编译器给主线程类生成「在主线程上释放」的 deinit。部署目标 iOS 16，所以用的是 App 内嵌的向后兼容版（`…BackDeploy`）。它在 x86_64 模拟器上一遇到嵌套释放就崩。
   - 真机上没有：11-04 到 11-05 的 157 份真机日志里，崩溃标记出现 0 次。
   - 影响面：`blindRunTests/` 里 95 个文件会创建 `AppState`。

⇒ **模拟器这条路现在走不通。** 编译能过，但大部分单测会让进程崩溃，还会在负责人的 Mac 上不停弹窗。
为了绕开一个只在模拟器上出现的运行时问题去改 App 的并发设置，不值得。真机仍然是唯一可用的 XCTest 通道。

天花板：Rosetta 的长期支持要以 Apple 公告为准，这次没核。高德或阿里云换成 xcframework 并带 arm64 模拟器片后，这条路就不需要了。

## 5. 结论

- **真机测试有必要，但只对一部分改动有必要**：音频、定位、VoiceOver 实际朗读、只在真机出现的崩溃，以及上架前在真机 `111` 的签核。纯逻辑单测在手机上只占约 2 分钟，不需要占手机。
- **Token**：直接占约 11%，最大的一块是「等」（42%）。
- **手机时间**：大头是 `AccessibilityAuditTests`。

可做的优化，按收益排：

1. 等待不再占轮次：启动后一次后台等到结束，只回一行结论，不再 `pgrep` / `tail` 轮询。估计能去掉「等待」那 115.6M 中的大部分。
2. 审计按改动的页面跑，攒成一批由调度会话统一跑（11-04 负责人已许可「改完一起跑一次」）。先把 40 轮「只挂审计」的失败分成真缺陷和误报。
3. ~~单测改到模拟器跑~~：11-06 实测不可行，见 §4 第 7 条。

## 来源

- [Start Debugging：Fix: Unable to find a destination matching …（2026-08）](https://startdebugging.net/2026/08/fix-unable-to-find-a-destination-matching-the-provided-destination-specifier-in-a-flutter-ios-build/)
- [Apple Developer Forums：How to enable Rosetta simulators on Xcode 26 Beta 3](https://developer.apple.com/forums/thread/793321)（抓取被拦，只看到搜索摘要）
- 本机 `xcodebuild -help`（Xcode 26.2，17C52）
