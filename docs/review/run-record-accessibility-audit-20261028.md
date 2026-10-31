# 跑后记录无障碍走查（阶段 7，HANDOFF §7 九项）— 2026-10-28

范围：四个界面——记录 tab（两端）、陪跑员详情、跑者详情（含留言）。验收清单是 `docs/ui/mockups/run-record/HANDOFF.md` §7，原型是同目录 `prototype.html` 的 `data-vo`。

方法：读代码与用例，逐项判「通过 / 不通过 / 只能真机人工」。**没有跑真机**，下面的「通过」都是静态结论。代码基点是 PR「跑后记录阶段 7」分支，行号以该分支为准。

## 结论

| # | 检查项 | 记录 tab | 陪跑员详情 | 跑者详情 |
|---|---|---|---|---|
| 1 | 标签与 `data-vo` 信息不少 | 通过 | 本轮补了 4 处，余下见 #580 | 头部、分段、更多数据一致；路线叙述见 #580 |
| 2 | 进页右划一次到「听这次跑步」 | — | — | READY 有路线时通过；**无路线时原来要划两次，本轮已修** |
| 3 | 无裸「按钮」「图片」，装饰隐藏 | 通过 | 通过 | 通过 |
| 4 | 配速图有 `AXChartDescriptor` | — | 代码已接；Audio Graph 只能真机人工，方向疑似与声音路线相反（#581） | 不适用（没有配速图） |
| 5 | 地图一段整体描述、标记不逐个暴露 | — | 静态通过；真高德底图下未验 | 静态通过 |
| 6 | 最大字号竖排、不截断 | 竖排通过；「未完成的预约」行审计误报（见下） | 竖排通过；不截断只能看截图 | 竖排通过；不截断只能看截图 |
| 7 | 深色 / 增强对比度 / 减弱动态效果 | 深色、减弱动态效果通过；**增强对比度没有分支（#579）** | 同左 | 同左 |
| 8 | 颜色信息有文字或形状冗余 | 通过 | 通过（每行配速文字、「最快」字样、「快 ▬ 慢」图例） | 通过 |
| 9 | 讲述、声音路线、VoiceOver 不互相打断 | — | 不适用（没有播放） | 代码顺序通过；**声音路线渲染中焦点移走不取消，本轮已修**；听感只能真机人工 |

## 本轮修掉的

| 问题 | 位置 | 守着它的用例 |
|---|---|---|
| 陪跑员页导航标题念成「陈星号」 | `Shared/SpokenNavigationTitle.swift` | `testRunRecordScreensNeverSpeakMaskStarsAndRunnerNeverShowsPrimePace`（UI） |
| 地图描述没说颜色含义与最快的一公里；地图没有「快 ▬ 慢」图例 | `VolunteerRunRecordContent+Spoken.swift`、`RunPaceLegend.swift` | `testMapDescriptionSaysWhatTheColoursMeanAndWhichKilometreWasFastest`；UI `testVolunteerRunRecordDetailShowsTheCardAndPassesAudit` |
| 配速图摘要没有休息点、没说最快是第几公里 | `RunPaceChartDescriptor.swift` | `testPaceChartSummaryMentionsEveryRest`、`testPaceChartSummaryNamesTheFastestKilometreAndCadenceSaysAverage` |
| 步频念「步频」少了「平均」 | `VolunteerRunRecordView.swift` `primaryStats` | 同上 |
| 发送按钮没说谁能听到 | `VolunteerRunRecordView.swift` 发送按钮 hint | `testSendButtonHintSaysWhoWillHearItWithoutTheMask` |
| 跑者页无路线时「这次没有记录到完整路线」夹在头部与「听这次跑步」之间，要划两次 | `RunnerRunRecordView.swift` `loaded` | **没有用例**：Mock 没有 INSUFFICIENT_TRACK 种子，READY 那条 UI 用例守着顺序 |
| 声音路线还在渲染时焦点移走，渲染完照样响 | `Shared/RunRecordAudio.swift` `focusMoved` | `testRouteStillRenderingIsCancelledWhenFocusMovesAway` |

## 记录 tab 字号审计（tasks 1.2）：判误报

2026-10-14 在 iPhone 16 Pro / iOS 27.0.1、main `52d501a` 上跑 `testRunnerRecordsTabShowsMonthAndUnfinishedGroupAndPassesAudit`（4 条）与 `testVolunteerRecordsTabShowsMonthAndUnfinishedGroupAndPassesAudit`（5 条），都是「User will not be able to change the font size of this element」。被点名的只有「未完成的预约」那一组（组标题 + 行内状态、日期、地址）。

同一台机器 `testRecordsTabScreenshotsInLightDarkAndLargestText`（passed=1）的 `records-runner-ax-xxxl-bottom` 与 `records-volunteer-ax-xxxl-bottom` 两张截图里，这些字全部放大到了 AX-XXXL。与 2026-09-24（iOS 26）记下的 `List` 误报同形（项目记忆 `list-rows-false-dynamic-type-audit`）。按负责人当时的定法：不加审计白名单，两条用例保持红，根因（候选：常驻 `ScrollView` + `VStack` 替代 `List`）未查。证据原文在 #247 的评论里。

## 没修、已立 issue 的

- #579：四个界面不响应「增强对比度」（中）。
- #580：读屏比原型少的信息——路线叙述、分段备注「热身 / 包含折返」、途中记录措辞与休息地名（低）。
- #581：配速图 Audio Graph「高 = 慢」与声音路线「高 = 快」方向相反（低，只能人耳确认）。

## 只能真机人工的

- 时间「06:42」、分隔符「·」、全角括号的读法。
- 转子里 Audio Graph 能否播放、方向。
- 真高德底图下地图标记是否被读屏逐个读到（UI 测试恒为占位图）。
- 最大字号下文字有没有截断（只有截图附件，没有断言）。
- 讲述、声音路线、朗读留言与 VoiceOver 同时发声时的听感；别的 App 的音频只是被压低（ducking），不会被停。
- 增强对比度（XCUITest 切不了）。
