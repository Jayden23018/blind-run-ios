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

如果本轮修的是一个**已经犯过第二次**的错，按 `AGENTS.md` 的「事故复盘规则」给它找归宿：能静态查的进 `scripts/hooks/guard.sh`，能运行时查的进测试，两者都不能的写进项目记忆。只写文档不算完成。
