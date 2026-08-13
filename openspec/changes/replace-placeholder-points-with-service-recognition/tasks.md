# Tasks

## 1. 契约投递（与实现并行）

- [ ] 1.1 投 handoff「待后端确认」：要不要做真的积分体系？要的话给出产生规则、
      有没有兑换出口、会不会过期。注明前端已撤掉假实现，**不阻塞**后端将来做真的。
- [ ] 1.2 投 handoff：完成单数多的志愿者要不要在派单里加权（滴滴「点亮勋章后接单概率增加」）？
      这决定成就体系是纯荣誉还是有实际收益，会影响前端文案措辞。
- [ ] 1.3 投 handoff：`dispatch-summary` 能否补**累计服务时长**？按小时数分层是行业通行做法，
      我们缺这一维只能退用单数。

## 2. 删除假积分

- [ ] 2.1 `blindRun/Core/Models/VolunteerDispatchSummaryModels.swift`：
      删 `pointsBalance` 字段（`:78`）与 `resolvedPointsBalance`（`:82-84`）；
      删 `pointsDelta` 的 `+100` 兜底（`:177-182`），**保留 `pointsDelta` 字段本身**（见 D6）。
- [ ] 2.2 `blindRun/Volunteer/VolunteerHomeView.swift`：
      `:1431` 删「积分」那格（剩三格，不补第四格）；
      `:1481` 的 `accessibilityLabel` 同步删「积分 N」——**这条最容易漏，视觉上没了但读屏还在念**；
      `:1266-1269` 入口图标 `gift` → `rosette`，标题「积分」→「服务成就」，hint 同步。
- [ ] 2.3 `blindRun/Volunteer/VolunteerOrderFlowViews.swift`：
      删 `:11` 的 `"+100 积分"`、`:65` 与 `:2375` 的「服务完成，获得 +100 积分」、
      `:2458` 的 `accessibilityLabel("服务完成，获得一百积分")`。
      `pointsDelta` 为 `nil` 时不显示积分行（不再编造）。
- [ ] 2.4 `blindRun/Core/MockAPIClient.swift`：`:895` 的 `pointsDelta: 100`、`:938` 的
      `pointsBalance: nil` 随字段调整。Mock 不得再造出后端不存在的字段值。

## 3. 服务成就页

- [ ] 3.1 新建 `blindRun/Volunteer/VolunteerServiceRecognition.swift`：
      纯数据类型 `ServiceRecognitionTier`（5 档，见 D2），
      纯函数 `tiers(completedCount:) -> [(tier, isUnlocked, remaining)]`。
      **不 import SwiftUI**，保证可单测。
- [ ] 3.2 改写 `VolunteerOrderFlowViews.swift:1700-1788` 的 `VolunteerPointsPlaceholderView`
      为 `VolunteerServiceRecognitionView`：
      - 删掉 `VolunteerPointsViewModel` 整个类（死代码，只有一个从不赋值的 `errorMessage`）
      - 头部显示真实完成单数 + 当前档位
      - 5 档列表，每档带**档位名文字 + 独立 SF Symbol + 颜色**（D3：颜色不得是唯一指示）
      - 未解锁档位写「还差 N 单解锁」，不只是置灰
      - `accessibilityLabel` 给完整语义（「金牌陪跑员，已解锁」/「荣誉陪跑员，还差 43 单解锁」）
      - 页面无自己的网络请求与状态，`dispatchSummary` 由调用方传入（D4）
- [ ] 3.3 更新调用点的导航与页面标题（「积分商城」→「服务成就」）。

## 4. 规格

- [ ] 4.1 MODIFIED `openspec/specs/system-dispatch-flow/spec.md` 的
      **Requirement: Volunteer statistics and temporary points are displayed**——
      本变更的 spec delta 已写好，归档时生效。确认无其它未归档变更改同一条
      （2026-08-13 已核：零命中）。

## 5. 测试

- [ ] 5.1 `blindRunTests/VolunteerServiceRecognitionTests.swift`（纯单测）：
      - `completedCount = 0` → 全部未解锁，第一档提示「还差 1 单」
      - 边界值 1 / 9 / 10 / 24 / 25 / 49 / 50 / 99 / 100 / 101 各自解锁到哪一档
      - `totalCompleted == nil` 时按 0 处理，不崩
- [ ] 5.2 加一条回归断言：`VolunteerDispatchSummaryResponse` 解码一份**不含** `pointsBalance`
      的真实响应后，全仓不再有任何地方产出「完成数×100」这个值。
- [ ] 5.3 全仓字符串检查：发布产物里不再出现「积分商城」「+100 积分」「敬请期待」。
      按 `AGENTS.md` §1.1 考虑落成 `scripts/hooks/guard.mjs` 一条守卫
      （拦「敬请期待」这类占位承诺文案）。
- [ ] 5.4 跑收窄范围的真机测试（本变更不碰全局单例，不需要全量）：
      ```bash
      scripts/device-test.sh -only-testing:blindRunTests/VolunteerServiceRecognitionTests \
                             -only-testing:blindRunTests/blindRunTests
      ```
      ⚠️ `blindRunTests.swift:1048-1049` 与 `:4730-4731` 现在断言的是
      `resolvedPointsBalance == 100 / 200`，**这两处会红，是预期内的**——
      它们正是本变更要撤掉的行为，改成断言完成单数。
      `passed=0` 一律当失败查。

## 6. 收尾

- [ ] 6.1 真机 `111` 上开 VoiceOver 走一遍成就页：遍历顺序、每档 label 语义完整、
      未解锁档位听得出「还差几单」。低视力档位（AX3 以上字号 + 深色模式）看一眼不裁切。
- [ ] 6.2 按 skill `aidrun-ship-check` 输出验证结论，贴真实测试输出。
- [ ] 6.3 同步 handoff（第 1 节三条），commit，push，开 PR。
