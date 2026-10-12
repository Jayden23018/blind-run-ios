# 盲人端方向 A 重设计（PR #370）：真机实现 vs 定稿逐屏对照

- 日期：2026-10-12
- 对象：`feat/blind-runner-redesign` 合入 `origin/main @ de662c6` 之后的提交
- 设计基准：`docs/ui/mockups/blind-redesign-20261007/final/A-final.png`（8 屏）；陪跑员端基准 `docs/ui/mockups/volunteer-order-page-v2/`
- 实现侧：iPhone 16 Pro 有线，`ScreenTourTests` 40/40 通过，72 张截图。截图按规则不入库，重抓命令：

  ```bash
  scripts/device-test.sh -only-testing:blindRunUITests/ScreenTourTests
  ```

## 结论

8 屏的骨架全部落地：彩色头卡按状态变色（匹配白 / 约好深蓝 / 出发蓝 / 汇合琥珀 / 跑步青绿 / 完成绿）、引导绳、底部常驻「求助与安全」、订单页隐藏标签栏且有返回、星火不显示在线志愿者数。
与定稿不同的 6 处都是**视觉或文案细节**，OpenSpec 规格没有逐字规定这些地方，不算任务未完成；要不要改由负责人定。

## 逐屏

| # | 定稿 | 真机截图 | 判定 |
|---|---|---|---|
| ① 首页 | 深蓝订单卡 + 引导绳 + 「预约新的陪跑」 | `B08-home-with-order` | 一致 |
| ② 语音预约 | 深蓝卡、标题「预约陪跑」、黄色主按钮「开始说话」+ 白色「改用表单」 | `B07-booking-voice` | **偏差 1**：整块蓝色卡，卡内白色胶囊「轻点开始说话」，底部是两个描边按钮「重复一遍」「改用表单」，没有黄色主按钮；导航标题是「创建预约」 |
| ③ 匹配中 | 白卡，眉题「匹配 · 第 1 步，共 4 步」，绳左端「?」，底部白色按钮「取消这次预约」 | `B10-blind-PENDING_MATCH` | **偏差 2**：眉题是开跑时刻（「明天早上 0:17 开跑」，单测 `testStepsOtherThanBookedPutTheStartTimeInTheEyebrow` 有意钉住），绳左端是「陪」；取消是信息列表里的一行「取消匹配」，不是底部按钮 |
| 约好（定稿未单列） | — | `B12-blind-SCHEDULED_CONFIRMED` | 深蓝卡 + 大号开跑时刻，与首页卡同语言 |
| ④ 出发 | 蓝卡「陈正在赶来」+ 黄色「打电话给陈」 | `B14-blind-DRIVER_EN_ROUTE` | 一致（眉题同偏差 2） |
| ⑤ 汇合 | 琥珀卡「陈到了，在南门等你」+ 黄色「开始跑步」+ 白色「打电话给陈」 | `B15-blind-DRIVER_ARRIVED` | **偏差 3**：标题「陈已到达」；**没有「打电话给陈」按钮**，只剩「开始跑步」与求助 |
| ⑥ 跑步中 | 青绿卡 + 并肩绳 + 三个数字；唯一的大按钮「听当前状态」 | `B16-blind-IN_PROGRESS` | **偏差 4**：按钮文案是「播报当前数据」（`BlindOrderFlowStep.swift:188`），高度是普通按钮，不是定稿那块加高的按钮 |
| ⑦ 完成 + 评价 | 绿卡 + 五档跑步小人评价在首屏 | `B19-blind-COMPLETED` | **偏差 5**：首屏是「服务已完成 / 本次路线」，评价在中间，两张截图都没截到评价那一段 ⇒ 五档小人**未经截图确认**（单测 `testRunExperienceRatingMapsFiveWordsToOneThroughFive` 守着档位映射） |
| ⑧ 星火 | 无顶部统计条，底部卡「N 对跑友正在同行」+「听见星光」 | `B30-xinghuo` | **偏差 6**：顶部仍有三格统计条（正在同行 / 今日陪跑 / 今日公里），已不含在线志愿者数，符合任务 5.3；定稿里没有这一条。地图区是占位图，因为 UI 测试默认关地图 |

## 陪跑员端（#370 只删节奏卡、调绳子阻尼）

`V01`–`V17` 的骨架与 v2 一致：彩色头卡 + 引导绳、右上求助胶囊、黄色主按钮、跑步中青绿头卡（V19）。
没有逐个对照 v2 的 13 个 HTML 画板，只确认 #370 没有改坏这一端。

## 真机测试

| 批次 | 结果 |
|---|---|
| 单测 12 个 suite | `passed=338 failed=0`；新增的 14 条 `BlindOrderHeroTests` 在日志里都是 passed |
| `ScreenTourTests` | `passed=40 failed=0` |
| `AccessibilityAuditTests` | `passed=43 failed=4` |

那 4 条失败在 `origin/main @ de662c6` 上用同一组 `-only-testing` 重跑，**4/4 同样失败、报错一致**，已由 #384 跟踪：
星火卡片把手排在内容前、求助中心读屏首项是关闭按钮、两端记录页 Dynamic Type。

#370 自己带进来的失败只有一条：`testBlindXinghuoPageShowsSummaryAndPassesAudit` 断言摘要要念「志愿者」，
而任务 5.3 有意去掉了这个人数。已改成断言「跑友正在同行」且不含「志愿者在线」，真机复跑后这两条断言通过，
该用例只剩 #384 那条把手问题。

## 没做的

- 任务 6.3 的「零上下文评委连续两轮 ≥8 分」没做 ⇒ OpenSpec 变更 `redesign-blind-runner-screens-a` 暂不归档。
- 低视力通道（深色、横屏、AX5 字号）没有截图对照。
