---
name: aidrun-ship-check
description: AidRun 模块收尾检查单与验证纪律。实现完成、准备提交、准备汇报「做完了/修好了/测试通过」之前必读。
---

# AidRun 收尾检查

从 `AGENTS.md` 第 11 / 12 / 15 节拆出，并入验证纪律。

## 一、宣称完成前的五步（不许跳）

1. **定位验证命令** —— 哪一条命令能证明这个主张？
2. **本会话新跑一次** —— 不引用上次的结果，不引用别人的结果。
3. **读全量输出，含退出码** —— 不是只看最后一行。
4. **确认它真的证明了这个主张** —— 编译通过不证明测试通过；套件绿不证明你新写的用例执行过。
5. **带证据汇报** —— 贴命令、贴关键输出、贴数字。

**禁用词**：「应该可以」「大概修好了」「理论上没问题」「不出意外的话」。

### 本仓库特有的两个假绿陷阱

- 真机跑测时若设备锁屏，`xcodebuild` 会**静默等在** `Run Destination Preflight: Unlock ... to Continue`，不报错也不退出，输出文件 0 字节看着像在跑。跑之前先解锁并保持屏幕常亮。用 `scripts/device-test.sh`，它会先探活。
- 日志里是 `Test case '...' passed`（**小写 c**）。按 `Test Case` 去 grep 会全部计成 0，然后你会以为一条都没跑或全跑了。

## 二、验证命令

> 2026-08-07：本节是**验证命令的唯一源**，`AGENTS.md` 已改为只留指针。
> 此前两处各存一份并且**已经漂移**——这里漏了 `validate-error-codes` / `validate-golden-corpus`
> 两条 CI 门禁，还少了「默认不要裸跑全量」的警告。正是 `AGENTS.md` §7 说的「两份会漂移」。

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机（唯一 XCTest 通道，模拟器因高德无 arm64-sim slice 永久不可用；
#       脚本会先探活并按小写 `Test case` 统计）
# ⚠️ 默认**不要**这样裸跑全量，先看下面第 2.1 节「跑多大范围」
scripts/device-test.sh

# 规格与文档
openspec validate --all --strict --no-interactive   # 全量；单个变更用 openspec validate <change-id> --strict --no-interactive
node scripts/validate-docs.mjs
node scripts/validate-spec-coverage.mjs    # 路径级：前端调的每条路径都在契约里
node scripts/validate-golden-corpus.mjs    # 语音黄金语料 vs 前端镜像清单
node scripts/validate-error-codes.mjs      # 前端 ErrorCode 枚举 vs 后端 ErrorCode.java

# 生产就绪
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 \
  scripts/production-readiness-check.sh
scripts/dual-device-validation.sh
```

后三条要读后端仓库。装一次本地 pre-push 钩子把它们钉在 push 前：`scripts/install-git-hooks.sh`。
CI（`.github/workflows/verify.yml`）跑编译门禁 + 规格校验，但**跑不了真机 XCTest**。

纯逻辑改动可以先用独立 Swift 脚本实跑，秒级出结果，但**它不能替代真机 XCTest**。

### 2.1 跑多大范围：默认只跑覆盖本次改动的 suite，不是全量

全量约 10 分钟、会超 Bash 600s 上限、还会撞上脚本的 preflight watchdog 反复被掐。
**默认做法**：先查哪些用例真的碰了你改的东西，只跑那几个 suite。

```bash
# ① 先定范围（把改动涉及的类型/方法名列进去）
python3 - <<'EOF'
import os, re
PATTERN = r'(BookingDurationOption|expectedDurationMinutes|makeCreateOrderRequest)'  # 换成你改的符号
for root, _, fs in os.walk('blindRunTests'):
    for f in (x for x in fs if x.endswith('.swift')):
        p = os.path.join(root, f)
        n = sum(1 for l in open(p).read().split('\n') if re.search(PATTERN, l))
        if n: print(f'{f}: {n} 处')
EOF

# ② 只跑命中的 suite
scripts/device-test.sh -only-testing:blindRunTests/VoiceOrderWizardTests \
                       -only-testing:blindRunTests/blindRunTests
