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

```bash
# 无真机时的编译上限
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

# 真机全量（唯一的 XCTest 通道，模拟器因高德无 arm64-sim slice 永久不可用）
scripts/device-test.sh

# 规格与文档
openspec validate <change-id> --strict --no-interactive
node scripts/validate-docs.mjs
node scripts/validate-spec-coverage.mjs

# 生产就绪
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 \
  scripts/production-readiness-check.sh
scripts/dual-device-validation.sh
```

纯逻辑改动可以先用独立 Swift 脚本实跑，秒级出结果，但**它不能替代真机 XCTest**。

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
4. 需要人工确认的问题（需要后端拍板的开后端仓库 issue：`gh issue create --repo Jayden23018/blind-run-backend --label 待后端确认 --label handoff`）
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

## 六、跑多大范围：默认只跑覆盖本次改动的 suite，不是全量

> 2026-09-17 从 `AGENTS.md` §11 搬来。搬的理由：它只在**准备跑测试**那一刻有用，
> 而 AGENTS.md 每个会话常驻 —— 官方 context engineering 指南点名这类内容该走
> progressive disclosure（skill 注入不进缓存前缀，用到才付钱）。

全量约 10 分钟、会超 Bash 600s 上限、还会撞上脚本的 preflight watchdog 反复被掐。
**默认做法**：先查哪些用例真的碰了你改的东西，只跑那几个 suite。

