---
name: aidrun-visual-verdict
description: 拿参考图（docs/ui/mockups/ 的设计稿、用户给的截图）和真机实现截图逐项对比，打 0–100 分，给 pass / revise / fail 和差异清单，无障碍差异单列；没过线不收工。用户给了参考图、说「按设计稿来」「和这张图对一下」「像不像」，或改完界面要判还原度时读。
---

# AidRun 参考图对比（visual verdict）

功能对、界面不对，以前要人亲眼看才发现。这个 skill 把「看」变成一份可复核的判定：
分数、结论、逐条差异，加一栏无障碍检查。**没有参考图就不用它**，只做无障碍审计走 `aidrun-a11y-voice` / `aidrun-ship-check`。

## 一、参考图从哪来

1. 设计包：先读 `docs/ui/mockups/INDEX.md`。标「待确认」的行**先问用户**再拿来比。
2. 同目录有 `DECISIONS*.md` 时，它和图冲突以它为准（例：陪跑员订单页 v2 的 V4 已作废，图里还在）。被裁决掉的部分不算差异。
3. 用户在对话里给的截图。问清它是「目标长相」还是「现在的长相」，两者用法相反。
   问不到时（例如在 subagent 里跑）：按「目标长相」扣分，并把这个前提写进 `reasoning`。
   差异在代码里能找到有意为之的证据（注释、DECISIONS）时，`fix` 写「先确认参考图版本」，不写「删掉」。

## 二、实现截图从哪来

⛔ **模拟器拿不到本 App 的截图**，iOS Simulator 工具对它用不上，别试。原因：高德 SDK 的 arm64 只有真机 slice
（`otool -l -arch arm64 Pods/AMap3DMap-NO-IDFA/MAMapKit.framework/MAMapKit` 只见 `LC_VERSION_MIN_IPHONEOS`），
`Podfile` 因此排除了模拟器 arm64，App 编不出 Apple Silicon 模拟器版本（2026-10-20 复核）。

1. **真机，按页面跑一条巡游用例**：`blindRunUITests/ScreenTourTests.swift` 每屏一条用例（`testTour_B07_BookingVoice` 这类）。
   跑前先读 skill `aidrun-device-test`，然后：
   ```bash
   scripts/device-test.sh -only-testing:blindRunUITests/ScreenTourTests/testTour_B07_BookingVoice
   ```
   图在脚本最后打印的 `attachments/` 目录，`manifest.json` 记了哪张属于哪条用例。
   要比的页面没有巡游用例 → 在 `ScreenTourTests` 里照现有写法加一条，算本次 UI 改动的一部分。
2. 用户直接给的实现截图。
3. 真机离线或锁屏 → **不打分**，直接说「没有当前实现截图，未判定」。
   ⛔ 不拿仓库里的旧截图冒充当前实现。用户明说可以用旧图时，在 `implementation` 字段写明截图日期，
   并查截图之后这一页的源文件改过没有：`git log --oneline --since=<截图日期> -- <页面源文件>`。
   有提交就把「图比代码旧」写进 `conditions.mismatch`，这次判定只代表那张图，不代表当前代码。

## 三、比之前先对齐条件

两张图必须是同一种条件，否则差异是条件造成的，不是实现造成的：

| 条件 | 要求 |
|---|---|
| 设备 | iPhone 竖屏（上架包只支持 iPhone）。宽高比差 >3% 时 `vv.py` 会报 `WARN aspect` |
| 明暗 | 同一种外观 |
| 字号档 | 设计稿默认是「大」（系统默认档）；实现图也要默认档才能比还原度 |
| 数据状态 | 同一订单状态、同一角色。数据值不同（地名、时间、人名长短）不算差异；固定文案的措辞不同算「明显」差异 |

条件对不上的差异**不扣分**，写进 `conditions.mismatch`。状态栏、时间、电量、顶部「Mock 本地模拟」黄条一律忽略。

## 四、步骤

1. 出对比图和差异热点（坐标是实现图的像素）：
   ```bash
   python3 .claude/skills/aidrun-visual-verdict/scripts/vv.py pair <参考图> <实现图> <输出目录>
   ```
   输出 `side-by-side.png`：左参考、中实现、右热力图（红 = 变了，蓝框编号 = 热点）。
