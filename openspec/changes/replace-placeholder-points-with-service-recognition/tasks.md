# Tasks

## 1. 契约投递（与实现并行）

- [ ] 1.1 投 handoff「待后端确认」：要不要做真的积分体系？要的话给出产生规则、
      有没有兑换出口、会不会过期。注明前端已撤掉假实现，**不阻塞**后端将来做真的。
- [ ] 1.2 投 handoff：完成单数多的志愿者要不要在派单里加权（滴滴「点亮勋章后接单概率增加」）？
      这决定成就体系是纯荣誉还是有实际收益，会影响前端文案措辞。
- [ ] 1.3 投 handoff：`dispatch-summary` 能否补**累计服务时长**？按小时数分层是行业通行做法，
      我们缺这一维只能退用单数。

## 2. 删除假积分

- [x] 2.1 `VolunteerDispatchSummaryModels.swift`：删 `pointsBalance` 字段与 `resolvedPointsBalance`；
      删 `resolvedPointsDelta` 的 `+100` 兜底，`pointsText` 改为 `String?`（`nil` 时整行不显示），
      **保留 `pointsDelta` 字段本身**（见 D6）。
- [x] 2.2 `VolunteerHomeView.swift`：四格改三格（不补第四格凑数）；
      `accessibilityLabel` 里的「积分 N」同步删——**这条最容易漏，视觉上没了但读屏还在念**；
      入口图标 `gift` → `rosette`，标题「积分」→「成就」，label/hint 同步。
      最近订单卡的积分行改为「后端真发了才显示」。
- [x] 2.3 `VolunteerOrderFlowViews.swift`：删 `VolunteerServiceRecord.pointsText`（恒为「+100 积分」）
      及其在 accessibility label 里的引用；服务记录卡里那行积分整行删掉。
      `.completed` 的描述文案由「服务完成，获得 +100 积分」改为「服务完成，感谢你的陪伴」——
      **不是只删**：这是志愿者跑完一趟唯一的正反馈，把假承诺删掉不该连正反馈一起删掉，
      一句感谢不涉及任何数字且是真的。
- [x] 2.4 `MockAPIClient.swift`：`pointsDelta` 改 `nil`，删 `pointsBalance` 传参。
      Mock 造出后端不存在的字段值会让 Mock 环境的 UI 与真实环境长得不一样，而 UI 是照着 Mock 调的。

## 3. 服务成就页

- [x] 3.1 新建 `blindRun/Volunteer/VolunteerServiceRecognition.swift`：
      `ServiceRecognitionTier`（5 档，见 D2）、`ServiceRecognitionProgress`、
      `progress(completedCount:)` / `currentTier` / `nextTierRemaining` / `summarySpeech`。
      **不 import SwiftUI**，保证可单测。
- [x] 3.2 `VolunteerPointsPlaceholderView` → `VolunteerServiceRecognitionView`：
      删掉 `VolunteerPointsViewModel` 整个类（死代码）；头部是真实完成单数 + 当前称号；
      5 档列表每档带档位名 + 独立 SF Symbol + 状态文字（颜色不是唯一指示）；
      未解锁写「还差 N 单」；`accessibilityLabel` 给完整语义；
      页面无自己的网络请求与状态，`dispatchSummary` 由调用方传入。
- [x] 3.3 调用点导航与标题更新（「积分商城」→「服务成就」）。

## 4. 规格

- [ ] 4.1 MODIFIED `openspec/specs/system-dispatch-flow/spec.md` 的
      **Requirement: Volunteer statistics and temporary points are displayed**——
      本变更的 spec delta 已写好，归档时生效。确认无其它未归档变更改同一条
      （2026-08-13 已核：零命中）。

## 5. 测试

- [x] 5.1 `blindRunTests/VolunteerServiceRecognitionTests.swift`（纯单测，12 条）：
      边界值 0/1/9/10/24/25/49/50/99/100/101 逐个钉解锁档数与当前称号；
      已解锁档 `remaining == 0`；负数按 0 处理；每档靠名称与图标可区分（非颜色）；
      未解锁 label 说清还差几单；播报不出现「积分」「兑换」。
- [x] 5.2 回归断言：`pointsDelta` 为 `null` 时 `pointsText` 为 `nil`（不再编「+100」）；
      后端真发时如实显示；`VolunteerDispatchSummaryResponse` 解码一份**含** `pointsBalance`
      的 JSON 时该键被忽略，成就页仍只用 `completedCount`。
      同时改掉 `blindRunTests.swift` 两处断言 `resolvedPointsBalance == 100 / 200` 的旧用例
      —— 它们钉住的正是本变更要撤掉的合成值。
- [x] 5.3 **落成守卫**（`AGENTS.md` §1.1）：`guard.mjs` 新增 `placeholder-promise`，
      拦出货代码里的「敬请期待 / 即将上线 / 敬请关注」。占位 UI 本身不禁，
      拦的是「会兑现」的暗示。全仓复扫确认零误伤，`validate-guard.mjs` 加 3 条正反用例
      （并带上 post 模式 runner —— 内容级规则要从磁盘读真实文件，此前 runner 只跑 `pre`）。
      `node scripts/validate-guard.mjs` → 31 条全过。
- [x] 5.4 跑收窄范围的真机测试（范围按符号搜 `blindRunTests` 定；本变更不碰全局单例）：
      ```bash
      scripts/device-test.sh -only-testing:blindRunTests/VolunteerServiceRecognitionTests \
                             -only-testing:blindRunTests/blindRunTests \
                             -only-testing:blindRunTests/OrderEnumLeniencyDecodingTests
      ```
      **`passed=311 failed=0 skipped=0 result=Passed`**（iPhone 16 Pro）。
      逐 suite 核过日志确认不是零执行：`VolunteerServiceRecognitionTests` 12 条
      （逐条 passed）、`blindRunTests` 281 条、`OrderEnumLeniencyDecodingTests` 17 条。
      `blindRunTests` 全绿说明改掉的那两处旧断言（`resolvedPointsBalance == 100 / 200`）
      没有连累同套件的其它用例。

## 6. 收尾

- [ ] 6.1 真机 `111` 上开 VoiceOver 走一遍成就页：遍历顺序、每档 label 语义完整、
      未解锁档位听得出「还差几单」。低视力档位（AX3 以上字号 + 深色模式）看一眼不裁切。
- [ ] 6.2 按 skill `aidrun-ship-check` 输出验证结论，贴真实测试输出。
- [ ] 6.3 同步 handoff（第 1 节三条），commit，push，开 PR。