```

**什么时候才必须全量**——只有一条判据：**改的东西是全 App 唯一的出口 / 共享单例 / 全局配置**，
所有调用方都从它身上过。例如 `SystemSpeechAudioSession`（每个用麦克风的地方都走它）、
`APIClient`、`AppState`。这类改动的影响面按符号搜不出来，必须全量。

反过来，「改了一个 view model 的一个字段」「加了一条解析规则」不属于这类，按符号搜到的 suite
就是完整覆盖面。**命中数只有 1 且是无关字面量的文件要看一眼再决定跳过**，别只看数字。

> 2026-08-06 立此条：同一天里全量被反复跑了 5 次，其中 4 次的结论在第 1 次就已经拿到，
> 后面纯粹是在跟脚本的 watchdog 较劲。用户两次指出这件事，走 §1.4。
>
> **零执行不是通过。** `passed=0 failed=0` 一律当失败查——设备锁屏、`-only-testing` 名字打错、
> 测试目标没编出来都会长这样：命令回来了、看起来一切正常，但一条断言都没跑。
> 脚本对这种情况有硬失败，别绕过它。

### 2.2 读后端仓库的那 4 条门禁在哪跑（2026-08-06 定型，别再重新推导一遍）

契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料这 4 条需要读后端私有仓库，跑在**三个不同的地方**：

| 位置 | 这 4 条 | 说明 |
|---|---|---|
| 上游 `JerryZhao-1/blind-run-ios` | ⚠️ **warning 空过** | 我们不是它的 admin，配不了 secret。**上游 CI 绿 ≠ 契约对过了** |
| fork `Jayden23018/blind-run-ios` | ✅ 真跑 | 配了 `BACKEND_REPO_TOKEN`（fine-grained PAT，只读 `blind-run-backend`） |
| 本地 pre-push | ✅ 真跑 | 读 `../demo`，装钩子后每次 push 自动 |

**fork 的既定配置**（改动前先知道，别当成异常）：

- 默认分支被**故意**设成 `integrate/swift-migration`，不是 `main` —— `workflow_dispatch`
  和 `schedule` 都只认默认分支，而 `main` 上没有 `verify.yml`。手动触发：
  `gh workflow run verify.yml --repo Jayden23018/blind-run-ios --ref integrate/swift-migration`
- `schedule` 每天 09:17（北京）跑一次。它抓的是 **push 触发天生抓不到的那类：你 push 之后
  后端才改契约**。上游默认分支是 `main` 且 `main` 上没有本文件，所以定时跑不会在上游触发。
- **fork 的 CI 红在 `Checkout backend contract`（403）= PAT 过期了**，不是代码坏了。
  重建 PAT 后 `gh secret set BACKEND_REPO_TOKEN --repo Jayden23018/blind-run-ios`。
- GitHub 会把连续 60 天无活动仓库的定时任务停掉。长期没推东西时留意一下。

**推送必须两边都到**，否则 fork 上那套 CI 等于没配。`scripts/install-git-hooks.sh` 已把
`git push origin` 配成同时推上游与 fork（前提是本机有名为 `fork` 的 remote），不靠人记：

```bash
git remote add fork https://github.com/Jayden23018/blind-run-ios.git   # 每台机器一次
scripts/install-git-hooks.sh                                          # 装钩子 + 配双推
```

pre-push 会先校验 `../demo` 与其 `origin/main` 一致 —— 停在特性分支或工作区脏着时，
这 4 条读的就不是契约本身，会直接拦下（逃生口 `AIDRUN_ALLOW_BACKEND_DRIFT=1`）。

契约 fixture（真实响应回归，见 `blindRunTests/ContractFixtureTests.swift`）：

```bash
node scripts/capture-fixtures.mjs            # dry-run，只列要打的只读端点
node scripts/capture-fixtures.mjs --write    # 真实采集并脱敏落盘
```

**编译通过不等于测试通过。永远不许把没执行过的测试写成通过。**

## 三、模块完成检查单

- [ ] 符合 `AGENTS.md`、`plan.md`、`docs/01-10`？
- [ ] 符合 OpenSpec？`openspec validate` 过了？
- [ ] 订单状态用词正确（无 `submitted`/`contacted`/`expired`/`matching`/`accepted`/`arrived`）？
- [ ] 没有把后端代码引入 iOS 仓库？
- [ ] 没有把 Flutter 当作当前实现？
- [ ] 没有硬编码高德 key？
- [ ] 没有把业务逻辑堆进 SwiftUI View？
- [ ] 有 accessibilityLabel / accessibilityHint？关键盲人按钮 ≥64pt？有「重复当前状态」？（目测项，**不能替代下面第五节的审计**）
- [ ] 危险操作有二次确认？
- [ ] 客户端模型与 ViewModel 对 API 响应和订单状态行为有测试覆盖？
- [ ] 改动触及的真实集成路径，在真机 `111` / `iPad Pro (2)` 上验证过？
- [ ] 新增/改写的用例**逐条**核过确实执行并通过，不是「套件绿就算跑了」？

## 四、汇报格式

1. 创建/修改的文件清单
2. 若改了 `AGENTS.md`，摘要说明改了哪些节
3. 是否发现 docs / OpenSpec 与 `AGENTS.md` 冲突
4. 需要人工确认的问题（需要后端拍板的写进后端仓库 `demo/docs/handoff.md` 的「待后端确认」）
5. 测试结果：**真跑过的写结果，没跑的明说没跑**
6. 未完成项及原因
7. 文档任务时，确认没有动业务代码

## 五、发版前无障碍门（**强制**，不可跳）

这是助盲应用。**无障碍回归 = 功能全损**，不是体验降级 —— 一个丢了 `accessibilityLabel` 的按钮，
对明眼人是"图标没文字"，对目标用户是"这个按钮不存在"。

CI 跑不了任何 XCTest（高德无 arm64-sim slice），所以这道门**只能靠人在发版前主动跑**。
它不会自己红给你看 —— 这正是它必须写进检查单的原因。

```bash
# 全量真机测试，含 blindRunUITests/AccessibilityAuditTests
scripts/device-test.sh