2. 用 Read 看 `side-by-side.png` 和两张原图。热点看不清就放大：`vv.py crop <图> X Y W H <输出.png>`。
   放大图是 3 倍：放大图里的坐标 ÷ 3，再加上裁剪起点 (X, Y)，才是实现图的像素坐标。
3. 按第五节逐条列差异、扣分。
4. 按第七节对**实现图**做无障碍检查。
5. 按第八节输出。
6. 没过线 → 改代码 → 重新截实现图 → 从第 1 步再判。**同一页最多 3 轮**；第 3 轮还没过就停下，把差异清单交给用户定（反复改同一处说明方向本身有问题）。

⚠️ 热力图只是**定位工具**，`changed pixels` 百分比**不是分数**：真实文案长度、列表行数一变，百分比就大幅波动。分数只从第五节来。
反过来，热力图没标出的地方也要自己看一遍：两张图整体偏移几个像素时，`vv.py` 会把整块都标红或都漏掉。

## 五、扣分表

分数 = 100 − 各条扣分之和，最低 0。**同一个根因只扣一次**（一组按钮都用错同一种样式 = 一条）。

| 级别 | 每条扣 | 什么算 |
|---|---|---|
| 结构 | 15 | 元素缺失或多出、元素顺序不同、主次关系不同（哪个是主按钮）、整块放错位置 |
| 语义色 | 10 | 状态色或主按钮色用错，颜色表达的意思变了（`AppColors` 的语义色） |
| 明显 | 5 | 字号档或字重一眼可见地不同、间距或对齐一眼可见地不同、圆角 / 描边 / 填充样式不同、文案不同 |
| 细微 | 2 | 要放大才看得出的间距、阴影、图标细节 |

**有意偏离不扣分**，列进 `intentional_deviations` 并写依据（`文件:行号`）：

- 实现比参考图更守本仓库的无障碍硬规则：字更大、按钮更高（盲人端主按钮 ≥64pt）、对比度更高、不封顶 Dynamic Type。
  设计稿与无障碍冲突时无障碍赢（`docs/ui/design-direction.md`）。
- `DECISIONS*.md` 已裁决改掉的部分。

## 六、过线阈值与理由

| 结论 | 条件 |
|---|---|
| `pass` | 分数 ≥ 90，**且**无障碍检查没有 `FAIL`（`未验` 不挡 `pass`，但汇报时必须逐项列出没验的） |
| `revise` | 分数 70–89；或分数 ≥ 90 但陪跑员端有无障碍 `FAIL` |
| `fail` | 分数 < 70；或**盲人端**有无障碍 `FAIL` |

为什么这样定：

- **90 = 一条结构差异就过不了线。** 对本 App 来说结构差异不只是「不好看」：VoiceOver 的遍历顺序跟视图的声明和绘制顺序走
  （记忆 `swiftui-traversal-order-follows-paint-order`），元素多一个、少一个或换了顺序，读屏顺序跟着变。
- **90 仍然容得下两条「明显」差异。** 设计稿是默认字号、假数据的静态图，真机有安全区和真实文案长度。
  要求 95 以上会逼人为了像素去改，而 `design-direction.md` 定的是无障碍优先于还原度。
- **低于 70 = 已经不是同一个设计**（例如两条结构差异加一条语义色）。这时继续微调没有意义，应该回头确认参考图是不是对的那一版。
- **无障碍一票否决。** 低视力用户靠的就是这块屏（记忆 `low-vision-visual-channel-unaudited`）。和设计稿一模一样、但字被截成「…」，等于没做。
  盲人端判 `fail`、陪跑员端判 `revise`，因为陪跑员是明眼人，部分门槛本来就低（`design-direction.md:212`）。

## 七、无障碍检查（单列，不进分数）

每项给 `ok` / `FAIL` / `待核` / `未验` 之一，并附证据。截图判不了的写 `未验`，**不写 `ok`**。
`待核` 是中间状态：查完代码后 `status` 改成最终的 `ok` 或 `FAIL`，查的过程写进 `evidence`。

