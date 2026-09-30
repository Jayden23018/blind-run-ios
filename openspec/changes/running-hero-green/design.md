## Context

`VolunteerRunningPage.heroCard` 用 `isPaused ? statePaused : stateAgreed`（`VolunteerOrderFlowPage.swift`）。`AppColors.Flow` 里没有青绿；交付包 v2 C01 给的是 `#0A6B72`。锁屏卡分支（PR #231）在 widget 目标里已有自己的 `stateRunning = 0x0A6B72`，与 App 目标是两份独立的色板，名字不冲突。

## Goals / Non-Goals

**Goals:** 跑步中头卡启用青绿；对比度有测试守。

**Non-Goals:** 跑步中页布局与功能；锁屏卡（FE-2）；把 App 与 widget 两份色板合并成一份（跨目标共享是另一件事）。

## Decisions

1. **新增 `stateRunning`，亮暗同值。** 与 `stateDeparted` / `stateDone` / `statePaused` 同一做法：底是品牌色表面，不随明暗变。
2. **对比度按测试同一套公式复算，全部过线**（WCAG 相对亮度；半透明白按 sRGB 逐通道叠合；复算方法先在「金色压藏青 = 10.57」上对过数，与 `FlowPalette.swift` 注释一致）：

   | 项 | 青绿 `#0A6B72` | 门槛 |
   |---|---|---|
   | 主角数字 / 标题（白） | 6.25 | 4.5 |
   | 小标题（白 90%） | 5.39 | 4.5 |
   | 副文（白 94%） | 5.73 | 4.5 |
   | 陪跑员头像姓氏 | 6.25 | 4.5 |
   | 跑者头像姓氏（白压白 8% 叠色） | 5.26 | 4.5 |
   | 引导绳（白 75%） | 4.27 | 3 |
   | 金色 `#FFD978` 压青绿 | 4.60 | 3 |

   跑步中头卡没有引导绳，后两行只是为了让 `heroStates` 的逐色用例一视同仁。
3. **暂停灰不动。** 暂停时整张头卡换灰（V13、FE-3），与青绿互斥。
4. **`heroStates` 加一项，并加一条断言钉住色值**：只加到列表里，取值被改成别的深色对比度用例也照样绿，所以单独断言 `stateRunning` 是 `0x0A6B72` 且 ≠ `stateAgreedTone` / `statePausedTone`。**它管不到 `heroCard` 有没有真的用这个色**（视图层一行取色，单测够不着），那一行靠 review；这个缺口写在用例注释里，不假装被守住。
5. **不改 widget 色板。** 那份在 PR #231 里，本变更合入后 App 里的 `stateRunning` 与它同值，靠人对（两处都写了 `0x0A6B72`）；合并两份色板留给后续。

## Risks / Trade-offs

- [App 与 widget 两份色板同值靠人对] → 两处都带同一个十六进制值与出处（交付包 C01），#231 合入时对一次；不为它单开抽象。
- [真机上青绿头卡与其他状态色的相邻观感未验] → 本变更只有编译与对比度复算，没有真机截图；INDEX「未逐屏对照」照旧，不写「一致」。