# 只跑无障碍审计（改动小时用，秒级）
scripts/device-test.sh -only-testing:blindRunUITests/AccessibilityAuditTests
```

`performAccessibilityAudit` 覆盖 5 类：`contrast` / `dynamicType` / `elementDetection` /
`hitRegion` / `sufficientElementDescription`。审计失败**不需要断言**，它自己会让用例红。

### 自动审计查不到的，必须人工过一遍

Apple 自己的立场是「审计是地板不是天花板」，且**只检查当前屏幕上的元素**。以下三条自动化覆盖不到：

- [ ] **开 VoiceOver 实走一遍改动路径** —— 审计能查"有没有 label"，查不了"label 念出来对不对"。
      ⚠️ `accessibilityIdentifier` 对辅助技术**不可见**，它是给测试用的；要断言的是 VoiceOver 念出「开始服务」，不是元素存在。
- [ ] **Screen Curtain（屏幕帘幕）走关键流程** —— 三指三击开启，屏幕全黑，这才是用户的真实处境。
      下单 / 接单 / SOS 三条路径必须能纯靠听完成。
- [ ] **焦点顺序与视觉顺序一致**，用转子（Rotor）核标题结构。

### 什么时候必须跑

- 任何 App Store 提交前 —— **无例外**
- 改动触及 SwiftUI View / 按钮 / 播报文案 / 状态流转时
- 后端 `ttsText` 模板有变更时（那是盲人真正"看到"的内容）

## 六、事故复盘（改动收尾时顺手做）

如果本轮修的是一个**已经犯过第二次**的错，按 `AGENTS.md` 的「事故复盘规则」给它找归宿：能静态查的进 `scripts/hooks/guard.mjs`，能运行时查的进测试，能「该做没做」查的进 `scripts/hooks/stop-checklist.mjs`，三者都不能的写进项目记忆。只写文档不算完成。

> 2026-08-07 订正：本行此前写的是 `scripts/hooks/guard.sh`，**该文件不存在**（早已改名 `guard.mjs`）。
> `AGENTS.md` §1 正好拿这次改名当「反复查 = 事实没落地」的范例，而这条死引用就躺在它自己举的例子上。