| 检查 | 怎么判 | 门槛 |
|---|---|---|
| 文字截断 | 找「…」、只露半行的字、被底栏或求助条盖住的字 | 出现即 `FAIL` |
| 对比度 | `vv.py contrast <实现图> X Y W H`：框住一段字（或一个图标）和它所在的纯色底，框里只能有一种底色。脚本取框里最多的颜色当底、离底最远的那批像素当字。⛔ 别自己挑单个像素量：半尺寸截图的笔画只有 2px，单点取色会量出假的低值 | 正文 ≥4.5:1；大字、有意义的图标、控件边界 ≥3:1（`design-direction.md:55`、`:123`） |
| 点击区域 | 只量**能单独点**的控件；提示文字、装饰胶囊不量，整块可点的面板去代码查 `contentShape`。量可见形状的**描边外沿**：像素 ÷ 屏幕倍数 = pt。倍数 = 截图宽 px ÷ 屏宽 pt（iPhone 16 Pro 原图 1206 ÷ 402 = 3；缩到一半的图 603 ÷ 402 = 1.5） | 盲人端主按钮 ≥64pt（`aidrun-a11y-voice`）；陪跑员端主 / 次按钮 64、两列按钮 48、文字按钮与求助胶囊 44（`design-direction.md:212`）。量出来落在门槛 ±1pt 内 → `待核`，查代码里的尺寸常量 |
| 字号档 | 实现图是哪个字号档 | 只有默认档的图 → `未验`（AX5 要另截） |
| 遮挡 | 内容被底栏、求助条、横幅盖住 | 出现即 `FAIL` |

点击区域的特殊规则：截图只看得到**可见形状**，可点区可能比形状大（`contentShape`）也可能比形状小（`frame` 挂在 label 外面不扩大可点区，
记忆 `button-frame-outside-label-does-not-grow-hit-area`）。形状够门槛 → `ok`，但注明「可点区要 UI 用例断言 frame」；
形状不够 → `待核`，去代码查这个控件的 `frame` / `contentShape`，查实了再定 `ok` 或 `FAIL`。

VoiceOver 遍历顺序、`accessibilityLabel` 的文本、读屏行为从截图上看不出来，不在本 skill 的范围，写一行「截图判不了，见 `aidrun-a11y-voice`」。

## 八、输出格式

先给 JSON（下一轮对比和 PR 描述都直接引用它），再给一张中文汇总表。

```json
{
  "score": 85,
  "verdict": "revise",
  "reference": "参考图路径",
  "implementation": "实现图路径；来源（真机 ScreenTour 用例名 / 用户给）；截图时间",
  "conditions": {"device": "iPhone 16 Pro 竖屏", "appearance": "浅色", "text_size": "默认", "data_state": "盲人端·语音下单", "mismatch": []},
  "differences": [
    {"id": 1, "level": "结构", "deduct": 15, "where": "实现图 px (240,420)-(360,500)", "what": "实现多出麦克风图标，参考图没有", "fix": "删掉或回头确认参考图版本（已知时写 文件:行号）"}
  ],
  "intentional_deviations": [
    {"what": "主按钮比参考图高", "basis": ".claude/skills/aidrun-a11y-voice/SKILL.md:14 盲人端主按钮 ≥64pt"}
  ],
  "accessibility": [
    {"check": "文字截断", "status": "ok", "evidence": "全屏无「…」"},
    {"check": "对比度", "status": "ok", "evidence": "标题 #FFFFFF on #0058C7 = 6.52:1"}
  ],
  "reasoning": "一到两句：为什么是这个分数和结论"
}
```

`verdict` 由第六节的规则从 `score` 和 `accessibility` 推出来，不另凭感觉定。

## 九、来源

思路和 JSON 输出形状参考 [oh-my-claudecode `skills/visual-verdict/SKILL.md`](https://github.com/Yeachan-Heo/oh-my-claudecode/blob/e4b78700319d14425887eb310cfe0252f95e70ad/skills/visual-verdict/SKILL.md)
（MIT License，Copyright (c) 2025 Yeachan Heo；2026-10-20 读取）。本文件是重写，不是复制。和上游不同的地方：
扣分表让分数可复核；阈值按本 App 的读屏顺序与低视力场景重定；无障碍单列且一票否决；实现图走真机巡游用例；同一页最多 3 轮。
