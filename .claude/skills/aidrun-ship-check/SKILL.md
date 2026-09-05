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

## 二、验证命令（`AGENTS.md` §11 的完整版）

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机（唯一 XCTest 通道；脚本会先探活，统计只认 result bundle 不认日志）
# ⚠️ 默认**不要**这样裸跑全量，先看下面「跑多大范围」
scripts/device-test.sh

openspec validate --all --strict --no-interactive
node scripts/validate-docs.mjs
node scripts/validate-spec-coverage.mjs    # 路径级：前端调的每条路径都在契约里
node scripts/validate-golden-corpus.mjs    # 语音黄金语料 vs 前端镜像清单
node scripts/validate-error-codes.mjs      # 前端 ErrorCode 枚举 vs 后端 ErrorCode.java
node scripts/validate-voice-intent-words.mjs  # 确认轮本地直通表 vs 后端 VoiceSlotParser 的 INTENT_* 正则

# 生产就绪
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 \
  scripts/production-readiness-check.sh
scripts/dual-device-validation.sh
```

中间四条（spec-coverage / golden-corpus / error-codes / voice-intent-words）要读后端仓库。
装一次本地 pre-push 钩子把它们钉在 push 前：`scripts/install-git-hooks.sh`。
CI（`.github/workflows/verify.yml`）跑编译门禁 + 规格校验，但**跑不了真机 XCTest**。

纯逻辑改动可以先用独立 Swift 脚本实跑，秒级出结果，但**它不能替代真机 XCTest**。

### 跑多大范围：默认只跑覆盖本次改动的 suite，不是全量

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
> 后面纯粹是在跟脚本的 watchdog 较劲。用户两次指出这件事，走 `AGENTS.md` §1.4。
>
> **零执行不是通过。** `passed=0 failed=0` 一律当失败查——设备锁屏、`-only-testing` 名字打错、
> 测试目标没编出来都会长这样：命令回来了、看起来一切正常，但一条断言都没跑。
> 脚本对这种情况有硬失败，别绕过它。

### 读后端仓库的那 5 条门禁在哪跑（2026-08-12 改口径，别再按旧的双推推导）

契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料 / 确认轮词表这 5 条需要读后端私有仓库，
跑在**两个地方**：

| 位置 | 这 5 条 | 说明 |
|---|---|---|
| `Jayden23018/blind-run-ios`（`origin`，**主线**）| ✅ 真跑 | 配了 `BACKEND_REPO_TOKEN`（fine-grained PAT，只读 `blind-run-backend`） |
| 本地 pre-push | ✅ 真跑 | 读 `../demo` 的 `origin/main`，装钩子后每次 push 自动 |

**`JerryZhao-1/blind-run-ios` 自 2026-08-12 起只是 `upstream`，不再是投递目标。** 分支不往那边推、
PR 也不往那边开。它的 CI 配不上 secret（我们不是 admin），这 5 条在那边是 warning 空过 ——
**上游 CI 绿 ≠ 契约对过了**。要取上游的新提交：`git fetch upstream`。

**主线仓库的既定配置**（改动前先知道，别当成异常）：

- 默认分支是 `main`（2026-08-21 从 `integrate/swift-migration` 改过来，该分支同日已删除）。
  `workflow_dispatch` 和 `schedule` 都只认默认分支，而 `verify.yml` 就在 `main` 上，
  且比原 integrate 上那份更新（多一个 `validate-shared-checkout-guard` job）。手动触发：
  `gh workflow run verify.yml --repo Jayden23018/blind-run-ios --ref main`

  > 改动前这里写着「默认分支是 integrate，而 `main` 上没有 `verify.yml`」—— **后半句早就不成立了**，
  > `main` 上一直有。这句过时描述的代价是真的：2026-08-21 据它推导出「要删 integrate 得先把
  > `verify.yml` 落到 main」这个根本不存在的前置步骤。清理时 integrate 已落后 main 62 个提交、
  > 独有提交 0，唯一活着的理由就是被默认分支设置钉住。
  > **教训**：这一节标题写着「既定配置」，最容易被当成不用核的背景事实照抄。
  > 引用本节任何一条之前，用一条命令当场核，别转述：
  > `git ls-tree -r origin/main --name-only | grep .github`
- `schedule` 每天 09:17（北京）跑一次。它抓的是 **push 触发天生抓不到的那类：你 push 之后
  后端才改契约**。
- **CI 红在 `Checkout backend contract`（403）= PAT 过期了**，不是代码坏了。
  重建 PAT 后 `gh secret set BACKEND_REPO_TOKEN --repo Jayden23018/blind-run-ios`。
- GitHub 会把连续 60 天无活动仓库的定时任务停掉。长期没推东西时留意一下。

每台机器装一次钩子即可，不再需要配双推（旧机器重跑本脚本会清掉遗留的双推配置）：

```bash
scripts/install-git-hooks.sh
```

这 5 条读的契约**取自后端仓库的 `origin/main`**（`git show origin/main:docs/api_spec.yaml`
落到临时文件），不是 `../demo` 的工作区文件 —— 工作区是共享 checkout，随时停在特性分支
或带着同事未提交的 WIP，而 CI 是从后端默认分支拉契约的。所以 `../demo` 当前在哪个分支、
脏不脏，都不影响门禁结论。

确实要拿未合并的后端改动验证 iOS 侧：`AIDRUN_ALLOW_BACKEND_DRIFT=1 git push` 改读工作区文件
（或用 `AIDRUN_API_SPEC=` / `AIDRUN_GOLDEN_CORPUS=` / `AIDRUN_BACKEND_ERROR_CODES=` /
`AIDRUN_BACKEND_VOICE_PARSER=` / `AIDRUN_BACKEND_VOICE_SERVICE=` 逐个指定）。
此时「生成代码与契约不同步」**不构成提交理由** —— 那份契约不是上游的，提交重新生成的结果
等于把别人的 WIP 烘进你的 PR。钩子在这条路径上会自己说明，并给出 `git checkout --` 的还原命令。

> ⚠️ **这只管 pre-push。** 手动跑 `node scripts/validate-*.mjs` 仍然默认读 `../demo` 工作区 ——
> 2026-08-12 因此把一份**正确**的语料镜像改动判成了伪造（后端当时停在特性分支，语料 96 条而
> `origin/main` 已 101 条），差点据此删掉。手动跑之前自己导出真契约：
> `git -C ../demo show origin/main:docs/voice-golden-corpus.json > /tmp/c.json` 再传进去。
> 详见 `docs/review/frontend-backend-alignment-review-20260812.md` §B1。

> 第 5 条 `validate-voice-intent-words.mjs` 是 2026-08-10 加的：确认轮改成「本地直通 + 后端兜底」
> 之后，同一句话由两处判定，本地表里出现一个后端判成**别的**意图的词就会让有网/断网行为分叉。
> 加它的直接起因是「再说一次」——前端判「重说」（清空整句）、后端判 `REPEAT`（只重念）。

契约 fixture（真实响应回归，见 `blindRunTests/ContractFixtureTests.swift`）：

```bash
node scripts/capture-fixtures.mjs            # dry-run，只列要打的只读端点
node scripts/capture-fixtures.mjs --write    # 真实采集并脱敏落盘
```

### 用 `/goal` 把「跑到绿」交给评估器

真机测试是「终态可验证」的典型，适合 `/goal`。⚠️ 但评估器**不跑命令、不读文件**，
只看 Claude 在对话里贴出来的东西 —— 所以条件必须写成脚本输出里会出现的字样：

```text
/goal scripts/device-test.sh 的输出里 failed=0 且 passed>0，且我没有改动 blindRunTests/ 以外的文件
```

写「测试通过」这种模糊条件没用，评估器判不了。另外后台任务在跑时它会**跳过该轮评估**，
真机测试动辄几分钟，属于正常现象不是卡住。

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

如果本轮修的是一个**已经犯过第二次**的错，按 `AGENTS.md` 的「事故复盘规则」给它找归宿：能静态查的进 `scripts/hooks/guard.mjs`（配 `scripts/validate-guard.mjs` 的正反用例），能运行时查的进测试，两者都不能的写进项目记忆。只写文档不算完成。