```bash
# ① 先定范围（把改动涉及的类型/方法名列进去）
python3 - <<'PYEOF'
import os, re
PATTERN = r'(BookingDurationOption|expectedDurationMinutes|makeCreateOrderRequest)'  # 换成你改的符号
for root, _, fs in os.walk('blindRunTests'):
    for f in (x for x in fs if x.endswith('.swift')):
        p = os.path.join(root, f)
        n = sum(1 for l in open(p).read().split('\n') if re.search(PATTERN, l))
        if n: print(f'{f}: {n} 处')
PYEOF

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

### 用 `/goal` 把「跑到绿」交给评估器（可选，但条件的写法不可选）

真机测试是「终态可验证」的典型，适合 `/goal`。⚠️ 评估器**不跑命令、不读文件**
（官方逐字 *"It doesn't run commands or read files independently"*），只看 Claude 在对话里贴出来的东西
—— 所以条件必须写成**脚本输出里真的会出现的字样**，而且**必须带 turn 上限**：

```text
/goal scripts/device-test.sh 的输出里 failed=0 且 passed>0，且我没有改动 blindRunTests/ 以外的文件，or stop after 12 turns
```

写「测试通过」这种模糊条件没用，评估器判不了。三段各有各的作用：
**一个可测终态**（`failed=0 且 passed>0` —— `passed>0` 那半是本仓库的「零执行不是通过」，
少了它设备锁屏会被判成达成）+ **不许动的边界**（防止它改测试来凑绿）+ **turn 上限**。

🔴 **turn 上限在本仓库是必需项，不是保险。** 官方唯一的失控保护是
「**连续几轮没有工具调用**就停下」——而真机测试失败时**每一轮都真的跑了命令**，
那条保护**不会触发**。`device-test.sh` 在设备离线/锁屏时是快速失败（它先探活），
于是「快速失败 → 评估器判 not yet met → 再跑一轮」可以转得很快。
两台真机长期离线是本仓库的常态（见记忆 `ui-test-runner-needs-usb-not-wifi`：
11 种失败签名里大多数不是代码问题、要人去插线或点按），所以这条一定会撞上。

**三条本机前提，用前各看一眼**：

| 前提 | 现状（2026-09-21 实测） | 影响 |
|---|---|---|
| Claude Code 版本 | **2.1.224** | 官方 check-in 需 **2.1.234+**、idle check-in 需 2.1.236+、自动重试提示需 2.1.269+ ⇒ **本机都还没有**。后台任务卡住时不会有 30 分钟 check-in 来救，只能自己看 |
| 后台任务 | 有后台任务在跑时**跳过该轮评估** | 真机测试动辄几分钟，`run_in_background` 跑时评估会推迟 —— 属正常不是卡住 |
| 本仓库 Stop 钩子 | `stop-checklist.mjs`（exit 2 + stderr，`stop_hook_active` 兜底一轮只拦一次） | ⚠️ **与 `/goal` 的叠加行为未实测。** 官方说 `/goal` 自己就是 session 级的 prompt-based Stop hook，且「a hook that ended the turn」会让 goal **pause**。两者方向一致（都是「别停，继续」），推断不冲突，**但这是推断** |

`/goal`（无参数）看状态，`/goal clear` 清掉。`disableAllHooks: true` 或 `allowManagedHooksOnly`
时 `/goal` 整个不可用（评估器属 hooks 系统）——本仓库与本机 settings 都没设这两项，实测确认。

⚠️ **社区评价不一致，别当银弹**：HN 上 `mohsen1`（2026-05-28，[48313546](https://news.ycombinator.com/item?id=48313546)）
逐字说 *"Claude Code /goal or even /loop does not work hard enough and gives up. I have observed it
just claiming it's 'iterating' in a broken loop or simply giving up."* ——
那是 Claude Code 刚跟上这个功能时的评价（`/goal` 是 Codex 先有的），但**它描述的失效形态
正好是「假绿」**，与本仓库最怕的那类错误同型 ⇒ **`/goal` 报达成之后，仍然要自己看
result bundle 的 `passed=N failed=0`**，别把它当成验证本身。

完整依据、官方逐字原文与三条待实测项见
[`docs/research/goal-command-for-device-tests-20260921.md`](../../../docs/research/goal-command-for-device-tests-20260921.md)。

## 七、读后端仓库的那 5 条门禁在哪跑

> 同上，2026-09-17 从 `AGENTS.md` §11 搬来。只在 push 或排查门禁报错时需要。

契约覆盖 / 生成代码比对 / 错误码对撞 / 黄金语料 / 确认轮词表这 5 条需要读后端私有仓库，
跑在**两个地方**：

| 位置 | 这 5 条 | 说明 |
|---|---|---|
| `Jayden23018/blind-run-ios`（`origin`，**主线**）| ✅ 真跑 | 配了 `BACKEND_REPO_TOKEN`（fine-grained PAT，只读 `blind-run-backend`） |
| 本地 pre-push | ✅ 真跑 | 读 `../demo` 的 `origin/main`，装钩子后每次 push 自动（`scripts/install-git-hooks.sh`，每台机器一次） |

**`JerryZhao-1/blind-run-ios` 自 2026-08-12 起只是 `upstream`，不再是投递目标。** 分支不往那边推、
PR 也不往那边开。它的 CI 配不上 secret（我们不是 admin），这 5 条在那边是 warning 空过 ——
**上游 CI 绿 ≠ 契约对过了**。要取上游的新提交：`git fetch upstream`。

**主线仓库的既定配置**（改动前先知道，别当成异常）：

- 默认分支是 `main`。`workflow_dispatch` 和 `schedule` 都只认默认分支。手动触发：
  `gh workflow run verify.yml --repo Jayden23018/blind-run-ios --ref main`
- `schedule` 每天 09:17（北京）跑一次。它抓的是 **push 触发天生抓不到的那类：你 push 之后
  后端才改契约**。
- **CI 红在 `Checkout backend contract`（403）= PAT 过期了**，不是代码坏了。
  重建 PAT 后 `gh secret set BACKEND_REPO_TOKEN --repo Jayden23018/blind-run-ios`。
- GitHub 会把连续 60 天无活动仓库的定时任务停掉。长期没推东西时留意一下。

> ⚠️ **本节标题写着「既定配置」，最容易被当成不用核的背景事实照抄。**
> 2026-08-21 就据一句过时描述（「main 上没有 verify.yml」）推导出一个根本不存在的前置步骤。
> 引用本节任何一条之前，用一条命令当场核，别转述：
> `git ls-tree -r origin/main --name-only | grep .github`

这 5 条读的契约**取自后端仓库的 `origin/main`**（`git show origin/main:docs/api_spec.yaml`
落到临时文件），不是 `../demo` 的工作区文件 —— 工作区是共享 checkout，随时停在特性分支
或带着同事未提交的 WIP。所以 `../demo` 当前在哪个分支、脏不脏，都不影响门禁结论。

确实要拿未合并的后端改动验证 iOS 侧：`AIDRUN_ALLOW_BACKEND_DRIFT=1 git push` 改读工作区文件
（或用 `AIDRUN_API_SPEC=` / `AIDRUN_GOLDEN_CORPUS=` / `AIDRUN_BACKEND_ERROR_CODES=` /
`AIDRUN_BACKEND_VOICE_PARSER=` / `AIDRUN_BACKEND_VOICE_SERVICE=` 逐个指定）。
此时「生成代码与契约不同步」**不构成提交理由** —— 那份契约不是上游的，提交重新生成的结果
等于把别人的 WIP 烘进你的 PR。

> 🔴 **推论（2026-09-09 实测）：一次同时改两端的功能，必须后端先合，iOS 才推得上去。**
> 默认路径读后端 `origin/main`（新错误码/新端点还在你自己的分支上 → 报「前端映射了后端不存在的码」），
> 加 `AIDRUN_ALLOW_BACKEND_DRIFT=1` 则转而撞上上面这条。**两条都不是 bug，是设计使然的顺序约束。**
> ⛔ 不要用 `AIDRUN_SKIP_PREPUSH=1` 绕 —— 那一次跳过全部 5 道门禁。
> 正解：合掉后端 PR → `git checkout -- Packages/AidRunAPI/Sources/AidRunAPI` 还原 drift 弄脏的工作区 →
> iOS 直接 `git push`。详见记忆 `prepush-contract-gate-reads-backend-worktree`。

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

## 八、事故复盘（改动收尾时顺手做）

如果本轮修的是一个**已经犯过第二次**的错，按 `AGENTS.md` 的「事故复盘规则」给它找归宿：能静态查的进 `scripts/hooks/guard.mjs`（配 `scripts/validate-guard.mjs` 的正反用例），能运行时查的进测试，两者都不能的写进项目记忆。只写文档不算完成。
